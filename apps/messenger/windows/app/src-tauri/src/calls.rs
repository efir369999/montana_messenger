//! CALLS, ONE TO ONE (iOS MontanaCall + MontanaWakePush's call lane; Android Calls.kt, CallLine.kt): the voice and the picture
//! go by WebRTC in the window -- DTLS-SRTP, as iOS (SFrame is off on both platforms) -- and everything else rides Montana's
//! roads: the call's words on the signal lane under the call's epoch (the first sixteen characters of its seed), the ring
//! letter in the box (RG:), the VoIP knock that wakes a phone (/wake-voip), the TURN pass of the nodes (/turn-cred). The call
//! log is a row of the chat (CL:) written by each side; a missed call is told by the caller's MC: letter.

use crate::book::{birth_ms, mint_mid, Book, Msg};
use crate::post::{marks, Desk};
use crate::vault::Vault;
use crate::wire::{self, b64, body_key, conv_w, sub_id, unb64};
use crate::{crypto, doors};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Mutex;

pub const RING: &str = "\u{200B}\u{200B}RG:";
pub const MISSED: &str = "\u{200B}\u{200B}MC:";
pub const LOG: &str = "\u{200B}\u{200B}CL:";
pub const LIFE_S: i64 = 90;
const GRAVES: &str = "callGraves";
/// THE CALL ON DISK (iOS HeldCall, sealed by the device key): written while a call stands with a peer that rebuilds in place, so
/// the next run of a process that died holding it goes back in; a call that ended leaves nothing.
const HELD: &str = "callHeld";

/// A call that rang here by the box (the RG: letter), for the window to show.
#[derive(serde::Serialize, Clone, Debug)]
pub struct Ring {
    pub chat: String,
    pub seed: String,
    pub video: bool,
    pub name: String,
}

/// The rings the walks found, until the window takes them.
pub static RINGS: Mutex<Vec<Ring>> = Mutex::new(Vec::new());

pub fn epoch_of(seed: &str) -> String {
    seed.chars().take(16).collect()
}

/// The ring letter's tag (iOS MontanaMissedCall 49): the seed's letters and digits, the first twelve.
pub fn tag_of(seed: &str) -> String {
    seed.chars().filter(|c| c.is_ascii_alphanumeric()).take(12).collect()
}

/// A seed whose call ended lies a week in the graves: a late word of it never rings again.
pub fn bury(vault: &Vault, seed: &str) {
    let mut g: serde_json::Map<String, Value> = vault.get(GRAVES).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let now = wire::now_ms() / 1000;
    g.retain(|_, at| now - at.as_i64().unwrap_or(0) < 7 * 86_400);
    g.insert(epoch_of(seed), json!(now));
    vault.set(GRAVES, Value::Object(g).to_string().as_bytes());
}

/// The standing call written for the next run (the window's own record: peer, seed, sides, moments, rejoins).
pub fn hold(vault: &Vault, record: &str) -> bool {
    let ok = serde_json::from_str::<Value>(record).ok().is_some_and(|v| v["seed"].as_str().is_some_and(|s| wire::unb64(s).map(|b| b.len()) == Some(32)));
    ok && vault.set(HELD, record.as_bytes())
}

/// The call a process died holding, if any.
pub fn held(vault: &Vault) -> Option<String> {
    vault.get(HELD).and_then(|b| String::from_utf8(b).ok())
}

/// The record goes when its call ends -- only its own: a newer call's record stays.
pub fn unhold(vault: &Vault, seed: Option<&str>) {
    let mine = held(vault).and_then(|r| serde_json::from_str::<Value>(&r).ok()).map(|v| v["seed"].as_str().map(str::to_string));
    if seed.is_none() || mine.flatten().as_deref() == seed {
        vault.delete(HELD);
    }
}

pub fn buried(vault: &Vault, seed: &str) -> bool {
    let g: serde_json::Map<String, Value> = vault.get(GRAVES).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    g.contains_key(&epoch_of(seed))
}

/// The call's words onto the lane (iOS signalCall): twin ‖ 0 ‖ epoch ‖ 0 ‖ raw DEFLATE of the JSON array, sealed under the
/// pipe's minute key. ONE DOOR ONCE THE PEER IS HEARD (iOS MTCallRoute): the words go to the door the peer's own words came
/// by -- the one it reads -- and to every living door while none is known, or when that door refuses.
pub fn post_words(book: &Book, twin: &str, r: &str, epoch: &str, words: &str) -> bool {
    post_to(book, twin, r, epoch, words, door_of(epoch))
}

/// A packet that waited its receipt in vain goes to every living door (iOS: the route changes after a silence).
pub fn post_words_all(book: &Book, twin: &str, r: &str, epoch: &str, words: &str) -> bool {
    post_to(book, twin, r, epoch, words, None)
}

fn post_to(book: &Book, twin: &str, r: &str, epoch: &str, words: &str, door: Option<String>) -> bool {
    let Some(secret) = book.secret(r) else { return false };
    let plain = [twin.as_bytes(), &[0], epoch.as_bytes(), &[0], &miniz_oxide::deflate::compress_to_vec(words.as_bytes(), 6)].concat();
    let Some(env) = crypto::seal(&body_key(&secret, wire::minute()), &plain) else { return false };
    let cw = conv_w(&secret, wire::day());
    let body = json!({ "conv": cw, "from_id": sub_id(&cw, twin), "env": b64(&env) });
    if let Some(d) = door {
        if doors::post_at(&d, "/signal", &body, 5_000).0 == 200 {
            return true;
        }
    }
    let mut ok = false;
    for d in doors::all() {
        ok |= doors::post_at(&d, "/signal", &body, 5_000).0 == 200;
    }
    ok
}

/// The door the peer's words of this call came by (iOS MTCallRoute.heard): the one its lane is read at.
pub fn heard_at(epoch: &str, door: &str) {
    with_route(epoch, |r| r.door = Some(door.to_string()));
}

pub fn door_of(epoch: &str) -> Option<String> {
    with_route(epoch, |r| r.door.clone())
}

/// THE CALL'S PACKETS AND THEIR RECEIPTS (iOS MTCallRoute and receivedCallSignal): every word of one packet of mine names it
/// «q»; the far side answers each packet that names one with «call-receipt», a repeat too, and a packet without its receipt
/// in two seconds goes again to every door while the call lives; a packet heard twice reaches the window once.
#[derive(Default)]
pub struct Route {
    /// my packets waiting for their receipt: q, chat, the words, born, last sent, sent how often
    pending: Vec<(String, String, String, i64, i64, u32)>,
    /// the packets of theirs already heard, by q, and when
    heard: HashMap<String, i64>,
    touched: i64,
    /// the door the peer's words came by
    door: Option<String>,
}

/// The routes of the calls in flight, by epoch; a route untouched for twice a call's life is let go.
static ROUTES: Mutex<Option<HashMap<String, Route>>> = Mutex::new(None);
const RECEIPT_WAIT_MS: i64 = 2_000;
const TRIES: u32 = 6;

fn with_route<T>(epoch: &str, f: impl FnOnce(&mut Route) -> T) -> T {
    let mut all = ROUTES.lock().unwrap();
    let all = all.get_or_insert_with(HashMap::new);
    let now = wire::now_ms();
    all.retain(|_, r| now - r.touched < LIFE_S * 2000);
    let r = all.entry(epoch.to_string()).or_default();
    r.touched = now;
    f(r)
}

/// A packet of mine named (iOS sendCallSignal: msgs[i].q = receipt): each word of it carries one fresh «q»; a receipt names
/// none. The packet's name and its words.
pub fn name_packet(words: &str) -> Option<(String, String)> {
    let mut msgs: Vec<Value> = serde_json::from_str(words).ok()?;
    if msgs.is_empty() || msgs.iter().any(|m| m["ctrl"] == json!("call-receipt")) {
        return None;
    }
    let q = crate::book::mint_mid();
    for m in msgs.iter_mut() {
        m["q"] = json!(q);
    }
    Some((q.clone(), Value::Array(msgs).to_string()))
}

/// The receipt of their packet, as iOS writes it.
pub fn receipt_words(epoch: &str, q: &str) -> String {
    json!([{ "t": "cal", "ctrl": "call-receipt", "e": epoch, "q": q }]).to_string()
}

/// What one packet heard on the lane holds (iOS handleLiveCallSignal): the receipts of mine it brings, the names of theirs to
/// answer, and the words for the window -- none when it is all receipts, or a packet heard before.
#[derive(Debug, Default, PartialEq)]
pub struct Heard {
    pub receipts: Vec<String>,
    pub answer: Vec<String>,
    pub fresh: Option<String>,
}

pub fn sort_heard(epoch: &str, words: &str) -> Heard {
    let Ok(msgs) = serde_json::from_str::<Vec<Value>>(words) else { return Heard { fresh: Some(words.to_string()), ..Default::default() } };
    let now = wire::now_ms();
    with_route(epoch, |route| {
        let mut out = Heard::default();
        let mut kept = vec![];
        // a packet is new or a repeat as a whole: the first of its words decides for all of them (iOS acceptedReceipt)
        let mut fresh_q: HashMap<String, bool> = HashMap::new();
        for m in msgs {
            let q = m["q"].as_str().filter(|q| !q.is_empty() && q.len() <= 64).map(str::to_string);
            if m["ctrl"] == json!("call-receipt") {
                // transport state, never an instruction to the call
                if let Some(q) = q {
                    route.pending.retain(|p| p.0 != q);
                    out.receipts.push(q);
                }
                continue;
            }
            match q {
                Some(q) => {
                    if !out.answer.contains(&q) {
                        out.answer.push(q.clone()); // every repeat is answered: a lost receipt must not keep them sending
                    }
                    let first = *fresh_q.entry(q.clone()).or_insert_with(|| route.heard.insert(q, now).is_none());
                    if first {
                        kept.push(m);
                    }
                }
                None => kept.push(m), // an older build's word names no packet
            }
        }
        if route.heard.len() > 2048 {
            route.heard.retain(|_, t| now - *t <= LIFE_S * 1000);
        }
        if !kept.is_empty() {
            out.fresh = Some(Value::Array(kept).to_string());
        }
        out
    })
}

/// A packet of mine sent: kept until its receipt comes.
pub fn sent(epoch: &str, chat: &str, q: &str, words: &str) {
    let now = wire::now_ms();
    with_route(epoch, |r| {
        if r.pending.len() < 128 && !r.pending.iter().any(|p| p.0 == q) {
            r.pending.push((q.to_string(), chat.to_string(), words.to_string(), now, now, 1));
        }
    });
}

/// The packets of mine whose receipt did not come in two seconds, to go again: chat and words. A packet tried six times, or
/// older than the call's life, is let go.
pub fn due(epoch: &str) -> Vec<(String, String)> {
    let now = wire::now_ms();
    with_route(epoch, |r| {
        r.pending.retain(|p| p.5 < TRIES && now - p.3 < LIFE_S * 1000);
        let mut out = vec![];
        for p in r.pending.iter_mut().filter(|p| now - p.4 >= RECEIPT_WAIT_MS) {
            p.4 = now;
            p.5 += 1;
            out.push((p.1.clone(), p.2.clone()));
        }
        out
    })
}

/// One long poll of the call's lane: the words of this epoch (as JSON arrays), and whether a letter waits in the box.
pub fn listen(book: &Book, twin: &str, r: &str, epoch: &str, wait: u32) -> Option<(Vec<String>, bool)> {
    let secret = book.secret(r)?;
    let cw = conv_w(&secret, wire::day());
    let dev = wire::hex(&wire::sha(&[b"mt-lane-dev\0", format!("windows-call-{}", std::process::id()).as_bytes(), b"\0", cw.as_bytes()])[..8]);
    let body = json!({ "conv": cw, "from_id": sub_id(&cw, twin), "wait": wait, "dev": dev });
    let mut out = vec![];
    let mut boxed = false;
    let mut any = false;
    for door in doors::all() {
        let (code, v) = doors::post_at(&door, "/signal-fetch", &body, (wait + 3) * 1000);
        if code != 200 {
            continue;
        }
        any = true;
        for e in v.as_ref().and_then(|v| v["envs"].as_array()).cloned().unwrap_or_default() {
            let Some(e) = e.as_str() else { continue };
            if e == "box" {
                boxed = true;
                continue;
            }
            if let Some((_, ep, bytes)) = crate::presence::Presence::open(&secret, e, None) {
                if ep == epoch {
                    out.push(String::from_utf8_lossy(&bytes).into_owned());
                }
            }
        }
        if !out.is_empty() {
            heard_at(epoch, &door);
            break;
        }
    }
    any.then_some((out, boxed))
}

/// THE VOIP KNOCK (iOS MontanaWakePush.wakeVoip): «ring» ‖ 0 ‖ twin ‖ 0 ‖ raw DEFLATE of the call's card, sealed under the pipe
/// key; the first door that woke a phone ends the walk. 1 rung, 0 nobody (no phone of theirs takes VoIP wakes), -1 no door.
#[allow(clippy::too_many_arguments)]
pub fn wake_voip(book: &Book, twin: &str, r: &str, seed: &str, video: bool, name: &str, offer: &str, born: i64) -> i32 {
    let Some(secret) = book.secret(r) else { return -1 };
    let card = |o: &str| json!({ "o": o, "v": video, "s": seed, "n": name, "g": "", "av": false, "rj": false, "born": born }).to_string();
    let seal = |c: String| -> Option<String> {
        let plain = [b"ring".as_slice(), &[0], twin.as_bytes(), &[0], &miniz_oxide::deflate::compress_to_vec(c.as_bytes(), 6)].concat();
        crypto::seal(&body_key(&secret, wire::minute()), &plain).map(|e| b64(&e))
    };
    let Some(mut env) = seal(card(offer)) else { return -1 };
    if env.len() > 4600 {
        let Some(e) = seal(card("")) else { return -1 };
        env = e;
    }
    let cw = conv_w(&secret, wire::day());
    let body = json!({ "conv": cw, "from_id": sub_id(&cw, twin), "env": env, "dw": 1, "expires": born / 1000 + LIFE_S });
    let mut nobody = true;
    for d in doors::write_order() {
        let (code, v) = doors::post_at(&d, "/wake-voip", &body, 6_000);
        if code == 200 && v.as_ref().and_then(|v| v["sent"].as_i64().or(v["woken"].as_i64())).unwrap_or(0) > 0 {
            return 1;
        }
        if code != 404 {
            nobody = false;
        }
    }
    if nobody { 0 } else { -1 }
}

/// THE TURN PASS (iOS turnCred): asked of every door, the first answer taken -- {username, credential, uris, stun}.
pub fn turn_cred() -> Option<Value> {
    for d in doors::all() {
        let (code, v) = doors::post_at(&d, "/turn-cred", &json!({}), 6_000);
        if code == 200 {
            if let Some(v) = v.filter(|v| v["uris"].is_array()) {
                return Some(v);
            }
        }
    }
    None
}

/// The call's row in the chat (iOS CL:): video or voice, incoming or not, the seconds talked, missed or not.
pub fn log_row(book: &Book, r: &str, video: bool, inc: bool, dur: i64, miss: bool) {
    let mid = mint_mid();
    let at = birth_ms(&mid).unwrap_or_else(wire::now_ms);
    let text = format!("{LOG}{}", json!({ "v": video, "inc": inc, "dur": dur, "miss": miss }));
    book.edit(r, |c| {
        // the same call told twice within its life: one row (iOS: same kind within 90 s)
        if let Some(last) = c.msgs.iter().rev().find(|m| m.text.starts_with(LOG)) {
            if last.text == text && at - last.at < LIFE_S * 1000 {
                return;
            }
        }
        c.msgs.push(Msg { mid, text, mine: !inc, at, state: 2, ..Default::default() });
    });
}

impl Desk<'_> {
    /// The ring letter (iOS E2E.ringLetter): silent, one per call, named by the seed's tag.
    pub fn ring_letter(&self, r: &str, seed: &str, video: bool) -> String {
        let mid = format!("ring-{}", tag_of(seed));
        let w = json!({ "v": video, "s": seed, "n": self.my_name.trim(), "t": wire::now_ms() as f64 / 1000.0 });
        self.deliver(r, &mid, &format!("{RING}{w}"));
        mid
    }

    /// The missed call told (iOS MC:): the callee's chat gets its row and its banner; my other devices get the word as mine
    /// (iOS enqueue: MC: changes a row), and write the row of my call nobody answered.
    pub fn missed_letter(&self, r: &str, seed: &str, video: bool) {
        let (mid, text) = (mint_mid(), format!("{MISSED}{}", json!({ "v": video, "s": seed })));
        self.mirror_sent(r, &mid, &text, "", "", "");
        self.deliver(r, &mid, &text);
    }

    /// A ring by the box (iOS ChatStore 4370-4392): too old or buried -- nothing; else the window rings.
    pub fn heard_ring(&self, r: &str, text: &str) {
        let Some(o) = text.strip_prefix(RING).and_then(|j| serde_json::from_str::<Value>(j).ok()) else { return };
        let Some(seed) = o["s"].as_str().filter(|s| unb64(s).is_some_and(|b| b.len() == 32)) else { return };
        let t = o["t"].as_f64().unwrap_or(0.0);
        if wire::now_ms() as f64 / 1000.0 - t > LIFE_S as f64 || buried(self.vault, seed) || self.book.chat(r).is_some_and(|c| c.blocked) || crate::doors::barred(r) {
            return;
        }
        let ring = Ring { chat: r.to_string(), seed: seed.to_string(), video: o["v"].as_bool().unwrap_or(false), name: o["n"].as_str().unwrap_or("").to_string() };
        let mut rings = RINGS.lock().unwrap();
        if !rings.iter().any(|x| x.seed == ring.seed) {
            rings.push(ring);
        }
    }

    /// A missed call told by the caller (iOS DeliveryEngine 284-306): a row and a banner, unless the seed is known here; the
    /// receipt only from the device that took it from the box (`answer`), never from a copy of the twin mirror.
    pub fn heard_missed(&self, r: &str, mid: &str, text: &str, answer: bool) {
        if let Some(o) = text.strip_prefix(MISSED).and_then(|j| serde_json::from_str::<Value>(j).ok()) {
            if let Some(seed) = o["s"].as_str() {
                if !buried(self.vault, seed) {
                    bury(self.vault, seed);
                    log_row(self.book, r, o["v"].as_bool().unwrap_or(false), true, 0, true);
                    self.news.lock().unwrap().push(crate::post::News { chat: r.to_string(), text: "☎️ Пропущенный звонок".into(), anon: None });
                }
            }
        }
        if answer {
            self.deliver(r, &format!("rcpt-{mid}"), &format!("{}{mid}", marks::DELIVERED));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_standing_call_is_kept_sealed_for_the_next_run_and_goes_with_its_own_end_only() {
        let d = std::env::temp_dir().join(format!("montana-held-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let v = Vault::at(&d).unwrap();
        let seed = wire::b64(&[7u8; 32]);
        assert!(!hold(&v, "{\"seed\":\"short\"}"), "a record without a call's seed is not kept");
        assert!(!hold(&v, "not json"));
        assert_eq!(held(&v), None);
        let rec = json!({ "chat": "pipe-a", "seed": seed, "connectedAt": 1, "rebuilds": true, "alive": 2 }).to_string();
        assert!(hold(&v, &rec));
        assert_eq!(held(&v).as_deref(), Some(rec.as_str()), "the next run reads the very record");
        let sealed = std::fs::read(d.join("callHeld.sealed")).unwrap();
        assert!(!String::from_utf8_lossy(&sealed).contains(&seed), "the seed is never on the disk in the clear");
        unhold(&v, Some(&wire::b64(&[8u8; 32])));
        assert!(held(&v).is_some(), "another call's end leaves this record");
        unhold(&v, Some(&seed));
        assert_eq!(held(&v), None, "its own end takes it");
        assert!(hold(&v, &rec));
        unhold(&v, None);
        assert_eq!(held(&v), None, "a judged record goes");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn the_peers_door_carries_the_calls_words_once_it_is_heard() {
        let epoch = "door-test-epoch0";
        assert_eq!(door_of(epoch), None, "every door while the peer is unheard");
        heard_at(epoch, "https://door.example/pushwake");
        assert_eq!(door_of(epoch).as_deref(), Some("https://door.example/pushwake"));
        heard_at(epoch, "https://other.example/pushwake");
        assert_eq!(door_of(epoch).as_deref(), Some("https://other.example/pushwake"), "the latest door the peer spoke by");
        assert_eq!(door_of("another-epoch-00"), None, "a door is the call's own");
    }

    #[test]
    fn a_packet_is_named_answered_each_time_and_heard_once() {
        let words = json!([{ "t": "cal", "ctrl": "call-ice", "candidate": { "c": "a" } }, { "t": "cal", "ctrl": "call-ice", "candidate": { "c": "b" } }]).to_string();
        let (q, named) = name_packet(&words).unwrap();
        let msgs: Vec<Value> = serde_json::from_str(&named).unwrap();
        assert!(msgs.iter().all(|m| m["q"] == json!(q)), "every word of the packet names it");
        assert!(name_packet(&receipt_words("e1", &q)).is_none(), "a receipt names no packet");
        // heard: answered, and the window hears it once
        let first = sort_heard("e1", &named);
        assert_eq!((first.answer.clone(), first.receipts.len()), (vec![q.clone()], 0));
        assert_eq!(first.fresh.as_deref().map(|f| serde_json::from_str::<Vec<Value>>(f).unwrap().len()), Some(2));
        let again = sort_heard("e1", &named);
        assert_eq!((again.answer, again.fresh), (vec![q.clone()], None), "a repeat is answered, never heard twice");
        // an older build's packet names none: heard each time, answered never
        let old = sort_heard("e1", &words);
        assert!(old.answer.is_empty() && old.fresh.is_some());
        // mine waits for its receipt, goes again after two seconds, and the receipt lets it go
        sent("e2", "chat", &q, &named);
        assert!(due("e2").is_empty(), "not yet");
        with_route("e2", |r| r.pending[0].4 -= RECEIPT_WAIT_MS);
        assert_eq!(due("e2"), vec![("chat".to_string(), named.clone())]);
        let back = sort_heard("e2", &receipt_words("e2", &q));
        assert_eq!((back.receipts, back.fresh), (vec![q.clone()], None), "a receipt is transport, never the call's word");
        with_route("e2", |r| assert!(r.pending.is_empty()));
    }
}
