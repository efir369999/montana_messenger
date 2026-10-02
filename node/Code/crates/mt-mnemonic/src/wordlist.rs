// spec, раздел "Ключи → Мнемоника и seed → Каноническая wordlist"

use std::sync::OnceLock;

use crate::{sha256_raw, Hash32};

const WORDLIST_RAW: &str = include_str!("../../../../Montana wordlist.txt");

pub const WORDLIST_SIZE: usize = 2048;

// Binding fingerprint of the canonical list: SHA-256 over `Montana wordlist.txt`
// in canonical encoding = concat(word_i || 0x0A) for i ∈ [0, 2047].
pub const WORDLIST_FINGERPRINT: Hash32 = [
    0x2f, 0x5e, 0xed, 0x53, 0xa4, 0x72, 0x7b, 0x4b, 0xf8, 0x88, 0x0d, 0x8f, 0x3f, 0x19, 0x9e, 0xfc,
    0x90, 0xe5, 0x85, 0x03, 0x64, 0x6d, 0x9f, 0xf8, 0xef, 0xf3, 0xa2, 0xed, 0x3b, 0x24, 0xdb, 0xda,
];

pub fn wordlist() -> &'static [&'static str; WORDLIST_SIZE] {
    static CACHE: OnceLock<[&'static str; WORDLIST_SIZE]> = OnceLock::new();
    CACHE.get_or_init(init_wordlist)
}

fn init_wordlist() -> [&'static str; WORDLIST_SIZE] {
    let computed = sha256_raw(WORDLIST_RAW.as_bytes());
    // Несовпадение = corruption встроенного wordlist либо wrong file.
    // Protocol violation, не runtime error.
    assert_eq!(
        computed, WORDLIST_FINGERPRINT,
        "Montana wordlist fingerprint mismatch — встроенный wordlist повреждён или заменён"
    );

    let mut arr: [&'static str; WORDLIST_SIZE] = [""; WORDLIST_SIZE];
    let mut count = 0;
    for line in WORDLIST_RAW.lines() {
        assert!(
            count < WORDLIST_SIZE,
            "wordlist has more than {WORDLIST_SIZE} lines"
        );
        arr[count] = line;
        count += 1;
    }
    assert_eq!(
        count, WORDLIST_SIZE,
        "wordlist does not have exactly {WORDLIST_SIZE} lines"
    );

    for i in 1..WORDLIST_SIZE {
        assert!(
            arr[i - 1] < arr[i],
            "wordlist not lexicographically sorted at position {i}"
        );
    }

    arr
}

// Shortest unambiguous entry: the canonical list keeps the first four letters of
// every word distinct, so four characters already name one word.
pub const MIN_PREFIX_CHARS: usize = 4;

// The whole list is walked for every lookup and no comparison exits early: the
// time of a lookup does not tell which word was entered, only that a lookup
// happened. Case is folded and a four-letter prefix is accepted, so a phrase
// carried through a password manager or written by hand still opens the account.
pub fn word_index(word: &str) -> Option<u16> {
    let words = wordlist();
    let input = word.as_bytes();

    let mut exact_idx: u32 = 0;
    let mut exact_found: u8 = 0;
    let mut prefix_idx: u32 = 0;
    let mut prefix_hits: u32 = 0;

    for (i, w) in words.iter().enumerate() {
        let candidate = w.as_bytes();
        let is_prefix = ct_is_prefix(candidate, input);
        let same_len = u8::from(candidate.len() == input.len());
        let is_exact = is_prefix & same_len;

        let m_exact = 0u32.wrapping_sub(is_exact as u32);
        exact_idx = (exact_idx & !m_exact) | ((i as u32) & m_exact);
        exact_found |= is_exact;

        let m_prefix = 0u32.wrapping_sub(is_prefix as u32);
        prefix_idx = (prefix_idx & !m_prefix) | ((i as u32) & m_prefix);
        prefix_hits += is_prefix as u32;
    }

    if exact_found == 1 {
        return Some(exact_idx as u16);
    }
    if input.len() >= MIN_PREFIX_CHARS && prefix_hits == 1 {
        return Some(prefix_idx as u16);
    }
    None
}

// Lengths are public — they are visible in the shape of what was typed. Only the
// content of the comparison is kept out of the timing.
fn ct_is_prefix(candidate: &[u8], input: &[u8]) -> u8 {
    if input.is_empty() || input.len() > candidate.len() {
        return 0;
    }
    let mut diff = 0u8;
    for i in 0..input.len() {
        diff |= candidate[i] ^ input[i].to_ascii_lowercase();
    }
    ct_is_zero(diff)
}

fn ct_is_zero(x: u8) -> u8 {
    (((x as u32).wrapping_sub(1)) >> 31) as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fingerprint_matches_spec() {
        let computed = sha256_raw(WORDLIST_RAW.as_bytes());
        assert_eq!(computed, WORDLIST_FINGERPRINT);
    }

    #[test]
    fn first_word_abandon() {
        let wl = wordlist();
        assert_eq!(wl[0], "abandon");
    }

    #[test]
    fn second_word_ability() {
        let wl = wordlist();
        assert_eq!(wl[1], "ability");
    }

    #[test]
    fn last_word_zoo() {
        let wl = wordlist();
        assert_eq!(wl[2047], "zoo");
    }

    #[test]
    fn exactly_2048_words() {
        let wl = wordlist();
        assert_eq!(wl.len(), 2048);
    }

    #[test]
    fn all_lowercase_ascii() {
        let wl = wordlist();
        for (i, w) in wl.iter().enumerate() {
            assert!(
                w.bytes().all(|b| b.is_ascii_lowercase()),
                "word {i} ({w}) has non-lowercase-ASCII bytes"
            );
        }
    }

    #[test]
    fn lexicographically_sorted() {
        let wl = wordlist();
        for i in 1..WORDLIST_SIZE {
            assert!(wl[i - 1] < wl[i]);
        }
    }

    #[test]
    fn word_index_abandon_is_zero() {
        assert_eq!(word_index("abandon"), Some(0));
    }

    #[test]
    fn word_index_zoo_is_2047() {
        assert_eq!(word_index("zoo"), Some(2047));
    }

    #[test]
    fn word_index_unknown_returns_none() {
        assert_eq!(word_index("notaword"), None);
        assert_eq!(word_index(""), None);
    }

    #[test]
    fn word_index_is_case_insensitive() {
        assert_eq!(word_index("Abandon"), Some(0));
        assert_eq!(word_index("ABANDON"), Some(0));
        assert_eq!(word_index("ZoO"), Some(2047));
    }

    #[test]
    fn word_index_accepts_four_letter_prefix() {
        assert_eq!(word_index("aban"), Some(0));
        assert_eq!(word_index("Aban"), Some(0));
        assert_eq!(word_index("abando"), Some(0));
    }

    #[test]
    fn word_index_refuses_prefix_shorter_than_four() {
        assert_eq!(word_index("aba"), None);
        assert_eq!(word_index("z"), None);
    }

    #[test]
    fn four_letter_prefixes_are_unique_across_the_list() {
        // Основание для MIN_PREFIX_CHARS: четырёх букв достаточно, чтобы назвать
        // ровно одно слово канонического списка.
        let wl = wordlist();
        let mut prefixes: Vec<&str> = wl
            .iter()
            .map(|w| {
                if w.len() >= MIN_PREFIX_CHARS {
                    &w[..MIN_PREFIX_CHARS]
                } else {
                    w
                }
            })
            .collect();
        prefixes.sort_unstable();
        let before = prefixes.len();
        prefixes.dedup();
        assert_eq!(before, prefixes.len(), "four-letter prefixes collide");
    }

    #[test]
    fn every_word_resolves_to_its_own_index() {
        let wl = wordlist();
        for (i, w) in wl.iter().enumerate() {
            assert_eq!(word_index(w), Some(i as u16), "word {i} ({w})");
        }
    }

    #[test]
    fn ct_is_zero_matches_its_contract() {
        assert_eq!(ct_is_zero(0), 1);
        for x in 1u8..=255 {
            assert_eq!(ct_is_zero(x), 0, "x = {x}");
        }
    }
}
