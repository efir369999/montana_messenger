//! Smoke test against a LIVE postman (env MT_POSTMAN_*). The full MUQ path of the app client:
//! connect → derive queue → register → send(self) → recv → ack. Skipped if the env is unset.
#![cfg(all(not(target_arch = "wasm32"), feature = "network"))]

use mt_bindings::muq_addressing::*;
use mt_bindings::network::*;
use std::ffi::CString;

fn hex_to_vec(h: &str) -> Vec<u8> {
    (0..h.len())
        .step_by(2)
        .filter_map(|i| u8::from_str_radix(&h[i..i + 2], 16).ok())
        .collect()
}

#[test]
fn smoke_remote_postman() {
    let (Ok(addr), Ok(kem_hex), Ok(overlay_hex)) = (
        std::env::var("MT_POSTMAN_ADDR"),
        std::env::var("MT_POSTMAN_KEM"),
        std::env::var("MT_POSTMAN_OVERLAY"),
    ) else {
        eprintln!("SKIP: MT_POSTMAN_* env not set");
        return;
    };
    let kem = hex_to_vec(&kem_hex);
    let overlay = hex_to_vec(&overlay_hex);
    assert_eq!(kem.len(), 1184, "host_kem 1184 B");
    assert_eq!(overlay.len(), 32, "host_overlay 32 B");

    let c_addr = CString::new(addr.clone()).unwrap();
    let client = unsafe { mt_client_connect(c_addr.as_ptr()) };
    assert!(!client.is_null(), "connect to {addr}");

    // queue from routing_secret
    let rs = [0x42u8; 32];
    let (mut rpk, mut rsk) = ([0u8; 1952], [0u8; 4032]);
    let (mut spk, mut ssk) = ([0u8; 1952], [0u8; 4032]);
    let rc = unsafe {
        mt_muq_derive_queue_keys(
            rs.as_ptr(),
            0,
            rpk.as_mut_ptr(),
            rsk.as_mut_ptr(),
            spk.as_mut_ptr(),
            ssk.as_mut_ptr(),
        )
    };
    assert_eq!(rc, 0, "derive_queue_keys");
    let (mut recv_id, mut send_id) = ([0u8; 32], [0u8; 32]);
    unsafe {
        mt_muq_gen_queue_id(recv_id.as_mut_ptr());
        mt_muq_gen_queue_id(send_id.as_mut_ptr());
    }
    let mut qw = [0u8; 4096];
    let qn = unsafe {
        mt_muq_queue_serialize(
            recv_id.as_ptr(),
            send_id.as_ptr(),
            rpk.as_ptr(),
            spk.as_ptr(),
            0,
            64,
            qw.as_mut_ptr(),
            qw.len(),
        )
    };
    assert!(qn > 0, "queue_serialize");

    let reg =
        unsafe { mt_client_register(client, overlay.as_ptr(), kem.as_ptr(), qw.as_ptr(), qn) };
    assert_eq!(reg, 0, "register on a live postman");

    let msg = b"montana p2p smoke";
    let msg_id = [0x99u8; 16];
    let snd = unsafe {
        mt_client_send(
            client,
            overlay.as_ptr(),
            kem.as_ptr(),
            send_id.as_ptr(),
            ssk.as_ptr(),
            msg_id.as_ptr(),
            msg.as_ptr(),
            msg.len(),
        )
    };
    assert_eq!(snd, 0, "send self");

    let mut out = [0u8; 4096];
    let n = unsafe {
        mt_client_recv(
            client,
            overlay.as_ptr(),
            kem.as_ptr(),
            recv_id.as_ptr(),
            rsk.as_ptr(),
            out.as_mut_ptr(),
            out.len(),
        )
    };
    eprintln!("RECV returned {n} bytes");
    assert!(n > 0, "recv non-empty");

    let ack = unsafe {
        mt_client_ack(
            client,
            overlay.as_ptr(),
            kem.as_ptr(),
            recv_id.as_ptr(),
            rsk.as_ptr(),
        )
    };
    assert_eq!(ack, 0, "ack");
    unsafe { mt_client_free(client) };
    eprintln!("✅ SMOKE OK: live postman {addr} — register/send/recv/ack passed");
}
