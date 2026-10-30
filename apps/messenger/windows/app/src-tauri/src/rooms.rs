//! A GROUP'S LIVE ROOM (iOS MTGroupRoom; the author's words 07.10.2026 00:2x MSK: «audio and video calls in a group with up to
//! 13 connected at once ... and streaming»): a voice or video chat of up to thirteen people, and a stream where its owner speaks
//! and the rest watch. No server holds a room: a room of N is N-1 calls of two. The room is told to the group by the group's own
//! word «room» -- opened, invited, came in, a key handed, still here, went out, closed -- and the room's key rides inside those
//! end-to-end words alone. Every pair speaks its own lane, named by the room and the two seats and sealed by a key the two derive
//! from the room's key; the content of every pair word (the description, the candidates) is sealed to its receiver's own room
//! key (ML-KEM-768, then AES-256-GCM): a person of the group who is not one of the two reads none of it. The later of two to come
//! in offers. Here live the rooms, their words and the lanes; the window holds the pairs (WebRTC) and their beat.

use crate::groups::{self, Group};
use crate::post::Desk;
use crate::wire::{self, b64, body_key, conv_w, hex, sha, sub_id, unb64};
use crate::{abi, aesgcm, crypto, doors};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

/// [I-14] The most people in one room at once (the author's word 07.10.2026 00:2x MSK: «up to 13 connected at once»).
pub const CAPACITY: usize = 13;
/// A room no word renewed for half an hour is gone from the bars: its people may have left without a word.
const STALE_S: f64 = 1800.0;
/// How often a living room's first one says it lives.
const HERE_EVERY_S: f64 = 600.0;
/// A pair word older than this is a corpse (the node keeps a lane's word sixty seconds).
const SIGNAL_LIFE_S: f64 = 60.0;
/// [I-15] One person's invitations show once in two minutes, however many rooms they open.
const ASKER_PAUSE_S: f64 = 120.0;
/// The rooms this machine knows and their people's keys (iOS mt.rooms.seen): the vault, this device's own.
const BOOK: &str = "roomsSeen";

/// A room's event on the group's road (iOS MTRoomEvent), short keys; a key a reader does not know is skipped.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Event {
    /// the room's id: 32 lowercase hex
    pub r: String,
    /// open, ask, in, key, here, out, end
    pub e: String,
    /// call or live
    pub m: String,
    /// the room's key, base64 of 32 bytes
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub k: Option<String>,
    /// 1: the speaker comes with a camera (open: a video chat)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub v: Option<i64>,
    /// the moment, seconds
    pub at: f64,
    /// the seat that holds the room's control
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub o: Option<String>,
    /// the seats an invitation (or a handed key) is for
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to: Option<Vec<String>>,
    /// the seat the event is about when it is not the speaker's own
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub w: Option<String>,
    /// the speaker's own room key (ML-KEM-768 public, base64)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    /// the seats in the room (here)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub p: Option<Vec<String>>,
    /// the speaker's own moment of coming in, when the word is said later than it
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub s: Option<f64>,
}

/// A group's room as this machine knows it from the group's words (iOS MTRoomSeen).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Seen {
    pub id: String,
    pub kind: String,
    /// base64 of the room's 32-byte key
    pub key: String,
    pub owner: String,
    pub video: bool,
    /// every seat in the room and the moment it came in
    pub people: BTreeMap<String, f64>,
    /// the room's first moment known here: of two rooms of one group the earlier stands
    pub since: f64,
    pub at: f64,
    #[serde(default)]
    pub asked_by: Option<String>,
    /// every seat's room key (base64), as its own word on the group's road named it
    #[serde(default)]
    pub keys: BTreeMap<String, String>,
}

/// One pair word on the pair's lane (iOS MTRoomSignal): its content sealed to the receiver's room key.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Signal {
    pub r: String,
    pub f: String,
    pub t: String,
    /// offer, answer, ice, bye
    pub c: String,
    pub g: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ct: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub x: Option<String>,
    pub at: f64,
}

/// The content of a pair word (iOS MTRoomInner).
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Inner {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sdp: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ice: Option<Vec<Ice>>,
}

/// A candidate as a pair word carries it (iOS MTRoomICE).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Ice {
    pub s: String,
    pub i: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m: Option<String>,
}

/// The room this machine is in (iOS MTRoomLive), less its pairs: the window holds those.
#[derive(Clone, Debug)]
pub struct Live {
    pub group: String,
    pub chat: String,
    pub id: String,
    pub kind: String,
    pub key: Vec<u8>,
    pub me: String,
    pub since: f64,
    pub owner: String,
    pub video: bool,
    pub people: BTreeMap<String, f64>,
    /// every other seat's room key, from its own word on the group's road
    pub keys: BTreeMap<String, Vec<u8>>,
    pub kem_pub: Vec<u8>,
    kem_sec: Vec<u8>,
    /// the comings in already handed my key (seat and moment)
    keyed: HashSet<String>,
    reannounced: HashSet<String>,
    /// the seats invited that are not in yet, and when
    pub ringing: BTreeMap<String, f64>,
    said_here: f64,
    was_alone: bool,
    /// the seats whose pair with this machine stands, and the moment each pair was born for (the window says so)
    pub linked: BTreeMap<String, f64>,
    /// my twin reference: the lanes' envelopes name it
    twin: String,
}

impl Live {
    /// Who speaks and shows: everyone in a chat; in a stream its owner alone.
    pub fn stage(&self, seat: &str) -> bool {
        self.kind == "call" || seat == self.owner
    }
}

/// A ROOM MINTED BEFORE IT OPENS (iOS MTRoomMint; a call of two growing into one): its id, its key, this machine's room key
/// and its moment -- the peer is told all of it on the call's own road.
#[derive(Clone)]
struct Mint {
    id: String,
    key: Vec<u8>,
    kp: Vec<u8>,
    ks: Vec<u8>,
    at: f64,
}

fn mint() -> Option<Mint> {
    let (kp, ks) = keypair()?;
    Some(Mint { id: hex(&crypto::random(16)?), key: crypto::random(32)?, kp, ks, at: now_s() })
}

/// A call of two growing into a room (iOS grow): the group born for it, the room minted, the peer's seat and the others'.
struct Grow {
    chat: String,
    mint: Mint,
    peer: String,
    others: Vec<String>,
    video: bool,
}

#[derive(Default)]
struct State {
    lifted: bool,
    seen: BTreeMap<String, Seen>,
    live: Option<Live>,
    asked: HashSet<String>,
    rang_by: HashMap<String, f64>,
    /// a way in that waits for the room's word (a banner tapped before it landed): chat, room, when
    pending: Option<(String, String, f64)>,
    /// my room key and moment already given on a call's road for a room it moves into (iOS pendingMint): room, key pair, moment
    pending_mint: Option<(String, Vec<u8>, Vec<u8>, f64)>,
    grow: Option<Grow>,
}

/// The rooms of each person on this machine, by the person's twin reference (a check holds two people in one process).
static STATE: Mutex<Option<HashMap<String, State>>> = Mutex::new(None);

/// The window's ear: what changed in the rooms ("montana://room"), a pair word ("montana://room-signal"), a line to say.
type Notify = Box<dyn Fn(&str, Value) + Send + Sync>;
static NOTIFY: OnceLock<Notify> = OnceLock::new();

/// Whether a room stands on this machine (a move between seats waits for it: iOS MTSeats.refusedForCall).
pub fn standing() -> bool {
    STATE.lock().unwrap().as_ref().is_some_and(|all| all.values().any(|s| s.live.is_some()))
}

pub fn on_change(f: Notify) {
    let _ = NOTIFY.set(f);
}

fn tell_window(name: &str, v: Value) {
    if let Some(f) = NOTIFY.get() {
        f(name, v);
    }
}

/// The pair words a check's people heard, by person.
#[cfg(test)]
pub static CAUGHT: Mutex<Vec<(String, Value)>> = Mutex::new(Vec::new());

fn tell_signal(_twin: &str, v: Value) {
    #[cfg(test)]
    CAUGHT.lock().unwrap().push((_twin.to_string(), v.clone()));
    tell_window("montana://room-signal", v);
}

/// A line the room says (iOS say), as its English key; the window says it in its language.
fn say(key: &str) {
    tell_window("montana://room-say", json!({ "say": key }));
}

/// The window's language (the room's names: «Вы», «Участник»; the invitation's banner).
static RU: AtomicBool = AtomicBool::new(true);

pub fn set_ru(on: bool) {
    RU.store(on, Ordering::SeqCst);
}

fn ru_now() -> bool {
    RU.load(Ordering::SeqCst)
}

fn now_s() -> f64 {
    wire::now_ms() as f64 / 1000.0
}

pub fn is_room_id(s: &str) -> bool {
    s.len() == 32 && s.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
}

pub fn is_seat(s: &str) -> bool {
    !s.is_empty() && s.chars().count() <= 128 && s.chars().all(|c| c.is_alphanumeric())
}

/// The pair's lane, named by the room and the two seats, the lower first -- both machines name it alike.
pub fn lane_name(id: &str, a: &str, b: &str) -> String {
    format!("room:{id}:{}:{}", a.min(b), a.max(b))
}

/// The pair's key: the room's key and the two seats.
pub fn lane_key(key: &[u8], a: &str, b: &str) -> [u8; 32] {
    sha(&[b"mt-room-pair", key, a.min(b).as_bytes(), &[0], a.max(b).as_bytes()])
}

/// The later of two to come in: the moment first, the seat for a tie -- the one order every phone computes alike.
pub fn later(a: (f64, &str), b: (f64, &str)) -> bool {
    if a.0 != b.0 { a.0 > b.0 } else { a.1 > b.1 }
}

/// The first in the room: it says what a seat that vanished cannot say, and holds the control when the owner goes.
pub fn first_in(people: &BTreeMap<String, f64>) -> String {
    people.iter().fold(None::<(&String, f64)>, |best, (s, at)| match best {
        Some((bs, bat)) if !later((bat, bs), (*at, s)) => Some((bs, bat)),
        _ => Some((s, *at)),
    }).map(|(s, _)| s.clone()).unwrap_or_default()
}

/// What a pair word's content is bound to: the room, from whom, to whom, its kind and the pair's generation.
pub fn bind(id: &str, from: &str, to: &str, c: &str, g: i64) -> String {
    format!("{id}/{from}/{to}/{c}/{g}")
}

/// A PAIR WORD IS SEALED TO ITS RECEIVER (iOS MTRoomSeal): the shared secret of an encapsulation to the receiver's room key,
/// bound to the room, the two seats, the word's kind and generation, keys AES-256-GCM.
pub fn seal_word(plain: &[u8], to: &[u8], bind: &str) -> Option<(Vec<u8>, Vec<u8>)> {
    if to.len() != abi::MT_MLKEM_PUBKEY_SIZE {
        return None;
    }
    let (ct, ss) = crypto::mlkem_encaps(to)?;
    let boxed = aesgcm::seal(&sha(&[b"mt-room-word", &ss, bind.as_bytes()]), plain)?;
    Some((ct, boxed))
}

pub fn open_word(boxed: &[u8], ct: &[u8], sec: &[u8], bind: &str) -> Option<Vec<u8>> {
    if ct.len() != abi::MT_MLKEM_CT_SIZE || sec.len() != abi::MT_MLKEM_SECKEY_SIZE {
        return None;
    }
    let ss = crypto::mlkem_decaps(sec, ct)?;
    aesgcm::open(&sha(&[b"mt-room-word", &ss, bind.as_bytes()]), boxed)
}

fn keypair() -> Option<(Vec<u8>, Vec<u8>)> {
    crypto::mlkem_keypair(&crypto::random(abi::MT_MLKEM_SEED_LEN)?)
}

fn fresh(s: &Seen) -> bool {
    now_s() - s.at < STALE_S
}

/// THE MOMENT A LATE WORD OF MINE IS SAID AT (iOS spoken): inside its life -- at my own moment while it is young, half its
/// life ago once it is older -- and my moment rides in «s».
fn spoken(since: f64) -> f64 {
    since.max(now_s() - STALE_S / 2.0)
}

fn with<T>(d: &Desk, f: impl FnOnce(&mut State) -> T) -> T {
    let mut g = STATE.lock().unwrap();
    let st = g.get_or_insert_with(HashMap::new).entry(d.twin.clone()).or_default();
    if !st.lifted {
        st.lifted = true;
        let book: BTreeMap<String, Seen> = d.vault.get(BOOK).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        st.seen = book.into_iter().filter(|(_, s)| fresh(s) && !s.people.is_empty()).collect();
    }
    f(st)
}

/// The name a seat is shown by in its group's room: «You» for this machine's own.
fn name_of(d: &Desk, g: &Group, seat: &str, ru: bool) -> String {
    if seat == g.me {
        return if ru { "Вы".into() } else { "You".into() };
    }
    let n = d.seat_name(g, seat);
    if n.is_empty() { if ru { "Участник".into() } else { "Member".into() } } else { n }
}

/// Every group's room as the bars show it, and the room in hand, for the window.
fn publish(d: &Desk, st: &State) {
    if let Ok(b) = serde_json::to_vec(&st.seen) {
        d.vault.set(BOOK, &b);
    }
    tell_window("montana://room", snapshot(d, st));
}

fn snapshot(d: &Desk, st: &State) -> Value {
    let ru = ru_now();
    let mut rooms = serde_json::Map::new();
    for (gid, s) in st.seen.iter().filter(|(_, s)| !s.people.is_empty() && fresh(s)) {
        let Some(g) = d.group(gid) else { continue };
        let asker = s.asked_by.as_ref().map(|a| name_of(d, &g, a, ru));
        rooms.insert(groups::chat_of(gid), json!({ "kind": s.kind, "video": s.video, "count": s.people.len(), "asker": asker,
                                                  "mine": st.live.as_ref().is_some_and(|r| r.id == s.id), "id": s.id }));
    }
    let live = st.live.as_ref().and_then(|r| {
        let g = d.group(&r.group)?;
        let mut order: Vec<(&String, &f64)> = r.people.iter().collect();
        order.sort_by(|a, b| if later((*b.1, b.0), (*a.1, a.0)) { std::cmp::Ordering::Less } else { std::cmp::Ordering::Greater });
        let people: Vec<Value> = order.iter().map(|(s, at)| json!({ "seat": s, "at": at, "name": name_of(d, &g, s, ru), "key": r.keys.contains_key(*s),
                                                                   "owner": **s == r.owner, "me": **s == r.me })).collect();
        let now = now_s();
        let ringing: Vec<Value> = r.ringing.iter().filter(|(s, at)| !r.people.contains_key(*s) && now - **at < 120.0)
            .map(|(s, _)| json!({ "seat": s, "name": name_of(d, &g, s, ru) })).collect();
        Some(json!({ "chat": r.chat, "id": r.id, "kind": r.kind, "video": r.video, "me": r.me, "owner": r.owner, "title": g.title,
                     "people": people, "ringing": ringing, "since": r.since }))
    });
    json!({ "rooms": rooms, "live": live })
}

/// The room's state for a window that opens now.
pub fn state_now(d: &Desk) -> Value {
    with(d, |st| snapshot(d, st))
}

fn tell(d: &Desk, e: &Event, gid: &str, ring: bool) {
    let Ok(text) = serde_json::to_string(e) else { return };
    // an invitation goes to the seats it names alone and rings there; a key handed to one who came in goes to them alone, silent
    let targeted = e.e == "ask" || e.e == "key";
    let to = if targeted { e.to.clone() } else { None };
    d.room_word(gid, &text, to.as_deref(), e.e == "ask" && ring);
}

/// The rooms a person may open in a chat (iOS kinds): a group -- a chat and a stream; a channel -- a stream, by its voices alone.
pub fn kinds(g: &Group) -> Vec<&'static str> {
    if g.left || g.removed {
        return vec![];
    }
    if g.kind == "g" {
        return vec!["call", "live"];
    }
    if g.owner.is_empty() || (g.admins.contains(&g.me) && groups::admin_can(g, &g.me, "po")) { vec!["live"] } else { vec![] }
}

/// A ROOM'S WORD FROM THE GROUP (iOS heard): its seat is already proven by the group's road.
pub fn heard(d: &Desk, text: &str, gid: &str, seat: &str, name: &str) {
    let Ok(e) = serde_json::from_str::<Event>(text) else { return };
    if !is_room_id(&e.r) || !(e.m == "call" || e.m == "live") {
        return;
    }
    let Some(g) = d.group(gid) else { return };
    let chat = groups::chat_of(gid);
    let now = now_s();
    if now - e.at >= STALE_S {
        return;
    }
    let came = e.s.map(|s| s.min(e.at)).unwrap_or(e.at);
    let key = e.k.as_deref().and_then(unb64).filter(|k| k.len() == 32);
    with(d, |st| {
        let mut moved = false;
        let (mut s, known, first_sight) = match st.seen.get(gid) {
            Some(cur) if cur.id == e.r => (cur.clone(), true, false),
            _ => {
                if e.e == "out" || e.e == "end" {
                    return;
                }
                let Some(key) = key.as_ref() else { return };
                let born = Seen { id: e.r.clone(), kind: e.m.clone(), key: b64(key), owner: e.o.clone().unwrap_or_else(|| seat.to_string()),
                                  video: e.v == Some(1), people: BTreeMap::new(), since: came, at: e.at, asked_by: None, keys: BTreeMap::new() };
                if let Some(cur) = st.seen.get(gid).filter(|c| !c.people.is_empty() && fresh(c)).cloned() {
                    // TWO ROOMS OF ONE GROUP (opened at once): the earlier stands -- by its moment, by its id for a tie -- on every phone
                    let cur_first = if cur.since != born.since { cur.since < born.since } else { cur.id < born.id };
                    if cur_first {
                        if let Some(r) = st.live.as_mut().filter(|r| r.id == cur.id && !r.reannounced.contains(&e.r)) {
                            r.reannounced.insert(e.r.clone());
                            let again = Event { r: r.id.clone(), e: "in".into(), m: r.kind.clone(), k: Some(b64(&r.key)), at: spoken(r.since),
                                                o: Some(r.owner.clone()), q: Some(b64(&r.kem_pub)), s: Some(r.since), ..Default::default() };
                            tell(d, &again, gid, false);
                        }
                        return;
                    }
                    moved = st.live.as_ref().is_some_and(|r| r.id == cur.id);
                }
                (born, false, true)
            }
        };
        let who = e.w.clone().unwrap_or_else(|| seat.to_string());
        // the speaker's room key, from its own word on the group's road: every pair word to it is sealed to this key
        if e.e != "out" && e.e != "end" {
            if let Some(q) = e.q.as_deref().filter(|q| unb64(q).is_some_and(|b| b.len() == abi::MT_MLKEM_PUBKEY_SIZE)) {
                s.keys.insert(seat.to_string(), q.to_string());
            }
        }
        let mut closed = false;
        match e.e.as_str() {
            "open" => {
                // a room is opened once, by its owner
                if known && seat != s.owner {
                    return;
                }
                s.people.insert(seat.to_string(), e.at);
                s.owner = e.o.clone().unwrap_or_else(|| seat.to_string());
                s.video = e.v == Some(1);
            }
            "ask" => {
                s.people.entry(seat.to_string()).or_insert(e.at);
                let once = format!("{}/{seat}", e.r);
                let quiet = now - st.rang_by.get(&format!("{gid}/{seat}")).copied().unwrap_or(0.0) < ASKER_PAUSE_S;
                let for_me = e.to.as_ref().is_some_and(|t| t.contains(&g.me));
                let in_it = st.live.as_ref().is_some_and(|r| r.id == s.id);
                if for_me && !in_it && now - e.at < 120.0 && !st.asked.contains(&once) && !quiet {
                    st.asked.insert(once);
                    st.rang_by.insert(format!("{gid}/{seat}"), now);
                    s.asked_by = Some(seat.to_string());
                    let ru = ru_now();
                    let asker = if name.trim().is_empty() { name_of(d, &g, seat, ru) } else { name.trim().to_string() };
                    let say = |asker: &str| match (s.kind.as_str(), e.v == Some(1), ru) {
                        ("live", _, true) => format!("{asker} приглашает вас на трансляцию"),
                        ("live", _, false) => format!("{asker} invites you to a live stream"),
                        (_, true, true) => format!("{asker} приглашает вас в видеочат"),
                        (_, true, false) => format!("{asker} invites you to a video chat"),
                        (_, false, true) => format!("{asker} приглашает вас в голосовой чат"),
                        (_, false, false) => format!("{asker} invites you to a voice chat"),
                    };
                    // the asker is named only while the person's Show sender stands (iOS 2304 MTGroupRoom 543-545)
                    let anon = say(if ru { "Собеседник" } else { "Correspondent" });
                    d.news.lock().unwrap().push(crate::post::News { chat: chat.clone(), text: say(&asker), anon: Some(anon) });
                }
            }
            "in" => {
                s.people.insert(who.clone(), came);
            }
            "key" => {
                s.people.entry(seat.to_string()).or_insert(came);
            }
            "here" => {
                s.people.entry(seat.to_string()).or_insert(e.at);
                for x in e.p.iter().flatten().take(CAPACITY).filter(|x| is_seat(x)) {
                    s.people.entry(x.clone()).or_insert(e.at);
                }
            }
            "out" => {
                s.people.remove(&who);
            }
            "end" => {
                if !(seat == s.owner || s.people.keys().all(|k| k == seat)) {
                    return;
                }
                s.people.clear();
                closed = true;
            }
            _ => return,
        }
        if !s.people.contains_key(&s.owner) && !s.people.is_empty() {
            s.owner = first_in(&s.people);
        }
        s.at = s.at.max(e.at);
        if s.people.is_empty() { st.seen.remove(gid); } else { st.seen.insert(gid.to_string(), s.clone()); }
        // THE ROOM IN THE GROUP'S FEED: begun, once; ended, with how long it lived
        if first_sight && !s.people.is_empty() {
            d.room_event(gid, "call", &s.owner, &s.kind, s.video, &s.id, 0);
        }
        if closed && known {
            d.room_event(gid, "ended", seat, &s.kind, s.video, &s.id, (now - s.since).max(0.0) as i64);
        }
        if moved {
            leave_in(d, st, "the earlier room stands", true);
            let _ = join_in(d, st, &chat, s.video);
        } else if st.live.as_ref().is_some_and(|r| r.id == s.id) {
            follow(d, st, &s, &e.e, &who, seat);
        }
        publish(d, st);
        take_pending(d, st, gid);
    });
}

/// The room this machine is in learns what the group said of it (iOS follow).
fn follow(d: &Desk, st: &mut State, s: &Seen, event: &str, seat: &str, speaker: &str) {
    let me = {
        let Some(r) = st.live.as_mut() else { return };
        r.people = s.people.clone();
        // a seat with a standing pair of ours is in the room whatever another view says: the living line is the witness
        for (k, m) in r.linked.clone() {
            r.people.entry(k).or_insert(m);
        }
        for (k, v) in &s.keys {
            if *k != r.me {
                if let Some(b) = unb64(v) {
                    r.keys.insert(k.clone(), b);
                }
            }
        }
        let me = r.me.clone();
        let since = r.since;
        r.people.entry(me.clone()).or_insert(since);
        // one invited who came in is no longer «calling», even after it goes out (iOS: the ringing list is filtered for good)
        let inside: Vec<String> = r.people.keys().cloned().collect();
        r.ringing.retain(|s, _| !inside.contains(s));
        if !r.people.contains_key(&r.owner) {
            r.owner = first_in(&r.people);
        }
        if event == "in" && seat != me {
            // ONE WHO CAME IN GETS MY KEY FROM ME: a person added while the room lived never heard the words that named the keys of
            // those already in -- each of us hands ours, to them alone
            if let Some(m) = r.people.get(seat).copied() {
                let mark = format!("{seat}/{m}");
                if !r.keyed.contains(&mark) {
                    r.keyed.insert(mark);
                    let e = Event { r: r.id.clone(), e: "key".into(), m: r.kind.clone(), k: Some(b64(&r.key)), at: spoken(r.since),
                                    o: Some(r.owner.clone()), to: Some(vec![seat.to_string()]), q: Some(b64(&r.kem_pub)), s: Some(r.since),
                                    ..Default::default() };
                    let gid = r.group.clone();
                    tell(d, &e, &gid, false);
                }
            }
        }
        if event == "out" && seat != me {
            if speaker != seat {
                // another's word about a seat is believed only while no pair of ours stands with it
                if let Some(m) = r.linked.get(seat).copied() {
                    r.people.insert(seat.to_string(), m);
                }
            } else {
                // a seat takes itself out: its standing pair is no witness against its own word
                r.linked.remove(seat);
                r.people.remove(seat);
            }
        }
        me
    };
    if event == "end" {
        leave_in(d, st, "ended", false);
        say("The call has ended");
        return;
    }
    // THE ROOM GREW PAST ITS MEASURE (two came in at once): the latest by the one order leave, every phone alike
    let full = st.live.as_ref().is_some_and(|r| {
        let mut order: Vec<(&String, &f64)> = r.people.iter().collect();
        order.sort_by(|a, b| if later((*b.1, b.0), (*a.1, a.0)) { std::cmp::Ordering::Less } else { std::cmp::Ordering::Greater });
        order.iter().position(|(s, _)| **s == me).is_some_and(|i| i >= CAPACITY)
    });
    if full {
        leave_in(d, st, "full", true);
        say("This call is full");
        return;
    }
    sync_lanes(&d.twin, st);
}

/// The ways in that waited (iOS takePending): a banner tapped before the room's word landed opens once the room is known.
fn take_pending(d: &Desk, st: &mut State, gid: &str) {
    let Some((chat, room, at)) = st.pending.clone() else { return };
    if st.live.is_some() || groups::chat_of(gid) != chat || st.seen.get(gid).map(|s| s.id.as_str()) != Some(room.as_str()) {
        return;
    }
    st.pending = None;
    if now_s() - at < 60.0 {
        let _ = join_in(d, st, &chat, false);
    }
}

/// A ROOM IS OPENED (iOS open): this machine is in it at once; the group hears it opened and the chosen hear they are invited --
/// a way in, never a ring. A room living in the group is joined instead: one room per group.
pub fn open(d: &Desk, chat: &str, kind: &str, video: bool, seats: &[String]) -> Result<(), &'static str> {
    let gid = chat.strip_prefix("grp:").ok_or("The call could not start")?;
    let g = d.group(gid).ok_or("The call could not start")?;
    if !kinds(&g).contains(&kind) {
        return Err("The call could not start");
    }
    with(d, |st| {
        if st.seen.get(gid).is_some_and(|s| !s.people.is_empty() && fresh(s)) {
            join_in(d, st, chat, video)?;
            invite_in(d, st, seats, true);
            publish(d, st);
            return Ok(());
        }
        open_in(d, st, chat, kind, video, seats, None, None)?;
        publish(d, st);
        Ok(())
    })
}

/// `minted` -- the room minted before it opens (grow); `comer` -- the peer of a call of two that already said it comes in: its
/// seat, its moment and its room key, so the pair with it stands at once instead of waiting for the group's road.
#[allow(clippy::too_many_arguments)]
fn open_in(d: &Desk, st: &mut State, chat: &str, kind: &str, video: bool, seats: &[String], minted: Option<Mint>,
           comer: Option<(String, f64, Vec<u8>)>) -> Result<(), &'static str> {
    let gid = chat.strip_prefix("grp:").ok_or("The call could not start")?;
    let g = d.group(gid).ok_or("The call could not start")?;
    if st.live.is_some() {
        leave_in(d, st, "another room", true);
    }
    let m = match minted { Some(m) => m, None => mint().ok_or("The call could not start")? };
    let (id, key, kp, ks, now) = (m.id, m.key, m.kp, m.ks, m.at);
    let mut s = Seen { id: id.clone(), kind: kind.into(), key: b64(&key), owner: g.me.clone(), video, people: BTreeMap::new(), since: now,
                       at: now, asked_by: None, keys: BTreeMap::new() };
    s.people.insert(g.me.clone(), now);
    s.keys.insert(g.me.clone(), b64(&kp));
    if let Some((seat, at, key)) = comer.filter(|c| c.0 != g.me && is_seat(&c.0) && c.2.len() == abi::MT_MLKEM_PUBKEY_SIZE) {
        s.people.insert(seat.clone(), at);
        s.keys.insert(seat, b64(&key));
    }
    st.seen.insert(gid.to_string(), s.clone());
    enter(d, st, &s, &g, chat, video, kp.clone(), ks);
    let e = Event { r: id.clone(), e: "open".into(), m: kind.into(), k: Some(b64(&key)), v: Some(if video { 1 } else { 0 }), at: now,
                    o: Some(g.me.clone()), q: Some(b64(&kp)), ..Default::default() };
    tell(d, &e, gid, false);
    d.room_event(gid, "call", &g.me, kind, video, &id, 0);
    invite_in(d, st, seats, true);
    Ok(())
}

/// A CALL OF TWO GROWS INTO A ROOM (iOS MTGroupRoom.grow; the author's words 17.10.2026 23:22 MSK: «add to the current call more
/// people, up to 13 on a call»): a group of this machine is born of the peer and the people chosen, the room is minted, and
/// the word for the call's own road comes back -- «group/room», then on a line of its own the peer's invitation into the
/// group and the room's open (base64 of {i, o}), which an older build cannot read and passes by. The call stands until the peer
/// answers that it comes in.
pub fn grow_prepare(d: &Desk, peer: &str, pipes: &[String], video: bool) -> Option<String> {
    let title = if ru_now() { "Групповой звонок" } else { "Group Call" };
    let mut all = vec![peer.to_string()];
    all.extend(pipes.iter().filter(|p| *p != peer).cloned());
    if all.len() + 1 > CAPACITY {
        return None;
    }
    let chat = d.group_create(title, &all)?;
    let gid = chat.strip_prefix("grp:")?.to_string();
    let g = d.group(&gid)?;
    let seat = g.members.iter().find(|m| m.pipe == peer)?.seat.clone();
    let others: Vec<String> = g.members.iter().map(|m| m.seat.clone()).filter(|s| *s != seat).collect();
    let m = mint()?;
    let opened = Event { r: m.id.clone(), e: "open".into(), m: "call".into(), k: Some(b64(&m.key)), v: Some(if video { 1 } else { 0 }), at: m.at,
                         o: Some(g.me.clone()), q: Some(b64(&m.kp)), ..Default::default() };
    let inline = b64(json!({ "i": d.invitation_text(&gid, &seat)?, "o": serde_json::to_string(&opened).ok()? }).to_string().as_bytes());
    let word = format!("{gid}/{}\n{inline}", m.id);
    with(d, |st| st.grow = Some(Grow { chat, mint: m, peer: seat, others, video }));
    Some(word)
}

/// The peer answered the move (iOS roomAnswered, «key moment»), or said nothing in four seconds: the room opens with the peer in
/// it when it answered, the peer invited without a ring (its way back), the others invited.
pub fn grow_open(d: &Desk, reply: Option<&str>) -> Result<(), &'static str> {
    with(d, |st| {
        let g = st.grow.take().ok_or("The call could not start")?;
        let comer = reply.and_then(|r| {
            let (k, at) = r.trim().split_once(' ')?;
            Some((g.peer.clone(), at.parse::<f64>().ok()?, unb64(k)?))
        });
        open_in(d, st, &g.chat, "call", g.video, &[], Some(g.mint), comer)?;
        invite_in(d, st, std::slice::from_ref(&g.peer), false);
        invite_in(d, st, &g.others, true);
        publish(d, st);
        Ok(())
    })
}

/// THE ROOM HANDED ON THE CALL'S OWN ROAD (iOS takeInline): the owner's invitation of this machine into the call's group and the
/// room's open ride in the move word itself. The group and the room stand here now; my room key and my moment go back on the same
/// road, and the way in waits for the call of two to rest. Only the call's peer, owning the group it names, is believed.
pub fn take_inline(d: &Desk, peer: &str, head: &str, payload: &str) -> Option<String> {
    let (gid, room) = head.split_once('/')?;
    if !is_room_id(gid) || !is_room_id(room) || with(d, |st| st.live.is_some()) {
        return None;
    }
    let o: Value = serde_json::from_slice(&unb64(payload)?).ok()?;
    let (inv, open) = (o["i"].as_str()?, o["o"].as_str()?);
    d.group_word(peer, &crate::book::mint_mid(), inv);
    let g = d.group(gid)?;
    if g.owner != peer {
        return None;
    }
    heard(d, open, gid, "0", "");
    let (kp, ks) = keypair()?;
    let at = now_s();
    with(d, |st| {
        if st.seen.get(gid).map(|s| s.id.as_str()) != Some(room) {
            return None;
        }
        st.pending_mint = Some((room.to_string(), kp.clone(), ks, at));
        Some(format!("{} {at}", b64(&kp)))
    })
}

/// THIS MACHINE COMES INTO THE GROUP'S ROOM (iOS join): it calls everyone already in, being later.
pub fn join(d: &Desk, chat: &str, video: bool) -> Result<(), &'static str> {
    with(d, |st| {
        let r = join_in(d, st, chat, video);
        publish(d, st);
        r
    })
}

fn join_in(d: &Desk, st: &mut State, chat: &str, video: bool) -> Result<(), &'static str> {
    let gid = chat.strip_prefix("grp:").ok_or("The call has ended")?;
    let g = d.group(gid).filter(|g| !g.left).ok_or("The call has ended")?;
    let s = st.seen.get(gid).filter(|s| fresh(s) && !s.people.is_empty()).cloned().ok_or("The call has ended")?;
    if st.live.as_ref().is_some_and(|r| r.id == s.id) {
        return Ok(());
    }
    if s.people.len() >= CAPACITY {
        return Err("This call is full");
    }
    if st.live.is_some() {
        leave_in(d, st, "another room", true);
    }
    // A CALL OF TWO MOVING IN comes with the room key and the moment it already gave its peer on the call's road (take_inline)
    let minted = st.pending_mint.take().filter(|m| m.0 == s.id);
    let (kp, ks, now) = match minted {
        Some((_, kp, ks, at)) => (kp, ks, at),
        None => {
            let (kp, ks) = keypair().ok_or("The call could not start")?;
            (kp, ks, now_s())
        }
    };
    let mut s2 = s.clone();
    s2.people.insert(g.me.clone(), now);
    s2.at = now;
    s2.asked_by = None;
    s2.keys.insert(g.me.clone(), b64(&kp));
    st.seen.insert(gid.to_string(), s2.clone());
    let video = video && s.kind == "call";
    enter(d, st, &s2, &g, chat, video, kp.clone(), ks);
    let e = Event { r: s.id.clone(), e: "in".into(), m: s.kind.clone(), k: Some(s.key.clone()), v: Some(if video { 1 } else { 0 }), at: now,
                    o: Some(s.owner.clone()), q: Some(b64(&kp)), ..Default::default() };
    tell(d, &e, gid, false);
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn enter(d: &Desk, st: &mut State, s: &Seen, g: &Group, chat: &str, video: bool, kp: Vec<u8>, ks: Vec<u8>) {
    let r = Live {
        group: g.id.clone(), chat: chat.to_string(), id: s.id.clone(), kind: s.kind.clone(), key: unb64(&s.key).unwrap_or_default(),
        me: g.me.clone(), since: s.people.get(&g.me).copied().unwrap_or_else(now_s), owner: s.owner.clone(), video, people: s.people.clone(),
        keys: s.keys.iter().filter(|(k, _)| **k != g.me).filter_map(|(k, v)| unb64(v).map(|b| (k.clone(), b))).collect(),
        kem_pub: kp, kem_sec: ks, keyed: HashSet::new(), reannounced: HashSet::new(), ringing: BTreeMap::new(), said_here: now_s(),
        was_alone: false, linked: BTreeMap::new(), twin: d.twin.clone(),
    };
    st.live = Some(r);
    sync_lanes(&d.twin, st);
}

/// THIS MACHINE LEAVES THE ROOM (iOS leave): the group hears it went out -- the last one out, or a stream's owner, closes it.
pub fn leave(d: &Desk) {
    with(d, |st| {
        leave_in(d, st, "by hand", true);
        publish(d, st);
    });
}

fn leave_in(d: &Desk, st: &mut State, _why: &str, tell_group: bool) {
    let Some(r) = st.live.take() else { return };
    close_lanes(&d.twin);
    crate::wallet::burn_now(d.vault);   // the room's last seconds go to the chain as it is left (iOS MTGroupRoom → MTCallMint.finish)
    let now = now_s();
    let others = r.people.keys().filter(|k| **k != r.me).count();
    // A STREAM ENDS WITH ITS OWNER; the last one out ends the room
    let ends = others == 0 || (r.kind == "live" && r.owner == r.me);
    if tell_group {
        if ends {
            let since = st.seen.get(&r.group).filter(|s| s.id == r.id).map(|s| s.since).unwrap_or(r.since);
            let video = st.seen.get(&r.group).is_some_and(|s| s.video);
            d.room_event(&r.group, "ended", &r.me, &r.kind, video, &r.id, (now - since).max(0.0) as i64);
        }
        let e = Event { r: r.id.clone(), e: (if ends { "end" } else { "out" }).into(), m: r.kind.clone(), at: now, o: Some(r.owner.clone()),
                        ..Default::default() };
        tell(d, &e, &r.group, false);
    }
    if let Some(s) = st.seen.get_mut(&r.group).filter(|s| s.id == r.id) {
        s.people.remove(&r.me);
        s.at = now;
        if ends || s.people.is_empty() {
            st.seen.remove(&r.group);
        }
    }
}

/// The owner closes the room for everyone in it (iOS endForEveryone); the pairs hear «end» on their channels from the window.
pub fn end_for_everyone(d: &Desk) {
    with(d, |st| {
        let Some(r) = st.live.clone().filter(|r| r.owner == r.me) else { return };
        let e = Event { r: r.id.clone(), e: "end".into(), m: r.kind.clone(), at: now_s(), o: Some(r.owner.clone()), ..Default::default() };
        tell(d, &e, &r.group, false);
        let since = st.seen.get(&r.group).filter(|s| s.id == r.id).map(|s| s.since).unwrap_or(r.since);
        let video = st.seen.get(&r.group).is_some_and(|s| s.video);
        d.room_event(&r.group, "ended", &r.me, &r.kind, video, &r.id, (now_s() - since).max(0.0) as i64);
        leave_in(d, st, "ended for everyone", false);
        st.seen.remove(&r.group);
        publish(d, st);
    });
}

/// AN INVITATION (iOS invite): the seats chosen hear the room's way in -- a banner and the bar over their chat, never a ring.
pub fn invite(d: &Desk, seats: &[String]) {
    with(d, |st| {
        invite_in(d, st, seats, true);
        publish(d, st);
    });
}

fn invite_in(d: &Desk, st: &mut State, seats: &[String], ring: bool) {
    let Some(r) = st.live.as_mut() else { return };
    let mut all: Vec<String> = seats.iter().filter(|s| is_seat(s)).cloned().collect();
    all.sort();
    all.dedup();
    all.truncate(200);
    if all.is_empty() {
        return;
    }
    let now = now_s();
    for s in all.iter().filter(|s| !r.people.contains_key(*s)) {
        r.ringing.insert(s.clone(), now);
    }
    // a word of the group holds 4096 bytes: the seats ride in portions of sixteen
    for part in all.chunks(16) {
        let e = Event { r: r.id.clone(), e: "ask".into(), m: r.kind.clone(), k: Some(b64(&r.key)), v: Some(0), at: now, o: Some(r.owner.clone()),
                        to: Some(part.to_vec()), q: Some(b64(&r.kem_pub)), ..Default::default() };
        let gid = r.group.clone();
        tell(d, &e, &gid, ring);
    }
    say("Invitation sent");
}

/// The owner takes one seat out of the room (iOS ownerDrop): the group hears it went out; the window tells the pair «drop».
pub fn owner_drop(d: &Desk, seat: &str) {
    with(d, |st| {
        let Some(r) = st.live.clone().filter(|r| r.owner == r.me && r.people.contains_key(seat)) else { return };
        let e = Event { r: r.id.clone(), e: "out".into(), m: r.kind.clone(), at: now_s(), o: Some(r.owner.clone()), w: Some(seat.to_string()),
                        ..Default::default() };
        tell(d, &e, &r.group, false);
        vanish_in(d, st, seat, false);
        publish(d, st);
    });
}

/// A SEAT THAT LEFT OR FELL SILENT WITHOUT A WORD (iOS vanish, the window's beat: no pair of ours stood with it for three
/// minutes, or its pair said bye): it leaves the room here, and the first in the room says it went out -- for the bars.
pub fn vanish(d: &Desk, seat: &str, tell_group: bool) {
    with(d, |st| {
        vanish_in(d, st, seat, tell_group);
        publish(d, st);
    });
}

fn vanish_in(d: &Desk, st: &mut State, seat: &str, tell_group: bool) {
    let Some(r) = st.live.as_mut() else { return };
    r.linked.remove(seat);
    if r.people.remove(seat).is_none() {
        return;
    }
    if tell_group && first_in(&r.people) == r.me {
        let e = Event { r: r.id.clone(), e: "out".into(), m: r.kind.clone(), at: now_s(), o: Some(r.owner.clone()), w: Some(seat.to_string()),
                        ..Default::default() };
        let gid = r.group.clone();
        tell(d, &e, &gid, false);
    }
    if r.owner == seat {
        r.owner = first_in(&r.people);
    }
    let (gid, id, owner) = (r.group.clone(), r.id.clone(), r.owner.clone());
    // ALONE AFTER EVERYONE FELL SILENT: the silence may be mine -- it says once more that it is here
    if tell_group && r.people.len() == 1 && !r.was_alone {
        r.was_alone = true;
        let e = Event { r: r.id.clone(), e: "in".into(), m: r.kind.clone(), k: Some(b64(&r.key)), at: spoken(r.since), o: Some(r.owner.clone()),
                        q: Some(b64(&r.kem_pub)), s: Some(r.since), ..Default::default() };
        tell(d, &e, &gid, false);
    }
    if let Some(s) = st.seen.get_mut(&gid).filter(|s| s.id == id) {
        s.people.remove(seat);
        s.owner = owner;
    }
    sync_lanes(&d.twin, st);
}

/// A pair of the window stood or fell: a standing pair is the witness that its seat is in the room.
pub fn linked(d: &Desk, seat: &str, on: bool) {
    with(d, |st| {
        let Some(r) = st.live.as_mut() else { return };
        if on {
            let m = r.people.get(seat).copied().unwrap_or_else(now_s);
            r.linked.insert(seat.to_string(), m);
            r.was_alone = false;
        } else {
            r.linked.remove(seat);
        }
    });
}

/// THE ROOM'S BEAT (iOS beat, the room's part): a living room's first one says every ten minutes that it lives.
pub fn beat(d: &Desk) {
    with(d, |st| {
        let Some(r) = st.live.as_mut() else { return };
        let now = now_s();
        if now - r.said_here > HERE_EVERY_S && first_in(&r.people) == r.me {
            r.said_here = now;
            let e = Event { r: r.id.clone(), e: "here".into(), m: r.kind.clone(), k: Some(b64(&r.key)), at: now, o: Some(r.owner.clone()),
                            q: Some(b64(&r.kem_pub)), p: Some(r.people.keys().cloned().collect()), ..Default::default() };
            let gid = r.group.clone();
            tell(d, &e, &gid, false);
        }
    });
}

/// The group went from this machine (left, taken out): the room goes with it.
pub fn group_gone(d: &Desk, gid: &str) {
    with(d, |st| {
        if st.live.as_ref().is_some_and(|r| r.group == gid) {
            leave_in(d, st, "the group went", true);
        }
        st.seen.remove(gid);
        publish(d, st);
    });
}

/// A tap on a room's invitation before its word landed here: the way in waits a minute for it.
pub fn join_when_known(d: &Desk, chat: &str, room: &str) {
    with(d, |st| { st.pending = Some((chat.to_string(), room.to_string(), now_s())); });
}

// ───────────────────────────── the lanes of the pairs ─────────────────────────────

struct Lane {
    stop: Arc<AtomicBool>,
}

static LANES: Mutex<Option<HashMap<String, Lane>>> = Mutex::new(None);

/// The lanes stand for every seat this person pairs with (in a stream the watchers pair with its owner alone), and no other.
fn sync_lanes(twin: &str, st: &State) {
    let mut lanes = LANES.lock().unwrap();
    let lanes = lanes.get_or_insert_with(HashMap::new);
    let mine = format!("{twin}\0");
    let want: HashMap<String, (String, Vec<u8>)> = match st.live.as_ref() {
        Some(r) => r.people.keys().filter(|s| **s != r.me && (r.stage(s) || r.stage(&r.me)))
            .map(|s| { let n = lane_name(&r.id, &r.me, s); (format!("{mine}{n}"), (n, lane_key(&r.key, &r.me, s).to_vec())) }).collect(),
        None => HashMap::new(),
    };
    lanes.retain(|k, l| {
        let keep = !k.starts_with(&mine) || want.contains_key(k);
        if !keep {
            l.stop.store(true, Ordering::SeqCst);
        }
        keep
    });
    for (k, (name, secret)) in want {
        if lanes.contains_key(&k) {
            continue;
        }
        let stop = Arc::new(AtomicBool::new(false));
        lanes.insert(k, Lane { stop: stop.clone() });
        let twin = twin.to_string();
        std::thread::spawn(move || listen_lane(&name, &secret, &twin, &stop));
    }
}

fn close_lanes(twin: &str) {
    let mine = format!("{twin}\0");
    if let Some(l) = LANES.lock().unwrap().as_mut() {
        l.retain(|k, x| {
            if k.starts_with(&mine) {
                x.stop.store(true, Ordering::SeqCst);
            }
            !k.starts_with(&mine)
        });
    }
}

/// One lane long-polled while it lives (iOS fetchSignals on the room's set): its words, opened, go to the room.
fn listen_lane(name: &str, secret: &[u8], twin: &str, stop: &AtomicBool) {
    while !stop.load(Ordering::SeqCst) {
        let cw = conv_w(secret, wire::day());
        let dev = hex(&sha(&[b"mt-lane-dev\0", format!("windows-room-{}", std::process::id()).as_bytes(), b"\0", cw.as_bytes()])[..8]);
        let body = json!({ "conv": cw, "from_id": sub_id(&cw, twin), "wait": 10, "dev": dev });
        let mut any = false;
        let mut got = vec![];
        for door in doors::all() {
            let (code, v) = doors::post_at(&door, "/signal-fetch", &body, 13_000);
            if code != 200 {
                continue;
            }
            any = true;
            for e in v.as_ref().and_then(|v| v["envs"].as_array()).cloned().unwrap_or_default() {
                let Some(e) = e.as_str().filter(|e| *e != "box") else { continue };
                if let Some((_, epoch, bytes)) = crate::presence::Presence::open(secret, e, None) {
                    if epoch == "room" {
                        got.push(bytes);
                    }
                }
            }
            if !got.is_empty() {
                break;
            }
        }
        if stop.load(Ordering::SeqCst) {
            return;
        }
        for b in got {
            lane_word(twin, name, &b);
        }
        if !any {
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }
}

/// The room a person is in.
fn live_of(twin: &str) -> Option<Live> {
    STATE.lock().unwrap().as_ref().and_then(|m| m.get(twin)).and_then(|st| st.live.clone())
}

/// A PAIR WORD FROM THE NODE (iOS laneWord): the lane is the room's, the content is mine alone.
fn lane_word(twin: &str, name: &str, payload: &[u8]) {
    let Ok(s) = serde_json::from_slice::<Signal>(payload) else { return };
    let r = live_of(twin);
    let Some(r) = r else { return };
    if s.r != r.id || s.t != r.me || name != lane_name(&r.id, &r.me, &s.f) || now_s() - s.at >= SIGNAL_LIFE_S {
        return;
    }
    let mut inner = Inner::default();
    if let (Some(ct), Some(x)) = (s.ct.as_deref().and_then(unb64), s.x.as_deref().and_then(unb64)) {
        let Some(i) = open_word(&x, &ct, &r.kem_sec, &bind(&r.id, &s.f, &r.me, &s.c, s.g)).and_then(|p| serde_json::from_slice::<Inner>(&p).ok()) else {
            return; // a pair word not sealed to this machine
        };
        inner = i;
    }
    tell_signal(twin, json!({ "from": s.f, "c": s.c, "g": s.g, "sdp": inner.sdp, "ice": inner.ice }));
}

/// A PAIR WORD TO A SEAT (iOS send): sealed to its room key, onto the pair's lane at every living door. False -- the seat's room
/// key has not come yet (the window offers again on its beat).
pub fn send(twin: &str, seat: &str, c: &str, gen: i64, sdp: Option<String>, ice: Option<Vec<Ice>>) -> bool {
    let r = live_of(twin);
    let Some(r) = r else { return false };
    if !is_seat(seat) || seat == r.me || !["offer", "answer", "ice", "bye"].contains(&c) {
        return false;
    }
    let mut s = Signal { r: r.id.clone(), f: r.me.clone(), t: seat.to_string(), c: c.to_string(), g: gen, ct: None, x: None, at: now_s() };
    if sdp.is_some() || ice.is_some() {
        let Some(to) = r.keys.get(seat) else { return false };
        let Ok(inner) = serde_json::to_vec(&Inner { sdp, ice }) else { return false };
        let Some((ct, boxed)) = seal_word(&inner, to, &bind(&r.id, &r.me, seat, c, gen)) else { return false };
        s.ct = Some(b64(&ct));
        s.x = Some(b64(&boxed));
    }
    let Ok(payload) = serde_json::to_vec(&s) else { return false };
    post_lane(&r.twin, &lane_key(&r.key, &r.me, seat), &payload)
}

/// twin ‖ 0 ‖ «room» ‖ 0 ‖ raw DEFLATE of the word, sealed under the lane's minute key (iOS postSignal), at every living door.
fn post_lane(twin: &str, secret: &[u8], payload: &[u8]) -> bool {
    let plain = [twin.as_bytes(), &[0], b"room", &[0], &miniz_oxide::deflate::compress_to_vec(payload, 6)].concat();
    let Some(env) = crypto::seal(&body_key(secret, wire::minute()), &plain) else { return false };
    let cw = conv_w(secret, wire::day());
    let body = json!({ "conv": cw, "from_id": sub_id(&cw, twin), "env": b64(&env) });
    let mut ok = false;
    for door in doors::all() {
        ok |= doors::post_at(&door, "/signal", &body, 5_000).0 == 200;
    }
    ok
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pair_word_opens_for_its_receiver_alone() {
        let (pk, sk) = keypair().unwrap();
        let (other_pk, other_sk) = keypair().unwrap();
        let b = bind("a".repeat(32).as_str(), "0", "b1", "offer", 0);
        let (ct, boxed) = seal_word(b"v=0 sdp", &pk, &b).unwrap();
        assert_eq!(open_word(&boxed, &ct, &sk, &b).as_deref(), Some(&b"v=0 sdp"[..]));
        assert!(open_word(&boxed, &ct, &other_sk, &b).is_none(), "another person of the group reads nothing");
        assert!(open_word(&boxed, &ct, &sk, &bind("a".repeat(32).as_str(), "0", "b1", "offer", 1)).is_none(), "another generation opens nothing");
        assert!(seal_word(b"x", &other_pk[..10], &b).is_none());
    }

    #[test]
    fn the_names_the_order_and_the_lane_are_ios_own() {
        let id = "0123456789abcdef0123456789abcdef";
        assert!(is_room_id(id) && !is_room_id(&id.to_uppercase()) && !is_room_id("abc"));
        assert_eq!(lane_name(id, "b2", "a1"), format!("room:{id}:a1:b2"));
        assert_eq!(lane_key(&[1; 32], "b2", "a1"), lane_key(&[1; 32], "a1", "b2"), "both name the pair's key alike");
        assert_eq!(hex(&lane_key(&[0; 32], "0", "1")), hex(&sha(&[b"mt-room-pair", &[0; 32], b"0", &[0], b"1"])));
        assert!(later((2.0, "a"), (1.0, "b")) && later((1.0, "b"), (1.0, "a")) && !later((1.0, "a"), (1.0, "b")));
        let people: BTreeMap<String, f64> = [("c".to_string(), 5.0), ("a".to_string(), 7.0), ("b".to_string(), 5.0)].into_iter().collect();
        assert_eq!(first_in(&people), "b", "the earliest moment, the lower seat for a tie");
        // an event reads iOS's JSON and writes its keys short, with nothing for what it lacks
        let e: Event = serde_json::from_str(r#"{"r":"0123456789abcdef0123456789abcdef","e":"ask","m":"call","at":1792536000.5,"to":["b1"],"x":7}"#).unwrap();
        assert_eq!((e.e.as_str(), e.to.as_deref(), e.k.as_deref()), ("ask", Some(&["b1".to_string()][..]), None));
        let out = serde_json::to_value(&Event { r: id.into(), e: "out".into(), m: "call".into(), at: 1.0, ..Default::default() }).unwrap();
        assert_eq!(out, json!({ "r": id, "e": "out", "m": "call", "at": 1.0 }));
        assert_eq!(bind(id, "0", "b1", "ice", 2), format!("{id}/0/b1/ice/2"));
    }
}
