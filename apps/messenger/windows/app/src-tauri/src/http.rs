//! One POST of JSON to a node's door (iOS URLSession; Android Wire.post), by Windows' own WinHTTP: the system's TLS and its
//! certificate store, no crate of our own on the road. The code and the body; a door that does not answer is -1.

#[cfg(windows)]
pub fn post(url: &str, body: &str, timeout_ms: u32) -> (i32, Option<String>) {
    use std::ptr::{null, null_mut};
    use windows_sys::Win32::Networking::WinHttp::*;

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }
    let Some(rest) = url.strip_prefix("https://") else { return (-1, None) };
    let (host, path) = rest.split_once('/').map(|(h, p)| (h, format!("/{p}"))).unwrap_or((rest, "/".into()));
    let (host, port) = match host.split_once(':') {
        Some((h, p)) => (h, p.parse::<u16>().unwrap_or(443)),
        None => (host, 443u16),
    };

    // SAFETY: every handle is opened, checked and closed on every path; the buffers outlive the calls that read them
    unsafe {
        let session = WinHttpOpen(wide("Montana-Windows/0.1").as_ptr(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null(), null(), 0);
        if session.is_null() {
            return (-1, None);
        }
        let t = timeout_ms as i32;
        WinHttpSetTimeouts(session, t, t, t, t);
        let connect = WinHttpConnect(session, wide(host).as_ptr(), port, 0);
        let mut result = (-1, None);
        if !connect.is_null() {
            let request = WinHttpOpenRequest(connect, wide("POST").as_ptr(), wide(&path).as_ptr(), null(), null(), null(), WINHTTP_FLAG_SECURE);
            if !request.is_null() {
                let headers = wide("Content-Type: application/json\r\n");
                let bytes = body.as_bytes();
                let sent = WinHttpSendRequest(request, headers.as_ptr(), u32::MAX, bytes.as_ptr() as *const _, bytes.len() as u32, bytes.len() as u32, 0) != 0
                    && WinHttpReceiveResponse(request, null_mut()) != 0;
                if sent {
                    let mut code: u32 = 0;
                    let mut size = std::mem::size_of::<u32>() as u32;
                    WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, null(), &mut code as *mut u32 as *mut _, &mut size, null_mut());
                    // the node's own second (its Date header): a second of the person on the network (person.rs)
                    let mut st: windows_sys::Win32::Foundation::SYSTEMTIME = std::mem::zeroed();
                    let mut size = std::mem::size_of::<windows_sys::Win32::Foundation::SYSTEMTIME>() as u32;
                    if WinHttpQueryHeaders(request, WINHTTP_QUERY_DATE | WINHTTP_QUERY_FLAG_SYSTEMTIME, null(), &mut st as *mut _ as *mut _, &mut size, null_mut()) != 0 {
                        crate::person::clock(unix_of(st.wYear as i64, st.wMonth as i64, st.wDay as i64, st.wHour as i64, st.wMinute as i64, st.wSecond as i64));
                    }
                    let mut data = Vec::new();
                    loop {
                        let mut avail: u32 = 0;
                        if WinHttpQueryDataAvailable(request, &mut avail) == 0 || avail == 0 {
                            break;
                        }
                        let at = data.len();
                        data.resize(at + avail as usize, 0);
                        let mut read: u32 = 0;
                        if WinHttpReadData(request, data[at..].as_mut_ptr() as *mut _, avail, &mut read) == 0 {
                            break;
                        }
                        data.truncate(at + read as usize);
                    }
                    result = (code as i32, Some(String::from_utf8_lossy(&data).into_owned()));
                }
                WinHttpCloseHandle(request);
            }
            WinHttpCloseHandle(connect);
        }
        WinHttpCloseHandle(session);
        result
    }
}

#[cfg(not(windows))]
pub fn post(_: &str, _: &str, _: u32) -> (i32, Option<String>) {
    (-1, None)
}

/// A civil moment of UTC as Unix seconds (the days from the civil date, Howard Hinnant's algorithm).
pub fn unix_of(y: i64, m: i64, d: i64, hh: i64, mm: i64, ss: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    (era * 146_097 + doe - 719_468) * 86_400 + hh * 3600 + mm * 60 + ss
}

/// ONE GET OF A PAGE SOMEONE SHARES (iOS MTLinkPreview.fetchData): http or https, Windows' own redirects, at most `limit`
/// bytes; with `head` the read stops once the page's head closed -- everything a card is made of lives there. The code and the
/// bytes; nothing when nobody answered.
#[cfg(windows)]
pub fn get(url: &str, timeout_ms: u32, limit: usize, head: bool) -> Option<(i32, Vec<u8>)> {
    get_with(url, "Mozilla/5.0 (Windows NT 10.0) MontanaPreview/1", &[], timeout_ms, limit, head).map(|(c, d, _)| (c, d))
}

type Headers = Vec<(String, String)>;

/// A GET with the request's own headers, answering the code, the bytes and the answer's headers (lower-case names) -- a VPN plan's
/// panel reads a device by `x-hwid` and names the plan in `profile-title` (iOS MontanaVPNSubscription.request).
#[cfg(windows)]
pub fn get_with(url: &str, agent: &str, extra: &[(&str, &str)], timeout_ms: u32, limit: usize, head: bool)
    -> Option<(i32, Vec<u8>, Headers)> {
    use std::ptr::{null, null_mut};
    use windows_sys::Win32::Networking::WinHttp::*;

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }
    let (secure, rest) = match (url.strip_prefix("https://"), url.strip_prefix("http://")) {
        (Some(r), _) => (true, r),
        (_, Some(r)) => (false, r),
        _ => return None,
    };
    let rest = rest.split('#').next().unwrap_or("");
    let cut = rest.find(['/', '?']).unwrap_or(rest.len());
    let (host, path) = (&rest[..cut], &rest[cut..]);
    let path = if path.starts_with('/') { path.to_string() } else { format!("/{path}") };
    let (host, port) = match host.rsplit_once(':') {
        Some((h, p)) if p.chars().all(|c| c.is_ascii_digit()) => (h, p.parse::<u16>().ok()?),
        _ => (host, if secure { 443 } else { 80 }),
    };
    if host.is_empty() || host.contains('@') {
        return None;
    }
    // SAFETY: every handle is opened, checked and closed on every path; the buffers outlive the calls that read them
    unsafe {
        let session = WinHttpOpen(wide(agent).as_ptr(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null(), null(), 0);
        if session.is_null() {
            return None;
        }
        let t = timeout_ms as i32;
        WinHttpSetTimeouts(session, t, t, t, t);
        let connect = WinHttpConnect(session, wide(host).as_ptr(), port, 0);
        let mut result = None;
        if !connect.is_null() {
            let request = WinHttpOpenRequest(connect, wide("GET").as_ptr(), wide(&path).as_ptr(), null(), null(), null(),
                                             if secure { WINHTTP_FLAG_SECURE } else { 0 });
            if !request.is_null() {
                let lines: String = extra.iter().map(|(k, v)| format!("{k}: {v}\r\n")).collect();
                let hw = wide(&lines);
                let sent = WinHttpSendRequest(request, if lines.is_empty() { null() } else { hw.as_ptr() }, if lines.is_empty() { 0 } else { u32::MAX },
                                              null(), 0, 0, 0) != 0
                    && WinHttpReceiveResponse(request, null_mut()) != 0;
                if sent {
                    let mut code: u32 = 0;
                    let mut size = std::mem::size_of::<u32>() as u32;
                    WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, null(), &mut code as *mut u32 as *mut _, &mut size, null_mut());
                    // the answer's headers, every line "name: value"
                    let mut hsize: u32 = 0;
                    WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, null(), null_mut(), &mut hsize, null_mut());
                    let mut heads = Vec::new();
                    if hsize > 0 {
                        let mut buf = vec![0u16; hsize as usize / 2 + 1];
                        if WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, null(), buf.as_mut_ptr() as *mut _, &mut hsize, null_mut()) != 0 {
                            let text = String::from_utf16_lossy(&buf[..hsize as usize / 2]);
                            for line in text.split("\r\n").skip(1) {
                                if let Some((k, v)) = line.split_once(':') {
                                    heads.push((k.trim().to_lowercase(), v.trim().to_string()));
                                }
                            }
                        }
                    }
                    let mut data = Vec::new();
                    while data.len() < limit {
                        let mut avail: u32 = 0;
                        if WinHttpQueryDataAvailable(request, &mut avail) == 0 || avail == 0 {
                            break;
                        }
                        let take = (avail as usize).min(limit - data.len());
                        let at = data.len();
                        data.resize(at + take, 0);
                        let mut read: u32 = 0;
                        if WinHttpReadData(request, data[at..].as_mut_ptr() as *mut _, take as u32, &mut read) == 0 {
                            break;
                        }
                        data.truncate(at + read as usize);
                        if head && data[at.saturating_sub(8)..].windows(5).any(|w| w.eq_ignore_ascii_case(b"/head")) {
                            break;
                        }
                    }
                    result = Some((code as i32, data, heads));
                }
                WinHttpCloseHandle(request);
            }
            WinHttpCloseHandle(connect);
        }
        WinHttpCloseHandle(session);
        result
    }
}

#[cfg(not(windows))]
pub fn get(_: &str, _: u32, _: usize, _: bool) -> Option<(i32, Vec<u8>)> {
    None
}
#[cfg(not(windows))]
pub fn get_with(_: &str, _: &str, _: &[(&str, &str)], _: u32, _: usize, _: bool) -> Option<(i32, Vec<u8>, Headers)> {
    None
}

/// What a request carries: nothing, bytes, or a file read a megabyte at a time.
pub enum Body<'a> {
    None,
    Bytes(&'a [u8]),
    File(&'a std::path::Path),
}
/// Where an answer goes: memory (at most so many bytes), or a file written as it comes.
pub enum Sink<'a> {
    Memory(usize),
    File(&'a std::path::Path),
}
/// The node's answer: its code, the bytes kept in memory, its headers (lower-case names).
#[derive(Debug, Default)]
pub struct Answer {
    pub code: i32,
    pub body: Vec<u8>,
    pub heads: Vec<(String, String)>,
}
impl Answer {
    pub fn head(&self, name: &str) -> Option<&str> {
        self.heads.iter().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
    }
}
/// Why no answer came: the certificate was not the one pinned (nothing of the request left), or the door did not answer.
#[derive(Debug, PartialEq)]
pub enum Silence {
    NotPinned,
    NoAnswer(u32),
}

/// ONE REQUEST TO ONE'S OWN NODE (iOS HomeNodeWatch over URLSession with MTNodeTrust): any method, the request's headers, a body
/// streamed from a file, an answer into a file. `pin` -- the SHA-256 (hex) of the certificate the node made for itself (iOS
/// MontanaNodeSetup): the digest is then the whole trust, the system's judgement of a certificate with no name and no authority
/// set aside, and it is checked when the handshake is done and before a byte of the request leaves (WinHTTP's SENDING_REQUEST)
/// -- the token rides only to the machine the person named. `progress` hears the share of the bytes sent, then of those come.
#[cfg(windows)]
#[allow(clippy::too_many_arguments)]
pub fn exchange(method: &str, url: &str, headers: &[(&str, &str)], body: Body, sink: Sink, pin: Option<&str>, timeout_ms: u32,
                progress: &dyn Fn(f64)) -> Result<Answer, Silence> {
    use std::io::{Read, Write};
    use std::ptr::{null, null_mut};
    use windows_sys::Win32::Networking::WinHttp::*;
    use windows_sys::Win32::Security::Cryptography::{CertFreeCertificateContext, CERT_CONTEXT};

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }
    /// What the callback reads and says: the pin, and whether the certificate shown was another.
    struct Trust {
        pin: [u8; 32],
        refused: std::sync::atomic::AtomicBool,
    }
    unsafe extern "system" fn shown(h: *mut core::ffi::c_void, ctx: usize, status: u32, _: *mut core::ffi::c_void, _: u32) {
        if status != WINHTTP_CALLBACK_STATUS_SENDING_REQUEST || ctx == 0 {
            return;
        }
        let trust = &*(ctx as *const Trust);
        let mut cert: *const CERT_CONTEXT = null();
        let mut size = std::mem::size_of::<*const CERT_CONTEXT>() as u32;
        let same = WinHttpQueryOption(h, WINHTTP_OPTION_SERVER_CERT_CONTEXT, &mut cert as *mut _ as *mut _, &mut size) != 0 && !cert.is_null() && {
            let der = std::slice::from_raw_parts((*cert).pbCertEncoded, (*cert).cbCertEncoded as usize);
            let d = crate::wire::sha(&[der]);
            CertFreeCertificateContext(cert);
            d == trust.pin
        };
        if !same {
            // another certificate: the request is cancelled here, before its headers (the token) leave
            trust.refused.store(true, std::sync::atomic::Ordering::SeqCst);
            WinHttpCloseHandle(h);
        }
    }

    let silent = |e: u32| Err(Silence::NoAnswer(e));
    let (secure, rest) = match (url.strip_prefix("https://"), url.strip_prefix("http://")) {
        (Some(r), _) => (true, r),
        (_, Some(r)) => (false, r),
        _ => return silent(0),
    };
    let cut = rest.find(['/', '?']).unwrap_or(rest.len());
    let (host, path) = (&rest[..cut], &rest[cut..]);
    let path = if path.starts_with('/') { path.to_string() } else { format!("/{path}") };
    let (host, port) = match host.rsplit_once(':') {
        Some((h, p)) if p.chars().all(|c| c.is_ascii_digit()) => (h, p.parse::<u16>().unwrap_or(443)),
        _ => (host, if secure { 443 } else { 80 }),
    };
    let pin = match pin.filter(|p| !p.is_empty()) {
        Some(p) => Some(crate::wire::unhex(p).and_then(|b| <[u8; 32]>::try_from(b).ok()).ok_or(Silence::NotPinned)?),
        None => None,
    };
    if host.is_empty() || host.contains('@') || (pin.is_some() && !secure) {
        return silent(0);
    }
    let (mut file, total): (Option<std::fs::File>, u64) = match &body {
        Body::None => (None, 0),
        Body::Bytes(b) => (None, b.len() as u64),
        Body::File(p) => match std::fs::File::open(p) {
            Ok(f) => {
                let n = f.metadata().map(|m| m.len()).unwrap_or(0);
                (Some(f), n)
            }
            Err(_) => return silent(0),
        },
    };
    let trust = Box::new(Trust { pin: pin.unwrap_or([0; 32]), refused: std::sync::atomic::AtomicBool::new(false) });
    // SAFETY: every handle is opened, checked and closed on every path; the trust outlives the request whose callback reads it;
    // the buffers outlive the calls that read them
    unsafe {
        let session = WinHttpOpen(wide("Montana-Windows/0.1").as_ptr(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null(), null(), 0);
        if session.is_null() {
            return silent(windows_sys::Win32::Foundation::GetLastError());
        }
        let t = timeout_ms as i32;
        WinHttpSetTimeouts(session, t, t, t, t);
        let connect = WinHttpConnect(session, wide(host).as_ptr(), port, 0);
        let mut result: Result<Answer, Silence> = silent(0);
        if !connect.is_null() {
            let request = WinHttpOpenRequest(connect, wide(method).as_ptr(), wide(&path).as_ptr(), null(), null(), null(),
                                             if secure { WINHTTP_FLAG_SECURE } else { 0 });
            let mut open = !request.is_null();
            if open {
                if pin.is_some() {
                    // the digest is the whole trust: the system's verdict on a self-made certificate is set aside, and checked here
                    let mut flags: u32 = SECURITY_FLAG_IGNORE_UNKNOWN_CA | SECURITY_FLAG_IGNORE_CERT_CN_INVALID | SECURITY_FLAG_IGNORE_CERT_DATE_INVALID
                        | SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE;
                    WinHttpSetOption(request, WINHTTP_OPTION_SECURITY_FLAGS, &mut flags as *mut u32 as *mut _, 4);
                    let mut ctx = &*trust as *const Trust as usize;
                    WinHttpSetOption(request, WINHTTP_OPTION_CONTEXT_VALUE, &mut ctx as *mut usize as *mut _, std::mem::size_of::<usize>() as u32);
                    // winhttp.h's WINHTTP_CALLBACK_FLAG_SEND_REQUEST: the sending and the sent of the request
                    WinHttpSetStatusCallback(request, Some(shown), WINHTTP_CALLBACK_STATUS_SENDING_REQUEST | WINHTTP_CALLBACK_STATUS_REQUEST_SENT, 0);
                }
                let lines: String = headers.iter().map(|(k, v)| format!("{k}: {v}\r\n")).collect();
                let hw = wide(&lines);
                let (first, first_len) = match &body {
                    Body::Bytes(b) => (b.as_ptr() as *const core::ffi::c_void, b.len() as u32),
                    _ => (null(), 0),
                };
                let mut ok = WinHttpSendRequest(request, if lines.is_empty() { null() } else { hw.as_ptr() }, if lines.is_empty() { 0 } else { u32::MAX },
                                                first, first_len, total.min(u32::MAX as u64) as u32, 0) != 0;
                if trust.refused.load(std::sync::atomic::Ordering::SeqCst) {
                    open = false; // the callback closed it: nothing of the request left
                    ok = false;
                }
                // the body streamed after the head: a megabyte at a time, the share told as it goes
                if ok {
                    if let Some(f) = file.as_mut() {
                        let mut buf = vec![0u8; 1 << 20];
                        let mut sent: u64 = 0;
                        loop {
                            let n = match f.read(&mut buf) {
                                Ok(0) => break,
                                Ok(n) => n,
                                Err(_) => {
                                    ok = false;
                                    break;
                                }
                            };
                            let mut wrote: u32 = 0;
                            if WinHttpWriteData(request, buf.as_ptr() as *const _, n as u32, &mut wrote) == 0 || wrote as usize != n {
                                ok = false;
                                break;
                            }
                            sent += n as u64;
                            progress(sent as f64 / total.max(1) as f64);
                        }
                    }
                }
                ok = ok && WinHttpReceiveResponse(request, null_mut()) != 0;
                if ok {
                    let mut code: u32 = 0;
                    let mut size = std::mem::size_of::<u32>() as u32;
                    WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, null(), &mut code as *mut u32 as *mut _, &mut size, null_mut());
                    let mut heads = Vec::new();
                    let mut hsize: u32 = 0;
                    WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, null(), null_mut(), &mut hsize, null_mut());
                    if hsize > 0 {
                        let mut buf = vec![0u16; hsize as usize / 2 + 1];
                        if WinHttpQueryHeaders(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, null(), buf.as_mut_ptr() as *mut _, &mut hsize, null_mut()) != 0 {
                            let text = String::from_utf16_lossy(&buf[..hsize as usize / 2]);
                            for line in text.split("\r\n").skip(1) {
                                if let Some((k, v)) = line.split_once(':') {
                                    heads.push((k.trim().to_lowercase(), v.trim().to_string()));
                                }
                            }
                        }
                    }
                    let length: u64 = heads.iter().find(|(k, _)| k == "content-length").and_then(|(_, v)| v.parse().ok()).unwrap_or(0);
                    let mut kept = Vec::new();
                    let mut out = match &sink {
                        Sink::File(p) => std::fs::File::create(p).ok(),
                        Sink::Memory(_) => None,
                    };
                    let limit = match &sink {
                        Sink::Memory(l) => *l,
                        Sink::File(_) => usize::MAX,
                    };
                    let mut come: u64 = 0;
                    let mut buf = vec![0u8; 1 << 16];
                    loop {
                        let mut avail: u32 = 0;
                        if WinHttpQueryDataAvailable(request, &mut avail) == 0 || avail == 0 {
                            break;
                        }
                        let take = (avail as usize).min(buf.len());
                        let mut read: u32 = 0;
                        if WinHttpReadData(request, buf.as_mut_ptr() as *mut _, take as u32, &mut read) == 0 || read == 0 {
                            break;
                        }
                        let part = &buf[..read as usize];
                        match out.as_mut() {
                            Some(o) => {
                                if o.write_all(part).is_err() {
                                    ok = false;
                                    break;
                                }
                            }
                            None if kept.len() < limit => kept.extend_from_slice(&part[..part.len().min(limit - kept.len())]),
                            None => {}
                        }
                        come += read as u64;
                        if length > 0 {
                            progress(come as f64 / length as f64);
                        }
                    }
                    if ok {
                        result = Ok(Answer { code: code as i32, body: kept, heads });
                    }
                } else if trust.refused.load(std::sync::atomic::Ordering::SeqCst) {
                    result = Err(Silence::NotPinned);
                } else {
                    result = silent(windows_sys::Win32::Foundation::GetLastError());
                }
                if open {
                    WinHttpCloseHandle(request);
                }
            }
            WinHttpCloseHandle(connect);
        }
        WinHttpCloseHandle(session);
        drop(trust);
        result
    }
}
#[cfg(not(windows))]
#[allow(clippy::too_many_arguments)]
pub fn exchange(_: &str, _: &str, _: &[(&str, &str)], _: Body, _: Sink, _: Option<&str>, _: u32, _: &dyn Fn(f64)) -> Result<Answer, Silence> {
    Err(Silence::NoAnswer(0))
}

/// The one deadline of a post to a node (iOS MTNodeWire.postTimeoutS).
pub const POST_DEADLINE_MS: u32 = 5_000;

/// A cargo's own deadline (iOS cargoTimeoutS): five seconds plus a second per sixteen kilobytes.
pub fn cargo_timeout_ms(bytes: usize) -> u32 {
    5_000 + (bytes as u64 * 1000 / 16_384) as u32
}
