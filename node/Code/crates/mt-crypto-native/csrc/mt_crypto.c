#include "mt_crypto.h"

#include <openssl/core_names.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/params.h>

#include <string.h>

static int extract_octet_param(
    EVP_PKEY* pkey,
    const char* param_name,
    uint8_t* out,
    size_t expected_len
) {
    size_t actual_len = 0;
    if (EVP_PKEY_get_octet_string_param(pkey, param_name, NULL, 0, &actual_len) != 1) {
        return MT_ERR_PARAM_QUERY_FAILED;
    }
    if (actual_len != expected_len) {
        return MT_ERR_PARAM_SIZE_MISMATCH;
    }
    if (EVP_PKEY_get_octet_string_param(pkey, param_name, out, expected_len, &actual_len) != 1) {
        return MT_ERR_PARAM_FETCH_FAILED;
    }
    if (actual_len != expected_len) {
        return MT_ERR_PARAM_SIZE_MISMATCH;
    }
    return MT_OK;
}

static int keypair_from_seed_generic(
    const char* alg_name,
    const char* seed_param_name,
    const uint8_t* seed,
    size_t seed_len,
    uint8_t* pk_out,
    size_t pk_len,
    uint8_t* sk_out,
    size_t sk_len
) {
    if (seed == NULL || pk_out == NULL || sk_out == NULL) {
        return MT_ERR_INVALID_INPUT;
    }

    int rc = MT_ERR_KEYGEN_FAILED;
    EVP_PKEY_CTX* ctx = NULL;
    EVP_PKEY* pkey = NULL;
    OSSL_PARAM params[2];

    ctx = EVP_PKEY_CTX_new_from_name(NULL, alg_name, NULL);
    if (ctx == NULL) {
        rc = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    if (EVP_PKEY_keygen_init(ctx) != 1) {
        goto cleanup;
    }

    /*
     * OpenSSL EVP convention: OSSL_PARAM_construct_octet_string takes (void*)
     * для backwards compat с pre-const-correct C API; OSSL_PARAM_set_*
     * семантически НЕ модифицирует input — bytes только читаются для
     * передачи в KeyGen / Sign / fromdata. Cast (void*)seed — convention,
     * не actual mutation. Same pattern на всех 4 octet_string call sites.
     */
    params[0] = OSSL_PARAM_construct_octet_string(
        seed_param_name, (void*)seed, seed_len
    );
    params[1] = OSSL_PARAM_construct_end();

    if (EVP_PKEY_CTX_set_params(ctx, params) != 1) {
        goto cleanup;
    }

    if (EVP_PKEY_generate(ctx, &pkey) != 1) {
        goto cleanup;
    }
    if (pkey == NULL) {
        goto cleanup;
    }

    rc = extract_octet_param(pkey, OSSL_PKEY_PARAM_PUB_KEY, pk_out, pk_len);
    if (rc != MT_OK) {
        goto cleanup;
    }

    rc = extract_octet_param(pkey, OSSL_PKEY_PARAM_PRIV_KEY, sk_out, sk_len);
    if (rc != MT_OK) {
        goto cleanup;
    }

    rc = MT_OK;

cleanup:
    if (pkey != NULL) {
        EVP_PKEY_free(pkey);
    }
    if (ctx != NULL) {
        EVP_PKEY_CTX_free(ctx);
    }
    return rc;
}

int mt_keypair_from_seed_mldsa(
    const uint8_t seed[MT_MLDSA65_SEED_SIZE],
    uint8_t pk_out[MT_MLDSA65_PUBKEY_SIZE],
    uint8_t sk_out[MT_MLDSA65_SECRETKEY_SIZE]
) {
    return keypair_from_seed_generic(
        "ML-DSA-65",
        OSSL_PKEY_PARAM_ML_DSA_SEED,
        seed,
        MT_MLDSA65_SEED_SIZE,
        pk_out,
        MT_MLDSA65_PUBKEY_SIZE,
        sk_out,
        MT_MLDSA65_SECRETKEY_SIZE
    );
}

int mt_keypair_from_seed_mlkem(
    const uint8_t seed[MT_MLKEM768_SEED_SIZE],
    uint8_t pk_out[MT_MLKEM768_PUBKEY_SIZE],
    uint8_t sk_out[MT_MLKEM768_SECRETKEY_SIZE]
) {
    return keypair_from_seed_generic(
        "ML-KEM-768",
        OSSL_PKEY_PARAM_ML_KEM_SEED,
        seed,
        MT_MLKEM768_SEED_SIZE,
        pk_out,
        MT_MLKEM768_PUBKEY_SIZE,
        sk_out,
        MT_MLKEM768_SECRETKEY_SIZE
    );
}

static EVP_PKEY* mldsa_pkey_from_secret(
    const uint8_t* sk,
    size_t sk_len
) {
    EVP_PKEY_CTX* ctx = NULL;
    EVP_PKEY* pkey = NULL;
    OSSL_PARAM params[2];

    ctx = EVP_PKEY_CTX_new_from_name(NULL, "ML-DSA-65", NULL);
    if (ctx == NULL) {
        return NULL;
    }

    if (EVP_PKEY_fromdata_init(ctx) != 1) {
        goto fail;
    }

    /* OpenSSL EVP convention: (void*)sk — backwards compat cast, не mutation
     * (см. extended comment в keypair_from_seed_generic). */
    params[0] = OSSL_PARAM_construct_octet_string(
        OSSL_PKEY_PARAM_PRIV_KEY, (void*)sk, sk_len
    );
    params[1] = OSSL_PARAM_construct_end();

    if (EVP_PKEY_fromdata(ctx, &pkey, EVP_PKEY_KEYPAIR, params) != 1) {
        pkey = NULL;
        goto fail;
    }

fail:
    EVP_PKEY_CTX_free(ctx);
    return pkey;
}

static EVP_PKEY* mldsa_pkey_from_public(
    const uint8_t* pk,
    size_t pk_len
) {
    EVP_PKEY_CTX* ctx = NULL;
    EVP_PKEY* pkey = NULL;
    OSSL_PARAM params[2];

    ctx = EVP_PKEY_CTX_new_from_name(NULL, "ML-DSA-65", NULL);
    if (ctx == NULL) {
        return NULL;
    }

    if (EVP_PKEY_fromdata_init(ctx) != 1) {
        goto fail;
    }

    /* OpenSSL EVP convention: (void*)pk — backwards compat cast, не mutation
     * (см. extended comment в keypair_from_seed_generic). */
    params[0] = OSSL_PARAM_construct_octet_string(
        OSSL_PKEY_PARAM_PUB_KEY, (void*)pk, pk_len
    );
    params[1] = OSSL_PARAM_construct_end();

    if (EVP_PKEY_fromdata(ctx, &pkey, EVP_PKEY_PUBLIC_KEY, params) != 1) {
        pkey = NULL;
        goto fail;
    }

fail:
    EVP_PKEY_CTX_free(ctx);
    return pkey;
}

int mt_sign_mldsa(
    const uint8_t sk[MT_MLDSA65_SECRETKEY_SIZE],
    const uint8_t* msg,
    size_t msg_len,
    uint8_t sig_out[MT_MLDSA65_SIGNATURE_SIZE]
) {
    if (sk == NULL || sig_out == NULL || (msg == NULL && msg_len != 0)) {
        return MT_ERR_INVALID_INPUT;
    }

    int rc = MT_ERR_SIGN_FAILED;
    EVP_PKEY* pkey = NULL;
    EVP_MD_CTX* md_ctx = NULL;
    OSSL_PARAM sig_params[2];
    int deterministic = 1;

    pkey = mldsa_pkey_from_secret(sk, MT_MLDSA65_SECRETKEY_SIZE);
    if (pkey == NULL) {
        rc = MT_ERR_INVALID_SECRET_KEY;
        goto cleanup;
    }

    md_ctx = EVP_MD_CTX_new();
    if (md_ctx == NULL) {
        rc = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    sig_params[0] = OSSL_PARAM_construct_int(
        OSSL_SIGNATURE_PARAM_DETERMINISTIC, &deterministic
    );
    sig_params[1] = OSSL_PARAM_construct_end();

    if (EVP_DigestSignInit_ex(md_ctx, NULL, NULL, NULL, NULL, pkey, sig_params) != 1) {
        rc = MT_ERR_SIGN_FAILED;
        goto cleanup;
    }

    size_t sig_len = MT_MLDSA65_SIGNATURE_SIZE;
    if (EVP_DigestSign(md_ctx, sig_out, &sig_len, msg, msg_len) != 1) {
        rc = MT_ERR_SIGN_FAILED;
        goto cleanup;
    }
    if (sig_len != MT_MLDSA65_SIGNATURE_SIZE) {
        rc = MT_ERR_SIGN_LENGTH_MISMATCH;
        goto cleanup;
    }

    rc = MT_OK;

cleanup:
    if (md_ctx != NULL) {
        EVP_MD_CTX_free(md_ctx);
    }
    if (pkey != NULL) {
        EVP_PKEY_free(pkey);
    }
    return rc;
}

int mt_sign_mldsa_ctx(
    const uint8_t sk[MT_MLDSA65_SECRETKEY_SIZE],
    const uint8_t* msg, size_t msg_len,
    const uint8_t* ctx, size_t ctx_len,
    uint8_t sig_out[MT_MLDSA65_SIGNATURE_SIZE]
) {
    if (sk == NULL || sig_out == NULL || (msg == NULL && msg_len != 0)
        || (ctx == NULL && ctx_len != 0)) {
        return MT_ERR_INVALID_INPUT;
    }
    /* FIPS 204: context length max 255 bytes. */
    if (ctx_len > 255) {
        return MT_ERR_INVALID_INPUT;
    }

    int rc = MT_ERR_SIGN_FAILED;
    EVP_PKEY* pkey = NULL;
    EVP_MD_CTX* md_ctx = NULL;
    OSSL_PARAM sig_params[3];
    int deterministic = 1;

    pkey = mldsa_pkey_from_secret(sk, MT_MLDSA65_SECRETKEY_SIZE);
    if (pkey == NULL) {
        rc = MT_ERR_INVALID_SECRET_KEY;
        goto cleanup;
    }

    md_ctx = EVP_MD_CTX_new();
    if (md_ctx == NULL) {
        rc = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    sig_params[0] = OSSL_PARAM_construct_int(
        OSSL_SIGNATURE_PARAM_DETERMINISTIC, &deterministic
    );
    /* OpenSSL EVP convention: (void*)ctx — backwards compat cast, не mutation
     * (см. extended comment в keypair_from_seed_generic). FIPS 204 ctx_len ≤ 255
     * проверен выше (line 268-270). */
    sig_params[1] = OSSL_PARAM_construct_octet_string(
        OSSL_SIGNATURE_PARAM_CONTEXT_STRING, (void*)ctx, ctx_len
    );
    sig_params[2] = OSSL_PARAM_construct_end();

    if (EVP_DigestSignInit_ex(md_ctx, NULL, NULL, NULL, NULL, pkey, sig_params) != 1) {
        rc = MT_ERR_SIGN_FAILED;
        goto cleanup;
    }

    size_t sig_len = MT_MLDSA65_SIGNATURE_SIZE;
    if (EVP_DigestSign(md_ctx, sig_out, &sig_len, msg, msg_len) != 1) {
        rc = MT_ERR_SIGN_FAILED;
        goto cleanup;
    }
    if (sig_len != MT_MLDSA65_SIGNATURE_SIZE) {
        rc = MT_ERR_SIGN_LENGTH_MISMATCH;
        goto cleanup;
    }

    rc = MT_OK;

cleanup:
    if (md_ctx != NULL) {
        EVP_MD_CTX_free(md_ctx);
    }
    if (pkey != NULL) {
        EVP_PKEY_free(pkey);
    }
    return rc;
}

int mt_verify_mldsa(
    const uint8_t pk[MT_MLDSA65_PUBKEY_SIZE],
    const uint8_t* msg,
    size_t msg_len,
    const uint8_t sig[MT_MLDSA65_SIGNATURE_SIZE]
) {
    if (pk == NULL || sig == NULL || (msg == NULL && msg_len != 0)) {
        return MT_ERR_INVALID_INPUT;
    }

    int rc = MT_ERR_VERIFY_FAILED;
    EVP_PKEY* pkey = NULL;
    EVP_MD_CTX* md_ctx = NULL;

    pkey = mldsa_pkey_from_public(pk, MT_MLDSA65_PUBKEY_SIZE);
    if (pkey == NULL) {
        rc = MT_ERR_INVALID_PUBLIC_KEY;
        goto cleanup;
    }

    md_ctx = EVP_MD_CTX_new();
    if (md_ctx == NULL) {
        rc = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    if (EVP_DigestVerifyInit_ex(md_ctx, NULL, NULL, NULL, NULL, pkey, NULL) != 1) {
        rc = MT_ERR_VERIFY_FAILED;
        goto cleanup;
    }

    int verify_rc = EVP_DigestVerify(md_ctx, sig, MT_MLDSA65_SIGNATURE_SIZE, msg, msg_len);
    if (verify_rc == 1) {
        rc = MT_OK;
    } else {
        rc = MT_ERR_VERIFY_FAILED;
    }

cleanup:
    if (md_ctx != NULL) {
        EVP_MD_CTX_free(md_ctx);
    }
    if (pkey != NULL) {
        EVP_PKEY_free(pkey);
    }
    return rc;
}

/* Build an ML-KEM-768 EVP_PKEY from a raw public key. */
static EVP_PKEY* mlkem_pkey_from_public(
    const uint8_t* pk,
    size_t pk_len
) {
    EVP_PKEY_CTX* ctx = NULL;
    EVP_PKEY* pkey = NULL;
    OSSL_PARAM params[2];

    ctx = EVP_PKEY_CTX_new_from_name(NULL, "ML-KEM-768", NULL);
    if (ctx == NULL) {
        return NULL;
    }

    if (EVP_PKEY_fromdata_init(ctx) != 1) {
        goto fail;
    }

    /* OpenSSL EVP convention: (void*)pk — backwards compat cast, not mutation. */
    params[0] = OSSL_PARAM_construct_octet_string(
        OSSL_PKEY_PARAM_PUB_KEY, (void*)pk, pk_len
    );
    params[1] = OSSL_PARAM_construct_end();

    if (EVP_PKEY_fromdata(ctx, &pkey, EVP_PKEY_PUBLIC_KEY, params) != 1) {
        pkey = NULL;
        goto fail;
    }

fail:
    EVP_PKEY_CTX_free(ctx);
    return pkey;
}

/* Build an ML-KEM-768 EVP_PKEY from a raw secret key. */
static EVP_PKEY* mlkem_pkey_from_secret(
    const uint8_t* sk,
    size_t sk_len
) {
    EVP_PKEY_CTX* ctx = NULL;
    EVP_PKEY* pkey = NULL;
    OSSL_PARAM params[2];

    ctx = EVP_PKEY_CTX_new_from_name(NULL, "ML-KEM-768", NULL);
    if (ctx == NULL) {
        return NULL;
    }

    if (EVP_PKEY_fromdata_init(ctx) != 1) {
        goto fail;
    }

    params[0] = OSSL_PARAM_construct_octet_string(
        OSSL_PKEY_PARAM_PRIV_KEY, (void*)sk, sk_len
    );
    params[1] = OSSL_PARAM_construct_end();

    if (EVP_PKEY_fromdata(ctx, &pkey, EVP_PKEY_KEYPAIR, params) != 1) {
        pkey = NULL;
        goto fail;
    }

fail:
    EVP_PKEY_CTX_free(ctx);
    return pkey;
}

int mt_mlkem_encapsulate(
    const uint8_t pk[MT_MLKEM768_PUBKEY_SIZE],
    uint8_t ct_out[MT_MLKEM768_CIPHERTEXT_SIZE],
    uint8_t ss_out[MT_MLKEM768_SS_SIZE]
) {
    EVP_PKEY* pkey = NULL;
    EVP_PKEY_CTX* ctx = NULL;
    int ret = MT_ERR_KEYGEN_FAILED;
    size_t ct_len = MT_MLKEM768_CIPHERTEXT_SIZE;
    size_t ss_len = MT_MLKEM768_SS_SIZE;

    if (pk == NULL || ct_out == NULL || ss_out == NULL) {
        return MT_ERR_INVALID_INPUT;
    }

    pkey = mlkem_pkey_from_public(pk, MT_MLKEM768_PUBKEY_SIZE);
    if (pkey == NULL) {
        return MT_ERR_INVALID_PUBLIC_KEY;
    }

    ctx = EVP_PKEY_CTX_new_from_pkey(NULL, pkey, NULL);
    if (ctx == NULL) {
        ret = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    if (EVP_PKEY_encapsulate_init(ctx, NULL) != 1) {
        ret = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    if (EVP_PKEY_encapsulate(ctx, ct_out, &ct_len, ss_out, &ss_len) != 1) {
        ret = MT_ERR_KEYGEN_FAILED;
        goto cleanup;
    }

    if (ct_len != MT_MLKEM768_CIPHERTEXT_SIZE || ss_len != MT_MLKEM768_SS_SIZE) {
        ret = MT_ERR_PARAM_SIZE_MISMATCH;
        goto cleanup;
    }

    ret = MT_OK;

cleanup:
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    return ret;
}

int mt_mlkem_decapsulate(
    const uint8_t sk[MT_MLKEM768_SECRETKEY_SIZE],
    const uint8_t ct[MT_MLKEM768_CIPHERTEXT_SIZE],
    uint8_t ss_out[MT_MLKEM768_SS_SIZE]
) {
    EVP_PKEY* pkey = NULL;
    EVP_PKEY_CTX* ctx = NULL;
    int ret = MT_ERR_KEYGEN_FAILED;
    size_t ss_len = MT_MLKEM768_SS_SIZE;

    if (sk == NULL || ct == NULL || ss_out == NULL) {
        return MT_ERR_INVALID_INPUT;
    }

    pkey = mlkem_pkey_from_secret(sk, MT_MLKEM768_SECRETKEY_SIZE);
    if (pkey == NULL) {
        return MT_ERR_INVALID_SECRET_KEY;
    }

    ctx = EVP_PKEY_CTX_new_from_pkey(NULL, pkey, NULL);
    if (ctx == NULL) {
        ret = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    if (EVP_PKEY_decapsulate_init(ctx, NULL) != 1) {
        ret = MT_ERR_OPENSSL_INIT;
        goto cleanup;
    }

    if (EVP_PKEY_decapsulate(ctx, ss_out, &ss_len, ct, MT_MLKEM768_CIPHERTEXT_SIZE) != 1) {
        ret = MT_ERR_KEYGEN_FAILED;
        goto cleanup;
    }

    if (ss_len != MT_MLKEM768_SS_SIZE) {
        ret = MT_ERR_PARAM_SIZE_MISMATCH;
        goto cleanup;
    }

    ret = MT_OK;

cleanup:
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    return ret;
}

int mt_self_test(void) {
    uint8_t mldsa_seed[MT_MLDSA65_SEED_SIZE] = {0};
    uint8_t mldsa_pk[MT_MLDSA65_PUBKEY_SIZE];
    uint8_t mldsa_sk[MT_MLDSA65_SECRETKEY_SIZE];
    uint8_t mldsa_pk2[MT_MLDSA65_PUBKEY_SIZE];
    uint8_t mldsa_sk2[MT_MLDSA65_SECRETKEY_SIZE];

    int rc = mt_keypair_from_seed_mldsa(mldsa_seed, mldsa_pk, mldsa_sk);
    if (rc != MT_OK) {
        return rc;
    }
    rc = mt_keypair_from_seed_mldsa(mldsa_seed, mldsa_pk2, mldsa_sk2);
    if (rc != MT_OK) {
        return rc;
    }
    if (memcmp(mldsa_pk, mldsa_pk2, MT_MLDSA65_PUBKEY_SIZE) != 0) {
        OPENSSL_cleanse(mldsa_sk, sizeof(mldsa_sk));
        OPENSSL_cleanse(mldsa_sk2, sizeof(mldsa_sk2));
        return MT_ERR_KAT_MISMATCH;
    }
    if (memcmp(mldsa_sk, mldsa_sk2, MT_MLDSA65_SECRETKEY_SIZE) != 0) {
        OPENSSL_cleanse(mldsa_sk, sizeof(mldsa_sk));
        OPENSSL_cleanse(mldsa_sk2, sizeof(mldsa_sk2));
        return MT_ERR_KAT_MISMATCH;
    }

    static const uint8_t test_msg[] = {0x01, 0x02, 0x03, 0x04};
    uint8_t sig[MT_MLDSA65_SIGNATURE_SIZE];
    rc = mt_sign_mldsa(mldsa_sk, test_msg, sizeof(test_msg), sig);
    if (rc != MT_OK) {
        return rc;
    }
    rc = mt_verify_mldsa(mldsa_pk, test_msg, sizeof(test_msg), sig);
    if (rc != MT_OK) {
        return rc;
    }

    uint8_t sig2[MT_MLDSA65_SIGNATURE_SIZE];
    rc = mt_sign_mldsa(mldsa_sk, test_msg, sizeof(test_msg), sig2);
    if (rc != MT_OK) {
        return rc;
    }
    if (memcmp(sig, sig2, MT_MLDSA65_SIGNATURE_SIZE) != 0) {
        return MT_ERR_KAT_MISMATCH;
    }

    static const uint8_t bad_msg[] = {0x01, 0x02, 0x03, 0x05};
    rc = mt_verify_mldsa(mldsa_pk, bad_msg, sizeof(bad_msg), sig);
    if (rc == MT_OK) {
        return MT_ERR_KAT_MISMATCH;
    }

    uint8_t mlkem_seed[MT_MLKEM768_SEED_SIZE] = {0};
    uint8_t mlkem_pk[MT_MLKEM768_PUBKEY_SIZE];
    uint8_t mlkem_sk[MT_MLKEM768_SECRETKEY_SIZE];
    uint8_t mlkem_pk2[MT_MLKEM768_PUBKEY_SIZE];
    uint8_t mlkem_sk2[MT_MLKEM768_SECRETKEY_SIZE];

    rc = mt_keypair_from_seed_mlkem(mlkem_seed, mlkem_pk, mlkem_sk);
    if (rc != MT_OK) {
        return rc;
    }
    rc = mt_keypair_from_seed_mlkem(mlkem_seed, mlkem_pk2, mlkem_sk2);
    if (rc != MT_OK) {
        return rc;
    }
    if (memcmp(mlkem_pk, mlkem_pk2, MT_MLKEM768_PUBKEY_SIZE) != 0) {
        return MT_ERR_KAT_MISMATCH;
    }
    if (memcmp(mlkem_sk, mlkem_sk2, MT_MLKEM768_SECRETKEY_SIZE) != 0) {
        OPENSSL_cleanse(mldsa_sk, sizeof(mldsa_sk));
        OPENSSL_cleanse(mldsa_sk2, sizeof(mldsa_sk2));
        OPENSSL_cleanse(mlkem_sk, sizeof(mlkem_sk));
        OPENSSL_cleanse(mlkem_sk2, sizeof(mlkem_sk2));
        return MT_ERR_KAT_MISMATCH;
    }

    /* Zeroise every stack-resident secret-key buffer before returning so the
       stack frame does not retain ML-DSA-65 / ML-KEM-768 secret bytes. The KAT
       in this self-test uses seed = {0}, so the secrets are public-derivable,
       but the discipline holds for the day this routine accepts an operator-
       supplied seed. */
    OPENSSL_cleanse(mldsa_sk, sizeof(mldsa_sk));
    OPENSSL_cleanse(mldsa_sk2, sizeof(mldsa_sk2));
    OPENSSL_cleanse(mlkem_sk, sizeof(mlkem_sk));
    OPENSSL_cleanse(mlkem_sk2, sizeof(mlkem_sk2));
    return MT_OK;
}
