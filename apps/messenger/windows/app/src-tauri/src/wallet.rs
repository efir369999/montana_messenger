//! THE COINS ON THE NODES (iOS MTCoinTx's roads, MTCoinSplit; Audit/COIN-TX-V3.md): the book's coins stand on the person's own
//! chain -- its first v3 record a GENESIS (of 0 since the v2 cut), what the book holds above the chain laid as a MINT within the time
//! the key lived, once a window of τ1. Coins to a person are a SEND on my chain committed to their key under the pair's blind; the
//! receiver's RECV takes it on theirs, and a SEND nobody took comes back by a REFUND after a day. Every record is laid only on the
//! head this machine read and verified as its own; the node's word decides, never the phone's clock.

use crate::coins;
use crate::cointx::{self, Hands, Kind, ZERO};
use crate::doors;
use crate::vault::Vault;
use serde_json::{json, Value};
use std::sync::Mutex;

const STATE: &str = "coin3";

/// A key's chain as its node folds it (POST /tx-head), and the node's own second.
#[derive(Clone, Debug, Default)]
pub struct Chain3 {
    pub head: String,
    pub height: i64,
    pub birth: i64,
    pub mint_end: i64,
    pub proven: i64,
    pub declared: i64,
    pub v3: bool,
    pub now: i64,
    pub minted: Option<i64>,
}

/// My coin key's tag, derived once a run (iOS cachedKeyTag): the about word carries it to every correspondent.
pub static MY_FROM: Mutex<Option<String>> = Mutex::new(None);

/// The seed's coin key of the person seated.
pub fn hands(words: &str) -> Option<Hands> {
    let h = Hands::from_master(&crate::seed::master_of(words)?)?;
    *MY_FROM.lock().unwrap() = Some(h.from());
    *HELD.lock().unwrap() = Some(std::sync::Arc::new(h.clone()));
    Some(h)
}
/// The coin key this process derived for its person (one person a process): the roads that pay away from the walk ask it.
static HELD: Mutex<Option<std::sync::Arc<Hands>>> = Mutex::new(None);
pub fn held_hands() -> Option<std::sync::Arc<Hands>> {
    HELD.lock().unwrap().clone()
}

/// AN AUTO-REACTION'S COINS ARE A SEND OF THE CHAIN (iOS 2304 MTCoinSend.autoGive, MTCoinTx.once): the letter's landing only names
/// the pay -- a SEND goes to the network, which a landing never waits on -- and the coin walk pays it; once a letter: the name
/// «auto:» and the letter's wire name is taken before the SEND goes (two days are kept, a letter is paid within one), and a SEND
/// that never went gives the name back.
static AUTO: Mutex<Vec<(String, String, i64)>> = Mutex::new(Vec::new());
pub fn auto_queue(vault: &Vault, r: &str, mid: &str, coins_: i64) -> bool {
    let name = format!("auto:mid:{mid}");
    let now = crate::wire::now_ms() / 1000;
    let mut s = state(vault);
    let mut once: serde_json::Map<String, Value> = s["once"].as_object().cloned().unwrap_or_default();
    once.retain(|_, at| now - at.as_i64().unwrap_or(0) < 2 * 86_400);
    if once.contains_key(&name) || coins::holds(vault, "spend", &name) {
        return false;
    }
    once.insert(name, json!(now));
    s["once"] = Value::Object(once);
    save(vault, &s);
    AUTO.lock().unwrap().push((r.to_string(), mid.to_string(), coins_));
    true
}
pub fn auto_take() -> Vec<(String, String, i64)> {
    std::mem::take(&mut *AUTO.lock().unwrap())
}
pub fn auto_release(vault: &Vault, mid: &str) {
    let mut s = state(vault);
    if s["once"].as_object_mut().and_then(|m| m.remove(&format!("auto:mid:{mid}"))).is_some() {
        save(vault, &s);
    }
}
/// Whether this correspondent was told my coin key (the about word carries it until then).
pub fn told_key(vault: &Vault, conv: &str, k: &str) -> bool {
    state(vault)["told"][conv].as_str() == Some(k)
}
pub fn note_told_key(vault: &Vault, conv: &str, k: &str) {
    let mut s = state(vault);
    s["told"][conv] = json!(k);
    save(vault, &s);
}
/// Their send found no key of mine (iOS forgetToldKey): the mark goes, and the next about word carries the key again.
pub fn forget_told_key(vault: &Vault, conv: &str) {
    let mut s = state(vault);
    if s["told"].as_object_mut().and_then(|m| m.remove(conv)).is_some() {
        save(vault, &s);
    }
}

type Split = (i64, i64, i64, i64, f64);
/// The chain's last word this run (iOS MTCoinSplit): proven, declared, height, the node's second it was told at and this computer's
/// moment then (iOS 2305 Split.second, at).
static SPLIT: Mutex<Option<Split>> = Mutex::new(None);
fn local_s() -> f64 {
    crate::wire::now_ms() as f64 / 1000.0
}
static MINTED_AT: Mutex<i64> = Mutex::new(0);

/// A chain's node asked through any door of it (iOS chainDoor: «through the api door when the phone knows it, else through any
/// door of that node the phone holds»): a door out of reach gives the ask to the next door of the same machine -- the same node,
/// whose word alone a record is believed by.
pub fn ask(door: &str, path: &str, body: &Value) -> (i32, Option<Value>) {
    let mut last = (-1, None);
    for d in doors::of_machine(door) {
        last = doors::post_at(&d, path, body, 15_000);
        if last.0 != -1 {
            break;
        }
    }
    last
}

fn num(o: &Value, k: &str) -> i64 {
    o[k].as_str().and_then(|s| s.parse().ok()).or_else(|| o[k].as_i64()).unwrap_or(0)
}

pub fn chain3(from: &str, door: &str) -> Option<Chain3> {
    let (code, o) = ask(door, "/tx-head", &json!({ "from": from }));
    let o = o.filter(|_| code == 200)?;
    let head = o["head"].as_str().filter(|h| h.len() == 64)?.to_string();
    let now = num(&o, "now");
    Some(Chain3 {
        head, height: num(&o, "height"), birth: num(&o, "birth"), mint_end: num(&o, "mint_end"), proven: num(&o, "proven"),
        declared: num(&o, "declared"), v3: num(&o, "v3") == 1, now: if now == 0 { crate::wire::now_ms() / 1000 } else { now },
        minted: (!o["minted"].is_null()).then(|| num(&o, "minted")),
    })
}

/// The head is believed only as my own signed record (iOS headIsMine): its bytes are its name, the core verifies it, it is my key's.
fn head_is_mine(head: &str, me: &str, door: &str) -> bool {
    if head == ZERO {
        return true;
    }
    let (code, o) = ask(door, "/tx-get", &json!({ "id": head }));
    let Some(b) = o.filter(|_| code == 200).and_then(|o| o["rec"].as_str().and_then(crate::wire::unb64)) else { return false };
    cointx::read(&b).is_some_and(|r| r.id == head && r.from == me && (r.version == 2 || r.version == 3))
}

/// One record of my key laid on my chain's head, the head read back and verified as mine first; a head that moved is asked again
/// once (iOS layOnHead): the node's code, its word, the record laid.
pub fn lay_on_head(h: &Hands, make: &dyn Fn(&Chain3) -> Option<Vec<u8>>) -> (i32, String, Option<Vec<u8>>) {
    let me = h.from();
    let Some(door) = cointx::chain_door(&me) else { return (-1, "no door".into(), None) };
    for _ in 0..2 {
        let Some(st) = chain3(&me, &door) else { return (-1, "no head".into(), None) };
        if !head_is_mine(&st.head, &me, &door) {
            return (-1, "head unverified".into(), None);
        }
        let Some(rec) = make(&st) else { return (-1, "no record".into(), None) };
        let (code, o) = ask(&door, "/tx-put", &json!({ "rec": crate::wire::b64(&rec) }));
        let word = o.as_ref().and_then(|o| o["error"].as_str()).unwrap_or("").to_string();
        if code == 200 {
            return (200, String::new(), Some(rec));
        }
        if code == 409 && word == "not on the head" {
            continue;
        }
        return (code, word, Some(rec));
    }
    (409, "not on the head".into(), None)
}

fn nonce() -> Vec<u8> {
    crate::crypto::random(16).unwrap_or_else(|| vec![7; 16])
}
fn birth_ms() -> u64 {
    crate::wire::now_ms().max(0) as u64
}

/// THE CHAIN HOLDS WHAT THE BOOK HOLDS (iOS reconcile, sections 3-4): the key's first v3 record its GENESIS (of 0 since the v2 cut);
/// then what the book holds above the chain laid as a MINT of the time since the last one, at most what the key's time allows --
/// once a window of τ1, or at once when a send needs it. The interval is the node's clock.
pub fn reconcile(vault: &Vault, h: &Hands, force: bool) -> Option<Chain3> {
    let me = h.from();
    let door = cointx::chain_door(&me)?;
    let mut st = chain3(&me, &door)?;
    let book = coins::balance(vault);
    if !st.v3 {
        let amount = book.max(0).min(cointx::genesis_room(st.height, st.birth, st.now));
        let (code, word, _) = lay_on_head(h, &|s| cointx::build3(h, Kind::Genesis, amount as u64, birth_ms(), &s.head, &nonce(), &[0; 32], &[0; 32], ZERO, 0, 0));
        mark(&format!("genesis code={code} word={word} amount={amount}"));
        if code != 200 {
            return None;
        }
        st = chain3(&me, &door)?;
    }
    // ONLY THE CHAIN MINTS (iOS reconcile, section 4, fold-6): from the node's TX_TIME_CUT the chain credits the key's seconds itself, so
    // the phone lays no MINT and shows the fold /tx-head answers -- until the node's TX_ONLINE_CUT, past which a key's life mints
    // nothing by itself
    if cointx::TIME_CUT <= st.now {
        // MINTING IS ITS OWN ROAD (fold-7): the node counts of a MINT only what its interval holds of the last MINT_FRESH seconds
        // before it takes it, so while the person is here the computer lays the seconds since the last MINT, never older than the
        // freshness less the road's margin; the node's minute between two MINTs is the pace
        if !(cointx::ONLINE_CUT <= st.now && here() && st.mint_end + 60 <= st.now) {
            told(&st);
            return Some(st);
        }
        let (code, word, _) = lay_on_head(h, &|s| {
            if s.height <= 0 || s.now < cointx::ONLINE_CUT {
                return None;
            }
            let t1 = s.now;
            let t0 = s.mint_end.max(t1 - cointx::MINT_FRESH + PRESENT_MARGIN);
            // the present seconds alone weigh it (fold-8): the life the node credited up to the online cut is not asked again
            let amount = cointx::present(t0, t1, t1 + PRESENT_MARGIN);
            if amount <= 0 || t1 < t0 + 60 {
                return None;
            }
            cointx::build3(h, Kind::Mint, amount as u64, birth_ms(), &s.head, &nonce(), &[0; 32], &[0; 32], ZERO, t0 as u64, t1 as u64)
        });
        mark(&format!("present mint code={code} word={word}"));
        let after = if code == 200 { chain3(&me, &door).unwrap_or(st) } else { st };
        told(&after);
        return Some(after);
    }
    let wall = crate::wire::now_ms() / 1000;
    {
        let mut at = MINTED_AT.lock().unwrap();
        if !force && wall - *at < cointx::WINDOW {
            told(&st);
            return Some(st);
        }
        *at = wall;
    }
    let gap = book - st.proven - st.declared;
    if gap <= 0 || st.now - 120 < st.mint_end + 60 {
        told(&st);
        return Some(st);
    }
    let (code, word, _) = lay_on_head(h, &|s| {
        let (t0, t1) = (s.mint_end, s.now - 120);
        let room = cointx::allow_time(t1 - s.birth, s.now) - s.minted.unwrap_or_else(|| cointx::allow_time(t0 - s.birth, s.now));
        let amount = (book - s.proven - s.declared).min(room);
        if amount <= 0 || t1 < t0 + 60 {
            return None;
        }
        cointx::build3(h, Kind::Mint, amount as u64, birth_ms(), &s.head, &nonce(), &[0; 32], &[0; 32], ZERO, t0 as u64, t1 as u64)
    });
    mark(&format!("mint code={code} word={word} gap={gap}"));
    let after = if code == 200 { chain3(&me, &door).unwrap_or(st) } else { st };
    told(&after);
    Some(after)
}

fn told(st: &Chain3) {
    if st.v3 {
        *SPLIT.lock().unwrap() = Some((st.proven, st.declared, st.height, st.now, local_s()));
        // a SEND laid on a head below this height stands in this state, or never will
        FLYING.lock().unwrap().retain(|(_, h, _)| st.height <= *h);
    }
}

/// The person's own chain as this computer's copy of the chains folded it (iOS MTCoinSplit.heard fromCopy): heard before the node's
/// word, never over a higher state; the same state keeps the moment it was first told.
pub fn heard_copy(st: &cointx::St, second: i64) {
    if !st.v3 {
        return;
    }
    let mut split = SPLIT.lock().unwrap();
    if split.is_some_and(|(_, _, h, ..)| st.height < h) {
        return;
    }
    if split.map(|(p, d, h, ..)| (p, d, h)) != Some((st.proven, st.declared, st.height)) {
        *split = Some((st.proven, st.declared, st.height, second, local_s()));
    }
    drop(split);
    FLYING.lock().unwrap().retain(|(_, h, _)| st.height <= *h);
    mark(&format!("split proven={} declared={} copy=1", st.proven, st.declared));
}

/// THE PERSON HERE MINTS (iOS MTCoinTx.here, fold-7): online -- the window in front of the person (Windows holds no tunnel of its own).
pub fn here() -> bool {
    crate::person::front()
}
/// The seconds the road to the node may take: a MINT reaching it later than this counts less than it names (iOS presentMargin).
const PRESENT_MARGIN: i64 = 20;
/// Under the node's minute plus one beat, a MINT's interval never passes the freshness less the margin (iOS presentBeat).
pub const PRESENT_BEAT: u64 = 40;

/// THE SENDS ON THEIR WAY TO THE CHAIN (iOS MTCoinSplit.flying, fold-7): a SEND laid on the head of height h stands in every state of a
/// height above h, or never will; until the chain tells a state above h its coins are on their way and the available leaves them out.
/// Held in memory: a new run reads the chain after the send's road has ended.
/// (the SEND's name, the height it was laid on, its coins)
static FLYING: Mutex<Vec<(String, i64, i64)>> = Mutex::new(Vec::new());
fn laid(id: &str, coins_: i64, height: i64) {
    let mut f = FLYING.lock().unwrap();
    f.retain(|(k, ..)| k != id);
    f.push((id.to_string(), height, coins_));
}

/// THE AVAILABLE, ONE NUMBER EVERYWHERE (iOS MTCoinSplit.available): what the person's chain holds for its owner, proven and declared,
/// less the sends on their way to it; before the chain spoke this run, the book. The book no longer caps it (fold-7): it mints nothing
/// after the time cut, so as a ceiling it would freeze the number while the chain mints.
pub fn available(vault: &Vault) -> i64 {
    let Some((p, d, height, second, at)) = *SPLIT.lock().unwrap() else { return coins::balance(vault) };
    let away: i64 = FLYING.lock().unwrap().iter().filter(|(_, h, _)| height <= *h).map(|(.., c)| *c).sum();
    // the seconds the chain has credited since it spoke, by its own step (iOS 2305 available's «lived»)
    let lived = cointx::since(second, second + (local_s() - at).max(0.0) as i64);
    (p + d + lived - away).max(0)
}

/// THE BEAT OF THE CHAIN'S MINTING (iOS 2305 MTCoinSplit.beat, the author's words 23.10.2026 23:2x MSK: «in the client the minting
/// shows just as before, only it all happens at the core's level»): every second the available is read again, and what the chain's
/// own step raised it by rises on the screen as a coin -- never a coin the chain did not fold.
static SHOWN: Mutex<Option<i64>> = Mutex::new(None);
pub fn beat(vault: &Vault) {
    if SPLIT.lock().unwrap().is_none() {
        return;
    }
    let now = available(vault);
    let before = SHOWN.lock().unwrap().replace(now);
    if let Some(b) = before.filter(|b| *b < now) {
        coins::flash_chain(vault, now - b);
    }
}
pub fn split() -> Option<(i64, i64, i64)> {
    SPLIT.lock().unwrap().map(|(p, d, h, ..)| (p, d, h))
}

// A CALL MOVES NO COIN (the author's word 29.10.2026 19:31 UTC, council link 11871; iOS 21c95645 «Calls move no coin»): the
// call's chain burn (owe, burn_now, burn_owed) is gone; an owed left in the folder by the builds before is read by nothing.

fn state(vault: &Vault) -> Value {
    vault.get(STATE).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_else(|| json!({ "k": {}, "told": {}, "open": [] }))
}
fn save(vault: &Vault, v: &Value) {
    vault.set(STATE, v.to_string().as_bytes());
}

/// A correspondent's coin key, told in their about word («k»): the key a SEND of version 3 commits to.
pub fn peer_from(vault: &Vault, conv: &str) -> Option<String> {
    state(vault)["k"][conv].as_str().map(str::to_string)
}
pub fn note_peer_from(vault: &Vault, conv: &str, from: &str) {
    if from.len() != 64 || !from.chars().all(|c| c.is_ascii_hexdigit()) {
        return;
    }
    let mut s = state(vault);
    if s["k"][conv].as_str() == Some(from) {
        return;
    }
    s["k"][conv] = json!(from);
    save(vault, &s);
}

pub enum Sent {
    Taken(String),
    Pending,
    NotApplicable(String),
    Failed,
}

/// SENDS (iOS send3): the receiver's key known, my chain announced and holding the sum; the record names the declared part (proven
/// is spent first), commits to the receiver's key under the pair's blind and is laid on my chain's head. The book's debit stands
/// under the record's name; a record no node took gives it back.
/// `on` -- the letter a paid reaction's SEND stands under (iOS send3 on target): its coins stand under that letter.
pub fn send3(vault: &Vault, h: &Hands, conv: &str, secret: &[u8], coins_: i64, on: Option<&str>) -> Sent {
    let Some(peer) = peer_from(vault, conv).and_then(|p| cointx::unhex32(&p)) else { return Sent::NotApplicable("no receiver key".into()) };
    let me = h.from();
    let Some(door) = cointx::chain_door(&me) else { return Sent::Failed };
    let Some(first) = reconcile(vault, h, true) else { return Sent::NotApplicable("no chain".into()) };
    if !first.v3 || first.proven + first.declared < coins_ {
        return Sent::NotApplicable("chain short".into());
    }
    let nonce = nonce();
    let pair = cointx::pair_tag(secret);
    // the blind stands on the key an item laid today stands on (iOS MTNodeWire.itemKey): the conversation's root past the anchor
    let commit = cointx::commitment(&peer, &cointx::blind(&crate::wire::item_key(secret, crate::wire::day()), &nonce));
    for attempt in 1..=2 {
        let Some(st) = chain3(&me, &door) else { return Sent::Failed };
        if !st.v3 || st.proven + st.declared < coins_ {
            return Sent::NotApplicable("chain short".into());
        }
        if !head_is_mine(&st.head, &me, &door) {
            return Sent::Failed;
        }
        let dec = (coins_ - st.proven).max(0);
        let Some(rec) = cointx::build3(h, Kind::Send, coins_ as u64, birth_ms(), &st.head, &nonce, &pair, &commit, ZERO, dec as u64, 0) else { return Sent::Failed };
        let id = cointx::name(&rec);
        // A SEND THE CHAIN HOLDS STANDS IN THE BOOK WHATEVER ITS BALANCE (iOS sendHeld, fold-7): the chain weighed the sum a moment
        // before, and the book, which mints nothing after the time cut, holds less than the chain -- its refusal would keep coins the
        // chain lets go
        if !coins::moved(vault, "retake", coins_, &format!("{}{id}", coins::TX), Some(conv), on) {
            return Sent::Failed;
        }
        let (code, o) = ask(&door, "/tx-put", &json!({ "rec": crate::wire::b64(&rec) }));
        mark(&format!("send code={code} coins={coins_} dec={dec} id={} attempt={attempt}", &id[..12]));
        if code == 200 && o.as_ref().and_then(|o| o["id"].as_str()) == Some(id.as_str()) {
            let mut s = state(vault);
            if let Some(a) = s["open"].as_array_mut() { a.push(json!({ "id": id, "conv": conv, "coins": coins_, "at": st.now })); }
            save(vault, &s);
            laid(&id, coins_, st.height);
            return Sent::Taken(id);
        }
        if code == -1 && ask(&door, "/tx-get", &json!({ "id": id })).0 == 200 {
            laid(&id, coins_, st.height);
            return Sent::Taken(id);
        }
        // not taken: the coins come back under the record's name, and a head that moved is tried once more
        coins::moved(vault, "receive", coins_, &format!("{}{id}", coins::TX_BACK), Some(conv), on);
        if code != 409 {
            return if code == -1 { Sent::Pending } else { Sent::Failed };
        }
    }
    Sent::Failed
}

/// RECEIVES (iOS receive3): a SEND of my pair that commits to my key is taken by a RECV on my chain; the book credits it only when
/// my chain holds it (or the SEND's node names me as the one who took it).
pub fn receive3(vault: &Vault, h: &Hands, s: &cointx::Rec, conv: &str, secret: &[u8]) -> bool {
    if s.kind != Kind::Send as u8 {
        return false;
    }
    let me = h.from();
    let Some(mine) = cointx::unhex32(&me) else { return false };
    // the sender's day is its own clock: the root first, then the established secret (iOS itemKeys)
    let Some(blind) = crate::wire::item_keys(secret).iter().map(|k| cointx::blind(k, &s.nonce))
        .find(|b| cointx::commitment(&mine, b).as_slice() == s.to.as_slice()) else { return false };
    let name = format!("{}{}", coins::TX, s.id);
    if coins::holds(vault, "receive", &name) {
        return false;
    }
    let Some(st) = reconcile(vault, h, false) else { return false };
    if !st.v3 {
        return false;
    }
    let (code, word, _) = lay_on_head(h, &|c| cointx::build3(h, Kind::Recv, s.amount, birth_ms(), &c.head, &nonce(), &[0; 32], &blind, &s.id, s.a, 0));
    let mut taken = code == 200;
    if !taken && (word == "settled" || word == "not yours") {
        if let Some(door) = cointx::chain_door(&s.from) {
            let (_, o) = ask(&door, "/tx-settle", &json!({ "send": s.id }));
            taken = o.is_some_and(|o| o["state"].as_str() == Some("recv") && o["by"].as_str() == Some(me.as_str()));
        }
    }
    mark(&format!("recv code={code} word={word} taken={taken}"));
    taken && coins::moved(vault, "receive", s.amount as i64, &name, Some(conv), heard_on(vault, &s.id).as_deref())
}

/// THE LETTER A PAID REACTION'S SEND STANDS UNDER, AS ITS WORD NAMED IT (iOS MTCoinTx.heard): the word moves no coins; it names the
/// SEND, and the scan asked at once credits that SEND under the letter. A word later than the scan leaves the coins right and under
/// no letter. The newest 256 names are kept.
pub fn heard(vault: &Vault, tx: &str, sid: &str) {
    if tx.len() != 64 || !tx.chars().all(|c| c.is_ascii_hexdigit()) || sid.is_empty() {
        return;
    }
    let mut s = state(vault);
    let mut rows: Vec<Value> = s["heard"].as_array().cloned().unwrap_or_default().into_iter().filter(|r| r[0].as_str() != Some(tx)).collect();
    rows.push(json!([tx, sid]));
    let from = rows.len().saturating_sub(256);
    s["heard"] = Value::Array(rows.split_off(from));
    save(vault, &s);
    if !coins::holds(vault, "receive", &format!("{}{tx}", coins::TX)) {
        SCAN_SOON.store(true, std::sync::atomic::Ordering::SeqCst);
    }
}
fn heard_on(vault: &Vault, tx: &str) -> Option<String> {
    state(vault)["heard"].as_array()?.iter().rev().find(|r| r[0].as_str() == Some(tx)).and_then(|r| r[1].as_str().map(str::to_string))
}
/// A paid reaction's word came: the pairs' scan is asked now, not at its next round (iOS scanFresh «reaction»).
static SCAN_SOON: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
pub fn scan_due() -> bool {
    SCAN_SOON.swap(false, std::sync::atomic::Ordering::SeqCst)
}

/// A TRANSFER TO ONE'S OWN OTHER ACCOUNT IS ONE PAIR, SENT AND RECEIVED IN THE SAME STEP (iOS MTCoinTx.landOwn; the author's words
/// 12.10.2026 13:2x MSK «either the coins left or not -- there is no third»; 15:3x, No.66 «one pair of records, sent and received»):
/// the computer holds both seeds, so the RECV of my SEND is laid at once on the other key's own chain with that key -- the chain
/// opened first by its GENESIS of the book its folder holds, as its own device would open it. A SEND whose RECV did not stand stays
/// the receiver's to take when seated, or comes back by the REFUND after a day -- never both. Whether it was taken, and the word.
pub fn land_own(their: &Hands, their_book: i64, send: &str, secret: &[u8]) -> (bool, String) {
    let me = match MY_FROM.lock().unwrap().clone() { Some(m) => m, None => return (false, "no key of mine".into()) };
    let Some(door) = cointx::chain_door(&me) else { return (false, "no door".into()) };
    let (code, o) = ask(&door, "/tx-get", &json!({ "id": send }));
    let Some(s) = o.filter(|_| code == 200).and_then(|o| o["rec"].as_str().and_then(crate::wire::unb64)).and_then(|b| cointx::read(&b)) else {
        return (false, format!("no record code={code}"));
    };
    if s.id != send || s.version != 3 || s.kind != Kind::Send as u8 {
        return (false, "not a send of v3".into());
    }
    let them = their.from();
    let (Some(theirs), Some(tdoor)) = (cointx::unhex32(&them), cointx::chain_door(&them)) else { return (false, "no door of theirs".into()) };
    let Some(blind) = crate::wire::item_keys(secret).iter().map(|k| cointx::blind(k, &s.nonce))
        .find(|b| cointx::commitment(&theirs, b).as_slice() == s.to.as_slice()) else { return (false, "not their key".into()) };
    if let Some(st) = chain3(&them, &tdoor).filter(|st| !st.v3) {
        let amount = their_book.max(0).min(cointx::genesis_room(st.height, st.birth, st.now));
        let (code, word, _) = lay_on_head(their, &|c| cointx::build3(their, Kind::Genesis, amount as u64, birth_ms(), &c.head, &nonce(), &[0; 32], &[0; 32], ZERO, 0, 0));
        mark(&format!("own genesis code={code} word={word} amount={amount}"));
    }
    let (code, word, _) = lay_on_head(their, &|c| cointx::build3(their, Kind::Recv, s.amount, birth_ms(), &c.head, &nonce(), &[0; 32], &blind, &s.id, s.a, 0));
    (code == 200, format!("recv code={code} word={word}"))
}

/// THE PAIRS' RECORDS (iOS scan): every pipe's tag asked on both chain nodes; a verified record of another key is a credit (a v3 SEND
/// taken by my RECV), a record of my own key my send from another device of the words. A record is believed only from its key's
/// chain node. The pipes: (conversation, secret).
pub fn scan(vault: &Vault, h: &Hands, pipes: &[(String, Vec<u8>)]) -> usize {
    let me = h.from();
    let by_tag: std::collections::HashMap<String, (String, Vec<u8>)> =
        pipes.iter().map(|(c, s)| (crate::wire::hex(&cointx::pair_tag(s)), (c.clone(), s.clone()))).collect();
    if by_tag.is_empty() {
        return 0;
    }
    let tags: Vec<String> = by_tag.keys().cloned().collect();
    let mut credited = 0;
    let mut seen = std::collections::HashSet::new();
    for (node, host) in cointx::CHAIN_NODES {
        let door = format!("https://{host}/pushwake");
        for part in tags.chunks(256) {
            let mut since = 0i64;
            loop {
                let (code, o) = ask(&door, "/tx-pair", &json!({ "tags": part, "since": since }));
                let Some(o) = o.filter(|_| code == 200) else { break };
                let txs = o["txs"].as_array().cloned().unwrap_or_default();
                for x in &txs {
                    let (Some(id), Some(b)) = (x["id"].as_str(), x["rec"].as_str().and_then(crate::wire::unb64)) else { continue };
                    if !seen.insert(id.to_string()) {
                        continue;
                    }
                    let Some(r) = cointx::read(&b).filter(|r| r.id == id) else { continue };
                    let Some((conv, secret)) = by_tag.get(&crate::wire::hex(&r.pair)) else { continue };
                    if r.version != 1 && cointx::chain_node(&r.from) != Some(node) {
                        continue; // a record laid on another node than its key's moves nothing (a v1 record stands on no chain)
                    }
                    let name = format!("{}{}", coins::TX, r.id);
                    if r.from == me {
                        if !coins::holds(vault, "send", &name) {
                            coins::moved(vault, "retake", r.amount as i64, &name, Some(conv), None);
                        }
                    } else if r.version == 3 {
                        if receive3(vault, h, &r, conv, secret) {
                            credited += 1;
                        }
                    } else {
                        // A v1 OR v2 RECORD OF ANOTHER KEY IS CREDITED AS IT CAME (iOS scan): the book takes it under its name; a v2 one is
                        // noted with its sender, so the REFUND that takes it back at the sender's node takes it out of this book too
                        if coins::moved(vault, "receive", r.amount as i64, &name, Some(conv), None) {
                            credited += 1;
                        }
                        if r.version == 2 && coins::holds(vault, "receive", &name) {
                            note_credit2(vault, &r.id, &r.from, r.amount as i64, conv);
                        }
                    }
                }
                let last = o["last"].as_i64().unwrap_or(since);
                if txs.len() < 512 || last <= since {
                    break;
                }
                since = last;
            }
        }
    }
    mark(&format!("scan pipes={} credited={credited}", by_tag.len()));
    credited
}

/// The v2 records this book credited, each with its sender's key, its coins and its pair (iOS noteCredit2): a REFUND by the sender
/// takes them back (credits_gone).
fn note_credit2(vault: &Vault, id: &str, from: &str, coins: i64, conv: &str) {
    let mut s = state(vault);
    if !s["credits2"][id].is_null() {
        return;
    }
    if !s["credits2"].is_object() {
        s["credits2"] = json!({});
    }
    s["credits2"][id] = json!({ "f": from, "n": coins, "p": conv });
    save(vault, &s);
}

/// THE COINS ARE EITHER GONE OR NOT (iOS creditsGone; constitution, article 8): a v2 record credited here whose sender's REFUND took
/// it back at its chain node leaves this book by one move under its name, whatever the balance (retake: the truth of a debt). Asked
/// once an hour. Nothing is laid on any chain: the book follows what the chain already says.
pub fn credits_gone(vault: &Vault) {
    let s = state(vault);
    let notes = s["credits2"].as_object().cloned().unwrap_or_default();
    let now = crate::wire::now_ms() / 1000;
    if notes.is_empty() || now - s["credits2_at"].as_i64().unwrap_or(0) < 3600 {
        return;
    }
    let mut left = serde_json::Map::new();
    for (id, c) in notes {
        let (Some(from), Some(coins), Some(conv)) = (c["f"].as_str(), c["n"].as_i64(), c["p"].as_str()) else { continue };
        let Some(door) = cointx::chain_door(from) else { continue };
        let (code, f) = ask(&door, "/tx-settle", &json!({ "send": id }));
        if code != 200 || f.as_ref().and_then(|f| f["state"].as_str()) != Some("refund") {
            left.insert(id, c);
            continue;
        }
        let gone = format!("{}{id}", coins::TX_GONE);
        if !(coins::holds(vault, "send", &gone) || coins::moved(vault, "retake", coins, &gone, Some(conv), None)) {
            left.insert(id.clone(), c);
        }
        mark(&format!("credit gone coins={coins} id={}", id.get(..12).unwrap_or("")));
    }
    let mut s = state(vault);
    s["credits2"] = Value::Object(left);
    s["credits2_at"] = json!(now);
    save(vault, &s);
}

/// An untaken SEND comes back after a day by a REFUND on my chain (iOS refundDue): its node's clock decides, one fate a SEND.
pub fn refund_due(vault: &Vault, h: &Hands) {
    let me = h.from();
    let Some(door) = cointx::chain_door(&me) else { return };
    let mut s = state(vault);
    let open = s["open"].as_array().cloned().unwrap_or_default();
    if open.is_empty() {
        return;
    }
    let mut left = vec![];
    for o in open {
        let (Some(id), Some(conv), Some(c)) = (o["id"].as_str(), o["conv"].as_str(), o["coins"].as_i64()) else { continue };
        let at = o["at"].as_i64().unwrap_or(0);
        let (_, f) = ask(&door, "/tx-settle", &json!({ "send": id }));
        let fate = f.as_ref().and_then(|f| f["state"].as_str()).unwrap_or("").to_string();
        if fate == "recv" {
            continue;
        }
        let back = format!("{}{id}", coins::TX_BACK);
        if fate == "refund" {
            coins::moved(vault, "receive", c, &back, Some(conv), None);
            continue;
        }
        let due = fate == "open" && chain3(&me, &door).is_some_and(|st| at + 86_460 <= st.now);
        if !due {
            left.push(o);
            continue;
        }
        let (code, word, _) = lay_on_head(h, &|c3| cointx::build3(h, Kind::Refund, c as u64, birth_ms(), &c3.head, &nonce(), &[0; 32], &[0; 32], id, 0, 0));
        mark(&format!("refund code={code} word={word}"));
        if code == 200 { coins::moved(vault, "receive", c, &back, Some(conv), None); } else { left.push(o); }
    }
    s["open"] = json!(left);
    save(vault, &s);
}

fn mark(line: &str) {
    crate::trace_line(&format!("coin_v3 {line}"));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn throwaway() -> (Vault, std::path::PathBuf, Hands) {
        let dir = std::env::temp_dir().join(format!("mt-wallet-{}", crate::board::fresh_id()));
        let h = Hands::from_seed(&crate::crypto::random(32).unwrap()).unwrap();
        (Vault::at(&dir).unwrap(), dir, h)
    }

    /// A throwaway key whose chain node answers now: a key's node is fixed by its first byte (iOS chainNodes), and a node out of
    /// reach this hour is not this test's subject -- the key is drawn again, and the test says which node it stands on.
    fn throwaway_on_a_living_node() -> (Vault, std::path::PathBuf, Hands) {
        let mut silent = vec![];
        for _ in 0..16 {
            let (v, d, h) = throwaway();
            let door = cointx::chain_door(&h.from()).unwrap();
            if silent.contains(&door) {
                continue;
            }
            if ask(&door, "/tx-head", &json!({ "from": h.from() })).0 == 200 {
                eprintln!("a throwaway key on {door}{}", if silent.is_empty() { String::new() } else { format!(" ({} did not answer)", silent.join(", ")) });
                return (v, d, h);
            }
            silent.push(door);
        }
        panic!("no chain node answers: {silent:?}");
    }

    /// THROUGH THE NODES, TWO THROWAWAY KEYS (test identities only, the owner's word 21.10.2026 19:0x): each chain opens with its
    /// GENESIS of 0; the book mints nothing and the chain holds the seconds A's key lived, never more (fold-6: the node credits them
    /// itself, no MINT is laid); A sends 10 committed to B's key under the pair's blind; B's RECV takes them on B's chain -- both nodes'
    /// folds say so.
    #[test]
    #[ignore]
    fn two_keys_open_their_chains_and_a_send_is_taken_by_its_receiver() {
        if std::env::var("MONTANA_LIVE").is_err() {
            return;
        }
        let (va, da, ha) = throwaway_on_a_living_node();
        let (vb, db, hb) = throwaway_on_a_living_node();
        // ONLY THE CHAIN MINTS (fold-6, from 23.10.2026): the book mints nothing, the node credits the key's life itself
        assert_eq!(coins::in_window(&va, 300, coins::TAP, 300, false), 0, "the book mints nothing after the time cut");
        coins::close_windows(&va, true);
        let a0 = reconcile(&va, &ha, true).expect("A's chain answers");
        // a GENESIS of 0: nothing declared, and nothing proven beyond the seconds the key has lived (the nodes' fold counts them)
        assert!(a0.v3 && a0.declared == 0 && a0.proven <= a0.now - a0.birth + 1, "a new key opens with a GENESIS of 0: {a0:?}");
        let b0 = reconcile(&vb, &hb, true).expect("B's chain answers");
        assert!(b0.v3);
        // a MINT covers at least 60 s and ends 120 s before the node's now: three minutes after the birth
        std::thread::sleep(std::time::Duration::from_secs(190));
        let a1 = reconcile(&va, &ha, true).expect("A's chain answers again");
        assert!(0 < a1.proven && a1.proven <= a1.now - a1.birth, "a MINT of at most the seconds lived: {a1:?}");
        assert!(a1.proven < 300, "the book's 300 are above what time allows the chain");
        let secret = crate::crypto::random(32).unwrap();
        note_peer_from(&va, "B", &hb.from());
        let id = match send3(&va, &ha, "B", &secret, 10, None) {
            Sent::Taken(id) => id,
            _ => panic!("the SEND was not taken"),
        };
        let door = cointx::chain_door(&ha.from()).unwrap();
        let (code, o) = ask(&door, "/tx-get", &json!({ "id": id }));
        assert_eq!(code, 200);
        let rec = cointx::read(&crate::wire::unb64(o.unwrap()["rec"].as_str().unwrap()).unwrap()).unwrap();
        let b_before = chain3(&hb.from(), &cointx::chain_door(&hb.from()).unwrap()).unwrap();
        assert!(receive3(&vb, &hb, &rec, "A", &secret), "B's RECV is taken");
        let b1 = chain3(&hb.from(), &cointx::chain_door(&hb.from()).unwrap()).unwrap();
        let a2 = chain3(&ha.from(), &door).unwrap();
        // the records this machine laid: one SEND on A's chain, one RECV on B's. The nodes' fold of «proven» counts each key's lived
        // seconds by itself since 23.10.2026 (B, whose book never held a coin to mint, reads 192 + 10), so the sums are read as
        // they move: B's by the 10 taken, A's by the 10 sent -- each against the same key's time
        assert_eq!((b1.height, a2.height), (b_before.height + 1, a1.height + 1), "one SEND, one RECV: {a1:?} {a2:?} {b_before:?} {b1:?}");
        assert!(b1.proven >= b_before.proven + 10 && b1.proven <= b_before.proven + 10 + (b1.now - b_before.now) + 2, "B took the 10: {b_before:?} {b1:?}");
        assert!(a2.proven <= a1.proven - 10 + (a2.now - a1.now) + 2, "A's 10 left: {a1:?} {a2:?}");
        assert_eq!(coins::balance(&vb), 10);
        let _ = (std::fs::remove_dir_all(da), std::fs::remove_dir_all(db));
    }

    /// A v2 CREDIT ITS SENDER TOOK BACK LEAVES THE BOOK (iOS creditsGone), read only against the network: a record of the network
    /// whose sender's REFUND stands at its node (1 369 000 coins, refunded 2026-10-20), credited in a throwaway book and noted; the
    /// walk takes it out by one move under «txgone:», the balance back where it was, and a second walk within the hour asks nothing.
    #[test]
    #[ignore]
    fn a_v2_credit_its_sender_took_back_leaves_the_book() {
        if std::env::var("MONTANA_LIVE").is_err() {
            return;
        }
        let id = "dedcaae88f7beb908f3c16705cf9f04d1f6d57620359b77289ece0176a721577";
        let rec = cointx::CHAIN_NODES.iter().find_map(|(_, host)| {
            let (code, o) = crate::doors::post_machine(&format!("https://{host}/pushwake"), "/tx-get", &json!({ "id": id }), 30_000);
            o.filter(|_| code == 200).and_then(|o| o["rec"].as_str().and_then(crate::wire::unb64)).and_then(|b| cointx::read(&b))
        }).expect("a node holds the record");
        assert_eq!((rec.version, rec.kind, rec.amount), (2, Kind::Send as u8, 1_369_000));
        let (v, dir, _) = throwaway();
        let name = format!("{}{id}", coins::TX);
        assert!(coins::moved(&v, "receive", rec.amount as i64, &name, Some("pair"), None));
        note_credit2(&v, id, &rec.from, rec.amount as i64, "pair");
        assert_eq!(coins::balance(&v), 1_369_000);
        credits_gone(&v);
        assert!(coins::holds(&v, "send", &format!("{}{id}", coins::TX_GONE)), "the REFUND took it back");
        assert_eq!(coins::balance(&v), 0);
        assert!(state(&v)["credits2"].as_object().is_some_and(|m| m.is_empty()), "the note is let go");
        credits_gone(&v);
        assert_eq!(coins::balance(&v), 0, "taken out once");
        let _ = std::fs::remove_dir_all(dir);
    }
}
