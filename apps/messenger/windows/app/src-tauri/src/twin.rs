//! THE PERSON'S OTHER DEVICES (iOS MontanaArchive's twin, MontanaPQ.swift 872-1155; MontanaDeliveryEngine.landMirrored and
//! landOwn; ChatStore.readByTwin): every device of the 24 words is one reference to the pipes of its correspondents, so the
//! node's box hands a letter to whichever device takes it first, that device's confirmation erases it for the rest, and a
//! letter one device sent the box never gives the others. So the devices of the words keep in step through a pipe only these
//! words derive («twin:history»): what one device lands from a correspondent, sends or reads rides to the others as words of
//! a mirror («lt»), and the blocks of its archive ride beside them («hist») -- both on the cargo road, named by one silent
//! letter in that pipe, laid within half a minute with whatever came beside it.

use crate::book::{birth_ms, Chat, Msg};
use crate::post::{marks, Desk};
use crate::wire::{self, hex, sha};
use crate::{groups, history, meeting};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

/// A read mark for the person's own devices alone, + the birth millisecond of the newest letter read; never on a pair's wire.
pub const READ_MARK: &str = "\u{200B}\u{200B}TR:";
/// The twin's past asked and given back, and a card born on another device (iOS twinAskMark, twinRowMark, twinCardMark).
const ASK_MARK: &str = "\u{200B}\u{200B}TA:";
const ROW_MARK: &str = "\u{200B}\u{200B}TW:";
const CARD_MARK: &str = "\u{200B}\u{200B}TC:";
const KEEP_MARK: &str = "\u{200B}\u{200B}KP:";
/// The mirror's name for the cards' words, never a conversation (iOS twinCardPipe).
const CARD_PIPE: &str = "twin:card";

const QUEUE: &str = "twinMirror"; // the words not laid yet, in order (iOS twin-mirror.json)
const GIVEN: &str = "twinGiven"; // c/m/x[..24] -> the second it was queued: a name is given once within the hour
const DUE: &str = "twinDue"; // "lt" / "hist" -> the millisecond the next lay is due (0: nothing waits)
const SEEN: &str = "twinSeen"; // the letters of the other devices already taken here, the newest 512 (iOS mt.history.twinSeen)
const BOXED: &str = "twinBoxed"; // folder -> the first block of mine not laid yet (iOS mt.history.boxed)
const HELD: &str = "twinHeld"; // words for a pipe this machine does not know yet: they land once its head comes
const ASKED: &str = "twinAsked"; // chat/second/hash of the rows already asked of the other devices (iOS mt.twin.asked)
pub const GONE: &str = "twinGone"; // the SHA-256 (hex) of correspondences erased here: their blocks are not filed again
const WAITING: &str = "twinWaiting"; // chat/second/hash -> a text row asked by its key, landing by its archive name past its hour

const KEPT: usize = 4000; // [I-14]: a device away for long is given the newest, the history road keeps the rest
const ROUND: usize = 500;
const CAP: usize = 8 << 20; // one letter's file stays small; what is left rides the next round
const SOON_MS: i64 = 30_000;
const AGAIN_MS: i64 = 120_000; // a lay that did not reach the nodes is tried again later
const HOLD_MS: i64 = 2 * 86_400_000;
const ANSWER_MS: i64 = 120_000; // an iPhone gives an asked row back within its mirror's half minute; past two, no device will

static QLOCK: Mutex<()> = Mutex::new(());
static DLOCK: Mutex<()> = Mutex::new(());
/// The rows of the twin's pipe whose road did not come whole: tried again by the next walks, let go after five.
static FAILS: Mutex<Option<HashMap<String, u32>>> = Mutex::new(None);

/// One word of the mirror (iOS TwinWord), as JSON with its empty fields left out.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Word {
    /// the pipe it rode, or the conversation a read mark reads
    pub c: String,
    /// its wire name, as it was born
    pub m: String,
    /// the letter's words, as the correspondent's device opens them
    pub x: String,
    /// 1: the person's own word
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub o: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub qt: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub qm: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lp: Option<String>,
    /// its place in this device's queue, never read by the other
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub q: Option<i64>,
}

fn some(s: &str) -> Option<String> {
    (!s.is_empty()).then(|| s.to_string())
}

/// The pipe's secret (iOS twinSecret): the history key under its own label and this app's name -- only a device holding these
/// words derives it.
pub fn secret(hk: &[u8]) -> [u8; 32] {
    sha(&[b"mt-twin-box\0", history::APP.as_bytes(), b"\0", hk])
}

/// This machine's tag among the devices of the words (iOS E2E.deviceTag, «ios-» there): the words' entropy over the device id.
pub fn device_tag(entropy: &[u8], device: &[u8]) -> String {
    format!("windows-{}", hex(&sha(&[b"mt-device-tag\0", entropy, device])[..6]))
}

/// THIS MACHINE'S NAME AMONG THE PERSON'S DEVICES (iOS twinDeviceRef): the pipe of the devices knows it by it, and since 2306 every
/// box marks what this machine took by it under each label (MontanaArchive.deviceSid = the label's sid of this name).
pub fn device_name(twin: &str, a: &crate::history::Archive) -> String {
    format!("{twin}#{}", device_tag(&a.keys().entropy, &a.device()))
}

/// The pipe, this machine's name in it (iOS twinDeviceRef: the node rings every device of the pipe but the one that spoke),
/// and its writer tag in hex (the «f» of a letter it lays).
pub struct Me {
    pub secret: [u8; 32],
    pub name: String,
    pub tag: String,
}

/// The words of the wire that are machinery between two phones, never a row (iOS isControlMarker, ContentView.swift 4093).
const CONTROL: [&str; 29] = [
    marks::READ, marks::DELIVERED, "\u{200B}\u{200B}TY:", marks::REACT, marks::AVATAR, marks::NAME, marks::ABOUT,
    "\u{200B}\u{200B}PG:", "\u{200B}\u{200B}QC:", marks::VOICE, marks::DELETE, marks::CONVDEL, "\u{200B}\u{200B}DF:",
    marks::MEDIA, marks::STICKER, "\u{200B}\u{200B}WH:", "\u{200B}\u{200B}PA:", "\u{200B}\u{200B}EX:", marks::CARGO_GONE,
    "\u{200B}\u{200B}WA:", "\u{200B}\u{200B}PL:", "\u{200B}\u{200B}AP:", marks::EDIT, marks::PIN, "\u{200B}\u{200B}SM:",
    "\u{200B}\u{200B}SY:", "\u{200B}\u{200B}PX:", KEEP_MARK, "\u{200B}\u{200B}DK:",
];

/// THE MIRROR'S CHOICE OF WORDS (iOS MontanaDeliveryEngine.mirrors): what stands in a conversation or moves a row -- a letter of
/// every kind, a receipt, a read mark, a deletion, a group's word -- rides to the other devices; what says only «here, now»
/// (typing, presence, a name, a face) does not. By the code, an edit, a reaction and a pin do not ride either.
pub fn mirrors(t: &str) -> bool {
    if t.starts_with(groups::MARK) {
        return groups::mirrors(t);
    }
    if [marks::DELIVERED, marks::READ, marks::DELETE].iter().any(|m| t.starts_with(m)) {
        return true;
    }
    !CONTROL.iter().any(|m| t.starts_with(m)) || [marks::MEDIA, marks::VOICE, marks::STICKER].iter().any(|m| t.starts_with(m))
}

/// A row the twin's blocks gave back under the archive's own name (arc:…) is the same letter a word of the mirror brings
/// under its wire name: the row takes the name instead of standing twice. True when such a row was renamed.
pub fn arc_rename(c: &mut Chat, mid: &str, text: &str, mine: bool, at: i64) -> bool {
    match c.msgs.iter_mut().find(|m| m.mid.starts_with("arc:") && m.mine == mine && m.text == text && (m.at - at).abs() < 2_000) {
        Some(m) => {
            m.mid = mid.to_string();
            true
        }
        None => false,
    }
}

/// The archive's key of a row's words, the same on every device of the seed (iOS rowHash): eight bytes of SHA-256, in hex.
pub fn row_hash(archived: &str) -> String {
    hex(&sha(&[archived.as_bytes()])[..8])
}

/// A row's words as the archive writes them (iOS archivedText): a file in the archive's own form.
fn archived(m: &Msg) -> String {
    if m.text.starts_with(crate::media::MARK) { history::archive_media(&m.mid, &m.text) } else { m.text.clone() }
}

/// A row's archive key (iOS archiveSig): the second, the side, the words.
fn sig(at_secs: i64, mine: bool, archived: &str) -> String {
    format!("{at_secs}|{}|{archived}", if mine { 1 } else { 0 })
}

fn jmap(v: &crate::vault::Vault, name: &str) -> Map<String, Value> {
    match v.get(name).and_then(|b| serde_json::from_slice(&b).ok()) {
        Some(Value::Object(o)) => o,
        _ => Map::new(),
    }
}

fn jlist<T: serde::de::DeserializeOwned>(v: &crate::vault::Vault, name: &str) -> Vec<T> {
    v.get(name).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn keep<T: Serialize>(v: &crate::vault::Vault, name: &str, x: &T) {
    if let Ok(b) = serde_json::to_vec(x) {
        v.set(name, &b);
    }
}

impl Desk<'_> {
    /// The pipe of these words' devices and this machine in it; None before the archive stands (its keys are the words').
    pub fn twin_me(&self) -> Option<Me> {
        let a = self.archive.as_ref()?;
        let k = a.keys();
        let tag = a.writer_tag()?;
        Some(Me { secret: secret(&k.hk), name: device_name(&self.twin, a), tag: hex(&tag) })
    }

    // ───────────────────────────── laying ─────────────────────────────

    /// A WORD FOR THE OTHER DEVICES (iOS mirrorNote): kept beside the history until it rode, laid within half a minute with
    /// whatever came beside it. A name given within the hour is not queued twice; a newer read mark of a conversation stands
    /// for the older; the newest 4000 are kept.
    pub fn mirror_note(&self, mut w: Word) {
        if self.archive.is_none() {
            return;
        }
        {
            let _g = QLOCK.lock().unwrap();
            let mut q: Vec<Word> = jlist(self.vault, QUEUE);
            let reads = w.x.starts_with(READ_MARK);
            if reads {
                q.retain(|e| !(e.c == w.c && e.x.starts_with(READ_MARK)));
            }
            let now = wire::now_ms() / 1000;
            let name = format!("{}/{}/{}", w.c, w.m, w.x.chars().take(24).collect::<String>());
            let mut given = jmap(self.vault, GIVEN);
            if !reads && given.get(&name).and_then(|v| v.as_i64()).is_some_and(|t| now - t <= 3600) {
                return;
            }
            given.insert(name, json!(now));
            if given.len() > 2000 {
                given.retain(|_, v| now - v.as_i64().unwrap_or(0) < 3600);
            }
            self.vault.set(GIVEN, Value::Object(given).to_string().as_bytes());
            w.q = Some(q.iter().filter_map(|e| e.q).max().unwrap_or(0) + 1);
            q.push(w);
            if q.len() > KEPT {
                let over = q.len() - KEPT;
                q.drain(..over);
            }
            keep(self.vault, QUEUE, &q);
        }
        self.twin_soon("lt", SOON_MS);
    }

    /// What this person sent rides to the other devices under its name (iOS enqueue): a pair's letter or word the mirror
    /// carries -- never a receipt or a read mark, which are this device's word to the correspondent; a group's words ride as the
    /// copies they are (carry).
    pub fn mirror_sent(&self, r: &str, mid: &str, text: &str, qt: &str, qm: &str, lp: &str) {
        // Saved Messages is never mirrored: its letters ride the archive's blocks alone (iOS: no enqueue, no mirrorNote)
        if groups::is_group(r) || crate::book::is_saved(r) || !mirrors(text) || text.starts_with(marks::DELIVERED) || text.starts_with(marks::READ) {
            return;
        }
        let at = wire::now_ms() as f64 / 1000.0;
        self.mirror_note(Word { c: r.into(), m: mid.into(), x: text.into(), o: Some(1), at: Some(at), qt: some(qt), qm: some(qm), lp: some(lp), q: None });
    }

    /// A correspondent's word this device took rides to the other devices (iOS receive): the box gave it to this one, and this
    /// one's confirmation erases it there.
    pub fn mirror_heard(&self, r: &str, mid: &str, text: &str, qt: &str, qm: &str, lp: &str) {
        if !mirrors(text) {
            return;
        }
        let at = birth_ms(mid).unwrap_or_else(wire::now_ms) as f64 / 1000.0;
        self.mirror_note(Word { c: r.into(), m: mid.into(), x: text.into(), at: Some(at), qt: some(qt), qm: some(qm), lp: some(lp), ..Default::default() });
    }

    /// THE LIVE CARDS GO TO THE OTHER DEVICES (iOS twinLiveCards): said at a birth and at every keeping-up; a repeat within
    /// the hour rides once (the queue's own rule).
    pub fn twin_cards(&self) {
        for (inv, body) in (crate::card::Card { vault: self.vault }).live_cards() {
            self.mirror_note(Word { c: CARD_PIPE.into(), m: inv, x: format!("{CARD_MARK}{body}"), o: Some(1), ..Default::default() });
        }
    }

    /// A lay is due within `ms` (iOS mirrorSoon / twinSoon): a lay already due keeps its moment.
    pub fn twin_soon(&self, what: &str, ms: i64) {
        let _g = DLOCK.lock().unwrap();
        let mut d = jmap(self.vault, DUE);
        if d.get(what).and_then(|v| v.as_i64()).unwrap_or(0) == 0 {
            d.insert(what.into(), json!(wire::now_ms() + ms));
            self.vault.set(DUE, Value::Object(d).to_string().as_bytes());
        }
    }

    fn twin_due(&self, what: &str) -> bool {
        let _g = DLOCK.lock().unwrap();
        let mut d = jmap(self.vault, DUE);
        let at = d.get(what).and_then(|v| v.as_i64()).unwrap_or(0);
        if at == 0 || at > wire::now_ms() {
            return false;
        }
        d.insert(what.into(), json!(0));
        self.vault.set(DUE, Value::Object(d).to_string().as_bytes());
        true
    }

    /// THE TWIN'S WALK: the words and the blocks that are due are laid; words held for a pipe unknown here are tried again.
    pub fn twin_walk(&self) -> bool {
        if self.twin_due("lt") {
            self.lay_mirror();
        }
        if self.twin_due("hist") {
            self.lay_hist();
        }
        let held = self.land_held();
        self.land_waiting() || held
    }

    /// THE WORDS LAID (iOS layMirror): up to 500 as one JSON array on the cargo road, named by a silent letter in the pipe with
    /// «w» «lt», their count and this machine's writer tag; what rode leaves the queue, the rest waits for the next round.
    pub fn lay_mirror(&self) -> bool {
        let Some(me) = self.twin_me() else { return false };
        let batch: Vec<Word> = {
            let _g = QLOCK.lock().unwrap();
            jlist::<Word>(self.vault, QUEUE).into_iter().take(ROUND).collect()
        };
        if batch.is_empty() {
            return true;
        }
        let Ok(body) = serde_json::to_vec(&batch) else { return false };
        let laid = history::lay_road(&body).is_some_and(|mut road| {
            road["w"] = json!("lt");
            road["n"] = json!(batch.len());
            road["f"] = json!(me.tag);
            history::knock(&me.secret, &me.name, &format!("{KEEP_MARK}{road}"))
        });
        if !laid {
            crate::trace_line(&format!("twin_lt the words did not reach the nodes n={}", batch.len()));
            self.twin_soon("lt", AGAIN_MS);
            return false;
        }
        crate::trace_line(&format!("twin_lt laid words={} reads={}", batch.len(), batch.iter().filter(|w| w.x.starts_with(READ_MARK)).count()));
        let top = batch.iter().filter_map(|w| w.q).max().unwrap_or(-1);
        let left = {
            let _g = QLOCK.lock().unwrap();
            let mut q: Vec<Word> = jlist(self.vault, QUEUE);
            q.retain(|e| e.q.unwrap_or(-1) > top);
            keep(self.vault, QUEUE, &q);
            q.len()
        };
        if left > 0 {
            self.twin_soon("lt", SOON_MS);
        }
        true
    }

    /// THE BLOCKS LAID (iOS layForTwins): every block this machine sealed since the last lay, folder by folder, as one file
    /// (u32 LE length ‖ sealed)×N of at most 8 MiB on the cargo road, «w» «hist»; the cursor moves only once a door boxed it.
    pub fn lay_hist(&self) -> bool {
        let (Some(me), Some(a)) = (self.twin_me(), self.archive.as_ref()) else { return false };
        let Some(wt) = a.writer_tag() else { return false };
        let cursor = jmap(self.vault, BOXED);
        let (mut blob, mut tops, mut n, mut more) = (Vec::new(), Map::new(), 0usize, false);
        for f in a.folders() {
            if blob.len() > CAP {
                more = true;
                break;
            }
            let from = cursor.get(&f).and_then(|v| v.as_u64()).unwrap_or(0);
            let mut top = from;
            for (seq, sealed) in a.export(&f, &wt, from) {
                blob.extend_from_slice(&(sealed.len() as u32).to_le_bytes());
                blob.extend_from_slice(&sealed);
                top = top.max(seq + 1);
                n += 1;
            }
            if top != from {
                tops.insert(f, json!(top));
            }
        }
        if n == 0 {
            return true;
        }
        let laid = history::lay_road(&blob).is_some_and(|mut road| {
            road["w"] = json!("hist");
            road["n"] = json!(n);
            road["f"] = json!(me.tag);
            history::knock(&me.secret, &me.name, &format!("{KEEP_MARK}{road}"))
        });
        if !laid {
            self.twin_soon("hist", AGAIN_MS);
            return false;
        }
        let mut cursor = jmap(self.vault, BOXED);
        for (k, v) in tops {
            let was = cursor.get(&k).and_then(|x| x.as_u64()).unwrap_or(0);
            cursor.insert(k, json!(was.max(v.as_u64().unwrap_or(0))));
        }
        self.vault.set(BOXED, Value::Object(cursor).to_string().as_bytes());
        if more {
            self.twin_soon("hist", SOON_MS);
        }
        true
    }

    // ───────────────────────────── taking ─────────────────────────────

    /// A ROW OF THE TWIN'S PIPE (iOS twinTakes): never a letter of the feed. Blocks of the history or words of the mirror,
    /// fetched by their road; a letter this machine laid itself stays for the others. True when the row may be confirmed to
    /// the node -- taken, already taken, not ours, or a road that failed five times.
    pub fn twin_takes(&self, me: &Me, plain: &[u8]) -> bool {
        let f = wire::fields(plain, 0, 2);
        let Some(o) = f[1].strip_prefix(KEEP_MARK).and_then(|j| serde_json::from_str::<Value>(j).ok()) else { return true };
        if f[0].is_empty() {
            return true;
        }
        if o["f"].as_str() == Some(me.tag.as_str()) {
            return false; // this machine's own letter, heard back from the box: it stays for the others
        }
        let mid = f[0].clone();
        let seen: Vec<String> = jlist(self.vault, SEEN);
        if seen.contains(&mid) {
            crate::trace_line(&format!("twin_take mid={} seen before", mid.chars().take(8).collect::<String>()));
            return true;
        }
        let taken = match o["w"].as_str() {
            Some("lt") => self.take_mirror(&o),
            Some("hist") => self.take_hist(&o),
            _ => true, // a word of the pipe this build does not know: taken unread (iOS: COMPAT-GATED)
        };
        let mut fails = FAILS.lock().unwrap();
        let fails = fails.get_or_insert_with(HashMap::new);
        if !taken {
            let n = fails.entry(mid.clone()).or_insert(0);
            *n += 1;
            crate::trace_line(&format!("twin_take mid={} the road did not come whole fails={n}", mid.chars().take(8).collect::<String>()));
            if *n < 5 {
                return false;
            }
        }
        fails.remove(&mid);
        let mut seen = seen;
        seen.push(mid);
        let over = seen.len().saturating_sub(512);
        seen.drain(..over);
        keep(self.vault, SEEN, &seen);
        true
    }

    /// THE WORDS OF THE OTHER DEVICE (iOS takeMirror): each lands here by the one landing road, in the order that device heard
    /// them. False when the road did not come whole.
    fn take_mirror(&self, o: &Value) -> bool {
        let Some(file) = history::fetch_road(o) else { return false };
        let Ok(words) = serde_json::from_slice::<Vec<Word>>(&file) else { return true };
        for w in &words {
            self.land_mirrored(w);
        }
        crate::trace_line(&format!("twin_lt taken words={}", words.len()));
        true
    }

    /// THE BLOCKS OF THE OTHER DEVICE (iOS takeFromTwin + absorb): each filed in its correspondence's folder; a block of a
    /// correspondence erased here is not filed; a correspondence this machine does not hold stands from them, as a restore
    /// stands it -- its secret and name from the heads, its letters from the rows. False when the road did not come whole.
    fn take_hist(&self, o: &Value) -> bool {
        let Some(blob) = history::fetch_road(o) else { return false };
        self.file_blocks(&blob);
        true
    }

    /// The blocks of one file filed; the count of correspondences that stood new.
    pub fn file_blocks(&self, blob: &[u8]) -> usize {
        let Some(a) = &self.archive else { return 0 };
        let gone = jmap(self.vault, GONE);
        let mut known: HashMap<[u8; 32], String> = HashMap::new();
        for r in self.book.refs().into_iter().chain(self.book.all().into_iter().map(|c| c.reference)) {
            known.insert(sha(&[r.as_bytes()]), r);
        }
        known.insert(sha(&[crate::book::SAVED.as_bytes()]), crate::book::SAVED.to_string());   // no secret names it (iOS refBook)
        let mut fresh: Vec<history::Record> = vec![];
        let mut gaps: HashMap<String, Vec<history::Item>> = HashMap::new();
        let mut i = 0;
        while i + 4 <= blob.len() {
            let len = u32::from_le_bytes(blob[i..i + 4].try_into().unwrap()) as usize;
            i += 4;
            if len == 0 || i + len > blob.len() {
                break;
            }
            let sealed = &blob[i..i + len];
            i += len;
            let Some(conv) = a.peek_conv(sealed) else { continue };
            if gone.contains_key(&hex(&conv)) {
                continue;
            }
            match known.get(&conv).filter(|r| self.book.chat(r).is_some()) {
                Some(r) => {
                    a.ingest(r, sealed);
                    gaps.entry(r.clone()).or_default().extend(a.open_block(sealed).into_iter().filter(|i| i.dir != history::HEAD_DIR));
                }
                None => fresh.push(history::Record { kind: history::KIND_BLOCK, name: String::new(), data: sealed.to_vec() }),
            }
        }
        for (r, items) in gaps {
            self.ask_twin(&r, &items);
        }
        if fresh.is_empty() {
            return 0;
        }
        let done = history::restore(a, self.book, self.media, Some(self.faces), &fresh);
        if done.chats > 0 {
            self.land_held();
        }
        done.chats
    }

    // ───────────────────────────── the past the other device missed ─────────────────────────────

    /// THE PAST THE OTHER DEVICE HOLDS AND THIS FEED DOES NOT (iOS archive_gap + MontanaArchive.askTwin): the mirror carries what
    /// lands from now on, and an archive row bears no letter's name, so its blocks never lay rows into a conversation held here.
    /// The rows of those blocks no row here answers by the archive's key -- the second, the side, the words -- are asked of the
    /// other devices by that key, once each, two hundred a round; a conversation with no row here is the blocks' own to fill.
    fn ask_twin(&self, r: &str, items: &[history::Item]) {
        let Some(c) = self.book.chat(r).filter(|c| !c.msgs.is_empty()) else { return };
        let have: HashSet<String> = c.msgs.iter().filter(|m| m.at > 0).map(|m| sig(m.at / 1000, m.mine, &archived(m))).collect();
        let mut asked: Vec<String> = jlist(self.vault, ASKED);
        let mut waiting = jmap(self.vault, WAITING);
        let (mut seen, mut fresh) = (HashSet::new(), vec![]);
        for i in items {
            let Some(text) = String::from_utf8(i.content.clone()).ok().filter(|t| !t.is_empty()) else { continue };
            let (mine, at) = (i.dir == 0, i.at as i64);
            let s = sig(at, mine, &text);
            if !seen.insert(s.clone()) || have.contains(&s) {
                continue;
            }
            let h = row_hash(&text);
            let key = format!("{r}/{at}/{h}");
            if asked.contains(&key) {
                continue;
            }
            if fresh.len() >= 200 {
                break;
            }
            if !text.starts_with(crate::media::MARK) {
                waiting.insert(key.clone(), json!({ "r": r, "at": at, "o": mine, "x": text, "due": wire::now_ms() + ANSWER_MS }));
            }
            asked.push(key);
            fresh.push(json!([at, if mine { 1 } else { 0 }, h]));
        }
        if fresh.is_empty() {
            return;
        }
        let over = asked.len().saturating_sub(5000);
        asked.drain(..over);
        keep(self.vault, ASKED, &asked);
        if waiting.len() <= 2000 {
            self.vault.set(WAITING, Value::Object(waiting).to_string().as_bytes());
        }
        self.mirror_note(Word { c: r.into(), m: crate::book::mint_mid(), x: format!("{ASK_MARK}{}", json!({ "i": fresh })), o: Some(1), ..Default::default() });
    }

    /// THE PAST NO DEVICE GAVE BACK (Android keeps its devices in step by the blocks alone -- MontanaArchive.absorb lays a twin's
    /// blocks into its feed -- and speaks no mirror, so a TA: of mine finds no TW:): a text row asked by its key and not given back
    /// within two minutes lands by its archive name, as a copy lays it. A row of the same side and words within two minutes of
    /// it is the answer that came; a letter buried here born in the same second is that row, and it stays in its grave. A file's
    /// row waits for its TW:, which alone carries the file. True when a row landed.
    fn land_waiting(&self) -> bool {
        let mut w = jmap(self.vault, WAITING);
        let now = wire::now_ms();
        let due: Vec<String> = w.iter().filter(|(_, v)| v["due"].as_i64().unwrap_or(0) <= now).map(|(k, _)| k.clone()).collect();
        if due.is_empty() {
            return false;
        }
        let mut landed = false;
        for k in due {
            let Some(v) = w.remove(&k) else { continue };
            let (r, at, mine, text) = (v["r"].as_str().unwrap_or(""), v["at"].as_i64().unwrap_or(0), v["o"].as_bool().unwrap_or(false), v["x"].as_str().unwrap_or(""));
            if r.is_empty() || at <= 0 || text.is_empty() {
                continue;
            }
            let mid = history::arc_mid(at as u64, mine, text);
            self.book.edit(r, |c| {
                let answered = c.msgs.iter().any(|m| m.mid == mid || (m.mine == mine && archived(m) == text && (m.at / 1000 - at).abs() <= 120));
                let buried = c.graves.iter().any(|g| *g == mid || birth_ms(g).is_some_and(|b| (b / 1000 - at).abs() <= 1));
                if !answered && !buried {
                    c.msgs.push(Msg { mid: mid.clone(), text: text.to_string(), mine, at: at * 1000, state: if mine { 2 } else { 0 }, ..Default::default() });
                    c.msgs.sort_by_key(|m| m.at);
                    landed = true;
                }
            });
        }
        self.vault.set(WAITING, Value::Object(w).to_string().as_bytes());
        landed
    }

    /// A row whose file did not come whole is asked again the next time the gap is measured (iOS unaskTwin): its key goes by
    /// the conversation and the second, whatever form of the file's words the asker hashed.
    fn unask_twin(&self, r: &str, at: i64) {
        let mut asked: Vec<String> = jlist(self.vault, ASKED);
        asked.retain(|k| !k.starts_with(&format!("{r}/{at}/")));
        keep(self.vault, ASKED, &asked);
    }

    /// THE OTHER DEVICE ASKS FOR ROWS ITS ARCHIVE HOLDS AND ITS FEED DOES NOT (iOS ChatStore.giveTwinRows): each row held here
    /// under an asked key is given back by its name -- its words, and its file by the cargo road; a row this machine does not
    /// hold is the truth too (deleted here, or never here), and nothing is said of it.
    fn give_twin(&self, chat: &str, body: &str) {
        let o: Value = serde_json::from_str(body).unwrap_or_default();
        let want: HashSet<String> = o["i"].as_array().into_iter().flatten().take(200).filter_map(|i| {
            let a = i.as_array().filter(|a| a.len() == 3)?;
            Some(format!("{}|{}|{}", a[0].as_i64()?, a[1].as_i64()?, a[2].as_str()?))
        }).collect();
        let Some(c) = self.book.chat(chat).filter(|_| !want.is_empty()) else { return };
        for m in c.msgs.iter().filter(|m| m.at > 0 && marks::is_row(&m.text)) {
            if !want.contains(&format!("{}|{}|{}", m.at / 1000, if m.mine { 1 } else { 0 }, row_hash(&archived(m)))) {
                continue;
            }
            let mut g = json!({});
            if let Some(j) = m.text.strip_prefix(crate::media::MARK) {
                // a file rides the cargo road under a fresh key, the road inside the pipe only the seed's devices open
                let f: Value = serde_json::from_str(j).unwrap_or_default();
                let road = match self.media.big(&m.mid) {
                    Some(size) => history::lay_road_from(&crate::media::Source::Parts(self.media, &m.mid, size)),
                    None => self.media.get(&m.mid).and_then(|b| history::lay_road(&b)),
                };
                let Some(road) = road else { continue };
                g["k"] = json!(f["k"].as_str().unwrap_or("doc"));
                g["f"] = json!(history::file_name(&m.mid, &m.text));
                if let Some(n) = f["n"].as_str() {
                    g["n"] = json!(n);
                }
                if let Some(cap) = f["cap"].as_str().filter(|c| !c.is_empty()) {
                    g["t"] = json!(cap);
                }
                if let Some(d) = f["du"].as_f64().filter(|d| *d > 0.0) {
                    g["d"] = json!(d);
                }
                g["road"] = road;
            } else {
                g["t"] = json!(m.text);
            }
            if !m.from.is_empty() {
                g["sr"] = json!(m.from);
            }
            self.mirror_note(Word { c: chat.into(), m: m.mid.clone(), x: format!("{ROW_MARK}{g}"), o: m.mine.then_some(1),
                                    at: Some(m.at as f64 / 1000.0), ..Default::default() });
        }
    }

    /// A ROW THE OTHER DEVICE GAVE BACK (iOS ChatStore.takeTwinRow): laid by its own birth, once -- never over a row of the same
    /// name or the same archive key standing here, never over its grave; a file comes by the cargo road into the store. The
    /// archive already holds the row: it is not written there twice.
    fn take_twin_row(&self, w: &Word, body: &str) {
        let o: Value = serde_json::from_str(body).unwrap_or_default();
        let at = w.at.unwrap_or(0.0);
        let Some(c) = self.book.chat(&w.c) else { return };
        if at <= 0.0 || w.m.is_empty() || w.m.len() > 128 || c.msgs.iter().any(|m| m.mid == w.m) || c.graves.contains(&w.m) {
            return;
        }
        let (own, t) = (w.o == Some(1), o["t"].as_str().unwrap_or(""));
        let mut row = Msg { mid: w.m.clone(), text: t.to_string(), mine: own, at: (at * 1000.0).round() as i64, state: if own { 2 } else { 0 },
                            from: o["sr"].as_str().filter(|s| s.len() <= 128).unwrap_or("").to_string(), ..Default::default() };
        let kind = o["k"].as_str();
        if let Some(k) = kind {
            let f = o["f"].as_str().unwrap_or("");
            if !["img", "vid", "aud", "doc"].contains(&k) || f.is_empty() || f.contains('/') || f.contains('\\') || f.starts_with('.') {
                return;
            }
            let ext: String = f.rsplit('.').next().filter(|e| *e != f).unwrap_or("bin").chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect();
            let mut m = json!({ "k": k, "e": if ext.is_empty() { "bin".to_string() } else { ext } });
            match k {
                "img" | "vid" if !t.is_empty() => m["cap"] = json!(t),
                "aud" => {
                    if let Some(d) = o["d"].as_f64() {
                        m["du"] = json!(d);
                    }
                }
                _ => {}
            }
            if k == "img" || k == "doc" {
                if let Some(n) = o["n"].as_str().or((k == "doc").then_some(f)) {
                    m["n"] = json!(n.chars().take(255).collect::<String>());
                }
            }
            row.text = format!("{}{}", crate::media::MARK, m);
        }
        let s = sig(row.at / 1000, own, &archived(&row));
        if row.text.is_empty() || c.msgs.iter().any(|m| m.at > 0 && sig(m.at / 1000, m.mine, &archived(m)) == s) {
            return;
        }
        if kind.is_some() && !self.media.has(&row.mid) {
            match o.get("road").and_then(|r| history::fetch_road_into(r, self.media, &row.mid)) {
                Some(size) => {
                    let mut m: Value = serde_json::from_str(&row.text[crate::media::MARK.len()..]).unwrap_or_default();
                    m["sz"] = json!(size);
                    row.text = format!("{}{}", crate::media::MARK, m);
                }
                _ => return self.unask_twin(&w.c, at as i64),
            }
        }
        self.book.edit(&w.c, |c| {
            if !c.msgs.iter().any(|m| m.mid == row.mid) && !c.graves.contains(&row.mid) {
                c.msgs.push(row);
                c.msgs.sort_by_key(|m| m.at);
            }
        });
    }

    // ───────────────────────────── landing ─────────────────────────────

    /// A WORD THE OTHER DEVICE MIRRORED HERE (iOS landMirrored): a read mark reads the conversation here too; every other word
    /// walks the one landing road under the name it was born with -- the person's own as mine, a correspondent's as theirs --
    /// and rides no further. A word for a pipe this machine does not know waits for the head the blocks bring.
    pub fn land_mirrored(&self, w: &Word) {
        if let Some(ms) = w.x.strip_prefix(READ_MARK) {
            self.read_by_twin(&w.c, ms.trim().parse().ok());
            return;
        }
        if let Some(body) = w.x.strip_prefix(CARD_MARK) {
            // a card the other device gave birth to: this machine opens the introductions it brings (iOS MontanaCard.takeTwin)
            (crate::card::Card { vault: self.vault }).take_twin(body);
            return;
        }
        if let Some(body) = w.x.strip_prefix(ASK_MARK) {
            self.give_twin(&w.c, body);
            return;
        }
        if let Some(body) = w.x.strip_prefix(ROW_MARK) {
            self.take_twin_row(w, body);
            return;
        }
        if w.m.is_empty() || w.x.is_empty() || w.m.len() > 128 {
            return;
        }
        if self.book.secret(&w.c).is_none() && self.book.chat(&w.c).is_none() {
            self.hold(w);
            return;
        }
        let (qt, qm, lp) = (w.qt.clone().unwrap_or_default(), w.qm.clone().unwrap_or_default(), w.lp.clone().unwrap_or_default());
        let mut text = w.x.clone();
        if text.starts_with(marks::LONG) {
            match self.fetch_long(&text) {
                Ok(t) => text = t,
                Err(_) => return,
            }
        }
        if w.o == Some(1) {
            self.land_own(&w.c, &w.m, &text, &qt, &qm, &lp);
        } else {
            self.land_theirs(&w.c, &w.m, &text, &qt, &qm, &lp);
        }
    }

    /// A correspondent's word another device took: it lands as if this machine had taken it, but answers nobody -- the device
    /// that took it already did. A ring that rode the mirror is stale: the call's own lane reaches every device.
    fn land_theirs(&self, r: &str, mid: &str, text: &str, qt: &str, qm: &str, lp: &str) {
        if self.book.chat(r).is_some_and(|c| c.blocked) || crate::doors::barred(r) {
            if marks::is_row(text) {
                self.book.edit(r, |c| c.bury(mid));
            }
            return;
        }
        meeting::first_done(self.vault, r);
        if text.starts_with(groups::MARK) {
            self.group_heard_by_twin(r, mid, text);
            return;
        }
        if text.starts_with(crate::calls::RING) {
            return;
        }
        self.place_quiet(r, mid, text, qt, qm, lp);
    }

    /// THE PERSON'S OWN WORD FROM ANOTHER DEVICE (iOS landOwn): a letter stands here as mine, «sent» until the correspondent's
    /// receipt moves it, ringing nothing; a group's word is done here as it was done there; a deletion of a letter or of the
    /// whole conversation is applied here and said to nobody; every other word was that device's to the correspondent.
    pub fn land_own(&self, r: &str, mid: &str, text: &str, qt: &str, qm: &str, lp: &str) {
        if text.starts_with(groups::MARK) {
            self.group_own(r, text);
            return;
        }
        if let Some(d) = text.strip_prefix(marks::DELETE) {
            let d = d.strip_prefix("mid:").unwrap_or(d).to_string();
            if !d.is_empty() && self.book.chat(r).is_some() {
                self.book.edit(r, |c| c.bury(&d));
            }
            return;
        }
        if text.starts_with(marks::CONVDEL) {
            let Some(fu) = birth_ms(mid) else { return };
            if self.book.chat(r).is_none_or(|c| fu <= c.funeral) {
                return; // a funeral no newer than the one kept is a repeat
            }
            self.book.edit(r, |c| {
                c.funeral = fu;
                c.msgs.retain(|m| m.at > fu);
                if c.msgs.is_empty() {
                    c.unread = 0;
                    c.hidden = true;
                }
            });
            return;
        }
        if let Some(j) = text.strip_prefix(crate::calls::MISSED) {
            // my call nobody answered, told from another device of mine: its row stands here too, once a call (by its seed)
            let o: Value = serde_json::from_str(j).unwrap_or_default();
            if let Some(seed) = o["s"].as_str().filter(|s| !s.is_empty() && s.len() <= 64) {
                if self.book.chat(r).is_some() && !crate::calls::buried(self.vault, seed) {
                    crate::calls::bury(self.vault, seed);
                    crate::calls::log_row(self.book, r, o["v"].as_bool().unwrap_or(false), false, 0, true);
                }
            }
            return;
        }
        if !marks::is_row(text) {
            return;
        }
        let Some(c) = self.book.chat(r) else { return };
        let at = birth_ms(mid).unwrap_or_else(wire::now_ms);
        if c.msgs.iter().any(|m| m.mid == mid) || c.graves.iter().any(|g| g == mid) || (c.funeral > 0 && at <= c.funeral) {
            return;
        }
        let lp = crate::linkcard::parse(lp).map(|c| c.to_string()).unwrap_or_default();
        let row = Msg { mid: mid.to_string(), text: text.to_string(), mine: true, at, state: 1, qt: qt.chars().take(200).collect(), qm: qm.to_string(), lp, ..Default::default() };
        let mut renamed = false;
        self.book.edit(r, |c| {
            renamed = arc_rename(c, mid, text, true, at);
            if !renamed {
                c.msgs.push(row);
                c.msgs.sort_by_key(|m| m.at);
            }
            c.hidden = false;
        });
        if !renamed {
            self.archive_row(r, true, at, mid, text);
        }
    }

    /// THE OTHER DEVICE READ THIS CONVERSATION (iOS readByTwin): its letters up to the same one are read here too and the count
    /// follows what is left; nothing is said to the correspondent -- the device that read already said it, if the person tells it.
    pub fn read_by_twin(&self, r: &str, ms: Option<i64>) {
        let Some(ms) = ms.filter(|m| *m > 0) else { return };
        if self.book.chat(r).is_none() {
            return;
        }
        let edge = ms + 1;
        self.book.edit(r, |c| {
            let left = c.msgs.iter().filter(|m| !m.mine && m.at > edge && marks::is_row(&m.text)).count() as u32;
            crate::trace_line(&format!("twin_read chat={} upto={ms} unread={} left={left}", r.chars().take(10).collect::<String>(), c.unread));
            c.unread = c.unread.min(left);
            if c.unread == 0 {
                c.marked = false;
            }
        });
    }

    fn hold(&self, w: &Word) {
        let _g = QLOCK.lock().unwrap();
        let mut held: Vec<(Word, i64)> = jlist(self.vault, HELD);
        if held.iter().any(|(x, _)| x.c == w.c && x.m == w.m && x.x == w.x) {
            return;
        }
        held.push((w.clone(), wire::now_ms()));
        let over = held.len().saturating_sub(ROUND);
        held.drain(..over);
        keep(self.vault, HELD, &held);
    }

    /// The words held for pipes unknown here land once their pipe stands; the rest wait two days. True when one landed.
    fn land_held(&self) -> bool {
        if !self.vault.has(HELD) {
            return false;
        }
        let held: Vec<(Word, i64)> = {
            let _g = QLOCK.lock().unwrap();
            let all: Vec<(Word, i64)> = jlist(self.vault, HELD);
            let now = wire::now_ms();
            let (ready, wait): (Vec<_>, Vec<_>) = all.into_iter().filter(|(_, at)| now - at < HOLD_MS)
                .partition(|(w, _)| self.book.secret(&w.c).is_some() || self.book.chat(&w.c).is_some());
            if wait.is_empty() {
                self.vault.delete(HELD);
            } else {
                keep(self.vault, HELD, &wait);
            }
            ready
        };
        for (w, _) in &held {
            self.land_mirrored(w);
        }
        !held.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::book::{mint_mid, Book};
    use crate::vault::Vault;
    use crate::{media, seed};

    fn desk<'a>(v: &'a Vault, b: &'a Book, s: &'a media::Store, p: &'a crate::presence::Presence, words: &str, dev: u8, root: &std::path::Path) -> Desk<'a> {
        let a = history::Archive::new(&root.join(format!("arc{dev}")), history::keys(words).unwrap(), [dev; 16]);
        Desk { vault: v, book: b, twin: seed::twin_of(words).unwrap(), author_key: seed::author_key_of(words), my_name: "Alice".into(), news: Default::default(),
               media: s, faces: s, self_face: vec![], about: Default::default(), read_receipts: true, presence: p, archive: Some(a) }
    }

    #[test]
    fn the_twins_pipe_and_name_are_the_words_own_and_each_machine_is_itself() {
        let hk = [7u8; 32];
        let s = secret(&hk);
        assert_eq!(s, sha(&[b"mt-twin-box\0quest.montana.app\0", &hk]));
        assert_ne!(device_tag(&[1; 32], &[1; 16]), device_tag(&[1; 32], &[2; 16]), "two machines of one person are two names");
        assert!(device_tag(&[1; 32], &[1; 16]).starts_with("windows-") && device_tag(&[1; 32], &[1; 16]).len() == 20);
    }

    #[test]
    fn a_word_of_the_mirror_reads_as_ios_writes_it() {
        let w = Word { c: "ab".into(), m: "t1-X".into(), x: "привет".into(), o: Some(1), at: Some(1760943600.5), q: Some(3), ..Default::default() };
        let j = serde_json::to_string(&w).unwrap();
        assert_eq!(j, r#"{"c":"ab","m":"t1-X","x":"привет","o":1,"at":1760943600.5,"q":3}"#, "empty fields are left out");
        // as iOS JSONEncoder writes [TwinWord]: every optional absent, a field this build does not know
        let ios: Vec<Word> = serde_json::from_str(r#"[{"c":"cd","m":"M","x":"\u200b\u200bTR:1760943600123","o":1,"zz":2},{"m":"n","c":"c","x":"y","lp":"https:\/\/a"}]"#).unwrap();
        assert_eq!((ios[0].o, ios[0].at, ios[1].lp.as_deref()), (Some(1), None, Some("https://a")));
    }

    #[test]
    fn the_mirror_carries_what_stands_in_a_conversation_and_not_what_says_here_now() {
        for t in ["привет", "\u{200B}\u{2064}t1-A", "\u{200B}\u{2063}17", "\u{200B}\u{200B}DL:mid:t1-A", "\u{200B}\u{200B}MD:{}",
                  "\u{2063}\u{2063}🔥", "\u{2063}LB:{}", "\u{200B}\u{200B}MC:{}", "\u{200B}\u{200B}GR:{\"t\":\"say\",\"g\":\"x\"}"] {
            assert!(mirrors(t), "{t:?} rides");
        }
        for t in ["\u{200B}\u{200B}NM:Боб", "\u{200B}\u{200B}AV:", "\u{200B}\u{200B}AP:1", "\u{200B}\u{200B}ED:{}", "\u{200B}\u{200B}RC:{}",
                  "\u{200B}\u{200B}PN:{}", "\u{2063}mtconvdel:", "\u{200B}\u{200B}GR:{\"t\":\"ty\",\"g\":\"x\"}", "\u{200B}\u{200B}KP:{}"] {
            assert!(!mirrors(t), "{t:?} stays");
        }
    }

    #[test]
    fn the_queue_gives_a_name_once_an_hour_and_the_newest_read_mark_stands() {
        let root = std::env::temp_dir().join(format!("montana-twin-q-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let (v, s, p) = (Vault::at(&root.join("v")).unwrap(), media::Store::at(&root.join("m")).unwrap(), crate::presence::Presence::default());
        let b = Book::new(v.clone());
        let d = desk(&v, &b, &s, &p, &words, 1, &root);
        let w = Word { c: "ab".into(), m: "t1-A".into(), x: "привет".into(), ..Default::default() };
        d.mirror_note(w.clone());
        d.mirror_note(w.clone());
        d.mirror_note(Word { c: "ab".into(), m: "r1".into(), x: format!("{READ_MARK}5"), o: Some(1), ..Default::default() });
        d.mirror_note(Word { c: "ab".into(), m: "r2".into(), x: format!("{READ_MARK}9"), o: Some(1), ..Default::default() });
        let q: Vec<Word> = jlist(&v, QUEUE);
        assert_eq!(q.iter().map(|w| w.m.as_str()).collect::<Vec<_>>(), ["t1-A", "r2"]);
        assert_eq!(q.iter().map(|w| w.q.unwrap()).collect::<Vec<_>>(), [1, 2], "each word its place after the last one waiting");
        assert!(jmap(&v, DUE)["lt"].as_i64().unwrap() > wire::now_ms(), "laid within half a minute");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn mirrored_words_land_mine_as_mine_theirs_as_theirs_and_a_read_mark_reads() {
        let root = std::env::temp_dir().join(format!("montana-twin-l-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let (v, s, p) = (Vault::at(&root.join("v")).unwrap(), media::Store::at(&root.join("m")).unwrap(), crate::presence::Presence::default());
        let b = Book::new(v.clone());
        let d = desk(&v, &b, &s, &p, &words, 2, &root);
        let secret = vec![9u8; 32];
        let r = b.establish(&secret).unwrap();
        b.open(&r, "Боб", false);
        let (theirs, mine) = (mint_mid(), mint_mid());
        d.land_mirrored(&Word { c: r.clone(), m: theirs.clone(), x: "от Боба".into(), ..Default::default() });
        d.land_mirrored(&Word { c: r.clone(), m: theirs.clone(), x: "от Боба".into(), ..Default::default() });
        d.land_mirrored(&Word { c: r.clone(), m: mine.clone(), x: "моё с iPhone".into(), o: Some(1), ..Default::default() });
        d.land_mirrored(&Word { c: r.clone(), m: "x1".into(), x: "\u{200B}\u{200B}NM:Чужое".into(), o: Some(1), ..Default::default() });
        let c = b.chat(&r).unwrap();
        assert_eq!(c.msgs.len(), 2, "a repeat is a repeat, a name of my own is applied to nobody");
        assert!(c.msgs.iter().any(|m| m.mid == theirs && !m.mine) && c.msgs.iter().any(|m| m.mid == mine && m.mine && m.state == 1));
        assert_eq!((c.unread, c.name.as_str()), (1, "Боб"));
        assert_eq!(d.news.lock().unwrap().len(), 1, "their letter rings here too, mine never");
        // read on the other device up to Bob's letter: nothing left unread here
        d.land_mirrored(&Word { c: r.clone(), m: "r".into(), x: format!("{READ_MARK}{}", birth_ms(&theirs).unwrap()), o: Some(1), ..Default::default() });
        assert_eq!(b.chat(&r).unwrap().unread, 0);
        // my other device took a letter away for both: gone here too, and it does not come back
        d.land_mirrored(&Word { c: r.clone(), m: mint_mid(), x: format!("{}mid:{mine}", marks::DELETE), o: Some(1), ..Default::default() });
        d.land_mirrored(&Word { c: r.clone(), m: mine.clone(), x: "моё с iPhone".into(), o: Some(1), ..Default::default() });
        assert!(!b.chat(&r).unwrap().msgs.iter().any(|m| m.mid == mine));
        // a word for a pipe this machine does not know waits
        d.land_mirrored(&Word { c: "ffff".into(), m: mint_mid(), x: "позже".into(), ..Default::default() });
        assert_eq!(jlist::<(Word, i64)>(&v, HELD).len(), 1);
        let _ = std::fs::remove_dir_all(&root);
    }

    /// TWO MACHINES OF ONE PERSON, LIVE: Alice's first machine hands her card and takes Bob's first letter; its words and
    /// blocks reach her second machine through the pipe of her words, where Bob's pipe, name and letter stand too; the second
    /// writes to Bob under that pipe and the first holds the letter as mine; Bob writes again, the first takes it and reads it,
    /// and the second has it with nothing left unread; a group the first makes stands on the second as mine, with its letter.
    /// Run with --ignored and MONTANA_LIVE=1: it speaks to Montana's nodes with throw-away identities.
    #[test]
    #[ignore]
    fn two_machines_of_one_person_keep_in_step_through_their_pipe() {
        let root = std::env::temp_dir().join(format!("montana-twin-live-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (wa, wb) = (seed::generate().unwrap(), seed::generate().unwrap());
        let (v1, v2, vb) = (Vault::at(&root.join("a1")).unwrap(), Vault::at(&root.join("a2")).unwrap(), Vault::at(&root.join("b")).unwrap());
        let (b1, b2, bb) = (Book::new(v1.clone()), Book::new(v2.clone()), Book::new(vb.clone()));
        let (s1, s2, sb) = (media::Store::at(&root.join("a1m")).unwrap(), media::Store::at(&root.join("a2m")).unwrap(), media::Store::at(&root.join("bm")).unwrap());
        let p = crate::presence::Presence::default();
        let (a1, a2) = (desk(&v1, &b1, &s1, &p, &wa, 1, &root), desk(&v2, &b2, &s2, &p, &wa, 2, &root));
        let bob = Desk { vault: &vb, book: &bb, twin: seed::twin_of(&wb).unwrap(), author_key: seed::author_key_of(&wb), my_name: "Bob".into(), news: Default::default(),
                         media: &sb, faces: &sb, self_face: vec![], about: Default::default(), read_receipts: true, presence: &p, archive: None };
        let wait = |who: &Desk, ok: &dyn Fn() -> bool| {
            for _ in 0..25 {
                who.fetch_once();
                if ok() {
                    return true;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            false
        };
        assert_ne!(a1.twin_me().unwrap().name, a2.twin_me().unwrap().name, "two machines, two names in the pipe");

        let link = (crate::card::Card { vault: &v1 }).offer_permanent("Alice").unwrap();
        let mut met = meeting::Outcome::Refused;
        for _ in 0..10 {
            met = meeting::meet(&vb, &bb, &link);
            if matches!(met, meeting::Outcome::Opened(_)) { break; }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        let meeting::Outcome::Opened(rb) = met else { panic!("Bob could not meet Alice's card: {met:?}") };
        let first = bob.send(&rb, "Привет, Алиса");
        assert!(wait(&a1, &|| b1.chat(&rb).is_some_and(|c| c.msgs.iter().any(|m| m.mid == first))), "the first machine never took Bob's letter");

        // the first machine's words and blocks: Bob's pipe, name and letter stand on the second
        assert!(a1.lay_mirror(), "the words did not reach the nodes");
        assert!(a1.lay_hist(), "the blocks did not reach the nodes");
        assert!(wait(&a2, &|| b2.chat(&rb).is_some_and(|c| c.msgs.iter().any(|m| m.mid == first && !m.mine))), "the second machine never had Bob's letter");
        assert_eq!(b2.secret(&rb), b1.secret(&rb), "one pipe on both machines");
        assert_eq!(b2.chat(&rb).unwrap().name, "Bob");
        assert_eq!(b2.chat(&rb).unwrap().msgs.iter().filter(|m| m.text == "Привет, Алиса").count(), 1, "the blocks' row and the mirror's word are one letter");

        // the second machine writes to Bob under that pipe: Bob hears it, the first holds it as mine
        let mine = a2.send(&rb, "Пишу со второй машины");
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.mid == mine)), "Bob never heard the second machine");
        assert!(a2.lay_mirror());
        assert!(wait(&a1, &|| b1.chat(&rb).unwrap().msgs.iter().any(|m| m.mid == mine && m.mine)), "the first machine does not hold the second's letter as mine");

        // Bob writes again: the first takes it and reads it; the second has it, and nothing is left unread there
        let second = bob.send(&rb, "Второе письмо Боба");
        assert!(wait(&a1, &|| b1.chat(&rb).unwrap().msgs.iter().any(|m| m.mid == second)), "the first machine never took Bob's second letter");
        a1.mark_read(&rb);
        assert!(a1.lay_mirror());
        assert!(wait(&a2, &|| b2.chat(&rb).unwrap().msgs.iter().any(|m| m.mid == second)), "the second machine never had Bob's second letter");
        assert_eq!(b2.chat(&rb).unwrap().unread, 0, "read on the first machine, read on the second");

        // a group the first machine makes stands on the second as mine, with its letter
        let g = a1.group_create("Семья", std::slice::from_ref(&rb)).unwrap();
        let gm = a1.send(&g, "В группу с первой машины");
        assert!(a1.lay_mirror());
        assert!(wait(&a2, &|| b2.chat(&g).is_some_and(|c| c.msgs.iter().any(|m| m.mid == gm && m.mine))), "the group never stood on the second machine");
        let held = a2.group(g.trim_start_matches("grp:")).unwrap();
        assert!(held.owner.is_empty() && held.members.len() == 1 && held.members[0].pipe == rb, "the second machine holds the group as its owner");

        // a card of the day born on the first machine opens Carol's introduction on the second (iOS twinLiveCards / takeTwin)
        let wc = seed::generate().unwrap();
        let vc = Vault::at(&root.join("c")).unwrap();
        let (bc, sc) = (Book::new(vc.clone()), media::Store::at(&root.join("cm")).unwrap());
        let carol = Desk { vault: &vc, book: &bc, twin: seed::twin_of(&wc).unwrap(), author_key: seed::author_key_of(&wc), my_name: "Carol".into(),
                           news: Default::default(), media: &sc, faces: &sc, self_face: vec![], about: Default::default(), read_receipts: true, presence: &p, archive: None };
        let day = (crate::card::Card { vault: &v1 }).offer_short("Alice").unwrap();
        a1.twin_cards();
        assert!(a1.lay_mirror());
        let inv = crate::meeting::invite(&day).unwrap();
        assert!(wait(&a2, &|| (crate::card::Card { vault: &v2 }).outstanding_invites().contains(&inv)), "the second machine never took the card");
        let mut met = meeting::Outcome::Refused;
        for _ in 0..10 {
            met = meeting::meet(&vc, &bc, &day);
            if matches!(met, meeting::Outcome::Opened(_)) { break; }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        let meeting::Outcome::Opened(rc) = met else { panic!("Carol could not meet the card: {met:?}") };
        carol.send(&rc, "Привет, это Кэрол");
        assert!(wait(&a2, &|| b2.chat(&rc).is_some_and(|c| c.msgs.iter().any(|m| m.text == "Привет, это Кэрол"))),
                "the second machine never opened Carol's introduction by the first machine's card");
        assert_eq!(b2.chat(&rc).unwrap().name, "Carol");

        // a file the first machine holds and the mirror never carried: its blocks reach the second, which asks for the row by
        // its key (TA:), and the first gives it back by its name with the file on the cargo road (TW:)
        let mf = mint_mid();
        let file: Vec<u8> = (0..40_000u32).map(|i| (i % 253) as u8).collect();
        assert!(s1.put(&mf, &file));
        let text = format!("{}{}", media::MARK, json!({ "k": "doc", "e": "txt", "n": "заметка.txt", "sz": file.len() }));
        let at = birth_ms(&mf).unwrap();
        b1.edit(&rb, |c| c.msgs.push(Msg { mid: mf.clone(), text: text.clone(), mine: true, at, state: 2, ..Default::default() }));
        a1.archive_row(&rb, true, at, &mf, &text);
        assert!(a1.lay_hist(), "the blocks did not reach the nodes");
        let asked = || jlist::<Word>(&v2, QUEUE).iter().any(|w| w.c == rb && w.x.starts_with(ASK_MARK));
        assert!(wait(&a2, &asked), "the second machine never asked for the row");
        assert!(a2.lay_mirror());
        let given = || jlist::<Word>(&v1, QUEUE).iter().any(|w| w.m == mf && w.x.starts_with(ROW_MARK));
        assert!(wait(&a1, &given), "the first machine never gave the row");
        assert!(a1.lay_mirror());
        assert!(wait(&a2, &|| s2.get(&mf).as_deref() == Some(file.as_slice())), "the file never came by the cargo road");
        let row = b2.chat(&rb).unwrap().msgs.into_iter().find(|m| m.mid == mf).expect("the row stands on the second machine");
        assert!(row.mine && row.at == at && row.text.contains("заметка.txt"), "mine, at its birth, under its name: {}", row.text);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_row_the_other_device_holds_is_asked_by_its_key_and_given_back_by_its_name() {
        let root = std::env::temp_dir().join(format!("montana-twin-ask-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let (v1, s1, p) = (Vault::at(&root.join("v1")).unwrap(), media::Store::at(&root.join("m1")).unwrap(), crate::presence::Presence::default());
        let (v2, s2) = (Vault::at(&root.join("v2")).unwrap(), media::Store::at(&root.join("m2")).unwrap());
        let (b1, b2) = (Book::new(v1.clone()), Book::new(v2.clone()));
        let (d1, d2) = (desk(&v1, &b1, &s1, &p, &words, 1, &root), desk(&v2, &b2, &s2, &p, &words, 2, &root));
        let secret = vec![5u8; 32];
        let r = b1.establish(&secret).unwrap();
        b1.open(&r, "Боб", false);
        assert_eq!(b2.establish(&secret).as_deref(), Some(r.as_str()));
        b2.open(&r, "Боб", false);
        // the first machine holds three rows -- Bob's, mine, and one the second machine took away
        let (m1, m2, m3) = (mint_mid(), mint_mid(), mint_mid());
        for (mid, mine, text) in [(&m1, false, "первое от Боба"), (&m2, true, "мой ответ"), (&m3, false, "удалённое")] {
            let at = birth_ms(mid).unwrap();
            b1.edit(&r, |c| c.msgs.push(Msg { mid: mid.clone(), text: text.into(), mine, at, state: 2, ..Default::default() }));
            d1.archive_row(&r, mine, at, mid, text);
        }
        b2.edit(&r, |c| {
            c.msgs.push(Msg { mid: m1.clone(), text: "первое от Боба".into(), at: birth_ms(&m1).unwrap(), ..Default::default() });
            c.bury(&m3);
        });
        let a1 = d1.archive.as_ref().unwrap();
        let wt = a1.writer_tag().unwrap();
        let mut blob = vec![];
        for f in a1.folders() {
            for (_, sealed) in a1.export(&f, &wt, 0) {
                blob.extend_from_slice(&(sealed.len() as u32).to_le_bytes());
                blob.extend_from_slice(&sealed);
            }
        }
        // the conversation is held on the second: the blocks lay no row there, and the rows they hold beyond its feed are asked
        assert_eq!(d2.file_blocks(&blob), 0);
        let asks: Vec<Word> = jlist::<Word>(&v2, QUEUE).into_iter().filter(|w| w.x.starts_with(ASK_MARK)).collect();
        assert_eq!(asks.len(), 1, "one word asks");
        let body: Value = serde_json::from_str(&asks[0].x[ASK_MARK.len()..]).unwrap();
        let keys = body["i"].as_array().unwrap();
        assert_eq!(keys.len(), 2, "the two rows it lacks, by their keys");
        assert!(keys.contains(&json!([birth_ms(&m2).unwrap() / 1000, 1, row_hash("мой ответ")])), "a key is the second, the side, the hash");
        d2.file_blocks(&blob);
        assert_eq!(jlist::<Word>(&v2, QUEUE).iter().filter(|w| w.x.starts_with(ASK_MARK)).count(), 1, "a key is asked once");
        // the first gives them back by their names; the second lays its own by its birth and leaves the buried one in its grave
        d1.land_mirrored(&asks[0]);
        let given: Vec<Word> = jlist::<Word>(&v1, QUEUE).into_iter().filter(|w| w.x.starts_with(ROW_MARK)).collect();
        assert_eq!(given.len(), 2, "both rows it holds are given");
        assert!(given.iter().any(|w| w.m == m2 && w.o == Some(1)), "mine goes as mine, under its name");
        for w in &given {
            d2.land_mirrored(w);
        }
        let c = b2.chat(&r).unwrap();
        assert_eq!(c.msgs.len(), 2, "the grave holds");
        let back = c.msgs.iter().find(|m| m.mid == m2).expect("my row came back");
        assert!(back.mine && back.text == "мой ответ" && back.at == birth_ms(&m2).unwrap());
        assert!(c.msgs.windows(2).all(|w| w[0].at <= w[1].at), "laid by its birth");
        for w in &given {
            d2.land_mirrored(w);
        }
        assert_eq!(b2.chat(&r).unwrap().msgs.len(), 2, "given twice, laid once");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_row_no_device_gives_back_lands_by_its_archive_name_and_a_buried_one_stays() {
        let root = std::env::temp_dir().join(format!("montana-twin-wait-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let (v1, s1, p) = (Vault::at(&root.join("v1")).unwrap(), media::Store::at(&root.join("m1")).unwrap(), crate::presence::Presence::default());
        let (v2, s2) = (Vault::at(&root.join("v2")).unwrap(), media::Store::at(&root.join("m2")).unwrap());
        let (b1, b2) = (Book::new(v1.clone()), Book::new(v2.clone()));
        let (d1, d2) = (desk(&v1, &b1, &s1, &p, &words, 1, &root), desk(&v2, &b2, &s2, &p, &words, 2, &root));
        let secret = vec![6u8; 32];
        let r = b1.establish(&secret).unwrap();
        b1.open(&r, "Боб", false);
        b2.establish(&secret).unwrap();
        b2.open(&r, "Боб", false);
        // the other device (an Android phone: blocks, no mirror) holds Bob's letter, mine of ten minutes ago, and one deleted here
        let (m1, m2, m3) = (mint_mid(), mint_mid(), mint_mid());
        let ago = birth_ms(&m2).unwrap() - 600_000;
        for (mid, mine, text, at) in [(&m1, false, "письмо Боба", birth_ms(&m1).unwrap()), (&m2, true, "моё с телефона", ago), (&m3, false, "удалённое здесь", birth_ms(&m3).unwrap())] {
            b1.edit(&r, |c| c.msgs.push(Msg { mid: mid.clone(), text: text.into(), mine, at, state: 2, ..Default::default() }));
            d1.archive_row(&r, mine, at, mid, text);
        }
        b2.edit(&r, |c| {
            c.msgs.push(Msg { mid: m1.clone(), text: "письмо Боба".into(), at: birth_ms(&m1).unwrap() + 1500, ..Default::default() });
            c.bury(&m3);
        });
        let a1 = d1.archive.as_ref().unwrap();
        let wt = a1.writer_tag().unwrap();
        let mut blob = vec![];
        for f in a1.folders() {
            for (_, sealed) in a1.export(&f, &wt, 0) {
                blob.extend_from_slice(&(sealed.len() as u32).to_le_bytes());
                blob.extend_from_slice(&sealed);
            }
        }
        d2.file_blocks(&blob);
        assert!(!d2.land_waiting(), "the answer has its two minutes");
        assert_eq!(b2.chat(&r).unwrap().msgs.len(), 1);
        // no TW: came: past the two minutes the text rows land by their archive names
        let mut w = jmap(&v2, WAITING);
        for v in w.values_mut() {
            v["due"] = json!(0);
        }
        v2.set(WAITING, Value::Object(w).to_string().as_bytes());
        assert!(d2.land_waiting());
        let c = b2.chat(&r).unwrap();
        assert_eq!(c.msgs.len(), 2, "Bob's letter stands once, the deleted one stays in its grave: {:?}", c.msgs.iter().map(|m| &m.text).collect::<Vec<_>>());
        let mine = c.msgs.iter().find(|m| m.text == "моё с телефона").expect("my letter from the phone stands");
        assert!(mine.mine && mine.mid.starts_with("arc:") && mine.at == ago / 1000 * 1000 && mine.state == 2);
        assert!(c.msgs.windows(2).all(|w| w[0].at <= w[1].at), "laid by its birth");
        // the mirror's word that names it later renames it, never doubles it
        b2.edit(&r, |c| { assert!(arc_rename(c, &m2, "моё с телефона", true, ago)); });
        assert!(!d2.land_waiting());
        assert_eq!(b2.chat(&r).unwrap().msgs.iter().filter(|m| m.text == "моё с телефона").count(), 1);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn my_call_nobody_answered_stands_on_my_other_device_once() {
        let root = std::env::temp_dir().join(format!("montana-twin-mc-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let (v, s, p) = (Vault::at(&root.join("v")).unwrap(), media::Store::at(&root.join("m")).unwrap(), crate::presence::Presence::default());
        let b = Book::new(v.clone());
        let d = desk(&v, &b, &s, &p, &words, 2, &root);
        let r = b.establish(&[6u8; 32]).unwrap();
        b.open(&r, "Боб", false);
        let seed = wire::b64(&[7u8; 32]);
        let word = format!("{}{}", crate::calls::MISSED, json!({ "v": false, "s": seed }));
        d.land_own(&r, &mint_mid(), &word, "", "", "");
        d.land_own(&r, &mint_mid(), &word, "", "", "");
        let rows: Vec<Msg> = b.chat(&r).unwrap().msgs.into_iter().filter(|m| m.text.starts_with(crate::calls::LOG)).collect();
        assert_eq!(rows.len(), 1, "one row a call");
        let o: Value = serde_json::from_str(&rows[0].text[crate::calls::LOG.len()..]).unwrap();
        assert_eq!((o["inc"].as_bool(), o["miss"].as_bool(), rows[0].mine), (Some(false), Some(true), true), "my call, not answered");
        assert!(mirrors(&word), "the caller's word rides the mirror");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn the_blocks_of_the_other_device_stand_a_correspondence_this_machine_did_not_hold() {
        let root = std::env::temp_dir().join(format!("montana-twin-h-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let (v1, s1, p) = (Vault::at(&root.join("v1")).unwrap(), media::Store::at(&root.join("m1")).unwrap(), crate::presence::Presence::default());
        let (v2, s2) = (Vault::at(&root.join("v2")).unwrap(), media::Store::at(&root.join("m2")).unwrap());
        let (b1, b2) = (Book::new(v1.clone()), Book::new(v2.clone()));
        let (d1, d2) = (desk(&v1, &b1, &s1, &p, &words, 1, &root), desk(&v2, &b2, &s2, &p, &words, 2, &root));
        let secret = vec![4u8; 32];
        let r = b1.establish(&secret).unwrap();
        b1.open(&r, "Боб", false);
        let (m1, m2) = (mint_mid(), mint_mid());
        d1.archive_row(&r, false, birth_ms(&m1).unwrap(), &m1, "первое от Боба");
        d1.archive_row(&r, true, birth_ms(&m2).unwrap(), &m2, "мой ответ");
        let a1 = d1.archive.as_ref().unwrap();
        let wt = a1.writer_tag().unwrap();
        let mut blob = vec![];
        for f in a1.folders() {
            for (_, sealed) in a1.export(&f, &wt, 0) {
                assert_eq!(a1.peek_conv(&sealed), Some(sha(&[r.as_bytes()])));
                blob.extend_from_slice(&(sealed.len() as u32).to_le_bytes());
                blob.extend_from_slice(&sealed);
            }
        }
        assert!(!blob.is_empty(), "this machine's blocks are exported");
        assert!(a1.export(&a1.folders()[0], &[0, 0, 0, 0], 0).is_empty(), "another writer's are not");
        // the word of Bob's letter came before the blocks: it waits, then lands onto the row the blocks gave back
        d2.land_mirrored(&Word { c: r.clone(), m: m1.clone(), x: "первое от Боба".into(), ..Default::default() });
        assert_eq!(d2.file_blocks(&blob), 1, "the pipe stood from the head");
        let c = b2.chat(&r).unwrap();
        assert_eq!((c.name.as_str(), c.msgs.len()), ("Боб", 2));
        assert!(c.msgs.iter().any(|m| m.mid == m1 && !m.mine), "the row took the letter's wire name");
        assert_eq!(b2.secret(&r), Some(secret));
        assert_eq!(d2.file_blocks(&blob), 0, "twice is once");
        assert_eq!(b2.chat(&r).unwrap().msgs.len(), 2);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_forged_block_or_another_persons_stands_nothing() {
        let root = std::env::temp_dir().join(format!("montana-twin-f-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (words, other) = (seed::generate().unwrap(), seed::generate().unwrap());
        let (v1, s1, p) = (Vault::at(&root.join("v1")).unwrap(), media::Store::at(&root.join("m1")).unwrap(), crate::presence::Presence::default());
        let (v2, s2) = (Vault::at(&root.join("v2")).unwrap(), media::Store::at(&root.join("m2")).unwrap());
        let (v3, s3) = (Vault::at(&root.join("v3")).unwrap(), media::Store::at(&root.join("m3")).unwrap());
        let (b1, b2, b3) = (Book::new(v1.clone()), Book::new(v2.clone()), Book::new(v3.clone()));
        let (d1, d2, d3) = (desk(&v1, &b1, &s1, &p, &words, 1, &root), desk(&v2, &b2, &s2, &p, &words, 2, &root), desk(&v3, &b3, &s3, &p, &other, 3, &root));
        let r = b1.establish(&[6u8; 32]).unwrap();
        b1.open(&r, "Боб", false);
        let m = mint_mid();
        d1.archive_row(&r, false, birth_ms(&m).unwrap(), &m, "первое от Боба");
        let a1 = d1.archive.as_ref().unwrap();
        let wt = a1.writer_tag().unwrap();
        let sealed: Vec<Vec<u8>> = a1.folders().iter().flat_map(|f| a1.export(f, &wt, 0)).map(|(_, s)| s).collect();
        assert!(!sealed.is_empty());
        let file = |blocks: &[Vec<u8>]| blocks.iter().flat_map(|s| [(s.len() as u32).to_le_bytes().to_vec(), s.clone()].concat()).collect::<Vec<u8>>();
        // another person's machine: these blocks are sealed under words it does not hold
        assert_eq!(d3.file_blocks(&file(&sealed)), 0, "another person's blocks stand nothing");
        assert!(b3.chat(&r).is_none() && b3.secret(&r).is_none());
        // the same words, every block changed by one bit -- at its head, in its middle, at its tail
        for at in [0usize, 1, 2] {
            let forged: Vec<Vec<u8>> = sealed.iter().map(|s| { let mut f = s.clone(); let i = [0, f.len() / 2, f.len() - 1][at]; f[i] ^= 1; f }).collect();
            assert_eq!(d2.file_blocks(&file(&forged)), 0, "a forged block stands nothing ({at})");
            assert!(b2.chat(&r).is_none() && b2.secret(&r).is_none(), "nor its pipe ({at})");
        }
        // a file whose last length runs past its end is read up to there; a length of zero ends it
        let mut cut = file(&sealed);
        cut.truncate(cut.len() - 1);
        let mut zero = 0u32.to_le_bytes().to_vec();
        zero.extend(file(&sealed));
        assert_eq!((d2.file_blocks(&zero), b2.chat(&r).is_none()), (0, true), "nothing past a zero length");
        // a file cut inside its last block: the blocks before the cut stand what they hold (here the head: the pipe, no row yet)
        assert_eq!(d2.file_blocks(&cut), 1);
        assert_eq!(b2.chat(&r).map(|c| c.msgs.len()), Some(0), "the cut block's row is not laid in part");
        // the whole blocks then: the conversation stands once, and a row its feed lacks is asked of the other device, never laid
        // into a held feed (iOS restoreFromArchive: the feed is the truth)
        assert_eq!(d2.file_blocks(&file(&sealed)), 0, "no second conversation");
        assert_eq!(b2.all().iter().filter(|c| c.reference == r).count(), 1);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn saved_messages_rides_the_blocks_alone_and_a_held_feed_is_asked_not_overwritten() {
        use crate::book::SAVED;
        let root = std::env::temp_dir().join(format!("montana-twin-s-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let p = crate::presence::Presence::default();
        let (v1, s1) = (Vault::at(&root.join("v1")).unwrap(), media::Store::at(&root.join("m1")).unwrap());
        let (v2, s2) = (Vault::at(&root.join("v2")).unwrap(), media::Store::at(&root.join("m2")).unwrap());
        let (v3, s3) = (Vault::at(&root.join("v3")).unwrap(), media::Store::at(&root.join("m3")).unwrap());
        let (b1, b2, b3) = (Book::new(v1.clone()), Book::new(v2.clone()), Book::new(v3.clone()));
        let (d1, d2, d3) = (desk(&v1, &b1, &s1, &p, &words, 1, &root), desk(&v2, &b2, &s2, &p, &words, 2, &root), desk(&v3, &b3, &s3, &p, &words, 3, &root));
        // device 1 writes to itself: the row stands «sent» at birth, nothing waits for a road, nothing is mirrored, no coin
        let mid = d1.draft(SAVED, "заметка себе", "", "");
        assert!(d1.post(SAVED, &mid));
        let row = b1.chat(SAVED).unwrap().msgs.into_iter().find(|m| m.mid == mid).unwrap();
        assert_eq!((row.mine, row.state), (true, 1));
        assert!(b1.chat(SAVED).unwrap().pending.is_empty() && jlist::<Word>(&v1, QUEUE).is_empty(), "no word, no mirror");
        // its folder: the key's own label, the head «a:» once, then the row (iOS writeHeadIn form «a»)
        let a1 = d1.archive.as_ref().unwrap();
        let wt = a1.writer_tag().unwrap();
        let mut blob = vec![];
        let mut contents = vec![];
        for f in a1.folders() {
            for (_, sealed) in a1.export(&f, &wt, 0) {
                assert_eq!(a1.peek_conv(&sealed), Some(sha(&[SAVED.as_bytes()])), "the conversation is the key's SHA-256, the same for all");
                contents.extend(a1.open_block(&sealed).into_iter().map(|i| (i.dir, String::from_utf8(i.content).unwrap())));
                blob.extend_from_slice(&(sealed.len() as u32).to_le_bytes());
                blob.extend_from_slice(&sealed);
            }
        }
        assert_eq!(contents, [(2, "a:Saved Messages".to_string()), (0, "заметка себе".to_string())]);
        // device 2 holds no Saved Messages: the blocks stand it, its row by the archive's name; twice is once
        d2.file_blocks(&blob);
        let c2 = b2.chat(SAVED).expect("the room stood from the blocks");
        assert_eq!(c2.msgs.iter().map(|m| (m.text.as_str(), m.mine)).collect::<Vec<_>>(), [("заметка себе", true)]);
        d2.file_blocks(&blob);
        assert_eq!(b2.chat(SAVED).unwrap().msgs.len(), 1);
        // device 3 holds its own Saved Messages: the feed is the truth -- no row laid by the blocks, the row asked of the twins
        let own = d3.draft(SAVED, "своя заметка", "", "");
        d3.file_blocks(&blob);
        assert_eq!(b3.chat(SAVED).unwrap().msgs.len(), 1, "a held feed is not overwritten by blocks");
        assert_eq!(jmap(&v3, WAITING).len(), 1, "the missing row is asked by its archive key");
        // no device gave it back within two minutes: it lands by its archive name (the port's way, iOS waits for a TW:)
        let mut w = jmap(&v3, WAITING);
        for (_, x) in w.iter_mut() {
            x["due"] = json!(0);
        }
        v3.set(WAITING, Value::Object(w).to_string().as_bytes());
        assert!(d3.land_waiting());
        let texts: Vec<String> = b3.chat(SAVED).unwrap().msgs.into_iter().map(|m| m.text).collect();
        assert_eq!(texts.len(), 2);
        assert!(texts.contains(&"заметка себе".to_string()) && b3.chat(SAVED).unwrap().msgs.iter().any(|m| m.mid == own));
        let _ = std::fs::remove_dir_all(&root);
    }
}
