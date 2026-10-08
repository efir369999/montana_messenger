// Regression test for the [C-1] EXEMPT FFI boundary constants.
//
// mt-crypto-native declares the MLDSA65_* / MLKEM768_* sizes as the primary FFI
// contract. mt-crypto is the authoritative SSOT for the rest of the workspace. This test
// checks byte-exact equality on every build -- drift = failing build.

use mt_crypto::{
    KEYPAIR_SEED_SIZE, MLKEM_PUBLIC_KEY_SIZE, MLKEM_SECRET_KEY_SIZE, MLKEM_SEED_SIZE,
    PUBLIC_KEY_SIZE, SECRET_KEY_SIZE, SIGNATURE_SIZE,
};

#[test]
fn mt_crypto_native_consts_match_mt_crypto() {
    assert_eq!(
        mt_crypto_native::MLDSA65_PUBKEY_SIZE,
        PUBLIC_KEY_SIZE,
        "FFI MLDSA65_PUBKEY_SIZE drift vs mt_crypto::PUBLIC_KEY_SIZE"
    );
    assert_eq!(
        mt_crypto_native::MLDSA65_SECRETKEY_SIZE,
        SECRET_KEY_SIZE,
        "FFI MLDSA65_SECRETKEY_SIZE drift vs mt_crypto::SECRET_KEY_SIZE"
    );
    assert_eq!(
        mt_crypto_native::MLDSA65_SIGNATURE_SIZE,
        SIGNATURE_SIZE,
        "FFI MLDSA65_SIGNATURE_SIZE drift vs mt_crypto::SIGNATURE_SIZE"
    );
    assert_eq!(
        mt_crypto_native::MLDSA65_SEED_SIZE,
        KEYPAIR_SEED_SIZE,
        "FFI MLDSA65_SEED_SIZE drift vs mt_crypto::KEYPAIR_SEED_SIZE"
    );
    assert_eq!(
        mt_crypto_native::MLKEM768_PUBKEY_SIZE,
        MLKEM_PUBLIC_KEY_SIZE,
        "FFI MLKEM768_PUBKEY_SIZE drift vs mt_crypto::MLKEM_PUBLIC_KEY_SIZE"
    );
    assert_eq!(
        mt_crypto_native::MLKEM768_SECRETKEY_SIZE,
        MLKEM_SECRET_KEY_SIZE,
        "FFI MLKEM768_SECRETKEY_SIZE drift vs mt_crypto::MLKEM_SECRET_KEY_SIZE"
    );
    assert_eq!(
        mt_crypto_native::MLKEM768_SEED_SIZE,
        MLKEM_SEED_SIZE,
        "FFI MLKEM768_SEED_SIZE drift vs mt_crypto::MLKEM_SEED_SIZE"
    );
}
