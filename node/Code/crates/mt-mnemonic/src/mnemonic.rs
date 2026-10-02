// The identity root: 24 words carry 256 bits of entropy plus one checksum byte;
// the master seed is derived from the entropy itself, so the way the words are
// typed — spacing, case, Unicode form — cannot change a single derived byte.

use crate::sha256_raw;
use mt_codec::domain;
use zeroize::{Zeroize, Zeroizing};

use crate::bit_packing::{pack_indices_to_bytes, unpack_bytes_to_indices, PACKED_BYTES};
use crate::hkdf::hkdf_expand;
use crate::pbkdf2::pbkdf2_hmac_sha256;
use crate::wordlist::{word_index, wordlist};

pub const MNEMONIC_WORD_COUNT: usize = 24;
pub const KDF_ITER: u32 = 1_048_576; // = 2^20
pub const MASTER_SEED_LEN: usize = 64;
// spec: ML-DSA-65 seed (FIPS 204 §3.1, ξ ∈ B32) — 32 байта (was Falcon 48).
pub const MLDSA_SEED_LEN: usize = 32;
pub const MLKEM_SEED_LEN: usize = 64;
// libp2p Ed25519 transport identity seed (RFC 8032 Ed25519 secret = 32 байта).
pub const ED25519_SEED_LEN: usize = 32;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum MnemonicError {
    WordCount(usize),
    UnknownWord(usize),
    ChecksumMismatch,
}

impl core::fmt::Display for MnemonicError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::WordCount(n) => write!(f, "expected 24 words, got {n}"),
            Self::UnknownWord(pos) => write!(
                f,
                "word at position {pos} is not in canonical Montana wordlist"
            ),
            Self::ChecksumMismatch => write!(f, "mnemonic checksum mismatch"),
        }
    }
}

impl std::error::Error for MnemonicError {}

pub fn mnemonic_to_entropy(mnemonic: &str) -> Result<[u8; 32], MnemonicError> {
    // split_whitespace вместо split(' ') — UX-friendly: пользователь
    // может скопировать мнемонику с tab-ами, multiple spaces, либо
    // newlines между словами (типичный случай при copy-paste из менеджера
    // паролей). Strict single-space parsing давал false `WordCount` либо
    // `UnknownWord` ошибки на безобидных whitespace вариациях.
    let words: Vec<&str> = mnemonic.split_whitespace().collect();
    if words.len() != MNEMONIC_WORD_COUNT {
        return Err(MnemonicError::WordCount(words.len()));
    }

    // Все двадцать четыре слова просматриваются всегда: разбор, обрывающийся на
    // первом непонятном слове, сообщал бы временем, где именно человек ошибся.
    let mut indices = [0u16; MNEMONIC_WORD_COUNT];
    let mut first_unknown: Option<usize> = None;
    for (i, w) in words.iter().enumerate() {
        match word_index(w) {
            Some(idx) => indices[i] = idx,
            None => {
                if first_unknown.is_none() {
                    first_unknown = Some(i);
                }
            },
        }
    }
    if let Some(pos) = first_unknown {
        indices.zeroize();
        return Err(MnemonicError::UnknownWord(pos));
    }

    let mut buf: [u8; PACKED_BYTES] = pack_indices_to_bytes(&indices);
    indices.zeroize();
    let mut entropy = [0u8; 32];
    entropy.copy_from_slice(&buf[0..32]);
    let checksum_provided = buf[32];
    let checksum_computed = sha256_raw(&entropy)[0];
    buf.zeroize();

    if checksum_provided != checksum_computed {
        entropy.zeroize();
        return Err(MnemonicError::ChecksumMismatch);
    }
    Ok(entropy)
}

pub fn mnemonic_to_master_seed(mnemonic: &str) -> Result<[u8; MASTER_SEED_LEN], MnemonicError> {
    let mut entropy = mnemonic_to_entropy(mnemonic)?;
    let dk = Zeroizing::new(pbkdf2_hmac_sha256(
        &entropy,
        domain::SEED,
        KDF_ITER,
        MASTER_SEED_LEN,
    ));
    entropy.zeroize();
    let mut master_seed = [0u8; MASTER_SEED_LEN];
    master_seed.copy_from_slice(&dk);
    Ok(master_seed)
}

pub fn mldsa_seed_for_role(
    master_seed: &[u8; MASTER_SEED_LEN],
    role: &[u8],
) -> [u8; MLDSA_SEED_LEN] {
    let dk = Zeroizing::new(hkdf_expand(master_seed, role, MLDSA_SEED_LEN));
    let mut out = [0u8; MLDSA_SEED_LEN];
    out.copy_from_slice(&dk);
    out
}

pub fn mlkem_seed_for_role(
    master_seed: &[u8; MASTER_SEED_LEN],
    role: &[u8],
) -> [u8; MLKEM_SEED_LEN] {
    let dk = Zeroizing::new(hkdf_expand(master_seed, role, MLKEM_SEED_LEN));
    let mut out = [0u8; MLKEM_SEED_LEN];
    out.copy_from_slice(&dk);
    out
}

// [I-16] admission A-1: деривация seed для libp2p ed25519 transport keypair (admission-
// обёртка libp2p PeerId, НЕ Montana-identity — та ML-DSA-65). Единый источник ed25519-роли.
pub fn ed25519_seed_for_role(
    master_seed: &[u8; MASTER_SEED_LEN],
    role: &[u8],
) -> [u8; ED25519_SEED_LEN] {
    let dk = Zeroizing::new(hkdf_expand(master_seed, role, ED25519_SEED_LEN));
    let mut out = [0u8; ED25519_SEED_LEN];
    out.copy_from_slice(&dk);
    out
}

pub fn entropy_to_mnemonic(entropy: &[u8; 32]) -> String {
    let checksum = sha256_raw(entropy)[0];
    let mut buf = [0u8; PACKED_BYTES];
    buf[..32].copy_from_slice(entropy);
    buf[32] = checksum;
    let mut indices = unpack_bytes_to_indices(&buf);
    buf.zeroize();
    let wl = wordlist();
    let words: Vec<&str> = indices.iter().map(|&i| wl[i as usize]).collect();
    indices.zeroize();
    words.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_length_zero_words() {
        // split_whitespace на пустой строке даёт 0 элементов (vs split(' ')
        // даёт 1 пустой элемент). Closure F-12 (split_whitespace вместо
        // split(' ')) изменил это поведение в UX-friendly сторону.
        let err = mnemonic_to_master_seed("").unwrap_err();
        assert_eq!(err, MnemonicError::WordCount(0));
    }

    #[test]
    fn whitespace_tolerant_parsing() {
        // F-12 closure: пользователь может скопировать мнемонику с tab-ами,
        // multiple spaces либо newlines между словами — split_whitespace
        // tolerates все эти случаи.
        let m = ["abandon"; 24].join("  "); // double space между словами
        let err = mnemonic_to_master_seed(&m).unwrap_err();
        // 24 слова парсятся правильно (не WordCount), но "abandon" × 24
        // не имеет valid checksum → ChecksumMismatch
        assert_eq!(err, MnemonicError::ChecksumMismatch);

        let m_tabs = ["abandon"; 24].join("\t");
        let err_tabs = mnemonic_to_master_seed(&m_tabs).unwrap_err();
        assert_eq!(err_tabs, MnemonicError::ChecksumMismatch);

        let m_newlines = ["abandon"; 24].join("\n");
        let err_newlines = mnemonic_to_master_seed(&m_newlines).unwrap_err();
        assert_eq!(err_newlines, MnemonicError::ChecksumMismatch);
    }

    #[test]
    fn invalid_length_one_word() {
        let err = mnemonic_to_master_seed("abandon").unwrap_err();
        assert_eq!(err, MnemonicError::WordCount(1));
    }

    #[test]
    fn invalid_length_23_words() {
        let m = "abandon ".repeat(22) + "abandon";
        let err = mnemonic_to_master_seed(&m).unwrap_err();
        assert_eq!(err, MnemonicError::WordCount(23));
    }

    #[test]
    fn invalid_word_at_position_0() {
        let m = format!("bogus {}", "abandon ".repeat(23).trim_end());
        let err = mnemonic_to_master_seed(&m).unwrap_err();
        assert_eq!(err, MnemonicError::UnknownWord(0));
    }

    #[test]
    fn invalid_checksum_all_abandon() {
        // "abandon" × 24 имеет неверный checksum (checksum последнего слова должен быть
        // SHA-256(zeros_32)[0] = 0x66, что соответствует 24-му слову "art" (index 102).
        let m = "abandon ".repeat(23) + "abandon";
        let err = mnemonic_to_master_seed(&m).unwrap_err();
        assert_eq!(err, MnemonicError::ChecksumMismatch);
    }

    #[test]
    fn entropy_zero_roundtrip_successful() {
        let entropy = [0u8; 32];
        let mnemonic = entropy_to_mnemonic(&entropy);
        let master_seed = mnemonic_to_master_seed(&mnemonic).expect("valid mnemonic");
        assert_eq!(master_seed.len(), 64);
    }

    #[test]
    fn entropy_zero_produces_23_abandon_plus_art() {
        let entropy = [0u8; 32];
        let mnemonic = entropy_to_mnemonic(&entropy);
        let expected_last = "art"; // BIP-39 standard: zero entropy + checksum 0x66 → word 102
        let words: Vec<&str> = mnemonic.split(' ').collect();
        for w in words.iter().take(23) {
            assert_eq!(*w, "abandon");
        }
        assert_eq!(words[23], expected_last);
    }

    #[test]
    fn determinism_mnemonic_to_master_seed() {
        let entropy = [0xabu8; 32];
        let mnemonic = entropy_to_mnemonic(&entropy);
        let a = mnemonic_to_master_seed(&mnemonic).unwrap();
        let b = mnemonic_to_master_seed(&mnemonic).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn per_role_derivations_differ() {
        let entropy = [0x11u8; 32];
        let mnemonic = entropy_to_mnemonic(&entropy);
        let master = mnemonic_to_master_seed(&mnemonic).unwrap();
        let mldsa_acc = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
        let mldsa_node = mldsa_seed_for_role(&master, domain::NODE_KEY);
        let mlkem_app = mlkem_seed_for_role(&master, domain::APP_ENCRYPTION_KEY);
        assert_ne!(mldsa_acc[..], mldsa_node[..]);
        assert_ne!(&mldsa_acc[..], &mlkem_app[..MLDSA_SEED_LEN]);
    }

    #[test]
    fn per_role_derivation_determinism() {
        let master = [0x55u8; 64];
        let a = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
        let b = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
        assert_eq!(a, b);
    }

    #[test]
    fn mldsa_seed_len_is_32() {
        // FIPS 204 §3.1: ξ ∈ B32 (ML-DSA-65 KeyGen_internal seed)
        assert_eq!(MLDSA_SEED_LEN, 32);
    }

    #[test]
    fn ed25519_seed_len_is_32() {
        // RFC 8032 Ed25519 secret key = 32 bytes
        assert_eq!(ED25519_SEED_LEN, 32);
    }

    #[test]
    fn ed25519_seed_for_role_determinism() {
        let master = [0x77u8; 64];
        let a = ed25519_seed_for_role(&master, domain::LIBP2P_TRANSPORT_KEY);
        let b = ed25519_seed_for_role(&master, domain::LIBP2P_TRANSPORT_KEY);
        assert_eq!(a, b);
    }

    #[test]
    fn unknown_word_reports_the_first_position_regardless_of_how_many_are_wrong() {
        let entropy = [0x21u8; 32];
        let canonical = entropy_to_mnemonic(&entropy);
        let mut words: Vec<String> = canonical.split(' ').map(str::to_string).collect();
        words[5] = "zzzz".to_string();
        words[19] = "qqqq".to_string();
        assert_eq!(
            mnemonic_to_entropy(&words.join(" ")).unwrap_err(),
            MnemonicError::UnknownWord(5)
        );
    }

    #[test]
    fn uppercase_and_prefix_input_yield_the_same_master_seed() {
        let entropy = [0x5cu8; 32];
        let canonical = entropy_to_mnemonic(&entropy);
        let expected = mnemonic_to_master_seed(&canonical).expect("canonical parses");

        let shouted: String = canonical.to_uppercase();
        assert_eq!(
            mnemonic_to_master_seed(&shouted).expect("uppercase parses"),
            expected
        );

        let clipped: Vec<String> = canonical
            .split_whitespace()
            .map(|w| w.chars().take(4).collect::<String>())
            .collect();
        assert_eq!(
            mnemonic_to_master_seed(&clipped.join(" ")).expect("prefixes parse"),
            expected
        );
    }

    #[test]
    fn ed25519_seed_differs_from_mldsa_node_for_same_master() {
        // libp2p transport identity must NOT collide with consensus node key
        let master = [0x33u8; 64];
        let libp2p = ed25519_seed_for_role(&master, domain::LIBP2P_TRANSPORT_KEY);
        let node = mldsa_seed_for_role(&master, domain::NODE_KEY);
        assert_ne!(libp2p[..], node[..]);
    }
}
