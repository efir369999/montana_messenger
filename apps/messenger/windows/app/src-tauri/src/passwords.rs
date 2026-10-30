//! PASSWORDS (iOS MTPasswords; the author's word 06.10.2026 17:4x MSK: «create in Montana a new app on the side panel --
//! Passwords, with the whole interface for creating and managing one's sensitive data, down to OTP keys and sharing»): the
//! person's secrets -- sign-ins, one-time codes, notes -- sealed in this computer's own vault (DPAPI, never in a copy), opened
//! by the device owner's own check (Windows Hello) for five minutes, copied out of the clipboard's history and cloud, and shared
//! only into a Montana chat, end to end, where the receiver saves it into their own Passwords.

use crate::vault::Vault;
use crate::wire;
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicI64, Ordering};

/// One secret, in the very fields iOS writes (MTSecretItem): a letter between the two reads as either writes it.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Default)]
pub struct Item {
    #[serde(default)]
    pub id: String,
    #[serde(default = "login")]
    pub kind: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub site: String,
    #[serde(default)]
    pub login: String,
    #[serde(default)]
    pub password: String,
    /// a base32 key or an otpauth:// link
    #[serde(default)]
    pub otp: String,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub at: f64,
}
fn login() -> String {
    "login".into()
}

const VAULT: &str = "passwords";
/// How long one check of the device owner keeps the passwords open.
const OPEN_MS: i64 = 5 * 60_000;
static OPEN_UNTIL: AtomicI64 = AtomicI64::new(0);

pub fn open_now() {
    OPEN_UNTIL.store(wire::now_ms() + OPEN_MS, Ordering::SeqCst);
}
pub fn is_open() -> bool {
    wire::now_ms() < OPEN_UNTIL.load(Ordering::SeqCst)
}
pub fn lock() {
    OPEN_UNTIL.store(0, Ordering::SeqCst);
}

fn all(v: &Vault) -> Vec<Item> {
    v.get(VAULT).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}
fn write(v: &Vault, items: &[Item]) -> bool {
    v.set(VAULT, serde_json::to_vec(items).unwrap_or_default().as_slice())
}

/// The secrets, by title (only while open).
pub fn items(v: &Vault) -> Option<Vec<Item>> {
    if !is_open() {
        return None;
    }
    let mut a = all(v);
    a.sort_by_key(|e| e.title.to_lowercase());
    Some(a)
}

/// A secret kept (new or changed): a new one gets its name; only while open.
pub fn save(v: &Vault, item: Item) -> bool {
    if !is_open() || !["login", "code", "note"].contains(&item.kind.as_str()) {
        return false;
    }
    let mut a = all(v);
    let mut kept = item;
    if kept.id.is_empty() {
        kept.id = wire::hex(&crate::crypto::random(16).unwrap_or_default());
    }
    kept.at = wire::now_ms() as f64 / 1000.0;
    match a.iter_mut().find(|e| e.id == kept.id) {
        Some(e) => *e = kept,
        None => a.push(kept),
    }
    write(v, &a)
}

pub fn remove(v: &Vault, id: &str) -> bool {
    if !is_open() {
        return false;
    }
    let a: Vec<Item> = all(v).into_iter().filter(|e| e.id != id).collect();
    write(v, &a)
}

pub fn item(v: &Vault, id: &str) -> Option<Item> {
    is_open().then(|| all(v).into_iter().find(|e| e.id == id)).flatten()
}

// ── one-time codes (RFC 6238 over RFC 4226): the algorithm is the site's, an external standard's own ──

pub struct Spec {
    pub key: Vec<u8>,
    pub digits: usize,
    pub period: u64,
    pub alg: String,
}

/// The key as base32 or an otpauth:// link (iOS MTOneTimeCode.spec).
pub fn spec(raw: &str) -> Option<Spec> {
    let text = raw.trim();
    if text.to_lowercase().starts_with("otpauth://") {
        let query = text.split_once('?').map(|(_, q)| q).unwrap_or("");
        let get = |name: &str| query.split('&').filter_map(|p| p.split_once('=')).find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.to_string());
        let key = base32(&get("secret").unwrap_or_default())?;
        return Some(Spec {
            key,
            digits: get("digits").and_then(|d| d.parse().ok()).unwrap_or(6),
            period: get("period").and_then(|d| d.parse().ok()).unwrap_or(30),
            alg: get("algorithm").unwrap_or_else(|| "SHA1".into()).to_uppercase(),
        });
    }
    Some(Spec { key: base32(text)?, digits: 6, period: 30, alg: "SHA1".into() })
}

/// RFC 4648 base32, read as iOS reads it (spaces, dashes and the padding passed over).
pub fn base32(text: &str) -> Option<Vec<u8>> {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let (mut value, mut bits) = (0u32, 0u32);
    let mut out = vec![];
    for ch in text.to_uppercase().bytes().filter(|c| !b"= -".contains(c)) {
        let i = ALPHABET.iter().position(|&a| a == ch)? as u32;
        value = ((value << 5) | i) & 0xFFFF;
        bits += 5;
        if bits >= 8 {
            out.push(((value >> (bits - 8)) & 0xFF) as u8);
            bits -= 8;
        }
    }
    (!out.is_empty()).then_some(out)
}

/// The code of the window of the period at `unix_s`.
pub fn code(spec: &Spec, unix_s: u64) -> Option<String> {
    let counter = (unix_s / spec.period.max(1)).to_be_bytes();
    let mac = hmac(&spec.alg, &spec.key, &counter)?;
    let at = (mac[mac.len() - 1] & 0x0F) as usize;
    let bin = ((mac[at] as u32 & 0x7F) << 24) | ((mac[at + 1] as u32) << 16) | ((mac[at + 2] as u32) << 8) | mac[at + 3] as u32;
    let digits = spec.digits.clamp(6, 8);
    Some(format!("{:0width$}", bin % 10u32.pow(digits as u32), width = digits))
}

/// HMAC by Windows' own cryptography (CNG's HMAC pseudo-handles): SHA-1, SHA-256 or SHA-512, as the site's key asks.
#[cfg(windows)]
fn hmac(alg: &str, key: &[u8], msg: &[u8]) -> Option<Vec<u8>> {
    use windows_sys::Win32::Security::Cryptography::*;
    let (h, len) = match alg {
        "SHA256" => (BCRYPT_HMAC_SHA256_ALG_HANDLE, 32),
        "SHA512" => (BCRYPT_HMAC_SHA512_ALG_HANDLE, 64),
        _ => (BCRYPT_HMAC_SHA1_ALG_HANDLE, 20),
    };
    let mut out = vec![0u8; len];
    // SAFETY: the key, the message and an output buffer of the hash's own length
    let rc = unsafe { BCryptHash(h, key.as_ptr(), key.len() as u32, msg.as_ptr(), msg.len() as u32, out.as_mut_ptr(), len as u32) };
    (rc == 0).then_some(out)
}
#[cfg(not(windows))]
fn hmac(_: &str, _: &[u8], _: &[u8]) -> Option<Vec<u8>> {
    None
}

/// Twenty characters, letters that are not mistaken for one another, digits and a few signs, each drawn without bias.
pub fn fresh(length: usize) -> String {
    const ALPHABET: &[u8] = b"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_.!?#";
    let limit = 256 - 256 % ALPHABET.len();
    let mut out = String::new();
    while out.len() < length {
        for b in crate::crypto::random(32).unwrap_or_default() {
            if (b as usize) < limit && out.len() < length {
                out.push(ALPHABET[b as usize % ALPHABET.len()] as char);
            }
        }
    }
    out
}

// ── a secret shared into a chat (iOS MTSecretLetter) ──

pub const LINK: &str = "montana://secret/1/";
const KEY: &str = "🔑 ";

/// The key glyph and the title on the first line, the machine line under it; the item's own name stays home.
pub fn letter(item: &Item) -> Option<String> {
    let shared = Item { id: String::new(), ..item.clone() };
    let code = base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&shared).ok()?).replace('+', "-").replace('/', "_");
    Some(format!("{KEY}{}\n{LINK}{code}", item.title))
}

/// A secret letter: its first line names it; its machine line is never drawn.
pub fn is_letter(text: &str) -> bool {
    text.starts_with(KEY) && text.lines().last().is_some_and(|l| l.starts_with(LINK))
}

/// What a secret letter shows of itself: the key glyph and the title.
pub fn shown(text: &str) -> String {
    text.lines().next().unwrap_or("").to_string()
}

/// The secret a letter carries, under a name of its own here.
pub fn parse(text: &str) -> Option<Item> {
    if !is_letter(text) || text.len() > 65_536 {
        return None;
    }
    let line = text.lines().last()?;
    let code = line.strip_prefix(LINK)?.replace('-', "+").replace('_', "/");
    let bytes = base64::engine::general_purpose::STANDARD.decode(code.trim()).ok()?;
    let mut item: Item = serde_json::from_slice(&bytes).ok()?;
    item.id = String::new();
    ["login", "code", "note"].contains(&item.kind.as_str()).then_some(item)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_time_codes_agree_with_rfc_6238() {
        // RFC 6238 appendix B: the seeds of 20, 32 and 64 bytes, eight digits
        let s1 = Spec { key: b"12345678901234567890".to_vec(), digits: 8, period: 30, alg: "SHA1".into() };
        let s256 = Spec { key: b"12345678901234567890123456789012".to_vec(), digits: 8, period: 30, alg: "SHA256".into() };
        let s512 = Spec { key: b"1234567890123456789012345678901234567890123456789012345678901234".to_vec(), digits: 8, period: 30, alg: "SHA512".into() };
        assert_eq!(code(&s1, 59).as_deref(), Some("94287082"));
        assert_eq!(code(&s256, 59).as_deref(), Some("46119246"));
        assert_eq!(code(&s512, 59).as_deref(), Some("90693936"));
        assert_eq!(code(&s1, 1111111109).as_deref(), Some("07081804"));
        assert_eq!(code(&s1, 20000000000).as_deref(), Some("65353130"));
        // base32 and the otpauth link: «GEZDGNBVGY3TQOJQ…» is «1234567890…»
        assert_eq!(base32("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ").unwrap(), b"12345678901234567890");
        assert_eq!(base32("gezd gnbv-gy3t qojq====").unwrap(), b"1234567890");
        assert!(base32("not base32!").is_none());
        let link = spec("otpauth://totp/Site:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Site&digits=8").unwrap();
        assert_eq!((link.digits, link.period, link.alg.as_str()), (8, 30, "SHA1"));
        assert_eq!(code(&link, 59).as_deref(), Some("94287082"));
        assert_eq!(code(&spec("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ").unwrap(), 59).as_deref(), Some("287082"), "six digits by default");
    }

    #[test]
    fn a_secret_letter_reads_as_ios_writes_it_and_shows_only_its_title() {
        let item = Item { id: "local".into(), kind: "login".into(), title: "Почта".into(), site: "mail.example".into(), login: "alice".into(),
                          password: "S3cret!".into(), at: 1.5, ..Default::default() };
        let text = letter(&item).unwrap();
        assert!(text.starts_with("🔑 Почта\nmontana://secret/1/"));
        assert!(is_letter(&text) && !text.contains("S3cret!") && !text.contains("local"), "the secret rides coded, the item's own name stays home");
        assert_eq!(shown(&text), "🔑 Почта");
        let back = parse(&text).unwrap();
        assert_eq!((back.title.as_str(), back.password.as_str(), back.id.as_str()), ("Почта", "S3cret!", ""));
        // as iOS JSONEncoder writes it: every field, the kind's raw value, the moment a Double
        let ios = r#"{"id":"","kind":"code","title":"Bank","site":"","login":"","password":"","otp":"GEZDGNBVGY3TQOJQ","note":"","at":1760943600.25}"#;
        let code = base64::engine::general_purpose::STANDARD.encode(ios).replace('+', "-").replace('/', "_");
        let got = parse(&format!("🔑 Bank\n{LINK}{code}")).unwrap();
        assert_eq!((got.kind.as_str(), got.otp.as_str()), ("code", "GEZDGNBVGY3TQOJQ"));
        assert!(parse("🔑 Bank\nmontana://secret/1/@@@").is_none());
        assert!(!is_letter("🔑 just a key"));
        assert_eq!(fresh(20).len(), 20);
        assert_ne!(fresh(20), fresh(20));
    }
}
