//! THE FROZEN FORMULAS OF THE NODE WIRE, byte for byte as iOS writes them (MTNodeWire, MTPipe; Android Pipes.kt Wire): every
//! label and key is SHA-256(domain ‖ 0x00 ‖ parts…), a window laid little-endian in eight bytes. The seal is the core's.
//! The tests hold iOS's own vectors (agreesWithCanon, pipeAgreesWithCanon, authorAgreesWithCanon): a drift of one byte and
//! no letter leaves.

use crate::crypto;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

/// One size for every envelope: the node cannot tell letter lengths apart (iOS envelopeSize).
pub const ENVELOPE: usize = 2048;
/// The fields before the author's: mid, text, name, glyph, quote, quoted mid, card.
pub const AUTHOR_FIELDS: usize = 7;

pub fn sha(parts: &[&[u8]]) -> [u8; 32] {
    let mut h = Sha256::new();
    for p in parts {
        h.update(p);
    }
    h.finalize().into()
}

/// SHA-256(domain ‖ 0 ‖ parts…) (iOS MTPipe.domained).
pub fn domained(domain: &str, parts: &[&[u8]]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(domain.as_bytes());
    h.update([0u8]);
    for p in parts {
        h.update(p);
    }
    h.finalize().into()
}

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

pub fn unhex(h: &str) -> Option<Vec<u8>> {
    h.len().is_multiple_of(2).then(|| (0..h.len()).step_by(2).map(|i| u8::from_str_radix(&h[i..i + 2], 16).ok()).collect()).flatten()
}

pub fn le8(w: i64) -> [u8; 8] {
    (w as u64).to_le_bytes()
}

pub fn b64(d: &[u8]) -> String {
    STANDARD.encode(d)
}

pub fn unb64(s: &str) -> Option<Vec<u8>> {
    STANDARD.decode(s.trim()).ok()
}

pub fn b64url(d: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(d)
}

pub fn unb64url(s: &str) -> Option<Vec<u8>> {
    URL_SAFE_NO_PAD.decode(s.trim_end_matches('=')).ok()
}

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0) + clock_shift_ms()
}

/// A CHECK'S CLOCK AHEAD (MONTANA_CLOCK_SHIFT_DAYS, read only in a check's run -- MONTANA_DATA_DIR set): the days the client counts
/// as its own, so a pair of test identities meets the walk's later days before the calendar does (iOS: the walk counts the client's
/// day). Never in the person's program: without a check's folder it is zero.
fn clock_shift_ms() -> i64 {
    static SHIFT: std::sync::OnceLock<i64> = std::sync::OnceLock::new();
    *SHIFT.get_or_init(|| {
        if std::env::var_os("MONTANA_DATA_DIR").is_none() {
            return 0;
        }
        std::env::var("MONTANA_CLOCK_SHIFT_DAYS").ok().and_then(|d| d.trim().parse::<i64>().ok()).filter(|d| (0..=400).contains(d)).unwrap_or(0) * 86_400_000
    })
}

pub fn minute() -> i64 {
    now_ms() / 60_000
}

pub fn day() -> i64 {
    now_ms() / 86_400_000
}

/// THE PIPE SECRET WALKS WITH THE CLIENT'S DAY (iOS MTNodeWire.pipeSecret, 21.10.2026; Canon, «The secret a tag stands on walks with
/// the window»): pipe_secret(D + 1) = SHA-256("mt-pipe-ratchet" ‖ 0 ‖ pipe_secret(D)), one step a day, standing still through
/// WALK_ANCHOR_DAY -- up to that day every key is byte for byte the one the earlier builds and Android derive, so they still meet,
/// and from the day after each day stands one hash further down a one-way walk. A day is clamped to MAX_WALK steps, so a forged
/// time costs a bounded walk and opens nothing.
pub const WALK_ANCHOR_DAY: i64 = 20754; // 28.10.2026 UTC
pub const MINUTES_PER_DAY: i64 = 1440;
const MAX_WALK: i64 = 36_600;
type Walks = std::collections::HashMap<Vec<u8>, (i64, Vec<u8>)>;
/// secret -> (the steps walked, the value there): a walk goes on from where it stood
static WALKED: std::sync::Mutex<Option<Walks>> = std::sync::Mutex::new(None);
pub fn pipe_secret(secret: &[u8], day: i64) -> Vec<u8> {
    let steps = (day - WALK_ANCHOR_DAY).clamp(0, MAX_WALK);
    if steps == 0 {
        return secret.to_vec();
    }
    let mut g = WALKED.lock().unwrap();
    let walked = g.get_or_insert_with(Default::default);
    let (mut at, mut value) = match walked.get(secret) {
        Some((s, v)) if *s <= steps => (*s, v.clone()),
        _ => (0, secret.to_vec()),
    };
    while at < steps {
        value = domained("mt-pipe-ratchet", &[&value]).to_vec();
        at += 1;
    }
    if walked.len() >= 256 {
        walked.clear();
    }
    walked.insert(secret.to_vec(), (steps, value.clone()));
    value
}

/// The raw seal key of the set: SHA-256("mt-pipe-key" ‖ 0 ‖ step_secret ‖ W_LE) -- held by the canon vectors.
pub fn seal_key(step_secret: &[u8], w: i64) -> [u8; 32] {
    domained("mt-pipe-key", &[step_secret, &le8(w)])
}

/// The letter body key of a minute: the seal key under the pipe secret of that minute's day.
pub fn body_key(secret: &[u8], w: i64) -> [u8; 32] {
    seal_key(&pipe_secret(secret, w.div_euclid(MINUTES_PER_DAY)), w)
}

/// The canon's daily tag over the day's secret: SHA-256("mt-wake-conv" ‖ 0 ‖ day_secret ‖ W_LE) -- held by the canon vectors apart
/// from the walk that feeds it, as seal_key is for body_key.
pub fn conv_tag(day_secret: &[u8], day: i64) -> String {
    hex(&domained("mt-wake-conv", &[day_secret, &le8(day)]))
}

/// The conversation's daily label at the node: both sides derive it from the pipe secret of that day.
pub fn conv_w(secret: &[u8], day: i64) -> String {
    conv_tag(&pipe_secret(secret, day), day)
}

/// THE ROOT OF A CONVERSATION (iOS MTNodeWire.convRoot, 21.10.2026): SHA-256("mt-conv-root" ‖ 0 ‖ the established secret). What a pair
/// derives afresh for every item -- the blind of a coin SEND and the author field of a letter -- stands on the root from the day after
/// WALK_ANCHOR_DAY, never on the established secret, so the walk can erase that secret.
pub fn conv_root(secret: &[u8]) -> [u8; 32] {
    domained("mt-conv-root", &[secret])
}
/// The key an item laid on the day stands on: the root past the anchor, the established secret up to it.
pub fn item_key(secret: &[u8], day: i64) -> Vec<u8> {
    if day > WALK_ANCHOR_DAY { conv_root(secret).to_vec() } else { secret.to_vec() }
}
/// The keys a received item may stand on, the root first: the sender's day is its own clock, so the receiver tries both while it
/// still holds the established secret.
pub fn item_keys(secret: &[u8]) -> [Vec<u8>; 2] {
    [conv_root(secret).to_vec(), secret.to_vec()]
}

/// The daily label of a handed-out invitation (the first letter's box).
pub fn rdv_conv_w(inv: &[u8], day: i64) -> String {
    hex(&domained("mt-rdv-wake", &[inv, &le8(day)]))
}

/// The subscription tag standing in for the device at the node.
pub fn sub_id(conv: &str, reference: &str) -> String {
    hex(&domained("mt-wake-sub", &[conv.as_bytes(), &[0u8], reference.as_bytes()]))
}

/// The first-meeting letter's key, derived from the invitation (iOS rdvLetterSecret).
pub fn rdv_letter_secret(inv: &[u8]) -> [u8; 32] {
    domained("mt-rdv-letter", &[inv])
}

/// The local name of a correspondence: SHA-256(secret)[0..16] in hex (iOS MTPipeBook.reference).
pub fn reference(secret: &[u8]) -> String {
    hex(&sha(&[secret])[..16])
}

pub fn pipe_tag(secret: &[u8], w: i64) -> Vec<u8> {
    domained("mt-tag", &[secret, &le8(w)])[..16].to_vec()
}

#[cfg(test)]
pub fn step_label(secret: &[u8], w: i64) -> Vec<u8> {
    domained("mt-step", &[secret, &le8(w)])[..16].to_vec()
}

#[cfg(test)]
pub fn relay_seal(owner: &[u8], label: &[u8]) -> Vec<u8> {
    domained("mt-relay-seal", &[owner, label])[..16].to_vec()
}

pub fn owner_ref(owner: &[u8], secret: &[u8]) -> Vec<u8> {
    domained("mt-owner-ref", &[owner, secret])[..16].to_vec()
}

pub fn overlay_tag(auth_pub: &[u8]) -> [u8; 32] {
    domained("mt-overlay", &[auth_pub])
}

pub fn window_pos(overlay: &[u8], w: i64) -> [u8; 32] {
    domained("mt-pos", &[overlay, &le8(w)])
}

/// The order of Swift's lexicographicallyPrecedes over the first sixteen bytes: unsigned, a shorter prefix first.
#[cfg(test)]
fn order16(a: &[u8], b: &[u8]) -> std::cmp::Ordering {
    let n = 16.min(a.len()).min(b.len());
    a[..n].cmp(&b[..n]).then(16.min(a.len()).cmp(&16.min(b.len())))
}

/// THE HOLDER OF A TAG (iOS MTPipe.holder): the least commitment standing above the tag, the lowest of all when none does.
#[cfg(test)]
pub fn holder<'a>(tag: &[u8], commitments: &'a [Vec<u8>]) -> Option<&'a Vec<u8>> {
    let mut sorted: Vec<&Vec<u8>> = commitments.iter().collect();
    sorted.sort_by(|a, b| order16(a, b));
    sorted.iter().find(|c| order16(tag, c) == std::cmp::Ordering::Less).or_else(|| sorted.first()).copied()
}

/// A blob sealed under a body key (the core's seal with a fresh nonce).
pub fn seal(key: &[u8], plain: &[u8]) -> Option<Vec<u8>> {
    crypto::seal(key, plain)
}

pub fn open(key: &[u8], sealed: &[u8]) -> Option<Vec<u8>> {
    crypto::open(key, sealed)
}

/// A boxed letter wears the SENDER's minute, the node names the minute it took it: the walk goes back a day.
pub fn open_boxed(sealed: &[u8], secret: &[u8], at_s: i64) -> Option<Vec<u8>> {
    let w0 = at_s / 60;
    for w in [w0, w0 - 1, w0 + 1] {
        if let Some(p) = open(&body_key(secret, w), sealed) {
            return Some(p);
        }
    }
    let mut w = w0 - 2;
    for _ in 0..1439 {
        if let Some(p) = open(&body_key(secret, w), sealed) {
            return Some(p);
        }
        w -= 1;
    }
    None
}

/// mid‖0‖text‖0‖name‖0‖glyph‖0… — up to `count` fields from `from`; missing ones are empty (iOS parseLetterFields).
pub fn fields(plain: &[u8], from: usize, count: usize) -> Vec<String> {
    let mut out = Vec::with_capacity(count);
    let mut i = from;
    while out.len() < count {
        let mut z = i;
        while z < plain.len() && plain[z] != 0 {
            z += 1;
        }
        out.push(String::from_utf8_lossy(&plain[i.min(plain.len())..z]).into_owned());
        if z >= plain.len() {
            break;
        }
        i = z + 1;
    }
    while out.len() < count {
        out.push(String::new());
    }
    out
}

/// HMAC-SHA-256 (RFC 2104), the one MAC of the author field.
pub fn hmac(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut k = [0u8; 64];
    if key.len() > 64 {
        k[..32].copy_from_slice(&sha(&[key]));
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let ipad: Vec<u8> = k.iter().map(|b| b ^ 0x36).collect();
    let opad: Vec<u8> = k.iter().map(|b| b ^ 0x5c).collect();
    let inner = sha(&[&ipad, msg]);
    sha(&[&opad, &inner])
}

/// THE LETTER'S AUTHOR IS THE PERSON (iOS MTNodeWire.authorTag): HMAC under «mt-letter-author» of the seed over the pipe's
/// secret, the letter's name and its words, cut to sixteen bytes, in base64.
pub fn author_tag(key: &[u8], secret: &[u8], mid: &str, text: &str) -> String {
    let mut m = b"mt-letter-author\0".to_vec();
    m.extend_from_slice(secret);
    m.extend_from_slice(mid.as_bytes());
    m.push(0);
    m.extend_from_slice(text.as_bytes());
    b64(&hmac(key, &m)[..16])
}

/// The body with the author's field: the fields before it closed, the empty ones written; a body that would outgrow the
/// envelope rides without it. Past the anchor the field stands on the conversation's root (item_key).
pub fn with_author(body: &[u8], key: Option<&[u8]>, secret: &[u8], mid: &str, text: &str) -> Vec<u8> {
    with_author_on(body, key, secret, mid, text, day())
}
pub fn with_author_on(body: &[u8], key: Option<&[u8]>, secret: &[u8], mid: &str, text: &str, day: i64) -> Vec<u8> {
    let Some(key) = key.filter(|k| k.len() == 32) else { return body.to_vec() };
    let mut b = body.to_vec();
    if b.last().is_some_and(|&x| x != 0) {
        b.push(0);
    }
    let mut closed = b.iter().filter(|&&x| x == 0).count();
    while closed < AUTHOR_FIELDS {
        b.push(0);
        closed += 1;
    }
    if closed != AUTHOR_FIELDS {
        return body.to_vec();
    }
    b.extend_from_slice(author_tag(key, &item_key(secret, day), mid, text).as_bytes());
    b.push(0);
    if b.len() <= ENVELOPE { b } else { body.to_vec() }
}

/// Whether a letter's author field is this person's: the tag made again under the root and under the secret, compared in constant
/// time (iOS authorHolds over itemKeys).
pub fn author_holds(tag: &str, key: Option<&[u8]>, secret: &[u8], mid: &str, text: &str) -> bool {
    let Some(key) = key.filter(|k| k.len() == 32) else { return false };
    let Some(got) = unb64(tag).filter(|g| g.len() == 16) else { return false };
    item_keys(secret).iter().any(|k| {
        unb64(&author_tag(key, k, mid, text)).is_some_and(|want| got.iter().zip(&want).fold(0u8, |d, (a, b)| d | (a ^ b)) == 0)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(b: u8, n: usize) -> Vec<u8> {
        vec![b; n]
    }

    #[test]
    fn the_box_agrees_with_ios_canon() {
        let s32: Vec<u8> = (0..32).collect();
        assert_eq!(sub_id("mt-conv-Q7", "mtAddrZ93kLmNoPq"), "e5438bfedc8b1fdcdadfb9f4d3995fac7722c0074f3a20ccd3e911ce5beb35de");
        assert_eq!(sub_id("ab", "c"), "a279974b24ff1b84299330076b5f5858684d56733458de21b152aa8521c7a230");
        assert_eq!(sub_id("a", "bc"), "c04b7d58e4c7aaca35800d119fd6fde021f95f7d3c9438e3ca46cd855afe6a8a");
        // the canon's tag over the day's secret, apart from the walk (iOS 2304 MontanaWakePush 815: the vector moved to convTag --
        // read through conv_w, day 29737 walks 8983 steps and the canon fails, as it did iOS 2266-2267)
        assert_eq!(conv_tag(&s32, 29737), "43eaf2811da7947166d4e851e52c4ab89e09c8c92247370d3c734ef08ca1e6ea");
        assert_eq!(conv_tag(&s32, 29738), "f5f2941435d76c0a80dd229722ef42382695e88fdd1fabf89d71f317bef05430");
        assert_eq!(hex(&seal_key(&s32, 0x0102030405060708)), "e55fbc1e0f95c4fe012b476c4dd1a51c9455e24641248f4f1557ed57f8c14f35");
        assert_eq!(hex(&body_key(&s32, 1000)), "e25542e65a84d1a5b5c72a13172ecb62319c18f21a59978a53e7dac2c22a966a");
    }

    /// THE WALK OF THE PIPE SECRET AND THE ROOT, iOS 2304's own vectors (MTPipe.selfCheck 199-237, derived in Python apart from the
    /// code): the anchor day is the established secret, the next two are one and two steps down; the root blinds and signs past the
    /// anchor, and a reader holds both.
    #[test]
    fn the_walk_of_the_pipe_secret_and_the_root_agree_with_ios_2304() {
        let s32: Vec<u8> = (0..32).collect();
        let a = WALK_ANCHOR_DAY;
        assert_eq!(pipe_secret(&s32, a), s32);
        assert_eq!(pipe_secret(&s32, a - 400), s32, "before the anchor nothing walks");
        assert_eq!(hex(&pipe_secret(&s32, a + 1)), "5dcfd87692fcd444a4344d756dfa37abe670d2eb252aa9b402646be97cf3c50a");
        assert_eq!(hex(&pipe_secret(&s32, a + 2)), "0c31775e80ae463de61fecee68bee8bb4ebbcee8e6b2045f8714e93ef18cb1b0");
        assert_eq!(hex(&pipe_secret(&s32, a + 1)), "5dcfd87692fcd444a4344d756dfa37abe670d2eb252aa9b402646be97cf3c50a", "a walk back is walked afresh");
        assert_eq!(hex(&body_key(&s32, (a + 2) * MINUTES_PER_DAY)), "925378a4bb83e7137cbb1f8cdaba8b79fc37e30d3159e4158da6e0fee8518bb5");
        assert_eq!(conv_w(&s32, a), "d29425fcf807a325b74d8bb017420cfe2250cc47e8bdc6351f6006cd4a6bdc9b");
        assert_eq!(conv_w(&s32, a + 2), "c665fdca8978b9c6e54b9a4f16a06ccac657ba7da259df0a8f3e2550d7c2d518");
        assert_eq!(hex(&conv_root(&s32)), "d9c3e7f533da2d0ed10b6729601c478ab29d1b0cafed60443113ee6a63824e11");
        assert_eq!((item_key(&s32, a), item_key(&s32, a + 1)), (s32.clone(), conv_root(&s32).to_vec()));
        assert_eq!(item_keys(&s32), [conv_root(&s32).to_vec(), s32.clone()]);
        // the author field stands on the same key: the root past the anchor, the secret on the anchor day; a reader holds both
        let person = r(0x33, 32);
        let root_tag = author_tag(&person, &conv_root(&s32), "m", "t");
        let anchor_tag = author_tag(&person, &s32, "m", "t");
        assert_ne!(root_tag, anchor_tag);
        assert_eq!(with_author_on(&[], Some(&person), &s32, "m", "t", a + 1), [vec![0; 7], root_tag.as_bytes().to_vec(), vec![0]].concat());
        assert_eq!(with_author_on(&[], Some(&person), &s32, "m", "t", a), [vec![0; 7], anchor_tag.as_bytes().to_vec(), vec![0]].concat());
        assert!(author_holds(&root_tag, Some(&person), &s32, "m", "t") && author_holds(&anchor_tag, Some(&person), &s32, "m", "t"));
    }

    #[test]
    fn the_pipe_agrees_with_ios_canon() {
        let s32: Vec<u8> = (0..32).collect();
        let owner = r(0x99, 32);
        let ring = vec![r(0x10, 32), r(0x90, 32)];
        assert_eq!(hex(&pipe_tag(&r(0x44, 32), 1000)), "1d99467017fe1d0cc7c7ba29df6fd1b6");
        assert_eq!(hex(&pipe_tag(&r(0x44, 32), 1001)), "c146445f67c990e25256dd88dfb39a49");
        assert_eq!(hex(&pipe_tag(&r(0x55, 32), 1000)), "783b2b17dffaab016d1aca852f60ea3e");
        assert_eq!(hex(&step_label(&r(0x51, 32), 1000)), "4b8cb5c6442a52d0750bfb4fac0ba39d");
        assert_eq!(hex(&step_label(&r(0x52, 32), 1000)), "401d8ab71a2e2554ab30c11aab1ae97d");
        assert_eq!(hex(&step_label(&r(0x51, 32), 1001)), "1cc3ac539a8b1d2701e489455a8b04d5");
        assert_eq!(hex(&relay_seal(&owner, &r(0xAA, 16))), "2c2231f087682d4daef313938a2da5e0");
        assert_eq!(hex(&relay_seal(&owner, &r(0xBB, 16))), "3e83b1e1610e48bfc13929a602617d79");
        assert_eq!(hex(&owner_ref(&owner, &r(0x44, 32))), "f4f72dafb742470e49defbd3c2326c27");
        assert_eq!(hex(&owner_ref(&owner, &r(0x45, 32))), "d24f63a8c1220ea9c176ec706b8a256f");
        assert_eq!(holder(&unhex("45468cdd9bcdebe6f622c46257c27fe3").unwrap(), &ring), Some(&ring[1]));
        assert_eq!(holder(&r(0xFF, 16), &ring), Some(&ring[0]));
        assert_eq!(hex(&window_pos(&s32, 0x0102030405060708)), "6f241143b5736f8ee9af63cd2db6fbf59b5bbc22069cc045307e8862e3ed6f8f");
        assert_eq!(hex(&window_pos(&s32, 1000)), "db09ddb4cd56d677bd1f9fdc00a6894bc088b2cb8a382eaeb1f76644f2f95eec");
        let auth: Vec<u8> = (0..1952).map(|i| ((i * 7 + 3) % 256) as u8).collect();
        assert_eq!(hex(&overlay_tag(&auth)), "f2c55658958eee8b961a4d63c2ec60a793cf9f22c373d115f3021523e3f0eabe");
    }

    #[test]
    fn the_author_field_agrees_with_ios_canon() {
        let key = r(0x61, 32);
        let secret = r(0x44, 32);
        let mid = "t1792249000000-ABCD";
        let text = "Привет, Montana 🌍";
        let mut head = [mid.as_bytes(), &[0], text.as_bytes(), &[0], b"Alice", &[0, 0]].concat();
        assert_eq!(author_tag(&key, &secret, mid, text), "WcOqZdlxhSpBEZYKgbjSSg==");
        assert_eq!(author_tag(&key, &secret, mid, ""), "AZIK29ezKo70HRREQwXbzA==");
        // the canon's vectors stand on the anchor day: the field signed under the established secret
        let signed = with_author_on(&head, Some(&key), &secret, mid, text, WALK_ANCHOR_DAY);
        assert_eq!(signed.len(), 82);
        assert_eq!(hex(&sha(&[&signed])), "5fe43b371f456a08e30ffe5d736c866719e26f5702fcf4da3ca7145ca39b358d");
        head.extend_from_slice(&[0, 0]);
        head.extend_from_slice(b"{\"u\":\"https://montana.quest\",\"t\":\"Montana\"}");
        assert_eq!(hex(&sha(&[&with_author_on(&head, Some(&key), &secret, mid, text, WALK_ANCHOR_DAY)])), "bd472907cb6fb8d2d13a4291f80f976fdb836658b4ecd1f3d9d53ad1ea112d9c");
        assert!(author_holds("WcOqZdlxhSpBEZYKgbjSSg==", Some(&key), &secret, mid, text));
        assert!(!author_holds("WcOqZdlxhSpBEZYKgbjSSg==", Some(&key), &secret, mid, "x"));
    }

    #[test]
    fn a_boxed_letter_opens_in_the_senders_minute_or_a_day_back() {
        let secret = r(0x33, 32);
        let w = minute();
        let sealed = seal(&body_key(&secret, w - 37), b"mid\0hello\0").unwrap();
        assert_eq!(open_boxed(&sealed, &secret, w * 60).as_deref(), Some(&b"mid\0hello\0"[..]));
        let f = fields(b"mid\0hello\0Alice\0\0", 0, 7);
        assert_eq!((f[0].as_str(), f[1].as_str(), f[2].as_str(), f[6].as_str()), ("mid", "hello", "Alice", ""));
    }
}
