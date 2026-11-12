//! mDNS discovery of Montana nodes on the local network (Montana P2P Network, Stage 6, item 3):
//! `_montana._udp.local`. Sub-mode A′ of Stage 5 — two phones on the same Wi-Fi find
//! each other without configuration and without DHT. Discovery layer: an address from mDNS is verified further
//! (E2E / overlay), mDNS compromise = wrong address → detected, not breach.

use std::ffi::CString;
use std::os::raw::c_char;
use std::time::Duration;

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};

const SERVICE_TYPE: &str = "_montana._udp.local.";

/// Opaque handle to the mDNS daemon (keeps the service registration alive).
pub struct MtMdns {
    daemon: ServiceDaemon,
}

/// Advertise this node's postman on the local network on port `port`. Returns a handle
/// (the daemon keeps the advertisement alive) or null. `instance` — C-string instance name.
///
/// # Safety
/// `instance` — valid C-string or null.
#[no_mangle]
pub unsafe extern "C" fn mt_mdns_advertise(port: u16, instance: *const c_char) -> *mut MtMdns {
    let name = if instance.is_null() {
        "montana-node".to_string()
    } else {
        match std::ffi::CStr::from_ptr(instance).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return std::ptr::null_mut(),
        }
    };
    let Ok(daemon) = ServiceDaemon::new() else {
        return std::ptr::null_mut();
    };
    let host = format!("{name}.local.");
    let Ok(info) = ServiceInfo::new(SERVICE_TYPE, &name, &host, "", port, None) else {
        return std::ptr::null_mut();
    };
    let info = info.enable_addr_auto(); // auto interface addresses
    if daemon.register(info).is_err() {
        return std::ptr::null_mut();
    }
    Box::into_raw(Box::new(MtMdns { daemon }))
}

/// Find Montana nodes on the local network within `timeout_ms`. Writes found addresses into `out`
/// as "ip:port\n"-separated ASCII (capacity `out_cap`, null-terminated), returns
/// the number of nodes found (0 if none / error).
///
/// # Safety
/// `out` — buffer ≥ `out_cap` bytes or null.
#[no_mangle]
pub unsafe extern "C" fn mt_mdns_browse(timeout_ms: u32, out: *mut u8, out_cap: usize) -> usize {
    let Ok(daemon) = ServiceDaemon::new() else {
        return 0;
    };
    let Ok(receiver) = daemon.browse(SERVICE_TYPE) else {
        return 0;
    };
    let deadline = Duration::from_millis(timeout_ms as u64);
    let mut found: Vec<String> = Vec::new();
    // collect ServiceResolved until the deadline
    let start = std::time::Instant::now();
    while start.elapsed() < deadline {
        let remaining = deadline.saturating_sub(start.elapsed());
        match receiver.recv_timeout(remaining) {
            Ok(ServiceEvent::ServiceResolved(info)) => {
                let port = info.get_port();
                for addr in info.get_addresses() {
                    let ep = format!("{addr}:{port}");
                    if !found.contains(&ep) {
                        found.push(ep);
                    }
                }
            },
            Ok(_) => continue,
            Err(_) => break,
        }
    }
    let _ = daemon.shutdown();

    if !out.is_null() && out_cap > 0 {
        let joined = found.join("\n");
        if let Ok(cs) = CString::new(joined) {
            let bytes = cs.as_bytes_with_nul();
            if bytes.len() <= out_cap {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len());
            }
        }
    }
    found.len()
}

/// Stop the advertisement and free the handle.
///
/// # Safety
/// `h` — handle from `mt_mdns_advertise` or null; do not reuse.
#[no_mangle]
pub unsafe extern "C" fn mt_mdns_stop(h: *mut MtMdns) {
    if h.is_null() {
        return;
    }
    let m = Box::from_raw(h);
    let _ = m.daemon.shutdown();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn advertise_handle_and_stop() {
        let instance = CString::new("test-node").unwrap();
        let h = unsafe { mt_mdns_advertise(8444, instance.as_ptr()) };
        assert!(!h.is_null(), "mDNS announce started");
        unsafe { mt_mdns_stop(h) };
        // null is safe
        unsafe { mt_mdns_stop(std::ptr::null_mut()) };
    }

    #[test]
    fn browse_short_timeout_no_crash() {
        // short browse must not panic; count ≥ 0 (usually 0 in sandbox)
        let mut out = [0u8; 512];
        let n = unsafe { mt_mdns_browse(300, out.as_mut_ptr(), out.len()) };
        let _ = n; // multicast may be unavailable in CI/sandbox — the point is no panic
    }
}
