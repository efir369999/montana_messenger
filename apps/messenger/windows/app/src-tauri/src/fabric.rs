//! THE FABRIC OF TIME (iOS MTFabric, MTFabricRules; the author's words 17.10.2026 22:24-23:18 and 18.10.2026; Canon «The level of
//! the fabric of time», «The half of the fabric», «The testimony of an exchange»): the third level of the person. A correspondent
//! this person exchanged live acts with -- words, voice, pictures, files, stickers, transfers, a game's moves, a call that wove --
//! signs, once a day, that the person's act reached them, naming the correspondence by the hash its secret gives and stating its
//! own ceiling; the person keeps what they were given. The level is H over the regular correspondents' values -- the greatest g
//! for which at least g of them, each heard in both halves of the last τ₂, stand at g or above -- and through the first τ₂ of the
//! fabric on this seed, the person's own ceiling. Byte for byte iOS's rules and their frozen vectors.

use crate::abi::*;
use crate::vault::Vault;
use crate::wire::{b64, domained, hex, unb64};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// The fabric's word on the pipe (iOS fabricMark): never a row, never receipted.
pub const MARK: &str = "\u{200B}\u{200B}FT:";
/// A call is a live act of the fabric when each side received the other's voice this long (Canon, call_seconds).
pub const CALL_SECONDS: i64 = 60;
/// τ₂ in windows of a minute, its half, and a segment (τ₂ / 14): one testimony a segment from one signer.
pub const TAU2_WINDOWS: u64 = 20_160;
pub const HALF_WINDOWS: u64 = TAU2_WINDOWS / 2;
pub const SEGMENT_WINDOWS: u64 = TAU2_WINDOWS / 14;
pub const SUITE: u16 = 1; // Canon, the suite table: row 1, ML-DSA-65
pub const SIGNATURE_LENGTH: usize = 3309;
pub const SCOPE_LENGTH: usize = 43; // 2 + 32 + 8 + 1
pub const TESTIMONY_LENGTH: usize = 3352;
pub const MOST_LEVELS: i64 = 19; // the most levels the wallet holds, which no ceiling exceeds
const KEY: &str = "fabricV2";
const WINDOW_SECONDS: u64 = 60;

/// The level of the wallet: the prefixes of π the balance reaches.
pub fn wallet_level(balance: i64) -> i64 {
    crate::coins::pi_place(balance) as i64
}
/// H: the greatest g for which at least g of the values stand at g or above.
pub fn fabric_level(values: &[i64]) -> i64 {
    let mut v = values.to_vec();
    v.sort_by(|a, b| b.cmp(a));
    let mut level = 0;
    for x in v {
        if x <= level {
            break;
        }
        level += 1;
    }
    level
}
/// The half of the last τ₂ a testimony stands in: 0 the newer, 1 the older, 2 and beyond out of the window.
pub fn half(now: u64, window: u64) -> u64 {
    now.saturating_sub(window) / HALF_WINDOWS
}
pub fn segment(window: u64) -> u64 {
    window / SEGMENT_WINDOWS
}
/// The level of a person: the lowest of the three.
pub fn level_of_person(person: i64, wallet: i64, fabric: i64) -> i64 {
    person.min(wallet).min(fabric)
}
/// THE FAR VOICE, AS THIS SIDE RECEIVED IT (iOS MTFabricRules.voiced): a stretch counts when its level stands at a voice's floor
/// (-40 dBov) or above, and only by the share of it that was received rather than made up for lost packets.
pub fn voiced(seconds: f64, energy: f64, received: f64, concealed: f64) -> f64 {
    if !(0.0 < seconds && 0.0 < received && 0.0 <= energy && 0.01 <= (energy / seconds).sqrt()) {
        return 0.0;
    }
    seconds * ((received - concealed) / received).clamp(0.0, 1.0)
}

/// A LIVE ACT (App, «The fabric of time a client weighs»): what stands in a conversation, never a receipt or a group's word; as
/// iOS 2251's code reads it, the word of the app's presence (AP:) is one too.
pub fn is_live_act(text: &str) -> bool {
    if text.starts_with(crate::groups::MARK) {
        return false;
    }
    crate::post::marks::is_row(text) || text.starts_with(crate::post::marks::LONG) || text.starts_with(crate::presence::APP)
}

/// What a correspondent signs on a live act received from the person (Canon, «The testimony of an exchange»).
#[derive(Clone, Debug, PartialEq)]
pub struct Testimony {
    pub suite: u16,
    pub addressee: [u8; 32],
    pub window: u64,
    pub ceiling: u8,
}
impl Testimony {
    /// The signed scope: every field before the signature, little-endian, in the canonical order.
    pub fn scope(&self) -> Vec<u8> {
        let mut out = self.suite.to_le_bytes().to_vec();
        out.extend_from_slice(&self.addressee);
        out.extend_from_slice(&self.window.to_le_bytes());
        out.push(self.ceiling);
        out
    }
    /// testimony_id = SHA-256("mt-exchange-testimony" || 0x00 || signed_scope).
    pub fn id(&self) -> [u8; 32] {
        domained("mt-exchange-testimony", &[&self.scope()])
    }
    /// A ceiling beyond the wallet's most levels is refused before anything else is asked.
    pub fn refused(&self) -> bool {
        MOST_LEVELS < self.ceiling as i64
    }
    /// The testimony and its signature; any other length than testimony_len is refused before it is parsed.
    pub fn parse(b: &[u8]) -> Option<(Testimony, Vec<u8>)> {
        if b.len() != TESTIMONY_LENGTH {
            return None;
        }
        let t = Testimony { suite: u16::from_le_bytes([b[0], b[1]]), addressee: b[2..34].try_into().ok()?,
                            window: u64::from_le_bytes(b[34..42].try_into().ok()?), ceiling: b[42] };
        Some((t, b[SCOPE_LENGTH..].to_vec()))
    }
}

/// The hash two people read their thirty digits from (iOS MTPipe.fingerprintMaterial): SHA-256("mt-safety" || 0 || h) 5200 times.
pub fn fingerprint_material(key: &[u8]) -> [u8; 32] {
    let mut h = domained("mt-safety", &[key]);
    for _ in 1..5200 {
        h = domained("mt-safety", &[&h]);
    }
    h
}

/// THE FROZEN VECTORS (Canon, «Frozen vectors»; iOS MTFabricRules.selfCheck), each named by the wrong reading it refuses.
pub fn self_check() -> bool {
    if wallet_level(2) != 0 || wallet_level(3) != 1 || wallet_level(313) != 2 || wallet_level(314) != 3 || wallet_level(3_141_592_653_589_793_238) != 19 {
        return false;
    }
    if fabric_level(&[]) != 0 || fabric_level(&[5]) != 1 || fabric_level(&[3, 3, 3]) != 3 || fabric_level(&[9, 1, 7, 2, 6]) != 3
        || fabric_level(&[2, 2, 2, 2, 2, 2]) != 2 {
        return false;
    }
    if HALF_WINDOWS != 10_080 || SEGMENT_WINDOWS != 1_440 || half(20_160, 10_081) != 0 || half(20_160, 10_080) != 1 || half(20_160, 0) != 2
        || half(10_080, 20_160) != 0 {
        return false;
    }
    if level_of_person(20, 5, 3) != 3 || level_of_person(7, 2, 9) != 2 || level_of_person(0, 9, 9) != 0 {
        return false;
    }
    let mut t = Testimony { suite: 1, addressee: [0x22; 32], window: 0x0102_0304_0506_0708, ceiling: 9 };
    let signature = vec![0x5Au8; SIGNATURE_LENGTH];
    let whole = [t.scope(), signature.clone()].concat();
    if t.scope().len() != SCOPE_LENGTH || t.refused() || hex(&t.id()) != "ea5deddd35b6355762867a5e744e4d3fdc76c3e72d9e70d17d5907a3b056d5da"
        || Testimony::parse(&whole) != Some((t.clone(), signature)) || Testimony::parse(&t.scope()).is_some() {
        return false;
    }
    t.ceiling = 19;
    if t.refused() {
        return false;
    }
    t.ceiling = 20;
    if !t.refused() {
        return false;
    }
    voiced(2.0, 2.0 * 0.05 * 0.05, 96_000.0, 0.0) == 2.0 && voiced(2.0, 2.0 * 0.05 * 0.05, 96_000.0, 48_000.0) == 1.0
        && voiced(2.0, 2.0 * 0.001 * 0.001, 96_000.0, 0.0) == 0.0 && voiced(2.0, 0.0, 96_000.0, 0.0) == 0.0
}

// ───────────────────────────── the fabric of this seed on this machine ─────────────────────────────

#[derive(Serialize, Deserialize, Clone)]
struct Held {
    id: String,
    key: String,
    conv: String,
    window: u64,
    ceiling: i64,
    body: String,
}
#[derive(Serialize, Deserialize, Clone)]
struct Change {
    window: u64,
    level: i64,
    digest: String,
}
#[derive(Serialize, Deserialize, Default)]
struct Kept {
    opened: Option<u64>,
    held: Vec<Held>,
    /// the hash a fingerprint is read from: the key its testimonies verify under
    keys: HashMap<String, String>,
    /// a pipe: the window this machine last left a live act on it
    sent: HashMap<String, u64>,
    /// a pipe: the segment this machine last gave a testimony on it
    given: HashMap<String, u64>,
    changes: Vec<Change>,
}

struct State {
    vault: Vault,
    dir: PathBuf,
    kept: Kept,
    level: Option<i64>,
    ceiling: Option<i64>,
    regulars: usize,
    testimonies: usize,
    grace_days: Option<i64>,
    /// a pipe's hash (the fingerprint material of its secret), derived once a life
    pairs: HashMap<String, [u8; 32]>,
    /// testimonies to sign: the pipe and the scope, signed by the walk that holds the words
    due: Vec<(String, [u8; 32], Vec<u8>)>,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

/// The person seated: their fabric read from their own vault.
pub fn start(vault: &Vault, dir: &Path) {
    let kept: Kept = vault.get(KEY).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    *STATE.lock().unwrap() = Some(State { vault: vault.clone(), dir: dir.to_path_buf(), kept, level: None, ceiling: None, regulars: 0,
                                          testimonies: 0, grace_days: None, pairs: HashMap::new(), due: vec![] });
}

fn keep(st: &State) {
    st.vault.set(KEY, serde_json::to_vec(&st.kept).unwrap_or_default().as_slice());
}

/// The network's window as this machine reads it: the nodes' second (their Date header) over sixty; 0 before a node answered.
pub fn window_now() -> u64 {
    crate::person::node_now_s().map(|s| s.max(0) as u64 / WINDOW_SECONDS).unwrap_or(0)
}

/// The level of the fabric now, for the Global Level; None until this life has read one.
pub fn level_now() -> Option<i64> {
    STATE.lock().unwrap().as_ref().and_then(|st| st.level)
}

/// THE READING (App): the ceiling, the regular correspondents and their values, the level -- again whenever what they stand on
/// moved. `person` is the person's level, `balance` the book's.
pub fn refresh(person: Option<i64>, balance: i64) {
    let mut g = STATE.lock().unwrap();
    let Some(st) = g.as_mut() else { return };
    let w = window_now();
    if w == 0 {
        return;
    }
    let mut moved = prune(&mut st.kept, w);
    if st.kept.opened.is_none() {
        st.kept.opened = Some(w);
        moved = true;
    }
    let ceil = person.map(|p| MOST_LEVELS.min(p).min(wallet_level(balance)));
    let opened = st.kept.opened.unwrap_or(w);
    let grace = w < opened + TAU2_WINDOWS;
    let regs = regulars(&st.kept, w);
    let lvl = if grace { ceil } else { Some(fabric_level(&regs.iter().map(|k| value(&st.kept, k, w)).collect::<Vec<_>>())) };
    if let Some(l) = lvl.filter(|l| st.kept.changes.last().map(|c| c.level) != Some(*l)) {
        let digest = digest(&st.kept, &regs, w);
        st.kept.changes.push(Change { window: w, level: l, digest });
        moved = true;
        write_chain(st);
        crate::trace_line(&format!("fabric_level level={l} regulars={} grace={}", regs.len(), grace as u8));
    }
    let left = ((opened + TAU2_WINDOWS) * WINDOW_SECONDS) as i64 - crate::person::node_now_s().unwrap_or(0);
    st.level = lvl;
    st.ceiling = ceil;
    st.regulars = regs.len();
    st.testimonies = st.kept.held.iter().filter(|h| half(w, h.window) < 2).count();
    st.grace_days = grace.then(|| ((left as f64 / 86_400.0).ceil() as i64).max(1));
    if moved {
        keep(st);
    }
}

/// The correspondents regular now: a testimony from them in each half of the last τ₂.
fn regulars(k: &Kept, w: u64) -> Vec<String> {
    let mut halves: HashMap<&str, [bool; 2]> = HashMap::new();
    for h in &k.held {
        let x = half(w, h.window);
        if x < 2 {
            halves.entry(&h.key).or_default()[x as usize] = true;
        }
    }
    let mut out: Vec<String> = halves.into_iter().filter(|(_, b)| b[0] && b[1]).map(|(k, _)| k.to_string()).collect();
    out.sort();
    out
}
/// A correspondent's value: the lowest ceiling they stated in the testimonies of the last τ₂.
fn value(k: &Kept, key: &str, w: u64) -> i64 {
    k.held.iter().filter(|h| h.key == key && half(w, h.window) < 2).map(|h| h.ceiling).min().unwrap_or(0)
}
/// The set a change of the level stood on: SHA-256 over the regulars' testimonies' identifiers, sorted (this machine's alone).
fn digest(k: &Kept, regs: &[String], w: u64) -> String {
    let mut ids: Vec<&str> = k.held.iter().filter(|h| regs.contains(&h.key) && half(w, h.window) < 2).map(|h| h.id.as_str()).collect();
    ids.sort();
    hex(&crate::wire::sha(&[ids.join("\n").as_bytes()]))
}
/// A testimony leaves at its half 2, a pipe's marks a τ₂ after they were made; a key leaves with its last testimony.
fn prune(k: &mut Kept, w: u64) -> bool {
    let before = (k.held.len(), k.sent.len(), k.given.len());
    k.held.retain(|h| half(w, h.window) < 2);
    k.sent.retain(|_, v| half(w, *v) < 2);
    k.given.retain(|_, v| half(w, *v * SEGMENT_WINDOWS) < 2);
    let keys: std::collections::HashSet<String> = k.held.iter().map(|h| h.key.clone()).collect();
    k.keys.retain(|key, _| keys.contains(key));
    if k.changes.len() > 200 {
        let n = k.changes.len() - 200;
        k.changes.drain(..n);
    }
    before != (k.held.len(), k.sent.len(), k.given.len())
}

/// One link at every change of the level, named by its window and the set it stood on, sealed on the one before.
fn chain(changes: &[Change]) -> Vec<crate::coins::Link> {
    let (mut out, mut prev) = (Vec::<crate::coins::Link>::new(), "0".repeat(64));
    for c in changes {
        let n = out.len() as i64 + 1;
        let at = (c.window * WINDOW_SECONDS) as i64 * 1000;
        let refr = format!("w:{}:{}", c.window, &c.digest[..16.min(c.digest.len())]);
        let hash = crate::coins::chain_seal(n, at, "level", c.level, &refr, &prev);
        out.push(crate::coins::Link { n, at, k: "level".into(), c: c.level, refr, prev: prev.clone(), hash: hash.clone() });
        prev = hash;
    }
    out
}
fn write_chain(st: &State) {
    let dir = st.dir.join("TimeChain");
    let _ = std::fs::create_dir_all(&dir);
    let body: String = chain(&st.kept.changes).iter().filter_map(|l| serde_json::to_string(l).ok()).map(|l| l + "\n").collect();
    let _ = std::fs::write(dir.join("wallet-fabric.jsonl"), body);
}

fn pair(st: &mut State, conv: &str, secret: &[u8]) -> Option<[u8; 32]> {
    if let Some(p) = st.pairs.get(conv) {
        return Some(*p);
    }
    if secret.len() != 32 {
        return None;
    }
    let p = fingerprint_material(secret);
    st.pairs.insert(conv.to_string(), p);
    Some(p)
}

/// A LIVE ACT THIS MACHINE LEFT FOR A CORRESPONDENT: the window it last spoke on the pipe.
pub fn spoke(conv: &str) {
    if conv.is_empty() || crate::groups::is_group(conv) {
        return;
    }
    let w = window_now();
    let mut g = STATE.lock().unwrap();
    let Some(st) = g.as_mut() else { return };
    if w == 0 || st.kept.sent.get(conv) == Some(&w) {
        return;
    }
    st.kept.sent.insert(conv.to_string(), w);
    keep(st);
}

/// A LIVE ACT CAME FROM A CORRESPONDENT: when this machine spoke to them within the last half of τ₂ and gave them no testimony
/// this segment, a testimony is made ready -- the window it heard them in and its own ceiling -- for the walk to sign and give by
/// the pair's own road. A person who only writes is given none.
pub fn heard(conv: &str, secret: &[u8]) {
    if conv.is_empty() || crate::groups::is_group(conv) {
        return;
    }
    let w = window_now();
    let mut g = STATE.lock().unwrap();
    let Some(st) = g.as_mut() else { return };
    let Some(s) = st.kept.sent.get(conv).copied() else { return };
    if w == 0 || half(w, s) != 0 {
        return;
    }
    if st.kept.given.get(conv) == Some(&segment(w)) {
        return crate::trace_line("fabric_tx given this segment"); // one a segment to one correspondent (Canon)
    }
    let Some(named) = pair(st, conv, secret) else { return };
    let Some(c) = st.ceiling else { return crate::trace_line("fabric_tx held: this life has not read its own levels yet") };
    let t = Testimony { suite: SUITE, addressee: named, window: w, ceiling: c.clamp(0, 255) as u8 };
    st.kept.given.insert(conv.to_string(), segment(w));
    keep(st);
    st.due.push((conv.to_string(), named, t.scope()));
}

/// THE KEY THIS PERSON SIGNS A CORRESPONDENCE'S TESTIMONIES WITH (iOS MTFabric.signer): HKDF-Expand(master_seed, "mt-fabric-key"
/// || 0x00 || the correspondence's hash) into ML-DSA-65 -- one on every device of the words, another in every correspondence.
pub fn signer(master: &[u8], pair: &[u8; 32]) -> Option<(Vec<u8>, Vec<u8>)> {
    let role = [b"mt-fabric-key".as_slice(), &[0], pair].concat();
    let seed = crate::seed::role_of_master(master, &role)?;
    let (mut pk, mut sk) = (vec![0u8; MT_MLDSA_PUBKEY_SIZE], vec![0u8; MT_MLDSA_SECKEY_SIZE]);
    // SAFETY: a 32-byte seed and buffers of the core's sizes
    let rc = unsafe { mt_mldsa_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) };
    (rc == MT_OK).then_some((pk, sk))
}

pub fn has_due() -> bool {
    STATE.lock().unwrap().as_ref().is_some_and(|st| !st.due.is_empty())
}

/// The testimonies made ready, signed by the walk that holds the words and given as the fabric's word: (pipe, word).
pub fn signed_due(words: &str) -> Vec<(String, String)> {
    let due: Vec<_> = STATE.lock().unwrap().as_mut().map(|st| std::mem::take(&mut st.due)).unwrap_or_default();
    if due.is_empty() {
        return vec![];
    }
    let Some(master) = crate::seed::master_of(words) else { return vec![] };
    due.into_iter().filter_map(|(conv, named, scope)| {
        let (pk, mut sk) = signer(&master, &named)?;
        let mut sig = vec![0u8; MT_MLDSA_SIG_SIZE];
        // SAFETY: the secret key, the scope and a signature buffer of the core's size
        let rc = unsafe { mt_sign(sk.as_ptr(), scope.as_ptr(), scope.len(), sig.as_mut_ptr()) };
        sk.fill(0);
        if rc != MT_OK {
            crate::trace_line("fabric_tx FAIL the seed's key did not sign");
            return None;
        }
        let body = json!({ "t": b64(&[scope, sig].concat()), "k": b64(&pk) });
        crate::trace_line("fabric_tx signed");
        Some((conv, format!("{MARK}{body}")))
    }).collect()
}

fn verify(pk: &[u8], msg: &[u8], sig: &[u8]) -> bool {
    pk.len() == MT_MLDSA_PUBKEY_SIZE && sig.len() == MT_MLDSA_SIG_SIZE
        // SAFETY: a public key and a signature of the core's sizes, the message's own length
        && unsafe { mt_verify(pk.as_ptr(), msg.as_ptr(), msg.len(), sig.as_ptr()) } == MT_OK
}

/// THE FABRIC'S WORD CAME (Canon, «Invariants of a testimony»): it counts only once every question is answered, in this order --
/// its length, what it states of itself, that it names this correspondence, that its window stands no more than one window past
/// this machine's reading and inside the last τ₂, that its signature holds under the key it came with. One a segment from one key
/// is kept, the one stating the lower ceiling.
pub fn received(payload: &str, conv: &str, secret: &[u8]) {
    let refuse = |why: &str| crate::trace_line(&format!("fabric_refused why={why}"));
    let Ok(o) = serde_json::from_str::<Value>(payload) else { return refuse("unreadable") };
    if o.get("t").is_none() {
        return; // a word of an older build: a ceiling and an estimate, which this fabric does not weigh
    }
    let (Some(body), Some(key)) = (o["t"].as_str().and_then(unb64), o["k"].as_str().and_then(unb64)) else { return refuse("unreadable") };
    let Some((t, sig)) = Testimony::parse(&body) else { return refuse("length") };
    if t.suite != SUITE {
        return refuse("suite");
    }
    if t.refused() {
        return refuse("ceilingBeyondTheWallet");
    }
    let w = window_now();
    let mut g = STATE.lock().unwrap();
    let Some(st) = g.as_mut() else { return };
    if pair(st, conv, secret) != Some(t.addressee) {
        drop(g);
        return refuse("addressee");
    }
    if t.window > w + 1 {
        drop(g);
        return refuse("window");
    }
    if half(w, t.window) >= 2 {
        return; // older than the window: it counts nothing
    }
    if !verify(&key, &t.scope(), &sig) {
        drop(g);
        return refuse("signature");
    }
    let id = hex(&t.id());
    if st.kept.held.iter().any(|h| h.id == id) {
        return;
    }
    let signer = hex(&fingerprint_material(&key));
    let seg = segment(t.window);
    if let Some(i) = st.kept.held.iter().position(|h| h.key == signer && segment(h.window) == seg) {
        if t.ceiling as i64 >= st.kept.held[i].ceiling {
            return;
        }
        st.kept.held.remove(i);
    }
    st.kept.held.push(Held { id, key: signer.clone(), conv: conv.to_string(), window: t.window, ceiling: t.ceiling as i64, body: b64(&body) });
    st.kept.keys.insert(signer, b64(&key));
    keep(st);
    crate::trace_line(&format!("fabric_rx ceiling={} half={}", t.ceiling, half(w, t.window)));
}

/// The fabric as the TimeChain page shows it.
pub fn shown() -> Value {
    let g = STATE.lock().unwrap();
    let Some(st) = g.as_ref() else { return json!({}) };
    let links = chain(&st.kept.changes);
    json!({ "level": st.level, "ceiling": st.ceiling, "regulars": st.regulars, "testimonies": st.testimonies, "graceDays": st.grace_days,
            "links": links.len(), "head": links.last().map(|l| l.hash.clone()).unwrap_or_else(|| "0".repeat(64)) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_fabrics_rules_hold_their_frozen_vectors() {
        assert!(self_check());
        // the regulars: a key heard in both halves counts, one heard in one half does not
        let mut k = Kept::default();
        let w = 40_000u64;
        for (key, win, c) in [("a", w - 10, 5), ("a", w - 15_000, 7), ("b", w - 20, 9), ("c", w - 30_000, 9)] {
            k.held.push(Held { id: format!("{key}{win}"), key: key.into(), conv: "x".into(), window: win, ceiling: c, body: String::new() });
        }
        assert_eq!(regulars(&k, w), vec!["a".to_string()]);
        assert_eq!(value(&k, "a", w), 5, "the lowest ceiling of the window");
        assert!(prune(&mut k, w), "a testimony τ₂ old leaves");
        assert_eq!(k.held.len(), 3);
        // a change of the level is a sealed link
        let c = chain(&[Change { window: 100, level: 2, digest: "ab".repeat(32) }, Change { window: 200, level: 3, digest: "cd".repeat(32) }]);
        assert_eq!((c[0].refr.as_str(), c[1].prev.clone()), ("w:100:abababababababab", c[0].hash.clone()));
    }
}
