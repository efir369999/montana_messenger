//! C-ABI surface — shared by the iOS staticlib and the Android cdylib.
//!
//! All functions return an i32 status code. Output buffers are caller-supplied,
//! of fixed length documented in `mt_bindings.h`.

// Safety contracts (buffer sizes, non-null pointers) are documented in mt_bindings.h.
#![allow(clippy::missing_safety_doc)]

use core::slice;
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, mlkem_decapsulate, mlkem_encapsulate,
    sign as mldsa_sign, verify as mldsa_verify, MlkemCiphertext, MlkemPublicKey, MlkemSecretKey,
    PublicKey, SecretKey, Signature,
};
use mt_mnemonic::{
    mldsa_seed_for_role, mlkem_seed_for_role, mnemonic_to_entropy, mnemonic_to_master_seed,
};
use mt_state::derive_account_id;
use zeroize::Zeroizing;

use super::*;

/// Canonical suite_id for the ML-DSA-65 account keypair (spec §Suite registry).
pub const MT_SUITE_MLDSA65: u16 = 0x0001;

#[no_mangle]
pub extern "C" fn mt_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn mt_mnemonic_to_master_seed(
    mnemonic_utf8: *const c_char,
    out_master_seed: *mut u8,
) -> c_int {
    guard(|| {
        if mnemonic_utf8.is_null() || out_master_seed.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let cs = match CStr::from_ptr(mnemonic_utf8).to_str() {
            Ok(s) => s,
            Err(_) => return MT_ERR_INVALID_UTF8,
        };
        match mnemonic_to_master_seed(cs) {
            Ok(seed) => {
                slice::from_raw_parts_mut(out_master_seed, MT_MASTER_SEED_LEN)
                    .copy_from_slice(&seed[..]);
                MT_OK
            },
            Err(e) => match e {
                mt_mnemonic::MnemonicError::WordCount(_) => MT_ERR_MNEMONIC_WORD_COUNT,
                mt_mnemonic::MnemonicError::UnknownWord(_) => MT_ERR_MNEMONIC_UNKNOWN_WORD,
                mt_mnemonic::MnemonicError::ChecksumMismatch => MT_ERR_MNEMONIC_CHECKSUM,
            },
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_mnemonic_to_entropy(
    mnemonic_utf8: *const c_char,
    out_entropy: *mut u8,
) -> c_int {
    guard(|| {
        if mnemonic_utf8.is_null() || out_entropy.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let cs = match CStr::from_ptr(mnemonic_utf8).to_str() {
            Ok(s) => s,
            Err(_) => return MT_ERR_INVALID_UTF8,
        };
        match mnemonic_to_entropy(cs) {
            Ok(ent) => {
                slice::from_raw_parts_mut(out_entropy, 32).copy_from_slice(&ent[..]);
                MT_OK
            },
            Err(e) => match e {
                mt_mnemonic::MnemonicError::WordCount(_) => MT_ERR_MNEMONIC_WORD_COUNT,
                mt_mnemonic::MnemonicError::UnknownWord(_) => MT_ERR_MNEMONIC_UNKNOWN_WORD,
                mt_mnemonic::MnemonicError::ChecksumMismatch => MT_ERR_MNEMONIC_CHECKSUM,
            },
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_mldsa_seed_for_role(
    master_seed: *const u8,
    role: *const u8,
    role_len: usize,
    out_seed: *mut u8,
) -> c_int {
    guard(|| {
        if master_seed.is_null() || role.is_null() || out_seed.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut master_arr = Zeroizing::new([0u8; MT_MASTER_SEED_LEN]);
        master_arr.copy_from_slice(slice::from_raw_parts(master_seed, MT_MASTER_SEED_LEN));
        let role_bytes = slice::from_raw_parts(role, role_len);
        let seed = Zeroizing::new(mldsa_seed_for_role(&master_arr, role_bytes));
        slice::from_raw_parts_mut(out_seed, MT_MLDSA_SEED_LEN).copy_from_slice(&seed[..]);
        MT_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_mldsa_keypair_from_seed(
    seed: *const u8,
    out_pubkey: *mut u8,
    out_seckey: *mut u8,
) -> c_int {
    guard(|| {
        if seed.is_null() || out_pubkey.is_null() || out_seckey.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut arr = Zeroizing::new([0u8; MT_MLDSA_SEED_LEN]);
        arr.copy_from_slice(slice::from_raw_parts(seed, MT_MLDSA_SEED_LEN));
        match keypair_from_seed(&arr) {
            Ok((pk, sk)) => {
                slice::from_raw_parts_mut(out_pubkey, MT_MLDSA_PUBKEY_SIZE)
                    .copy_from_slice(pk.as_bytes());
                slice::from_raw_parts_mut(out_seckey, MT_MLDSA_SECKEY_SIZE)
                    .copy_from_slice(sk.as_bytes());
                MT_OK
            },
            Err(_) => MT_ERR_KEYGEN_FAILED,
        }
    })
}

/// 24 words → the signing keys of the person (ML-DSA-65). The seed opens keys and nothing
/// that names their holder: the set publishes no identifier of a person, so none leaves here.
#[no_mangle]
pub unsafe extern "C" fn mt_seed_keys(
    mnemonic_utf8: *const c_char,
    out_pubkey: *mut u8,
    out_seckey: *mut u8,
) -> c_int {
    guard(|| {
        let mut master = Zeroizing::new([0u8; MT_MASTER_SEED_LEN]);
        let rc = mt_mnemonic_to_master_seed(mnemonic_utf8, master.as_mut_ptr());
        if rc != MT_OK {
            return rc;
        }
        let mut sign_seed = Zeroizing::new([0u8; MT_MLDSA_SEED_LEN]);
        let rc = mt_mldsa_seed_for_role(
            master.as_ptr(),
            mt_codec::domain::ACCOUNT_KEY.as_ptr(),
            mt_codec::domain::ACCOUNT_KEY.len(),
            sign_seed.as_mut_ptr(),
        );
        if rc != MT_OK {
            return rc;
        }
        mt_mldsa_keypair_from_seed(sign_seed.as_ptr(), out_pubkey, out_seckey)
    })
}

/// Transitional wrapper for builds not yet on `mt_seed_keys`: the same keys, plus the
/// identifier the set abolished, computed locally so the ABI stays for one cycle of builds.
#[no_mangle]
pub unsafe extern "C" fn mt_account_from_mnemonic(
    mnemonic_utf8: *const c_char,
    out_pubkey: *mut u8,
    out_seckey: *mut u8,
    out_account_id: *mut u8,
) -> c_int {
    guard(|| {
        let rc = mt_seed_keys(mnemonic_utf8, out_pubkey, out_seckey);
        if rc != MT_OK {
            return rc;
        }
        if out_account_id.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut arr = [0u8; MT_MLDSA_PUBKEY_SIZE];
        arr.copy_from_slice(slice::from_raw_parts(out_pubkey, MT_MLDSA_PUBKEY_SIZE));
        let id = derive_account_id(MT_SUITE_MLDSA65, &arr);
        slice::from_raw_parts_mut(out_account_id, MT_ACCOUNT_ID_LEN).copy_from_slice(&id);
        MT_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_sign(
    seckey: *const u8,
    msg: *const u8,
    msg_len: usize,
    out_sig: *mut u8,
) -> c_int {
    guard(|| {
        if seckey.is_null() || out_sig.is_null() || (msg.is_null() && msg_len > 0) {
            return MT_ERR_NULL_PTR;
        }
        let sk_bytes = slice::from_raw_parts(seckey, MT_MLDSA_SECKEY_SIZE);
        let sk = match SecretKey::from_slice(sk_bytes) {
            Some(k) => k,
            None => return MT_ERR_SIGN_FAILED,
        };
        let m: &[u8] = if msg_len == 0 {
            &[]
        } else {
            slice::from_raw_parts(msg, msg_len)
        };
        match mldsa_sign(&sk, m) {
            Ok(sig) => {
                slice::from_raw_parts_mut(out_sig, MT_MLDSA_SIG_SIZE)
                    .copy_from_slice(sig.as_bytes());
                MT_OK
            },
            Err(_) => MT_ERR_SIGN_FAILED,
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_verify(
    pubkey: *const u8,
    msg: *const u8,
    msg_len: usize,
    sig: *const u8,
) -> c_int {
    guard(|| {
        if pubkey.is_null() || sig.is_null() || (msg.is_null() && msg_len > 0) {
            return MT_ERR_NULL_PTR;
        }
        let pk_bytes = slice::from_raw_parts(pubkey, MT_MLDSA_PUBKEY_SIZE);
        let pk = match PublicKey::from_slice(pk_bytes) {
            Some(k) => k,
            None => return MT_ERR_VERIFY_FAILED,
        };
        let sig_bytes = slice::from_raw_parts(sig, MT_MLDSA_SIG_SIZE);
        let signature = match Signature::from_slice(sig_bytes) {
            Some(s) => s,
            None => return MT_ERR_VERIFY_FAILED,
        };
        let m: &[u8] = if msg_len == 0 {
            &[]
        } else {
            slice::from_raw_parts(msg, msg_len)
        };
        if mldsa_verify(&pk, m, &signature) {
            MT_OK
        } else {
            MT_ERR_VERIFY_FAILED
        }
    })
}

/// Creates a fresh identity: health-tested OS entropy → 24-word UTF-8 mnemonic.
///
/// This is the only door through which a Montana identity is born. A client that
/// draws its own randomness leaves the quality of the root outside the protocol.
/// `out_mnemonic_utf8` — a buffer ≥ out_capacity bytes; a null-terminated string is written.
/// Returns MT_ERR_CSPRNG when the operating system has no entropy source, and
/// MT_ERR_ENTROPY_HEALTH when the block returned by that source fails its health tests.
#[no_mangle]
pub unsafe extern "C" fn mt_generate_mnemonic(
    out_mnemonic_utf8: *mut u8,
    out_capacity: usize,
    out_len: *mut usize,
) -> c_int {
    guard(|| {
        if out_mnemonic_utf8.is_null() || out_len.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mnemonic = match mt_mnemonic::generate_mnemonic() {
            Ok(m) => m,
            Err(mt_mnemonic::EntropyError::Csprng) => return MT_ERR_CSPRNG,
            Err(_) => return MT_ERR_ENTROPY_HEALTH,
        };
        let bytes = mnemonic.as_bytes();
        if bytes.len() + 1 > out_capacity {
            return MT_ERR_BUFFER_TOO_SMALL;
        }
        let dst = slice::from_raw_parts_mut(out_mnemonic_utf8, out_capacity);
        dst[..bytes.len()].copy_from_slice(bytes);
        dst[bytes.len()] = 0;
        *out_len = bytes.len();
        MT_OK
    })
}

/// Measures of the seven entropy sources of THIS machine, so a person can see what their identity
/// stands on and a node can log it.
///
/// Writes 7 records of 7 bytes in the order of the mixing: OS CSPRNG, CPU instruction, execution
/// jitter, memory access, quartz drift, scheduler, timer overshoot. Each record is
/// `samples u16 LE ‖ distinct u16 LE ‖ max_repeat u16 LE ‖ alive u8`. No byte of any source
/// leaves through this door — only the count of them, because the measures are what a person is
/// entitled to see and the samples are what nobody is.
#[no_mangle]
pub unsafe extern "C" fn mt_entropy_sources(
    out: *mut u8,
    capacity: usize,
    out_len: *mut usize,
) -> c_int {
    guard(|| {
        if out.is_null() || out_len.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let m = mt_mnemonic::measure_sources();
        let need = m.len() * 7;
        if capacity < need {
            return MT_ERR_BUFFER_TOO_SMALL;
        }
        let dst = slice::from_raw_parts_mut(out, capacity);
        for (i, s) in m.iter().enumerate() {
            let at = i * 7;
            dst[at..at + 2].copy_from_slice(&s.samples.to_le_bytes());
            dst[at + 2..at + 4].copy_from_slice(&s.distinct.to_le_bytes());
            dst[at + 4..at + 6].copy_from_slice(&s.max_repeat.to_le_bytes());
            dst[at + 6] = u8::from(s.alive);
        }
        *out_len = need;
        MT_OK
    })
}

/// How many sources must be alive before an identity may be born. Below it birth is refused.
#[no_mangle]
pub extern "C" fn mt_entropy_min_live() -> c_int {
    mt_mnemonic::MIN_LIVE_SOURCES as c_int
}

/// The report of the LAST gather of this process — what the run's randomness stands on, so the
/// diary can name it, and which sources were judged dead when a refusal came. Costs nothing: no
/// measurement is taken here. Writes 16 bytes:
/// `alive u8 ‖ os u8 ‖ jitter u8 ‖ memory u8 ‖ quartz u8 ‖ scheduler u8 ‖ timer u8 ‖ scale u8 ‖ step_ns u32 LE ‖ reserved u32`.
/// Returns MT_ERR_IO when no gather has happened yet in this process.
#[no_mangle]
pub unsafe extern "C" fn mt_entropy_last_report(out: *mut u8, capacity: usize) -> c_int {
    guard(|| {
        if out.is_null() {
            return MT_ERR_NULL_PTR;
        }
        if capacity < 16 {
            return MT_ERR_BUFFER_TOO_SMALL;
        }
        let r = match mt_mnemonic::last_report() {
            Some(r) => r,
            None => return MT_ERR_IO,
        };
        let dst = slice::from_raw_parts_mut(out, 16);
        dst[0] = r.count() as u8;
        dst[1] = u8::from(r.os_csprng);
        dst[2] = u8::from(r.jitter);
        dst[3] = u8::from(r.memory);
        dst[4] = u8::from(r.quartz);
        dst[5] = u8::from(r.scheduler);
        dst[6] = u8::from(r.timer);
        dst[7] = r.scale.min(255) as u8;
        dst[8..12].copy_from_slice(&(r.step_ns.min(u32::MAX as u64) as u32).to_le_bytes());
        dst[12..16].copy_from_slice(&0u32.to_le_bytes());
        MT_OK
    })
}

/// HKDF-Expand(master_seed, role, 64) -> ML-KEM-768 seed (d‖z). Stage 1: app_kem_key.
#[no_mangle]
pub unsafe extern "C" fn mt_mlkem_seed_for_role(
    master_seed: *const u8,
    role: *const u8,
    role_len: usize,
    out_seed: *mut u8,
) -> c_int {
    guard(|| {
        if master_seed.is_null() || role.is_null() || out_seed.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut master_arr = Zeroizing::new([0u8; MT_MASTER_SEED_LEN]);
        master_arr.copy_from_slice(slice::from_raw_parts(master_seed, MT_MASTER_SEED_LEN));
        let role_bytes = slice::from_raw_parts(role, role_len);
        let seed = Zeroizing::new(mlkem_seed_for_role(&master_arr, role_bytes));
        slice::from_raw_parts_mut(out_seed, MT_MLKEM_SEED_LEN).copy_from_slice(&seed[..]);
        MT_OK
    })
}

/// ML-KEM-768 KeyGen from a 64-byte seed (FIPS 203, deterministic). pk 1184 / sk 2400.
#[no_mangle]
pub unsafe extern "C" fn mt_mlkem_keypair_from_seed(
    seed: *const u8,
    out_pubkey: *mut u8,
    out_seckey: *mut u8,
) -> c_int {
    guard(|| {
        if seed.is_null() || out_pubkey.is_null() || out_seckey.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut arr = Zeroizing::new([0u8; MT_MLKEM_SEED_LEN]);
        arr.copy_from_slice(slice::from_raw_parts(seed, MT_MLKEM_SEED_LEN));
        match keypair_from_seed_mlkem(&arr) {
            Ok((pk, sk)) => {
                slice::from_raw_parts_mut(out_pubkey, MT_MLKEM_PUBKEY_SIZE)
                    .copy_from_slice(pk.as_bytes());
                slice::from_raw_parts_mut(out_seckey, MT_MLKEM_SECKEY_SIZE)
                    .copy_from_slice(sk.as_bytes());
                MT_OK
            },
            Err(_) => MT_ERR_KEYGEN_FAILED,
        }
    })
}

/// ML-KEM-768 Encapsulate (FIPS 203 §6.2). pk 1184 -> ct 1088 / ss 32.
#[no_mangle]
pub unsafe extern "C" fn mt_mlkem_encaps(
    pubkey: *const u8,
    out_ct: *mut u8,
    out_ss: *mut u8,
) -> c_int {
    guard(|| {
        if pubkey.is_null() || out_ct.is_null() || out_ss.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let pk =
            match MlkemPublicKey::from_slice(slice::from_raw_parts(pubkey, MT_MLKEM_PUBKEY_SIZE)) {
                Some(k) => k,
                None => return MT_ERR_KEM_FAILED,
            };
        match mlkem_encapsulate(&pk) {
            Ok((ct, ss)) => {
                slice::from_raw_parts_mut(out_ct, MT_MLKEM_CT_SIZE).copy_from_slice(ct.as_bytes());
                slice::from_raw_parts_mut(out_ss, MT_MLKEM_SS_SIZE).copy_from_slice(ss.as_bytes());
                MT_OK
            },
            Err(_) => MT_ERR_KEM_FAILED,
        }
    })
}

/// ML-KEM-768 Decapsulate (FIPS 203 §6.3, implicit-rejection). sk 2400, ct 1088 -> ss 32.
#[no_mangle]
pub unsafe extern "C" fn mt_mlkem_decaps(
    seckey: *const u8,
    ct: *const u8,
    out_ss: *mut u8,
) -> c_int {
    guard(|| {
        if seckey.is_null() || ct.is_null() || out_ss.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let sk =
            match MlkemSecretKey::from_slice(slice::from_raw_parts(seckey, MT_MLKEM_SECKEY_SIZE)) {
                Some(k) => k,
                None => return MT_ERR_KEM_FAILED,
            };
        let ctv = match MlkemCiphertext::from_slice(slice::from_raw_parts(ct, MT_MLKEM_CT_SIZE)) {
            Some(c) => c,
            None => return MT_ERR_KEM_FAILED,
        };
        match mlkem_decapsulate(&sk, &ctv) {
            Ok(ss) => {
                slice::from_raw_parts_mut(out_ss, MT_MLKEM_SS_SIZE).copy_from_slice(ss.as_bytes());
                MT_OK
            },
            Err(_) => MT_ERR_KEM_FAILED,
        }
    })
}

/// 24-word mnemonic -> app_kem_key (ML-KEM-768) via role "mt-app-encryption-key". pk 1184 / sk 2400.
#[no_mangle]
pub unsafe extern "C" fn mt_app_kem_from_mnemonic(
    mnemonic_utf8: *const c_char,
    out_pubkey: *mut u8,
    out_seckey: *mut u8,
) -> c_int {
    guard(|| {
        let mut master = Zeroizing::new([0u8; MT_MASTER_SEED_LEN]);
        let rc = mt_mnemonic_to_master_seed(mnemonic_utf8, master.as_mut_ptr());
        if rc != MT_OK {
            return rc;
        }
        let mut kem_seed = Zeroizing::new([0u8; MT_MLKEM_SEED_LEN]);
        let rc = mt_mlkem_seed_for_role(
            master.as_ptr(),
            mt_codec::domain::APP_ENCRYPTION_KEY.as_ptr(),
            mt_codec::domain::APP_ENCRYPTION_KEY.len(),
            kem_seed.as_mut_ptr(),
        );
        if rc != MT_OK {
            return rc;
        }
        mt_mlkem_keypair_from_seed(kem_seed.as_ptr(), out_pubkey, out_seckey)
    })
}

/// history_key = HKDF-SHA-256(salt=0×32, ikm=entropy_32, info="mt-history-key", 32) — messenger Stage 10.
/// `entropy` — 32 bytes; `out` — 32 bytes. SSOT for history_key across all clients.
#[no_mangle]
pub unsafe extern "C" fn mt_history_key(entropy: *const u8, out: *mut u8) -> c_int {
    guard(|| {
        if entropy.is_null() || out.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let ent = slice::from_raw_parts(entropy, MT_HISTORY_KEY_LEN);
        let prk = mt_mnemonic::hmac_sha256(&[0u8; 32], ent); // HKDF-Extract(salt=0×32, ikm=entropy)
        let okm =
            mt_mnemonic::hkdf_expand(&prk, mt_codec::domain::MSG_HISTORY_KEY, MT_HISTORY_KEY_LEN);
        slice::from_raw_parts_mut(out, MT_HISTORY_KEY_LEN).copy_from_slice(&okm);
        MT_OK
    })
}

/// media_key = HKDF-SHA-256(salt=0×32, ikm=entropy_32, info="mt-media-key", 32) — s.2 Stage 1.
/// Separate seed branch for media at-rest (≠ history_key). `entropy`/`out` — 32 bytes. SSOT for all clients.
#[no_mangle]
pub unsafe extern "C" fn mt_media_key(entropy: *const u8, out: *mut u8) -> c_int {
    guard(|| {
        if entropy.is_null() || out.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let ent = slice::from_raw_parts(entropy, MT_HISTORY_KEY_LEN);
        let prk = mt_mnemonic::hmac_sha256(&[0u8; 32], ent); // HKDF-Extract(salt=0×32, ikm=entropy)
        let okm =
            mt_mnemonic::hkdf_expand(&prk, mt_codec::domain::MSG_MEDIA_KEY, MT_HISTORY_KEY_LEN);
        slice::from_raw_parts_mut(out, MT_HISTORY_KEY_LEN).copy_from_slice(&okm);
        MT_OK
    })
}

// ═══ Stage 1 of the second front — local archive Montana/Chats/<chat>/ ═══

/// Append a single message to the local archive: <base>/Chats/<chat>/conversation.mtlog,
/// sealed under history_key (Rust does encode+seal+file). base = the app's Montana folder.
///
/// # Safety
/// `hk`/`account_id`/`conv_id` → 32 B; strings are valid UTF-8 C-strings; `content` → `content_len` B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_append(
    base_path: *const c_char,
    chat_name: *const c_char,
    hk: *const u8,
    account_id: *const u8,
    device_id: *const u8,
    conv_id: *const u8,
    dir: u8,
    send_time: u64,
    content: *const u8,
    content_len: usize,
) -> c_int {
    guard(|| {
        if base_path.is_null()
            || chat_name.is_null()
            || hk.is_null()
            || account_id.is_null()
            || device_id.is_null()
            || conv_id.is_null()
            || (content.is_null() && content_len != 0)
        {
            return crate::MT_ERR_NULL_PTR;
        }
        let base = match CStr::from_ptr(base_path).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let chat = match CStr::from_ptr(chat_name).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let mut hk32 = [0u8; 32];
        hk32.copy_from_slice(slice::from_raw_parts(hk, 32));
        let mut acct = [0u8; 32];
        acct.copy_from_slice(slice::from_raw_parts(account_id, 32));
        let mut conv = [0u8; 32];
        conv.copy_from_slice(slice::from_raw_parts(conv_id, 32));
        let mut dev = [0u8; 16];
        dev.copy_from_slice(slice::from_raw_parts(device_id, 16));
        let body = if content_len == 0 {
            Vec::new()
        } else {
            slice::from_raw_parts(content, content_len).to_vec()
        };
        let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_IO,
        };
        // The core assigns a monotonic per-identity block_seq (seq.bin) — the client does not pass seq (no nonce reuse).
        // device_id (16 B) → writer_tag: separates the nonce space across this seed's devices (Stage 1).
        match store.append_item(chat, &hk32, &acct, &dev, &conv, dir, send_time, &body) {
            Ok(_seq) => crate::MT_OK,
            Err(_) => crate::MT_ERR_IO,
        }
    })
}

/// ArchiveRoot (Stage 2) over the whole local archive: reads every chat log under <base>/Chats/,
/// ingests sealed blocks by (writer_tag, block_seq), folds the Merkle root. Writes 32 bytes to `out`
/// and returns MT_OK; returns MT_ERR_IO on read failure; an empty archive yields all-zero out + MT_OK.
///
/// # Safety
/// `base_path` is a valid UTF-8 C-string; `hk`/`account_id` → 32 B; `out` → 32 B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_root(
    base_path: *const c_char,
    hk: *const u8,
    account_id: *const u8,
    out: *mut u8,
) -> c_int {
    guard(|| {
        if base_path.is_null() || hk.is_null() || account_id.is_null() || out.is_null() {
            return crate::MT_ERR_NULL_PTR;
        }
        let base = match CStr::from_ptr(base_path).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let mut hk32 = [0u8; 32];
        hk32.copy_from_slice(slice::from_raw_parts(hk, 32));
        let mut acct = [0u8; 32];
        acct.copy_from_slice(slice::from_raw_parts(account_id, 32));
        let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_IO,
        };
        let root = match store.archive_root(&hk32, &acct) {
            Ok(r) => r,
            Err(_) => return crate::MT_ERR_IO,
        };
        let out_slice = slice::from_raw_parts_mut(out, 32);
        match root {
            Some(r) => out_slice.copy_from_slice(&r),
            None => out_slice.fill(0),
        }
        crate::MT_OK
    })
}

/// writer_tag = SHA-256("mt-history-writer" ‖ 0x00 ‖ device_id)[0:4] — Stage 1 nonce split per writer.
///
/// # Safety
/// `device_id` → 16 B; `out` → 4 B.
#[no_mangle]
pub unsafe extern "C" fn mt_writer_tag(device_id: *const u8, out: *mut u8) -> c_int {
    guard(|| {
        if device_id.is_null() || out.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut dev = [0u8; 16];
        dev.copy_from_slice(slice::from_raw_parts(device_id, 16));
        let wt = mt_messenger_e2e::archive::writer_tag(&dev);
        slice::from_raw_parts_mut(out, 4).copy_from_slice(&wt);
        MT_OK
    })
}

/// (writer_tag, block_seq) identity of a sealed block — from the stored nonce prefix (no decrypt).
///
/// # Safety
/// `sealed` → `sealed_len` B; `out_writer_tag` → 4 B; `out_block_seq` → valid u64 pointer.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_block_id(
    sealed: *const u8,
    sealed_len: usize,
    out_writer_tag: *mut u8,
    out_block_seq: *mut u64,
) -> c_int {
    guard(|| {
        if sealed.is_null() || out_writer_tag.is_null() || out_block_seq.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let s = slice::from_raw_parts(sealed, sealed_len);
        let (Some(wt), Some(seq)) = (
            mt_messenger_e2e::archive::block_writer_tag(s),
            mt_messenger_e2e::archive::block_seq_of(s),
        ) else {
            return crate::MT_ERR_DECODE;
        };
        slice::from_raw_parts_mut(out_writer_tag, 4).copy_from_slice(&wt);
        *out_block_seq = seq;
        MT_OK
    })
}

/// Export this writer's sealed blocks of one chat with block_seq >= from_seq as a length-prefixed
/// stream (u32 LE ‖ sealed)×N — replication push source (Stage 3/4). Returns bytes written (>=0)
/// or an error code; MT_ERR_BUFFER_TOO_SMALL if `out_cap` is insufficient (cap = log size fits).
///
/// # Safety
/// strings are valid UTF-8 C-strings; `writer_tag` → 4 B; `out` → `out_cap` B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_export(
    base_path: *const c_char,
    chat_name: *const c_char,
    writer_tag: *const u8,
    from_seq: u64,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let r = guard(|| {
        if base_path.is_null()
            || chat_name.is_null()
            || writer_tag.is_null()
            || (out.is_null() && out_cap != 0)
        {
            return MT_ERR_NULL_PTR;
        }
        let base = match CStr::from_ptr(base_path).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let chat = match CStr::from_ptr(chat_name).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let mut wt = [0u8; 4];
        wt.copy_from_slice(slice::from_raw_parts(writer_tag, 4));
        let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_IO,
        };
        let stream = match store.export_mine(chat, &wt, from_seq) {
            Ok(v) => v,
            Err(_) => return crate::MT_ERR_IO,
        };
        if stream.len() > out_cap {
            return crate::MT_ERR_BUFFER_TOO_SMALL;
        }
        slice::from_raw_parts_mut(out, stream.len()).copy_from_slice(&stream);
        stream.len() as c_int
    });
    r as isize
}

/// Ingest a replicated sealed block as-stored into the chat's log (Stage 4): AEAD-authenticate,
/// dedup by (writer_tag, block_seq), append unchanged. Returns 1 appended, 0 duplicate, <0 error.
///
/// # Safety
/// strings are valid UTF-8 C-strings; `hk`/`account_id` → 32 B; `sealed` → `sealed_len` B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_ingest(
    base_path: *const c_char,
    chat_name: *const c_char,
    hk: *const u8,
    account_id: *const u8,
    sealed: *const u8,
    sealed_len: usize,
) -> c_int {
    guard(|| {
        if base_path.is_null()
            || chat_name.is_null()
            || hk.is_null()
            || account_id.is_null()
            || sealed.is_null()
        {
            return MT_ERR_NULL_PTR;
        }
        let base = match CStr::from_ptr(base_path).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let chat = match CStr::from_ptr(chat_name).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let mut hk32 = [0u8; 32];
        hk32.copy_from_slice(slice::from_raw_parts(hk, 32));
        let mut acct = [0u8; 32];
        acct.copy_from_slice(slice::from_raw_parts(account_id, 32));
        let s = slice::from_raw_parts(sealed, sealed_len);
        let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
            Ok(st) => st,
            Err(_) => return crate::MT_ERR_IO,
        };
        match store.ingest_block(chat, &hk32, &acct, s) {
            Ok(true) => 1,
            Ok(false) => 0,
            Err(e) if e.kind() == std::io::ErrorKind::InvalidData => crate::MT_ERR_DECODE,
            Err(_) => crate::MT_ERR_IO,
        }
    })
}

/// conv_id (32 B) of a sealed block — decrypt under history_key, first item's conv (routing).
///
/// # Safety
/// `hk`/`account_id` → 32 B; `sealed` → `sealed_len` B; `out` → 32 B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_peek_conv(
    hk: *const u8,
    account_id: *const u8,
    sealed: *const u8,
    sealed_len: usize,
    out: *mut u8,
) -> c_int {
    guard(|| {
        if hk.is_null() || account_id.is_null() || sealed.is_null() || out.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut hk32 = [0u8; 32];
        hk32.copy_from_slice(slice::from_raw_parts(hk, 32));
        let mut acct = [0u8; 32];
        acct.copy_from_slice(slice::from_raw_parts(account_id, 32));
        let s = slice::from_raw_parts(sealed, sealed_len);
        match mt_messenger_e2e::archive::peek_conv(&hk32, &acct, s) {
            Some(conv) => {
                slice::from_raw_parts_mut(out, 32).copy_from_slice(&conv);
                MT_OK
            },
            None => crate::MT_ERR_DECODE,
        }
    })
}

/// Open one sealed history block under history_key/account_id and return its plaintext in the
/// canonical block encoding (block_seq u64 LE ‖ count u32 LE ‖ items: conv_id 32 ‖ dir 1 ‖
/// send_time u64 LE ‖ len u32 LE ‖ content). The reading road of the archive: a device that
/// holds the sealed log and the seed rebuilds its feed from here; without it the archive was a
/// write-only mirror. Returns bytes written (>=0), MT_ERR_BUFFER_TOO_SMALL when `out_cap` is
/// short, MT_ERR_DECODE when the block does not open.
///
/// # Safety
/// `hk`/`account_id` → 32 B; `sealed` → `sealed_len` B; `out` → `out_cap` B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_open_block(
    hk: *const u8,
    account_id: *const u8,
    sealed: *const u8,
    sealed_len: usize,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let r = guard(|| {
        if hk.is_null()
            || account_id.is_null()
            || sealed.is_null()
            || (out.is_null() && out_cap != 0)
        {
            return MT_ERR_NULL_PTR;
        }
        let mut hk32 = [0u8; 32];
        hk32.copy_from_slice(slice::from_raw_parts(hk, 32));
        let mut acct = [0u8; 32];
        acct.copy_from_slice(slice::from_raw_parts(account_id, 32));
        let s = slice::from_raw_parts(sealed, sealed_len);
        let block = match mt_messenger_e2e::archive::open_block(&hk32, &acct, s) {
            Some(b) => b,
            None => return crate::MT_ERR_DECODE,
        };
        let plain = mt_messenger_e2e::archive::encode_block(&block);
        if plain.len() > out_cap {
            return crate::MT_ERR_BUFFER_TOO_SMALL;
        }
        slice::from_raw_parts_mut(out, plain.len()).copy_from_slice(&plain);
        plain.len() as c_int
    });
    r as isize
}

/// Encrypt media under media_key (NOT history_key: the branches are separate) and place it into <base>/Chats/<chat>/Media/<blob_id_hex>.
/// Other applications see only ciphertext; only the client can decrypt it using the seed.
///
/// # Safety
/// strings are valid UTF-8 C-strings; `hk`/`account_id` → 32 B; `blob` → `blob_len` B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_put_media(
    base_path: *const c_char,
    chat_name: *const c_char,
    blob_id_hex: *const c_char,
    mk: *const u8,
    account_id: *const u8,
    blob: *const u8,
    blob_len: usize,
) -> c_int {
    guard(|| {
        if base_path.is_null()
            || chat_name.is_null()
            || blob_id_hex.is_null()
            || mk.is_null()
            || account_id.is_null()
            || (blob.is_null() && blob_len != 0)
        {
            return crate::MT_ERR_NULL_PTR;
        }
        let base = match CStr::from_ptr(base_path).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let chat = match CStr::from_ptr(chat_name).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let bid = match CStr::from_ptr(blob_id_hex).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let mut mk32 = [0u8; 32];
        mk32.copy_from_slice(slice::from_raw_parts(mk, 32));
        let mut acct = [0u8; 32];
        acct.copy_from_slice(slice::from_raw_parts(account_id, 32));
        let data = if blob_len == 0 {
            Vec::new()
        } else {
            slice::from_raw_parts(blob, blob_len).to_vec()
        };
        let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_IO,
        };
        match store.put_media(chat, bid, &mk32, &acct, &data) {
            Ok(()) => crate::MT_OK,
            Err(_) => crate::MT_ERR_IO,
        }
    })
}

/// Read and decrypt media. Returns the plaintext length (>=0) or an error code (<0).
/// `out_cap` too small → MT_ERR_BUFFER_TOO_SMALL; file missing / decryption failed → MT_ERR_IO.
///
/// # Safety
/// strings are valid UTF-8; `hk`/`account_id` → 32 B; `out` → `out_cap` B.
#[no_mangle]
pub unsafe extern "C" fn mt_archive_get_media(
    base_path: *const c_char,
    chat_name: *const c_char,
    blob_id_hex: *const c_char,
    hk: *const u8,
    account_id: *const u8,
    out: *mut u8,
    out_cap: usize,
) -> isize {
    let r = guard(|| {
        if base_path.is_null()
            || chat_name.is_null()
            || blob_id_hex.is_null()
            || hk.is_null()
            || account_id.is_null()
            || (out.is_null() && out_cap != 0)
        {
            return crate::MT_ERR_NULL_PTR;
        }
        let base = match CStr::from_ptr(base_path).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let chat = match CStr::from_ptr(chat_name).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let bid = match CStr::from_ptr(blob_id_hex).to_str() {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_INVALID_UTF8,
        };
        let mut mk32 = [0u8; 32];
        mk32.copy_from_slice(slice::from_raw_parts(hk, 32)); // media_key
        let mut acct = [0u8; 32];
        acct.copy_from_slice(slice::from_raw_parts(account_id, 32));
        let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
            Ok(s) => s,
            Err(_) => return crate::MT_ERR_IO,
        };
        match store.get_media(chat, bid, &mk32, &acct) {
            Some(pt) => {
                if pt.len() > out_cap {
                    return crate::MT_ERR_BUFFER_TOO_SMALL;
                }
                slice::from_raw_parts_mut(out, pt.len()).copy_from_slice(&pt);
                pt.len() as i32
            },
            None => crate::MT_ERR_IO,
        }
    });
    r as isize
}
// Cap on one randomness draw: no caller asks for more, and an unbounded length
// turns the door into a way to keep the machine busy.
const MT_RANDOM_MAX_LEN: usize = 1024;

/// The ONLY runtime randomness door: nonces, packet and chunk identifiers,
/// connection seeds, the storage key. The seed is a full gather of seven sources, refused when fewer
/// than three are live, and it is taken ONCE per launch; every draw beyond that absorbs
/// a cheap probe of the crystal, so it does not depend only on the seed taken earlier.
///
/// There is no second door that took the full gather on every draw: the gather costs 21 ms, and that price
/// makes sense exactly once -- at identity birth, where it is paid for a root that lives for years.
/// Paying it for every nonce would mean keeping the machine busy with work that adds nothing:
/// the same gather taken at seeding stands behind every draw anyway.
#[no_mangle]
pub unsafe extern "C" fn mt_random_fast(out: *mut u8, len: usize) -> c_int {
    if out.is_null() || len == 0 || len > MT_RANDOM_MAX_LEN {
        return MT_ERR_NULL_PTR;
    }
    let dst = slice::from_raw_parts_mut(out, len);
    match mt_mnemonic::random_fast(dst) {
        Ok(()) => MT_OK,
        Err(_) => MT_ERR_CSPRNG,
    }
}
