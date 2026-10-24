//! THE COPY KEPT BY THE PEOPLE ONE WRITES TO (iOS MTKeeping; the author's words 08.10.2026: «restore by the words fully, byte
//! for byte», «restore over the network from the phones, as it should be»). The copy is the one this machine seals under the
//! words (history::make_copy). It is cut by the erasure code of a delivery into sixteen slots; the keepers -- correspondents
//! whose person allows keeping -- stand on a ring, each holding the slots of its place and of the next; every keeper holds,
//! beside its share, the head of the share, the seal of that head under a branch of the words it never sees, and the secret
//! of its slot. A machine that opens the words derives the secret of every slot, calls in each slot's pipe, checks every seal
//! and builds the copy back. Every road is one a letter already rides: the keeping words ride the correspondence (KP:), the
//! parts ride the cargo road, a call and its answer ride the box of a slot's pipe. And every correspondent gives back, when
//! asked, the conversation it holds with the one who restores («back» / «given»).

use crate::book::{mint_mid, Msg};
use crate::history::{self, Record};
use crate::post::{marks, Desk};
use crate::wire::{self, b64, hex, sha, unb64, unhex};
use crate::{doors, groups, seed};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

/// The one token of the keeping's service words (iOS keepMark), JSON with «w».
pub const MARK: &str = "\u{200B}\u{200B}KP:";
/// A given-back row's name on this machine, never on the wire (iOS MTRestoredMid.given).
pub const GIVEN: &str = "given:";

/// THE ERASURE CODE OF A DELIVERY, as Canon states it: Reed-Solomon over the field of 256 elements with the modulus 0x11D, the
/// Cauchy matrix cauchy[i][j] = inverse((erasure_data + i) XOR j), the body blocks first and the parity after them.
pub mod code {
    use sha2::{Digest, Sha256};
    use std::sync::OnceLock;

    pub const CHUNK: usize = 868; // Canon: chunk_bytes
    pub const GROUP: usize = 16; // Canon: erasure_group
    pub const DATA: usize = 12; // Canon: erasure_data
    pub const PARITY: usize = GROUP - DATA;

    /// A product in the field without a branch on either operand (mt-wire, erasure.rs).
    fn mul(a: u8, b: u8) -> u8 {
        let (mut product, mut left, mut right) = (0u8, a, b);
        for _ in 0..8 {
            product ^= left & 0u8.wrapping_sub(right & 1);
            let over = 0u8.wrapping_sub(left >> 7);
            left = (left << 1) ^ (0x1D & over);
            right >>= 1;
        }
        product
    }
    /// The whole table of the field, walked once: a product is then one read.
    fn table() -> &'static [u8] {
        static T: OnceLock<Vec<u8>> = OnceLock::new();
        T.get_or_init(|| {
            let mut t = vec![0u8; 65536];
            for a in 0..256usize {
                for b in 0..256usize {
                    t[(a << 8) | b] = mul(a as u8, b as u8);
                }
            }
            t
        })
    }
    fn inverse(a: u8) -> Option<u8> {
        let t = table();
        (a != 0).then(|| (1..=255u8).find(|&b| t[((a as usize) << 8) | b as usize] == 1)).flatten()
    }
    fn cauchy() -> &'static [[u8; DATA]; PARITY] {
        static C: OnceLock<[[u8; DATA]; PARITY]> = OnceLock::new();
        C.get_or_init(|| {
            let mut c = [[0u8; DATA]; PARITY];
            for (i, row) in c.iter_mut().enumerate() {
                for (j, x) in row.iter_mut().enumerate() {
                    *x = inverse(((DATA + i) ^ j) as u8).unwrap_or(0);
                }
            }
            c
        })
    }

    /// The parity blocks of one group: every body block scaled by its coefficient and summed, byte by byte.
    pub fn parity(blocks: &[Vec<u8>]) -> Option<Vec<Vec<u8>>> {
        let width = blocks.first()?.len();
        if blocks.len() != DATA || blocks.iter().any(|b| b.len() != width) {
            return None;
        }
        let (t, c) = (table(), cauchy());
        let mut out = vec![vec![0u8; width]; PARITY];
        for (i, o) in out.iter_mut().enumerate() {
            for (j, b) in blocks.iter().enumerate() {
                let row = (c[i][j] as usize) << 8;
                for (x, v) in o.iter_mut().zip(b) {
                    *x ^= t[row | *v as usize];
                }
            }
        }
        Some(out)
    }

    /// Any twelve cells of a group give its twelve body blocks, and no fewer: the rows they stand for are inverted in the field
    /// and applied to what they carry. Twelve body cells in hand are the body itself.
    pub fn reconstruct(present: &[(usize, Vec<u8>)]) -> Option<Vec<Vec<u8>>> {
        let mut seen = std::collections::HashSet::new();
        let mut taken: Vec<(usize, &Vec<u8>)> = vec![];
        for (p, b) in present {
            if *p < GROUP && seen.insert(*p) {
                taken.push((*p, b));
                if taken.len() == DATA {
                    break;
                }
            }
        }
        let width = taken.first()?.1.len();
        if taken.len() != DATA || taken.iter().any(|(_, b)| b.len() != width) {
            return None;
        }
        if taken.iter().all(|(p, _)| *p < DATA) {
            let mut out = vec![vec![]; DATA];
            for (p, b) in &taken {
                out[*p] = (*b).clone();
            }
            return Some(out);
        }
        let (t, c) = (table(), cauchy());
        let mut m: Vec<[u8; DATA]> = taken.iter().map(|(p, _)| {
            if *p < DATA { let mut r = [0u8; DATA]; r[*p] = 1; r } else { c[*p - DATA] }
        }).collect();
        let mut inv: Vec<[u8; DATA]> = (0..DATA).map(|r| { let mut x = [0u8; DATA]; x[r] = 1; x }).collect();
        for col in 0..DATA {
            let piv = (col..DATA).find(|&r| m[r][col] != 0)?;
            let iv = inverse(m[piv][col])?;
            m.swap(col, piv);
            inv.swap(col, piv);
            let s = (iv as usize) << 8;
            for x in 0..DATA {
                m[col][x] = t[s | m[col][x] as usize];
                inv[col][x] = t[s | inv[col][x] as usize];
            }
            for r in 0..DATA {
                if r != col && m[r][col] != 0 {
                    let f = (m[r][col] as usize) << 8;
                    for x in 0..DATA {
                        m[r][x] ^= t[f | m[col][x] as usize];
                        inv[r][x] ^= t[f | inv[col][x] as usize];
                    }
                }
            }
        }
        let mut out = vec![vec![0u8; width]; DATA];
        for (i, o) in out.iter_mut().enumerate() {
            for (j, (_, b)) in taken.iter().enumerate() {
                if inv[i][j] != 0 {
                    let row = (inv[i][j] as usize) << 8;
                    for (x, v) in o.iter_mut().zip(b.iter()) {
                        *x ^= t[row | *v as usize];
                    }
                }
            }
        }
        Some(out)
    }

    /// THE CUT (Canon «The keeping of a copy»): the container cut into blocks of chunk_bytes, grouped twelve at a time, every
    /// group coded into sixteen cells, and cell p of every group laid into the share of slot p mod n, ascending.
    pub struct Cut {
        pub length: u64,
        pub digest: [u8; 32],
        pub shares: Vec<Vec<u8>>,
        pub digests: Vec<[u8; 32]>,
    }
    pub fn cut(container: &[u8], n: usize) -> Option<Cut> {
        if ![4, 8, 16].contains(&n) || container.is_empty() {
            return None;
        }
        let mut shares = vec![Vec::new(); n];
        for group in container.chunks(DATA * CHUNK) {
            let blocks: Vec<Vec<u8>> = (0..DATA).map(|j| {
                let mut b = vec![0u8; CHUNK];
                let lo = j * CHUNK;
                if lo < group.len() {
                    let piece = &group[lo..group.len().min(lo + CHUNK)];
                    b[..piece.len()].copy_from_slice(piece);
                }
                b
            }).collect();
            let par = parity(&blocks)?;
            for (p, cell) in blocks.iter().chain(par.iter()).enumerate() {
                shares[p % n].extend_from_slice(cell);
            }
        }
        let digests = shares.iter().map(|s| Sha256::digest(s).into()).collect();
        Some(Cut { length: container.len() as u64, digest: Sha256::digest(container).into(), shares, digests })
    }

    /// THE COPY BUILT BACK from the shares in hand: for every group, the cells of each share read where the rule of positions
    /// laid them, any twelve rebuild the body, the last group cut at the container's own length. None when a group cannot stand.
    pub fn rebuild(parts: &[(usize, usize, &[u8])], length: u64) -> Option<Vec<u8>> {
        let n = parts.first()?.1;
        if ![4, 8, 16].contains(&n) || parts.iter().any(|p| p.1 != n || p.0 >= n) || length == 0 {
            return None;
        }
        let per = GROUP / n;
        let blocks = length.div_ceil(CHUNK as u64);
        let groups = blocks.div_ceil(DATA as u64) as usize;
        let mut out = Vec::with_capacity(length as usize);
        for g in 0..groups {
            let mut present: Vec<(usize, Vec<u8>)> = vec![];
            for (slot, _, share) in parts {
                let lo = g * per * CHUNK;
                let Some(d) = share.get(lo..lo + per * CHUNK) else { continue };
                for c in 0..per {
                    present.push((slot + c * n, d[c * CHUNK..(c + 1) * CHUNK].to_vec()));
                }
            }
            for b in reconstruct(&present)? {
                let take = (length - out.len() as u64).min(CHUNK as u64) as usize;
                out.extend_from_slice(&b[..take]);
                if out.len() as u64 == length {
                    break;
                }
            }
        }
        (out.len() as u64 == length).then_some(out)
    }

    /// THE CANON'S VECTORS OF THE WIRE, and a walk the frozen bytes cannot make alone (a second body of counting bytes rebuilt
    /// across a loss that takes three parity cells and one body cell).
    pub fn agrees() -> bool {
        let body: Vec<Vec<u8>> = (0..DATA).map(|j| vec![0xA0 + j as u8; CHUNK]).collect();
        let Some(par) = parity(&body) else { return false };
        let heads: Vec<String> = par.iter().map(|p| super::hex(&p[..4])).collect();
        if heads != ["a5a5a5a5", "acacacac", "b7b7b7b7", "bebebebe"] {
            return false;
        }
        let mut h = Sha256::new();
        for p in &par {
            h.update(p);
        }
        if super::hex(&h.finalize()) != "8963024273fc41fdf9afe063f3be77e7fbc312a7d8ede4f96a7fd99dd4fd0e69" {
            return false;
        }
        let whole: Vec<Vec<u8>> = body.iter().chain(par.iter()).cloned().collect();
        let lost = [0, 5, 7, 11];
        let left: Vec<(usize, Vec<u8>)> = whole.iter().cloned().enumerate().filter(|(i, _)| !lost.contains(i)).collect();
        if reconstruct(&left).as_ref() != Some(&body) {
            return false;
        }
        let counting: Vec<Vec<u8>> = (0..DATA).map(|j| (0..64).map(|x| ((j * 64 + x) % 251) as u8).collect()).collect();
        let Some(cp) = parity(&counting) else { return false };
        let loss = [3, 12, 13, 15];
        let left: Vec<(usize, Vec<u8>)> = counting.iter().chain(cp.iter()).cloned().enumerate().filter(|(i, _)| !loss.contains(i)).collect();
        reconstruct(&left).as_ref() == Some(&counting)
    }
}

/// THE QUANTITIES OF KEEPING, as Canon fixes them: the secret of a slot, the keeping key, the seal of a share's head.
pub mod derive {
    pub const SLOTS: usize = 16;

    /// slot_secret(k) = HKDF-Expand(master_seed, "mt-keep-slot" || 0x00 || k_1B, 32)
    pub fn slot_secret(master: &[u8], k: usize) -> Option<Vec<u8>> {
        (k < SLOTS).then(|| crate::seed::role_of_master(master, &[b"mt-keep-slot".as_slice(), &[0, k as u8]].concat())).flatten()
    }
    /// keep_key = HKDF-Expand(master_seed, "mt-keep-key", 32): it seals every head and is handed to nobody.
    pub fn keep_key(master: &[u8]) -> Option<Vec<u8>> {
        crate::seed::role_of_master(master, b"mt-keep-key")
    }
    /// light_secret = HKDF-Expand(master_seed, "mt-keep-light", 32): the pipe of light.
    pub fn light_secret(master: &[u8]) -> Option<Vec<u8>> {
        crate::seed::role_of_master(master, b"mt-keep-light")
    }

    /// head = k_1B || n_1B || generation_8B_LE || length_8B_LE || SHA-256(container) || SHA-256(share): eighty-two bytes.
    #[derive(Clone, Debug, PartialEq, Eq)]
    pub struct Head {
        pub slot: usize,
        pub n: usize,
        pub generation: u64,
        pub length: u64,
        pub copy: [u8; 32],
        pub share: [u8; 32],
    }
    impl Head {
        pub const BYTES: usize = 82;
        pub fn bytes(&self) -> Vec<u8> {
            let mut d = vec![self.slot as u8, self.n as u8];
            d.extend_from_slice(&self.generation.to_le_bytes());
            d.extend_from_slice(&self.length.to_le_bytes());
            d.extend_from_slice(&self.copy);
            d.extend_from_slice(&self.share);
            d
        }
        pub fn parse(b: &[u8]) -> Option<Head> {
            if b.len() != Self::BYTES || ![4, 8, 16].contains(&(b[1] as usize)) || b[0] >= b[1] {
                return None;
            }
            Some(Head {
                slot: b[0] as usize,
                n: b[1] as usize,
                generation: u64::from_le_bytes(b[2..10].try_into().ok()?),
                length: u64::from_le_bytes(b[10..18].try_into().ok()?),
                copy: b[18..50].try_into().ok()?,
                share: b[50..82].try_into().ok()?,
            })
        }
    }
    /// seal = SHA-256("mt-keep-seal" || 0x00 || keep_key || head), by the set's one composition.
    pub fn seal(key: &[u8], head: &Head) -> [u8; 32] {
        crate::wire::domained("mt-keep-seal", &[key, &head.bytes()])
    }

    /// THE CANON'S VECTORS OF KEEPING, from the master seed of sixty-four distinct bytes.
    pub fn agrees() -> bool {
        use crate::wire::hex;
        let master: Vec<u8> = (0..64).collect();
        let s = |k| slot_secret(&master, k).map(|x| hex(&x)).unwrap_or_default();
        let (Some(s3), Some(key), Some(light)) = (slot_secret(&master, 3), keep_key(&master), light_secret(&master)) else { return false };
        let backwards: Vec<u8> = master.iter().rev().copied().collect();
        let head = Head { slot: 2, n: 8, generation: 0x1112131415161718, length: 0x0102030405060708,
                          copy: (0x20..=0x3F).collect::<Vec<u8>>().try_into().unwrap(), share: (0x40..=0x5F).collect::<Vec<u8>>().try_into().unwrap() };
        s(0) == "f57057fdd34a297a072f161d54105f98ec23cbbaf6229662b36efb9ae4aaa9d7"
            && s(1) == "c534306aa283d19c8e83f392bda37a7e59b7ccd7868b8df455bb9b6716e1ab91"
            && s(15) == "4573fb5ad5dc3b579049f304cc95cf5f3765ceaf07caab730d986c034788edab"
            && hex(&crate::wire::pipe_tag(&s3, 1000)) == "ae67484d6abdb555a43159fc9386d753"
            && hex(&key) == "9945bec54d8f26ab7859b3e6eb886456ff529fd2637aa2650626b3595e88970c"
            && hex(&light) == "23d9bfa1a0151598ea710a15492cb9f8fcb46e5c86d39ba0e8824a69511a3776"
            && light_secret(&backwards).map(|x| hex(&x)).as_deref() == Some("8d14528b640e1d7b114c2d299cf85f4ba7813a2308255dfba6025f01e4f288b9")
            && hex(&crate::wire::pipe_tag(&light, 1000)) == "7b957934998d5c0ad69415e43616020c"
            && Head::parse(&head.bytes()).as_ref() == Some(&head)
            && hex(&seal(&key, &head)) == "80b0b97f66a8ef64fce6d692935a82b37bf978c0e215cd8b190bb7a1100475ae"
    }
}

/// THE RING OF KEEPERS (Network «The keepers are correspondents, and they stand on a ring»): every correspondent that allows
/// keeping, two at each position at most, and every share at two neighbouring positions.
pub mod ring {
    use super::code::GROUP;
    pub const MOST: usize = 2 * GROUP;
    /// The slots the keeper at place i of m keeps: those whose position, k mod q, is its own or the next one around the ring.
    pub fn slots(place: usize, of: usize) -> Vec<usize> {
        let q = of.min(GROUP);
        if q == 0 || place >= of {
            return vec![];
        }
        let j = place % q;
        (0..GROUP).filter(|k| k % q == j || k % q == (j + 1) % q).collect()
    }
    pub fn agrees() -> bool {
        slots(0, 4) == [0, 1, 4, 5, 8, 9, 12, 13]
            && slots(3, 4) == [0, 3, 4, 7, 8, 11, 12, 15]
            && slots(0, 1) == (0..16).collect::<Vec<_>>()
            && slots(1, 2) == (0..16).collect::<Vec<_>>()
            && slots(16, 20) == [0, 1]
            && slots(15, 16) == [0, 15]
    }
}

/// The keeping starts only where the Canon's vectors hold: a code or a derivation off by one byte would scatter parts nobody
/// can rebuild.
pub fn agrees() -> bool {
    static A: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *A.get_or_init(|| code::agrees() && derive::agrees() && ring::agrees())
}

// ── the person's choices (settings of this machine, in its vault) ──
const MINE: &str = "keepMine"; // my copy is kept by the people I write to (on by default)
const OTHERS: &str = "keepOthers"; // this machine keeps parts for the people who write to me (on by default)
const TOLD: &str = "keepTold"; // the person was told what each keeper learns, and chose
const BUDGET_MB: u64 = 1024; // what this machine keeps for others
const OWNER: &str = "keepOwner";
const HELD: &str = "keepHeld";
const ASKED_BACK: &str = "keepBackAsked";

fn flag(d: &Desk, name: &str, default: bool) -> bool {
    d.vault.get(name).map(|b| b == b"1").unwrap_or(default)
}
pub fn mine(d: &Desk) -> bool {
    flag(d, MINE, true)
}
pub fn others(d: &Desk) -> bool {
    flag(d, OTHERS, true)
}
/// The same consent read from the vault alone (iOS MTKeeping.others): the copy of the network's chains asks it.
pub fn others_in(vault: &crate::vault::Vault) -> bool {
    vault.get(OTHERS).map(|b| b == b"1").unwrap_or(true)
}
pub fn told(d: &Desk) -> bool {
    flag(d, TOLD, false)
}

/// A keeper of the ring holds the slots of its place and of the next; it is whole once it said «held» for every one.
#[derive(Serialize, Deserialize, Clone, Default, Debug, PartialEq)]
pub struct Keeper {
    pub slot: usize,
    pub held: bool,
    #[serde(default)]
    pub slots: Vec<usize>,
    #[serde(default)]
    pub held_slots: Vec<usize>,
}
/// The owner's side: the copy the keepers hold, a renewal asking, who said yes, the ring.
#[derive(Serialize, Deserialize, Clone, Default, Debug)]
pub struct Owner {
    pub generation: u64,
    pub asking: Option<u64>,
    pub asked_at: i64,
    pub yes: Vec<String>,
    pub n: usize,
    pub keepers: BTreeMap<String, Keeper>,
    pub renewed_at: i64,
    pub short: bool,
    pub tried_at: i64,
}
/// The keeper's side: one share of one owner's copy, under the name of its correspondence and its slot.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Held {
    pub slot: usize,
    pub n: usize,
    pub secret: String,
    pub head: String,
    pub seal: String,
    pub bytes: u64,
    pub at: i64,
    #[serde(default)]
    pub answered_at: i64,
    /// the owner's own road of this part on the nodes, and when it was laid: an answer within the pieces' week rides it whole
    #[serde(default)]
    pub road: Option<Value>,
    #[serde(default)]
    pub road_at: i64,
}

fn now_s() -> i64 {
    wire::now_ms() / 1000
}
fn owner(d: &Desk) -> Owner {
    d.vault.get(OWNER).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}
fn save_owner(d: &Desk, o: &Owner) {
    d.vault.set(OWNER, serde_json::to_vec(o).unwrap_or_default().as_slice());
}
pub fn held(d: &Desk) -> BTreeMap<String, Held> {
    d.vault.get(HELD).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}
fn save_held(d: &Desk, h: &BTreeMap<String, Held>) {
    d.vault.set(HELD, serde_json::to_vec(h).unwrap_or_default().as_slice());
}
fn key_of(conv: &str, k: usize) -> String {
    format!("{conv}#{k}")
}
fn conv_of(key: &str) -> &str {
    key.split('#').next().unwrap_or("")
}
fn generation(h: &Held) -> u64 {
    unhex(&h.head).and_then(|b| derive::Head::parse(&b)).map_or(0, |h| h.generation)
}

/// THE PARTS THIS MACHINE KEEPS FOR OTHERS lie in a folder of their own, beside the vault, never in this person's copy:
/// they are another person's, and they go back only to that person's words.
fn part_path(d: &Desk, key: &str) -> Option<std::path::PathBuf> {
    let dir = d.vault.dir().parent()?.join("keeping");
    std::fs::create_dir_all(&dir).ok()?;
    Some(dir.join(format!("{}.keep", hex(&sha(&[key.as_bytes()])[..16]))))
}

/// A keeping word into a correspondence: durable and silent, never a row, never mirrored.
fn say(d: &Desk, conv: &str, o: &Value) {
    d.word_kept(conv, &mint_mid(), &format!("{MARK}{o}"));
}
fn word(text: &str) -> Option<Map<String, Value>> {
    serde_json::from_str::<Value>(text.strip_prefix(MARK)?).ok()?.as_object().cloned()
}
fn trace(line: &str) {
    if std::env::var_os("MONTANA_TRACE").is_none() {
        return;
    }
    if std::env::var_os("MONTANA_DATA_DIR").is_none() {
        return;
    }
    let Some(dir) = crate::seats::here().map(|h| h.folder.clone()) else { return };
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(dir.join("trace.log")) {
        let _ = writeln!(f, "{} keep {line}", wire::now_ms());
    }
}

// ── the jobs: a word heard in a correspondence, or a call heard in a slot's pipe, done by the keeping's own walk; each
// person's own (a check holds several people in one process) ──
pub enum Job {
    Word(String, Map<String, Value>),
    Call(String),
}
static JOBS: Mutex<Vec<(String, Job)>> = Mutex::new(Vec::new());

/// A keeping word landed in a correspondence (post.rs place): never a row, done by the keeping's walk.
pub fn heard(me: &str, conv: &str, text: &str) {
    if !agrees() {
        return;
    }
    if let Some(o) = word(text) {
        trace(&format!("word w={} conv={}", o.get("w").and_then(|v| v.as_str()).unwrap_or("?"), &conv[..conv.len().min(10)]));
        JOBS.lock().unwrap().push((me.to_string(), Job::Word(conv.to_string(), o)));
    }
}
/// The pipes of the slots this machine holds, read in the box beside every correspondence (post.rs fetch_once).
pub fn listening(d: &Desk) -> Vec<(String, Vec<u8>)> {
    if !agrees() {
        return vec![];
    }
    held(d).into_iter().filter_map(|(k, h)| Some((k, unb64(&h.secret).filter(|s| s.len() == 32)?))).collect()
}
/// A row of the box under the pipe of a slot is this module's own: a call is answered, and the row is in hand either way.
pub fn takes(me: &str, key: &str, plain: &[u8]) -> bool {
    let f = wire::fields(plain, 0, 2);
    if word(&f[1]).and_then(|o| o.get("w").and_then(|v| v.as_str()).map(str::to_string)).as_deref() == Some("call") {
        JOBS.lock().unwrap().push((me.to_string(), Job::Call(key.to_string())));
    }
    true
}

/// What the keeping's walk tells the window: a first part held for someone (the person is told), the state moved.
#[derive(Default)]
pub struct Moved {
    pub told: Vec<(String, u64)>,
    pub changed: bool,
}

/// THE KEEPING'S WALK: the jobs heard, then the owner's rhythm. `words` -- the person's (none: nothing of the owner's side).
pub fn work(d: &Desk, words: Option<&str>, card: Option<Record>) -> Moved {
    let mut out = Moved::default();
    if !agrees() {
        return out;
    }
    let jobs: Vec<Job> = {
        let mut all = JOBS.lock().unwrap();
        let (mine, rest): (Vec<_>, Vec<_>) = std::mem::take(&mut *all).into_iter().partition(|(me, _)| *me == d.twin);
        *all = rest;
        mine.into_iter().map(|(_, j)| j).collect()
    };
    for j in jobs {
        match j {
            Job::Word(conv, o) => match o.get("w").and_then(|v| v.as_str()).unwrap_or("") {
                "ask" => answer_ask(d, &conv, &o),
                "yes" => out.changed |= took_yes(d, words, card.clone(), &conv, &o),
                "part" => {
                    if let Some(bytes) = take_part(d, &conv, &o) {
                        out.told.push((conv.clone(), bytes));
                        out.changed = true;
                    }
                }
                "held" => out.changed |= took_held(d, &conv, &o),
                "release" => out.changed |= drop_parts(d, &conv),
                "back" => answer_back(d, &conv, &o),
                "given" => out.changed |= take_given(d, &conv, &o) > 0,
                _ => {}
            },
            Job::Call(key) => answer_call(d, &key),
        }
    }
    if let Some(w) = words {
        out.changed |= tick(d, w, card);
    }
    out
}

// ── the owner ──

/// The people I write to, the latest first: a correspondence of a person -- never a group, a closed or blocked one.
fn people(d: &Desk) -> Vec<String> {
    let mut v: Vec<(i64, String)> = d.book.all().into_iter()
        .filter(|c| !groups::is_group(&c.reference) && !c.blocked && !c.hidden && c.reference != d.twin && !doors::barred(&c.reference))
        .filter(|c| d.book.secret(&c.reference).is_some())
        .map(|c| (c.msgs.iter().map(|m| m.at).max().unwrap_or(0), c.reference))
        .collect();
    v.sort_by(|a, b| b.0.cmp(&a.0));
    v.into_iter().map(|(_, r)| r).collect()
}

pub fn set_mine(d: &Desk, on: bool) {
    d.vault.set(MINE, if on { b"1" } else { b"0" });
    d.vault.set(TOLD, b"1"); // the switch stands under its own explanation
    let o = owner(d);
    if on {
        save_owner(d, &Owner { renewed_at: 0, tried_at: 0, ..o });
    } else {
        for conv in o.keepers.keys() {
            say(d, conv, &json!({ "w": "release" }));
        }
        save_owner(d, &Owner { generation: o.generation, ..Default::default() });
    }
}
pub fn set_others(d: &Desk, on: bool) {
    d.vault.set(OTHERS, if on { b"1" } else { b"0" });
    if !on {
        let convs: Vec<String> = held(d).keys().map(|k| conv_of(k).to_string()).collect();
        for c in convs {
            drop_parts(d, &c);
        }
    }
}

/// THE OWNER'S RHYTHM: a renewal is due a day after the last; it asks the people I write to, waits ten minutes for one yes at
/// least (a full ring goes at once), and an hour without one leaves the copy where it stands until tomorrow.
fn tick(d: &Desk, words: &str, card: Option<Record>) -> bool {
    if !mine(d) || !told(d) {
        return false;
    }
    let now = now_s();
    let mut o = owner(d);
    if let Some(g) = o.asking {
        // MONTANA_KEEP_WAIT (a check's own) shortens the ten minutes a renewal waits for more yeses
        let wait = std::env::var("MONTANA_KEEP_WAIT").ok().and_then(|w| w.parse::<i64>().ok()).unwrap_or(600);
        if o.yes.len() >= ring::MOST || (!o.yes.is_empty() && now - o.asked_at >= wait) {
            return renew(d, words, g, card);
        }
        if now - o.asked_at >= 3600 {
            o.short = true;
            o.asking = None;
            o.yes.clear();
            o.renewed_at = now;
            save_owner(d, &o);
            trace("ask: nobody said yes in an hour");
            return true;
        }
        return false;
    }
    if now - o.renewed_at.max(o.tried_at) < 86_400 {
        return false;
    }
    let people: Vec<String> = people(d).into_iter().take(2 * ring::MOST).collect();
    if people.is_empty() {
        o.short = true;
        o.renewed_at = now;
        save_owner(d, &o);
        trace("ask: nobody to ask");
        return true;
    }
    let g = o.generation + 1;
    o.asking = Some(g);
    o.asked_at = now;
    o.yes.clear();
    save_owner(d, &o);
    for conv in &people {
        say(d, conv, &json!({ "w": "ask", "g": g }));
    }
    trace(&format!("ask g={g} people={}", people.len()));
    true
}

fn took_yes(d: &Desk, words: Option<&str>, card: Option<Record>, conv: &str, o: &Map<String, Value>) -> bool {
    let mut own = owner(d);
    let (Some(g), Some(a)) = (o.get("g").and_then(|v| v.as_u64()), own.asking) else { return false };
    if g != a || own.yes.iter().any(|c| c == conv) {
        return false;
    }
    own.yes.push(conv.to_string());
    let full = own.yes.len() >= ring::MOST;
    save_owner(d, &own);
    trace(&format!("yes g={g} from={}", &conv[..conv.len().min(10)]));
    if full {
        if let Some(w) = words {
            renew(d, w, a, card);
        }
    }
    true
}

/// The keeper's own word: only this makes a part «held» on my screen; a keeper is whole once it holds every slot of its place.
fn took_held(d: &Desk, conv: &str, o: &Map<String, Value>) -> bool {
    let mut own = owner(d);
    if o.get("g").and_then(|v| v.as_u64()) != Some(own.generation) {
        return false;
    }
    let Some(k) = own.keepers.get_mut(conv) else { return false };
    match o.get("k").and_then(|v| v.as_u64()) {
        Some(s) => {
            if !k.held_slots.contains(&(s as usize)) {
                k.held_slots.push(s as usize);
                k.held_slots.sort();
            }
            let want = if k.slots.is_empty() { vec![k.slot] } else { k.slots.clone() };
            k.held = want.iter().all(|x| k.held_slots.contains(x));
        }
        None => k.held = true, // a keeper of an older build holds one part and names no slot
    }
    trace(&format!("held slot={:?} whole={}", o.get("k"), k.held));
    save_owner(d, &own);
    true
}

/// THE RENEWAL: the ring in the order of the latest letter, a full ring at most; the copy sealed and handed around it.
fn renew(d: &Desk, words: &str, g: u64, card: Option<Record>) -> bool {
    static RENEWING: AtomicBool = AtomicBool::new(false);
    let mut o = owner(d);
    if o.yes.is_empty() || RENEWING.swap(true, Ordering::SeqCst) {
        return false;
    }
    o.asking = None;
    o.tried_at = now_s();
    save_owner(d, &o);
    let rank: HashMap<String, usize> = people(d).into_iter().enumerate().map(|(i, c)| (c, i)).collect();
    let mut chosen = o.yes.clone();
    chosen.sort_by_key(|c| rank.get(c).copied().unwrap_or(usize::MAX));
    chosen.truncate(ring::MOST);
    let done = (|| {
        let a = d.archive.as_ref()?;
        let file = history::make_copy_planned(a, d.book, d.media, card, &history::Plan::load(d.vault), &Default::default())?;   // the person's plan (iOS scope)
        hand(d, words, &file, g, &chosen)
    })();
    RENEWING.store(false, Ordering::SeqCst);
    if done.is_none() {
        trace("renew: the copy was refused");
    }
    true
}

/// THE COPY HANDED AROUND THE RING: cut at the sixteen slots of a group, every share laid on the nodes ONCE and its road handed
/// to each keeper of its slot -- the ring costs the network a copy and a third, whatever the number of keepers.
fn hand(d: &Desk, words: &str, file: &[u8], g: u64, keepers: &[String]) -> Option<()> {
    let n = code::GROUP;
    let master = seed::master_of(words)?;
    let key = derive::keep_key(&master[..])?;
    let cut = code::cut(file, n)?;
    let mut roads: BTreeMap<usize, Value> = BTreeMap::new();
    for (k, share) in cut.shares.iter().enumerate() {
        if let Some(r) = history::lay_road(share) {
            roads.insert(k, r);
        }
    }
    let mut sent: BTreeMap<String, Keeper> = BTreeMap::new();
    let mut parts = 0;
    for (i, conv) in keepers.iter().enumerate() {
        let slots: Vec<usize> = ring::slots(i, keepers.len()).into_iter().filter(|k| roads.contains_key(k)).collect();
        for &k in &slots {
            let (Some(secret), Some(road)) = (derive::slot_secret(&master[..], k), roads.get(&k)) else { continue };
            let head = derive::Head { slot: k, n, generation: g, length: cut.length, copy: cut.digest, share: cut.digests[k] };
            let mut o = json!({ "w": "part", "k": k, "n": n, "s": b64(&secret), "h": hex(&head.bytes()), "e": hex(&derive::seal(&key, &head)) });
            for (a, b) in road.as_object()? {
                o[a] = b.clone();
            }
            say(d, conv, &o);
            parts += 1;
        }
        if let Some(&first) = slots.first() {
            sent.insert(conv.clone(), Keeper { slot: first, held: false, slots, held_slots: vec![] });
        }
    }
    if sent.is_empty() {
        trace("hand: no part left");
        return None;
    }
    let mut o = owner(d);
    for conv in o.keepers.keys().filter(|c| !sent.contains_key(*c)) {
        say(d, conv, &json!({ "w": "release" }));
    }
    o.keepers = sent;
    o.n = n;
    o.generation = g;
    o.yes.clear();
    o.short = false;
    o.renewed_at = now_s();
    save_owner(d, &o);
    trace(&format!("hand g={g} keepers={} parts={parts} laid={} bytes={}", o.keepers.len(), roads.len(), cut.length));
    Some(())
}

/// The keeping as the settings show it: my copy (asking, short, kept by how many of how many), the parts kept for others by
/// correspondence and size, and the taking back.
pub fn state(d: &Desk) -> Value {
    let o = owner(d);
    let mut kept: BTreeMap<String, u64> = BTreeMap::new();
    for (k, h) in held(d) {
        *kept.entry(conv_of(&k).to_string()).or_default() += h.bytes;
    }
    let kept: Vec<Value> = kept.into_iter().map(|(c, b)| {
        let name = d.book.chat(&c).map(|x| if x.alias.trim().is_empty() { x.name } else { x.alias }).unwrap_or_default();
        json!({ "chat": c, "name": name, "bytes": b })
    }).collect();
    json!({
        "mine": mine(d), "others": others(d), "told": told(d), "agrees": agrees(),
        "asking": o.asking.is_some(), "short": o.short, "keepers": o.keepers.len(), "held": o.keepers.values().filter(|k| k.held).count(),
        "generation": o.generation, "kept": kept, "taking": *TAKING.lock().unwrap(),
    })
}

// ── the keeper ──

fn held_bytes(h: &BTreeMap<String, Held>, except: &str) -> u64 {
    h.iter().filter(|(k, _)| conv_of(k) != except).map(|(_, x)| x.bytes).sum()
}

/// A question is answered only by a machine whose person allows keeping and whose budget has room: anything else is silence.
fn answer_ask(d: &Desk, conv: &str, o: &Map<String, Value>) {
    let Some(g) = o.get("g").and_then(|v| v.as_u64()) else { return };
    if !others(d) || held_bytes(&held(d), conv) >= BUDGET_MB * 1_048_576 {
        trace("quiet: no room or no keeping");
        return;
    }
    say(d, conv, &json!({ "w": "yes", "g": g }));
}

/// A PART HANDED: checked by its head and its seal's shape, fetched by its road, checked by the share's digest, kept; «held»
/// goes back. A renewal replaces: this person's parts of an older copy leave as the newer one arrives. The bytes when it is
/// the first part held for this person (the person is told).
fn take_part(d: &Desk, conv: &str, o: &Map<String, Value>) -> Option<u64> {
    let refuse = || { trace("part refused in silence"); None };
    if !others(d) {
        return refuse();
    }
    let (Some(k), Some(n)) = (o.get("k").and_then(|v| v.as_u64()), o.get("n").and_then(|v| v.as_u64())) else { return refuse() };
    let (k, n) = (k as usize, n as usize);
    let Some(secret) = o.get("s").and_then(|v| v.as_str()).and_then(unb64).filter(|s| s.len() == 32) else { return refuse() };
    let Some(hd) = o.get("h").and_then(|v| v.as_str()).and_then(unhex) else { return refuse() };
    let Some(head) = derive::Head::parse(&hd).filter(|h| h.slot == k && h.n == n) else { return refuse() };
    let Some(seal) = o.get("e").and_then(|v| v.as_str()).and_then(unhex).filter(|s| s.len() == 32) else { return refuse() };
    let Some(size) = o.get("z").and_then(|v| v.as_u64()).filter(|z| *z > 0) else { return refuse() };
    let key = key_of(conv, k);
    let mut all = held(d);
    let same_copy: u64 = all.iter().filter(|(x, h)| conv_of(x) == conv && **x != key && generation(h) == head.generation).map(|(_, h)| h.bytes).sum();
    if held_bytes(&all, conv) + same_copy + size > BUDGET_MB * 1_048_576 {
        return refuse();
    }
    let road = Value::Object(o.clone());
    let bytes = history::fetch_road(&road).filter(|b| sha(&[b]) == head.share)?;
    let path = part_path(d, &key)?;
    std::fs::write(&path, &bytes).ok()?;
    let first = !all.keys().any(|x| conv_of(x) == conv);
    let old: Vec<String> = all.iter().filter(|(x, h)| conv_of(x) == conv && **x != key && generation(h) < head.generation).map(|(x, _)| x.clone()).collect();
    for x in old {
        drop_key(d, &mut all, &x);
    }
    let now = now_s();
    let road = json!({ "z": size, "bk": o.get("bk"), "mref": o.get("mref"), "mk": o.get("mk") });
    all.insert(key, Held { slot: k, n, secret: b64(&secret), head: hex(&hd), seal: hex(&seal), bytes: size, at: now, answered_at: 0, road: Some(road), road_at: now });
    save_held(d, &all);
    say(d, conv, &json!({ "w": "held", "g": head.generation, "d": hex(&head.share), "k": k }));
    trace(&format!("part held slot={k} of {n} bytes={size}"));
    first.then_some(size)
}

fn drop_key(d: &Desk, all: &mut BTreeMap<String, Held>, key: &str) {
    all.remove(key);
    ROADS.lock().unwrap().remove(&format!("{}/{key}", d.twin));
    if let Some(p) = part_path(d, key) {
        let _ = std::fs::remove_file(p);
    }
}
/// The parts of one person leave this machine (their «release», or the person's own hand).
pub fn drop_parts(d: &Desk, conv: &str) -> bool {
    let mut all = held(d);
    let keys: Vec<String> = all.keys().filter(|k| conv_of(k) == conv).cloned().collect();
    if keys.is_empty() {
        return false;
    }
    for k in &keys {
        drop_key(d, &mut all, k);
    }
    save_held(d, &all);
    trace(&format!("drop parts={}", keys.len()));
    true
}

/// The roads this machine laid of a part for an answer (the pieces live a week on the nodes: a day's answers share them).
static ROADS: Mutex<BTreeMap<String, (i64, Value)>> = Mutex::new(BTreeMap::new());

/// A CALL IN A SLOT'S PIPE: the part goes back by the owner's own road while its pieces live, else by one laid here; the
/// head and the seal ride with it. One answer serves ten minutes of calls.
fn answer_call(d: &Desk, key: &str) {
    if !others(d) {
        return;
    }
    let mut all = held(d);
    let Some(h) = all.get(key).cloned() else { return };
    let now = now_s();
    if now - h.answered_at < 600 {
        return;
    }
    let Some(path) = part_path(d, key).filter(|p| p.exists()) else { return };
    let rk = format!("{}/{key}", d.twin);
    let cached = ROADS.lock().unwrap().get(&rk).filter(|(at, _)| now - at < 86_400).map(|(_, r)| r.clone());
    let mut road = match (&h.road, cached) {
        (Some(r), _) if now - h.road_at < 6 * 86_400 && r["z"].as_u64() == Some(h.bytes) => r.clone(),
        (_, Some(r)) => r,
        _ => {
            let Some(r) = std::fs::read(&path).ok().and_then(|b| history::lay_road(&b)) else {
                trace("answer: the part did not reach the nodes");
                return;
            };
            ROADS.lock().unwrap().insert(rk.clone(), (now, r.clone()));
            r
        }
    };
    road["w"] = json!("answer");
    road["h"] = json!(h.head);
    road["e"] = json!(h.seal);
    let Some(secret) = unb64(&h.secret) else { return };
    if !history::knock(&secret, &d.twin, &format!("{MARK}{road}")) {
        trace("answer: no door boxed it");
        return;
    }
    if let Some(x) = all.get_mut(key) {
        x.answered_at = now;
    }
    save_held(d, &all);
    trace(&format!("answer slot={} of {}", h.slot, h.n));
}

// ── a machine that opened the words ──

/// Where the taking back stands, for the settings: idle, calling (parts in hand of those needed), laying, done, failed.
#[derive(Serialize, Clone, Copy, Debug, PartialEq)]
#[serde(tag = "s", rename_all = "lowercase")]
pub enum Taking {
    Idle,
    Calling { have: usize, need: usize },
    Laying,
    Done,
    Failed,
}
pub static TAKING: Mutex<Taking> = Mutex::new(Taking::Idle);
static TAKING_NOW: AtomicBool = AtomicBool::new(false);
static TAKING_STOP: AtomicBool = AtomicBool::new(false);
pub fn stop_taking() {
    TAKING_STOP.store(true, Ordering::SeqCst);
}
pub fn is_taking() -> bool {
    TAKING_NOW.load(Ordering::SeqCst)
}

/// The rows of a derived pipe's box across the term (iOS BoxEar for one pipe): (node mid, the letter's words) of every letter
/// that opens under the secret; `take` -- the rows read are confirmed to the node.
pub fn read_pipe(secret: &[u8], twin: &str, take: bool) -> Vec<String> {
    let w0 = wire::day();
    let subs: Vec<String> = ((w0 - 8)..=(w0 + 1)).map(|d| wire::conv_w(secret, d)).collect();
    let page = json!({ "subs": subs, "sids": subs.iter().map(|c| wire::sub_id(c, twin)).collect::<Vec<_>>() });
    let mut seen = std::collections::HashSet::new();
    let (mut out, mut taken) = (vec![], vec![]);
    for (code, v) in doors::read_each("/fetch", &page, 8_000) {
        if code != 200 {
            continue;
        }
        for l in v.as_ref().and_then(|v| v["letters"].as_array()).cloned().unwrap_or_default() {
            let m = l["m"].as_str().unwrap_or("").to_string();
            if !seen.insert(m.clone()) {
                continue;
            }
            let Some(sealed) = l["e"].as_str().and_then(unb64) else { continue };
            let Some(plain) = wire::open_boxed(&sealed, secret, l["at"].as_i64().unwrap_or(now_s())) else { continue };
            out.push(wire::fields(&plain, 0, 2)[1].clone());
            if !m.is_empty() {
                taken.push(m);
            }
        }
    }
    if take && !taken.is_empty() {
        let body = json!({ "mids": taken });
        for door in doors::all() {
            doors::post_at(&door, "/box-del", &body, 5000);
        }
    }
    out
}

/// One knock in a derived pipe, silent or loud (a loud one rings the keeper's screen with the owner's name, for a keeper whose
/// app the system does not wake).
fn knock(secret: &[u8], twin: &str, o: &Value, silent: bool) -> bool {
    history::knock_as(secret, twin, &format!("{MARK}{o}"), silent)
}

struct Answer {
    head: derive::Head,
    share: Vec<u8>,
}

/// THE COPY TAKEN BACK FROM THE PEOPLE ONE WRITES TO: the pipe of every slot called, every answer's seal checked against the
/// words, and the copy of the highest generation whose every group stands built, checked against its digest and laid by
/// `lay` (true -- laid). The calls repeat every two minutes, loud after six minutes for the slots still silent; the walk
/// ends with the copy laid, after `hours` without one, or by stop_taking.
pub fn take_back(words: &str, twin: &str, entropy: &[u8], hours: f64, mut lay: impl FnMut(Vec<Record>) -> bool) -> bool {
    if !agrees() || TAKING_NOW.swap(true, Ordering::SeqCst) {
        return false;
    }
    TAKING_STOP.store(false, Ordering::SeqCst);
    let set = |t: Taking| *TAKING.lock().unwrap() = t;
    let done = (|| -> Option<bool> {
        let master = seed::master_of(words)?;
        let key = derive::keep_key(&master[..])?;
        let secrets: Vec<Vec<u8>> = (0..derive::SLOTS).filter_map(|k| derive::slot_secret(&master[..], k)).collect();
        if secrets.len() != derive::SLOTS {
            return None;
        }
        let mut answers: BTreeMap<String, Answer> = BTreeMap::new();
        let began = now_s();
        let (mut last_call, mut last_loud) = (0i64, 0i64);
        set(Taking::Calling { have: 0, need: 0 });
        while !TAKING_STOP.load(Ordering::SeqCst) {
            let now = now_s();
            if now - last_call >= 120 {
                last_call = now;
                let boxed = secrets.iter().filter(|s| knock(s, twin, &json!({ "w": "call" }), true)).count();
                trace(&format!("call slots={} boxed={boxed}", secrets.len()));
            }
            if now - began >= 360 && now - last_loud >= 600 {
                last_loud = now;
                let newest = answers.values().max_by_key(|a| a.head.generation).map(|a| a.head.clone());
                let heard: Vec<usize> = answers.values().filter(|a| Some(a.head.copy) == newest.as_ref().map(|h| h.copy)).map(|a| a.head.slot).collect();
                let rung = (0..newest.as_ref().map_or(derive::SLOTS, |h| h.n)).filter(|k| !heard.contains(k))
                    .filter(|&k| knock(&secrets[k], twin, &json!({ "w": "call", "loud": 1 }), false)).count();
                trace(&format!("call loud rung={rung} heard={}", heard.len()));
            }
            for (k, s) in secrets.iter().enumerate() {
                for text in read_pipe(s, twin, true) {
                    let Some(o) = word(&text) else { continue };
                    if o.get("w").and_then(|v| v.as_str()) != Some("answer") {
                        continue;
                    }
                    let Some(head) = o.get("h").and_then(|v| v.as_str()).and_then(unhex).and_then(|b| derive::Head::parse(&b)).filter(|h| h.slot == k) else { continue };
                    let Some(seal) = o.get("e").and_then(|v| v.as_str()).and_then(unhex) else { continue };
                    if seal != derive::seal(&key, &head) {
                        continue; // a part no seal of these words vouches for
                    }
                    let id = format!("{}.{k}", hex(&head.copy));
                    if answers.contains_key(&id) {
                        continue;
                    }
                    let Some(share) = history::fetch_road(&Value::Object(o.clone())).filter(|b| sha(&[b]) == head.share) else { continue };
                    trace(&format!("took slot={k} of {} generation={}", head.n, head.generation));
                    answers.insert(id, Answer { head, share });
                }
            }
            // the copies in hand, the newest first; a copy stands when its parts hold twelve cells of every group
            let mut copies: BTreeMap<[u8; 32], Vec<&Answer>> = BTreeMap::new();
            for a in answers.values() {
                copies.entry(a.head.copy).or_default().push(a);
            }
            let mut ranked: Vec<Vec<&Answer>> = copies.into_values().collect();
            ranked.sort_by_key(|v| std::cmp::Reverse(v[0].head.generation));
            if let Some(best) = ranked.first() {
                set(Taking::Calling { have: best.len(), need: 3 * best[0].head.n / 4 });
            }
            for parts in &ranked {
                let h0 = &parts[0].head;
                let same: Vec<&&Answer> = parts.iter().filter(|a| a.head.n == h0.n && a.head.length == h0.length).collect();
                if same.len() * (code::GROUP / h0.n) < code::DATA {
                    continue;
                }
                let list: Vec<(usize, usize, &[u8])> = same.iter().map(|a| (a.head.slot, a.head.n, a.share.as_slice())).collect();
                let Some(file) = code::rebuild(&list, h0.length).filter(|f| sha(&[f]) == h0.copy) else {
                    trace(&format!("build generation={} did not stand", h0.generation));
                    continue;
                };
                set(Taking::Laying);
                let Ok(records) = history::read_copy(entropy, &file) else { continue };
                let laid = lay(records);
                trace(&format!("build generation={} laid={laid}", h0.generation));
                set(if laid { Taking::Done } else { Taking::Failed });
                return Some(laid);
            }
            if (now_s() - began) as f64 > hours * 3600.0 {
                return Some(false);
            }
            for _ in 0..15 {
                if TAKING_STOP.load(Ordering::SeqCst) {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_secs(1));
            }
        }
        Some(false)
    })();
    if done != Some(true) && *TAKING.lock().unwrap() != Taking::Done {
        set(if TAKING_STOP.load(Ordering::SeqCst) { Taking::Idle } else { Taking::Failed });
    }
    TAKING_NOW.store(false, Ordering::SeqCst);
    done == Some(true)
}

// ── the correspondence given back ──

/// THE REQUEST: once a copy is laid, every correspondence of a person it names is asked in its own pipe, with the moment of
/// the last letter laid there; the answer is awaited a week.
pub fn ask_back(d: &Desk) -> usize {
    let now = now_s();
    let mut asked: Map<String, Value> = d.vault.get(ASKED_BACK).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    asked.retain(|_, at| now - at.as_i64().unwrap_or(0) < 7 * 86_400);
    let mut n = 0;
    for conv in people(d) {
        if now - asked.get(&conv).and_then(|v| v.as_i64()).unwrap_or(0) < 600 {
            continue;
        }
        let last = d.book.chat(&conv).and_then(|c| c.msgs.iter().map(|m| m.at).max()).unwrap_or(0) as f64 / 1000.0;
        say(d, &conv, &json!({ "w": "back", "a": last }));
        asked.insert(conv, json!(now));
        n += 1;
    }
    d.vault.set(ASKED_BACK, Value::Object(asked).to_string().as_bytes());
    trace(&format!("back asked={n}"));
    n
}

static ANSWERED_BACK: Mutex<BTreeMap<String, i64>> = Mutex::new(BTreeMap::new());

/// THE ANSWER: the letters of this correspondence this machine holds, later than the asker's last, on the cargo road and named
/// in the same correspondence -- nothing kept for the purpose, nothing but this correspondence, nothing while the person keeps
/// nothing for others. A letter of the asker rides with the author field it came with: their machine names it theirs by their
/// own key, never by this machine's word.
fn answer_back(d: &Desk, conv: &str, o: &Map<String, Value>) {
    let now = now_s();
    {
        let mut a = ANSWERED_BACK.lock().unwrap();
        let k = format!("{}/{conv}", d.twin);
        if !others(d) || now - a.get(&k).copied().unwrap_or(0) < 600 {
            trace("back quiet");
            return;
        }
        a.insert(k, now);
    }
    let since = o.get("a").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let Some(c) = d.book.chat(conv) else { return };
    let rows: Vec<&Msg> = c.msgs.iter()
        .filter(|m| m.at as f64 / 1000.0 > since && !m.text.is_empty() && !marks::is_service(&m.text) && !m.mid.starts_with(GIVEN))
        .collect();
    if rows.is_empty() {
        say(d, conv, &json!({ "w": "given", "c": 0 }));
        return;
    }
    let list: Vec<Value> = rows.iter().map(|m| {
        let mut e = json!({ "i": m.mid, "m": if m.mine { 1 } else { 0 }, "t": m.at as f64 / 1000.0, "x": m.text });
        if !m.mine && !m.author.is_empty() {
            e["a"] = json!(m.author);
        }
        e
    }).collect();
    let body = Value::Array(list).to_string().into_bytes();
    let Some(mut road) = history::lay_road(&body) else {
        trace("back: the letters did not reach the nodes");
        return;
    };
    road["w"] = json!("given");
    road["c"] = json!(rows.len());
    road["d"] = json!(hex(&sha(&[&body])));
    say(d, conv, &road);
    trace(&format!("back gave={} bytes={}", rows.len(), body.len()));
}

/// THE CORRESPONDENCE TAKEN BACK: only an answer to this machine's own request, only the letters later than the last one in
/// that correspondence here, each on the side of the one who wrote it. WHICH LETTER IS MINE IS SAID BY MY OWN WORDS: a letter
/// they name as theirs is theirs; one they name as mine stands as mine only when the author field it rode with is made again
/// under this person's key -- else it is not laid at all. The count laid.
fn take_given(d: &Desk, conv: &str, o: &Map<String, Value>) -> usize {
    let asked: Map<String, Value> = d.vault.get(ASKED_BACK).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let Some(at) = asked.get(conv).and_then(|v| v.as_i64()).filter(|at| now_s() - at < 7 * 86_400) else { return 0 };
    if o.get("c").and_then(|v| v.as_u64()).unwrap_or(0) == 0 {
        return 0;
    }
    let Some(digest) = o.get("d").and_then(|v| v.as_str()) else { return 0 };
    let Some(body) = history::fetch_road(&Value::Object(o.clone())).filter(|b| hex(&sha(&[b])) == digest) else {
        trace("given: the letters did not come whole");
        return 0;
    };
    let Ok(Value::Array(list)) = serde_json::from_slice::<Value>(&body) else { return 0 };
    let Some(secret) = d.book.secret(conv) else { return 0 };
    let Some(c) = d.book.chat(conv) else { return 0 };
    // the copies' last letter is the last one older than the request: a letter that came live after it is no measure
    let since = c.msgs.iter().filter(|m| m.at < at * 1000).map(|m| m.at).max().unwrap_or(0);
    let mut unproven = 0;
    let rows: Vec<Msg> = list.iter().filter_map(|e| {
        let t = e["t"].as_f64()?;
        let x = e["x"].as_str().filter(|x| !x.is_empty() && !marks::is_service(x) || x.starts_with(marks::STICKER))?;
        if (t * 1000.0) as i64 <= since {
            return None;
        }
        let wire_mid = e["i"].as_str().filter(|i| !i.is_empty());
        let mine = e["m"].as_i64().unwrap_or(0) == 0; // the other side's own letter is the other side's here
        if mine {
            let bare = wire_mid.map(|w| w.strip_prefix("mid:").unwrap_or(w)).unwrap_or("");
            if bare.is_empty() || !wire::author_holds(e["a"].as_str().unwrap_or(""), d.author_key.as_deref(), &secret, bare, x) {
                unproven += 1;
                return None;
            }
        }
        let mid = format!("{GIVEN}{}", wire_mid.map(str::to_string).unwrap_or_else(|| t.to_string()));
        Some(Msg { mid, text: x.to_string(), mine, at: (t * 1000.0) as i64, state: if mine { 2 } else { 0 }, ..Default::default() })
    }).collect();
    let mut laid = 0;
    d.book.edit(conv, |c| {
        let sig = |m: &Msg| format!("{}@{}@{}", m.at / 1000, if m.mine { 1 } else { 0 }, m.text);
        let seen: std::collections::HashSet<String> = c.msgs.iter().map(sig).collect();
        for m in rows {
            let wire_mid = m.mid.strip_prefix(GIVEN).unwrap_or(&m.mid).to_string();
            if seen.contains(&sig(&m)) || c.msgs.iter().any(|x| x.mid == m.mid || x.mid == wire_mid) {
                continue;
            }
            c.msgs.push(m);
            laid += 1;
        }
        c.msgs.sort_by_key(|m| m.at);
    });
    trace(&format!("given took={laid} of {} unproven_mine={unproven}", list.len()));
    laid
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_code_the_derivations_and_the_ring_agree_with_the_canon() {
        assert!(code::agrees(), "the erasure code");
        assert!(derive::agrees(), "the slot secrets, the keeping key, the light, the head and its seal");
        assert!(ring::agrees(), "the ring");
        assert!(agrees());
    }

    #[test]
    fn a_copy_cut_into_sixteen_comes_back_from_any_twelve_and_never_from_eleven() {
        let copy: Vec<u8> = (0..30_000u32).map(|i| (i * 7 % 251) as u8).collect();
        for n in [4, 8, 16] {
            let cut = code::cut(&copy, n).unwrap();
            assert_eq!(cut.shares.len(), n);
            assert_eq!(cut.length, copy.len() as u64);
            for (s, dg) in cut.shares.iter().zip(&cut.digests) {
                assert_eq!(&sha(&[s]), dg);
            }
            let all: Vec<(usize, usize, &[u8])> = cut.shares.iter().enumerate().map(|(k, s)| (k, n, s.as_slice())).collect();
            assert_eq!(code::rebuild(&all, cut.length).as_deref(), Some(copy.as_slice()), "every share, n={n}");
            // a quarter lost: the shares of the last quarter of the slots
            let keep = n * 3 / 4;
            let some: Vec<(usize, usize, &[u8])> = all.iter().rev().take(keep).cloned().collect();
            assert_eq!(code::rebuild(&some, cut.length).as_deref(), Some(copy.as_slice()), "three quarters, n={n}");
            let fewer: Vec<(usize, usize, &[u8])> = all.iter().take(keep - 1).cloned().collect();
            assert_eq!(code::rebuild(&fewer, cut.length), None, "less than three quarters, n={n}");
        }
        // a copy that fills its last group to the byte, and one byte of copy
        let exact = vec![9u8; code::DATA * code::CHUNK * 2];
        let cut = code::cut(&exact, 16).unwrap();
        let all: Vec<(usize, usize, &[u8])> = cut.shares.iter().enumerate().map(|(k, s)| (k, 16, s.as_slice())).collect();
        assert_eq!(code::rebuild(&all[4..], cut.length).as_deref(), Some(exact.as_slice()));
        let one = code::cut(&[42], 16).unwrap();
        let all: Vec<(usize, usize, &[u8])> = one.shares.iter().enumerate().map(|(k, s)| (k, 16, s.as_slice())).collect();
        assert_eq!(code::rebuild(&all[..12], 1).as_deref(), Some([42u8].as_slice()));
    }

    #[test]
    fn a_head_is_eighty_two_bytes_and_a_wrong_one_is_refused() {
        let h = derive::Head { slot: 15, n: 16, generation: 3, length: 1000, copy: [1; 32], share: [2; 32] };
        let b = h.bytes();
        assert_eq!(b.len(), derive::Head::BYTES);
        assert_eq!(derive::Head::parse(&b), Some(h.clone()));
        let mut bad = b.clone();
        bad[0] = 16; // a slot past n
        assert_eq!(derive::Head::parse(&bad), None);
        bad = b.clone();
        bad[1] = 5; // n of no code
        assert_eq!(derive::Head::parse(&bad), None);
        assert_eq!(derive::Head::parse(&b[..81]), None);
        assert_ne!(derive::seal(&[1; 32], &h), derive::seal(&[2; 32], &h), "the seal is the words' alone");
    }

    /// THE RING THROUGH THE NODES, with throwaway people: Alice keeps her copy with Bob (a ring of one: Bob holds all sixteen
    /// slots); a new machine of Alice's words calls the slots, Bob answers, the copy is built, checked and laid; then Bob gives
    /// back the conversation written after the copy -- his letter as his, Alice's as hers by her own key.
    #[test]
    #[ignore]
    fn a_copy_kept_by_a_correspondent_comes_back_to_the_words_and_the_talk_is_given_back() {
        if std::env::var_os("MONTANA_LIVE").is_none() {
            return;
        }
        use crate::book::Book;
        use crate::vault::Vault;
        use crate::{media, meeting};
        let root = std::env::temp_dir().join(format!("montana-keep-live-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (wa, wb) = (seed::generate().unwrap(), seed::generate().unwrap());
        let (v1, v2, vb) = (Vault::at(&root.join("a1")).unwrap(), Vault::at(&root.join("a2")).unwrap(), Vault::at(&root.join("b")).unwrap());
        let (b1, b2, bb) = (Book::new(v1.clone()), Book::new(v2.clone()), Book::new(vb.clone()));
        let (s1, s2, sb) = (media::Store::at(&root.join("a1m")).unwrap(), media::Store::at(&root.join("a2m")).unwrap(), media::Store::at(&root.join("bm")).unwrap());
        let p = crate::presence::Presence::default();
        let arc = |dev: u8| history::Archive::new(&root.join(format!("arc{dev}")), history::keys(&wa).unwrap(), [dev; 16]);
        fn desk<'a>(v: &'a Vault, b: &'a Book, s: &'a media::Store, p: &'a crate::presence::Presence, w: &str, a: history::Archive) -> Desk<'a> {
            Desk { vault: v, book: b, twin: seed::twin_of(w).unwrap(), author_key: seed::author_key_of(w), my_name: "Alice".into(), news: Default::default(),
                   media: s, faces: s, self_face: vec![], about: Default::default(), read_receipts: true, presence: p, archive: Some(a) }
        }
        let (a1, a2) = (desk(&v1, &b1, &s1, &p, &wa, arc(1)), desk(&v2, &b2, &s2, &p, &wa, arc(2)));
        let bob = Desk { vault: &vb, book: &bb, twin: seed::twin_of(&wb).unwrap(), author_key: seed::author_key_of(&wb), my_name: "Bob".into(), news: Default::default(),
                         media: &sb, faces: &sb, self_face: vec![], about: Default::default(), read_receipts: true, presence: &p, archive: None };
        let until = |what: &str, secs: u64, step: &dyn Fn() -> bool| {
            let end = std::time::Instant::now() + std::time::Duration::from_secs(secs);
            while std::time::Instant::now() < end {
                if step() {
                    return;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            panic!("{what}: never");
        };
        let has = |b: &Book, r: &str, text: &str, mine: bool| b.chat(r).is_some_and(|c| c.msgs.iter().any(|m| m.text == text && m.mine == mine));

        // Alice and Bob meet and write
        let link = (crate::card::Card { vault: &v1 }).offer_permanent("Alice").unwrap();
        let mut met = meeting::Outcome::Refused;
        for _ in 0..10 {
            met = meeting::meet(&vb, &bb, &link);
            if matches!(met, meeting::Outcome::Opened(_)) { break; }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        let meeting::Outcome::Opened(rb) = met else { panic!("Bob could not meet Alice: {met:?}") };
        bob.send(&rb, "Привет, Алиса");
        until("Alice takes Bob's letter", 60, &|| { a1.fetch_once(); has(&b1, &rb, "Привет, Алиса", false) });
        a1.send(&rb, "Ответ Алисы");
        until("Bob takes Alice's answer", 60, &|| { bob.fetch_once(); has(&bb, &rb, "Ответ Алисы", false) });

        // Alice keeps her copy with Bob: the ask, Bob's yes, the ring of one handed
        set_mine(&a1, true);
        work(&a1, Some(&wa), None);
        assert_eq!(owner(&a1).asking, Some(1), "the people Alice writes to are asked");
        until("Bob says yes", 90, &|| {
            bob.fetch_once();
            work(&bob, None, None);
            a1.fetch_once();
            work(&a1, Some(&wa), None);
            owner(&a1).yes == [rb.clone()]
        });
        let mut o = owner(&a1);
        o.asked_at -= 601; // the ten minutes a renewal waits for more yeses, gone
        save_owner(&a1, &o);
        work(&a1, Some(&wa), None);
        let o = owner(&a1);
        assert_eq!((o.generation, o.n, o.keepers.len()), (1, 16, 1), "the copy cut at sixteen and handed to Bob");
        assert_eq!(o.keepers[&rb].slots, (0..16).collect::<Vec<_>>(), "a ring of one keeps every slot");
        until("Bob holds sixteen parts and says so", 240, &|| {
            bob.fetch_once();
            work(&bob, None, None);
            a1.fetch_once();
            work(&a1, Some(&wa), None);
            held(&bob).len() == 16 && owner(&a1).keepers[&rb].held
        });

        // after the copy: Bob writes, Alice answers -- the new machine will not find these in any box
        bob.send(&rb, "Письмо после копии");
        until("Alice takes it", 60, &|| { a1.fetch_once(); has(&b1, &rb, "Письмо после копии", false) });
        a1.send(&rb, "Алиса после копии");
        until("Bob takes it", 60, &|| { bob.fetch_once(); has(&bb, &rb, "Алиса после копии", false) });
        assert!(bb.chat(&rb).unwrap().msgs.iter().any(|m| m.text == "Алиса после копии" && !m.author.is_empty()), "Bob keeps the author field Alice's letter rode with");

        // a new machine of Alice's words takes the copy back from Bob
        let entropy = history::keys(&wa).unwrap().entropy;
        let done = std::sync::atomic::AtomicBool::new(false);
        std::thread::scope(|sc| {
            let t = sc.spawn(|| {
                let laid = take_back(&wa, &a2.twin, &entropy, 0.1, |records| {
                    history::restore(a2.archive.as_ref().unwrap(), &b2, &s2, None, &records);
                    true
                });
                done.store(true, Ordering::SeqCst);
                laid
            });
            while !done.load(Ordering::SeqCst) {
                bob.fetch_once();
                work(&bob, None, None);
                std::thread::sleep(std::time::Duration::from_secs(3));
            }
            assert!(t.join().unwrap(), "the copy never came back from Bob");
        });
        assert_eq!(*TAKING.lock().unwrap(), Taking::Done);
        assert!(has(&b2, &rb, "Привет, Алиса", false) && has(&b2, &rb, "Ответ Алисы", true), "the copy laid Bob's pipe and both letters on the new machine");
        assert!(!has(&b2, &rb, "Письмо после копии", false), "a letter after the copy is not in it");

        // the conversation given back: Bob's letter as his, Alice's as hers by her own key
        assert_eq!(ask_back(&a2), 1);
        until("Bob gives the talk back", 120, &|| {
            bob.fetch_once();
            work(&bob, None, None);
            a2.fetch_once();
            work(&a2, None, None);
            has(&b2, &rb, "Письмо после копии", false) && has(&b2, &rb, "Алиса после копии", true)
        });
        let c = b2.chat(&rb).unwrap();
        assert_eq!(c.msgs.iter().filter(|m| m.text == "Письмо после копии").count(), 1, "given back once");
        assert!(c.msgs.iter().filter(|m| m.mid.starts_with(GIVEN)).count() >= 2);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_keeping_word_is_its_own_and_reads_as_ios_writes_it() {
        let o = word(&format!("{MARK}{{\"w\":\"ask\",\"g\":2}}")).unwrap();
        assert_eq!((o["w"].as_str(), o["g"].as_u64()), (Some("ask"), Some(2)));
        assert!(word("\u{200B}\u{200B}NM:Алиса").is_none());
        assert!(marks::is_service(MARK) && marks::is_silent(MARK) && !marks::is_row(&format!("{MARK}{{}}")), "never a row, never rings");
        assert!(!crate::twin::mirrors(&format!("{MARK}{{\"w\":\"ask\"}}")), "never mirrored to the person's other devices");
    }
}
