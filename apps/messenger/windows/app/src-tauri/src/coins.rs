//! THE BOOK OF COINS (iOS MTLocalCoinLedger, MTCoinEntry, MTCoinBook, MTChatMint, MTTimeChain; MTWalletCore.swift): one move of
//! coins per line -- earned, received, spent, sent, burned -- each taken once by its name; the balance is the sum of the lines.
//! 1 SECOND -- 1 COIN (the constitution, article 11; MTCoinBook.price): every minting of one second shares that second's one coin,
//! whatever door mints it -- a letter, a second of a call, the wallet's pull. A game's coins gather in a window of τ1 (60 s) and
//! join the book as one move. Every move joins its source's own TimeChain on this machine (TimeChain/wallet-<source>.jsonl), sealed
//! link by link. The chain on the nodes (cointx.rs) holds what the book holds by the time its key lived.

use crate::vault::Vault;
use crate::wire::{hex, hmac, sha};
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

const KEY: &str = "coinLedger";
/// One coin, the most a second mints, every door together (point 11).
pub const PRICE: i64 = 1;
/// A minting window of τ1: a game's coins of a minute ride one move.
const WINDOW_S: f64 = 60.0;
pub const TICKER: &str = "$TCM";
/// The prefixes of the book's own names (iOS refPrefix of each door).
pub const TAP: &str = "tap:";
pub const PULL: &str = "tap:pull-";
pub const AWAY: &str = "tap:away-";
pub const CALL_MINT: &str = "callmint:";
pub const CALL_BURN: &str = "call:";
pub const TX: &str = "tx:";
pub const TX_BACK: &str = "txback:";
/// The book's name of a v2 credit its sender took back by a REFUND (iOS gonePrefix): the move that takes it out again.
pub const TX_GONE: &str = "txgone:";
/// The coin letter's machine line (iOS MTCoinLetter.link) and a transfer's confirmation link (MTCoinTx.link).
pub const LETTER_LINK: &str = "montana://coin/1/";
pub const TX_LINK: &str = "https://montana.xxx/explorer/#tx=";

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Entry {
    /// earn | receive | spend | send | burn
    pub k: String,
    pub c: i64,
    #[serde(rename = "ref")]
    pub refr: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub peer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub on: Option<String>,
    pub at: f64,
}
impl Entry {
    pub fn id(&self) -> String {
        format!("{}:{}", self.k, self.refr)
    }
    pub fn signed(&self) -> i64 {
        if self.k == "earn" || self.k == "receive" { self.c } else { -self.c }
    }
    /// A name a restore gives a letter names no move (iOS MTRestoredMid: «arc:», «given:»).
    fn restored(&self) -> bool {
        self.refr.starts_with("arc:") || self.refr.starts_with("given:")
    }
}

/// The book's counts by source (iOS MTCoinCounts), the same for a move taken now and for the whole file folded at its reading.
#[derive(Serialize, Clone, Debug, Default, PartialEq)]
pub struct Counts {
    pub earned: i64,
    pub tapped: i64,
    pub played: i64,
    pub walled: i64,
    pub burned: i64,
    pub received: i64,
    pub spent: i64,
    pub sent: i64,
}
impl Counts {
    fn plus(a: i64, b: i64) -> i64 {
        a.checked_add(b).unwrap_or(if 0 < b { i64::MAX } else { i64::MIN })
    }
    fn add(&mut self, e: &Entry) {
        match e.k.as_str() {
            "earn" => self.earn(e.c, &e.refr),
            // a won game's sum taken and a lost game's given are chess (iOS MTChessCoins), so received and reactions count people
            "receive" if e.refr.starts_with("chess-won:") => self.played = Self::plus(self.played, e.c),
            "receive" => self.received = Self::plus(self.received, e.c),
            "spend" if e.refr.starts_with("chess-lost:") => self.played = Self::plus(self.played, -e.c),
            "spend" => self.spent = Self::plus(self.spent, e.c),
            "send" => self.sent = Self::plus(self.sent, e.c),
            _ => self.burned = Self::plus(self.burned, e.c),
        }
    }
    fn earn(&mut self, c: i64, refr: &str) {
        if refr.starts_with(TAP) {
            self.tapped = Self::plus(self.tapped, c);
        } else if refr.starts_with("chess:") || refr.starts_with("timer:") {   // a move's coin and the Timer (iOS movePrefix, MTChessTimer)
            self.played = Self::plus(self.played, c);
        } else if refr.starts_with("vpnwall:") {
            self.walled = Self::plus(self.walled, c);
        } else {
            self.earned = Self::plus(self.earned, c);
        }
    }
}

/// The source a move's TimeChain is named by (iOS MTTimeChain.source).
pub fn source(e: &Entry, group: bool) -> &'static str {
    let r = e.refr.as_str();
    if is_chess(r) { return "chess" }
    if r.starts_with(TAP) { return "pantheon" }
    if r.starts_with("vpnwall:") { return "vpnwall" }
    if r.starts_with("vpnpay:") { return "vpnpay" }
    if r.starts_with(CALL_MINT) { return "calls" }
    if r.starts_with("timer:") { return "timer" }
    if r.starts_with("cmt:") || r.starts_with("cmt-burn:") || r.starts_with("cmt-pay:") { return "comments" }
    match e.k.as_str() {
        "earn" => if group { "groups" } else { "chats" },
        "receive" => "received",
        "spend" => "spent",
        "send" => "sent",
        _ => if r.starts_with(CALL_BURN) { "calls" } else { "letters" },
    }
}

/// A TimeChain link's seal (iOS MTTimeChain.seal): SHA-256 over the link's fields, one per line, the previous seal last.
pub fn chain_seal(n: i64, at_ms: i64, k: &str, c: i64, refr: &str, prev: &str) -> String {
    hex(&sha(&[format!("{n}\n{at_ms}\n{k}\n{c}\n{refr}\n{prev}").as_bytes()]))
}

/// One link of a TimeChain (iOS MTTimeChain.Link), as its file holds it.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Link {
    pub n: i64,
    pub at: i64,
    pub k: String,
    pub c: i64,
    #[serde(rename = "ref")]
    pub refr: String,
    pub prev: String,
    pub hash: String,
}

/// One window of a game's coins, open (iOS MTLocalCoinLedger.windows).
#[derive(Clone, Debug)]
struct Window {
    refr: String,
    coins: i64,
    at: f64,
}

#[derive(Default)]
struct Book {
    entries: Vec<Entry>,
    taken: HashSet<String>,
    balance: i64,
    counts: Counts,
    on_target: HashMap<String, i64>,
    windows: HashMap<String, Window>,
    second: (i64, i64),
    dirty: bool,
    /// the TimeChains' heads, read once: chain -> (n, hash, the names it holds)
    chains: HashMap<String, (i64, String, HashSet<String>)>,
    /// the letters this machine minted for (iOS MTChatMint.earned) and the moment the chat coin came on
    since: f64,
    /// the coins born of late: (moment, the chain's source, coins) -- the minting's sign (iOS MTCoinFlash)
    flash: Vec<(f64, &'static str, i64)>,
    /// this device's new moves waiting for its lane of the TimeChain's tip (iOS keep -> MTTimeChainTip.add), at the next write
    lane: Vec<Entry>,
}

/// THE APPS THAT MINT (iOS MTCoinFlash, the author's word 04.10.2026 18:08 MSK): a coin born is noted by its chain's source; an app
/// whose coins were born within the last second and a half mints now.
fn flashed(b: &mut Book, refr: &str, c: i64, group: bool) {
    let t = now();
    let e = Entry { k: "earn".into(), c, refr: refr.to_string(), peer: None, on: None, at: t };
    b.flash.retain(|(at, _, _)| t - at < 3.0);
    b.flash.push((t, source(&e, group), c));
}
/// THE CHAIN'S SECOND ON THE SCREEN (iOS 2305 MTCoinSplit.beat): the seconds the chain credits by its own step rise as the book's
/// coins once rose -- shown, never booked.
pub fn flash_chain(vault: &Vault, coins: i64) {
    if coins > 0 {
        with(vault, |b| flashed(b, PULL, coins, false));
    }
}

/// What mints now: the sources whose coins were born in the last second and a half, and the coins born in the last second.
pub fn flash(vault: &Vault) -> (Vec<&'static str>, i64) {
    with(vault, |b| {
        let t = now();
        let mut apps: Vec<&'static str> = vec![];
        for (at, s, _) in &b.flash {
            if t - at < 1.5 && !apps.contains(s) {
                apps.push(s);
            }
        }
        (apps, b.flash.iter().filter(|(at, _, _)| t - at < 1.0).map(|(_, _, c)| c).sum())
    })
}

static BOOKS: Mutex<Option<HashMap<String, Book>>> = Mutex::new(None);

fn now() -> f64 {
    (crate::wire::now_ms() as f64).round() / 1000.0
}

fn with<R>(vault: &Vault, f: impl FnOnce(&mut Book) -> R) -> R {
    let mut g = BOOKS.lock().unwrap();
    let dir = vault.dir().to_string_lossy().to_string();
    let b = g.get_or_insert_with(HashMap::new).entry(dir).or_insert_with(|| read(vault));
    f(b)
}

/// The book read once: a line that does not read is no move, a name counts once, a sum that would not fit is refused.
fn read(vault: &Vault) -> Book {
    let mut b = Book::default();
    let text = vault.get(KEY).map(|v| String::from_utf8_lossy(&v).to_string()).unwrap_or_default();
    for line in text.lines() {
        let Ok(e) = serde_json::from_str::<Entry>(line) else { continue };
        if e.c <= 0 || e.restored() || b.taken.contains(&e.id()) {
            continue;
        }
        let Some(next) = b.balance.checked_add(e.signed()) else { continue };
        b.balance = next;
        b.counts.add(&e);
        if let Some(on) = &e.on {
            *b.on_target.entry(on.clone()).or_default() += e.c;
        }
        b.taken.insert(e.id());
        b.entries.push(e);
    }
    b.since = vault.get("coinSince").and_then(|v| String::from_utf8(v).ok()).and_then(|s| s.parse().ok()).unwrap_or(0.0);
    b
}

fn write(vault: &Vault, b: &mut Book) {
    let mut text = String::with_capacity(b.entries.len() * 80);
    for e in &b.entries {
        if let Ok(l) = serde_json::to_string(e) {
            text.push_str(&l);
            text.push('\n');
        }
    }
    vault.set(KEY, text.as_bytes());
    b.dirty = false;
}

#[cfg(test)]
thread_local! {
    static TEST_SECOND: std::cell::Cell<Option<i64>> = const { std::cell::Cell::new(None) };
}
/// A test stands the book's second where its rule is read (before the time cut, after it); None -- the wall clock again.
#[cfg(test)]
pub(crate) fn test_second(at: Option<i64>) {
    TEST_SECOND.with(|s| s.set(at));
}
/// The book's second: the wall clock's.
fn second_now() -> i64 {
    #[cfg(test)]
    if let Some(t) = TEST_SECOND.with(|s| s.get()) {
        return t;
    }
    crate::wire::now_ms() / 1000
}

/// THE ONE COIN OF A SECOND (iOS MTLocalCoinLedger.priced): all the minting of one second shares that second's one coin; a payment
/// for seconds lived away carries one for each of its seconds before this one.
fn priced(b: &mut Book, coins: i64, seconds: i64) -> i64 {
    let t = second_now();
    // ONLY THE CHAIN MINTS (iOS priced, fold-6 and fold-7): from the time cut the chain credits the seconds itself, so no door of the
    // book mints -- letters, taps, the pull, the VPN wall, calls, a named mint, chess, the seconds away. The person's number is the
    // chain's (wallet::available).
    if crate::cointx::TIME_CUT <= t {
        return 0;
    }
    if b.second.0 != t {
        b.second = (t, 0);
    }
    let away = PRICE * (seconds - 1).max(0);
    let room = (PRICE - b.second.1).max(0);
    let c = coins.min(room + away);
    b.second.1 += room.min((c - away).max(0));
    c
}

/// One move of this device into the book (iOS take + keep): it leaves for the seed's other devices too.
fn take(b: &mut Book, e: Entry) -> bool {
    let kept = e.clone();
    enter(b, e) && {
        keep(b, kept);
        true
    }
}
/// A NEW MOVE OF THIS DEVICE LEAVES FOR THE SEED'S OTHER DEVICES (iOS keep): the moves of a minute ride one piece of the vault, and
/// this device's lane takes it at the next write (MTTimeChainTip.add). A move joined from another device does neither (iOS join).
fn keep(b: &mut Book, e: Entry) {
    crate::coinvault::soon("moves", 60.0);
    b.lane.push(e);
}
/// One move into the book: never under a restored name, never past the integer.
fn enter(b: &mut Book, e: Entry) -> bool {
    if e.restored() {
        return false;
    }
    let Some(next) = b.balance.checked_add(e.signed()) else { return false };
    b.balance = next;
    b.counts.add(&e);
    if let Some(on) = &e.on {
        *b.on_target.entry(on.clone()).or_default() += e.c;
    }
    b.taken.insert(e.id());
    b.entries.push(e);
    b.dirty = true;
    true
}

/// The coins a letter's name minted (iOS MTChatMint.credit + earn): each letter of a pair's chat born since the coin came on earns
/// the second's one coin, once by its wire name; the coins this call added.
pub fn earn(vault: &Vault, names: &[(String, i64)], peer: Option<&str>) -> i64 {
    let mut got = 0;
    with(vault, |b| {
        if b.since == 0.0 {
            b.since = now();
            vault.set("coinSince", b.since.to_string().as_bytes());
        }
        for (name, born_ms) in names {
            if b.taken.contains(&format!("earn:{name}")) || (*born_ms as f64) / 1000.0 < b.since {
                continue;
            }
            let c = priced(b, PRICE, 1);
            if c <= 0 {
                continue;
            }
            let e = Entry { k: "earn".into(), c, refr: name.clone(), peer: peer.map(str::to_string), on: None, at: *born_ms as f64 / 1000.0 };
            if take(b, e) {
                got += c;
                flashed(b, name, c, peer.is_some());
            }
        }
    });
    got
}

/// A GAME'S COINS IN ITS WINDOW (iOS mintInWindow / burnInWindow): gathered for τ1 under one name and booked as one move when it
/// closes; the balance shows every coin at once. A burn takes at most what the balance holds.
pub fn in_window(vault: &Vault, coins: i64, prefix: &str, seconds: i64, burning: bool) -> i64 {
    with(vault, |b| {
        if coins <= 0 || (!burning && b.balance.checked_add(coins).is_none()) {
            return 0;
        }
        let c = if burning { coins.min(b.balance.max(0)) } else { priced(b, coins, seconds) };
        if c <= 0 {
            return 0;
        }
        let signed = if burning { -c } else { c };
        let t = now();
        let w = b.windows.entry(prefix.to_string()).or_insert_with(|| Window {
            refr: format!("{prefix}w{}-{}", (t * 1000.0) as i64, crate::board::fresh_id()), coins: 0, at: t,
        });
        let Some(next) = w.coins.checked_add(signed) else { return 0 };
        w.coins = next;
        b.balance += signed;
        if burning { b.counts.burned = Counts::plus(b.counts.burned, c) } else { b.counts.earn(c, prefix) }
        if !burning {
            flashed(b, prefix, c, false);
        }
        c
    })
}

/// The windows whose minute passed close into the book (and every one at the app's leaving): one move each.
pub fn close_windows(vault: &Vault, all: bool) -> usize {
    with(vault, |b| {
        let t = now();
        let due: Vec<String> = b.windows.iter().filter(|(_, w)| all || t - w.at >= WINDOW_S).map(|(k, _)| k.clone()).collect();
        for k in &due {
            let w = b.windows.remove(k).unwrap();
            if w.coins == 0 {
                continue;
            }
            // the window's coins already stand in the balance: the move is booked without moving them again
            let e = Entry { k: if w.coins < 0 { "burn".into() } else { "earn".into() }, c: w.coins.abs(), refr: w.refr, peer: None, on: None, at: w.at };
            b.taken.insert(e.id());
            b.entries.push(e.clone());
            b.dirty = true;
            keep(b, e);
        }
        due.len()
    })
}

/// Coins a hand moves (iOS move / receive / burn / retake): refused on a short balance or a name taken; a receive is once by its
/// name; a retake stands whatever the balance (the truth of a debt).
pub fn moved(vault: &Vault, k: &str, coins: i64, refr: &str, peer: Option<&str>, on: Option<&str>) -> bool {
    let took = with(vault, |b| {
        let e = Entry { k: k.into(), c: coins, refr: refr.into(), peer: peer.map(str::to_string), on: on.map(str::to_string), at: moment(refr) };
        if coins <= 0 || refr.is_empty() || b.taken.contains(&e.id()) {
            return false;
        }
        match k {
            "spend" | "send" if coins > b.balance => false,
            "burn" => {
                let c = coins.min(b.balance);
                c > 0 && take(b, Entry { c, ..e })
            }
            "retake" => take(b, Entry { k: "send".into(), ..e }),
            _ => take(b, e),
        }
    });
    if took {
        crate::coinvault::soon("move", 1.0);   // a move between people reaches the seed's devices at once (iOS keep)
    }
    took
}

/// A coin letter stands at its own birth in every book (iOS moment): its name carries the sender's millisecond.
fn moment(refr: &str) -> f64 {
    crate::book::birth_ms(refr).map(|ms| ms as f64 / 1000.0).unwrap_or_else(now)
}

/// The book as the wallet shows it: the balance, the counts, the newest moves first.
pub fn state(vault: &Vault, newest: usize) -> (i64, Counts, Vec<Entry>) {
    with(vault, |b| (b.balance, b.counts.clone(), b.entries.iter().rev().take(newest).cloned().collect()))
}
pub fn balance(vault: &Vault) -> i64 {
    with(vault, |b| b.balance)
}
/// The balance another person's book holds on this computer (iOS MTSeats.shelfCoins), read from its vault and never kept here:
/// their own process owns their book.
pub fn balance_in(vault: &Vault) -> i64 {
    read(vault).balance
}
/// Every move of the book, in its order (iOS entries): what the seed's vault lays on the nodes.
pub fn all_moves(vault: &Vault) -> Vec<Entry> {
    with(vault, |b| b.entries.clone())
}
/// THE SEED'S MOVES JOINED (iOS MTLocalCoinLedger.join): every move of another device of the words this book does not hold by its
/// name, never one under a restored name, never past the integer; the moves joined.
pub fn join(vault: &Vault, moves: &[Entry]) -> usize {
    with(vault, |b| {
        let mut n = 0;
        for e in moves {
            if e.c <= 0 || e.restored() || b.taken.contains(&e.id()) || !["earn", "receive", "spend", "send", "burn"].contains(&e.k.as_str()) {
                continue;
            }
            if enter(b, e.clone()) {
                n += 1;
            }
        }
        if n > 0 {
            write(vault, b);
            b.dirty = true; // the chains take the moves at the next flush
            crate::trace_line(&format!("coin_book joined moves={n} balance={}", b.balance));
        }
        n
    })
}
pub fn holds(vault: &Vault, k: &str, refr: &str) -> bool {
    with(vault, |b| b.taken.contains(&format!("{k}:{refr}")))
}

/// THE BOOK ON DISK AND ITS CHAINS (iOS keep / writeNow): what moved is written, and every new move joins its source's TimeChain
/// once by its name. `group` says whether a peer is a group's chat.
pub fn flush(vault: &Vault, dir: &std::path::Path, group: &dyn Fn(&str) -> bool) {
    with(vault, |b| {
        if !b.lane.is_empty() {
            let fresh = std::mem::take(&mut b.lane);
            crate::tip::add(vault, &fresh, b.balance, crate::coinvault::heard());
        }
        if !b.dirty {
            return;
        }
        write(vault, b);
        let chains = dir.join("TimeChain");
        let _ = std::fs::create_dir_all(&chains);
        let fresh: Vec<Entry> = b.entries.clone();
        for e in fresh {
            let src = source(&e, e.peer.as_deref().is_some_and(group));
            let head = b.chains.entry(src.to_string()).or_insert_with(|| read_chain(&chains, src));
            if head.2.contains(&e.refr) {
                continue;
            }
            let n = head.0 + 1;
            let at = (e.at * 1000.0).round() as i64;
            let hash = chain_seal(n, at, &e.k, e.c, &e.refr, &head.1);
            let link = Link { n, at, k: e.k.clone(), c: e.c, refr: e.refr.clone(), prev: head.1.clone(), hash: hash.clone() };
            if let Ok(line) = serde_json::to_string(&link) {
                use std::io::Write;
                if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(chains.join(format!("wallet-{src}.jsonl"))) {
                    let _ = writeln!(f, "{line}");
                }
            }
            head.0 = n;
            head.1 = hash;
            head.2.insert(e.refr.clone());
        }
    });
}

/// A LINK OF A CHAIN THAT MOVES NO COIN OF THE BOOK (iOS MTTimeChain.note): the wall's chain notes the fifth of the comments' coins its
/// owner keeps, and the fifth paid; once by its name.
pub fn note(vault: &Vault, src: &str, k: &str, c: i64, refr: &str) {
    let Some(dir) = vault.dir().parent().map(|d| d.join("TimeChain")) else { return };
    with(vault, |b| {
        let _ = std::fs::create_dir_all(&dir);
        let head = b.chains.entry(src.to_string()).or_insert_with(|| read_chain(&dir, src));
        let name = refr.to_string();
        if head.2.contains(&name) {
            return;
        }
        let n = head.0 + 1;
        let at = crate::wire::now_ms();
        let hash = chain_seal(n, at, k, c, &name, &head.1);
        let link = Link { n, at, k: k.to_string(), c, refr: name.clone(), prev: head.1.clone(), hash: hash.clone() };
        if let Ok(line) = serde_json::to_string(&link) {
            use std::io::Write;
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(dir.join(format!("wallet-{src}.jsonl"))) {
                let _ = writeln!(f, "{line}");
            }
        }
        head.0 = n;
        head.1 = hash;
        head.2.insert(name);
    });
}

/// THE TIMECHAINS ON THE WALLET (iOS MTTimeChain.sources, MTTimeChainRows): the sources in the wallet's order.
pub const SOURCES: [&str; 17] = ["pi", "chess", "pantheon", "vpnwall", "vpnpay", "timer", "chats", "groups", "channels", "comments", "wall",
                                 "received", "spent", "sent", "calls", "letters", "system"];

/// A chain's head as the wallet shows it (iOS MTTimeChain.Head): its length, its last seal, whether every seal holds from the genesis.
#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct Head {
    pub source: String,
    pub n: i64,
    pub hash: String,
    pub whole: bool,
}
/// One link as the chain's page shows it (iOS MTTimeChainPage).
#[derive(Serialize, Debug, Clone)]
pub struct LinkSeen {
    pub n: i64,
    pub at: i64,
    pub k: String,
    pub c: i64,
    #[serde(rename = "ref")]
    pub refr: String,
    pub prev: String,
    pub hash: String,
}

fn chain_file(dir: &std::path::Path, src: &str) -> Vec<Link> {
    let text = std::fs::read_to_string(dir.join("TimeChain").join(format!("wallet-{src}.jsonl"))).unwrap_or_default();
    text.lines().filter_map(|l| serde_json::from_str::<Link>(l).ok()).collect()
}

/// A chain read whole from its file and every seal checked from the genesis (iOS MTTimeChain.head): a link out of its place, one
/// standing on another seal, or one whose seal its fields do not give, ends the whole.
pub fn head(dir: &std::path::Path, src: &str) -> Head {
    let (mut prev, mut whole, mut n) = ("0".repeat(64), true, 0i64);
    for l in chain_file(dir, src) {
        n += 1;
        if l.n != n || l.prev != prev || l.hash != chain_seal(l.n, l.at, &l.k, l.c, &l.refr, &l.prev) {
            whole = false;
            break;
        }
        prev = l.hash;
    }
    Head { source: src.into(), n, hash: prev, whole }
}

/// The heads of every chain that holds a link, in the wallet's order.
pub fn heads(dir: &std::path::Path) -> Vec<Head> {
    SOURCES.iter().map(|s| head(dir, s)).filter(|h| h.n > 0).collect()
}

/// A chain's links, newest first (iOS MTTimeChainPage), at most `most`.
pub fn links(dir: &std::path::Path, src: &str, most: usize) -> Vec<LinkSeen> {
    chain_file(dir, src).into_iter().rev().take(most)
        .map(|l| LinkSeen { n: l.n, at: l.at, k: l.k, c: l.c, refr: l.refr, prev: l.prev, hash: l.hash }).collect()
}

fn read_chain(dir: &std::path::Path, src: &str) -> (i64, String, HashSet<String>) {
    let text = std::fs::read_to_string(dir.join(format!("wallet-{src}.jsonl"))).unwrap_or_default();
    let mut out = (0, "0".repeat(64), HashSet::new());
    for l in text.lines().filter_map(|l| serde_json::from_str::<Link>(l).ok()) {
        out.0 = l.n;
        out.1 = l.hash;
        out.2.insert(l.refr);
    }
    out
}

/// A COIN LETTER (iOS MTCoinLetter): «🪙 <coins>» and the machine line «montana://coin/1/» + base64url of {"c", "id"}, id being the
/// UUID of its own wire name -- a copy under another name credits nothing.
pub fn letter_of(text: &str) -> Option<(i64, String)> {
    if !text.starts_with("🪙 ") || text.len() > 512 {
        return None;
    }
    let line = text.split('\n').next_back()?.strip_prefix(LETTER_LINK)?;
    let code: String = line.chars().map(|c| match c { '-' => '+', '_' => '/', x => x }).collect();
    let o: serde_json::Value = serde_json::from_slice(&crate::wire::unb64(&code)?).ok()?;
    let (c, id) = (o["c"].as_i64()?, o["id"].as_str()?.to_string());
    (c > 0 && id.len() == 36).then_some((c, id))
}
/// Whether a coin letter names itself: its id is the UUID of its own wire name.
pub fn bound(id: &str, mid: &str) -> bool {
    let core = mid.strip_prefix("mid:").unwrap_or(mid);
    core.split_once('-').is_some_and(|(_, uuid)| uuid.eq_ignore_ascii_case(id))
}
/// A transfer's telling letter (iOS MTCoinSend.transferResult): the coins and the confirmation link; it mints nothing.
pub fn is_transfer(text: &str) -> bool {
    text.starts_with("🪙 ") && text.contains(TX_LINK)
}

/// THE KEYS ONLY THE WORDS DERIVE (iOS MTCoinVault.keys, MTTopNet.key, MTOwnWords): HKDF-SHA-256 of the entropy under each label,
/// then an HMAC for each row's token.
fn hkdf(entropy: &[u8], label: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let _ = Hkdf::<Sha256>::new(Some(&[]), entropy).expand(label, &mut out);
    out
}
pub struct VaultKeys {
    pub seal: [u8; 32],
    pub token: [u8; 32],
    pub tip: [u8; 32],
    owner: [u8; 32],
}
pub fn vault_keys(entropy: &[u8]) -> VaultKeys {
    let owner = hkdf(entropy, b"mt-coins-vault-owner-v1");
    VaultKeys { seal: hkdf(entropy, b"mt-coins-vault-key-v1"), token: hmac(&owner, b"mt-coins-vault-token"), tip: hmac(&owner, b"mt-timechain-tip-token"), owner }
}
impl VaultKeys {
    /// A node's own row of the book (iOS nodeToken) and the person's chain's row (personRow).
    pub fn node_token(&self, host: &str) -> [u8; 32] {
        hmac(&self.owner, &[b"mt-coins-vault-node-v1".as_slice(), host.as_bytes()].concat())
    }
    pub fn person_token(&self) -> [u8; 32] {
        hmac(&self.owner, b"mt-person-chain-token")
    }
}
/// The public table's row (iOS MTTopNet): HKDF(entropy, "mt-top-owner-v1"), its HMAC token, the row its SHA-256.
pub fn top_token(entropy: &[u8]) -> ([u8; 32], [u8; 32]) {
    let k = hkdf(entropy, b"mt-top-owner-v1");
    (k, hmac(&k, b"mt-top-token"))
}

/// AUTO-REACTIONS OF CHOSEN PEOPLE (iOS MTAutoReact, the author's word 06.10.2026): a person chosen with a number of coins is paid
/// that many on every letter of theirs born after the choice, within a day of its birth. The coins and the moment of the first choice.
const AUTO: &str = "autoReact";
pub fn auto_react(vault: &Vault, conv: &str) -> Option<(i64, f64)> {
    let all: serde_json::Value = vault.get(AUTO).and_then(|b| serde_json::from_slice(&b).ok())?;
    let r = &all[conv];
    Some((r["c"].as_i64().filter(|c| *c > 0)?, r["s"].as_f64()?))
}
pub fn auto_reacts(vault: &Vault) -> serde_json::Value {
    vault.get(AUTO).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_else(|| serde_json::json!({}))
}
/// The coins a person's every new letter is paid; nought lets the person go. The moment of the first choice stays while the number
/// changes, so a letter between two edits is paid by the rule that stood.
pub fn set_auto_react(vault: &Vault, conv: &str, coins: i64) {
    let mut all = auto_reacts(vault);
    if coins <= 0 {
        if let Some(o) = all.as_object_mut() {
            o.remove(conv);
        }
    } else {
        let since = auto_react(vault, conv).map(|(_, s)| s).unwrap_or_else(now);
        all[conv] = serde_json::json!({ "c": coins, "s": since });
    }
    vault.set(AUTO, all.to_string().as_bytes());
}

/// Every name a coin of chess moved under in the builds before (iOS MTCoinLegacy): the wallet still names that history's source;
/// nothing books under them now (the author's word 29.10.2026 19:31 UTC: no coins in chess).
pub fn is_chess(r: &str) -> bool {
    ["chess:", "chess-won:", "chess-lost:", "chess-pot:", "chess-stake:", "chess-back:"].iter().any(|p| r.starts_with(p))
}
/// The coins standing on a target (iOS coins(on:)): a wall post's coins.
pub fn on_target(vault: &Vault, on: &str) -> i64 {
    with(vault, |b| b.on_target.get(on).copied().unwrap_or(0))
}

/// THE LEVELS OF π (iOS MTPiLevels.place): how many prefixes of π's nineteen digits the balance reaches.
pub fn pi_place(balance: i64) -> usize {
    const DIGITS: &str = "3141592653589793238";
    (1..=DIGITS.len()).filter(|n| DIGITS[..*n].parse::<i64>().is_ok_and(|v| v <= balance)).count()
}
/// The person's level by their seconds on the network (iOS MTPersonChain.level): bit_length(s) - 1, none below a second.
pub fn person_level(s: i64) -> Option<i64> {
    (s >= 1).then(|| 63 - s.leading_zeros() as i64)
}

/// THE PANTHEON ON FIRE (iOS MTPantheon; the author's words 03.10-04.10.2026): the first tap lights the game and every tap mints
/// the second's one coin at most (`priced`), thirteen taps a second counted at most; the fire burns while a finger holds the coin and
/// goes out at three seconds of quiet after the last; a burn unbroken for sixty seconds goes out, and the coin rests sixty -- no tap
/// mints -- before the next burn counts anew.
#[derive(Default)]
pub struct Pantheon {
    lit_at: Option<f64>,
    rest_until: Option<f64>,
    taps: Vec<f64>,
    last: f64,
    holding: bool,
}
pub const CEILING: usize = 13;
pub const STREAK: f64 = 60.0;
pub const QUIET: f64 = 3.0;

impl Pantheon {
    /// The fire at a moment: a burn past its minute rests from that minute on, a quiet past three seconds puts it out, a rest past
    /// its minute ends; the speed counts the last second's taps.
    fn settle(&mut self, now: f64) {
        if self.rest_until.is_some_and(|r| now >= r) {
            self.rest_until = None;
        }
        if let Some(at) = self.lit_at {
            if now - at >= STREAK {
                self.lit_at = None;
                self.taps.clear();
                self.rest_until = Some(at + 2.0 * STREAK).filter(|r| now < *r);
            } else if !self.holding && now - self.last >= QUIET {
                self.lit_at = None;
            }
        }
        self.taps.retain(|t| now - t < 1.0);
    }
    fn rests(&self, now: f64) -> bool {
        self.rest_until.is_some_and(|r| now < r)
    }
    fn light(&mut self, now: f64) {
        if self.lit_at.is_none() && !self.rests(now) {
            self.lit_at = Some(now);
        }
    }
    /// A tap of the coin: whether it may mint -- not while the coin rests, not past thirteen this second.
    pub fn tap(&mut self, now: f64) -> bool {
        self.settle(now);
        if self.rests(now) {
            return false;
        }
        self.light(now);
        self.last = now;
        if self.taps.len() >= CEILING {
            return false;
        }
        self.taps.push(now);
        true
    }
    /// A finger on the coin lights the game at the touch itself; its lift starts the quiet.
    pub fn touch(&mut self, now: f64, down: bool) {
        self.settle(now);
        self.holding = down;
        self.last = now;
        if down {
            self.light(now);
        }
    }
    /// Whether the game burns now.
    pub fn lit(&mut self, now: f64) -> bool {
        self.settle(now);
        self.lit_at.is_some()
    }
    /// What the page draws: lit, the speed, the burn's seconds (of sixty), the rest's seconds left.
    pub fn shown(&mut self, now: f64) -> serde_json::Value {
        self.settle(now);
        serde_json::json!({
            "lit": self.lit_at.is_some(), "speed": self.taps.len(),
            "run": self.lit_at.map(|a| (now - a).clamp(0.0, STREAK).floor() as i64),
            "rest": self.rest_until.map(|r| (r - now).max(0.0).ceil() as i64),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ONE CLASSIFICATION (iOS MTCoinCounts.add): a move's coin and the Timer are chess, a won sum taken and a lost sum given are chess
    /// too, so received and reactions count people and reactions alone; any other earning of a game counts with the chats.
    #[test]
    fn every_coin_counts_under_its_own_source() {
        let e = |k: &str, c: i64, r: &str| Entry { k: k.into(), c, refr: r.into(), peer: None, on: None, at: 0.0 };
        let mut n = Counts::default();
        for x in [e("earn", 3, "chess:m1"), e("earn", 2, "timer:t1"), e("receive", 50, "chess-won:g1"), e("spend", 20, "chess-lost:g2"),
                  e("earn", 7, "chess-pot:g3"), e("receive", 100, "tx:abc"), e("spend", 4, "react:x"), e("earn", 9, "vpnwall:1")] {
            n.add(&x);
        }
        assert_eq!((n.played, n.earned, n.received, n.spent, n.walled), (3 + 2 + 50 - 20, 7, 100, 4, 9));
    }

    fn vault() -> (Vault, std::path::PathBuf) {
        let dir = std::env::temp_dir().join(format!("mt-coins-{}", crate::board::fresh_id()));
        (Vault::at(&dir).unwrap(), dir)
    }

    #[test]
    fn the_words_keys_agree_with_ios_frozen_vectors() {
        let counting: Vec<u8> = (0..32).collect();
        let k = vault_keys(&counting);
        assert_eq!(hex(&k.seal), "e9720340e7dcb4b6c2befea9a657718560646f727614f732971bf9ea7d3795fb");
        assert_eq!(hex(&k.token), "4b7fc64e903945bee08b4fc45f7ca094d9b61ae2c96f4d97ebd1ccd8b4b9ab86");
        assert_eq!(hex(&sha(&[&k.token])), "9e34605e5200c5f339f4a527f0654af5436a96b629f66835f91495b65e0ba245");
        let (tk, tt) = top_token(&counting);
        assert_eq!(hex(&tk), "7a504b1911419189651d037cfa3776404731270ebe01a2cbefe7aabbca5140d5");
        assert_eq!(hex(&tt), "67b2f9e4f8ba74bffee41cdfd8de2d3efca20554a495910ebc823b8ef4545ce2");
        assert_eq!(hex(&sha(&[&tt])), "f0b3cb47ae97a4849fd8d42d75bbbcc395f93b9b4adae16c5bb0e91b4641d369");
        // the levels: π's prefixes and the person's doublings (iOS selfCheck / levelKAT)
        assert_eq!((pi_place(2), pi_place(3), pi_place(313), pi_place(314), pi_place(3_141_592_653_589_793_238)), (0, 1, 2, 3, 19));
        assert_eq!((person_level(1), person_level(3), person_level(1_048_576), person_level(0)), (Some(0), Some(1), Some(20), None));
    }

    #[test]
    fn a_second_mints_one_coin_whatever_door_and_a_name_pays_once() {
        let (v, dir) = vault();
        let t = crate::wire::now_ms();
        // the book's rule before the time cut, its second stood there
        let base = crate::cointx::TIME_CUT - 10_000;
        test_second(Some(base));
        // the chat's coin comes on now: two letters of this second share its one coin, a letter born before mints nothing
        let born = t + 10_000;
        let got = earn(&v, &[(format!("mid:t{born}-A"), born), (format!("mid:t{born}-B"), born + 1), ("mid:t1-OLD".into(), 1)], None);
        assert_eq!(got, 1, "one coin a second, every door together");
        assert_eq!(earn(&v, &[(format!("mid:t{born}-A"), born)], None), 0, "a name pays once");
        // a window's coins stand in the balance at once and are booked as one move at its close
        let before = balance(&v);
        test_second(Some(base + 1));
        let w = in_window(&v, 1, PULL, 1, false);
        assert_eq!(w, 1);
        assert_eq!(balance(&v), before + w);
        close_windows(&v, true);
        let (_, counts, moves) = state(&v, 10);
        assert_eq!(counts.tapped, w);
        assert!(moves.iter().any(|e| e.refr.starts_with(PULL)));
        // a send above the balance is refused; a receive once by its name; a restored name moves nothing
        assert!(!moved(&v, "send", balance(&v) + 1, "x", Some("B"), None));
        assert!(moved(&v, "receive", 500, "mid:t5-R", Some("B"), None));
        assert!(!moved(&v, "receive", 500, "mid:t5-R", Some("B"), None));
        assert!(!moved(&v, "receive", 500, "arc:mid:t5-R", Some("B"), None));
        assert!(moved(&v, "send", 200, "tx:abc", Some("B"), None));
        // ONLY THE CHAIN MINTS FROM THE TIME CUT (iOS priced, fold-6): no door of the book mints; a burn still burns
        test_second(Some(crate::cointx::TIME_CUT));
        assert_eq!(earn(&v, &[(format!("mid:t{born}-C"), born + 2)], None), 0);
        assert_eq!(in_window(&v, 1, PULL, 1, false), 0);
        let held = balance(&v);
        assert_eq!(in_window(&v, 7, "burn:x:", 7, true), 7);
        assert_eq!(balance(&v), held - 7);
        close_windows(&v, true);
        test_second(None);
        // the book read again from the vault says the same
        flush(&v, &dir, &|_| false);
        let bal = balance(&v);
        BOOKS.lock().unwrap().as_mut().unwrap().remove(&v.dir().to_string_lossy().to_string());
        assert_eq!(balance(&v), bal);
        // every move joined its source's sealed chain
        let pull = std::fs::read_to_string(dir.join("TimeChain").join("wallet-pantheon.jsonl")).unwrap();
        let l: serde_json::Value = serde_json::from_str(pull.lines().next().unwrap()).unwrap();
        assert_eq!(l["hash"].as_str().unwrap(), chain_seal(1, l["at"].as_i64().unwrap(), "earn", l["c"].as_i64().unwrap(), l["ref"].as_str().unwrap(), &"0".repeat(64)));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_coin_letter_reads_as_ios_writes_it() {
        let id = "5CA782B0-A754-4443-B673-0579412060C2";
        let code = crate::wire::b64(format!("{{\"c\":60000,\"id\":\"{id}\"}}").as_bytes()).replace('+', "-").replace('/', "_");
        let text = format!("🪙 60000\n{LETTER_LINK}{code}");
        assert_eq!(letter_of(&text), Some((60000, id.to_string())));
        assert!(bound(id, &format!("mid:t1791483499406-{id}")) && !bound(id, "mid:t1-OTHER"));
        assert!(is_transfer(&format!("🪙 1,234 · 20 min\n{TX_LINK}2dd4")));
    }

    #[test]
    fn the_pantheon_burns_a_minute_then_rests_a_minute() {
        let mut p = Pantheon::default();
        assert!(p.tap(100.0), "the first tap lights the game and mints");
        assert_eq!(p.shown(100.5)["lit"], true);
        // thirteen taps a second count at most
        let mut counted = 1;
        for i in 0..20 {
            if p.tap(100.0 + 0.01 * i as f64) {
                counted += 1;
            }
        }
        assert_eq!(counted, CEILING);
        // three seconds of quiet put the fire out, with no rest (what the wallet's auto minting asks at the page's opening)
        assert!(p.lit(103.1), "the last tap at 100.19 burns three seconds");
        assert!(!p.lit(103.2));
        assert_eq!(p.shown(103.2)["lit"], false);
        assert!(p.shown(103.2)["rest"].is_null());
        // a finger held keeps it burning through the quiet
        assert!(p.tap(200.0));
        p.touch(200.5, true);
        assert_eq!(p.shown(205.0)["lit"], true);
        p.touch(205.0, false);
        // a burn unbroken for sixty seconds (lit at 200) goes out at 260, and the coin rests sixty
        let mut t = 205.0;
        while t < 257.5 {
            t += 2.0;
            assert!(p.tap(t), "the burn mints through its minute ({t})");
        }
        assert_eq!(p.shown(259.9)["run"], 59);
        assert!(!p.tap(260.5), "past its minute the coin rests");
        assert_eq!(p.shown(260.5)["lit"], false);
        assert_eq!(p.shown(260.5)["rest"], 60);
        assert!(!p.tap(319.0), "still resting");
        assert!(p.tap(320.5), "the rest is over: a new burn");
        assert_eq!(p.shown(320.5)["run"], 0);
    }

    #[test]
    fn a_chain_is_whole_from_its_genesis_and_a_spoiled_link_breaks_it() {
        let dir = std::env::temp_dir().join(format!("mt-chain-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        let vault = Vault::at(&dir.join("vault")).unwrap();
        test_second(Some(crate::cointx::TIME_CUT - 1000)); // the book mints only before the time cut
        assert!(in_window(&vault, PRICE, TAP, 1, false) > 0);
        test_second(None);
        close_windows(&vault, true);
        flush(&vault, &dir, &|_| false);
        let h = head(&dir, "pantheon");
        assert_eq!((h.n, h.whole), (1, true));
        assert_eq!(heads(&dir).iter().map(|h| h.source.as_str()).collect::<Vec<_>>(), vec!["pantheon"]);
        assert_eq!(links(&dir, "pantheon", 10)[0].hash, h.hash);
        // a link whose words were changed after its seal: the chain is no longer whole
        let file = dir.join("TimeChain").join("wallet-pantheon.jsonl");
        let text = std::fs::read_to_string(&file).unwrap().replacen("\"c\":", "\"c\":9", 1);
        std::fs::write(&file, text).unwrap();
        assert!(!head(&dir, "pantheon").whole);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
