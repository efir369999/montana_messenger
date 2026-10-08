//! E2E engine C ABI: full encrypt/decrypt flow + handshake through the C ABI.

use mt_bindings::ffi_e2e::{
    mt_e2e_build_handshake, mt_e2e_decrypt, mt_e2e_encrypt, mt_e2e_free, mt_e2e_process_handshake,
};
use mt_messenger_e2e::crypto::{dsa_pub_from_seed, kem_keypair_from_seed};
use mt_messenger_e2e::handshake::account_id;

unsafe fn ffi_encrypt(session: &[u8], pt: &[u8], seed: &[u8; 64]) -> (Vec<u8>, Vec<u8>) {
    let (mut os, mut osl, mut om, mut oml) =
        (std::ptr::null_mut(), 0usize, std::ptr::null_mut(), 0usize);
    let rc = mt_e2e_encrypt(
        session.as_ptr(),
        session.len(),
        pt.as_ptr(),
        pt.len(),
        seed.as_ptr(),
        &mut os,
        &mut osl,
        &mut om,
        &mut oml,
    );
    assert_eq!(rc, 0);
    let s = std::slice::from_raw_parts(os, osl).to_vec();
    let m = std::slice::from_raw_parts(om, oml).to_vec();
    mt_e2e_free(os, osl);
    mt_e2e_free(om, oml);
    (s, m)
}

unsafe fn ffi_decrypt(session: &[u8], msg: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let (mut os, mut osl, mut op, mut opl) =
        (std::ptr::null_mut(), 0usize, std::ptr::null_mut(), 0usize);
    let rc = mt_e2e_decrypt(
        session.as_ptr(),
        session.len(),
        msg.as_ptr(),
        msg.len(),
        &mut os,
        &mut osl,
        &mut op,
        &mut opl,
    );
    assert_eq!(rc, 0);
    let s = std::slice::from_raw_parts(os, osl).to_vec();
    let p = std::slice::from_raw_parts(op, opl).to_vec();
    mt_e2e_free(os, osl);
    mt_e2e_free(op, opl);
    (s, p)
}

#[test]
fn ffi_full_handshake_and_ratchet() {
    let (app_pub, app_sk) = kem_keypair_from_seed(&[0x11; 64]).unwrap();
    let (spk_pub, spk_sk) = kem_keypair_from_seed(&[0x22; 64]).unwrap();
    let bob_pub = dsa_pub_from_seed(&[0x44; 32]).unwrap();
    let alice_pub = dsa_pub_from_seed(&[0x55; 32]).unwrap();
    let bob_id = account_id(&bob_pub);

    unsafe {
        // build (Alice) through the C ABI -- account_seed = [0x55;32]
        let (mut oh, mut ohl, mut os, mut osl) =
            (std::ptr::null_mut(), 0usize, std::ptr::null_mut(), 0usize);
        let rc = mt_e2e_build_handshake(
            alice_pub.as_ptr(),
            [0x55u8; 32].as_ptr(),
            bob_pub.as_ptr(),
            app_pub.as_ptr(),
            spk_pub.as_ptr(),
            7,
            0,
            0,
            std::ptr::null(),
            [0x66u8; 64].as_ptr(),
            1000,
            &mut oh,
            &mut ohl,
            &mut os,
            &mut osl,
        );
        assert_eq!(rc, 0);
        let hs = std::slice::from_raw_parts(oh, ohl).to_vec();
        let alice0 = std::slice::from_raw_parts(os, osl).to_vec();
        mt_e2e_free(oh, ohl);
        mt_e2e_free(os, osl);

        // process (Bob) through the C ABI
        let (mut os2, mut osl2) = (std::ptr::null_mut(), 0usize);
        let rc = mt_e2e_process_handshake(
            hs.as_ptr(),
            hs.len(),
            bob_id.as_ptr(),
            app_pub.as_ptr(),
            app_sk.as_ptr(),
            spk_pub.as_ptr(),
            spk_sk.as_ptr(),
            0,
            std::ptr::null(),
            std::ptr::null(),
            1001,
            604800,
            &mut os2,
            &mut osl2,
        );
        assert_eq!(rc, 0);
        let bob0 = std::slice::from_raw_parts(os2, osl2).to_vec();
        mt_e2e_free(os2, osl2);

        // conversation through the C ABI
        let (alice1, m1) = ffi_encrypt(&alice0, b"ves put cherez FFI", &[0xA1; 64]);
        let (bob1, pt1) = ffi_decrypt(&bob0, &m1);
        assert_eq!(pt1, b"ves put cherez FFI");
        let (_bob2, r1) = ffi_encrypt(&bob1, b"otvet", &[0xB1; 64]);
        let (_alice2, pt2) = ffi_decrypt(&alice1, &r1);
        assert_eq!(pt2, b"otvet");
    }
}
