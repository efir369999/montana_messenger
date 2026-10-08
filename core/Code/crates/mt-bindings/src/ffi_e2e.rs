//! E2E engine C-ABI (mt-messenger-e2e) for iOS. Variable-length outputs use an
//! owned buffer: the function allocates and returns (ptr,len); the client frees via mt_e2e_free.

use core::slice;
use std::os::raw::c_int;

use mt_messenger_e2e::session::SessionState;

use super::{guard, MT_ERR_KEM_FAILED, MT_ERR_NULL_PTR, MT_ERR_REPLAY, MT_OK};
use mt_messenger_e2e::session::RatchetError;

unsafe fn write_out(data: Vec<u8>, out_ptr: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = data.into_boxed_slice();
    *out_len = boxed.len();
    *out_ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

/// Free the buffer produced by the mt_e2e_* functions.
///
/// # Safety
/// `ptr`/`len` are exactly what mt_e2e_* returned via out-parameters; call once.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        drop(Vec::from_raw_parts(ptr, len, len));
    }
}

/// RatchetEncrypt over an opaque session blob. Returns a new session blob + message.
///
/// # Safety
/// All pointers are valid for their length; `rng_seed` is 64 bytes; out-pointers are non-null.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_encrypt(
    session: *const u8,
    session_len: usize,
    pt: *const u8,
    pt_len: usize,
    rng_seed: *const u8,
    out_session: *mut *mut u8,
    out_session_len: *mut usize,
    out_msg: *mut *mut u8,
    out_msg_len: *mut usize,
) -> c_int {
    guard(|| {
        if session.is_null()
            || rng_seed.is_null()
            || out_session.is_null()
            || out_msg.is_null()
            || (pt_len > 0 && pt.is_null())
        {
            return MT_ERR_NULL_PTR;
        }
        let mut st = match SessionState::from_bytes(slice::from_raw_parts(session, session_len)) {
            Ok(s) => s,
            Err(_) => return MT_ERR_KEM_FAILED,
        };
        let plaintext = if pt_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(pt, pt_len)
        };
        let seed: [u8; 64] = slice::from_raw_parts(rng_seed, 64).try_into().unwrap();
        let msg = match st.encrypt(plaintext, &seed) {
            Ok(m) => m,
            Err(_) => return MT_ERR_KEM_FAILED,
        };
        write_out(st.to_bytes(), out_session, out_session_len);
        write_out(msg, out_msg, out_msg_len);
        MT_OK
    })
}

/// RatchetDecrypt over an opaque session blob. Returns a new blob + plaintext.
///
/// # Safety
/// All pointers are valid for their length; out-pointers are non-null.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_decrypt(
    session: *const u8,
    session_len: usize,
    msg: *const u8,
    msg_len: usize,
    out_session: *mut *mut u8,
    out_session_len: *mut usize,
    out_pt: *mut *mut u8,
    out_pt_len: *mut usize,
) -> c_int {
    guard(|| {
        if session.is_null() || msg.is_null() || out_session.is_null() || out_pt.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut st = match SessionState::from_bytes(slice::from_raw_parts(session, session_len)) {
            Ok(s) => s,
            Err(_) => return MT_ERR_KEM_FAILED,
        };
        let message = slice::from_raw_parts(msg, msg_len);
        let pt = match st.decrypt(message) {
            Ok(p) => p,
            Err(RatchetError::Replay) => return MT_ERR_REPLAY,
            Err(_) => return MT_ERR_KEM_FAILED,
        };
        write_out(st.to_bytes(), out_session, out_session_len);
        write_out(pt, out_pt, out_pt_len);
        MT_OK
    })
}

use mt_messenger_e2e::handshake::{
    build_handshake, process_handshake, RecipientBundle, RecipientKeys,
};
// DSSOT-3: sizes come from the crate's authoritative constants (SSOT), not magic numbers.
const MLDSA_PUB: usize = crate::MT_MLDSA_PUBKEY_SIZE;
const MLKEM_PUB: usize = crate::MT_MLKEM_PUBKEY_SIZE;
const MLKEM_SK: usize = crate::MT_MLKEM_SECKEY_SIZE;

/// Alice side: handshake + session initialization. Returns InitialHandshake
/// + the initiator session blob. `account_seed` is 32 bytes (ML-DSA identity seed).
///
/// # Safety
/// All key pointers are valid for the spec sizes; opk_* are read only when opk_flag=1.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn mt_e2e_build_handshake(
    alice_account_pub: *const u8,
    account_seed: *const u8,
    bob_account_pub: *const u8,
    bob_app_kem_pub: *const u8,
    bob_spk_pub: *const u8,
    spk_id: u32,
    opk_flag: u8,
    opk_id: u32,
    bob_opk_pub: *const u8,
    eph_seed: *const u8,
    send_time: u64,
    out_hs: *mut *mut u8,
    out_hs_len: *mut usize,
    out_session: *mut *mut u8,
    out_session_len: *mut usize,
) -> c_int {
    guard(|| {
        if alice_account_pub.is_null()
            || account_seed.is_null()
            || eph_seed.is_null()
            || bob_account_pub.is_null()
            || bob_app_kem_pub.is_null()
            || bob_spk_pub.is_null()
            || out_hs.is_null()
            || out_hs_len.is_null()
            || out_session.is_null()
            || out_session_len.is_null()
            || (opk_flag == 1 && bob_opk_pub.is_null())
        {
            return MT_ERR_NULL_PTR;
        }
        let a_pub: [u8; MLDSA_PUB] = slice::from_raw_parts(alice_account_pub, MLDSA_PUB)
            .try_into()
            .unwrap();
        let seed: [u8; 32] = slice::from_raw_parts(account_seed, 32).try_into().unwrap();
        let b_pub: [u8; MLDSA_PUB] = slice::from_raw_parts(bob_account_pub, MLDSA_PUB)
            .try_into()
            .unwrap();
        let app_pub: [u8; MLKEM_PUB] = slice::from_raw_parts(bob_app_kem_pub, MLKEM_PUB)
            .try_into()
            .unwrap();
        let spk_pub: [u8; MLKEM_PUB] = slice::from_raw_parts(bob_spk_pub, MLKEM_PUB)
            .try_into()
            .unwrap();
        let opk_pub: Option<[u8; MLKEM_PUB]> = if opk_flag == 1 {
            Some(
                slice::from_raw_parts(bob_opk_pub, MLKEM_PUB)
                    .try_into()
                    .unwrap(),
            )
        } else {
            None
        };
        let eph: [u8; 64] = slice::from_raw_parts(eph_seed, 64).try_into().unwrap();

        let bundle = RecipientBundle {
            account_key_pub: &b_pub,
            app_kem_pub: &app_pub,
            signed_prekey_pub: &spk_pub,
            spk_id,
            one_time: opk_pub.as_ref().map(|p| (opk_id, p)),
        };
        let hs = match build_handshake(&a_pub, &seed, &bundle, &eph, send_time) {
            Ok(h) => h,
            Err(_) => return MT_ERR_KEM_FAILED,
        };
        let session = SessionState::init_initiator(
            hs.transcript_hash,
            hs.session.root_key,
            hs.session.sending_chain_key,
            hs.eph_kem_pub_a,
            hs.eph_kem_sk_a,
            hs.signed_prekey_pub_b,
        );
        write_out(hs.bytes, out_hs, out_hs_len);
        write_out(session.to_bytes(), out_session, out_session_len);
        MT_OK
    })
}

/// Bob side: handshake processing + recipient session initialization.
///
/// # Safety
/// All key pointers are valid for the spec sizes; opk_* are read only when opk_flag=1.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn mt_e2e_process_handshake(
    hs: *const u8,
    hs_len: usize,
    bob_account_id: *const u8,
    bob_app_kem_pub: *const u8,
    bob_app_kem_sk: *const u8,
    bob_spk_pub: *const u8,
    bob_spk_sk: *const u8,
    opk_flag: u8,
    bob_opk_pub: *const u8,
    bob_opk_sk: *const u8,
    now: u64,
    accept_skew: u64,
    out_session: *mut *mut u8,
    out_session_len: *mut usize,
) -> c_int {
    guard(|| {
        if hs.is_null()
            || bob_account_id.is_null()
            || bob_app_kem_pub.is_null()
            || bob_app_kem_sk.is_null()
            || bob_spk_pub.is_null()
            || bob_spk_sk.is_null()
            || out_session.is_null()
            || out_session_len.is_null()
            || (opk_flag == 1 && (bob_opk_pub.is_null() || bob_opk_sk.is_null()))
        {
            return crate::MT_ERR_NULL_PTR;
        }
        let hs_bytes = slice::from_raw_parts(hs, hs_len);
        let acc_id: [u8; 32] = slice::from_raw_parts(bob_account_id, 32)
            .try_into()
            .unwrap();
        let app_pub: [u8; MLKEM_PUB] = slice::from_raw_parts(bob_app_kem_pub, MLKEM_PUB)
            .try_into()
            .unwrap();
        let spk_pub: [u8; MLKEM_PUB] = slice::from_raw_parts(bob_spk_pub, MLKEM_PUB)
            .try_into()
            .unwrap();
        let app_sk = slice::from_raw_parts(bob_app_kem_sk, MLKEM_SK);
        let spk_sk = slice::from_raw_parts(bob_spk_sk, MLKEM_SK);
        let opk: Option<([u8; MLKEM_PUB], &[u8])> = if opk_flag == 1 {
            let pk: [u8; MLKEM_PUB] = slice::from_raw_parts(bob_opk_pub, MLKEM_PUB)
                .try_into()
                .unwrap();
            Some((pk, slice::from_raw_parts(bob_opk_sk, MLKEM_SK)))
        } else {
            None
        };

        let keys = RecipientKeys {
            account_id: &acc_id,
            app_kem_pub: &app_pub,
            app_kem_sk: app_sk,
            signed_prekey_pub: &spk_pub,
            signed_prekey_sk: spk_sk,
            one_time: opk.as_ref().map(|(p, s)| (p, *s)),
        };
        let proc = match process_handshake(hs_bytes, &keys, now, accept_skew) {
            Ok(p) => p,
            Err(_) => return MT_ERR_KEM_FAILED,
        };
        let session = SessionState::init_responder(
            proc.transcript_hash,
            proc.session.root_key,
            proc.session.sending_chain_key,
            proc.eph_kem_pub_a,
            spk_pub,
            spk_sk.to_vec(),
        );
        write_out(session.to_bytes(), out_session, out_session_len);
        MT_OK
    })
}

use mt_messenger_e2e::media::{
    blob_id as media_blob_id, open_blob, pad_len as media_pad_len, seal_blob,
};

/// Seal a media blob: sealed_blob = nonce || Seal(blob_key, nonce, input, AD=mt-media).
/// out is an owned buffer (free via mt_e2e_free). `input` is already final (pad_len padding applied before the call).
///
/// # Safety
/// blob_key is 32 bytes, nonce is 12 bytes, input is input_len bytes; out_ptr/out_len are non-null.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_seal_blob(
    blob_key: *const u8,
    nonce: *const u8,
    input: *const u8,
    input_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    guard(|| {
        if blob_key.is_null()
            || nonce.is_null()
            || (input.is_null() && input_len != 0)
            || out_ptr.is_null()
            || out_len.is_null()
        {
            return MT_ERR_NULL_PTR;
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(slice::from_raw_parts(blob_key, 32));
        let mut n = [0u8; 12];
        n.copy_from_slice(slice::from_raw_parts(nonce, 12));
        let inp = if input_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(input, input_len)
        };
        write_out(seal_blob(&key, &n, inp), out_ptr, out_len);
        MT_OK
    })
}

/// blob_id = SHA-256(sealed_blob) -> out32 (32 bytes).
///
/// # Safety
/// sealed_blob is len bytes; out32 is 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_blob_id(
    sealed_blob: *const u8,
    len: usize,
    out32: *mut u8,
) -> c_int {
    guard(|| {
        if (sealed_blob.is_null() && len != 0) || out32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let b = if len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(sealed_blob, len)
        };
        let id = media_blob_id(b);
        slice::from_raw_parts_mut(out32, 32).copy_from_slice(&id);
        MT_OK
    })
}

/// Decrypt a blob -> padded plaintext (owned; caller truncates to size). Error -> MT_ERR_KEM_FAILED.
///
/// # Safety
/// blob_key is 32 bytes; sealed_blob is len bytes; out_ptr/out_len are non-null.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_open_blob(
    blob_key: *const u8,
    sealed_blob: *const u8,
    len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    guard(|| {
        if blob_key.is_null()
            || (sealed_blob.is_null() && len != 0)
            || out_ptr.is_null()
            || out_len.is_null()
        {
            return MT_ERR_NULL_PTR;
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(slice::from_raw_parts(blob_key, 32));
        let b = if len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(sealed_blob, len)
        };
        match open_blob(&key, b) {
            Some(pt) => {
                write_out(pt, out_ptr, out_len);
                MT_OK
            },
            None => MT_ERR_KEM_FAILED,
        }
    })
}

/// pad_len(n) is the target size after padding (size hiding).
#[no_mangle]
pub extern "C" fn mt_e2e_pad_len(n: usize) -> usize {
    media_pad_len(n)
}

/// safety_number(id_A, id_B) -> 60 ASCII digits (Stage 8). Both pointers are 32-byte account_id;
/// output is an owned buffer (60 bytes), freed via mt_e2e_free.
///
/// # Safety
/// `id_a`/`id_b` are valid for 32 bytes; out-pointers are non-null.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_safety_number(
    id_a: *const u8,
    id_b: *const u8,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    guard(|| {
        if id_a.is_null() || id_b.is_null() || out_ptr.is_null() || out_len.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let a: [u8; 32] = slice::from_raw_parts(id_a, 32).try_into().unwrap();
        let b: [u8; 32] = slice::from_raw_parts(id_b, 32).try_into().unwrap();
        let s = mt_messenger_e2e::safety::safety_number(&a, &b);
        write_out(s.into_bytes(), out_ptr, out_len);
        MT_OK
    })
}

/// party_code(account_id) -> 30 ASCII digits (Stage 8). The pointer is 32 bytes; output is owned.
///
/// # Safety
/// `id` is valid for 32 bytes; out-pointers are non-null.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_party_code(
    id: *const u8,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    guard(|| {
        if id.is_null() || out_ptr.is_null() || out_len.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let a: [u8; 32] = slice::from_raw_parts(id, 32).try_into().unwrap();
        let s = mt_messenger_e2e::safety::party_code(&a);
        write_out(s.into_bytes(), out_ptr, out_len);
        MT_OK
    })
}

/// call_key/sframe_key (Stage 13, PQ media layer of a call). `call_seed` is 32 bytes (from the E2E signal);
/// out is 64 bytes: call_key(32) || sframe_key(32).
///
/// # Safety
/// `call_seed` is valid for 32 bytes; `out` is valid for 64 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_e2e_call_key(call_seed: *const u8, out: *mut u8) -> c_int {
    guard(|| {
        if call_seed.is_null() || out.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let seed: [u8; 32] = slice::from_raw_parts(call_seed, 32).try_into().unwrap();
        let ck = mt_messenger_e2e::call::call_key(&seed);
        let sf = mt_messenger_e2e::call::sframe_key(&ck);
        let dst = slice::from_raw_parts_mut(out, 64);
        dst[..32].copy_from_slice(&ck);
        dst[32..].copy_from_slice(&sf);
        MT_OK
    })
}
