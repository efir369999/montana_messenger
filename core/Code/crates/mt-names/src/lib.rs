//! Montana Names -- the names layer. Pure functions: no network, no state, no time.
//! Source of the rules: "Montana Names", sections IV (objects), VII (normalisation), VIII (constants).

#![forbid(unsafe_code)]

use caseless::default_case_fold_str;
use unicode_normalization::UnicodeNormalization;

pub const NAME_MIN_LEN: usize = 4;
pub const NAME_MAX_LEN: usize = 32;

/// Why the name was not accepted. The refusal names the reason: the person is shown it verbatim.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum NameError {
    TooShort,
    TooLong,
    NotStartingWithLetter,
    EndsWithSign,
    DoubleSign,
    Empty,
    /// A character outside the set `[a-z0-9_-]` after NFKC and casefold.
    Charset,
}

/// Normalisation (section VII), eight consecutive steps:
/// 1. NFKC; 2. full casefold; 3. strip a leading `@`; 4. the set `[a-z0-9_-]`;
/// 5. length NAME_MIN_LEN..NAME_MAX_LEN; 6. starts with a letter;
/// 7. does not end with `_` or `-`; 8. two consecutive special characters are forbidden.
///
/// Steps 1-2 exist so that the same input yields the same result on every
/// platform: "Ａ" and "A" are one name, "straße" and "strasse" are one name. Without this the layer splits.
pub fn normalize(input: &str) -> Result<String, NameError> {
    // Exactly the eight spec steps and none of our own. Whitespace trimming IS NOT INCLUDED: it is absent from
    // section VII, and a foreign implementation would reject "  alice  ", which we would accept -- that is a split
    // of the layer. The client trims whitespace before the call.
    let folded = default_case_fold_str(&input.nfkc().collect::<String>());
    let stripped = folded.strip_prefix('@').unwrap_or(&folded);
    // A character outside the set is a REFUSAL, not a drop. Silently dropping would give the person
    // a DIFFERENT name than the one typed: "alicé" would become "alic" and they would not notice.
    if stripped.is_empty() {
        return Err(NameError::Empty);
    }
    if !stripped
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
    {
        return Err(NameError::Charset);
    }
    let kept = stripped.to_string();

    // Length is in normalised BYTES (section VII, step 5). The set is already checked, all characters are ASCII,
    // so bytes and characters coincide by construction.
    if kept.len() < NAME_MIN_LEN {
        return Err(NameError::TooShort);
    }
    if kept.len() > NAME_MAX_LEN {
        return Err(NameError::TooLong);
    }
    if !kept.chars().next().is_some_and(|c| c.is_ascii_lowercase()) {
        return Err(NameError::NotStartingWithLetter);
    }
    if kept.ends_with('_') || kept.ends_with('-') {
        return Err(NameError::EndsWithSign);
    }
    for pair in ["__", "--", "_-", "-_"] {
        if kept.contains(pair) {
            return Err(NameError::DoubleSign);
        }
    }
    Ok(kept)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Acceptance table of step A-1: input → expected outcome. Each row guards one rule.
    #[test]
    fn normalization_table() {
        let max_name = "a".repeat(NAME_MAX_LEN);
        let too_long = "a".repeat(NAME_MAX_LEN + 1);
        let ok: &[(&str, &str)] = &[
            ("alice", "alice"),
            ("@alice", "alice"),
            ("Alice", "alice"),
            ("ALICEMONTANA", "alicemontana"),
            ("alice_montana", "alice_montana"),
            ("alice-montana", "alice-montana"),
            ("a1ice", "a1ice"),
            ("ａｌｉｃｅ", "alice"), // fullwidth → NFKC
            ("ＡＬＩＣＥ", "alice"), // fullwidth + casefold
            ("straße", "strasse"),   // full casefold: ß → ss
            (max_name.as_str(), max_name.as_str()),
            ("ab_cd", "ab_cd"),
            ("ab-cd", "ab-cd"),
            ("a1_b2-c3", "a1_b2-c3"),
        ];
        for (input, want) in ok {
            assert_eq!(normalize(input).as_deref(), Ok(*want), "input {input:?}");
        }

        let bad: &[(&str, NameError)] = &[
            ("", NameError::Empty),
            ("🙂🙂", NameError::Charset),
            ("ALIÇE", NameError::Charset), // ç is outside the set -- a refusal, not a name substitution
            ("alice🙂", NameError::Charset),
            ("алиса-alice", NameError::Charset),
            ("alice montana", NameError::Charset), // space inside
            ("  alice  ", NameError::Charset),     // trimming is the client's job, not the layer's
            ("alice.montana", NameError::Charset),
            ("alice@montana", NameError::Charset), // only a leading @ is stripped
            ("abc", NameError::TooShort),
            ("@abc", NameError::TooShort),
            (too_long.as_str(), NameError::TooLong),
            ("1alice", NameError::NotStartingWithLetter),
            ("_alice", NameError::NotStartingWithLetter),
            ("-alice", NameError::NotStartingWithLetter),
            ("alice_", NameError::EndsWithSign),
            ("alice-", NameError::EndsWithSign),
            ("al__ice", NameError::DoubleSign),
            ("al--ice", NameError::DoubleSign),
            ("al_-ice", NameError::DoubleSign),
            ("al-_ice", NameError::DoubleSign),
        ];
        for (input, want) in bad {
            assert_eq!(normalize(input), Err(*want), "input {input:?}");
        }
    }

    /// Normalisation is idempotent: a result fed in again does not change.
    #[test]
    fn normalization_is_idempotent() {
        for input in ["Alice", "ａｌｉｃｅ", "straße", "@ALICE_montana"] {
            let once = normalize(input).unwrap();
            assert_eq!(normalize(&once).unwrap(), once, "input {input:?}");
        }
    }
}

/// Name slot (section IV): `slot = SHA-256("mt-name-slot" || 0x00 || normalized_name)`.
/// The name never reaches the chain -- only the slot does.
pub fn slot(normalized: &str) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-slot");
    h.update([0x00u8]);
    h.update(normalized.as_bytes());
    h.finalize().into()
}

#[cfg(test)]
mod slot_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// Frozen vectors of step A-2. The values were computed with this same composition and pinned:
    /// a divergence in a foreign implementation is caught here, not on the live network.
    #[test]
    fn slot_vectors() {
        // The values were computed by an INDEPENDENT implementation (python hashlib), not copied from ours:
        // a vector taken from our own code confirms only itself.
        for (name, want) in [
            (
                "alice",
                "b5793a0d4f7f0737ebffb1374d24d3eed05efef5bd63eb1e4b03d81652c2575e",
            ),
            (
                "alicemontana",
                "0d09230abe3641df7434050a5b99329b05c1f4c387dd9cd738843d4ac4672547",
            ),
            (
                "a1_b2-c3",
                "37bfee292d7a237a2c9d0f58448ca7df8a36476280ff91bd9f4ce5da32e7b406",
            ),
        ] {
            assert_eq!(hex(&slot(name)), want, "name {name:?}");
        }
    }

    /// The slot depends ONLY on the normalised name: different spellings of one name give one slot.
    #[test]
    fn slot_is_stable_across_writings() {
        let a = slot(&normalize("Alice").unwrap());
        let b = slot(&normalize("ａｌｉｃｅ").unwrap());
        let c = slot(&normalize("@ALICE").unwrap());
        assert_eq!(a, b);
        assert_eq!(a, c);
    }

    /// Different names give different slots (otherwise the layer would merge people).
    #[test]
    fn different_names_differ() {
        assert_ne!(slot("alice"), slot("alicf"));
    }
}

/// Length of the renewal chain (section VIII): 128 links of 6τ₂ each ≈ 29 years.
pub const NAME_CHAIN_LEN: usize = 128;

/// Far end of the chain (set): `HKDF-Expand(master_seed, "mt-name-own" || 0x00 || slot, 32)`.
/// The branch takes the SLOT, so two names of one holder give two chains that do not reduce
/// to each other. There is nowhere to store it and no need: it is derived from the seed phrase at any time.
pub fn name_own(master_seed: &[u8], slot: &[u8; 32]) -> [u8; 32] {
    let mut info = Vec::with_capacity(11 + 1 + 32);
    info.extend_from_slice(b"mt-name-own");
    info.push(0x00);
    info.extend_from_slice(slot);
    let v = mt_mnemonic::hkdf_expand(master_seed, &info, 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&v);
    out
}

/// Renewal chain (set). `link[N]` IS a branch of the seed, each previous link is the hash of
/// the next under the domain `mt-name-chain`, `anchor = link[0]`. The anchor is published and the links are opened one at a time:
/// knowing the link of step k does not give the link of step k+1, so renewal can be delegated without handing over
/// control of the name.
pub fn chain(name_own: &[u8; 32]) -> Vec<[u8; 32]> {
    use sha2::{Digest, Sha256};
    let mut links = vec![[0u8; 32]; NAME_CHAIN_LEN + 1];
    links[NAME_CHAIN_LEN] = *name_own;
    for i in (0..NAME_CHAIN_LEN).rev() {
        let mut h = Sha256::new();
        h.update(b"mt-name-chain");
        h.update([0x00u8]);
        h.update(links[i + 1]);
        links[i] = h.finalize().into();
    }
    links
}

/// Chain anchor -- its zeroth link.
pub fn anchor(chain: &[[u8; 32]]) -> [u8; 32] {
    chain[0]
}

/// Commitment (set): `SHA-256("mt-name-commit" || 0x00 || slot || blind || tip)`.
/// The batch assembler sees 32 opaque bytes: no name, no slot, no anchor.
pub fn commit(slot: &[u8; 32], blind: &[u8; 32], tip: &[u8; 32]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-commit");
    h.update([0x00u8]);
    h.update(slot);
    h.update(blind);
    h.update(tip);
    h.finalize().into()
}

/// Link check (set): `SHA-256("mt-name-chain" || 0x00 || link) == prev_link`.
pub fn verify_link(prev_link: &[u8; 32], link: &[u8; 32]) -> bool {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-chain");
    h.update([0x00u8]);
    h.update(link);
    let got: [u8; 32] = h.finalize().into();
    got == *prev_link
}

#[cfg(test)]
mod chain_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// The vector was computed by an independent HKDF-Expand implementation (python hmac), not taken from ours.
    #[test]
    fn name_own_vector() {
        let sl = slot("alicemontana");
        assert_eq!(
            hex(&name_own(&[0u8; 64], &sl)),
            "5fb0d57f205793cfce5517939cf30ed0562aba86f5d5adc81f2bd7ddb5b12ba4"
        );
    }

    #[test]
    fn chain_length_and_anchor() {
        let c = chain(&name_own(&[0u8; 64], &slot("alicemontana")));
        assert_eq!(c.len(), NAME_CHAIN_LEN + 1);
        assert_eq!(anchor(&c), c[0]);
    }

    /// Each previous link is the hash of the next. This is what makes the chain one-way.
    #[test]
    fn every_link_verifies_against_previous() {
        let c = chain(&name_own(&[7u8; 64], &slot("alicemontana")));
        for i in 0..NAME_CHAIN_LEN {
            assert!(verify_link(&c[i], &c[i + 1]), "link {i}");
        }
    }

    /// The reverse direction is impossible: a link does not verify against someone else's previous link.
    #[test]
    fn wrong_link_rejected() {
        let c = chain(&name_own(&[7u8; 64], &slot("alicemontana")));
        assert!(!verify_link(&c[0], &c[2]));
        assert!(!verify_link(&c[5], &c[5]));
    }

    /// The chain is deterministic: the same seed and the same name give the same chain.
    #[test]
    fn chain_is_deterministic() {
        let a = chain(&name_own(&[1u8; 64], &slot("alice")));
        let b = chain(&name_own(&[1u8; 64], &slot("alice")));
        assert_eq!(a, b);
    }

    /// Different names under one seed give different chains: the slot enters the seed branch.
    #[test]
    fn chain_binds_the_slot() {
        let seed = [1u8; 64];
        assert_ne!(
            chain(&name_own(&seed, &slot("alice"))),
            chain(&name_own(&seed, &slot("alicf")))
        );
    }

    #[test]
    fn commit_hides_everything() {
        let sl = slot("alice");
        let c = chain(&name_own(&[2u8; 64], &sl));
        let cm = commit(&sl, &[9u8; 32], &anchor(&c));
        // the commitment equals none of its inputs
        assert_ne!(cm, sl);
        assert_ne!(cm, anchor(&c));
        // and changes with any of them
        assert_ne!(cm, commit(&slot("alicf"), &anchor(&c), &[9u8; 32]));
        assert_ne!(cm, commit(&sl, &anchor(&c), &[8u8; 32]));
    }
}

/// Stretch iterations of the lookup key (section VIII). The same as in the derivation from the mnemonic.
/// Name contact key seed (set): `HKDF-Expand(master_seed, "mt-name-contact-key" || 0x00 || slot, 64)`.
/// The ML-KEM-768 pair is built from it, and its public key is what the name slot publishes. The secret
/// half never leaves the device, and the pair is built by the caller: it already has ML-KEM.
pub fn contact_seed(master_seed: &[u8], slot: &[u8; 32]) -> [u8; 64] {
    let mut info = Vec::with_capacity(19 + 1 + 32);
    info.extend_from_slice(b"mt-name-contact-key");
    info.push(0x00);
    info.extend_from_slice(slot);
    let v = mt_mnemonic::hkdf_expand(master_seed, &info, 64);
    let mut out = [0u8; 64];
    out.copy_from_slice(&v);
    out
}

/// First-contact tag (set): `SHA-256("mt-name-tag" || 0x00 || contact_root || W_8B_LE)[0..16]`.
/// It has the same shape as the tag of an ordinary pipe and its own domain -- so it does not collide with
/// a tag that stands on a secret held by two parties.
pub fn first_tag(contact_root: &[u8], window: u64) -> [u8; 16] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-tag");
    h.update([0x00u8]);
    h.update(contact_root);
    h.update(window.to_le_bytes());
    let full: [u8; 32] = h.finalize().into();
    let mut out = [0u8; 16];
    out.copy_from_slice(&full[..16]);
    out
}

/// First-message secret (set): `SHA-256("mt-name-first" || 0x00 || ss || contact_root || ct)`.
/// First contact is ONE encapsulation: a stranger encapsulates to the contact root,
/// the holder decapsulates, and the correspondence then continues under the ordinary tag. The root enters the derivation
/// so that two people writing to the same name do not arrive at one secret, and the ciphertext so that
/// two letters from one stranger do not either.
pub fn first_secret(ss: &[u8], contact_root: &[u8], ct: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-first");
    h.update([0x00u8]);
    h.update(ss);
    h.update(contact_root);
    h.update(ct);
    h.finalize().into()
}

pub const NAME_KDF_ITER: u32 = 1 << 20;
/// Number of zero bits in the sender puzzle (section VIII).
pub const NAME_PUZZLE_BITS: u32 = 20;

/// Lookup key (section VI): `PBKDF2-HMAC-SHA-256(password = normalized_name || eph_pk,
/// salt = slot, iterations = NAME_KDF_ITER, 32 B)`.
///
/// The stretching protects not storage -- there is none -- but the lookup: a postman that sees a
/// sealed request cannot learn by brute force which name was asked for.
pub fn req_key(normalized: &str, eph_pk: &[u8], slot: &[u8; 32]) -> [u8; 32] {
    req_key_iter(normalized, eph_pk, slot, NAME_KDF_ITER)
}

/// The same with an explicit iteration count -- ONLY for tests inside the crate. It does not leave the crate:
/// an open iteration parameter would sooner or later be called with a weak value, and the stretching,
/// which stands here to protect the lookup, would stop protecting.
fn req_key_iter(normalized: &str, eph_pk: &[u8], slot: &[u8; 32], iterations: u32) -> [u8; 32] {
    let mut password = normalized.as_bytes().to_vec();
    password.extend_from_slice(eph_pk);
    let v = mt_mnemonic::pbkdf2_hmac_sha256(&password, slot, iterations, 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&v);
    out
}

/// Sender puzzle (section V): `SHA-256("mt-name-puzzle" || 0x00 || slot || eph_pk || nonce)`.
pub fn puzzle(slot: &[u8; 32], eph_pk: &[u8], nonce: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-puzzle");
    h.update([0x00u8]);
    h.update(slot);
    h.update(eph_pk);
    h.update(nonce);
    h.finalize().into()
}

/// The puzzle is solved if the top `bits` bits of the hash are zero. The owner checks this with ONE hash and
/// only then spends the stretching: otherwise a stream of empty lookups would burn their CPU.
pub fn puzzle_ok(hash: &[u8; 32], bits: u32) -> bool {
    if bits > 256 {
        return false; // demanding more bits than the hash has is not "stricter", it is a caller error
    }
    let full = (bits / 8) as usize;
    let rest = bits % 8;
    if hash[..full].iter().any(|b| *b != 0) {
        return false;
    }
    if rest == 0 || full == hash.len() {
        return true;
    }
    hash[full] >> (8 - rest) == 0
}

#[cfg(test)]
mod request_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// Vectors computed with python hashlib.pbkdf2_hmac -- an independent implementation.
    #[test]
    fn req_key_vectors() {
        let eph: Vec<u8> = (0u8..32).collect();
        let sl = slot("alice");
        assert_eq!(
            hex(&req_key_iter("alice", &eph, &sl, 1024)),
            "e6374321d120fb63999005f1d4651eb7ce9399c7d1796c1ec1d2c47dddd0385b"
        );
    }

    /// The full 2²⁰ stretch is a separate run: it is slow by construction, and that is its job.
    #[test]
    fn req_key_full_iterations() {
        let eph: Vec<u8> = (0u8..32).collect();
        let sl = slot("alice");
        assert_eq!(
            hex(&req_key("alice", &eph, &sl)),
            "bb4b9c5906f55733826cf47381cfa3907aa1c510b677dcff6a85095c7fd427a6"
        );
    }

    /// The lookup key is bound to the NAME, the ephemeral key and the slot: change any one and the key changes.
    #[test]
    fn req_key_binds_all_three() {
        let eph: Vec<u8> = (0u8..32).collect();
        let other: Vec<u8> = (1u8..33).collect();
        let a = req_key_iter("alice", &eph, &slot("alice"), 64);
        assert_ne!(a, req_key_iter("alicf", &eph, &slot("alice"), 64));
        assert_ne!(a, req_key_iter("alice", &other, &slot("alice"), 64));
        assert_ne!(a, req_key_iter("alice", &eph, &slot("alicf"), 64));
    }

    #[test]
    fn puzzle_bits_check() {
        // exactly 20 zero bits: the first two bytes are zero, the third is < 0x10
        let mut h = [0u8; 32];
        h[2] = 0x0f;
        assert!(puzzle_ok(&h, 20));
        h[2] = 0x10;
        assert!(!puzzle_ok(&h, 20), "19 bits is not a solution");
        let zero = [0u8; 32];
        assert!(puzzle_ok(&zero, 20));
        assert!(puzzle_ok(&zero, 256));
        assert!(
            !puzzle_ok(&zero, 257),
            "more bits than the hash has is a caller error, not strictness"
        );
        let mut one = [0u8; 32];
        one[0] = 0x80;
        assert!(!puzzle_ok(&one, 1));
        assert!(puzzle_ok(&one, 0));
    }

    /// The puzzle is really solved by brute force and the solution is verified: low difficulty,
    /// so the test is fast, the mechanism is the same.
    #[test]
    fn puzzle_is_solvable_and_verifiable() {
        let sl = slot("alice");
        let eph: Vec<u8> = (0u8..32).collect();
        let bits = 12;
        let mut nonce = 0u64;
        let found = loop {
            let h = puzzle(&sl, &eph, &nonce.to_le_bytes());
            if puzzle_ok(&h, bits) {
                break nonce;
            }
            nonce += 1;
            assert!(nonce < 1 << 24, "no solution found -- the puzzle is broken");
        };
        assert!(puzzle_ok(&puzzle(&sl, &eph, &found.to_le_bytes()), bits));
        // another slot is not solved by the same nonce
        assert!(!puzzle_ok(
            &puzzle(&slot("alicf"), &eph, &found.to_le_bytes()),
            bits
        ));
    }
}

/// How many slots fall into one bucket (section VIII). Cover holds it from below, weight from above.
pub const NAME_BUCKET_TARGET: u64 = 256;

/// Slot bucket (section VI): the BUCKET is asked for as a whole, not the slot, otherwise the node learns
/// whom the asker is interested in.
///
/// `bits = max(0, ⌊log₂(occupied / NAME_BUCKET_TARGET)⌋)`, `bucket` is the top `bits` bits of the slot.
/// The occupied count is taken from the anchored index root, so everyone has the same one and there is no choice.
pub fn bucket_bits(occupied: u64) -> u32 {
    if occupied < NAME_BUCKET_TARGET {
        return 0;
    }
    (occupied / NAME_BUCKET_TARGET).ilog2()
}

/// Bucket as a number: the top `bits` bits of the slot, big-endian. With zero bits there is one bucket.
pub fn bucket(slot: &[u8; 32], occupied: u64) -> u64 {
    let bits = bucket_bits(occupied);
    if bits == 0 {
        return 0;
    }
    let mut top = 0u64;
    for b in &slot[..8] {
        top = (top << 8) | u64::from(*b);
    }
    top >> (64 - bits)
}

#[cfg(test)]
mod bucket_tests {
    use super::*;

    /// Acceptance table of step A-10: how many occupied → how many bucket bits.
    #[test]
    fn bucket_bits_table() {
        for (occupied, bits) in [
            (0u64, 0u32),
            (1, 0),
            (255, 0),
            (256, 0), // 256/256 = 1 → log2 = 0: still one bucket
            (511, 0),
            (512, 1), // two buckets
            (1023, 1),
            (1024, 2),
            (10_000, 5), // 10000/256 = 39 → log2 = 5
            (1_000_000, 11),
        ] {
            assert_eq!(bucket_bits(occupied), bits, "occupied {occupied}");
        }
    }

    /// Bucket size stays within [target, 2×target): this is the meaning of the formula.
    #[test]
    fn bucket_size_stays_in_band() {
        for occupied in [512u64, 1000, 4096, 100_000, 1_000_000, 10_000_000] {
            let buckets = 1u64 << bucket_bits(occupied);
            let per = occupied / buckets;
            assert!(
                (NAME_BUCKET_TARGET..2 * NAME_BUCKET_TARGET).contains(&per),
                "occupied {occupied}: in bucket {per}"
            );
        }
    }

    /// The bucket is a function of the slot and the occupied count ONLY: the asker has no choice.
    #[test]
    fn bucket_is_deterministic() {
        let s = slot("alice");
        assert_eq!(bucket(&s, 1_000_000), bucket(&s, 1_000_000));
    }

    /// The bucket fits within the number of buckets.
    #[test]
    fn bucket_within_range() {
        for occupied in [0u64, 512, 10_000, 1_000_000] {
            let n = 1u64 << bucket_bits(occupied);
            for name in ["alice", "alicemontana", "bobmontana", "carolmontana"] {
                assert!(
                    bucket(&slot(name), occupied) < n,
                    "name {name}, occupied {occupied}"
                );
            }
        }
    }
}

/// At most this many records in an answer (section VIII): a person publishes an email and a messenger under the name.
pub const NAME_ENTRY_MAX: usize = 2;
/// Answer ceiling in bytes (section VIII).
pub const NAME_ANSWER_MAX: usize = 8 * 1024;
/// Length of an ML-DSA-65 signature.
pub const SIG_LEN: usize = 3309;

/// Parsing failed. The reason is named: a silent refusal hides a format breakage.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ParseError {
    Truncated,
    BadVersion,
    TooManyEntries,
    BadLength,
    TooLarge,
}

/// Commitment (0x03): 32 opaque bytes and nothing else.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameCommit {
    pub commit: [u8; 32],
}

/// Reveal (0x03).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameReveal {
    pub slot: [u8; 32],
    pub anchor: [u8; 32],
    pub nonce: [u8; 32],
    pub commit_win: u32,
}

/// Renewal (0x03): the next chain link and its number.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameRenew {
    pub slot: [u8; 32],
    pub step: u32,
    pub link: [u8; 32],
}

/// One answer record: kind and value. A payment key is forbidden here ([I-2]).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameEntry {
    pub kind: u16,
    pub value: Vec<u8>,
    pub sig: Vec<u8>,
}

/// Owner answer (0x04). Stored nowhere: composed for every request.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameAnswer {
    pub entries: Vec<NameEntry>,
}

const V3: u8 = 0x03;
const V4: u8 = 0x04;

fn take<'a>(b: &mut &'a [u8], n: usize) -> Result<&'a [u8], ParseError> {
    if b.len() < n {
        return Err(ParseError::Truncated);
    }
    let (head, rest) = b.split_at(n);
    *b = rest;
    Ok(head)
}
fn take32(b: &mut &[u8]) -> Result<[u8; 32], ParseError> {
    let mut out = [0u8; 32];
    out.copy_from_slice(take(b, 32)?);
    Ok(out)
}
fn take_u32_le(b: &mut &[u8]) -> Result<u32, ParseError> {
    let mut out = [0u8; 4];
    out.copy_from_slice(take(b, 4)?);
    Ok(u32::from_le_bytes(out))
}
fn take_u16_le(b: &mut &[u8]) -> Result<u16, ParseError> {
    let mut out = [0u8; 2];
    out.copy_from_slice(take(b, 2)?);
    Ok(u16::from_le_bytes(out))
}

impl NameCommit {
    pub fn encode(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.commit);
        v
    }
    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let commit = take32(&mut b)?;
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self { commit })
    }
}

impl NameReveal {
    pub fn encode(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.slot);
        v.extend_from_slice(&self.anchor);
        v.extend_from_slice(&self.nonce);
        v.extend_from_slice(&self.commit_win.to_le_bytes());
        v
    }
    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let slot = take32(&mut b)?;
        let anchor = take32(&mut b)?;
        let nonce = take32(&mut b)?;
        let commit_win = take_u32_le(&mut b)?;
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self {
            slot,
            anchor,
            nonce,
            commit_win,
        })
    }
}

impl NameRenew {
    pub fn encode(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.slot);
        v.extend_from_slice(&self.step.to_le_bytes());
        v.extend_from_slice(&self.link);
        v
    }
    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let slot = take32(&mut b)?;
        let step = take_u32_le(&mut b)?;
        let link = take32(&mut b)?;
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self { slot, step, link })
    }
}

impl NameAnswer {
    pub fn encode(&self) -> Result<Vec<u8>, ParseError> {
        if self.entries.len() > NAME_ENTRY_MAX {
            return Err(ParseError::TooManyEntries);
        }
        let mut v = vec![V4, self.entries.len() as u8];
        for e in &self.entries {
            v.extend_from_slice(&e.kind.to_le_bytes());
            let len = u16::try_from(e.value.len()).map_err(|_| ParseError::BadLength)?;
            v.extend_from_slice(&len.to_le_bytes());
            v.extend_from_slice(&e.value);
        }
        for e in &self.entries {
            if e.sig.len() != SIG_LEN {
                return Err(ParseError::BadLength);
            }
            v.extend_from_slice(&e.sig);
        }
        if v.len() > NAME_ANSWER_MAX {
            return Err(ParseError::TooLarge);
        }
        Ok(v)
    }

    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if b.len() > NAME_ANSWER_MAX {
            return Err(ParseError::TooLarge); // the ceiling is a refusal, not truncation
        }
        if take(&mut b, 1)?[0] != V4 {
            return Err(ParseError::BadVersion);
        }
        let count = take(&mut b, 1)?[0] as usize;
        if count > NAME_ENTRY_MAX {
            return Err(ParseError::TooManyEntries);
        }
        let mut kinds = Vec::with_capacity(count);
        let mut values = Vec::with_capacity(count);
        for _ in 0..count {
            let kind = take_u16_le(&mut b)?;
            let len = take_u16_le(&mut b)? as usize;
            let value = take(&mut b, len)?.to_vec();
            kinds.push(kind);
            values.push(value);
        }
        let mut sigs = Vec::with_capacity(count);
        for _ in 0..count {
            sigs.push(take(&mut b, SIG_LEN)?.to_vec());
        }
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self {
            entries: (0..count)
                .map(|i| NameEntry {
                    kind: kinds[i],
                    value: values[i].clone(),
                    sig: sigs[i].clone(),
                })
                .collect(),
        })
    }
}

#[cfg(test)]
mod wire_tests {
    use super::*;

    fn answer(n: usize) -> NameAnswer {
        NameAnswer {
            entries: (0..n)
                .map(|i| NameEntry {
                    kind: 0x0001 + i as u16,
                    value: vec![0xAB; 40 + i],
                    sig: vec![0xCD; SIG_LEN],
                })
                .collect(),
        }
    }

    /// Round trip: encoded, parsed -- the same thing.
    #[test]
    fn round_trip_all_objects() {
        let c = NameCommit { commit: [1u8; 32] };
        assert_eq!(NameCommit::decode(&c.encode()), Ok(c.clone()));

        let r = NameReveal {
            slot: [2u8; 32],
            anchor: [3u8; 32],
            nonce: [4u8; 32],
            commit_win: 123_456,
        };
        assert_eq!(NameReveal::decode(&r.encode()), Ok(r.clone()));

        let n = NameRenew {
            slot: [5u8; 32],
            step: 7,
            link: [6u8; 32],
        };
        assert_eq!(NameRenew::decode(&n.encode()), Ok(n.clone()));

        for k in 0..=NAME_ENTRY_MAX {
            let a = answer(k);
            assert_eq!(
                NameAnswer::decode(&a.encode().unwrap()),
                Ok(a.clone()),
                "records {k}"
            );
        }
    }

    /// Field lengths are exactly per the spec.
    #[test]
    fn exact_lengths() {
        assert_eq!(NameCommit { commit: [0; 32] }.encode().len(), 1 + 32);
        assert_eq!(
            NameReveal {
                slot: [0; 32],
                anchor: [0; 32],
                nonce: [0; 32],
                commit_win: 0
            }
            .encode()
            .len(),
            1 + 32 + 32 + 32 + 4
        );
        assert_eq!(
            NameRenew {
                slot: [0; 32],
                step: 0,
                link: [0; 32]
            }
            .encode()
            .len(),
            1 + 32 + 4 + 32
        );
    }

    /// A truncated byte is a refusal, not a guess. Checked at EVERY length.
    #[test]
    fn truncation_is_rejected_at_every_length() {
        let objs: Vec<Vec<u8>> = vec![
            NameCommit { commit: [1; 32] }.encode(),
            NameReveal {
                slot: [2; 32],
                anchor: [3; 32],
                nonce: [4; 32],
                commit_win: 9,
            }
            .encode(),
            NameRenew {
                slot: [5; 32],
                step: 1,
                link: [6; 32],
            }
            .encode(),
            answer(2).encode().unwrap(),
        ];
        for (i, full) in objs.iter().enumerate() {
            for cut in 0..full.len() {
                let part = &full[..cut];
                let ok = match i {
                    0 => NameCommit::decode(part).is_ok(),
                    1 => NameReveal::decode(part).is_ok(),
                    2 => NameRenew::decode(part).is_ok(),
                    _ => NameAnswer::decode(part).is_ok(),
                };
                assert!(!ok, "object {i}, truncation to {cut} accepted");
            }
        }
    }

    /// An extra trailing byte is also a refusal: otherwise something could be appended to an object unnoticed.
    #[test]
    fn trailing_bytes_rejected() {
        let mut c = NameCommit { commit: [1; 32] }.encode();
        c.push(0);
        assert_eq!(NameCommit::decode(&c), Err(ParseError::BadLength));
    }

    /// A foreign version is a refusal.
    #[test]
    fn bad_version_rejected() {
        let mut c = NameCommit { commit: [1; 32] }.encode();
        c[0] = 0x02;
        assert_eq!(NameCommit::decode(&c), Err(ParseError::BadVersion));
    }

    /// More than NAME_ENTRY_MAX records is a refusal, both on assembly and on parsing.
    #[test]
    fn entry_cap_enforced() {
        assert_eq!(answer(3).encode(), Err(ParseError::TooManyEntries));
        let mut a = answer(2).encode().unwrap();
        a[1] = 3; // declared more than allowed
        assert_eq!(NameAnswer::decode(&a), Err(ParseError::TooManyEntries));
    }

    /// The answer ceiling is a refusal, not truncation.
    #[test]
    fn answer_cap_is_refusal_not_truncation() {
        let big = NameAnswer {
            entries: vec![NameEntry {
                kind: 1,
                value: vec![0; 5000], // 5000 + 3309 of signature > NAME_ANSWER_MAX
                sig: vec![0xCD; SIG_LEN],
            }],
        };
        assert_eq!(big.encode(), Err(ParseError::TooLarge));
        assert_eq!(
            NameAnswer::decode(&vec![0u8; NAME_ANSWER_MAX + 1]),
            Err(ParseError::TooLarge)
        );
    }

    /// A signature of the wrong length is a refusal: 3309 bytes of ML-DSA-65 and nothing else.
    #[test]
    fn signature_length_enforced() {
        let a = NameAnswer {
            entries: vec![NameEntry {
                kind: 1,
                value: vec![1, 2, 3],
                sig: vec![0; SIG_LEN - 1],
            }],
        };
        assert_eq!(a.encode(), Err(ParseError::BadLength));
    }
}

// ── Node: batch, index, bucket, lookup intake (checklist, stage C) ─────────────

/// Application identifier of the layer (section IV): `SHA-256("mt-app" || 0x00 || "montana-names")`.
pub fn app_id() -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-app");
    h.update([0x00u8]);
    h.update(b"montana-names");
    h.finalize().into()
}

/// Root of the layer object batch (section IV): a sparse tree over the canonical key.
/// There is ONE tree per project (`mt_merkle`), a second is not written.
///
/// The leaf key is the object itself in hashed form: the batch is a set, not a sequence,
/// so assembly order does not affect the root and the assembler cannot reorder objects.
pub fn batch_root(objects: &[Vec<u8>]) -> [u8; 32] {
    let mut tree = mt_merkle::SparseMerkleTree::new();
    for obj in objects {
        use sha2::{Digest, Sha256};
        let key: [u8; 32] = Sha256::digest(obj).into();
        tree.insert(key, obj);
    }
    tree.root()
}

/// The occupancy index is DERIVED: built by scanning reveals, it is not an authority.
/// A rebuild from scratch must give the same result, otherwise the index would become a second source of truth.
pub fn occupancy_index(reveals: &[NameReveal]) -> Vec<[u8; 32]> {
    let mut slots: Vec<[u8; 32]> = reveals.iter().map(|r| r.slot).collect();
    slots.sort_unstable();
    slots.dedup();
    slots
}

/// The BUCKET is returned as a whole. A request for a single slot is rejected: a node asked for a slot
/// learns whom the asker is interested in -- and it must not learn that.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ServeError {
    SingleSlotRequested,
    PuzzleUnsolved,
}

/// What the node returns for a bucket request: all occupied slots of this bucket.
pub fn serve_bucket(index: &[[u8; 32]], wanted_bucket: u64, occupied: u64) -> Vec<[u8; 32]> {
    index
        .iter()
        .copied()
        .filter(|s| bucket(s, occupied) == wanted_bucket)
        .collect()
}

/// Lookup intake on the node. The puzzle is checked with ONE hash and before any stretching: otherwise a stream
/// of empty lookups would burn the owner CPU, and that is exactly what spam is designed for.
pub fn accept_request(
    slot: &[u8; 32],
    eph_pk: &[u8],
    nonce: &[u8],
    single_slot_request: bool,
) -> Result<(), ServeError> {
    if single_slot_request {
        return Err(ServeError::SingleSlotRequested);
    }
    if !puzzle_ok(&puzzle(slot, eph_pk, nonce), NAME_PUZZLE_BITS) {
        return Err(ServeError::PuzzleUnsolved);
    }
    Ok(())
}

#[cfg(test)]
mod node_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// A value from section XI of the spec.
    #[test]
    fn app_id_matches_spec() {
        assert_eq!(
            hex(&app_id()),
            "350ee2a847cd651df34d0bc6c90b71f75a0485b763503a2ee292ea5b69cc8eb8"
        );
    }

    /// The batch is a SET: assembly order does not affect the root, objects cannot be reordered.
    #[test]
    fn batch_root_is_order_independent() {
        let a = NameCommit { commit: [1; 32] }.encode();
        let b = NameCommit { commit: [2; 32] }.encode();
        let c = NameCommit { commit: [3; 32] }.encode();
        let r1 = batch_root(&[a.clone(), b.clone(), c.clone()]);
        let r2 = batch_root(&[c, a, b]);
        assert_eq!(r1, r2);
    }

    /// Any change to an object changes the root: the batch can be withheld, not forged.
    #[test]
    fn batch_root_binds_every_object() {
        let a = NameCommit { commit: [1; 32] }.encode();
        let b = NameCommit { commit: [2; 32] }.encode();
        let b2 = NameCommit { commit: [9; 32] }.encode();
        assert_ne!(batch_root(&[a.clone(), b]), batch_root(&[a, b2]));
    }

    /// Neither the name, the slot nor the anchor can be derived from a commitment: the assembler sees 32 bytes of noise.
    #[test]
    fn commit_reveals_nothing() {
        let s = slot("anna");
        let c = chain(&[0xCD; 32]);
        let cm = commit(&s, &anchor(&c), &[7; 32]);
        let wire = NameCommit { commit: cm }.encode();
        // neither the slot nor the anchor occurs in the object bytes
        assert!(!wire.windows(32).any(|w| w == s));
        assert!(!wire.windows(32).any(|w| w == anchor(&c)));
        assert_eq!(
            wire.len(),
            33,
            "version and 32 bytes -- nothing else is in the object"
        );
    }

    /// The index is derived: rebuilt from scratch and in another order, it is the same.
    #[test]
    fn index_is_reproducible() {
        let mk = |n: &str| NameReveal {
            slot: slot(n),
            anchor: [0; 32],
            nonce: [0; 32],
            commit_win: 1,
        };
        let a = occupancy_index(&[mk("alice"), mk("bob1"), mk("alice")]);
        let b = occupancy_index(&[mk("bob1"), mk("alice")]);
        assert_eq!(a, b, "repetition and order do not change the index");
        assert_eq!(a.len(), 2, "a repeated reveal does not double the slot");
    }

    /// The bucket is returned whole: the answer holds all slots of the bucket, not the single one requested.
    #[test]
    fn bucket_served_whole() {
        let names: Vec<String> = (0..2000).map(|i| format!("user{i:05}")).collect();
        let index: Vec<[u8; 32]> = names.iter().map(|n| slot(n)).collect();
        let occupied = index.len() as u64;
        let target = slot(&names[0]);
        let b = bucket(&target, occupied);
        let served = serve_bucket(&index, b, occupied);
        assert!(served.contains(&target));
        assert!(
            served.len() >= 2,
            "the bucket holds one slot -- no cover: occupied {occupied}, bucket {b}"
        );
    }

    /// A single-slot request is rejected, an unsolved puzzle is rejected -- and before stretching.
    #[test]
    fn request_rules() {
        let s = slot("anna");
        let eph = vec![0x5A; 1184];
        assert_eq!(
            accept_request(&s, &eph, &[0; 8], true),
            Err(ServeError::SingleSlotRequested)
        );
        assert_eq!(
            accept_request(&s, &eph, &[0; 8], false),
            Err(ServeError::PuzzleUnsolved)
        );
        let nonce = 810_487u64.to_le_bytes();
        assert_eq!(accept_request(&s, &eph, &nonce, false), Ok(()));
    }
}

// ── Name ownership over time (checklist, stage D) ───────────────────────────────

/// Length of τ₂ in windows -- from the protocol.
pub const TAU2_WINDOWS: u32 = 20_160;
/// Renewal period (section VIII): 6τ₂.
pub const NAME_RENEW_WINDOWS: u32 = 6 * TAU2_WINDOWS;
/// Reveal deadline after the commitment (section VIII): 2τ₂.
pub const NAME_REVEAL_MAX_WINDOWS: u32 = 2 * TAU2_WINDOWS;

/// Why an ownership step was not accepted.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum LifecycleError {
    RevealTooLate,
    RevealBeforeCommit,
    RenewTooLate,
    RenewNotMonotonic,
    ChainExhausted,
    SecondNameForOneSecret,
}

/// A reveal must land in the chain no later than `NAME_REVEAL_MAX` after the commitment, otherwise the commitment is dead.
/// Dead commitments do not accumulate -- that is the point of the deadline.
pub fn check_reveal(commit_win: u32, reveal_win: u32) -> Result<(), LifecycleError> {
    if reveal_win <= commit_win {
        return Err(LifecycleError::RevealBeforeCommit);
    }
    if reveal_win - commit_win > NAME_REVEAL_MAX_WINDOWS {
        return Err(LifecycleError::RevealTooLate);
    }
    Ok(())
}

/// Start of period `step`. A renewal is placed HERE, not at the moment the person opened the
/// app: otherwise the moment of publication becomes a sign of their life, not a property of the schedule.
pub fn renew_period_start(reveal_win: u32, step: u32) -> u32 {
    reveal_win + step * NAME_RENEW_WINDOWS
}

/// A renewal is accepted if the link is monotonic, the chain is not exhausted and the period is not missed.
pub fn check_renew(
    prev_step: u32,
    prev_win: u32,
    step: u32,
    win: u32,
) -> Result<(), LifecycleError> {
    if step != prev_step + 1 {
        return Err(LifecycleError::RenewNotMonotonic);
    }
    if step as usize > NAME_CHAIN_LEN {
        return Err(LifecycleError::ChainExhausted);
    }
    if win <= prev_win || win - prev_win > NAME_RENEW_WINDOWS {
        return Err(LifecycleError::RenewTooLate);
    }
    Ok(())
}

/// The slot is free: more than `NAME_RENEW` was missed. The previous owner has no advantage --
/// the next one takes it on equal terms.
pub fn is_free(last_win: u32, now: u32) -> bool {
    now > last_win.saturating_add(NAME_RENEW_WINDOWS)
}

/// One name per secret (rule 2 of section II). A second name requires a second seed branch, not a second
/// slot on the same branch: otherwise one secret leak would take all of a person's names at once.
pub fn check_single_name(
    existing: Option<&[u8; 32]>,
    new_slot: &[u8; 32],
) -> Result<(), LifecycleError> {
    match existing {
        Some(s) if s != new_slot => Err(LifecycleError::SecondNameForOneSecret),
        _ => Ok(()),
    }
}

/// Ownership is confirmed: the chain from the anchor to the current link converges step by step.
/// The verifier needs neither the name nor the secret -- only the anchor and the presented links.
pub fn verify_ownership(anchor: &[u8; 32], links_in_order: &[[u8; 32]]) -> bool {
    let mut prev = *anchor;
    for l in links_in_order {
        if !verify_link(&prev, l) {
            return false;
        }
        prev = *l;
    }
    true
}

#[cfg(test)]
mod lifecycle_tests {
    use super::*;

    #[test]
    fn reveal_window_rules() {
        assert_eq!(check_reveal(100, 101), Ok(()));
        assert_eq!(check_reveal(100, 100 + NAME_REVEAL_MAX_WINDOWS), Ok(()));
        assert_eq!(
            check_reveal(100, 100 + NAME_REVEAL_MAX_WINDOWS + 1),
            Err(LifecycleError::RevealTooLate)
        );
        assert_eq!(
            check_reveal(100, 100),
            Err(LifecycleError::RevealBeforeCommit)
        );
        assert_eq!(
            check_reveal(100, 99),
            Err(LifecycleError::RevealBeforeCommit)
        );
    }

    /// A renewal stands at the start of the period: the moment of publication is a property of the schedule, not of life.
    #[test]
    fn renew_is_scheduled_at_period_start() {
        let reveal = 1_000u32;
        assert_eq!(renew_period_start(reveal, 1), reveal + NAME_RENEW_WINDOWS);
        assert_eq!(
            renew_period_start(reveal, 2),
            reveal + 2 * NAME_RENEW_WINDOWS
        );
        // and every renewal falls within its term
        let mut prev_win = reveal;
        for step in 1..=5u32 {
            let win = renew_period_start(reveal, step);
            assert_eq!(check_renew(step - 1, prev_win, step, win), Ok(()));
            prev_win = win;
        }
    }

    #[test]
    fn renew_rules() {
        assert_eq!(
            check_renew(3, 1000, 5, 2000),
            Err(LifecycleError::RenewNotMonotonic)
        );
        assert_eq!(
            check_renew(3, 1000, 3, 2000),
            Err(LifecycleError::RenewNotMonotonic)
        );
        assert_eq!(
            check_renew(3, 1000, 4, 1000 + NAME_RENEW_WINDOWS + 1),
            Err(LifecycleError::RenewTooLate)
        );
        assert_eq!(
            check_renew(3, 1000, 4, 1000),
            Err(LifecycleError::RenewTooLate)
        );
        assert_eq!(
            check_renew(NAME_CHAIN_LEN as u32, 1000, NAME_CHAIN_LEN as u32 + 1, 1001),
            Err(LifecycleError::ChainExhausted)
        );
    }

    /// More than a period missed -- the slot is free, and the previous owner has no privilege.
    #[test]
    fn release_after_missed_period() {
        let last = 10_000u32;
        assert!(!is_free(last, last + NAME_RENEW_WINDOWS));
        assert!(is_free(last, last + NAME_RENEW_WINDOWS + 1));
    }

    #[test]
    fn one_name_per_secret() {
        let a = slot("alice");
        let b = slot("bobbb");
        assert_eq!(check_single_name(None, &a), Ok(()));
        assert_eq!(
            check_single_name(Some(&a), &a),
            Ok(()),
            "renewal of one's own name"
        );
        assert_eq!(
            check_single_name(Some(&a), &b),
            Err(LifecycleError::SecondNameForOneSecret)
        );
    }

    /// Ownership is verified without the name and without the secret: only the anchor and the links.
    #[test]
    fn ownership_verifies_from_anchor_only() {
        let c = chain(&name_own(&[3u8; 64], &slot("alicemontana")));
        let a = anchor(&c);
        assert!(verify_ownership(&a, &c[1..6]));
        assert!(
            !verify_ownership(&a, &c[2..6]),
            "a missing link breaks the chain"
        );
        let mut broken = c[1..6].to_vec();
        broken[2] = [0xEE; 32];
        assert!(
            !verify_ownership(&a, &broken),
            "a substituted link breaks the chain"
        );
    }

    /// Recovery from the seed: the chain and anchor are the same, no state needs to be carried over.
    #[test]
    fn recovery_from_seed_reproduces_everything() {
        let seed = [0x5Au8; 64];
        let s = slot("alicemontana");
        let c1 = chain(&name_own(&seed, &s));
        // "another device": only the seed phrase and the name
        let c2 = chain(&name_own(&seed, &slot("alicemontana")));
        assert_eq!(anchor(&c1), anchor(&c2));
        assert_eq!(c1, c2);
    }
}

// ── Lookup and answer (checklist, stage E) ────────────────────────────────────────

/// Kinds of answer records (section IV). A payment key and any quantity of the value
/// plane are forbidden -- this is [I-2], not a preference.
pub const ENTRY_KIND_MAIL: u16 = 0x0001;
pub const ENTRY_KIND_OVERLAY: u16 = 0x0002;
pub const ENTRY_KIND_OPAQUE: u16 = 0xFFFF;
/// Forbidden kind: payment key.
pub const ENTRY_KIND_FORBIDDEN_NOTE_PK: u16 = 0x0100;

/// Why resolution did not succeed. Each step of section VI has its own refusal: a silent failure
/// hides a substitution.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ResolveError {
    BadName,
    RecordNotInBucket,
    RecordHashMismatch,
    NotOwned,
    EntrySignatureInvalid,
    ForbiddenEntryKind,
}

/// What the verifier knows about a record found in the bucket.
pub struct ResolveInput<'a> {
    pub raw_name: &'a str,
    pub bucket_slots: &'a [[u8; 32]],
    pub occupied: u64,
    pub record_bytes: &'a [u8],
    pub record_hash_claimed: [u8; 32],
    pub anchor: [u8; 32],
    pub links_in_order: &'a [[u8; 32]],
    pub answer: &'a NameAnswer,
    /// Check of the address record signature by the key that OWNS that address. The caller
    /// verifies the signature (it has the keys), the result comes here: the names layer knows nothing of ML-DSA.
    pub entry_signatures_ok: bool,
}

/// Resolution in the five steps of section VI. Each step with its own refusal; step order matters:
/// the ownership check comes BEFORE the record checks, otherwise a foreign record gets read in time.
pub fn resolve(input: &ResolveInput) -> Result<Vec<NameEntry>, ResolveError> {
    let normalized = normalize(input.raw_name).map_err(|_| ResolveError::BadName)?;
    let s = slot(&normalized);

    if !input.bucket_slots.contains(&s) {
        return Err(ResolveError::RecordNotInBucket);
    }
    use sha2::{Digest, Sha256};
    let h: [u8; 32] = Sha256::digest(input.record_bytes).into();
    if h != input.record_hash_claimed {
        return Err(ResolveError::RecordHashMismatch);
    }
    if !verify_ownership(&input.anchor, input.links_in_order) {
        return Err(ResolveError::NotOwned);
    }
    for e in &input.answer.entries {
        if e.kind == ENTRY_KIND_FORBIDDEN_NOTE_PK {
            return Err(ResolveError::ForbiddenEntryKind);
        }
    }
    if !input.entry_signatures_ok {
        return Err(ResolveError::EntrySignatureInvalid);
    }
    Ok(input.answer.entries.clone())
}

#[cfg(test)]
mod resolve_tests {
    use super::*;

    fn entry(kind: u16) -> NameEntry {
        NameEntry {
            kind,
            value: b"mt-overlay-address".to_vec(),
            sig: vec![0xCD; SIG_LEN],
        }
    }

    /// Resolution fixture: field names are clearer than a tuple of five values.
    struct Stand {
        bucket_slots: Vec<[u8; 32]>,
        links: Vec<[u8; 32]>,
        anchor: [u8; 32],
        record: Vec<u8>,
        record_hash: [u8; 32],
    }

    fn setup() -> Stand {
        let s = slot("alicemontana");
        let c = chain(&name_own(&[4u8; 64], &s));
        let record = b"record-bytes".to_vec();
        use sha2::{Digest, Sha256};
        let h: [u8; 32] = Sha256::digest(&record).into();
        Stand {
            bucket_slots: vec![s, slot("bobbbb")],
            links: c[1..4].to_vec(),
            anchor: anchor(&c),
            record,
            record_hash: h,
        }
    }

    #[test]
    fn resolve_happy_path() {
        let st = setup();
        let (bucket_slots, links, a, record, h) = (
            st.bucket_slots.clone(),
            st.links.clone(),
            st.anchor,
            st.record.clone(),
            st.record_hash,
        );
        let answer = NameAnswer {
            entries: vec![entry(ENTRY_KIND_OVERLAY)],
        };
        let out = resolve(&ResolveInput {
            raw_name: "AliceMontana",
            bucket_slots: &bucket_slots,
            occupied: 2,
            record_bytes: &record,
            record_hash_claimed: h,
            anchor: a,
            links_in_order: &links,
            answer: &answer,
            entry_signatures_ok: true,
        });
        assert_eq!(out.map(|v| v.len()), Ok(1));
    }

    /// Each step has ITS OWN refusal: a failure is neither silent nor generic.
    #[test]
    fn every_step_has_its_own_refusal() {
        let st = setup();
        let (bucket_slots, links, a, record, h) = (
            st.bucket_slots.clone(),
            st.links.clone(),
            st.anchor,
            st.record.clone(),
            st.record_hash,
        );
        let answer = NameAnswer {
            entries: vec![entry(ENTRY_KIND_OVERLAY)],
        };
        let base = |raw, bs: &[[u8; 32]], rh, an, lk: &[[u8; 32]], ans, sig| {
            resolve(&ResolveInput {
                raw_name: raw,
                bucket_slots: bs,
                occupied: 2,
                record_bytes: &record,
                record_hash_claimed: rh,
                anchor: an,
                links_in_order: lk,
                answer: ans,
                entry_signatures_ok: sig,
            })
        };
        assert_eq!(
            base("!!", &bucket_slots, h, a, &links, &answer, true),
            Err(ResolveError::BadName)
        );
        assert_eq!(
            base("carolmontana", &bucket_slots, h, a, &links, &answer, true),
            Err(ResolveError::RecordNotInBucket)
        );
        assert_eq!(
            base(
                "alicemontana",
                &bucket_slots,
                [0; 32],
                a,
                &links,
                &answer,
                true
            ),
            Err(ResolveError::RecordHashMismatch)
        );
        assert_eq!(
            base(
                "alicemontana",
                &bucket_slots,
                h,
                [9; 32],
                &links,
                &answer,
                true
            ),
            Err(ResolveError::NotOwned)
        );
        let forbidden = NameAnswer {
            entries: vec![entry(ENTRY_KIND_FORBIDDEN_NOTE_PK)],
        };
        assert_eq!(
            base(
                "alicemontana",
                &bucket_slots,
                h,
                a,
                &links,
                &forbidden,
                true
            ),
            Err(ResolveError::ForbiddenEntryKind)
        );
        assert_eq!(
            base("alicemontana", &bucket_slots, h, a, &links, &answer, false),
            Err(ResolveError::EntrySignatureInvalid)
        );
    }

    /// A payment key in an answer is rejected before signatures are checked: [I-2] is not up for discussion.
    #[test]
    fn note_key_refused_before_signatures() {
        let st = setup();
        let (bucket_slots, links, a, record, h) = (
            st.bucket_slots.clone(),
            st.links.clone(),
            st.anchor,
            st.record.clone(),
            st.record_hash,
        );
        let forbidden = NameAnswer {
            entries: vec![entry(ENTRY_KIND_FORBIDDEN_NOTE_PK)],
        };
        let r = resolve(&ResolveInput {
            raw_name: "alicemontana",
            bucket_slots: &bucket_slots,
            occupied: 2,
            record_bytes: &record,
            record_hash_claimed: h,
            anchor: a,
            links_in_order: &links,
            answer: &forbidden,
            entry_signatures_ok: false, // signatures are deliberately bad
        });
        assert_eq!(
            r,
            Err(ResolveError::ForbiddenEntryKind),
            "record kind outranks signature"
        );
    }

    /// The answer is stored nowhere: two answers to one request are different bytes, because
    /// they are sealed to different ephemeral keys. What is checked here is the assembly property itself:
    /// the same set of records encodes to the same bytes, and the difference is introduced by
    /// sealing -- which lives a layer above and is not part of the names layer.
    #[test]
    fn answer_is_assembled_not_stored() {
        let a1 = NameAnswer {
            entries: vec![entry(ENTRY_KIND_MAIL)],
        };
        let a2 = NameAnswer {
            entries: vec![entry(ENTRY_KIND_MAIL)],
        };
        assert_eq!(a1.encode(), a2.encode());
    }
}

/// Lookup to the owner (section V). The sealed part carries `slot` and the window number: an intercepted
/// lookup cannot be presented again -- the lookup carries a window, and a foreign window is rejected.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameRequest {
    pub slot: [u8; 32],
    pub window: u32,
    pub eph_pk: Vec<u8>,
    pub nonce: [u8; 8],
}

impl NameRequest {
    /// Bytes that are sealed to `req_key`. The object version is the same as for the others (0x03).
    pub fn sealed_body(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.slot);
        v.extend_from_slice(&self.window.to_le_bytes());
        v.extend_from_slice(&self.nonce);
        v.extend_from_slice(&self.eph_pk);
        v
    }
    pub fn parse_sealed(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let slot = take32(&mut b)?;
        let window = take_u32_le(&mut b)?;
        let mut nonce = [0u8; 8];
        nonce.copy_from_slice(take(&mut b, 8)?);
        let eph_pk = b.to_vec();
        if eph_pk.is_empty() {
            return Err(ParseError::Truncated);
        }
        Ok(Self {
            slot,
            window,
            eph_pk,
            nonce,
        })
    }
}

/// Why the lookup was not accepted.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum RequestError {
    WrongSlot,
    StaleWindow,
    PuzzleUnsolved,
}

/// A lookup is accepted only in ITS OWN window, only for ITS OWN slot, and only with a solved
/// puzzle. The window on the lookup is the replay protection: what was recorded yesterday is no good today.
pub fn check_request(
    req: &NameRequest,
    my_slot: &[u8; 32],
    now_window: u32,
) -> Result<(), RequestError> {
    if req.slot != *my_slot {
        return Err(RequestError::WrongSlot);
    }
    if req.window != now_window {
        return Err(RequestError::StaleWindow);
    }
    if !puzzle_ok(
        &puzzle(&req.slot, &req.eph_pk, &req.nonce),
        NAME_PUZZLE_BITS,
    ) {
        return Err(RequestError::PuzzleUnsolved);
    }
    Ok(())
}

#[cfg(test)]
mod request_object_tests {
    use super::*;

    fn req(window: u32) -> NameRequest {
        NameRequest {
            slot: slot("anna"),
            window,
            eph_pk: vec![0x5A; 1184],
            nonce: 810_487u64.to_le_bytes(),
        }
    }

    #[test]
    fn sealed_body_round_trip() {
        let r = req(42);
        assert_eq!(NameRequest::parse_sealed(&r.sealed_body()), Ok(r));
    }

    /// Replay of an intercepted lookup is rejected: it carries a foreign window.
    #[test]
    fn replay_is_refused() {
        let s = slot("anna");
        assert_eq!(check_request(&req(42), &s, 42), Ok(()));
        assert_eq!(
            check_request(&req(42), &s, 43),
            Err(RequestError::StaleWindow)
        );
        assert_eq!(
            check_request(&req(42), &s, 41),
            Err(RequestError::StaleWindow)
        );
    }

    /// A foreign slot is rejected before the puzzle: there is no reason to compute a hash for a foreign lookup.
    #[test]
    fn wrong_slot_refused_first() {
        let mut r = req(42);
        r.nonce = [0; 8]; // the puzzle is deliberately unsolved
        assert_eq!(
            check_request(&r, &slot("bobbbb"), 42),
            Err(RequestError::WrongSlot)
        );
    }

    #[test]
    fn unsolved_puzzle_refused() {
        let mut r = req(42);
        r.nonce = [0; 8];
        assert_eq!(
            check_request(&r, &slot("anna"), 42),
            Err(RequestError::PuzzleUnsolved)
        );
    }

    /// A truncated lookup is not parsed -- the ephemeral key is required.
    #[test]
    fn truncated_request_refused() {
        let full = req(1).sealed_body();
        for cut in 0..=45 {
            assert!(
                NameRequest::parse_sealed(&full[..cut.min(full.len())]).is_err(),
                "truncation {cut}"
            );
        }
    }
}

// ── Layer acceptance (checklist, stage G) ─────────────────────────────────────────────

/// What a chain observer sees from the names layer: ONLY the fact of batch anchoring.
/// The function exists so that this claim is verifiable rather than declarative.
pub struct ChainVisible {
    pub app_id: [u8; 32],
    pub batch_root: [u8; 32],
}

/// Assemble what goes to the chain. There is no name, no slot, no anchor here -- and the test below
/// checks this by scanning bytes, not by trusting the wording.
pub fn chain_visible(objects: &[Vec<u8>]) -> ChainVisible {
    ChainVisible {
        app_id: app_id(),
        batch_root: batch_root(objects),
    }
}

#[cfg(test)]
mod acceptance_tests {
    use super::*;

    /// G-42: two devices from one seed phrase give the same slot, chain and anchor.
    #[test]
    fn two_devices_from_one_seed_agree() {
        let seed = [0x11u8; 64];
        let name = "alicemontana";
        let (s1, c1) = {
            let s = slot(&normalize(name).unwrap());
            (s, chain(&name_own(&seed, &s)))
        };
        let (s2, c2) = {
            let s = slot(&normalize("AliceMontana").unwrap()); // another spelling of the same name
            (s, chain(&name_own(&seed, &s)))
        };
        assert_eq!(s1, s2);
        assert_eq!(anchor(&c1), anchor(&c2));
        assert_eq!(c1, c2);
    }

    /// G-43: a released name is taken by the next person, and their chain is DIFFERENT -- the previous owner
    /// keeps no power whatsoever over the slot.
    #[test]
    fn released_name_taken_by_next_owner() {
        let s = slot("alicemontana");
        let first = chain(&name_own(&[1u8; 64], &s));
        let second = chain(&name_own(&[2u8; 64], &s));
        assert_ne!(anchor(&first), anchor(&second));
        // links of the previous owner do not verify against the new anchor
        assert!(!verify_ownership(&anchor(&second), &first[1..3]));
        // and the slot is free by time
        let last = 5_000u32;
        assert!(is_free(last, last + NAME_RENEW_WINDOWS + 1));
    }

    /// G-44: the chain observer sees only the fact of anchoring. Checked by SCANNING: neither the slot,
    /// nor the anchor, nor the name occurs in what goes to the chain.
    #[test]
    fn chain_observer_sees_only_the_fact() {
        let s = slot("anna");
        let c = chain(&[0xCD; 32]);
        let objs = vec![
            NameCommit {
                commit: commit(&s, &anchor(&c), &[7; 32]),
            }
            .encode(),
            NameRenew {
                slot: s,
                step: 1,
                link: c[1],
            }
            .encode(),
        ];
        let v = chain_visible(&objs);
        let mut wire = v.app_id.to_vec();
        wire.extend_from_slice(&v.batch_root);
        assert!(!wire.windows(32).any(|w| w == s), "slot visible in the chain");
        assert!(
            !wire.windows(32).any(|w| w == anchor(&c)),
            "anchor visible in the chain"
        );
        assert!(!wire.windows(4).any(|w| w == b"anna"), "name visible in the chain");
        assert_eq!(wire.len(), 64, "exactly app_id and the batch root go to the chain");
    }

    /// G-44 continued: the reveal CONTAINS the slot and anchor -- and that is right, because
    /// the reveal goes to the chain precisely so that ownership becomes verifiable. The test pins
    /// the boundary: the commitment is opaque, not the reveal, and they must not be confused.
    #[test]
    fn reveal_is_open_by_design() {
        let s = slot("anna");
        let c = chain(&[0xCD; 32]);
        let r = NameReveal {
            slot: s,
            anchor: anchor(&c),
            nonce: [7; 32],
            commit_win: 5,
        };
        let wire = r.encode();
        assert!(wire.windows(32).any(|w| w == s));
        assert!(wire.windows(32).any(|w| w == anchor(&c)));
        // but the NAME is absent from the reveal too -- the name never reaches the chain
        assert!(!wire.windows(4).any(|w| w == b"anna"));
    }
}
