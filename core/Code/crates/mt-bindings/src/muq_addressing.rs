//! MUQ addressing FFI layer: queue key derivation, Queue serialization, id generation.
//! Complements the transport verbs (network.rs) with an application-client addressing layer:
//! the application builds a queue (recv/send id + keys), serializes it for register, generates id.
//! Logic SSOT is mt_overlay::muq (derive_queue_keypairs, Queue::to_bytes); this is the FFI wrapper.

use mt_crypto::{PUBLIC_KEY_SIZE, SECRET_KEY_SIZE};
use mt_overlay::muq::{derive_queue_keypairs, Queue, QUEUE_ID_SIZE, QUEUE_WIRE_SIZE};

/// Derive queue keys from routing_secret(32)+queue_index — recv/send ML-DSA keypairs.
/// out_recv_pk[1952] out_recv_sk[4032] out_send_pk[1952] out_send_sk[4032]. 0=success, -1=error.
///
/// # Safety
/// routing_secret → 32 B; out_* — valid buffers of the specified sizes.
#[no_mangle]
pub unsafe extern "C" fn mt_muq_derive_queue_keys(
    routing_secret: *const u8,
    queue_index: u64,
    out_recv_pk: *mut u8,
    out_recv_sk: *mut u8,
    out_send_pk: *mut u8,
    out_send_sk: *mut u8,
) -> i32 {
    if routing_secret.is_null()
        || out_recv_pk.is_null()
        || out_recv_sk.is_null()
        || out_send_pk.is_null()
        || out_send_sk.is_null()
    {
        return -1;
    }
    let mut rs = [0u8; 32];
    std::ptr::copy_nonoverlapping(routing_secret, rs.as_mut_ptr(), 32);
    let Ok(((rpk, rsk), (spk, ssk))) = derive_queue_keypairs(&rs, queue_index) else {
        return -1;
    };
    std::ptr::copy_nonoverlapping(rpk.as_bytes().as_ptr(), out_recv_pk, PUBLIC_KEY_SIZE);
    std::ptr::copy_nonoverlapping(rsk.as_bytes().as_ptr(), out_recv_sk, SECRET_KEY_SIZE);
    std::ptr::copy_nonoverlapping(spk.as_bytes().as_ptr(), out_send_pk, PUBLIC_KEY_SIZE);
    std::ptr::copy_nonoverlapping(ssk.as_bytes().as_ptr(), out_send_sk, SECRET_KEY_SIZE);
    0
}

/// Serialize Queue (wire §413) for registration. send_pk null = unsecured queue.
/// Returns: bytes written (QUEUE_WIRE_SIZE) or 0 on error / insufficient buffer.
///
/// # Safety
/// recv_id/send_id/recv_pk → 32/32/1952; send_pk → 1952 or null; out → out_cap bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_muq_queue_serialize(
    recv_id: *const u8,
    send_id: *const u8,
    recv_pk: *const u8,
    send_pk: *const u8,
    rotation_epoch: u64,
    quota: u32,
    out: *mut u8,
    out_cap: usize,
) -> usize {
    if recv_id.is_null() || send_id.is_null() || recv_pk.is_null() || out.is_null() {
        return 0;
    }
    if out_cap < QUEUE_WIRE_SIZE {
        return 0;
    }
    let mut rid = [0u8; QUEUE_ID_SIZE];
    let mut sid = [0u8; QUEUE_ID_SIZE];
    std::ptr::copy_nonoverlapping(recv_id, rid.as_mut_ptr(), QUEUE_ID_SIZE);
    std::ptr::copy_nonoverlapping(send_id, sid.as_mut_ptr(), QUEUE_ID_SIZE);
    let mut rpk = [0u8; PUBLIC_KEY_SIZE];
    std::ptr::copy_nonoverlapping(recv_pk, rpk.as_mut_ptr(), PUBLIC_KEY_SIZE);
    let spk = if send_pk.is_null() {
        None
    } else {
        let mut s = [0u8; PUBLIC_KEY_SIZE];
        std::ptr::copy_nonoverlapping(send_pk, s.as_mut_ptr(), PUBLIC_KEY_SIZE);
        Some(s)
    };
    let q = Queue {
        recv_id: rid,
        send_id: sid,
        recv_pubkey: rpk,
        send_pubkey: spk,
        rotation_epoch,
        quota,
    };
    let bytes = q.to_bytes();
    if bytes.len() > out_cap {
        return 0;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len());
    bytes.len()
}

/// Random QueueId (32 B, OS CSPRNG) — recv_id or send_id. 0=success, -1=error.
///
/// # Safety
/// out — valid for 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_muq_gen_queue_id(out: *mut u8) -> i32 {
    if out.is_null() {
        return -1;
    }
    let mut id = [0u8; QUEUE_ID_SIZE];
    if getrandom::getrandom(&mut id).is_err() {
        return -1;
    }
    std::ptr::copy_nonoverlapping(id.as_ptr(), out, QUEUE_ID_SIZE);
    0
}
