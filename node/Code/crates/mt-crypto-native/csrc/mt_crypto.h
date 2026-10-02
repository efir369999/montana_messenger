#ifndef MT_CRYPTO_H
#define MT_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#define MT_OK                            0
#define MT_ERR_INVALID_INPUT             1
#define MT_ERR_OPENSSL_INIT              2
#define MT_ERR_KEYGEN_FAILED             3
#define MT_ERR_SIGN_FAILED               4
#define MT_ERR_VERIFY_FAILED             5
#define MT_ERR_KAT_MISMATCH              6
#define MT_ERR_PARAM_QUERY_FAILED        7
#define MT_ERR_PARAM_SIZE_MISMATCH       8
#define MT_ERR_PARAM_FETCH_FAILED        9
#define MT_ERR_INVALID_SECRET_KEY       10
#define MT_ERR_INVALID_PUBLIC_KEY       11
#define MT_ERR_SIGN_LENGTH_MISMATCH     12

#define MT_MLDSA65_PUBKEY_SIZE     1952
#define MT_MLDSA65_SECRETKEY_SIZE  4032
#define MT_MLDSA65_SIGNATURE_SIZE  3309
#define MT_MLDSA65_SEED_SIZE         32

#define MT_MLKEM768_PUBKEY_SIZE    1184
#define MT_MLKEM768_SECRETKEY_SIZE 2400
#define MT_MLKEM768_SEED_SIZE        64
#define MT_MLKEM768_CIPHERTEXT_SIZE  1088
#define MT_MLKEM768_SS_SIZE            32

int mt_keypair_from_seed_mldsa(
    const uint8_t seed[MT_MLDSA65_SEED_SIZE],
    uint8_t pk_out[MT_MLDSA65_PUBKEY_SIZE],
    uint8_t sk_out[MT_MLDSA65_SECRETKEY_SIZE]
);

int mt_keypair_from_seed_mlkem(
    const uint8_t seed[MT_MLKEM768_SEED_SIZE],
    uint8_t pk_out[MT_MLKEM768_PUBKEY_SIZE],
    uint8_t sk_out[MT_MLKEM768_SECRETKEY_SIZE]
);

int mt_sign_mldsa(
    const uint8_t sk[MT_MLDSA65_SECRETKEY_SIZE],
    const uint8_t* msg, size_t msg_len,
    uint8_t sig_out[MT_MLDSA65_SIGNATURE_SIZE]
);

/* mt_sign_mldsa_ctx — FIPS 204 Algorithm 2 deterministic Sign с FIPS context.
 * Montana usage pattern: empty context (0-length) — equivalent к mt_sign_mldsa.
 * Non-empty context используется для NIST conformance testing с ACVP non-empty
 * context cases. ctx_len limit per FIPS 204: 255 bytes max. */
int mt_sign_mldsa_ctx(
    const uint8_t sk[MT_MLDSA65_SECRETKEY_SIZE],
    const uint8_t* msg, size_t msg_len,
    const uint8_t* ctx, size_t ctx_len,
    uint8_t sig_out[MT_MLDSA65_SIGNATURE_SIZE]
);

int mt_verify_mldsa(
    const uint8_t pk[MT_MLDSA65_PUBKEY_SIZE],
    const uint8_t* msg, size_t msg_len,
    const uint8_t sig[MT_MLDSA65_SIGNATURE_SIZE]
);

/* ML-KEM-768 encapsulate per FIPS 203 §6.2.
 * Takes a public key, produces (ciphertext, shared_secret). The shared
 * secret is the 32-byte derived key; the ciphertext is sent to the holder
 * of the secret key. */
int mt_mlkem_encapsulate(
    const uint8_t pk[MT_MLKEM768_PUBKEY_SIZE],
    uint8_t ct_out[MT_MLKEM768_CIPHERTEXT_SIZE],
    uint8_t ss_out[MT_MLKEM768_SS_SIZE]
);

/* ML-KEM-768 decapsulate per FIPS 203 §6.3.
 * Takes the secret key and a ciphertext, recovers the shared secret.
 * Implicit-rejection semantics: a malformed or substituted ciphertext
 * yields a pseudo-random shared secret indistinguishable from a valid
 * one to the caller; downstream handshake authentication MUST verify
 * an identity-bound MAC or signature to detect rejection. */
int mt_mlkem_decapsulate(
    const uint8_t sk[MT_MLKEM768_SECRETKEY_SIZE],
    const uint8_t ct[MT_MLKEM768_CIPHERTEXT_SIZE],
    uint8_t ss_out[MT_MLKEM768_SS_SIZE]
);

int mt_self_test(void);

#endif
