// The words a seed is shown as. The set states them in `docs/Montana Canon.md`, "The birth of a
// seed": twenty-four words of eleven bits each carry the entropy and one checksum byte, over a
// list of 2 048 lowercase words sorted lexicographically and fixed by its fingerprint. The list
// travels with this tree and is bound by that fingerprint, which the conformance harness parses
// out of the set — a list of the right shape and the wrong contents fails the build.
//
// The shape is BIP-39 and the key is not: what the master seed stretches is the entropy under
// the seed domain, never the text of the words.

use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

mt_codec::constants! {
    WORD_SHAPE:
    pub const WORDS: usize = 24, spells "The seed is shown to its holder as twenty-four words";
    pub const LIST_SIZE: usize = 2_048, writes "The canonical list holds 2 048 words";
    pub const BITS_PER_WORD: usize = 11, writes "`bits_per_word` = 11 bits a word";
    pub const PREFIX: usize = 4, spells "Four letters name one word";
}

const LIST_RAW: &str = include_str!("../wordlist.txt");

#[derive(Debug, PartialEq, Eq)]
pub enum WordsError {
    WrongCount { count: usize },
    UnknownWord { position: usize },
    ChecksumMismatch,
    AmbiguousPrefix { position: usize },
}

pub fn list() -> &'static [&'static str] {
    static CACHE: std::sync::OnceLock<Vec<&'static str>> = std::sync::OnceLock::new();
    CACHE.get_or_init(|| LIST_RAW.lines().collect())
}

// The fingerprint of the list: every word followed by one newline, hashed bare. The string
// carries no domain and separates nothing, so the NUL of the primitive has no place here.
pub fn fingerprint() -> [u8; 32] {
    let mut h = Sha256::new();
    for word in list() {
        h.update(word.as_bytes());
        h.update([0x0A]);
    }
    h.finalize().into()
}

pub fn checksum(entropy: &[u8; 32]) -> u8 {
    Sha256::digest(entropy)[0]
}

// The 264 bits of entropy and checksum, most significant bit first, in groups of eleven.
pub fn indices(entropy: &[u8; 32]) -> [u16; WORDS] {
    let mut bits = [0u8; 33];
    bits[..32].copy_from_slice(entropy);
    bits[32] = checksum(entropy);
    let mut out = [0u16; WORDS];
    for (word, slot) in out.iter_mut().enumerate() {
        let mut value = 0u16;
        for bit in 0..BITS_PER_WORD {
            let position = word * BITS_PER_WORD + bit;
            let byte = bits[position >> 3];
            let taken = (byte >> (7 - (position & 7))) & 1;
            value = (value << 1) | u16::from(taken);
        }
        *slot = value;
    }
    out
}

// The phrase: the words of those indices joined by single spaces and by nothing else.
pub fn phrase(entropy: &[u8; 32]) -> Zeroizing<String> {
    let words = list();
    let mut out = String::with_capacity(WORDS * 9);
    for (i, index) in indices(entropy).iter().enumerate() {
        if i > 0 {
            out.push(' ');
        }
        out.push_str(words[usize::from(*index)]);
    }
    Zeroizing::new(out)
}

// The first four letters of a word, or the whole of a word shorter than that: this is what the
// set means by four letters naming one word, and it is unique across the list.
pub fn head(word: &str) -> &str {
    match word.char_indices().nth(PREFIX) {
        Some((at, _)) => &word[..at],
        None => word,
    }
}

// Four letters name one word, and case carries nothing: a written phrase resolves to exactly
// one reading or to none. A form shorter than four letters is refused as ambiguous unless it is
// a whole word of the list, and a form that no word begins with is a stranger rather than a
// word to guess at.
fn resolve(written: &str, position: usize) -> Result<u16, WordsError> {
    // What is folded here is a word of somebody's phrase: it is wiped when this frame ends rather
    // than left in the memory the allocator hands to the next thing that asks.
    let lowered = Zeroizing::new(written.to_ascii_lowercase());
    let words = list();
    if let Some(index) = words.iter().position(|w| **w == *lowered) {
        return Ok(index as u16);
    }
    if lowered.len() < PREFIX {
        return Err(WordsError::AmbiguousPrefix { position });
    }
    let mut found = None;
    for (index, word) in words.iter().enumerate() {
        if word.starts_with(lowered.as_str()) {
            if found.is_some() {
                return Err(WordsError::AmbiguousPrefix { position });
            }
            found = Some(index as u16);
        }
    }
    found.ok_or(WordsError::UnknownWord { position })
}

pub fn entropy_of(written: &str) -> Result<Zeroizing<[u8; 32]>, WordsError> {
    let spoken: Vec<&str> = written.split_whitespace().collect();
    if spoken.len() != WORDS {
        return Err(WordsError::WrongCount {
            count: spoken.len(),
        });
    }
    let mut bits = Zeroizing::new([0u8; 33]);
    for (position, word) in spoken.iter().enumerate() {
        let index = resolve(word, position)?;
        for bit in 0..BITS_PER_WORD {
            let taken = (index >> (BITS_PER_WORD - 1 - bit)) & 1;
            if taken == 1 {
                let at = position * BITS_PER_WORD + bit;
                bits[at >> 3] |= 1 << (7 - (at & 7));
            }
        }
    }
    let mut entropy = Zeroizing::new([0u8; 32]);
    entropy.copy_from_slice(&bits[..32]);
    if bits[32] != checksum(&entropy) {
        return Err(WordsError::ChecksumMismatch);
    }
    Ok(entropy)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn the_list_is_the_shape_the_set_states() {
        let words = list();
        assert_eq!(words.len(), LIST_SIZE);
        for pair in words.windows(2) {
            assert!(pair[0] < pair[1], "{} then {}", pair[0], pair[1]);
        }
        for word in words {
            assert!(word.bytes().all(|b| b.is_ascii_lowercase()), "{word}");
            assert!(!word.is_empty(), "an empty line stands in the list");
        }
    }

    #[test]
    fn four_letters_name_one_word() {
        // A word shorter than four letters is its own head, and no longer word begins with it
        // and stops there — which is what makes the truncation unique across the whole list.
        let mut heads: Vec<&str> = list().iter().map(|w| head(w)).collect();
        let before = heads.len();
        heads.sort_unstable();
        heads.dedup();
        assert_eq!(before, heads.len());
    }

    #[test]
    fn the_fingerprint_is_the_one_the_set_holds() {
        // Canon, "The birth of a seed": the fingerprint of the canonical list.
        assert_eq!(
            hex(&fingerprint()),
            "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"
        );
    }

    #[test]
    fn the_phrase_of_a_zero_entropy_is_the_frozen_one() {
        // Canon, "The birth of a seed, end to end": the words joined by single spaces.
        let entropy = [0u8; 32];
        let spoken = phrase(&entropy);
        assert_eq!(spoken.split(' ').count(), WORDS);
        assert_eq!(
            hex(&sha2::Sha256::digest(spoken.as_bytes())),
            "69be79ef3c28f55d7cb84db2dd3c18dfff45eeefebd09b8c5f7f3489b8ba09ac"
        );
    }

    #[test]
    fn a_phrase_returns_the_entropy_it_was_written_from() {
        let mut entropy = [0u8; 32];
        for (i, b) in entropy.iter_mut().enumerate() {
            *b = (i as u8).wrapping_mul(37).wrapping_add(11);
        }
        let spoken = phrase(&entropy);
        assert_eq!(
            entropy_of(&spoken).expect("the phrase reads back")[..],
            entropy[..]
        );
    }

    #[test]
    fn case_and_spacing_carry_nothing_and_four_letters_suffice() {
        let entropy = [0x5Au8; 32];
        let spoken = phrase(&entropy);
        let shouted = spoken.to_uppercase();
        let spaced = spoken.split(' ').collect::<Vec<_>>().join("   ");
        let shortened: String = spoken.split(' ').map(head).collect::<Vec<_>>().join(" ");
        for written in [shouted, spaced, shortened] {
            assert_eq!(entropy_of(&written).expect("resolves")[..], entropy[..]);
        }
    }

    #[test]
    fn a_short_prefix_is_refused_rather_than_guessed() {
        let entropy = [0u8; 32];
        let spoken = phrase(&entropy);
        // Cut to three letters, "abandon" becomes no word of the list and names none.
        let truncated: String = spoken
            .split(' ')
            .map(|w| match w.char_indices().nth(3) {
                Some((at, _)) => &w[..at],
                None => w,
            })
            .collect::<Vec<_>>()
            .join(" ");
        assert_eq!(
            entropy_of(&truncated),
            Err(WordsError::AmbiguousPrefix { position: 0 })
        );
    }

    #[test]
    fn the_head_of_a_word_never_cuts_a_letter_in_half() {
        // A public function takes what a caller hands it, and a person may type anything.
        assert_eq!(head("abandon"), "aban");
        assert_eq!(head("art"), "art");
        assert_eq!(head(""), "");
        assert_eq!(head("aaaé"), "aaaé");
        assert_eq!(head("ааааа"), "аааа");
    }

    #[test]
    fn a_bad_checksum_a_wrong_count_and_a_stranger_are_each_refused() {
        let entropy = [0u8; 32];
        let spoken = phrase(&entropy);
        let mut words: Vec<&str> = spoken.split(' ').collect();
        // The last word carries the checksum byte, so replacing it breaks the check.
        let last = words.len() - 1;
        words[last] = if words[last] == "art" { "zoo" } else { "art" };
        assert_eq!(
            entropy_of(&words.join(" ")),
            Err(WordsError::ChecksumMismatch)
        );
        assert_eq!(
            entropy_of("abandon abandon"),
            Err(WordsError::WrongCount { count: 2 })
        );
        let mut stranger: Vec<&str> = spoken.split(' ').collect();
        stranger[5] = "qqqqq";
        assert_eq!(
            entropy_of(&stranger.join(" ")),
            Err(WordsError::UnknownWord { position: 5 })
        );
    }

    #[test]
    fn every_entropy_round_trips_through_its_phrase() {
        // xorshift64*, seeded once: the same run on every machine.
        let mut state = 0x4D54_2D53_4545_4431u64;
        let mut next = || {
            state ^= state >> 12;
            state ^= state << 25;
            state ^= state >> 27;
            state.wrapping_mul(0x2545_F491_4F6C_DD1D)
        };
        for _ in 0..500 {
            let mut entropy = [0u8; 32];
            for b in entropy.iter_mut() {
                *b = next() as u8;
            }
            let spoken = phrase(&entropy);
            assert_eq!(entropy_of(&spoken).expect("round trips")[..], entropy[..]);
        }
    }
}
