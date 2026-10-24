//! THE TIMECHAIN'S TIP RIDES ONE ROUND TRIP (iOS MTTimeChainTip, MTWalletCore.swift; the author's words 04.10.2026 16:30-16:34 MSK:
//! «find the lightest record of the TimeChain, so the sync tends to the speed of a ping -- a special file and only the last 13
//! records»). Every device of the words writes its own lane -- one writer, so two devices never contend for one link -- and every
//! link carries, beside its move, the lane's running balance. The tip is the lane's last thirteen links in their own bytes, sealed
//! under the words' key: one piece of each device on every node, in a row of its own beside the book (coinvault), replaced as the
//! lane grows. A device reads the others' tips in one round trip: a lane behind by thirteen links or less gives its missing moves in
//! the same piece, joined by their names; a longer gap or a seal that breaks the chain asks the book. The head also says the
//! writer's balance of the whole book once it had gathered it, so words opened anew show the seed's coins before the book lands.
//! The number shown stays the book's, where a move counts once by its name.

use crate::coins::{self, Entry, VaultKeys};
use crate::vault::Vault;
use crate::wire::{b64, hex, sha, unb64};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

pub const DEPTH: usize = 13;
/// The lane in this person's vault (iOS timechain-tip.bin in the person's coin folder, under the device's file protection).
const KEY: &str = "timechainTip";
const AAD: &[u8] = b"mt.timechain.tip";
const KINDS: [&str; 5] = ["earn", "receive", "spend", "send", "burn"];

#[derive(Clone, Debug, PartialEq)]
pub struct Link {
    pub n: u32,
    pub at: i64,
    pub k: u8,
    pub c: u64,
    pub b: i64,
    pub refr: String,
    pub peer: String,
    pub on: String,
}
impl Link {
    fn signed(&self) -> i64 {
        if self.k < 2 { self.c as i64 } else { -(self.c as i64) }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Tip {
    pub lane: Vec<u8>,
    pub seen: i64,
    pub heard: bool,
    pub prev: [u8; 32],
    pub links: Vec<Link>,
}

// THE BYTES, little-endian: the format 1, the lane (16), the seen balance (i64), heard (u8), prev (32), the count (u8), the links; a
// link: n (u32), at in ms (i64), the kind (u8), the coins (u64), the running balance (i64), then ref, peer and on, each a u16 length
// and its UTF-8.
pub fn encode(t: &Tip) -> Vec<u8> {
    let mut d = vec![1u8];
    d.extend(&t.lane);
    d.extend(t.seen.to_le_bytes());
    d.push(t.heard as u8);
    d.extend(t.prev);
    d.push(t.links.len() as u8);
    for l in &t.links {
        d.extend(bytes(l));
    }
    d
}
fn bytes(l: &Link) -> Vec<u8> {
    let mut d = Vec::with_capacity(40 + l.refr.len() + l.peer.len() + l.on.len());
    d.extend(l.n.to_le_bytes());
    d.extend(l.at.to_le_bytes());
    d.push(l.k);
    d.extend(l.c.to_le_bytes());
    d.extend(l.b.to_le_bytes());
    for s in [&l.refr, &l.peer, &l.on] {
        d.extend((s.len() as u16).to_le_bytes());
        d.extend(s.as_bytes());
    }
    d
}
struct Reader<'a> {
    d: &'a [u8],
    i: usize,
}
impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let s = self.d.get(self.i..self.i.checked_add(n)?)?;
        self.i += n;
        Some(s)
    }
    fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|b| b[0])
    }
    fn le<const N: usize>(&mut self) -> Option<[u8; N]> {
        self.take(N)?.try_into().ok()
    }
    fn text(&mut self) -> Option<String> {
        let n = u16::from_le_bytes(self.le()?) as usize;
        String::from_utf8(self.take(n)?.to_vec()).ok()
    }
}
pub fn decode(d: &[u8]) -> Option<Tip> {
    let mut r = Reader { d, i: 0 };
    if r.u8()? != 1 {
        return None;
    }
    let (lane, seen, heard, prev, count) = (r.take(16)?.to_vec(), i64::from_le_bytes(r.le()?), r.u8()?, r.le::<32>()?, r.u8()? as usize);
    if DEPTH < count {
        return None;
    }
    let mut t = Tip { lane, seen, heard: heard == 1, prev, links: Vec::with_capacity(count) };
    for _ in 0..count {
        let (n, at, k, c, b) = (u32::from_le_bytes(r.le()?), i64::from_le_bytes(r.le()?), r.u8()?, u64::from_le_bytes(r.le()?), i64::from_le_bytes(r.le()?));
        let (refr, peer, on) = (r.text()?, r.text()?, r.text()?);
        t.links.push(Link { n, at, k, c, b, refr, peer, on });
    }
    (r.i == d.len()).then_some(t)
}

// THE CHAIN: a link's seal is SHA-256 over the seal before it and the link's bytes, so the head seals the lane to its birth.
fn seal_link(prev: &[u8; 32], l: &Link) -> [u8; 32] {
    sha(&[prev, &bytes(l)])
}
fn chain(t: &Tip) -> Vec<[u8; 32]> {
    let mut prev = t.prev;
    t.links.iter().map(|l| {
        prev = seal_link(&prev, l);
        prev
    }).collect()
}
/// The window counts on: every link numbered after the one before, its balance the one before's and its own move.
fn whole(t: &Tip) -> bool {
    for (i, l) in t.links.iter().enumerate() {
        if KINDS.len() <= l.k as usize || l.c == 0 || l.c > i64::MAX as u64 {
            return false;
        }
        if i == 0 {
            continue;
        }
        let p = &t.links[i - 1];
        if l.n != p.n.wrapping_add(1) || p.b.checked_add(l.signed()) != Some(l.b) {
            return false;
        }
    }
    true
}
/// The window follows the head this device took of that lane: the seal at that link is the one taken, or the window begins right
/// after it. A lane never taken follows by itself.
fn follows(had: Option<(u32, [u8; 32])>, t: &Tip, seals: &[[u8; 32]]) -> bool {
    let (Some((n, hash)), Some(first)) = (had, t.links.first()) else { return true };
    if n.wrapping_add(1) == first.n {
        return t.prev == hash;
    }
    if first.n <= n {
        if let Some(i) = t.links.iter().position(|l| l.n == n) {
            return seals[i] == hash;
        }
    }
    true // further behind than the window: nothing to compare, the book carries the rest
}
/// The bytes read back as they were written (iOS selfCheck): thirteen links of every kind, a peer on every other one, the seal
/// followed from the sixth -- a writer and a reader that disagree on an order, a width or a length fail here.
pub fn self_check() -> bool {
    let mut t = Tip { lane: (0..16u8).collect(), seen: 13, heard: true, prev: [0; 32], links: vec![] };
    let mut b: i64 = 0;
    for n in 1..=DEPTH as u32 {
        let (k, c) = ((n % 5) as u8, n as u64 * 1_000_003);
        b += if k < 2 { c as i64 } else { -(c as i64) };
        t.links.push(Link { n, at: 1_759_000_000_000 + n as i64, k, c, b, refr: format!("r{n}"), peer: if n % 2 == 0 { format!("a:{n}") } else { String::new() }, on: String::new() });
    }
    let Some(back) = decode(&encode(&t)) else { return false };
    let (seals, back_seals) = (chain(&t), chain(&back));
    back == t && whole(&back) && follows(Some((t.links[5].n, seals[5])), &back, &back_seals) && !follows(Some((t.links[5].n, seals[4])), &back, &back_seals)
}
fn entry(l: &Link) -> Entry {
    Entry {
        k: KINDS[l.k as usize].into(),
        c: l.c as i64,
        refr: l.refr.clone(),
        peer: (!l.peer.is_empty()).then(|| l.peer.clone()),
        on: (!l.on.is_empty()).then(|| l.on.clone()),
        at: l.at as f64 / 1000.0,
    }
}

/// THE LANE CARRIES WHAT THE DEVICE BORE (iOS bore, the author's «yes» 04.10.2026 17:16 MSK to variant (a)): a letter's coin and a
/// coin letter reach every device of the words by the letter itself and the book counts each once by its name, so they ride no lane
/// -- a sum of lanes would count them once a device; the lane carries what this device alone bore: the Pantheon, the VPN wall,
/// chess and its Timer, the pull, spending, sending, burning.
fn bore(e: &Entry) -> bool {
    let s = coins::source(e, false);
    !((e.k == "earn" && matches!(s, "chats" | "groups" | "channels")) || (e.k == "receive" && s != "chess"))
}

/// What this run knows (one person a process -- a seat's move starts it anew): this device's lane, the last link of every other
/// lane taken, the balance the freshest heard tip told, the pieces opened once, the piece of this lane each node holds, the pieces
/// of this lane from before (gone at the next put), and when the next put leaves.
#[derive(Default)]
struct State {
    /// the vault's folder the lane was read from, and the lane
    tip: Option<(std::path::PathBuf, Tip)>,
    heads: HashMap<Vec<u8>, (u32, [u8; 32])>,
    seen: Option<i64>,
    seen_at: i64,
    opened: HashMap<String, Vec<u8>>,
    mine: HashMap<String, String>,
    stale: HashSet<String>,
    put_due: Option<f64>,
    put_at: f64,
    checked: bool,
    said_at: f64,
    asked: Option<String>,
}
static STATE: Mutex<Option<State>> = Mutex::new(None);
fn with<R>(f: impl FnOnce(&mut State) -> R) -> R {
    f(STATE.lock().unwrap().get_or_insert_with(State::default))
}
fn now() -> f64 {
    crate::wire::now_ms() as f64 / 1000.0
}

/// This device's lane, read once from the vault; born at the first ask where none stands. A lane that stands and would not open is
/// never written over: the lane waits for the next ask.
fn lane(st: &mut State, vault: &Vault) -> Option<Tip> {
    if st.tip.as_ref().is_none_or(|(d, _)| d != vault.dir()) {
        let t = if vault.has(KEY) {
            vault.get(KEY).and_then(|d| decode(&d)).filter(|t| t.lane.len() == 16)
        } else {
            crate::crypto::random(16).map(|lane| Tip { lane, seen: 0, heard: false, prev: [0; 32], links: vec![] })
        };
        st.tip = t.map(|t| (vault.dir().to_path_buf(), t));
    }
    st.tip.as_ref().map(|(_, t)| t.clone())
}

/// This device's own moves (the book's keep) join its lane: the running balance moves with each, the window keeps the last
/// thirteen, and the tip leaves for the nodes within two seconds. `heard` -- the seed's book was gathered here.
pub fn add(vault: &Vault, moves: &[Entry], balance: i64, heard: bool) {
    if moves.is_empty() {
        return;
    }
    with(|st| {
        let Some(mut t) = lane(st, vault) else { return };
        for e in moves.iter().filter(|e| bore(e)) {
            let Some(k) = KINDS.iter().position(|x| *x == e.k) else { continue };
            let (peer, on) = (e.peer.clone().unwrap_or_default(), e.on.clone().unwrap_or_default());
            if e.c <= 0 || [&e.refr, &peer, &on].iter().any(|s| 1024 < s.len()) {
                continue;
            }
            let signed = if k < 2 { e.c } else { -e.c };
            let Some(b) = t.links.last().map_or(0, |l| l.b).checked_add(signed) else { continue };
            let n = t.links.last().map_or(0, |l| l.n) + 1;
            t.links.push(Link { n, at: (e.at * 1000.0).round() as i64, k: k as u8, c: e.c as u64, b, refr: e.refr.clone(), peer, on });
            if DEPTH < t.links.len() {
                let first = t.links.remove(0);
                t.prev = seal_link(&t.prev, &first);
            }
        }
        t.seen = balance;
        t.heard = heard;
        vault.set(KEY, &encode(&t));
        st.tip = Some((vault.dir().to_path_buf(), t));
        // the tips leave at most once in two seconds: the moves of those seconds ride one piece
        if st.put_due.is_none() {
            st.put_due = Some(now() + (st.put_at + 2.0 - now()).max(0.3));
        }
    });
}

/// The put whose time came, taken (the coin walk asks every second while no put runs).
pub fn put_due() -> bool {
    with(|st| {
        let due = st.put_due.is_some_and(|t| t <= now());
        if due {
            st.put_due = None;
        }
        due
    })
}
/// A gathering asked by the window (the wallet's opening, its live round, the window's return) -- taken by the coin walk.
pub fn ask(why: &str) {
    with(|st| st.asked = Some(why.to_string()));
}
pub fn asked() -> Option<String> {
    with(|st| st.asked.take())
}
/// The balance of the whole book the freshest tip of another device told, written after that device had gathered the book.
pub fn seen() -> Option<i64> {
    with(|st| st.seen)
}
/// The run's memory of the tips let go (a check's second device in the same process).
#[cfg(test)]
pub fn forget() {
    *STATE.lock().unwrap() = None;
}

fn sealed(t: &Tip, key: &[u8; 32]) -> Option<Vec<u8>> {
    let nonce = crate::crypto::random(12)?;
    let ct = ChaCha20Poly1305::new(key.into()).encrypt(Nonce::from_slice(&nonce), Payload { msg: &encode(t), aad: AAD }).ok()?;
    Some([nonce, ct].concat())
}
fn opened(b: &[u8], key: &[u8; 32]) -> Option<Tip> {
    if b.len() < 28 {
        return None;
    }
    let plain = ChaCha20Poly1305::new(key.into()).decrypt(Nonce::from_slice(&b[..12]), Payload { msg: &b[12..], aad: AAD }).ok()?;
    decode(&plain).filter(|t| t.lane.len() == 16)
}

/// THE TIP LEAVES (iOS put): one piece of this lane on every node, under the words' tip row; the piece it replaces goes in the same
/// breath. The nodes that took it.
pub fn put(k: &VaultKeys) -> usize {
    let Some(t) = with(|st| {
        st.put_at = now();
        st.tip.as_ref().map(|(_, t)| t.clone())
    }) else { return 0 };
    let Some(blob) = sealed(&t, &k.seal) else { return 0 };
    let (token, id) = (hex(&k.tip), hex(&sha(&[&blob])));
    let mut laid = 0;
    for door in crate::doors::all() {
        // a piece named in its own replace would be taken off and not laid again (the node checks before it deletes)
        let gone: Vec<String> = with(|st| st.stale.iter().chain(st.mine.get(&door)).filter(|p| **p != id).cloned().collect::<HashSet<_>>().into_iter().collect());
        let (code, o) = crate::doors::post_machine(&door, "/vault-put", &json!({ "token": token, "blob": b64(&blob), "replace": gone }), 10_000);
        let Some(piece) = o.as_ref().and_then(|o| o["piece"].as_str()).filter(|_| code == 200).map(str::to_string) else { continue };
        with(|st| {
            st.mine.insert(door.clone(), piece.clone());
            st.opened.insert(piece, t.lane.clone());
        });
        laid += 1;
    }
    let say = with(|st| {
        if 0 < laid {
            st.stale.clear();
        }
        let say = 60.0 <= now() - st.said_at;
        if say {
            st.said_at = now();
        }
        say
    });
    if say {
        let last = t.links.last();
        crate::trace_line(&format!("tip_put n={} b={} bytes={} doors={laid}", last.map_or(0, |l| l.n), last.map_or(0, |l| l.b), blob.len()));
    }
    laid
}

/// THE OTHER DEVICES' TIPS IN ONE ROUND TRIP (iOS gather) to the first node that answers: a lane's new links join the book by their
/// names; a lane further behind than the window, or a link whose seal does not follow the head this device took, asks the book.
/// What it did: (lanes read, moves joined, a gap asked the book, broken lanes); None -- no node answered.
pub fn gather(vault: &Vault, k: &VaultKeys, why: &str) -> Option<(usize, usize, bool, usize)> {
    if with(|st| !std::mem::replace(&mut st.checked, true)) {
        crate::trace_line(&format!("tip_self ok={}", self_check() as u8));
    }
    let own = with(|st| lane(st, vault).map(|t| t.lane));
    let token = hex(&k.tip);
    let (mut fresh, mut lanes, mut gap, mut broken, mut answered) = (vec![], 0, false, 0, false);
    for door in crate::doors::all() {
        let have: Vec<String> = with(|st| st.opened.keys().take(256).cloned().collect());
        let (code, o) = crate::doors::post_machine(&door, "/vault-get", &json!({ "token": token, "have": have }), 6_000);
        let Some(o) = o.filter(|_| code == 200) else { continue };
        let Some(held) = o["held"].as_array().map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_string)).collect::<HashSet<_>>()) else { continue };
        answered = true;
        with(|st| {
            for x in o["pieces"].as_array().into_iter().flatten() {
                let (Some(id), Some(b)) = (x["piece"].as_str(), x["blob"].as_str().and_then(unb64)) else { continue };
                if hex(&sha(&[&b])) != id {
                    continue; // a piece is its own name
                }
                let Some(t) = opened(&b, &k.seal) else { continue };
                st.opened.insert(id.to_string(), t.lane.clone());
                if Some(&t.lane) == own.as_ref() {
                    if st.mine.get(&door).map(String::as_str) != Some(id) {
                        st.stale.insert(id.to_string());
                    }
                    continue;
                }
                lanes += 1;
                let (Some(first), Some(last)) = (t.links.first(), t.links.last()) else { continue };
                let seals = chain(&t);
                let had = st.heads.get(&t.lane).copied();
                if !whole(&t) || !follows(had, &t, &seals) {
                    broken += 1;
                    gap = true;
                    continue;
                }
                let took = had.map_or(0, |h| h.0);
                if last.n <= took {
                    continue;
                }
                if took + 1 < first.n {
                    gap = true; // further behind than the window: the book carries the rest
                }
                fresh.extend(t.links.iter().filter(|l| took < l.n).map(entry));
                st.heads.insert(t.lane.clone(), (last.n, seals[seals.len() - 1]));
                if t.heard && st.seen_at < last.at {
                    st.seen_at = last.at;
                    st.seen = Some(t.seen);
                }
            }
            st.opened.retain(|p, _| held.contains(p)); // a piece no node keeps is forgotten here too
        });
        break;
    }
    if !answered {
        return None;
    }
    let joined = if fresh.is_empty() { 0 } else { coins::join(vault, &fresh) };
    if gap {
        crate::coinvault::soon("tip", 1.0);
    }
    let say = 0 < joined || gap || with(|st| {
        let say = 60.0 <= now() - st.said_at;
        if say {
            st.said_at = now();
        }
        say
    });
    if say {
        crate::trace_line(&format!("tip_get why={why} lanes={lanes} joined={joined} gap={} broken={broken} seen={}", gap as u8, seen().unwrap_or(-1)));
    }
    Some((lanes, joined, gap, broken))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_tips_bytes_read_back_and_its_seals_follow_as_ios_writes_them() {
        assert!(self_check());
        // a broken count and a broken balance are not whole; a window behind by more than thirteen links follows by itself
        let mut t = Tip { lane: vec![9; 16], seen: 0, heard: false, prev: [0; 32], links: vec![] };
        for n in 1..=3u32 {
            t.links.push(Link { n, at: n as i64, k: 0, c: 5, b: 5 * n as i64, refr: format!("pantheon:{n}"), peer: String::new(), on: String::new() });
        }
        assert!(whole(&t));
        let mut bad = t.clone();
        bad.links[2].b += 1;
        assert!(!whole(&bad), "a running balance that does not follow its move");
        bad = t.clone();
        bad.links[2].n = 7;
        assert!(!whole(&bad), "a number that skips");
        assert!(follows(Some((40, [1; 32])), &t, &chain(&t)));
        // the window of thirteen: the first link leaves into the seal the next one follows
        let d = std::env::temp_dir().join(format!("mt-tip-{}", crate::board::fresh_id()));
        let v = Vault::at(&d).unwrap();
        forget();
        let moves: Vec<Entry> = (0..15).map(|i| Entry { k: "earn".into(), c: 2, refr: format!("{}w{i}", coins::TAP), peer: None, on: None, at: 1.0 + i as f64 }).collect();
        add(&v, &moves, 30, false);
        let letter = Entry { k: "earn".into(), c: 1, refr: "mid:t1-A".into(), peer: None, on: None, at: 20.0 };
        add(&v, &[letter], 31, true);
        let t = decode(&v.get(KEY).unwrap()).unwrap();
        assert_eq!((t.links.len(), t.links[0].n, t.links[12].n, t.links[12].b, t.seen, t.heard), (13, 3, 15, 30, 31, true), "a letter's coin rides no lane");
        let mut whole_lane = Tip { prev: [0; 32], links: vec![], ..t.clone() };
        for (i, e) in moves.iter().enumerate() {
            whole_lane.links.push(Link { n: i as u32 + 1, at: (e.at * 1000.0).round() as i64, k: 0, c: 2, b: 2 * (i as i64 + 1), refr: e.refr.clone(), peer: String::new(), on: String::new() });
        }
        assert_eq!(chain(&whole_lane)[1], t.prev, "the window's seal follows the links it let go");
        assert!(follows(Some((2, chain(&whole_lane)[1])), &t, &chain(&t)));
        forget();
        let _ = std::fs::remove_dir_all(d);
    }

    /// THE OTHER DEVICE'S COINS WITHIN ONE ROUND TRIP (live, MONTANA_LIVE=1; a throwaway seed): the moves one device bore ride its tip
    /// to the nodes, and another device of the same words takes them from the tip alone, by their names, once.
    #[test]
    #[ignore]
    fn a_device_takes_the_moves_another_device_bore_from_its_tip() {
        if std::env::var("MONTANA_LIVE").is_err() {
            return;
        }
        let e: Vec<u8> = crate::crypto::random(32).unwrap();
        let k = coins::vault_keys(&e);
        let dir = || std::env::temp_dir().join(format!("mt-tip-{}", crate::board::fresh_id()));
        let (da, db) = (dir(), dir());
        let (va, vb) = (Vault::at(&da).unwrap(), Vault::at(&db).unwrap());
        forget();
        let moves = vec![
            Entry { k: "earn".into(), c: 7, refr: format!("{}w{}", coins::TAP, crate::board::fresh_id()), peer: None, on: None, at: 1_791_303_000.0 },
            Entry { k: "send".into(), c: 3, refr: format!("tx:{}", crate::board::fresh_id()), peer: Some("K".into()), on: None, at: 1_791_303_001.0 },
        ];
        add(&va, &moves, 4, true);
        assert!(0 < put(&k), "a node took the tip");
        forget(); // the other device: another process, its own lane
        let got = gather(&vb, &k, "test").expect("a node answered");
        assert_eq!((got.0, got.1, got.2, got.3), (1, 2, false, 0), "one lane, both moves, no gap");
        assert_eq!((coins::balance(&vb), seen()), (4, Some(4)));
        assert_eq!(gather(&vb, &k, "test-again").map(|g| g.1), Some(0), "a link is taken once");
        forget();
        for d in [da, db] {
            let _ = std::fs::remove_dir_all(d);
        }
    }
}
