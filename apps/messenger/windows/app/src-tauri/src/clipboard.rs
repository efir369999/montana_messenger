//! The words onto the clipboard the way a secret goes there on Windows (iOS: UIPasteboard, which keeps no history and syncs
//! only by Handoff the person controls). Windows keeps a clipboard history (Win+V) and may upload it to the cloud clipboard;
//! the platform's own markers keep the text out of both and out of clipboard monitors: ExcludeClipboardContentFromMonitorProcessing,
//! CanIncludeInClipboardHistory = 0, CanUploadToCloudClipboard = 0. The text never passes through the window.

/// A secret: kept out of the history, the cloud and the monitors.
pub fn copy_secret(text: &str) -> bool {
    copy(text, true)
}

/// The clipboard emptied when it still holds that very text (a secret's ninety seconds are over; anything copied since stays).
pub fn clear_if(text: &str) {
    if read().as_deref() == Some(text) {
        copy("", true);
    }
}

#[cfg(windows)]
fn read() -> Option<String> {
    use windows_sys::Win32::System::DataExchange::{CloseClipboard, GetClipboardData, OpenClipboard};
    use windows_sys::Win32::System::Memory::{GlobalLock, GlobalUnlock};
    // SAFETY: the clipboard opened and closed around one read of its Unicode text, locked while it is copied out
    unsafe {
        if OpenClipboard(std::ptr::null_mut()) == 0 {
            return None;
        }
        let h = GetClipboardData(13);
        let mut out = None;
        if !h.is_null() {
            let p = GlobalLock(h) as *const u16;
            if !p.is_null() {
                let mut n = 0;
                while *p.add(n) != 0 && n < 1 << 20 {
                    n += 1;
                }
                out = String::from_utf16(std::slice::from_raw_parts(p, n)).ok();
                GlobalUnlock(h);
            }
        }
        CloseClipboard();
        out
    }
}
#[cfg(not(windows))]
fn read() -> Option<String> {
    None
}

/// Text the person shares on purpose (their link): an ordinary copy.
pub fn copy_text(text: &str) -> bool {
    copy(text, false)
}

#[cfg(windows)]
fn copy(text: &str, secret: bool) -> bool {
    use std::ptr::null_mut;
    use windows_sys::Win32::Foundation::{GlobalFree, HANDLE};
    use windows_sys::Win32::System::DataExchange::{CloseClipboard, EmptyClipboard, OpenClipboard, RegisterClipboardFormatW, SetClipboardData};
    use windows_sys::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};

    const CF_UNICODETEXT: u32 = 13;

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    unsafe fn global(bytes: &[u8]) -> Option<HANDLE> {
        let h = GlobalAlloc(GMEM_MOVEABLE, bytes.len());
        if h.is_null() {
            return None;
        }
        let p = GlobalLock(h) as *mut u8;
        if p.is_null() {
            GlobalFree(h);
            return None;
        }
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), p, bytes.len());
        GlobalUnlock(h);
        Some(h)
    }

    // SAFETY: the clipboard is opened, filled with memory handed over to it, and closed on every path
    unsafe {
        if OpenClipboard(null_mut()) == 0 {
            return false;
        }
        let mut ok = EmptyClipboard() != 0;
        let text16 = wide(text);
        let text_bytes = std::slice::from_raw_parts(text16.as_ptr() as *const u8, text16.len() * 2);
        if ok {
            ok = match global(text_bytes) {
                Some(h) => !SetClipboardData(CF_UNICODETEXT, h).is_null() || { GlobalFree(h); false },
                None => false,
            };
        }
        let zero = 0u32.to_le_bytes();
        for (name, data) in [
            ("ExcludeClipboardContentFromMonitorProcessing", &zero[..]),
            ("CanIncludeInClipboardHistory", &zero[..]),
            ("CanUploadToCloudClipboard", &zero[..]),
        ] {
            if !secret {
                break;
            }
            let f = RegisterClipboardFormatW(wide(name).as_ptr());
            if ok && f != 0 {
                if let Some(h) = global(data) {
                    if SetClipboardData(f, h).is_null() {
                        GlobalFree(h);
                        ok = false; // the text must not stand on the clipboard without its markers
                    }
                }
            }
        }
        if !ok {
            EmptyClipboard();
        }
        CloseClipboard();
        ok
    }
}

#[cfg(not(windows))]
fn copy(_: &str, _: bool) -> bool {
    false
}
