//! Noise_PQ XX handshake C-ABI (spec §5.0): stateful 3-message XX pattern. Secret keys never cross
//! the boundary — intermediate handshake state lives behind opaque `*mut c_void` Box handles.
//! Session output on completion is (sk_i_to_r[32], sk_r_to_i[32], channel_hash = transcript_hash[32]).
#![allow(clippy::missing_safety_doc)]

use core::slice;
use std::ffi::c_void;
use std::os::raw::c_int;

use mt_crypto::{keypair_from_seed, MlkemPublicKey, MlkemSecretKey, PublicKey, SecretKey};
use mt_noise_pq::{
    initiator_receive_msg2, initiator_send_msg1, initiator_send_msg3, responder_receive_msg1,
    responder_receive_msg3, responder_send_msg2, InitiatorMsg1Sent, InitiatorMsg2Received,
    NoisePqSession, ResponderMsg2Sent, NOISE_PQ_MSG1_SIZE, NOISE_PQ_MSG2_SIZE, NOISE_PQ_MSG3_SIZE,
};

use super::{
    guard, MT_ERR_KEYGEN_FAILED, MT_ERR_NULL_PTR, MT_ERR_VERIFY_FAILED, MT_MLDSA_SEED_LEN,
    MT_MLKEM_PUBKEY_SIZE, MT_MLKEM_SECKEY_SIZE, MT_OK,
};

unsafe fn node_id_from_seed(seed_ptr: *const u8) -> Option<(PublicKey, SecretKey)> {
    let mut arr = [0u8; MT_MLDSA_SEED_LEN];
    arr.copy_from_slice(slice::from_raw_parts(seed_ptr, MT_MLDSA_SEED_LEN));
    keypair_from_seed(&arr).ok()
}

unsafe fn write_session(s: &NoisePqSession, ki2r: *mut u8, kr2i: *mut u8, ch: *mut u8) {
    slice::from_raw_parts_mut(ki2r, 32).copy_from_slice(&s.sk_i_to_r);
    slice::from_raw_parts_mut(kr2i, 32).copy_from_slice(&s.sk_r_to_i);
    slice::from_raw_parts_mut(ch, 32).copy_from_slice(&s.transcript_hash);
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_initiator_msg1(
    responder_kem_pk: *const u8,
    node_id_seed: *const u8,
    out_msg1: *mut u8,
    out_state: *mut *mut c_void,
) -> c_int {
    guard(|| {
        if responder_kem_pk.is_null()
            || node_id_seed.is_null()
            || out_msg1.is_null()
            || out_state.is_null()
        {
            return MT_ERR_NULL_PTR;
        }
        let pk = match MlkemPublicKey::from_slice(slice::from_raw_parts(
            responder_kem_pk,
            MT_MLKEM_PUBKEY_SIZE,
        )) {
            Some(k) => k,
            None => return MT_ERR_KEYGEN_FAILED,
        };
        let (id_pk, id_sk) = match node_id_from_seed(node_id_seed) {
            Some(kp) => kp,
            None => return MT_ERR_KEYGEN_FAILED,
        };
        let (wire, state) = match initiator_send_msg1(&pk, id_sk, id_pk) {
            Ok(x) => x,
            Err(_) => return MT_ERR_KEYGEN_FAILED,
        };
        slice::from_raw_parts_mut(out_msg1, NOISE_PQ_MSG1_SIZE).copy_from_slice(&wire);
        *out_state = Box::into_raw(Box::new(state)) as *mut c_void;
        MT_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_initiator_msg2(
    state: *mut *mut c_void,
    msg2: *const u8,
    out_state2: *mut *mut c_void,
) -> c_int {
    guard(|| {
        if state.is_null() || msg2.is_null() || out_state2.is_null() {
            return MT_ERR_NULL_PTR;
        }
        // The state is consumed here unconditionally and the caller pointer is zeroed at once:
        // a repeated free becomes impossible rather than
        // a duty of whoever remembers the contract.
        if (*state).is_null() {
            return MT_ERR_NULL_PTR;
        }
        let st = *Box::from_raw(*state as *mut InitiatorMsg1Sent);
        *state = core::ptr::null_mut();
        let m = slice::from_raw_parts(msg2, NOISE_PQ_MSG2_SIZE);
        let st2 = match initiator_receive_msg2(m, st) {
            Ok(x) => x,
            Err(_) => return MT_ERR_VERIFY_FAILED,
        };
        *out_state2 = Box::into_raw(Box::new(st2)) as *mut c_void;
        MT_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_initiator_msg3(
    state2: *mut *mut c_void,
    out_msg3: *mut u8,
    out_sk_i_to_r: *mut u8,
    out_sk_r_to_i: *mut u8,
    out_channel_hash: *mut u8,
) -> c_int {
    guard(|| {
        if state2.is_null()
            || out_msg3.is_null()
            || out_sk_i_to_r.is_null()
            || out_sk_r_to_i.is_null()
            || out_channel_hash.is_null()
        {
            return MT_ERR_NULL_PTR;
        }
        // The state is consumed here unconditionally and the caller pointer is zeroed at once:
        // a repeated free becomes impossible rather than
        // a duty of whoever remembers the contract.
        if (*state2).is_null() {
            return MT_ERR_NULL_PTR;
        }
        let st2 = *Box::from_raw(*state2 as *mut InitiatorMsg2Received);
        *state2 = core::ptr::null_mut();
        let (wire, session) = match initiator_send_msg3(st2) {
            Ok(x) => x,
            Err(_) => return MT_ERR_KEYGEN_FAILED,
        };
        slice::from_raw_parts_mut(out_msg3, NOISE_PQ_MSG3_SIZE).copy_from_slice(&wire);
        write_session(&session, out_sk_i_to_r, out_sk_r_to_i, out_channel_hash);
        MT_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_responder_msg1(
    responder_kem_sk: *const u8,
    node_id_seed: *const u8,
    msg1: *const u8,
    out_msg2: *mut u8,
    out_state: *mut *mut c_void,
) -> c_int {
    guard(|| {
        if responder_kem_sk.is_null()
            || node_id_seed.is_null()
            || msg1.is_null()
            || out_msg2.is_null()
            || out_state.is_null()
        {
            return MT_ERR_NULL_PTR;
        }
        let sk = match MlkemSecretKey::from_slice(slice::from_raw_parts(
            responder_kem_sk,
            MT_MLKEM_SECKEY_SIZE,
        )) {
            Some(k) => k,
            None => return MT_ERR_KEYGEN_FAILED,
        };
        let (id_pk, id_sk) = match node_id_from_seed(node_id_seed) {
            Some(kp) => kp,
            None => return MT_ERR_KEYGEN_FAILED,
        };
        let m1 = slice::from_raw_parts(msg1, NOISE_PQ_MSG1_SIZE);
        let st1 = match responder_receive_msg1(m1, &sk, id_sk, id_pk) {
            Ok(x) => x,
            Err(_) => return MT_ERR_VERIFY_FAILED,
        };
        let (wire2, st2) = match responder_send_msg2(st1) {
            Ok(x) => x,
            Err(_) => return MT_ERR_KEYGEN_FAILED,
        };
        slice::from_raw_parts_mut(out_msg2, NOISE_PQ_MSG2_SIZE).copy_from_slice(&wire2);
        *out_state = Box::into_raw(Box::new(st2)) as *mut c_void;
        MT_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_responder_msg3(
    state: *mut *mut c_void,
    msg3: *const u8,
    out_sk_i_to_r: *mut u8,
    out_sk_r_to_i: *mut u8,
    out_channel_hash: *mut u8,
) -> c_int {
    guard(|| {
        if state.is_null()
            || msg3.is_null()
            || out_sk_i_to_r.is_null()
            || out_sk_r_to_i.is_null()
            || out_channel_hash.is_null()
        {
            return MT_ERR_NULL_PTR;
        }
        // The same contract as the two other consuming calls and as described in the header:
        // the state is taken unconditionally, the caller pointer is zeroed, nothing is left to free.
        if (*state).is_null() {
            return MT_ERR_NULL_PTR;
        }
        let st2 = *Box::from_raw(*state as *mut ResponderMsg2Sent);
        *state = core::ptr::null_mut();
        let m3 = slice::from_raw_parts(msg3, NOISE_PQ_MSG3_SIZE);
        let session = match responder_receive_msg3(m3, st2) {
            Ok(x) => x,
            Err(_) => return MT_ERR_VERIFY_FAILED,
        };
        write_session(&session, out_sk_i_to_r, out_sk_r_to_i, out_channel_hash);
        MT_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_state_free_initiator1(state: *mut c_void) {
    if !state.is_null() {
        drop(Box::from_raw(state as *mut InitiatorMsg1Sent));
    }
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_state_free_initiator2(state: *mut c_void) {
    if !state.is_null() {
        drop(Box::from_raw(state as *mut InitiatorMsg2Received));
    }
}

#[no_mangle]
pub unsafe extern "C" fn mt_noise_state_free_responder(state: *mut c_void) {
    if !state.is_null() {
        drop(Box::from_raw(state as *mut ResponderMsg2Sent));
    }
}
