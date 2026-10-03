#![allow(non_snake_case)]

use libc::{c_int, size_t};

// [C-1] EXEMPT — FFI boundary constants.
//
// mt-crypto-native — sub-FFI crate которым пользуется mt-crypto. Чтобы избежать
// циклической зависимости (mt-crypto уже импортирует mt-crypto-native), эти
// размеры дублируются здесь как primary FFI contract значения. Authoritative
// SSOT для остального workspace остаётся mt_crypto::{PUBLIC_KEY_SIZE,
// SECRET_KEY_SIZE, SIGNATURE_SIZE, KEYPAIR_SEED_SIZE, MLKEM_*}.
//
// Sync проверяется regression-тестом mt_crypto_native_consts_match в
// crates/mt-crypto/tests/native_consts_sync.rs — расхождение даёт failing
// build.
pub const MLDSA65_PUBKEY_SIZE: usize = 1952;
pub const MLDSA65_SECRETKEY_SIZE: usize = 4032;
pub const MLDSA65_SIGNATURE_SIZE: usize = 3309;
pub const MLDSA65_SEED_SIZE: usize = 32;

pub const MLKEM768_PUBKEY_SIZE: usize = 1184;
pub const MLKEM768_SECRETKEY_SIZE: usize = 2400;
pub const MLKEM768_SEED_SIZE: usize = 64;
pub const MLKEM768_CIPHERTEXT_SIZE: usize = 1088;
pub const MLKEM768_SS_SIZE: usize = 32;

pub const MT_OK: c_int = 0;
pub const MT_ERR_INVALID_INPUT: c_int = 1;
pub const MT_ERR_OPENSSL_INIT: c_int = 2;
pub const MT_ERR_KEYGEN_FAILED: c_int = 3;
pub const MT_ERR_SIGN_FAILED: c_int = 4;
pub const MT_ERR_VERIFY_FAILED: c_int = 5;
pub const MT_ERR_KAT_MISMATCH: c_int = 6;
pub const MT_ERR_PARAM_QUERY_FAILED: c_int = 7;
pub const MT_ERR_PARAM_SIZE_MISMATCH: c_int = 8;
pub const MT_ERR_PARAM_FETCH_FAILED: c_int = 9;
pub const MT_ERR_INVALID_SECRET_KEY: c_int = 10;
pub const MT_ERR_INVALID_PUBLIC_KEY: c_int = 11;
pub const MT_ERR_SIGN_LENGTH_MISMATCH: c_int = 12;

extern "C" {
    pub fn mt_keypair_from_seed_mldsa(seed: *const u8, pk_out: *mut u8, sk_out: *mut u8) -> c_int;

    pub fn mt_keypair_from_seed_mlkem(seed: *const u8, pk_out: *mut u8, sk_out: *mut u8) -> c_int;

    pub fn mt_sign_mldsa(sk: *const u8, msg: *const u8, msg_len: size_t, sig_out: *mut u8)
        -> c_int;

    pub fn mt_sign_mldsa_ctx(
        sk: *const u8,
        msg: *const u8,
        msg_len: size_t,
        ctx: *const u8,
        ctx_len: size_t,
        sig_out: *mut u8,
    ) -> c_int;

    pub fn mt_verify_mldsa(pk: *const u8, msg: *const u8, msg_len: size_t, sig: *const u8)
        -> c_int;

    pub fn mt_mlkem_encapsulate(pk: *const u8, ct_out: *mut u8, ss_out: *mut u8) -> c_int;

    pub fn mt_mlkem_decapsulate(sk: *const u8, ct: *const u8, ss_out: *mut u8) -> c_int;

    pub fn mt_self_test() -> c_int;
}
