/* mt_bindings.h -- Montana Protocol C ABI for iOS / macOS / Android.
 *
  * SSOT: single source of truth for Montana crypto/protocol.
  * Implementation: Rust crates (mt-mnemonic, mt-crypto, mt-state, mt-account).
 */

#ifndef MT_BINDINGS_H
#define MT_BINDINGS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MT_OK                              0
#define MT_ERR_NULL_PTR                   -1
#define MT_ERR_INVALID_UTF8               -2
#define MT_ERR_MNEMONIC_WORD_COUNT        -3
#define MT_ERR_MNEMONIC_UNKNOWN_WORD      -4
#define MT_ERR_MNEMONIC_CHECKSUM          -5
#define MT_ERR_KEYGEN_FAILED              -6
#define MT_ERR_SIGN_FAILED                -7
#define MT_ERR_VERIFY_FAILED              -8
#define MT_ERR_BUFFER_TOO_SMALL           -9
#define MT_ERR_ADDRESS_INVALID           -13
#define MT_ERR_IO                        -14
#define MT_ERR_DECODE                    -15
#define MT_ERR_CSPRNG                    -16
#define MT_ERR_ENTROPY_HEALTH            -17
#define MT_ERR_KEM_FAILED                -11
#define MT_ERR_REPLAY                    -12
#define MT_ERR_PANIC                    -100

#define MT_MASTER_SEED_LEN          64
#define MT_MLDSA_SEED_LEN           32
#define MT_MLDSA_PUBKEY_SIZE      1952
#define MT_MLDSA_SECKEY_SIZE      4032
#define MT_MLDSA_SIG_SIZE         3309
#define MT_ACCOUNT_ID_LEN           32
#define MT_SUITE_MLDSA65        0x0001
#define MT_MLKEM_SEED_LEN           64
#define MT_MLKEM_PUBKEY_SIZE      1184
#define MT_MLKEM_SECKEY_SIZE      2400
#define MT_MLKEM_CT_SIZE          1088
#define MT_MLKEM_SS_SIZE            32

uint32_t mt_abi_version(void);
int mt_mnemonic_to_master_seed(const char *mnemonic_utf8, uint8_t *out_master_seed);
int mt_mnemonic_to_entropy(const char *mnemonic_utf8, uint8_t *out_entropy);
int mt_mldsa_seed_for_role(const uint8_t *master_seed, const uint8_t *role, size_t role_len, uint8_t *out_seed);
int mt_mldsa_keypair_from_seed(const uint8_t *seed, uint8_t *out_pubkey, uint8_t *out_seckey);
/* 24 words -> the signing keys of the person (ML-DSA-65). Nothing that names the holder leaves here. */
int mt_seed_keys(const char *mnemonic_utf8, uint8_t *out_pubkey, uint8_t *out_seckey);
/* Transitional (one cycle of builds): the same keys plus the identifier the set abolished. */
int mt_account_from_mnemonic(const char *mnemonic_utf8, uint8_t *out_pubkey, uint8_t *out_seckey, uint8_t *out_account_id);
int mt_sign(const uint8_t *seckey, const uint8_t *msg, size_t msg_len, uint8_t *out_sig);
int mt_verify(const uint8_t *pubkey, const uint8_t *msg, size_t msg_len, const uint8_t *sig);

/* Fresh identity: health-tested OS entropy -> 24-word UTF-8 mnemonic (NUL-terminated).
   The only door through which a Montana identity is born; clients must not draw
   their own randomness. MT_ERR_CSPRNG (-16) when the OS has no entropy source,
   MT_ERR_ENTROPY_HEALTH (-17) when the block fails its health tests. */
int mt_generate_mnemonic(uint8_t *out_mnemonic_utf8, size_t out_capacity, size_t *out_len);

/* Measures of the seven entropy sources of this machine: 7 records of 7 bytes,
 * samples u16 LE | distinct u16 LE | max_repeat u16 LE | alive u8, in the order of the mixing.
 * No byte of any source leaves through this door — only the count of them. */
int mt_entropy_sources(uint8_t *out, size_t capacity, size_t *out_len);

/* How many sources must be alive before an identity may be born. */
int mt_entropy_min_live(void);
/* The last gather's report, 16 bytes: alive, os, jitter, memory, quartz, scheduler, timer, scale,
 * step_ns u32 LE, reserved u32. MT_ERR_IO before the first gather of the process. */
int mt_entropy_last_report(uint8_t *out, size_t capacity);

/* An identity is born ONLY here. The core draws it from four sources — the system CSPRNG,
   the processor instruction where it exists, the jitter of execution and the memory layout of
   this run — refuses when fewer than three are alive, and refuses when its self-test fails.
   No door accepts entropy from a caller: a client cannot supply a weak root even by mistake. */

/* ML-KEM-768 (FIPS 203) -- Stage 1 app_kem_key + Stages 4-7 key exchange. */
int mt_mlkem_seed_for_role(const uint8_t *master_seed, const uint8_t *role, size_t role_len, uint8_t *out_seed);
int mt_mlkem_keypair_from_seed(const uint8_t *seed, uint8_t *out_pubkey, uint8_t *out_seckey);
int mt_mlkem_encaps(const uint8_t *pubkey, uint8_t *out_ct, uint8_t *out_ss);
int mt_mlkem_decaps(const uint8_t *seckey, const uint8_t *ct, uint8_t *out_ss);
/* 24 words -> app_kem_key (ML-KEM-768, role "mt-app-encryption-key"). */
int mt_app_kem_from_mnemonic(const char *mnemonic_utf8, uint8_t *out_pubkey, uint8_t *out_seckey);
int mt_history_key(const uint8_t *entropy, uint8_t *out);

/* E2E engine (mt-messenger-e2e), Stage 6 hot path. Outputs are owned buffers,
  * release with mt_e2e_free(ptr,len). session is an opaque SessionState blob. */
void mt_e2e_free(uint8_t *ptr, size_t len);
int mt_e2e_encrypt(const uint8_t *session, size_t session_len,
                   const uint8_t *pt, size_t pt_len, const uint8_t *rng_seed,
                   uint8_t **out_session, size_t *out_session_len,
                   uint8_t **out_msg, size_t *out_msg_len);
int mt_e2e_decrypt(const uint8_t *session, size_t session_len,
                   const uint8_t *msg, size_t msg_len,
                   uint8_t **out_session, size_t *out_session_len,
                   uint8_t **out_pt, size_t *out_pt_len);
int mt_e2e_build_handshake(const uint8_t *alice_account_pub, const uint8_t *account_seed,
                           const uint8_t *bob_account_pub, const uint8_t *bob_app_kem_pub,
                           const uint8_t *bob_spk_pub, uint32_t spk_id, uint8_t opk_flag,
                           uint32_t opk_id, const uint8_t *bob_opk_pub, const uint8_t *eph_seed,
                           uint64_t send_time, uint8_t **out_hs, size_t *out_hs_len,
                           uint8_t **out_session, size_t *out_session_len);
int mt_e2e_process_handshake(const uint8_t *hs, size_t hs_len, const uint8_t *bob_account_id,
                             const uint8_t *bob_app_kem_pub, const uint8_t *bob_app_kem_sk,
                             const uint8_t *bob_spk_pub, const uint8_t *bob_spk_sk, uint8_t opk_flag,
                             const uint8_t *bob_opk_pub, const uint8_t *bob_opk_sk, uint64_t now,
                             uint64_t accept_skew, uint8_t **out_session, size_t *out_session_len);
int mt_e2e_seal_blob(const uint8_t *blob_key, const uint8_t *nonce, const uint8_t *input, size_t input_len, uint8_t **out_ptr, size_t *out_len);
int mt_e2e_blob_id(const uint8_t *sealed_blob, size_t len, uint8_t *out32);
int mt_e2e_open_blob(const uint8_t *blob_key, const uint8_t *sealed_blob, size_t len, uint8_t **out_ptr, size_t *out_len);
size_t mt_e2e_pad_len(size_t n);
int mt_e2e_safety_number(const uint8_t *id_a, const uint8_t *id_b, uint8_t **out_ptr, size_t *out_len);
int mt_e2e_party_code(const uint8_t *id, uint8_t **out_ptr, size_t *out_len);
int mt_e2e_call_key(const uint8_t *call_seed, uint8_t *out);   /* out = call_key(32) || sframe_key(32) */

/* Noise_PQ XX handshake (spec s.3 section 5.0). Opaque state handles keep secret keys in Rust.
   Wire sizes: msg1=2272, msg2=6349, msg3=5261. Session output: sk_i_to_r[32], sk_r_to_i[32],
   channel_hash[32]. node_id_seed = 32-byte ephemeral ML-DSA node identity seed. */
int mt_noise_initiator_msg1(const uint8_t *responder_kem_pk, const uint8_t *node_id_seed, uint8_t *out_msg1, void **out_state);
/* These three consume the handshake state UNCONDITIONALLY and set the caller's pointer
   to NULL on entry, including on every error path. A state passed here must never be
   handed to a free function afterwards: after the call there is nothing left to free,
   and the nulled pointer is what makes a double free impossible rather than forbidden. */
int mt_noise_initiator_msg2(void **state, const uint8_t *msg2, void **out_state2);
int mt_noise_initiator_msg3(void **state2, uint8_t *out_msg3, uint8_t *out_sk_i_to_r, uint8_t *out_sk_r_to_i, uint8_t *out_channel_hash);
int mt_noise_responder_msg1(const uint8_t *responder_kem_sk, const uint8_t *node_id_seed, const uint8_t *msg1, uint8_t *out_msg2, void **out_state);
int mt_noise_responder_msg3(void **state, const uint8_t *msg3, uint8_t *out_sk_i_to_r, uint8_t *out_sk_r_to_i, uint8_t *out_channel_hash);
void mt_noise_state_free_initiator1(void *state);
void mt_noise_state_free_initiator2(void *state);
void mt_noise_state_free_responder(void *state);

/* ── The plane of names ──────────────────────────────────────────────────────
 * Nine calls, all of them pure: normalization, the slot a name occupies, the
 * branch a chain is built from, a link of that chain, the commitment that takes
 * the slot, the verification of one link, the key a request is sealed to, the
 * puzzle a request answers, and the bucket a slot falls into. The logic lives in
 * mt-names and is never rewritten on the caller's side.
 */
int mt_name_normalize(const char *name_utf8, uint8_t *out, size_t out_cap, size_t *out_len);
int mt_name_slot(const char *normalized_utf8, uint8_t *out32);
int mt_name_own(const uint8_t *master_seed, size_t seed_len, const uint8_t *slot32, uint8_t *out32);
int mt_name_chain(const uint8_t *name_own32, uint8_t *out, size_t out_cap);
int mt_name_commit(const uint8_t *slot32, const uint8_t *blind32, const uint8_t *tip32, uint8_t *out32);

/* Fast source for values that live one frame: seeded by the same six-source gather,
   every draw absorbing a cheap quartz probe. Returns 0 on success. */
int mt_random_fast(uint8_t *out, size_t len);

int mt_name_contact_seed(const uint8_t *master_seed, size_t seed_len, const uint8_t *slot32, uint8_t *out64);
int mt_name_first_tag(const uint8_t *contact_root, size_t root_len, uint64_t window, uint8_t *out16);
int mt_name_first_secret(const uint8_t *ss, size_t ss_len, const uint8_t *contact_root, size_t root_len,
                         const uint8_t *ct, size_t ct_len, uint8_t *out32);
int mt_name_verify_link(const uint8_t *prev32, const uint8_t *link32);
int mt_name_req_key(const char *normalized_utf8, const uint8_t *eph_pk, size_t eph_len,
                    const uint8_t *slot32, uint8_t *out32);
int mt_name_puzzle(const uint8_t *slot32, const uint8_t *eph_pk, size_t eph_len,
                   const uint8_t *nonce, size_t nonce_len, uint8_t *out32);
int mt_name_bucket(const uint8_t *slot32, uint64_t occupied, uint64_t *out_bucket);

#ifdef __cplusplus
}
#endif

#endif
