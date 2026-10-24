//! THE CHAIN OF THE PERSON (iOS MTPersonChain, 10.10.2026; Canon «The level of the chain of the person»): the seconds the person
//! is on the network, by the nodes' own clock -- a node's answer of any road while the window is in front is a second (once a
//! second at most, iOS personFeed), and so is every second back to the answer before it when the two are no more than ten apart.
//! The level is bit_length(s) − 1, none below a second; the chain is one link a level, at the node second the count reached 2^k
//! (TimeChain/wallet-person.jsonl). The devices of the words join their seconds: one sealed piece a device on every node, beside
//! the coin book (/vault-put, /vault-get under the person's own row). The window left -- hidden or folded -- keeps the node second
//! of its last answer; the first answer after its return mints every second between, one coin a second (iOS left / came).

use crate::coins::{self, Link};
use crate::vault::Vault;
use crate::wire::{b64, hex, sha, unb64};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::Mutex;

/// Two answers this far apart or nearer vouch for every second between them.
pub const REACH: i64 = 10;
const KEY: &str = "personSeconds";
/// The words a piece's seal is bound to (iOS MTPersonChain.aad).
const AAD: &[u8] = b"mt.person.chain";

/// A stretch of node seconds, both ends counted.
#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
pub struct Span {
    pub a: i64,
    pub b: i64,
}
#[derive(Serialize, Deserialize, Clone, Copy, Debug)]
struct Away {
    at: i64,
    level: i64,
}
#[derive(Serialize, Deserialize, Default)]
struct Kept {
    lane: String,
    spans: Vec<Span>,
    away: Option<Away>,
}
/// One device's piece on the nodes (iOS Piece): its lane and its spans.
#[derive(Serialize, Deserialize)]
struct Piece {
    lane: String,
    spans: Vec<Span>,
}

struct State {
    vault: Vault,
    dir: PathBuf,
    lane: Vec<u8>,
    spans: Vec<Span>,
    away: Option<Away>,
    /// the node second of the last answer in this stretch in front
    last: Option<i64>,
    seconds: i64,
    links: Vec<Link>,
    dirty: bool,
    fed_at: f64,
    put_at: f64,
    got_at: f64,
    /// a piece's name: its lane, opened once
    opened: HashMap<String, Vec<u8>>,
    /// a node's door: the piece of this lane it holds now
    mine: HashMap<String, String>,
    stale: HashSet<String>,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);
/// The window in front of the person (focused): only then is a node's answer a second.
static FRONT: AtomicBool = AtomicBool::new(false);
/// How far the nodes' clock stands from this machine's, in milliseconds, since a node answered (iOS MontanaWakePush.nodeSkewMs).
static SKEW_MS: AtomicI64 = AtomicI64::new(i64::MIN);

/// A NODE'S SECOND HEARD (its Date header): the nodes' clock, and a second of the person on the network.
pub fn clock(s: i64) {
    if s <= 0 {
        return;
    }
    SKEW_MS.store(s * 1000 - crate::wire::now_ms(), Ordering::SeqCst);
    answered(s);
}
/// «Now» by the nodes' clock (iOS nodeNow), in seconds; None before a node answered.
pub fn node_now_s() -> Option<i64> {
    node_now_ms().map(|ms| ms / 1000)
}
/// The same, in milliseconds.
pub fn node_now_ms() -> Option<i64> {
    let skew = SKEW_MS.load(Ordering::SeqCst);
    (skew != i64::MIN).then(|| crate::wire::now_ms() + skew)
}

/// THE LEVEL (Canon): the whole doublings of the count, none below one second.
pub fn level(s: i64) -> Option<i64> {
    coins::person_level(s)
}

/// Spans joined: sorted, and any two that touch or overlap become one -- a second is counted once however many devices held it.
pub fn joined(mut all: Vec<Span>) -> Vec<Span> {
    all.retain(|s| s.a <= s.b);
    all.sort_by_key(|s| s.a);
    let mut out: Vec<Span> = vec![];
    for s in all {
        match out.last_mut() {
            Some(l) if s.a <= l.b + 1 => l.b = l.b.max(s.b),
            _ => out.push(s),
        }
    }
    out
}

/// One link a level, at the node second the count reached 2^k, each sealed on the one before (iOS MTPersonChain.chain).
pub fn chain(spans: &[Span]) -> Vec<Link> {
    let (mut out, mut count, mut next, mut prev) = (Vec::<Link>::new(), 0i64, 1i64, "0".repeat(64));
    for s in spans {
        let len = s.b - s.a + 1;
        while next <= count + len {
            let at = (s.a + (next - count) - 1) * 1000;
            let k = out.len() as i64;
            let refr = format!("level:{k}");
            let hash = coins::chain_seal(k + 1, at, "level", k, &refr, &prev);
            out.push(Link { n: k + 1, at, k: "level".into(), c: k, refr, prev: prev.clone(), hash: hash.clone() });
            prev = hash;
            if next > i64::MAX / 2 {
                return out;
            }
            next *= 2;
        }
        count += len;
    }
    out
}

fn seconds_of(spans: &[Span]) -> i64 {
    spans.iter().map(|s| s.b - s.a + 1).sum()
}

/// The person seated: their seconds read from their own vault (a fresh lane of sixteen bytes at the first life).
pub fn start(vault: &Vault, dir: &Path) {
    let kept: Kept = vault.get(KEY).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let lane = unb64(&kept.lane).filter(|l| l.len() == 16).or_else(|| crate::crypto::random(16)).unwrap_or_else(|| vec![0; 16]);
    let spans = joined(kept.spans);
    let mut st = State { vault: vault.clone(), dir: dir.to_path_buf(), lane, seconds: 0, links: vec![], spans, away: kept.away, last: None,
                         dirty: false, fed_at: 0.0, put_at: 0.0, got_at: 0.0, opened: HashMap::new(), mine: HashMap::new(), stale: HashSet::new() };
    recount(&mut st, false);
    keep(&st);
    *STATE.lock().unwrap() = Some(st);
}

fn keep(st: &State) {
    let kept = Kept { lane: b64(&st.lane), spans: st.spans.clone(), away: st.away };
    st.vault.set(KEY, serde_json::to_vec(&kept).unwrap_or_default().as_slice());
}

/// The count and the links read again; the chain's file follows a new level.
fn recount(st: &mut State, write: bool) {
    st.seconds = seconds_of(&st.spans);
    let fresh = chain(&st.spans);
    if fresh.last().map(|l| &l.hash) == st.links.last().map(|l| &l.hash) {
        return;
    }
    st.links = fresh;
    if !write && st.dir.join("TimeChain").join("wallet-person.jsonl").exists() {
        return;
    }
    let dir = st.dir.join("TimeChain");
    let _ = std::fs::create_dir_all(&dir);
    let body: String = st.links.iter().filter_map(|l| serde_json::to_string(l).ok()).map(|l| l + "\n").collect();
    let _ = std::fs::write(dir.join("wallet-person.jsonl"), body);
}

/// The window came in front of the person, or left it.
pub fn set_front(on: bool) {
    FRONT.store(on, Ordering::SeqCst);
}
/// Whether the window stands in front of the person now (iOS: the app not in the background).
pub fn front() -> bool {
    FRONT.load(Ordering::SeqCst)
}

/// A NODE ANSWERED (its Date header, the node's second): while the window stands in front its second counts, and so does every
/// second back to the answer before it when they are no further apart than the reach. The coins of the seconds away, if the window
/// had left, are minted here, at the first answer after its return.
pub fn answered(s: i64) {
    if !FRONT.load(Ordering::SeqCst) || s <= 0 {
        return;
    }
    let mut g = STATE.lock().unwrap();
    let Some(st) = g.as_mut() else { return };
    let now = crate::wire::now_ms() as f64 / 1000.0;
    if now - st.fed_at < 1.0 {
        return;
    }
    st.fed_at = now;
    let mint = st.away.take().map(|w| {
        keep(st);
        (s - w.at, w.level, st.vault.clone())
    });
    let from = st.last.filter(|l| *l <= s && s - l <= REACH).unwrap_or(s);
    st.last = Some(st.last.unwrap_or(s).max(s));
    let before = st.seconds;
    let mut all = st.spans.clone();
    all.push(Span { a: from, b: s });
    st.spans = joined(all);
    recount(st, true);
    if st.seconds != before {
        st.dirty = true;
        keep(st);
    }
    drop(g);
    // the seconds away, one coin a second (point 11, 19.10.2026), into the window of the away coins
    if let Some((gone, price, vault)) = mint.filter(|(gone, price, _)| *gone > 0 && *price > 0) {
        if let Some(coins) = gone.checked_mul(price) {
            let minted = coins::in_window(&vault, coins, coins::AWAY, gone, false);
            crate::trace_line(&format!("person_away seconds={gone} minted={minted}"));
        }
    }
}

/// THE WINDOW LEFT THE PERSON (hidden or folded, iOS left): the node second of its last answer is kept, and the coins of the seconds
/// away are minted at the return -- when the Global Level then stands above zero.
pub fn left(global: i64) {
    let mut g = STATE.lock().unwrap();
    let Some(st) = g.as_mut() else { return };
    let last = st.last.take();
    if let (Some(at), true) = (last, global > 0) {
        st.away = Some(Away { at, level: coins::PRICE });
        keep(st);
    }
}

/// The count as the TimeChain page shows it: seconds, level, the chain's length and its head.
pub fn shown() -> Value {
    let g = STATE.lock().unwrap();
    let Some(st) = g.as_ref() else { return json!({}) };
    let head = st.links.last().map(|l| l.hash.clone()).unwrap_or_else(|| "0".repeat(64));
    json!({ "seconds": st.seconds, "level": level(st.seconds), "links": st.links.len(), "head": head })
}
pub fn seconds() -> i64 {
    STATE.lock().unwrap().as_ref().map(|st| st.seconds).unwrap_or(0)
}

/// THE GLOBAL LEVEL OF THE PERSON, THE ONE READING OF IT (iOS MTPersonChain.global, Canon «The level of a person»): the lowest of
/// the person's level and the wallet's level of π (and of the fabric of time once this life reads one); never a sum or a mean.
pub fn global(balance: i64) -> i64 {
    crate::fabric::level_of_person(level(seconds()).unwrap_or(0), coins::pi_place(balance) as i64, crate::fabric::level_now().unwrap_or(i64::MAX))
}

fn seal(key: &[u8; 32], plain: &[u8]) -> Option<Vec<u8>> {
    let nonce = crate::crypto::random(12)?;
    let ct = ChaCha20Poly1305::new(key.into()).encrypt(Nonce::from_slice(&nonce), Payload { msg: plain, aad: AAD }).ok()?;
    Some([nonce, ct].concat())
}
fn open(key: &[u8; 32], sealed: &[u8]) -> Option<Vec<u8>> {
    if sealed.len() < 28 {
        return None;
    }
    ChaCha20Poly1305::new(key.into()).decrypt(Nonce::from_slice(&sealed[..12]), Payload { msg: &sealed[12..], aad: AAD }).ok()
}

/// THE DEVICES OF THE WORDS JOIN THEIR SECONDS (iOS tick): the other devices' pieces every half minute, this device's union when it
/// moved, once a minute at most. `entropy` is the words'; `write` -- whether this run lays anything on the nodes.
pub fn tick(entropy: &[u8; 32], write: bool) {
    let now = crate::wire::now_ms() as f64 / 1000.0;
    let (gather, put) = {
        let mut g = STATE.lock().unwrap();
        let Some(st) = g.as_mut() else { return };
        let gather = now - st.got_at >= 30.0;
        let put = write && st.dirty && now - st.put_at >= 60.0;
        if gather {
            st.got_at = now;
        }
        if put {
            st.put_at = now;
        }
        (gather, put)
    };
    let k = coins::vault_keys(entropy);
    let token = hex(&k.person_token());
    if gather {
        gather_pieces(&k.seal, &token);
    }
    if put {
        put_piece(&k.seal, &token);
    }
}

fn put_piece(key: &[u8; 32], token: &str) {
    let (plain, lane) = {
        let mut g = STATE.lock().unwrap();
        let Some(st) = g.as_mut() else { return };
        st.dirty = false;
        (serde_json::to_vec(&Piece { lane: b64(&st.lane), spans: st.spans.clone() }).unwrap_or_default(), st.lane.clone())
    };
    let Some(sealed) = seal(key, &plain) else { return };
    let id = hex(&sha(&[&sealed]));
    let mut laid = 0;
    for door in crate::doors::all() {
        let gone: Vec<String> = {
            let g = STATE.lock().unwrap();
            let Some(st) = g.as_ref() else { return };
            st.stale.iter().cloned().chain(st.mine.get(&door).cloned()).filter(|p| *p != id).collect()
        };
        let (code, o) = crate::doors::post_at(&door, "/vault-put", &json!({ "token": token, "blob": b64(&sealed), "replace": gone }), 10_000);
        let Some(piece) = o.as_ref().and_then(|o| o["piece"].as_str()).filter(|_| code == 200).map(str::to_string) else { continue };
        let mut g = STATE.lock().unwrap();
        let Some(st) = g.as_mut() else { return };
        st.mine.insert(door, piece.clone());
        st.opened.insert(piece, lane.clone());
        laid += 1;
    }
    let mut g = STATE.lock().unwrap();
    if let Some(st) = g.as_mut() {
        if laid > 0 { st.stale.clear() } else { st.dirty = true }
    }
    crate::trace_line(&format!("person_put doors={laid}"));
}

fn gather_pieces(key: &[u8; 32], token: &str) {
    let have: Vec<String> = STATE.lock().unwrap().as_ref().map(|st| st.opened.keys().take(256).cloned().collect()).unwrap_or_default();
    for door in crate::doors::all() {
        let (code, o) = crate::doors::post_at(&door, "/vault-get", &json!({ "token": token, "have": have }), 6_000);
        let Some(o) = o.filter(|_| code == 200) else { continue };
        let Some(held) = o["held"].as_array() else { continue };
        let horizon = crate::wire::now_ms() / 1000 + 60; // no second of the future is a second lived
        let mut got: Vec<Span> = vec![];
        let mut g = STATE.lock().unwrap();
        let Some(st) = g.as_mut() else { return };
        for x in o["pieces"].as_array().cloned().unwrap_or_default() {
            let (Some(id), Some(b)) = (x["piece"].as_str(), x["blob"].as_str().and_then(unb64)) else { continue };
            if hex(&sha(&[&b])) != id {
                continue; // a piece is its own name
            }
            let Some(p) = open(key, &b).and_then(|plain| serde_json::from_slice::<Piece>(&plain).ok()) else { continue };
            let Some(l) = unb64(&p.lane) else { continue };
            st.opened.insert(id.to_string(), l.clone());
            if l == st.lane {
                if st.mine.get(&door).map(String::as_str) != Some(id) {
                    st.stale.insert(id.to_string());
                }
                continue;
            }
            got.extend(p.spans.into_iter().filter(|s| s.b <= horizon));
        }
        let standing: HashSet<String> = held.iter().filter_map(|v| v.as_str().map(str::to_string)).collect();
        st.opened.retain(|k, _| standing.contains(k));
        let before = st.seconds;
        let mut all = st.spans.clone();
        all.extend(got);
        st.spans = joined(all);
        recount(st, true);
        if st.seconds != before {
            st.dirty = true;
            keep(st);
        }
        crate::trace_line(&format!("person_get seconds={} joined={}", st.seconds, st.seconds - before));
        return;
    }
}

/// ACCESS BY LEVEL (iOS MTLevelAccess; the author's words 16.10.2026 and 17.10.2026): every function a level opens, with its level --
/// at 7 the letters a correspondent deletes for everyone stay here (and the correspondent is told), at 7 calls record themselves,
/// at 8 a machine the person owns joins the network through this app. Below its level a function stands off; the person's own
/// choice is kept for the day the level opens it.
pub const KEEP_LEVEL: i64 = 7;
pub const RECORD_LEVEL: i64 = 7;
pub const NODE_LEVEL: i64 = 8;
pub const KEEP_CHOICE: &str = "levelKeepDeleted";
pub const RECORD_CHOICE: &str = "levelRecordCalls";
/// The person's choice for a function (on by default, as iOS keeps it).
pub fn choice(vault: &Vault, key: &str) -> bool {
    vault.get(key).map(|b| b != b"0").unwrap_or(true)
}
/// This machine keeps the letters its correspondents delete: the level opens it, and it stands until the person unticks it.
pub fn keeps_deleted(vault: &Vault) -> bool {
    global(coins::balance(vault)) >= KEEP_LEVEL && choice(vault, KEEP_CHOICE)
}

/// THE FROZEN VECTORS (iOS levelKAT; Canon: level(1) = 0, level(3) = 1, level(1048576) = 20, none below one second) and the
/// doubling's edge at every power.
pub fn level_kat() -> bool {
    if level(1) != Some(0) || level(3) != Some(1) || level(1_048_576) != Some(20) || level(0).is_some() || level(-5).is_some() {
        return false;
    }
    (1..=62).all(|k| level(1i64 << k) == Some(k) && level((1i64 << k) - 1) == Some(k - 1)) && level(i64::MAX) == Some(62)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_person_counts_each_second_once_and_seals_a_link_a_level() {
        assert!(level_kat());
        // two devices' spans that touch and overlap join into one
        let j = joined(vec![Span { a: 10, b: 12 }, Span { a: 5, b: 7 }, Span { a: 8, b: 9 }, Span { a: 11, b: 20 }, Span { a: 30, b: 29 }]);
        assert_eq!(j, vec![Span { a: 5, b: 20 }]);
        assert_eq!(seconds_of(&j), 16);
        // 16 seconds: levels 0..4 at the seconds the count reached 1, 2, 4, 8, 16
        let c = chain(&j);
        assert_eq!(c.iter().map(|l| (l.c, l.at / 1000)).collect::<Vec<_>>(), vec![(0, 5), (1, 6), (2, 8), (3, 12), (4, 20)]);
        assert_eq!(c[0].prev, "0".repeat(64));
        assert!(c.windows(2).all(|w| w[1].prev == w[0].hash));
        assert_eq!(c[4].hash, coins::chain_seal(5, 20_000, "level", 4, "level:4", &c[3].hash));
        // a piece sealed under the vault's key opens under it alone, bound to its words
        let key = [3u8; 32];
        let s = seal(&key, b"{\"lane\":\"x\",\"spans\":[]}").unwrap();
        assert_eq!(open(&key, &s).unwrap(), b"{\"lane\":\"x\",\"spans\":[]}");
        assert!(open(&[4u8; 32], &s).is_none());
    }

    #[test]
    fn a_function_of_a_level_stands_off_below_it_and_keeps_the_persons_choice() {
        let dir = std::env::temp_dir().join(format!("mt-levels-{}", hex(&crate::crypto::random(6).unwrap())));
        let v = Vault::at(&dir).unwrap();
        assert!(choice(&v, KEEP_CHOICE) && choice(&v, RECORD_CHOICE), "on by default, as iOS keeps them");
        assert!(v.set(KEEP_CHOICE, b"0") && !choice(&v, KEEP_CHOICE));
        assert!(v.set(KEEP_CHOICE, b"1"));
        // a person below level 7 keeps nothing others delete, whatever the choice
        assert!(global(coins::balance(&v)) < KEEP_LEVEL && !keeps_deleted(&v));
        assert_eq!((KEEP_LEVEL, RECORD_LEVEL, NODE_LEVEL), (7, 7, 8));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
