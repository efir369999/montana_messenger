//! Check of the names-layer C ABI: what the client sees must match the layer crate.
//! Without this test a divergence would surface on a device, not in the build.

use mt_bindings::ffi_names::*;
use mt_bindings::MT_ERR_NULL_PTR;
use std::ffi::CString;

#[test]
fn normalize_through_ffi() {
    let name = CString::new("@AliceMontana").unwrap();
    let mut out = [0u8; 32];
    let mut len = 0usize;
    let rc = unsafe { mt_name_normalize(name.as_ptr(), out.as_mut_ptr(), out.len(), &mut len) };
    assert_eq!(rc, 0);
    assert_eq!(&out[..len], b"alicemontana");
}

#[test]
fn normalize_refuses_bad_name() {
    for bad in ["abc", "1alice", "alice_", "al__ice", "ALIÇE"] {
        let c = CString::new(bad).unwrap();
        let mut out = [0u8; 32];
        let mut len = 0usize;
        let rc = unsafe { mt_name_normalize(c.as_ptr(), out.as_mut_ptr(), out.len(), &mut len) };
        assert_eq!(rc, MT_ERR_NAME_INVALID, "name {bad}");
    }
}

/// The slot is computed ONLY from the normalised name: raw input is rejected,
/// otherwise the chain would receive a slot of a different name than the one recorded.
#[test]
fn slot_refuses_unnormalized() {
    let raw = CString::new("AliceMontana").unwrap();
    let mut out = [0u8; 32];
    assert_eq!(
        unsafe { mt_name_slot(raw.as_ptr(), out.as_mut_ptr()) },
        MT_ERR_NAME_INVALID
    );

    let ok = CString::new("alicemontana").unwrap();
    assert_eq!(unsafe { mt_name_slot(ok.as_ptr(), out.as_mut_ptr()) }, 0);
    assert_eq!(out, mt_names::slot("alicemontana"));
}

#[test]
fn chain_and_commit_through_ffi() {
    let seed = [0x11u8; 64];
    let slot = mt_names::slot("alicemontana");
    let mut own = [0u8; 32];
    assert_eq!(
        unsafe { mt_name_own(seed.as_ptr(), seed.len(), slot.as_ptr(), own.as_mut_ptr()) },
        0
    );
    assert_eq!(own, mt_names::name_own(&seed, &slot));

    let mut buf = vec![0u8; (mt_names::NAME_CHAIN_LEN + 1) * 32];
    assert_eq!(
        unsafe { mt_name_chain(own.as_ptr(), buf.as_mut_ptr(), buf.len()) },
        0
    );
    let expected = mt_names::chain(&own);
    assert_eq!(&buf[..32], &expected[0][..], "anchor");
    assert_eq!(&buf[128 * 32..], &expected[128][..], "last link");

    let mut cm = [0u8; 32];
    let nonce = [7u8; 32];
    assert_eq!(
        unsafe { mt_name_commit(slot.as_ptr(), nonce.as_ptr(), buf.as_ptr(), cm.as_mut_ptr()) },
        0
    );
    assert_eq!(cm, mt_names::commit(&slot, &nonce, &expected[0]));

    // link check: the anchor is the hash of the first link
    assert_eq!(
        unsafe { mt_name_verify_link(buf.as_ptr(), buf[32..64].as_ptr()) },
        1
    );
    assert_eq!(
        unsafe { mt_name_verify_link(buf.as_ptr(), buf[64..96].as_ptr()) },
        0
    );
}

/// A small buffer is a refusal, not a write past the boundary.
#[test]
fn small_buffer_refused() {
    let own = [0u8; 32];
    let mut small = vec![0u8; 64];
    assert_eq!(
        unsafe { mt_name_chain(own.as_ptr(), small.as_mut_ptr(), small.len()) },
        MT_ERR_NAME_BUFFER
    );
}

/// A null pointer is a refusal, not a crash.
#[test]
fn null_pointers_refused() {
    let mut out = [0u8; 32];
    assert_eq!(
        unsafe { mt_name_slot(std::ptr::null(), out.as_mut_ptr()) },
        MT_ERR_NULL_PTR
    );
    assert_eq!(
        unsafe { mt_name_own(std::ptr::null(), 0, out.as_ptr(), out.as_mut_ptr()) },
        MT_ERR_NULL_PTR
    );
}

/// Puzzle and bucket across the ABI boundary.
#[test]
fn puzzle_and_bucket_through_ffi() {
    let slot = mt_names::slot("anna");
    let eph = vec![0x5Au8; 1184];
    let nonce = 810_487u64.to_le_bytes();
    let mut h = [0u8; 32];
    let solved = unsafe {
        mt_name_puzzle(
            slot.as_ptr(),
            eph.as_ptr(),
            eph.len(),
            nonce.as_ptr(),
            nonce.len(),
            h.as_mut_ptr(),
        )
    };
    assert_eq!(solved, 1, "the spec vector solves the puzzle at 20 bits");
    assert_eq!(h, mt_names::puzzle(&slot, &eph, &nonce));

    let mut b = 0u64;
    assert_eq!(
        unsafe { mt_name_bucket(slot.as_ptr(), 1_000_000, &mut b) },
        0
    );
    assert_eq!(b, mt_names::bucket(&slot, 1_000_000));
}
