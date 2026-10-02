// Identity root of Montana: entropy, mnemonic, master seed and the per-role
// branches derived from it. Every client reaches this crate through mt-bindings;
// no application generates or derives identity material on its own.

pub type Hash32 = [u8; 32];

#[inline]
pub fn sha256_raw(bytes: &[u8]) -> Hash32 {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes).into()
}

mod bit_packing;
mod entropy;
mod fast;
mod hkdf;
mod hmac;
mod mnemonic;
mod pbkdf2;
mod sources;
mod wordlist;

pub use entropy::{
    combine_entropy, generate_entropy, generate_entropy_reporting, generate_mnemonic,
    health_check, self_test as entropy_self_test, MIN_LIVE_SOURCES, EntropyError, ENTROPY_LEN,
};
pub use sources::{measure_sources, SourceMeasure};

#[cfg(any(test, feature = "vectors"))]
pub use sources::{jitter_probe, survey, SourceFacts};
pub use fast::random_fast;
pub use hkdf::hkdf_expand;
pub use hmac::hmac_sha256;
// Ветви личности — строго постквантовые.
#[cfg(any(test, feature = "vectors"))]
pub use mnemonic::entropy_to_mnemonic;
pub use mnemonic::{
    mldsa_seed_for_role, mlkem_seed_for_role, mnemonic_to_entropy,
    mnemonic_to_master_seed, MnemonicError, KDF_ITER, MASTER_SEED_LEN, MLDSA_SEED_LEN,
    MLKEM_SEED_LEN, MNEMONIC_WORD_COUNT,
};
// [I-16] admission A-1: транспортная обёртка libp2p PeerId, НЕ личность Montana.
// Компрометация даёт класс помехи, а не вскрытие: личность, содержимое и сессия
// остаются на ML-DSA-65 / ML-KEM-768.
pub use mnemonic::{ed25519_seed_for_role, ED25519_SEED_LEN};
pub use pbkdf2::pbkdf2_hmac_sha256;
pub use sources::{clock_step_ns, gather, last_report, SourceReport, JITTER_ROUNDS, PROOF_SCALES, TICKS_PER_SAMPLE};
pub use wordlist::{word_index, wordlist, MIN_PREFIX_CHARS, WORDLIST_FINGERPRINT, WORDLIST_SIZE};
