//! Stage 1 (unified crypto profile) -- terminal ML-KEM-768 vectors through the real C ABI.
//! Integration test (links the rlib, full stack) -- heavy crypto does not go into the lib unit test of the
//! cdylib/staticlib target (trimmed stack + linked OpenSSL).

use sha2::{Digest, Sha256};
use std::ffi::CString;

const MLKEM_SEED_LEN: usize = 64;
const MLKEM_PUBKEY_SIZE: usize = 1184;
const MLKEM_SECKEY_SIZE: usize = 2400;
const MLKEM_CT_SIZE: usize = 1088;
const MLKEM_SS_SIZE: usize = 32;

use mt_bindings::ffi_c::{
    mt_app_kem_from_mnemonic, mt_mlkem_decaps, mt_mlkem_encaps, mt_mlkem_keypair_from_seed,
};

/// Stage 1 terminal vector: app_kem_pub from the zero mnemonic.
/// Montana Messenger spec v0.40.0: SHA-256(app_kem_pub) = b827d3…
#[test]
fn app_kem_terminal_vector() {
    let m = mt_mnemonic::entropy_to_mnemonic(&[0u8; 32]);
    let mc = CString::new(m).unwrap();
    let mut pk = vec![0u8; MLKEM_PUBKEY_SIZE];
    let mut sk = vec![0u8; MLKEM_SECKEY_SIZE];
    let rc = unsafe { mt_app_kem_from_mnemonic(mc.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) };
    assert_eq!(rc, 0);
    let hex = Sha256::digest(&pk)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    assert_eq!(
        hex,
        "b827d37b2b225907c835f25a8652c215af69f8f52bd6a7ef0ae31955d63fd1c4"
    );
}

/// Encaps→Decaps through the C ABI: the shared secret matches on both sides (FIPS 203).
#[test]
fn encaps_decaps_roundtrip_ffi() {
    let seed = [0x55u8; MLKEM_SEED_LEN];
    let mut pk = vec![0u8; MLKEM_PUBKEY_SIZE];
    let mut sk = vec![0u8; MLKEM_SECKEY_SIZE];
    assert_eq!(
        unsafe { mt_mlkem_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) },
        0
    );
    let mut ct = vec![0u8; MLKEM_CT_SIZE];
    let mut ss_a = vec![0u8; MLKEM_SS_SIZE];
    assert_eq!(
        unsafe { mt_mlkem_encaps(pk.as_ptr(), ct.as_mut_ptr(), ss_a.as_mut_ptr()) },
        0
    );
    let mut ss_b = vec![0u8; MLKEM_SS_SIZE];
    assert_eq!(
        unsafe { mt_mlkem_decaps(sk.as_ptr(), ct.as_ptr(), ss_b.as_mut_ptr()) },
        0
    );
    assert_eq!(ss_a, ss_b);
}
