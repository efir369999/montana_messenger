//! Local self-host register: postman on loopback + connect to self + direct register.
//! Reproduces the iOS self-host path natively to diagnose register failures.
#![cfg(all(not(target_arch = "wasm32"), feature = "network"))]

use mt_bindings::muq_addressing::*;
use mt_bindings::network::*;
use std::ffi::CString;

#[test]
fn smoke_local_selfhost_register() {
    let bind = CString::new("127.0.0.1:0").unwrap();
    let mut portbuf = [0i8; 64];
    let postman = unsafe { mt_postman_start(bind.as_ptr(), portbuf.as_mut_ptr(), 64) };
    assert!(!postman.is_null(), "postman start");
    let port = unsafe { mt_postman_port(postman) };
    assert!(port > 0, "port>0");
    let mut kem = [0u8; 1184];
    let kn = unsafe { mt_postman_kem_pubkey(postman, kem.as_mut_ptr(), 1184) };
    assert_eq!(kn, 1184, "kem 1184");

    let addr = CString::new(format!("127.0.0.1:{port}")).unwrap();
    let client = unsafe { mt_client_connect(addr.as_ptr()) };
    assert!(!client.is_null(), "connect loopback");

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
    assert_eq!(rc, 0, "derive keys");
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
            std::ptr::null(),
            1,
            64,
            qw.as_mut_ptr(),
            qw.len(),
        )
    };
    eprintln!("QUEUE WIRE LEN = {qn}");
    assert!(qn > 0, "serialize qn>0");

    let reg = unsafe { mt_client_register_direct(client, qw.as_ptr(), qn) };
    eprintln!("REGISTER_DIRECT = {reg}  (0=ok, -1=fail)");
    assert_eq!(reg, 0, "self-host DIRECT register on loopback");
}
