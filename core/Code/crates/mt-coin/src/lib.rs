#![forbid(unsafe_code)]
// The fold of a coin key's chain (COIN-TX-V3, sections 3 and 4). Pure by construction: a record's
// signature is the core's mt_verify, the SEND a RECV or a REFUND settles comes from the caller's
// ledger, and the second a record is taken at is the chain node's, never a clock read here. Every
// amount of the state is a u128: the reference node folds in unbounded integers, and a sum of u64
// amounts must compare the same way.

use sha2::{Digest, Sha256};

pub const TX_MAGIC: &[u8; 4] = b"MTTX";
pub const TX2_LEN: usize = 5362;
pub const TX3_LEN: usize = 5443;

pub const TX_V2_CUT: u64 = 1_792_443_600;
// One second, one coin from the second of the v2 cut, so every GENESIS above 0 is weighed before it.
pub const TX_SECOND_CUT: u64 = TX_V2_CUT;
pub const TX_COIN_EPOCH: u64 = 1_788_210_000;
pub const TX_GENESIS_GATE: u64 = 1_792_354_500;
pub const TX_TIME_CUT: u64 = 1_792_702_800;
// Minting is its own road from this second on (fold-7): the key's life stops minting by itself, and
// a MINT counts only the seconds its key was present -- online, or behind its VPN -- the last
// TX_MINT_FRESH seconds before the node takes it. A BURN is taken from the same second.
pub const TX_ONLINE_CUT: u64 = 1_792_962_000;
pub const TX_MINT_FRESH: u64 = 120;
// Minting by a record stops at this second (fold-9, decision 362 a of the Author, 29.10.2026): a coin
// is born only by the window right of the consensus core (Montana-Core window_credit), never by a
// record a client lays. From it on a node takes no MINT at all; a GENESIS above 0 is refused since
// TX_V2_CUT and the key's life credits nothing since TX_ONLINE_CUT, so no record mints from here.
// Every record taken before it keeps its fate at a re-fold: the rule is chosen by the node's second.
pub const TX_MINT_STOP: u64 = 1_793_361_600;
pub const TX_DAY: u64 = 86_400;
pub const TX_MINT_MIN: u64 = 60;
// A change of the fold's rules re-folds every chain at a node's next start, so the rules have a name.
pub const TX_FOLD: &str = "fold-9";
pub const TX_GENESIS_CAP: u128 = a2(TX_V2_CUT - TX_COIN_EPOCH);

const TX_LIMIT: u128 = 13;
const TX_MUSIC: u128 = 2;
const TX_TO: &[u8] = b"mt-coin-to";
const ZERO: [u8; 32] = [0; 32];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Send,
    Recv,
    Mint,
    Refund,
    Genesis,
    Burn,
}

impl Kind {
    fn from_byte(b: u8) -> Option<Kind> {
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Record {
    pub id: [u8; 32],
    pub version: u8,
    pub kind: Kind,
    pub amount: u64,
    pub prev: [u8; 32],
    pub pair: [u8; 32],
    pub to: [u8; 32],
    pub reference: [u8; 32],
    pub t0: u64,
    pub t1: u64,
    pub dec: u64,
    pub from: [u8; 32],
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParseError {
    Magic,
    Version,
    Length,
    Kind,
    Field,
    Amount,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct KeyState {
    pub head: [u8; 32],
    pub height: u64,
    pub birth: u64,
    pub mint_end: u64,
    pub proven: u128,
    pub declared: u128,
    pub last_at: u64,
    pub v3: bool,
    pub minted: u128,
}

// A key's state as a node keeps it beside the chain and hands it to the core: head, height, birth,
// mint_end, proven, declared, last_at, v3, minted -- the struct's own order, little-endian.
pub const STATE_LEN: usize = 113;

fn u128_at(b: &[u8], at: usize) -> u128 {
    let mut w = [0u8; 16];
    w.copy_from_slice(&b[at..at + 16]);
    u128::from_le_bytes(w)
}

impl KeyState {
    pub fn encode(&self) -> [u8; STATE_LEN] {
        let mut b = [0u8; STATE_LEN];
        b[..32].copy_from_slice(&self.head);
        b[32..40].copy_from_slice(&self.height.to_le_bytes());
        b[40..48].copy_from_slice(&self.birth.to_le_bytes());
        b[48..56].copy_from_slice(&self.mint_end.to_le_bytes());
        b[56..72].copy_from_slice(&self.proven.to_le_bytes());
        b[72..88].copy_from_slice(&self.declared.to_le_bytes());
        b[88..96].copy_from_slice(&self.last_at.to_le_bytes());
        b[96] = u8::from(self.v3);
        b[97..113].copy_from_slice(&self.minted.to_le_bytes());
        b
    }

    // The v3 flag is 0 or 1, so one state has one reading.
    pub fn decode(b: &[u8; STATE_LEN]) -> Option<KeyState> {
        let v3 = match b[96] {
            0 => false,
            1 => true,
            _ => return None,
        };
        Some(KeyState {
            head: b32(b, 0),
            height: u64_at(b, 32),
            birth: u64_at(b, 40),
            mint_end: u64_at(b, 48),
            proven: u128_at(b, 56),
            declared: u128_at(b, 72),
            last_at: u64_at(b, 88),
            v3,
            minted: u128_at(b, 97),
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refusal {
    NotOnTheHead,
    Overspend,
    Split,
    Genesis,
    GenesisLate,
    GenesisAmount,
    GenesisPast,
    NoBirth,
    Interval,
    Allowance,
    NoSend,
    Amount,
    NotYours,
    Early,
    Settled,
    Stale,
    NotYet,
    Stopped,
}

impl Refusal {
    // The node's 409 says these very words; a phone and the Explorer show them as they are.
    pub fn word(self) -> &'static str {
        match self {
            Refusal::NotOnTheHead => "not on the head",
            Refusal::Overspend => "overspend",
            Refusal::Split => "split",
            Refusal::Genesis => "genesis",
            Refusal::GenesisLate => "genesis late",
            Refusal::GenesisAmount => "genesis amount",
            Refusal::GenesisPast => "genesis past",
            Refusal::NoBirth => "no birth",
            Refusal::Interval => "interval",
            Refusal::Allowance => "allowance",
            Refusal::NoSend => "no send",
            Refusal::Amount => "amount",
            Refusal::NotYours => "not yours",
            Refusal::Early => "early",
            Refusal::Settled => "settled",
            Refusal::Stale => "stale",
            Refusal::NotYet => "not yet",
            Refusal::Stopped => "minting stopped",
        }
    }

    // The declaration's order: a refusal crosses the C door as its place in it, counted from 1.
    pub const ALL: [Refusal; 18] = [
        Refusal::NotOnTheHead,
        Refusal::Overspend,
        Refusal::Split,
        Refusal::Genesis,
        Refusal::GenesisLate,
        Refusal::GenesisAmount,
        Refusal::GenesisPast,
        Refusal::NoBirth,
        Refusal::Interval,
        Refusal::Allowance,
        Refusal::NoSend,
        Refusal::Amount,
        Refusal::NotYours,
        Refusal::Early,
        Refusal::Settled,
        Refusal::Stale,
        Refusal::NotYet,
        Refusal::Stopped,
    ];

    pub fn code(self) -> u8 {
        self as u8 + 1
    }

    pub fn from_code(code: u8) -> Option<Refusal> {
        Refusal::ALL.get(usize::from(code).checked_sub(1)?).copied()
    }
}

// What the ledger holds of a SEND a RECV or a REFUND names: a v3 SEND, or a v2 record that spent
// on an opened chain -- then its to is zero, so no RECV opens it, and its dec is the one its fold
// step took.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SendFacts {
    pub from: [u8; 32],
    pub amount: u64,
    pub at: u64,
    pub to: [u8; 32],
    pub dec: u64,
}

pub trait Ledger {
    fn send(&self, id: &[u8; 32]) -> Option<SendFacts>;
    fn settled(&self, id: &[u8; 32]) -> bool;
}

// from, amount, at, to, dec -- little-endian.
pub const SENT_LEN: usize = 88;

impl SendFacts {
    pub fn encode(&self) -> [u8; SENT_LEN] {
        let mut b = [0u8; SENT_LEN];
        b[..32].copy_from_slice(&self.from);
        b[32..40].copy_from_slice(&self.amount.to_le_bytes());
        b[40..48].copy_from_slice(&self.at.to_le_bytes());
        b[48..80].copy_from_slice(&self.to);
        b[80..88].copy_from_slice(&self.dec.to_le_bytes());
        b
    }

    pub fn decode(b: &[u8; SENT_LEN]) -> SendFacts {
        SendFacts {
            from: b32(b, 0),
            amount: u64_at(b, 32),
            at: u64_at(b, 40),
            to: b32(b, 48),
            dec: u64_at(b, 80),
        }
    }
}

// The ledger as one record sees it: the SEND its reference names, if the node holds it, and whether
// a RECV or a REFUND has settled it -- all a node outside Rust hands the core for one step.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Named {
    pub reference: [u8; 32],
    pub sent: Option<SendFacts>,
    pub settled: bool,
}

impl Ledger for Named {
    fn send(&self, id: &[u8; 32]) -> Option<SendFacts> {
        if *id == self.reference {
            self.sent
        } else {
            None
        }
    }

    fn settled(&self, id: &[u8; 32]) -> bool {
        *id == self.reference && self.settled
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Folded {
    pub state: KeyState,
    // The declared part a v2 record that spent took; the ledger keeps it beside the record, so its
    // REFUND gives back the same split (fold-4).
    pub v2_dec: Option<u64>,
}

fn sha256(parts: &[&[u8]]) -> [u8; 32] {
    let mut h = Sha256::new();
    for part in parts {
        h.update(part);
    }
    h.finalize().into()
}

fn u64_at(b: &[u8], at: usize) -> u64 {
    let mut w = [0u8; 8];
    w.copy_from_slice(&b[at..at + 8]);
    u64::from_le_bytes(w)
}

fn b32(b: &[u8], at: usize) -> [u8; 32] {
    let mut w = [0u8; 32];
    w.copy_from_slice(&b[at..at + 32]);
    w
}

pub fn commitment(from: &[u8; 32], blind: &[u8; 32]) -> [u8; 32] {
    sha256(&[TX_TO, from, blind])
}

pub fn parse(rec: &[u8]) -> Result<Record, ParseError> {
    if rec.len() < 5 || rec[..4] != TX_MAGIC[..] {
        return Err(ParseError::Magic);
    }
    let id = sha256(&[rec]);
    match rec[4] {
        2 => {
            if rec.len() != TX2_LEN {
                return Err(ParseError::Length);
            }
            let amount = u64_at(rec, 5);
            if amount == 0 {
                return Err(ParseError::Amount);
            }
            Ok(Record {
                id,
                version: 2,
                kind: Kind::Send,
                amount,
                prev: b32(rec, 69),
                pair: b32(rec, 37),
                to: ZERO,
                reference: ZERO,
                t0: 0,
                t1: 0,
                dec: 0,
                from: sha256(&[&rec[101..2053]]),
            })
        },
        3 => {
            if rec.len() != TX3_LEN {
                return Err(ParseError::Length);
            }
            let kind = Kind::from_byte(rec[5]).ok_or(ParseError::Kind)?;
            let (pair, to, reference) = (b32(rec, 70), b32(rec, 102), b32(rec, 134));
            let (t0, t1) = (u64_at(rec, 166), u64_at(rec, 174));
            // A field its kind does not use is zero, so one record has one reading.
            let (uses_pair, uses_to, uses_ref, uses_t0, uses_t1) = match kind {
                Kind::Send => (true, true, false, true, false),
                Kind::Recv => (false, true, true, true, false),
                Kind::Mint => (false, false, false, true, true),
                Kind::Refund => (false, false, true, false, false),
                Kind::Genesis => (false, false, false, false, false),
                Kind::Burn => (false, false, false, true, false),
            };
            let stray = (!uses_pair && pair != ZERO)
                || (!uses_to && to != ZERO)
                || (!uses_ref && reference != ZERO)
                || (!uses_t0 && t0 != 0)
                || (!uses_t1 && t1 != 0);
            let unnamed = (kind == Kind::Send && to == ZERO)
                || (matches!(kind, Kind::Recv | Kind::Refund) && reference == ZERO);
            if stray || unnamed {
                return Err(ParseError::Field);
            }
            let dec = if matches!(kind, Kind::Send | Kind::Recv | Kind::Burn) {
                t0
            } else {
                0
            };
            let amount = u64_at(rec, 6);
            if amount < dec || (amount == 0 && kind != Kind::Genesis) {
                return Err(ParseError::Amount);
            }
            Ok(Record {
                id,
                version: 3,
                kind,
                amount,
                prev: b32(rec, 38),
                pair,
                to,
                reference,
                t0,
                t1,
                dec,
                from: sha256(&[&rec[182..2134]]),
            })
        },
        _ => Err(ParseError::Version),
    }
}

// A_2(x): what the seconds 1..x of a key's life could mint before TX_SECOND_CUT, and the bound of
// every GENESIS -- 2 x min(13, max(1, bit_length(s) - 1)) for the s-th second, summed a doubling
// at a time.
pub const fn a2(x: u64) -> u128 {
    let x = x as u128;
    let (mut total, mut lo, mut k) = (0u128, 1u128, 0u128);
    while lo <= x {
        let hi = if x < 2 * lo - 1 { x } else { 2 * lo - 1 };
        let level = if k < 1 {
            1
        } else if k > TX_LIMIT {
            TX_LIMIT
        } else {
            k
        };
        total += (hi - lo + 1) * level;
        lo *= 2;
        k += 1;
    }
    TX_MUSIC * total
}

// The rule a MINT is weighed by is chosen by the second the node took it at, never by its
// interval, so no record taken before the cut changes its fate at a re-fold.
pub fn allowance(lived: u64, at: u64) -> u128 {
    if TX_SECOND_CUT <= at {
        u128::from(lived)
    } else {
        a2(lived)
    }
}

// The key's time (fold-6): the seconds a key has lived up to at, credited once. From TX_ONLINE_CUT
// (fold-7) the life credits nothing more: the seconds up to the cut stay credited, and every later
// second is minted only by a MINT of a present key. Every second from TX_TIME_CUT is credited
// (fold-8): a key that minted above its life before the cut keeps that past and still gets the
// seconds since its last record -- the past never eats the present.
pub fn time_step(s: &KeyState, at: u64) -> KeyState {
    if at < TX_TIME_CUT || s.height == 0 {
        return *s;
    }
    let end = at.min(TX_ONLINE_CUT);
    let lived = u128::from(end.saturating_sub(s.birth));
    let fresh = u128::from(end.saturating_sub(s.last_at.max(TX_TIME_CUT).max(s.birth)));
    let credit = lived.saturating_sub(s.minted).max(fresh);
    if credit == 0 {
        return *s;
    }
    KeyState {
        proven: s.proven + credit,
        minted: s.minted + credit,
        ..*s
    }
}

// The balance a phone shows is the chain's own fold at the node's second, never a record laid for
// it, and never folded below the head's own second.
pub fn at_now(s: &KeyState, now: u64) -> KeyState {
    time_step(s, now.max(s.last_at))
}

pub fn step<L: Ledger>(s: &KeyState, r: &Record, at: u64, ledger: &L) -> Result<Folded, Refusal> {
    if r.prev != s.head {
        return Err(Refusal::NotOnTheHead);
    }
    let s = if r.version == 3 { time_step(s, at) } else { *s };
    let mut n = KeyState {
        head: r.id,
        height: s.height.saturating_add(1),
        last_at: at.max(s.last_at),
        ..s
    };
    if s.height == 0 {
        n.birth = at;
        n.mint_end = at;
    }
    let a = u128::from(r.amount);
    if r.version == 2 {
        // Before the key's first v3 record a v2 record is the book's own past, which the GENESIS
        // announces as it stood after it; from it on, every transfer moves its balance.
        if !s.v3 {
            return Ok(Folded {
                state: n,
                v2_dec: None,
            });
        }
        if s.proven + s.declared < a {
            return Err(Refusal::Overspend);
        }
        let d = a.saturating_sub(s.proven);
        n.proven = s.proven - (a - d);
        n.declared = s.declared - d;
        // d is at most the record's own u64 amount.
        return Ok(Folded {
            state: n,
            v2_dec: Some(d as u64),
        });
    }
    n.v3 = true;
    match r.kind {
        Kind::Genesis => {
            if s.v3 {
                return Err(Refusal::Genesis);
            }
            if a > 0 && TX_V2_CUT <= at {
                return Err(Refusal::GenesisLate);
            }
            if TX_GENESIS_CAP < a {
                return Err(Refusal::GenesisAmount);
            }
            if a > 0
                && TX_GENESIS_GATE <= at
                && (s.height == 0 || a2(at.saturating_sub(s.birth)) < a)
            {
                return Err(Refusal::GenesisPast);
            }
            n.declared = a;
        },
        Kind::Mint => {
            if TX_MINT_STOP <= at {
                return Err(Refusal::Stopped);
            }
            if s.height == 0 {
                return Err(Refusal::NoBirth);
            }
            if r.t0 < s.mint_end
                || u128::from(r.t1) < u128::from(r.t0) + u128::from(TX_MINT_MIN)
                || at < r.t1
            {
                return Err(Refusal::Interval);
            }
            // Present seconds only (fold-7): a MINT counts what its interval holds of the last
            // TX_MINT_FRESH seconds before the node took it, so the seconds of a key away from the
            // network are never minted afterwards. Its seconds start at TX_ONLINE_CUT, the time step
            // having credited every one before it, and the intervals never overlap (t0 at least
            // mint_end), so one second mints one coin without the life's sum (fold-8): a key that
            // minted above its life before TX_TIME_CUT mints its present seconds like any other.
            if TX_ONLINE_CUT <= at {
                let present = r.t1.saturating_sub(
                    r.t0.max(at.saturating_sub(TX_MINT_FRESH))
                        .max(TX_ONLINE_CUT),
                );
                if u128::from(present) < a {
                    return Err(Refusal::Stale);
                }
            } else if allowance(r.t1.saturating_sub(s.birth), at) < s.minted + a {
                return Err(Refusal::Allowance);
            }
            n.proven = s.proven + a;
            n.mint_end = r.t1;
            n.minted = s.minted + a;
        },
        Kind::Send | Kind::Burn => {
            // Proven is spent first, and what the SEND names as declared is exactly the rest, so
            // its receiver inherits the same split. A BURN spends the same way and names no one:
            // its coins leave every chain, and no RECV or REFUND can name it (a ledger holds SENDs
            // alone).
            if r.kind == Kind::Burn && at < TX_ONLINE_CUT {
                return Err(Refusal::NotYet);
            }
            if s.proven + s.declared < a {
                return Err(Refusal::Overspend);
            }
            let dec = u128::from(r.dec);
            if dec != a.saturating_sub(s.proven) {
                return Err(Refusal::Split);
            }
            n.proven = s.proven - (a - dec);
            n.declared = s.declared - dec;
        },
        Kind::Recv | Kind::Refund => {
            let sent = ledger.send(&r.reference).ok_or(Refusal::NoSend)?;
            if sent.amount != r.amount {
                return Err(Refusal::Amount);
            }
            if r.kind == Kind::Recv && sent.dec != r.dec {
                return Err(Refusal::Split);
            }
            if r.kind == Kind::Recv && commitment(&r.from, &r.to) != sent.to {
                return Err(Refusal::NotYours);
            }
            if r.kind == Kind::Refund && sent.from != r.from {
                return Err(Refusal::NotYours);
            }
            if r.kind == Kind::Refund && u128::from(at) < u128::from(sent.at) + u128::from(TX_DAY) {
                return Err(Refusal::Early);
            }
            if ledger.settled(&r.reference) {
                return Err(Refusal::Settled);
            }
            let dec = u128::from(sent.dec);
            // Proven never falls below zero: a ledger whose SEND declares more than it moves is
            // refused, never folded.
            n.proven = (s.proven + a).checked_sub(dec).ok_or(Refusal::Split)?;
            n.declared = s.declared + dec;
        },
    }
    Ok(Folded {
        state: n,
        v2_dec: None,
    })
}

// A whole chain in its order, each record with the second its chain node took it at: the state of
// its head, or the place of the first record refused and why.
pub fn fold<L: Ledger>(chain: &[(Record, u64)], ledger: &L) -> Result<KeyState, (usize, Refusal)> {
    let mut s = KeyState::default();
    for (i, (r, at)) in chain.iter().enumerate() {
        s = step(&s, r, *at, ledger).map_err(|e| (i, e))?.state;
    }
    Ok(s)
}
