//! C ABI of the names layer (checklist "Montana Names", stage A -- "core (mt-bindings)").
//!
//! Only forwarding into `mt_names` here: the logic lives in the layer crate and is not duplicated.
//! Every pointer is checked for null, every length against its bound; nothing escapes
//! outward from a panic.

use crate::{guard, MT_ERR_INVALID_UTF8, MT_ERR_NULL_PTR, MT_OK};
use core::ffi::{c_char, c_int};
use core::slice;
use std::ffi::CStr;

/// The name failed normalisation (section VII). A separate code so the client can show the reason.
pub const MT_ERR_NAME_INVALID: c_int = -30;
/// The caller buffer is too small.
pub const MT_ERR_NAME_BUFFER: c_int = -31;

/// Name normalisation. `out` must hold `NAME_MAX_LEN` bytes; the length is stored in `out_len`.
///
/// # Safety
/// Pointers must be valid, `out` at least 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_normalize(
    name_utf8: *const c_char,
    out: *mut u8,
    out_cap: usize,
    out_len: *mut usize,
) -> c_int {
    guard(|| {
        if name_utf8.is_null() || out.is_null() || out_len.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let s = match CStr::from_ptr(name_utf8).to_str() {
            Ok(s) => s,
            Err(_) => return MT_ERR_INVALID_UTF8,
        };
        let Ok(n) = mt_names::normalize(s) else {
            return MT_ERR_NAME_INVALID;
        };
        if n.len() > out_cap {
            return MT_ERR_NAME_BUFFER;
        }
        slice::from_raw_parts_mut(out, n.len()).copy_from_slice(n.as_bytes());
        *out_len = n.len();
        MT_OK
    })
}

/// Name slot. The name must ALREADY be normalised: the slot is computed from the normalised one,
/// and raw input must not be passed here.
///
/// # Safety
/// `out32` is exactly 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_slot(normalized_utf8: *const c_char, out32: *mut u8) -> c_int {
    guard(|| {
        if normalized_utf8.is_null() || out32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let s = match CStr::from_ptr(normalized_utf8).to_str() {
            Ok(s) => s,
            Err(_) => return MT_ERR_INVALID_UTF8,
        };
        // A normalised name must equal itself: otherwise the slot would be computed
        // from what the person typed, not from what is recorded in the chain.
        if mt_names::normalize(s).as_deref() != Ok(s) {
            return MT_ERR_NAME_INVALID;
        }
        slice::from_raw_parts_mut(out32, 32).copy_from_slice(&mt_names::slot(s));
        MT_OK
    })
}

/// Far end of the name chain: the master-seed branch that yields the slot.
///
/// # Safety
/// `master_seed` is `seed_len` bytes, `slot32` and `out32` are 32 bytes each.
#[no_mangle]
pub unsafe extern "C" fn mt_name_own(
    master_seed: *const u8,
    seed_len: usize,
    slot32: *const u8,
    out32: *mut u8,
) -> c_int {
    guard(|| {
        if master_seed.is_null() || slot32.is_null() || out32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let seed = slice::from_raw_parts(master_seed, seed_len);
        let mut sl = [0u8; 32];
        sl.copy_from_slice(slice::from_raw_parts(slot32, 32));
        slice::from_raw_parts_mut(out32, 32).copy_from_slice(&mt_names::name_own(seed, &sl));
        MT_OK
    })
}

/// The whole renewal chain: `(NAME_CHAIN_LEN + 1) × 32` bytes, link 0 is the anchor.
///
/// # Safety
/// `out` is at least `(NAME_CHAIN_LEN + 1) * 32` bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_chain(
    name_own32: *const u8,
    out: *mut u8,
    out_cap: usize,
) -> c_int {
    guard(|| {
        if name_own32.is_null() || out.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let need = (mt_names::NAME_CHAIN_LEN + 1) * 32;
        if out_cap < need {
            return MT_ERR_NAME_BUFFER;
        }
        let mut own = [0u8; 32];
        own.copy_from_slice(slice::from_raw_parts(name_own32, 32));
        let chain = mt_names::chain(&own);
        let dst = slice::from_raw_parts_mut(out, need);
        for (i, link) in chain.iter().enumerate() {
            dst[i * 32..(i + 1) * 32].copy_from_slice(link);
        }
        MT_OK
    })
}

/// Name commitment.
///
/// # Safety
/// All three inputs are 32 bytes each, `out32` is 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_commit(
    slot32: *const u8,
    blind32: *const u8,
    tip32: *const u8,
    out32: *mut u8,
) -> c_int {
    guard(|| {
        if slot32.is_null() || blind32.is_null() || tip32.is_null() || out32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut s = [0u8; 32];
        s.copy_from_slice(slice::from_raw_parts(slot32, 32));
        let mut b = [0u8; 32];
        b.copy_from_slice(slice::from_raw_parts(blind32, 32));
        let mut t = [0u8; 32];
        t.copy_from_slice(slice::from_raw_parts(tip32, 32));
        slice::from_raw_parts_mut(out32, 32).copy_from_slice(&mt_names::commit(&s, &b, &t));
        MT_OK
    })
}

/// Link check: 1 -- it converges, 0 -- it does not.
///
/// # Safety
/// Both inputs are 32 bytes each.
#[no_mangle]
pub unsafe extern "C" fn mt_name_verify_link(prev32: *const u8, link32: *const u8) -> c_int {
    guard(|| {
        if prev32.is_null() || link32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut p = [0u8; 32];
        p.copy_from_slice(slice::from_raw_parts(prev32, 32));
        let mut l = [0u8; 32];
        l.copy_from_slice(slice::from_raw_parts(link32, 32));
        c_int::from(mt_names::verify_link(&p, &l))
    })
}

/// Lookup key (2²⁰ stretch -- deliberately a slow operation).
///
/// # Safety
/// `out32` is 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_req_key(
    normalized_utf8: *const c_char,
    eph_pk: *const u8,
    eph_len: usize,
    slot32: *const u8,
    out32: *mut u8,
) -> c_int {
    guard(|| {
        if normalized_utf8.is_null() || eph_pk.is_null() || slot32.is_null() || out32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let s = match CStr::from_ptr(normalized_utf8).to_str() {
            Ok(s) => s,
            Err(_) => return MT_ERR_INVALID_UTF8,
        };
        let mut sl = [0u8; 32];
        sl.copy_from_slice(slice::from_raw_parts(slot32, 32));
        let eph = slice::from_raw_parts(eph_pk, eph_len);
        slice::from_raw_parts_mut(out32, 32).copy_from_slice(&mt_names::req_key(s, eph, &sl));
        MT_OK
    })
}

/// Sender puzzle: the hash goes to `out32`, returns 1 if solved at `NAME_PUZZLE_BITS`.
///
/// # Safety
/// `out32` is 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_puzzle(
    slot32: *const u8,
    eph_pk: *const u8,
    eph_len: usize,
    nonce: *const u8,
    nonce_len: usize,
    out32: *mut u8,
) -> c_int {
    guard(|| {
        if slot32.is_null() || eph_pk.is_null() || nonce.is_null() || out32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut sl = [0u8; 32];
        sl.copy_from_slice(slice::from_raw_parts(slot32, 32));
        let h = mt_names::puzzle(
            &sl,
            slice::from_raw_parts(eph_pk, eph_len),
            slice::from_raw_parts(nonce, nonce_len),
        );
        slice::from_raw_parts_mut(out32, 32).copy_from_slice(&h);
        c_int::from(mt_names::puzzle_ok(&h, mt_names::NAME_PUZZLE_BITS))
    })
}

/// Slot bucket given the known number of occupied entries.
///
/// # Safety
/// `slot32` is 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_bucket(
    slot32: *const u8,
    occupied: u64,
    out_bucket: *mut u64,
) -> c_int {
    guard(|| {
        if slot32.is_null() || out_bucket.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let mut sl = [0u8; 32];
        sl.copy_from_slice(slice::from_raw_parts(slot32, 32));
        *out_bucket = mt_names::bucket(&sl, occupied);
        MT_OK
    })
}

/// Name contact key seed: 64 bytes, from which the ML-KEM-768 pair is built.
///
/// # Safety
/// `master_seed` is `seed_len` bytes, `slot32` is 32, `out64` is 64 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_contact_seed(
    master_seed: *const u8,
    seed_len: usize,
    slot32: *const u8,
    out64: *mut u8,
) -> c_int {
    guard(|| {
        if master_seed.is_null() || slot32.is_null() || out64.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let seed = slice::from_raw_parts(master_seed, seed_len);
        let mut sl = [0u8; 32];
        sl.copy_from_slice(slice::from_raw_parts(slot32, 32));
        slice::from_raw_parts_mut(out64, 64).copy_from_slice(&mt_names::contact_seed(seed, &sl));
        MT_OK
    })
}

/// First-contact label for a claimed name: 16 bytes.
///
/// # Safety
/// `contact_root` is `root_len` bytes, `out16` is 16 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_first_tag(
    contact_root: *const u8,
    root_len: usize,
    window: u64,
    out16: *mut u8,
) -> c_int {
    guard(|| {
        if contact_root.is_null() || out16.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let root = slice::from_raw_parts(contact_root, root_len);
        slice::from_raw_parts_mut(out16, 16).copy_from_slice(&mt_names::first_tag(root, window));
        MT_OK
    })
}

/// First-message secret: every subsequent label of this correspondence rests on it.
///
/// # Safety
/// All three inputs are of their own length, `out32` is 32 bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_name_first_secret(
    ss: *const u8,
    ss_len: usize,
    contact_root: *const u8,
    root_len: usize,
    ct: *const u8,
    ct_len: usize,
    out32: *mut u8,
) -> c_int {
    guard(|| {
        if ss.is_null() || contact_root.is_null() || ct.is_null() || out32.is_null() {
            return MT_ERR_NULL_PTR;
        }
        let ss = slice::from_raw_parts(ss, ss_len);
        let root = slice::from_raw_parts(contact_root, root_len);
        let ct = slice::from_raw_parts(ct, ct_len);
        slice::from_raw_parts_mut(out32, 32).copy_from_slice(&mt_names::first_secret(ss, root, ct));
        MT_OK
    })
}
