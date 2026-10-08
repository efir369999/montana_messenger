//! Wake C-ABI (Montana P2P Network, Stage 7): byte-exact WakeInline/
//! WakeHandle formats, rung arbiter, account_id↔wake_handle registry. Pure synchronous
//! wrappers over mt-wake — no network stack, available to the client crypto build (iOS/
//! Android). FFI paths do not panic (mt-wake decode returns Result), so
//! catch_unwind is not needed; errors are reported via false/null.
//!
//! Thread-safety: the WakeRegistry handle is NOT synchronized for concurrent &mut —
//! the caller serializes access to a single handle. Format functions are stateless.

use mt_wake::{
    select_rung, WakeHandle, WakeInline, WakeRegistry, ACCOUNT_ID_LEN, RECV_ID_LEN,
    WAKE_HANDLE_LEN, WAKE_HANDLE_MSG_LEN, WAKE_INLINE_LEN,
};

/// Encodes WakeInline (recv_id 32 + window 8 LE) into `out` (40 B). true on success.
///
/// # Safety
/// `recv_id` is valid and ≥32 B; `out` is valid and ≥40 B.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_inline_encode(
    recv_id: *const u8,
    window: u64,
    out: *mut u8,
) -> bool {
    if recv_id.is_null() || out.is_null() {
        return false;
    }
    let mut rid = [0u8; RECV_ID_LEN];
    std::ptr::copy_nonoverlapping(recv_id, rid.as_mut_ptr(), RECV_ID_LEN);
    let enc = WakeInline {
        recv_id: rid,
        window,
    }
    .encode();
    std::ptr::copy_nonoverlapping(enc.as_ptr(), out, WAKE_INLINE_LEN);
    true
}

/// Decodes WakeInline from `input` (len B). On success writes recv_id (32) + window.
///
/// # Safety
/// `input` is valid and ≥`len` B; `out_recv_id` is ≥32 B; `out_window` is valid.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_inline_decode(
    input: *const u8,
    len: usize,
    out_recv_id: *mut u8,
    out_window: *mut u64,
) -> bool {
    if input.is_null() || out_recv_id.is_null() || out_window.is_null() {
        return false;
    }
    let slice = std::slice::from_raw_parts(input, len);
    match WakeInline::decode(slice) {
        Ok(w) => {
            std::ptr::copy_nonoverlapping(w.recv_id.as_ptr(), out_recv_id, RECV_ID_LEN);
            *out_window = w.window;
            true
        },
        Err(_) => false,
    }
}

/// Encodes WakeHandle (wake_handle 16 + window 8 LE) into `out` (24 B). true on success.
///
/// # Safety
/// `handle` is valid and ≥16 B; `out` is valid and ≥24 B.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_handle_encode(
    handle: *const u8,
    window: u64,
    out: *mut u8,
) -> bool {
    if handle.is_null() || out.is_null() {
        return false;
    }
    let mut h = [0u8; WAKE_HANDLE_LEN];
    std::ptr::copy_nonoverlapping(handle, h.as_mut_ptr(), WAKE_HANDLE_LEN);
    let enc = WakeHandle {
        wake_handle: h,
        window,
    }
    .encode();
    std::ptr::copy_nonoverlapping(enc.as_ptr(), out, WAKE_HANDLE_MSG_LEN);
    true
}

/// Decodes WakeHandle from `input` (len B). On success writes wake_handle (16) + window.
///
/// # Safety
/// `input` is valid and ≥`len` B; `out_handle` is ≥16 B; `out_window` is valid.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_handle_decode(
    input: *const u8,
    len: usize,
    out_handle: *mut u8,
    out_window: *mut u64,
) -> bool {
    if input.is_null() || out_handle.is_null() || out_window.is_null() {
        return false;
    }
    let slice = std::slice::from_raw_parts(input, len);
    match WakeHandle::decode(slice) {
        Ok(w) => {
            std::ptr::copy_nonoverlapping(w.wake_handle.as_ptr(), out_handle, WAKE_HANDLE_LEN);
            *out_window = w.window;
            true
        },
        Err(_) => false,
    }
}

/// Rung arbiter: returns the rung number 1–4 (highest sovereignty first).
#[no_mangle]
pub extern "C" fn mt_wake_select_rung(
    live_tunnel: bool,
    ibeacon_home: bool,
    unlock_sync: bool,
) -> u8 {
    select_rung(live_tunnel, ibeacon_home, unlock_sync) as u8
}

/// Creates an account_id↔wake_handle registry (for the postman phone). Freed by
/// `mt_wake_registry_free`.
#[no_mangle]
pub extern "C" fn mt_wake_registry_new() -> *mut WakeRegistry {
    Box::into_raw(Box::new(WakeRegistry::new()))
}

/// # Safety
/// `reg` is a pointer from `mt_wake_registry_new` (not used after free) or null.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_registry_free(reg: *mut WakeRegistry) {
    if !reg.is_null() {
        drop(Box::from_raw(reg));
    }
}

/// Registers account_id (32 B), writes the 16 B wake_handle. Idempotent. true on success.
///
/// # Safety
/// `reg` is valid; `account_id` is ≥32 B; `out_handle` is ≥16 B.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_register(
    reg: *mut WakeRegistry,
    account_id: *const u8,
    out_handle: *mut u8,
) -> bool {
    if reg.is_null() || account_id.is_null() || out_handle.is_null() {
        return false;
    }
    let mut acc = [0u8; ACCOUNT_ID_LEN];
    std::ptr::copy_nonoverlapping(account_id, acc.as_mut_ptr(), ACCOUNT_ID_LEN);
    match (*reg).register(acc) {
        Ok(h) => {
            std::ptr::copy_nonoverlapping(h.as_ptr(), out_handle, WAKE_HANDLE_LEN);
            true
        },
        Err(_) => false,
    }
}

/// Looks up wake_handle by account_id. true if found (writes out_handle), else false.
///
/// # Safety
/// `reg` is valid; `account_id` is ≥32 B; `out_handle` is ≥16 B.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_handle_of(
    reg: *const WakeRegistry,
    account_id: *const u8,
    out_handle: *mut u8,
) -> bool {
    if reg.is_null() || account_id.is_null() || out_handle.is_null() {
        return false;
    }
    let mut acc = [0u8; ACCOUNT_ID_LEN];
    std::ptr::copy_nonoverlapping(account_id, acc.as_mut_ptr(), ACCOUNT_ID_LEN);
    match (*reg).handle_of(&acc) {
        Some(h) => {
            std::ptr::copy_nonoverlapping(h.as_ptr(), out_handle, WAKE_HANDLE_LEN);
            true
        },
        None => false,
    }
}

/// Resolves account_id by wake_handle (postman, rung 4). true if found.
///
/// # Safety
/// `reg` is valid; `handle` is ≥16 B; `out_account` is ≥32 B.
#[no_mangle]
pub unsafe extern "C" fn mt_wake_account_of(
    reg: *const WakeRegistry,
    handle: *const u8,
    out_account: *mut u8,
) -> bool {
    if reg.is_null() || handle.is_null() || out_account.is_null() {
        return false;
    }
    let mut h = [0u8; WAKE_HANDLE_LEN];
    std::ptr::copy_nonoverlapping(handle, h.as_mut_ptr(), WAKE_HANDLE_LEN);
    match (*reg).account_of(&h) {
        Some(acc) => {
            std::ptr::copy_nonoverlapping(acc.as_ptr(), out_account, ACCOUNT_ID_LEN);
            true
        },
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_inline_roundtrip() {
        let recv_id = [0x11u8; 32];
        let mut enc = [0u8; 40];
        unsafe {
            assert!(mt_wake_inline_encode(
                recv_id.as_ptr(),
                42,
                enc.as_mut_ptr()
            ));
        }
        let mut rid = [0u8; 32];
        let mut win = 0u64;
        unsafe {
            assert!(mt_wake_inline_decode(
                enc.as_ptr(),
                enc.len(),
                rid.as_mut_ptr(),
                &mut win
            ));
        }
        assert_eq!(rid, recv_id);
        assert_eq!(win, 42);
    }

    #[test]
    fn ffi_handle_roundtrip() {
        let handle = [0x22u8; 16];
        let mut enc = [0u8; 24];
        unsafe {
            assert!(mt_wake_handle_encode(handle.as_ptr(), 7, enc.as_mut_ptr()));
        }
        let mut h = [0u8; 16];
        let mut win = 0u64;
        unsafe {
            assert!(mt_wake_handle_decode(
                enc.as_ptr(),
                enc.len(),
                h.as_mut_ptr(),
                &mut win
            ));
        }
        assert_eq!(h, handle);
        assert_eq!(win, 7);
    }

    #[test]
    fn ffi_decode_invalid_len() {
        let short = [0u8; 39];
        let mut rid = [0u8; 32];
        let mut win = 0u64;
        unsafe {
            assert!(!mt_wake_inline_decode(
                short.as_ptr(),
                short.len(),
                rid.as_mut_ptr(),
                &mut win
            ));
        }
    }

    #[test]
    fn ffi_select_rung_priority() {
        assert_eq!(mt_wake_select_rung(true, false, false), 1);
        assert_eq!(mt_wake_select_rung(false, true, false), 2);
        assert_eq!(mt_wake_select_rung(false, false, true), 3);
        assert_eq!(mt_wake_select_rung(false, false, false), 4);
    }

    #[test]
    fn ffi_registry_idempotent_and_reverse() {
        let reg = mt_wake_registry_new();
        let acc = [0x33u8; 32];
        let mut h1 = [0u8; 16];
        let mut h2 = [0u8; 16];
        unsafe {
            assert!(mt_wake_register(reg, acc.as_ptr(), h1.as_mut_ptr()));
            assert!(mt_wake_register(reg, acc.as_ptr(), h2.as_mut_ptr()));
        }
        assert_eq!(h1, h2);
        let mut acc_out = [0u8; 32];
        unsafe {
            assert!(mt_wake_account_of(reg, h1.as_ptr(), acc_out.as_mut_ptr()));
            mt_wake_registry_free(reg);
        }
        assert_eq!(acc_out, acc);
    }

    #[test]
    fn ffi_null_safe() {
        let mut out = [0u8; 40];
        unsafe {
            assert!(!mt_wake_inline_encode(
                std::ptr::null(),
                0,
                out.as_mut_ptr()
            ));
            assert!(!mt_wake_account_of(
                std::ptr::null(),
                out.as_ptr(),
                out.as_mut_ptr()
            ));
        }
    }
}
