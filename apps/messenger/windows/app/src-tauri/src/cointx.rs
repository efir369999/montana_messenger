//! THE COIN CHAIN (iOS MTCoinTx / MTCoinChainRules, Audit/COIN-TX-V3.md): every move of a balance is a signed record of its key's
//! chain. Coins enter a key only by a record (MINT, RECV, REFUND) and leave only by one (SEND); the key's chain lives on one node of
//! the fixed table (montana.quest, montana.xxx) at the index of its tag's first byte, which takes a record only on top of the head
//! and refuses one its fold breaks. The coin key is the seed's own (the core's ML-DSA-65 under the role «mt-coin-tx»), one on
//! every device of the words, and no relation to the account's key. The rules here are the document's sections 1, 3 and 4 as the
//! phone reads them; the vectors of its section 9 are the tests below.

use crate::abi::{mt_mldsa_keypair_from_seed, mt_sign, mt_verify, MT_MLDSA_PUBKEY_SIZE, MT_MLDSA_SECKEY_SIZE, MT_MLDSA_SIG_SIZE, MT_OK};
use crate::wire::{hex, hmac, sha};

pub const SIZE3: usize = 5443;
const BODY3: usize = 2134;
pub const SIZE2: usize = 5362;
const BODY2: usize = 2053;
const SIZE1: usize = 5330;
const BODY1: usize = 2021;
const MAGIC: &[u8] = b"MTTX";
const SIGNED1: &[u8] = b"mt-coin-tx-v1";
const SIGNED2: &[u8] = b"mt-coin-tx-v2";
const SIGNED3: &[u8] = b"mt-coin-tx-v3";
pub const ZERO: &str = "0000000000000000000000000000000000000000000000000000000000000000";
/// The chains' nodes, sorted by name, each with its one door (Moscow, Amsterdam): every phone and the Explorer read the same table.
pub const CHAIN_NODES: [(&str, &str); 2] = [("montana.quest", "api.montana.quest"), ("montana.xxx", "montana.xxx")];
/// The node's TX_V2_CUT (20.10.2026 00:00 MSK) and TX_COIN_EPOCH (01.09.2026 00:00 MSK), the GENESIS gate (18.10.2026).
pub const V2_CUT: i64 = 1_792_443_600;
pub const COIN_EPOCH: i64 = 1_788_210_000;
pub const GENESIS_GATE: i64 = 1_792_354_500;
/// τ1: the shortest interval a MINT covers, and how often the phone asks its chain to take what the book holds above it.
pub const WINDOW: i64 = 60;
/// From this node second a MINT is weighed one coin a second (the same second as the v2 cut).
pub const SECOND_CUT: i64 = V2_CUT;
/// THE CHAIN MINTS THE KEY'S TIME ITSELF (iOS MTCoinChainRules.timeCut, section 4, fold-6): from this node second every v3 record first
/// folds the seconds its key has lived, so no phone lays a MINT for its time. The node's TX_TIME_CUT, 23.10.2026 00:00 MSK.
pub const TIME_CUT: i64 = 1_792_702_800;
/// MINTING IS ITS OWN ROAD (iOS onlineCut, fold-7): from this node second the key's life mints nothing by itself, and a MINT counts
/// only what its interval holds of the last MINT_FRESH seconds before its node took it -- the seconds the key was present; a BURN is
/// taken from the same second. The node's TX_ONLINE_CUT, 26.10.2026 00:00 MSK.
pub const ONLINE_CUT: i64 = 1_792_962_000;
pub const MINT_FRESH: i64 = 120;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum Kind {
    Send = 1,
    Recv = 2,
    Mint = 3,
    Refund = 4,
    Genesis = 5,
    /// spends as a SEND and names no one (iOS Kind.burn, fold-7): an unrecorded call's seconds, from the online cut
    Burn = 6,
}
impl Kind {
    pub fn of(b: u8) -> Option<Kind> {
        match b {
            1 => Some(Kind::Send),
            2 => Some(Kind::Recv),
            3 => Some(Kind::Mint),
            4 => Some(Kind::Refund),
            5 => Some(Kind::Genesis),
            6 => Some(Kind::Burn),
            _ => None,
        }
    }
}

/// The seed's coin key (iOS MTCoinTx.derive): HKDF-Expand(master_seed, "mt-coin-tx", 32) into ML-DSA-65.
#[derive(Clone)]
pub struct Hands {
    pub pk: Vec<u8>,
    pub sk: Vec<u8>,
}
impl Drop for Hands {
    fn drop(&mut self) {
        self.sk.fill(0);
    }
}
impl Hands {
    pub fn from_master(master: &[u8]) -> Option<Hands> {
        let seed = crate::seed::role_of_master(master, b"mt-coin-tx")?;
        Hands::from_seed(&seed)
    }
    pub fn from_seed(seed: &[u8]) -> Option<Hands> {
        if seed.len() != 32 {
            return None;
        }
        let mut pk = vec![0u8; MT_MLDSA_PUBKEY_SIZE];
        let mut sk = vec![0u8; MT_MLDSA_SECKEY_SIZE];
        // SAFETY: a 32-byte seed and buffers of the core's sizes
        (unsafe { mt_mldsa_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) } == MT_OK).then_some(Hands { pk, sk })
    }
    /// The key's tag on the wire: SHA-256 of the public key, the sender's name in every record.
    pub fn from(&self) -> String {
        key_tag(&self.pk)
    }
    pub fn sign(&self, msg: &[u8]) -> Option<Vec<u8>> {
        let mut sig = vec![0u8; MT_MLDSA_SIG_SIZE];
        // SAFETY: the core's secret key, the message and a signature buffer of its size
        (unsafe { mt_sign(self.sk.as_ptr(), msg.as_ptr(), msg.len(), sig.as_mut_ptr()) } == MT_OK).then_some(sig)
    }
}

pub fn verify(pk: &[u8], msg: &[u8], sig: &[u8]) -> bool {
    pk.len() == MT_MLDSA_PUBKEY_SIZE && sig.len() == MT_MLDSA_SIG_SIZE
        // SAFETY: a public key and a signature of the core's sizes, and the message
        && unsafe { mt_verify(pk.as_ptr(), msg.as_ptr(), msg.len(), sig.as_ptr()) } == MT_OK
}

pub fn key_tag(pk: &[u8]) -> String {
    hex(&sha(&[pk]))
}

/// The pair's tag: HMAC-SHA-256 under the pipe's secret -- its two ends know it, no one else does.
pub fn pair_tag(secret: &[u8]) -> [u8; 32] {
    hmac(secret, b"mt-coin-pair-v1")
}

/// The blind of a SEND: HMAC-SHA-256 under the pair's secret over ASCII mt-coin-blind and the SEND's nonce (section 1).
pub fn blind(secret: &[u8], nonce: &[u8]) -> [u8; 32] {
    hmac(secret, &[b"mt-coin-blind".as_slice(), nonce].concat())
}

/// The receiver's commitment: SHA-256 of ASCII mt-coin-to, the receiver's from (32 bytes) and the blind (section 1).
pub fn commitment(from: &[u8], blind: &[u8]) -> [u8; 32] {
    sha(&[b"mt-coin-to", from, blind])
}

/// A key's chain node: the one at the index of the key tag's first byte.
pub fn chain_node(from: &str) -> Option<&'static str> {
    let first = u8::from_str_radix(from.get(..2)?, 16).ok()?;
    Some(CHAIN_NODES[first as usize % CHAIN_NODES.len()].0)
}
/// The door of a key's chain: its node's api name.
pub fn chain_door(from: &str) -> Option<String> {
    let node = chain_node(from)?;
    CHAIN_NODES.iter().find(|n| n.0 == node).map(|n| format!("https://{}/pushwake", n.1))
}

/// A_2(x) of section 4, the doubling rule: what the seconds 1..x of a key's life could mint before the second's cut --
/// 2 x min(13, max(1, bit_length(s) - 1)) a second.
pub fn time_a(x: i64) -> i64 {
    let (mut total, mut lo, mut k) = (0i64, 1i64, 0i64);
    while 0 < x && lo <= x {
        let hi = x.min(2 * lo - 1);
        total += (hi - lo + 1) * 13.min(1.max(k));
        lo *= 2;
        k += 1;
    }
    2 * total
}
pub fn genesis_cap() -> i64 {
    time_a(V2_CUT - COIN_EPOCH)
}
/// 1 SECOND -- 1 COIN (section 4, article 11): from the second's cut a MINT is weighed by the seconds of the key's whole life.
pub fn allow_time(x: i64, at: i64) -> i64 {
    if SECOND_CUT <= at { x.max(0) } else { time_a(x) }
}
/// What a GENESIS of a key at the node second `at` may announce: nothing after the v2 cut; a new key opens with a GENESIS of 0.
pub fn genesis_room(height: i64, birth: i64, at: i64) -> i64 {
    if V2_CUT <= at {
        return 0;
    }
    if at < GENESIS_GATE {
        return genesis_cap();
    }
    if height == 0 { 0 } else { genesis_cap().min(time_a(at - birth)) }
}

/// THE KEY'S SECONDS OF LIFE (iOS timeStep, fold-6 and fold-8): up to the node second `at` and never past the online cut, credited
/// once and proven by the same step. The past never eats the present: a key that minted above its life before the cut by the doubling
/// rule still gets every second since its last record, never before the cut -- the credit is the greater of its unminted life and
/// those seconds.
pub fn time_step(s: &St, at: i64) -> St {
    if at < TIME_CUT || s.height <= 0 {
        return s.clone();
    }
    let end = at.min(ONLINE_CUT);
    let fresh = (end - s.last_at.max(TIME_CUT).max(s.birth)).max(0);
    let credit = (end - s.birth - s.minted).max(fresh);
    if credit <= 0 {
        return s.clone();
    }
    St { proven: s.proven + credit, minted: s.minted + credit, ..s.clone() }
}

/// What the time step adds to a key folded at the node second `s` by the node second `t`, no record laid between (iOS 2305
/// MTCoinChainRules.since): from the time cut both sides of its credit grow by one a second up to the online cut, so the node's later
/// word is the earlier one plus these seconds.
pub fn since(s: i64, t: i64) -> i64 {
    if s < TIME_CUT {
        return 0;
    }
    (t.min(ONLINE_CUT) - s.min(ONLINE_CUT)).max(0)
}

/// The seconds a MINT taken at the node second `at` may count from the online cut (iOS present): what its interval holds of the last
/// MINT_FRESH, never a second before the cut -- the time step credited every one of those.
pub fn present(t0: i64, t1: i64, at: i64) -> i64 {
    (t1 - t0.max(at - MINT_FRESH).max(ONLINE_CUT)).max(0)
}

/// Section 1: a field its kind does not use is zero; a SEND names its commitment, a RECV and a REFUND the SEND they settle, and
/// the announced part of a SEND or RECV is never above its amount.
pub fn fields_hold(kind: u8, amount: u64, pair: &[u8], to: &[u8], refr: &[u8], a: u64, b: u64) -> bool {
    let none = [0u8; 32];
    match Kind::of(kind) {
        Some(Kind::Send) => refr == none && b == 0 && to != none && a <= amount,
        Some(Kind::Recv) => pair == none && b == 0 && refr != none && a <= amount,
        Some(Kind::Mint) => pair == none && to == none && refr == none,
        Some(Kind::Refund) => pair == none && to == none && refr != none && a == 0 && b == 0,
        Some(Kind::Genesis) => pair == none && to == none && refr == none && a == 0 && b == 0,
        Some(Kind::Burn) => pair == none && to == none && refr == none && b == 0 && a <= amount,
        None => false,
    }
}

/// A record read back (versions 2 and 3), believed only when its shape holds and the core verifies its signature.
#[derive(Clone, Debug)]
#[allow(dead_code)] // every field of the record as it is laid, read here or not
pub struct Rec {
    pub id: String,
    pub version: u8,
    pub kind: u8,
    pub amount: u64,
    pub birth_ms: u64,
    pub nonce: Vec<u8>,
    pub prev: String,
    pub pair: Vec<u8>,
    pub to: Vec<u8>,
    pub refr: String,
    pub a: u64,
    pub b: u64,
    pub from: String,
    pub bytes: Vec<u8>,
}

fn u64_at(b: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(b[at..at + 8].try_into().unwrap())
}
fn unhex(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) {
        return None;
    }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok()).collect()
}
pub fn unhex32(s: &str) -> Option<[u8; 32]> {
    unhex(s)?.try_into().ok()
}

/// A record's name: SHA-256 of its bytes, lowercase hex.
pub fn name(rec: &[u8]) -> String {
    hex(&sha(&[rec]))
}

/// THE RECORD OF VERSION 3 (section 1, 5443 bytes, little-endian), signed by the core over ASCII mt-coin-tx-v3 and bytes 0..2134.
#[allow(clippy::too_many_arguments)]
pub fn build3(h: &Hands, kind: Kind, amount: u64, birth_ms: u64, prev: &str, nonce: &[u8], pair: &[u8; 32], to: &[u8; 32], refr: &str, a: u64, b: u64) -> Option<Vec<u8>> {
    let (p, r) = (unhex32(prev)?, unhex32(refr)?);
    if nonce.len() != 16 || h.pk.len() != MT_MLDSA_PUBKEY_SIZE {
        return None;
    }
    let mut body = MAGIC.to_vec();
    body.push(3);
    body.push(kind as u8);
    body.extend_from_slice(&amount.to_le_bytes());
    body.extend_from_slice(&birth_ms.to_le_bytes());
    body.extend_from_slice(nonce);
    body.extend_from_slice(&p);
    body.extend_from_slice(pair);
    body.extend_from_slice(to);
    body.extend_from_slice(&r);
    body.extend_from_slice(&a.to_le_bytes());
    body.extend_from_slice(&b.to_le_bytes());
    body.extend_from_slice(&h.pk);
    if body.len() != BODY3 {
        return None;
    }
    let sig = h.sign(&[SIGNED3, &body].concat())?;
    body.extend_from_slice(&sig);
    Some(body)
}

pub fn read(rec: &[u8]) -> Option<Rec> {
    if rec.len() < 5 || &rec[..4] != MAGIC {
        return None;
    }
    match rec[4] {
        3 => read3(rec, false),
        2 => read2(rec, false),
        _ => None, // version 1 is read by no build of today
    }
}

/// A record read back by a copy of the network's chains (iOS read(_:known:)), version 1 among them -- read only, it stands on no
/// chain. known: a record of this very name verified here once, and the name is the hash of every byte, the signature's among them --
/// the same bytes, the same answer.
pub fn read_known(rec: &[u8], known: bool) -> Option<Rec> {
    if rec.len() < 5 || &rec[..4] != MAGIC {
        return None;
    }
    match rec[4] {
        3 => read3(rec, known),
        2 => read2(rec, known),
        1 => read1(rec, known),
        _ => None,
    }
}

fn read3(b: &[u8], known: bool) -> Option<Rec> {
    if b.len() != SIZE3 {
        return None;
    }
    let kind = b[5];
    let amount = u64_at(b, 6);
    let k = Kind::of(kind)?;
    if amount > i64::MAX as u64 || (amount == 0 && k != Kind::Genesis) {
        return None;
    }
    let (pair, to, refr, a, bb) = (&b[70..102], &b[102..134], &b[134..166], u64_at(b, 166), u64_at(b, 174));
    if !fields_hold(kind, amount, pair, to, refr, a, bb) {
        return None;
    }
    let pk = &b[182..BODY3];
    if !known && !verify(pk, &[SIGNED3, &b[..BODY3]].concat(), &b[BODY3..]) {
        return None;
    }
    Some(Rec {
        id: name(b), version: 3, kind, amount, birth_ms: u64_at(b, 14), nonce: b[22..38].to_vec(), prev: hex(&b[38..70]),
        pair: pair.to_vec(), to: to.to_vec(), refr: hex(refr), a, b: bb, from: key_tag(pk), bytes: b.to_vec(),
    })
}

fn read2(b: &[u8], known: bool) -> Option<Rec> {
    if b.len() != SIZE2 {
        return None;
    }
    let amount = u64_at(b, 5);
    if amount == 0 || amount > i64::MAX as u64 {
        return None;
    }
    let pk = &b[101..BODY2];
    if !known && !verify(pk, &[SIGNED2, &b[..BODY2]].concat(), &b[BODY2..]) {
        return None;
    }
    Some(Rec {
        id: name(b), version: 2, kind: Kind::Send as u8, amount, birth_ms: u64_at(b, 13), nonce: b[21..37].to_vec(), prev: hex(&b[69..101]),
        pair: b[37..69].to_vec(), to: vec![0; 32], refr: ZERO.into(), a: 0, b: 0, from: key_tag(pk), bytes: b.to_vec(),
    })
}

/// Version 1 (Audit/COIN-TX-V1.md): builds 2190 and older sent it; no chain holds it, a copy only verifies it.
fn read1(b: &[u8], known: bool) -> Option<Rec> {
    if b.len() != SIZE1 {
        return None;
    }
    let amount = u64_at(b, 5);
    if amount == 0 || amount > i64::MAX as u64 {
        return None;
    }
    let pk = &b[69..BODY1];
    if !known && !verify(pk, &[SIGNED1, &b[..BODY1]].concat(), &b[BODY1..]) {
        return None;
    }
    Some(Rec {
        id: name(b), version: 1, kind: Kind::Send as u8, amount, birth_ms: u64_at(b, 13), nonce: vec![], prev: String::new(),
        pair: b[37..69].to_vec(), to: vec![0; 32], refr: ZERO.into(), a: 0, b: 0, from: key_tag(pk), bytes: b.to_vec(),
    })
}

/// A key's state folded over its chain (section 3).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct St {
    pub head: String,
    pub height: i64,
    pub birth: i64,
    pub mint_end: i64,
    pub proven: i64,
    pub declared: i64,
    pub v3: bool,
    pub last_at: i64,
    pub minted: i64,
}
impl St {
    pub fn new() -> St {
        St { head: ZERO.into(), ..Default::default() }
    }
}

#[derive(Clone, Debug)]
pub struct SendInfo {
    pub from: String,
    pub amount: i64,
    pub at: i64,
    pub to: Vec<u8>,
    pub dec: i64,
}

/// A v2 record that spent stands open as a SEND (section 5, fold-4): on an opened chain it takes this declared part.
pub fn v2_spent(s: &St, amount: i64) -> Option<i64> {
    (s.v3 && amount <= s.proven + s.declared).then(|| (amount - s.proven).max(0))
}

/// ONE RECORD FOLDED ONTO ITS KEY'S STATE BY THE NODES' RULES (iOS MTCoinChainRules.step): the next state, or None for a record
/// that breaks a rule; `wait` for a RECV or REFUND whose SEND is not folded yet.
pub fn step(s: &St, p: &Rec, at: i64, sends: &std::collections::HashMap<String, SendInfo>, settled: &std::collections::HashSet<String>) -> (Option<St>, bool) {
    // first the key's time, then the record's kind (section 3, fold-6); a refused record leaves the state as it stood
    let timed = if p.version == 3 { time_step(s, at) } else { s.clone() };
    let s = &timed;
    let mut n = s.clone();
    n.head = p.id.clone();
    n.height += 1;
    n.last_at = at.max(s.last_at);
    if s.height == 0 {
        n.birth = at;
        n.mint_end = at;
    }
    let a = p.amount as i64;
    if p.version == 2 {
        // every transfer moves its balance: after the chain opened, a send that names no receiver spends as a SEND, proven first
        if !s.v3 {
            return (Some(n), false);
        }
        let Some(d) = v2_spent(s, a) else { return (None, false) };
        n.proven = s.proven - (a - d);
        n.declared = s.declared - d;
        return (Some(n), false);
    }
    n.v3 = true;
    match Kind::of(p.kind) {
        Some(Kind::Genesis) => {
            if s.v3 || (0 < a && V2_CUT <= at) || genesis_cap() < a {
                return (None, false);
            }
            if 0 < a && GENESIS_GATE <= at && (s.height == 0 || time_a(at - s.birth) < a) {
                return (None, false);
            }
            n.declared = a;
        }
        Some(Kind::Mint) => {
            let (t0, t1) = (p.a as i64, p.b as i64);
            if s.height == 0 || t0 < s.mint_end || t1 < t0 + 60 || at < t1 {
                return (None, false);
            }
            // from the online cut the present seconds alone weigh it: the intervals never overlap, so the life's sum is not asked
            // and a key that minted above its life before the time cut mints its present seconds like any other (fold-8)
            if ONLINE_CUT <= at {
                if present(t0, t1, at) < a {
                    return (None, false);
                }
            } else if allow_time(t1 - s.birth, at) - s.minted < a {
                return (None, false);
            }
            n.proven = s.proven + a;
            n.mint_end = t1;
            n.minted = s.minted + a;
        }
        Some(Kind::Send) | Some(Kind::Burn) => {
            // a BURN spends as a SEND and names no one: no RECV or REFUND can name it (the open SENDs hold SENDs alone)
            if p.kind == Kind::Burn as u8 && at < ONLINE_CUT {
                return (None, false);
            }
            let dec = p.a as i64;
            if s.proven + s.declared < a || dec != (a - s.proven).max(0) {
                return (None, false);
            }
            n.proven = s.proven - (a - dec);
            n.declared = s.declared - dec;
        }
        Some(Kind::Recv) | Some(Kind::Refund) => {
            let Some(sd) = sends.get(&p.refr) else { return (None, true) };
            if sd.amount != a || settled.contains(&p.refr) {
                return (None, false);
            }
            if p.kind == Kind::Recv as u8 {
                let Some(f) = unhex32(&p.from) else { return (None, false) };
                if sd.dec != p.a as i64 || commitment(&f, &p.to).as_slice() != sd.to.as_slice() {
                    return (None, false);
                }
            } else if sd.from != p.from || at < sd.at + 86_400 {
                return (None, false);
            }
            n.proven = s.proven + a - sd.dec;
            n.declared = s.declared + sd.dec;
        }
        None => return (None, false),
    }
    (Some(n), false)
}

/// THE ROOT OF A CHECKPOINT (section 6): SHA-256 of ASCII mt-coin-root-v1, then for every key in ascending from its from, the id of
/// its last record at or before T, and the count of those records as u64 little-endian.
pub fn root(keys: &mut [([u8; 32], [u8; 32], u64)]) -> String {
    keys.sort_by(|a, b| a.0.cmp(&b.0));
    let mut parts: Vec<Vec<u8>> = vec![b"mt-coin-root-v1".to_vec()];
    for (from, last, count) in keys.iter() {
        parts.push([from.as_slice(), last.as_slice(), &count.to_le_bytes()].concat());
    }
    let refs: Vec<&[u8]> = parts.iter().map(|p| p.as_slice()).collect();
    hex(&sha(&refs))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::{HashMap, HashSet};

    fn counting(from: u8) -> Vec<u8> {
        (from..from + 32).collect()
    }

    #[test]
    fn the_commitment_the_blind_and_the_time_agree_with_the_vectors() {
        // V1 the receiver's commitment
        assert_eq!(hex(&commitment(&counting(0), &counting(0x20))), "b08fb9c67b693f0cfe394de25474d2b79ae990a87a2f6a24bb7727560a8d88a4");
        // V2 the blind
        let nonce: Vec<u8> = (0x60..0x70).collect();
        assert_eq!(hex(&blind(&counting(0x40), &nonce)), "530efcc186fe26cb48fb4023c7a7e884c94516d14e62feaa06e81c76f89d7be4");
        // V3 the time a key may mint, A(x)
        for (x, a) in [(1, 2), (2, 4), (3, 6), (4, 10), (7, 22), (8, 28), (15, 70), (16, 78), (8191, 180_230), (8192, 180_256), (8193, 180_282), (86_400, 2_213_664)] {
            assert_eq!(time_a(x), a, "A({x})");
        }
        // from the second's cut: one coin a second of the key's life; a GENESIS of 0 for a key born after the v2 cut
        assert_eq!((allow_time(120, V2_CUT), allow_time(120, V2_CUT - 1)), (120, time_a(120)));
        assert_eq!(genesis_room(0, 0, V2_CUT + 10), 0);
        // V4 the root: keys a, b, c laid in the order a, c, b; a has 3 records, c 2, b 1; record i of key c is SHA-256("root head c i")
        let key = |c: &str| sha(&[format!("root key {c}").as_bytes()]);
        let head = |c: &str, i: u64| sha(&[format!("root head {c} {i}").as_bytes()]);
        let mut keys = vec![(key("a"), head("a", 2), 3u64), (key("c"), head("c", 1), 2), (key("b"), head("b", 0), 1)];
        assert_eq!(root(&mut keys), "4db30532f47a38696a81aa103cabea16ecf6034934cf26decbb9e78ad848b5e1");
    }

    fn rec(version: u8, kind: Kind, amount: u64, a: u64, b: u64, refr: &str) -> Rec {
        Rec { id: format!("{:064x}", amount * 1000 + kind as u64 * 10 + version as u64), version, kind: kind as u8, amount, birth_ms: 0,
              nonce: vec![0; 16], prev: ZERO.into(), pair: vec![0; 32], to: vec![0; 32], refr: refr.into(), a, b, from: "S".into(), bytes: vec![] }
    }

    #[test]
    fn a_v2_record_on_an_opened_chain_spends_as_a_send() {
        // V6: GENESIS 1000 declared (before the cut), MINT 500, SEND 1200 (dec 700), then a v2 record of 50: proven 0, declared 250;
        // a v2 record of 251 next is an overspend
        let (sends, settled) = (HashMap::new(), HashSet::new());
        let t = V2_CUT - 100_000;
        let mut s = St::new();
        s = step(&s, &rec(3, Kind::Genesis, 1000, 0, 0, ZERO), t, &sends, &settled).0.unwrap();
        s = step(&s, &rec(3, Kind::Mint, 500, t as u64, t as u64 + 600, ZERO), t + 600, &sends, &settled).0.unwrap();
        s = step(&s, &rec(3, Kind::Send, 1200, 700, 0, ZERO), t + 700, &sends, &settled).0.unwrap();
        s = step(&s, &rec(2, Kind::Send, 50, 0, 0, ZERO), t + 800, &sends, &settled).0.unwrap();
        assert_eq!((s.proven, s.declared), (0, 250));
        assert!(step(&s, &rec(2, Kind::Send, 251, 0, 0, ZERO), t + 900, &sends, &settled).0.is_none(), "overspend");
        // after the cut: a GENESIS above 0 is refused, a MINT is weighed one coin a second of the key's life
        let after = V2_CUT + 1000;
        assert!(step(&St::new(), &rec(3, Kind::Genesis, 5, 0, 0, ZERO), after, &sends, &settled).0.is_none());
        let g = step(&St::new(), &rec(3, Kind::Genesis, 0, 0, 0, ZERO), after, &sends, &settled).0.unwrap();
        assert!(step(&g, &rec(3, Kind::Mint, 121, after as u64, after as u64 + 120, ZERO), after + 120, &sends, &settled).0.is_none());
        let m = step(&g, &rec(3, Kind::Mint, 120, after as u64, after as u64 + 120, ZERO), after + 120, &sends, &settled).0.unwrap();
        assert_eq!((m.proven, m.minted, m.mint_end), (120, 120, after + 120));
    }

    /// FOLD-6, 7 AND 8 AS iOS 2304 READS THEM (MTCoinChainRules.timeStep, present, step): from the time cut the chain credits the key's
    /// life itself and a MINT of it is refused; the past never eats the present; from the online cut a MINT is weighed by its present
    /// seconds alone and a BURN spends as a SEND.
    #[test]
    fn the_chain_mints_the_keys_time_and_from_the_online_cut_only_presence_mints() {
        let (sends, settled) = (HashMap::new(), HashSet::new());
        let born = TIME_CUT - 1000;
        let s = St { v3: true, height: 2, birth: born, mint_end: born, last_at: TIME_CUT - 10, minted: 500, proven: 500, ..St::new() };
        assert_eq!(time_step(&s, TIME_CUT - 1), s, "before the time cut the life is not credited");
        let t = time_step(&s, TIME_CUT + 100);
        assert_eq!((t.proven, t.minted), (1100, 1100), "the unminted life up to the record: 1100 - 500");
        // a key that minted above its life before the cut gets the seconds since its last record, never before the cut (fold-8)
        let over = St { minted: 50_000, proven: 50_000, ..s.clone() };
        assert_eq!(time_step(&over, TIME_CUT + 100).proven, 50_100);
        // never past the online cut
        assert_eq!(time_step(&s, ONLINE_CUT + 5000).minted, ONLINE_CUT - born);
        // between the cuts the life is the chain's: a MINT of it is refused, a GENESIS of 0 and a SEND fold on the credited life
        let at = TIME_CUT + 600;
        assert!(step(&s, &rec(3, Kind::Mint, 60, (TIME_CUT + 400) as u64, (TIME_CUT + 500) as u64, ZERO), at, &sends, &settled).0.is_none());
        let sent = step(&s, &rec(3, Kind::Send, 1500, 0, 0, ZERO), at, &sends, &settled).0.unwrap();
        assert_eq!((sent.proven, sent.minted), (1600 - 1500, 1600));
        // a v2 record is no v3 record: the life is not folded by it
        assert_eq!(step(&s, &rec(2, Kind::Send, 10, 0, 0, ZERO), at, &sends, &settled).0.unwrap().minted, 500);
        // from the online cut: what the interval holds of the last 120 seconds before the node took it
        assert_eq!(present(ONLINE_CUT + 100, ONLINE_CUT + 200, ONLINE_CUT + 230), 90);
        assert_eq!(present(ONLINE_CUT - 300, ONLINE_CUT + 60, ONLINE_CUT + 60), 60, "never a second before the cut");
        let on = St { mint_end: ONLINE_CUT, last_at: ONLINE_CUT, ..s.clone() };
        let (t0, t1) = (ONLINE_CUT + 100, ONLINE_CUT + 200);
        assert!(step(&on, &rec(3, Kind::Mint, 91, t0 as u64, t1 as u64, ZERO), t1 + 30, &sends, &settled).0.is_none());
        let m = step(&on, &rec(3, Kind::Mint, 90, t0 as u64, t1 as u64, ZERO), t1 + 30, &sends, &settled).0.unwrap();
        assert_eq!((m.proven - on.proven, m.mint_end), (ONLINE_CUT - born - 500 + 90, t1), "the life up to the cut, then the present");
        // a BURN: refused before the online cut, a SEND that names no one after it
        assert!(fields_hold(6, 40, &[0; 32], &[0; 32], &[0; 32], 0, 0) && !fields_hold(6, 40, &[0; 32], &[1; 32], &[0; 32], 0, 0));
        assert!(step(&s, &rec(3, Kind::Burn, 40, 0, 0, ZERO), ONLINE_CUT - 1, &sends, &settled).0.is_none());
        let b = step(&m, &rec(3, Kind::Burn, 40, 0, 0, ZERO), t1 + 40, &sends, &settled).0.unwrap();
        assert_eq!(b.proven, m.proven - 40);
        // iOS 2305 since: what the time step adds between two node seconds, no record laid -- one a second between the cuts
        assert_eq!(since(TIME_CUT - 5, TIME_CUT + 100), 0, "a word told before the time cut grows by nothing");
        assert_eq!(since(TIME_CUT + 10, TIME_CUT + 25), 15);
        assert_eq!(since(ONLINE_CUT - 5, ONLINE_CUT + 100), 5, "never past the online cut");
        assert_eq!(since(ONLINE_CUT + 1, ONLINE_CUT + 100), 0);
        // the chain's later word is the earlier one plus these seconds (no record between)
        let early = time_step(&s, TIME_CUT + 100);
        assert_eq!(time_step(&s, TIME_CUT + 160).proven, early.proven + since(TIME_CUT + 100, TIME_CUT + 160));
    }

    #[test]
    fn a_send_and_its_recv_signed_by_the_core_are_the_vectors_records() {
        // V5: S and R from the seeds SHA-256("seed v3 vector S"/"R"); the core's ML-DSA-65 is deterministic
        let s = Hands::from_seed(&sha(&[b"seed v3 vector S"])).unwrap();
        let r = Hands::from_seed(&sha(&[b"seed v3 vector R"])).unwrap();
        let nonce = &sha(&[b"nonce v3 S"])[..16];
        let pair = sha(&[b"pair v3 S"]);
        let bl = blind(&sha(&[b"secret v3 S"]), nonce);
        let to = commitment(&unhex32(&r.from()).unwrap(), &bl);
        let send = build3(&s, Kind::Send, 1234, 1_760_300_000_000, ZERO, nonce, &pair, &to, ZERO, 0, 0).unwrap();
        assert_eq!(send.len(), SIZE3);
        assert_eq!(hex(&sha(&[SIGNED3, &send[..BODY3]])), "cf00d783cfb5364e6c00afdaaeb203b32635b31d6894650f3fb68d7b3c96e3e5");
        assert_eq!(name(&send), "2dd4cf64695222b31d4cd0c799a1f21888aaacb83bab7febfce055f6b7da46fa");
        let back = read(&send).unwrap();
        assert_eq!((back.kind, back.amount, back.from.as_str()), (1, 1234, s.from().as_str()));
        let recv = build3(&r, Kind::Recv, 1234, 1_760_300_000_000, ZERO, &sha(&[b"nonce v3 R"])[..16], &[0; 32], &bl, &back.id, 0, 0).unwrap();
        assert_eq!(name(&recv), "ce5a492c063c71435ccb9582e3662c1d876310fe04d2846d73f7d07bd0236646");
        // the RECV opens the SEND for R's chain alone
        let rr = read(&recv).unwrap();
        let mut sends = HashMap::new();
        sends.insert(back.id.clone(), SendInfo { from: back.from.clone(), amount: 1234, at: 0, to: back.to.clone(), dec: 0 });
        let opened = step(&St { v3: true, height: 1, head: ZERO.into(), ..St::new() }, &rr, 10, &sends, &HashSet::new()).0.unwrap();
        assert_eq!(opened.proven, 1234);
        let mut wrong = rr.clone();
        wrong.from = s.from();
        assert!(step(&St { v3: true, height: 1, ..St::new() }, &wrong, 10, &sends, &HashSet::new()).0.is_none());
        // a record whose byte moved is no record
        let mut broken = send.clone();
        broken[7] ^= 1;
        assert!(read(&broken).is_none());
    }
}
