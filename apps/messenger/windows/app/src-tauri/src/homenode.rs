//! YOUR NODE (iOS MontanaHomeNode, HomeNodeWatch; the author's word 28.09.2026: «your node is your backup of the whole phone. What
//! you choose yourself. A machine the person owns, named by its address alone»). THE COPY OF THE WHOLE APP goes there and comes
//! back from there: the sealed copy the engine writes (history::make_copy -- iOS's own MontanaBackup, .mtbak), under the key the
//! 24 words open, the words never in it. A node of one's own knows no account, so a shelf is named by a TOKEN only the words derive
//! (HKDF of the entropy under one label, then one HMAC); the node checks sha256(token) against the shelf's name and stores nothing
//! of anybody. The token rides only inside TLS to the person's own machine -- a machine put up from here is trusted by the digest of
//! the certificate it made for itself (http::exchange's pin). The keeper's word is the only word: what the page says about the node
//! is what the node answered -- held, with its size and moment; none; refused; did not answer.

use crate::http::{self, Body, Sink, Silence};
use crate::vault::Vault;
use crate::wire::{hex, hmac};
use serde::Serialize;

const HOST: &str = "homeNodeHost";
const PIN: &str = "homeNodePin";
const ON: &str = "homeNodeOn";
const LAST: &str = "homeNodeAt";
/// The door's own TLS port, beside the plain one a front proxies to (iOS MontanaNodeSetup.tlsPort).
pub const TLS_PORT: u16 = 8463;
const TOKEN_HEADER: &str = "X-Montana-Vault";
const DIGEST_HEADER: &str = "X-Montana-SHA256";
/// What a question waits for (iOS: 15 s for the node's word, 60 s a request on the way of a copy).
const ASK_MS: u32 = 15_000;
const MOVE_MS: u32 = 60_000;

// ── the shelf's name ──
pub fn vault_key(entropy: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let _ = hkdf::Hkdf::<sha2::Sha256>::new(Some(&[]), entropy).expand(b"mt-vault-owner-v1", &mut out);
    out
}
pub fn token(k: &[u8; 32]) -> [u8; 32] {
    hmac(k, b"mt-vault-token")
}
#[cfg(test)]
pub fn shelf(t: &[u8]) -> String {
    hex(&crate::wire::sha(&[t]))
}
pub fn token_hex(entropy: &[u8]) -> String {
    hex(&token(&vault_key(entropy)))
}

// ── what this computer keeps of it (the person's vault) ──
pub fn host(v: &Vault) -> String {
    v.get(HOST).and_then(|b| String::from_utf8(b).ok()).unwrap_or_default()
}
/// The address, bare (iOS setHost): no scheme, no slash, in small letters.
pub fn set_host(v: &Vault, h: &str) -> String {
    let clean = h.trim().to_lowercase().replace("https://", "").replace('/', "");
    v.set(HOST, clean.as_bytes());
    crate::trace_line(&format!("home_node host set={}", if clean.is_empty() { 0 } else { 1 }));
    clean
}
/// The digest of the node's own certificate (a node put up by address); empty for a named node.
pub fn pin(v: &Vault) -> String {
    v.get(PIN).and_then(|b| String::from_utf8(b).ok()).unwrap_or_default()
}
pub fn set_pin(v: &Vault, p: &str) {
    v.set(PIN, p.as_bytes());
}
/// The person's switch of the daily copies (the level opens it -- the caller weighs it, iOS MontanaHomeNode.on).
pub fn switched(v: &Vault) -> bool {
    v.get(ON).as_deref() == Some(b"1")
}
pub fn set_switched(v: &Vault, on: bool) {
    v.set(ON, if on { b"1" } else { b"0" });
}
/// This computer's own clock of its last copy to the node (seconds).
pub fn last(v: &Vault) -> f64 {
    v.get(LAST).and_then(|b| String::from_utf8(b).ok()).and_then(|s| s.parse().ok()).unwrap_or(0.0)
}
pub fn note_copied(v: &Vault, at: f64) {
    v.set(LAST, at.to_string().as_bytes());
}
/// Due once a day, or when the node holds none of ours (iOS due).
pub fn due(v: &Vault, holds_none: bool) -> bool {
    holds_none || crate::wire::now_ms() as f64 / 1000.0 - last(v) >= 86_400.0
}
/// A pinned node is spoken to straight, on the door's own TLS port; a named one through its front, under /pushwake (iOS base).
pub fn base(host: &str, pin: &str) -> Option<String> {
    if host.is_empty() {
        return None;
    }
    Some(if pin.is_empty() { format!("https://{host}/pushwake") } else { format!("https://{host}:{TLS_PORT}") })
}

/// The moment a copy's name carries (montana-yyyy-MM-dd-HHmmss-…): «yyyy-MM-dd HH:mm», or nothing for a name not a copy's
/// (iOS MontanaBackup.born(ofName:)).
pub fn born(name: &str) -> Option<String> {
    let m = name.strip_prefix("montana-")?.strip_suffix(".mtbak")?;
    let (d, t) = (m.get(..10)?, m.get(11..17)?);
    let ok = d.chars().enumerate().all(|(i, c)| if i == 4 || i == 7 { c == '-' } else { c.is_ascii_digit() }) && t.chars().all(|c| c.is_ascii_digit());
    ok.then(|| format!("{d} {}:{}", &t[..2], &t[2..4]))
}

/// THE NODE'S WORD (iOS HomeNodeWatch.State).
#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(tag = "kind")]
pub enum State {
    NoHost,
    None { free: i64 },
    Held { name: String, moment: String, bytes: i64, free: i64 },
    Refused { why: String },
    Silent { why: String },
}

fn silent_word(s: Silence) -> String {
    match s {
        Silence::NotPinned => "certificate".into(),
        Silence::NoAnswer(e) => format!("WinHTTP {e}"),
    }
}

/// The node's word, asked afresh (iOS ask): what it can do (/health), and what it holds of ours (/vault-have).
pub fn ask(v: &Vault, entropy: &[u8]) -> (State, Vec<String>) {
    let (h, p) = (host(v), pin(v));
    let Some(b) = base(&h, &p) else { return (State::NoHost, vec![]) };
    let pin = (!p.is_empty()).then_some(p.as_str());
    let caps = http::exchange("GET", &format!("{b}/health"), &[], Body::None, Sink::Memory(64 << 10), pin, ASK_MS, &|_| {})
        .ok().filter(|a| a.code == 200)
        .and_then(|a| serde_json::from_slice::<serde_json::Value>(&a.body).ok())
        .and_then(|j| j["caps"].as_object().map(|c| c.iter().filter(|(_, on)| on.as_bool() == Some(true)).map(|(k, _)| k.clone()).collect::<Vec<_>>()))
        .map(|mut c| {
            c.sort();
            c
        })
        .unwrap_or_default();
    let tok = token_hex(entropy);
    let state = match http::exchange("GET", &format!("{b}/vault-have"), &[(TOKEN_HEADER, &tok)], Body::None, Sink::Memory(1 << 20), pin, ASK_MS, &|_| {}) {
        Err(s) => {
            let why = silent_word(s);
            crate::trace_line(&format!("home_node no answer {why}"));
            State::Silent { why }
        }
        Ok(a) if a.code != 200 => {
            crate::trace_line(&format!("home_node have refused code={}", a.code));
            State::Refused { why: a.code.to_string() }
        }
        Ok(a) => {
            let j: serde_json::Value = serde_json::from_slice(&a.body).unwrap_or_default();
            let free = j["free"].as_i64().unwrap_or(0);
            let held = j["held"].as_array().cloned().unwrap_or_default();
            crate::trace_line(&format!("home_node holds n={} free={free}", held.len()));
            match held.first().and_then(|t| Some((t["name"].as_str()?.to_string(), t["bytes"].as_i64()?))) {
                Some((name, bytes)) => State::Held { moment: born(&name).unwrap_or_default(), name, bytes, free },
                None => State::None { free },
            }
        }
    };
    (state, caps)
}

/// A COPY TO THE NODE (iOS hand): the sealed file sent whole under its name and its digest, held only on the node's echo of the
/// digest. Err -- the word of the refusal.
pub fn send(v: &Vault, entropy: &[u8], file: &std::path::Path, progress: &dyn Fn(f64)) -> Result<(), String> {
    let (h, p) = (host(v), pin(v));
    let b = base(&h, &p).ok_or("no address")?;
    let name = file.file_name().and_then(|n| n.to_str()).ok_or("name")?.to_string();
    let digest = digest_of(file).ok_or("digest")?;
    let tok = token_hex(entropy);
    let url = format!("{b}/vault-put?name={name}&sha256={digest}");
    let headers = [(TOKEN_HEADER, tok.as_str()), (DIGEST_HEADER, digest.as_str()), ("Content-Type", "application/octet-stream")];
    match http::exchange("PUT", &url, &headers, Body::File(file), Sink::Memory(64 << 10), (!p.is_empty()).then_some(p.as_str()), MOVE_MS, progress) {
        Err(s) => {
            let why = silent_word(s);
            crate::trace_line(&format!("home_node put no answer {why}"));
            Err(format!("put {why}"))
        }
        Ok(a) => {
            let j: serde_json::Value = serde_json::from_slice(&a.body).unwrap_or_default();
            if a.code != 200 || j["sha256"].as_str() != Some(digest.as_str()) {
                crate::trace_line(&format!("home_node put refused code={}", a.code));
                return Err(format!("put {} {}", a.code, j["error"].as_str().unwrap_or("")).trim().to_string());
            }
            note_copied(v, crate::wire::now_ms() as f64 / 1000.0);
            crate::trace_line(&format!("home_node held bytes={} (the node echoed the digest)", std::fs::metadata(file).map(|m| m.len()).unwrap_or(0)));
            Ok(())
        }
    }
}

/// THE NEWEST COPY THE NODE HOLDS comes back (iOS takeBack): into `dir` under the name the node gives; Err -- the word, «empty»
/// when the node holds none.
pub fn take_back(v: &Vault, entropy: &[u8], dir: &std::path::Path, progress: &dyn Fn(f64)) -> Result<std::path::PathBuf, String> {
    let (h, p) = (host(v), pin(v));
    let b = base(&h, &p).ok_or("no address")?;
    let _ = std::fs::create_dir_all(dir);
    let landing = dir.join(format!("{}.part", crate::board::fresh_id()));
    let tok = token_hex(entropy);
    let got = http::exchange("GET", &format!("{b}/vault-get"), &[(TOKEN_HEADER, &tok)], Body::None, Sink::File(&landing), (!p.is_empty()).then_some(p.as_str()), MOVE_MS, progress);
    let fail = |w: String| {
        let _ = std::fs::remove_file(&landing);
        Err(w)
    };
    match got {
        Err(s) => fail(format!("get {}", silent_word(s))),
        Ok(a) if a.code == 404 => fail("empty".into()),
        Ok(a) => match a.head("x-montana-name").filter(|n| a.code == 200 && born(n).is_some()).map(str::to_string) {
            None => fail(format!("get {}", a.code)),
            Some(name) => {
                let dst = dir.join(&name);
                let _ = std::fs::remove_file(&dst);
                std::fs::rename(&landing, &dst).map_err(|_| "disk".to_string())?;
                crate::trace_line(&format!("home_node fetched {name}"));
                Ok(dst)
            }
        },
    }
}

/// SHA-256 of a file, a megabyte in hand at a time.
pub fn digest_of(file: &std::path::Path) -> Option<String> {
    use sha2::Digest;
    use std::io::Read;
    let mut f = std::fs::File::open(file).ok()?;
    let mut h = sha2::Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf).ok()?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Some(hex(&h.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_shelf_of_the_words_holds_ios_frozen_vectors() {
        let counting: Vec<u8> = (0..32).collect();
        let k = vault_key(&counting);
        let t = token(&k);
        assert_eq!(hex(&k), "aa75b0afc0c9b1b4e31a8fecf371ee72866865e7a77cf61f9f1f0ad457652097");
        assert_eq!(hex(&t), "0695b3db38b3c8525f8d8b7a270ae0bc5504c2d0d58634a937e52c2b9f7d2d28");
        assert_eq!(shelf(&t), "125ff41ffac97cae3ce9ba4ab20ae5586587f5c8960fee4055f6aaa8c219b49a");
        assert_eq!(born("montana-2026-09-23-143542-fc4380015be1598a.mtbak").as_deref(), Some("2026-09-23 14:35"));
        assert_eq!(born("photo.jpg"), None);
        assert_eq!(base("node.example", "").as_deref(), Some("https://node.example/pushwake"));
        assert_eq!(base("10.0.0.7", "ab").as_deref(), Some("https://10.0.0.7:8463"));
        assert_eq!(base("", ""), None);
    }

    /// THE COPY GOES TO ONE'S OWN NODE AND COMES BACK (live: iOS's own door, Code/Node, started by tools\homenode-door.ps1 at
    /// 127.0.0.1 with a certificate it made for itself, its digest in MONTANA_HOME_PIN; throwaway words): the shelf of these words
    /// is empty, the copy is held once the node echoes its digest, comes back byte for byte; another certificate hears nothing
    /// of the request, and a stranger's words see an empty shelf.
    #[test]
    #[ignore]
    fn a_copy_goes_to_ones_own_node_and_comes_back_and_another_certificate_hears_nothing() {
        let Ok(pin) = std::env::var("MONTANA_HOME_PIN") else { return };
        let dir = std::env::temp_dir().join(format!("mt-home-{}", crate::board::fresh_id()));
        let v = Vault::at(&dir.join("v")).unwrap();
        set_host(&v, "127.0.0.1");
        set_pin(&v, &pin);
        let e = crate::crypto::random(32).unwrap();
        let (state, caps) = ask(&v, &e);
        assert!(matches!(state, State::None { .. }), "a fresh shelf holds none: {state:?}");
        assert!(caps.contains(&"vault".to_string()), "the door offers the copies: {caps:?}");
        let copy = dir.join("montana-2026-10-23-061500-0123456789abcdef.mtbak");
        let seed = crate::crypto::random(32).unwrap();
        let bytes: Vec<u8> = (0..3usize << 20).map(|i| seed[i % 32] ^ (i >> 5) as u8).collect();
        std::fs::write(&copy, &bytes).unwrap();
        let sent = std::sync::Mutex::new(0.0f64);
        send(&v, &e, &copy, &|f| *sent.lock().unwrap() = f).expect("held");
        assert!(*sent.lock().unwrap() >= 0.99, "the share of the bytes sent reached the whole");
        match ask(&v, &e).0 {
            State::Held { name, moment, bytes: n, .. } => assert_eq!((name.as_str(), moment.as_str(), n), (copy.file_name().unwrap().to_str().unwrap(), "2026-10-23 06:15", bytes.len() as i64)),
            other => panic!("the node should hold the copy: {other:?}"),
        }
        let back = take_back(&v, &e, &dir.join("back"), &|_| {}).expect("it comes back");
        assert_eq!(std::fs::read(&back).unwrap(), bytes, "byte for byte");
        assert!(matches!(ask(&v, &crate::crypto::random(32).unwrap()).0, State::None { .. }), "a stranger's words see an empty shelf");
        set_pin(&v, &"00".repeat(32));
        assert_eq!(ask(&v, &e).0, State::Silent { why: "certificate".into() }, "another certificate: nothing asked");
        assert_eq!(send(&v, &e, &copy, &|_| {}), Err("put certificate".into()));
        let _ = std::fs::remove_dir_all(dir);
    }
}
