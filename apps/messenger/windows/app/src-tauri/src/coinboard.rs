//! THE PEOPLE'S BALANCES AND LEVELS (iOS MTCoinBoard, MTLevelDistribution; the author's words 04.10.2026 and 11.10.2026: «everywhere an
//! avatar is shown, the balance on the left and the user's global level on the right»): what each correspondent last told in their
//! presence words -- «C» and their coins, «L» and their Global Level -- the newest word wins, a word that names no level takes it
//! away. Nothing told is believed past the pair's own coin chain: the coins shown are the chain's proven and declared, the level
//! at most the wallet level of that number; a pair whose chain is not read yet wears nothing. The levels' colours stand on the
//! public distribution of levels, read from the nodes (/level-get) -- this machine publishes nothing to it.

use crate::vault::Vault;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

const KEY: &str = "coinBoard";
/// The owner's switch (iOS MTCoinShow «Show my coins», Privacy): on, every presence word carries the balance.
pub const SHOW: &str = "coinsShown";

#[derive(Serialize, Deserialize, Clone, Copy)]
struct Told {
    v: i64,
    at: f64,
}
#[derive(Serialize, Deserialize, Default)]
struct Kept {
    told: HashMap<String, Told>,
    levels: HashMap<String, Told>,
}
#[derive(Default)]
struct State {
    kept: Kept,
    loaded: bool,
    /// a pair's chain as its node proves it: (coins, read at)
    chain: HashMap<String, (i64, f64)>,
    heard_coins: HashMap<String, Told>,
    heard_level: HashMap<String, Told>,
    level_heard_at: HashMap<String, f64>,
    asking: HashSet<String>,
    /// the public distribution of levels: (level, count), read at
    bins: Vec<(i64, i64)>,
    bins_at: f64,
}
static STATE: Mutex<Option<State>> = Mutex::new(None);

fn now() -> f64 {
    crate::wire::now_ms() as f64 / 1000.0
}
fn with<R>(vault: &Vault, f: impl FnOnce(&mut State) -> R) -> R {
    let mut g = STATE.lock().unwrap();
    let st = g.get_or_insert_with(State::default);
    if !st.loaded {
        st.loaded = true;
        st.kept = vault.get(KEY).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    }
    f(st)
}
fn keep(vault: &Vault, st: &State) {
    vault.set(KEY, serde_json::to_vec(&st.kept).unwrap_or_default().as_slice());
}

/// Whether the owner shows their coins (on by default, as iOS).
pub fn shown(vault: &Vault) -> bool {
    vault.get(SHOW).map(|b| b != b"0").unwrap_or(true)
}

/// MY TAIL OF THE PRESENCE WORD (iOS coinTail + levelTail): «C» and the balance while the owner shows it, «L» and the Global Level once
/// this life knows the person's seconds -- an unknown level is not said as none.
pub fn tail(vault: &Vault) -> String {
    let balance = crate::coins::balance(vault);
    let mut out = String::new();
    if shown(vault) {
        out += &format!("C{balance}");
    }
    if crate::person::level(crate::person::seconds()).is_some() {
        out += &format!("L{}", crate::person::global(balance));
    }
    out
}

/// What stands after the ground's digits of a presence word's held tags (iOS coinsSaid / levelSaid): the balance, and the level --
/// Some(-1) when the word names the held tags and no level (its owner keeps it to themselves), None when it names none of them.
pub fn said(tail: &str) -> (Option<i64>, Option<i64>) {
    let digits = |s: &str| -> usize { s.chars().take_while(|c| c.is_ascii_digit()).count() };
    let Some(i) = tail.find('N') else { return (None, None) };
    let mut rest = &tail[i + 1..];
    rest = &rest[digits(rest)..];
    if let Some(r) = rest.strip_prefix('A') {
        rest = &r[digits(r)..];
    }
    let Some(r) = rest.strip_prefix('W') else { return (None, None) };
    rest = &r[digits(r)..];
    let Some(r) = rest.strip_prefix('G') else { return (None, None) };
    rest = &r[digits(r)..];
    let mut coins = None;
    if let Some(r) = rest.strip_prefix('C') {
        let n = r.chars().take_while(|c| c.is_ascii_digit() || *c == '-').count();
        coins = r[..n].parse::<i64>().ok();
        rest = &r[n..];
    }
    let level = match rest.strip_prefix('L') {
        Some(r) => Some(r[..digits(r)].parse::<i64>().unwrap_or(-1)),
        None => Some(-1),
    };
    (coins, level)
}

/// Presence words heard on the lane, waiting for the walk that holds the vault: (pair, the word's held tags, its moment).
static HEARD: Mutex<Vec<(String, String, f64)>> = Mutex::new(Vec::new());
pub fn hear_later(conv: &str, tail: &str, at: f64) {
    let mut h = HEARD.lock().unwrap();
    h.retain(|x| x.0 != conv);
    h.push((conv.to_string(), tail.to_string(), at));
}
/// The words heard since, settled into the board.
pub fn drain(vault: &Vault) {
    let heard: Vec<_> = std::mem::take(&mut *HEARD.lock().unwrap());
    for (conv, tail, at) in heard {
        self::heard(vault, &conv, &tail, at);
    }
}

/// A pair's presence word told its balance and level (iOS note / noteLevel): kept when newer than the last, up to what the pair's
/// chain proves.
pub fn heard(vault: &Vault, conv: &str, tail: &str, at: f64) {
    let (coins, level) = said(tail);
    let mut prove = false;
    with(vault, |st| {
        if let Some(c) = coins {
            if st.kept.told.get(conv).map(|t| t.at).unwrap_or(0.0) <= at {
                if c < 0 {
                    // a negative balance is «hidden»: the pair turned its coins off
                    st.heard_coins.remove(conv);
                    if st.kept.told.remove(conv).is_some() {
                        keep(vault, st);
                    }
                } else {
                    st.heard_coins.insert(conv.to_string(), Told { v: c, at });
                    prove = true;
                }
            }
        }
        if let Some(l) = level {
            let last = st.kept.levels.get(conv).map(|t| t.at).unwrap_or(0.0).max(st.level_heard_at.get(conv).copied().unwrap_or(0.0));
            if last <= at {
                st.level_heard_at.insert(conv.to_string(), at);
                if l >= 0 {
                    st.heard_level.insert(conv.to_string(), Told { v: l, at });
                    prove = true;
                } else {
                    st.heard_level.remove(conv);
                    if st.kept.levels.remove(conv).is_some() {
                        keep(vault, st);
                    }
                }
            }
        }
        settle(vault, st, conv);
    });
    if prove {
        prove_chain(vault, conv);
    }
}

/// What the pair told, kept up to its chain: the chain's number, never the told one; the level at most the wallet level of it.
fn settle(vault: &Vault, st: &mut State, conv: &str) {
    let Some((cap, _)) = st.chain.get(conv).copied() else { return };
    let mut moved = false;
    if let Some(t) = st.heard_coins.get(conv).copied() {
        if st.kept.told.get(conv).map(|x| x.v) != Some(cap) {
            moved = true;
        }
        st.kept.told.insert(conv.to_string(), Told { v: cap, at: t.at });
    }
    if let Some(l) = st.heard_level.get(conv).copied() {
        let level = l.v.min(crate::fabric::wallet_level(cap));
        if st.kept.levels.get(conv).map(|x| x.v) != Some(level) {
            st.kept.levels.insert(conv.to_string(), Told { v: level, at: l.at });
            moved = true;
        }
    }
    if moved {
        keep(vault, st);
    }
}

/// THE PAIR'S CHAIN READ FROM ITS NODE (iOS proveChain): at most once in ten minutes, off the caller's thread.
fn prove_chain(vault: &Vault, conv: &str) {
    let fresh = |st: &State| st.chain.get(conv).is_some_and(|c| now() - c.1 < 600.0) || st.asking.contains(conv);
    let Some(from) = crate::wallet::peer_from(vault, conv) else { return };
    let Some(door) = crate::cointx::chain_door(&from) else { return };
    if with(vault, |st| { let f = fresh(st); if !f { st.asking.insert(conv.to_string()); } f }) {
        return;
    }
    let (vault, conv) = (vault.clone(), conv.to_string());
    std::thread::spawn(move || {
        let read = crate::wallet::chain3(&from, &door);
        let was = read.is_some();
        with(&vault, |st| {
            st.asking.remove(&conv);
            if let Some(c) = read {
                st.chain.insert(conv.clone(), ((c.proven + c.declared).max(0), now()));
                settle(&vault, st, &conv);
            }
        });
        crate::trace_line(&format!("coin_board chain read={was}"));
    });
}

/// THE PUBLIC DISTRIBUTION OF LEVELS (iOS MTLevelDistribution.refresh, the reading alone): every minute at most; a level's colour
/// is its rank in it. This machine puts no row of its own (/level-put is a publication -- it waits for the owner's word).
pub fn read_bins() {
    if STATE.lock().unwrap().as_ref().is_some_and(|st| now() - st.bins_at < 60.0) {
        return;
    }
    if let Some(st) = STATE.lock().unwrap().as_mut() {
        st.bins_at = now();
    }
    for door in crate::doors::all().into_iter().take(3) {
        let (code, o) = crate::doors::post_at(&door, "/level-get", &json!({}), 6_000);
        let Some(rows) = o.filter(|_| code == 200).and_then(|o| o["levels"].as_array().cloned()) else { continue };
        let mut bins: Vec<(i64, i64)> = rows.iter().filter_map(|r| Some((r["level"].as_i64()?, r["count"].as_i64()?)))
            .filter(|(l, c)| (0..=62).contains(l) && (1..=1_000_000).contains(c)).collect();
        bins.sort();
        bins.dedup_by_key(|b| b.0);
        if let Some(st) = STATE.lock().unwrap().as_mut() {
            st.bins = bins;
        }
        return;
    }
}

/// One row of the Montana Top (iOS MTTopNet.Row): its name (sha256 of its owner's token), the name its owner shows, the coins.
#[derive(Serialize, Clone)]
pub struct TopRow {
    pub id: String,
    pub name: String,
    pub coins: i64,
}
/// THE MONTANA TOP AS THE NODES KEEP IT (iOS MTTopNet): the whole table, the most coins first, this person's place in it, whether a
/// node that keeps it answered, and this seed's own row.
#[derive(Serialize, Clone, Default)]
pub struct Top {
    pub rows: Vec<TopRow>,
    pub rank: Option<i64>,
    pub answered: bool,
    pub mine: String,
}
static TOP: Mutex<Option<(Top, f64)>> = Mutex::new(None);

/// The row this seed owns in the table (iOS MTTopNet.myRow): sha256 of the token only the words derive.
pub fn top_row(entropy: &[u8]) -> String {
    let (_, token) = crate::coins::top_token(entropy);
    crate::wire::hex(&crate::wire::sha(&[&token]))
}

/// A name of the table as letters only (iOS read): the controls and the marks of direction and format a node of another hand may
/// carry are taken out here again.
fn letters(name: &str) -> String {
    name.chars().filter(|c| !c.is_control() && !matches!(*c as u32, 0x00AD | 0x061C | 0x180E | 0x200B..=0x200F | 0x202A..=0x202E
        | 0x2060..=0x2064 | 0x2066..=0x206F | 0xFEFF | 0xFFF9..=0xFFFB)).take(64).collect()
}

/// THE ONE TABLE READ (iOS MTTopNet.read, the author's words 04.10.2026: «a live set», «everyone has one source of all data»): the
/// first node that keeps it answers the whole table and this row's place; once in three seconds at most. Nothing is put here:
/// the person's own row (/top-put) is a publication of a name and coins and waits for the owner's word.
pub fn read_top(mine: &str) {
    {
        let mut g = TOP.lock().unwrap();
        if g.as_ref().is_some_and(|(_, at)| now() - at < 3.0) {
            return;
        }
        let mut kept = g.take().map(|(t, _)| t).unwrap_or_default();
        kept.mine = mine.to_string();
        *g = Some((kept, now()));
    }
    for door in crate::doors::all().into_iter().take(3) {
        let (code, o) = crate::doors::post_at(&door, "/top-get", &json!({ "row": mine }), 6_000);
        let Some(o) = o.filter(|_| code == 200) else { continue };
        let Some(list) = o["rows"].as_array() else { continue };
        let rows: Vec<TopRow> = list.iter().filter_map(|x| Some(TopRow { id: x["row"].as_str()?.chars().take(64).collect(),
            name: letters(x["name"].as_str().unwrap_or("")), coins: x["coins"].as_i64()? })).collect();
        let first = TOP.lock().unwrap().as_ref().is_none_or(|(t, _)| !t.answered);
        if first {
            crate::trace_line(&format!("top_get rows={} rank={}", rows.len(), o["rank"].as_i64().unwrap_or(0)));
        }
        *TOP.lock().unwrap() = Some((Top { rows, rank: o["rank"].as_i64(), answered: true, mine: mine.to_string() }, now()));
        return;
    }
}
/// The table as last read, with this seed's row; empty and unanswered before a node that keeps it spoke.
pub fn top() -> Top {
    TOP.lock().unwrap().as_ref().map(|(t, _)| t.clone()).unwrap_or_default()
}

/// A level's rank in the distribution, 0 at the lowest reported level and 1 at the highest (iOS MTLevelDistribution.rank).
pub fn rank(level: i64, bins: &[(i64, i64)]) -> Option<f64> {
    let (first, last) = (bins.first()?, bins.last()?);
    if first.0 == last.0 {
        return Some(if level < first.0 { 0.0 } else { 1.0 });
    }
    if level <= first.0 {
        return Some(0.0);
    }
    if level >= last.0 {
        return Some(1.0);
    }
    let total: f64 = bins.iter().map(|b| b.1 as f64).sum();
    let before: f64 = bins.iter().filter(|b| b.0 < level).map(|b| b.1 as f64).sum();
    let same = bins.iter().find(|b| b.0 == level).map(|b| b.1 as f64).unwrap_or(0.0);
    let (low, high) = (first.1 as f64 / 2.0, total - last.1 as f64 / 2.0);
    Some(((before + same / 2.0 - low) / (high - low)).clamp(0.0, 1.0))
}

/// THE BADGES AS THE WINDOW DRAWS THEM: mine (the balance while shown, the Global Level once the seconds are read) and each pair's
/// told and proven, with every level's rank for its colour.
pub fn badges(vault: &Vault) -> Value {
    let balance = crate::coins::balance(vault);
    let mine_level = crate::person::level(crate::person::seconds()).map(|_| crate::person::global(balance));
    with(vault, |st| {
        let ranks = |l: i64| rank(l, &st.bins);
        let mut told = serde_json::Map::new();
        let convs: HashSet<&String> = st.kept.told.keys().chain(st.kept.levels.keys()).collect();
        for c in convs {
            let lv = st.kept.levels.get(c).map(|t| t.v);
            told.insert(c.clone(), json!({ "coins": st.kept.told.get(c).map(|t| t.v), "level": lv, "rank": lv.and_then(ranks) }));
        }
        json!({ "mine": { "coins": shown(vault).then_some(balance), "level": mine_level, "rank": mine_level.and_then(ranks) }, "told": told })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_top_row_is_ios_frozen_vector_and_a_name_is_letters_only() {
        // iOS MTTopNet.keyKAT: the counting bytes 0x00..0x1f
        let counting: Vec<u8> = (0..32).collect();
        assert_eq!(top_row(&counting), "f0b3cb47ae97a4849fd8d42d75bbbcc395f93b9b4adae16c5bb0e91b4641d369");
        assert_eq!(letters("Ки\u{202E}ра\u{200B}\u{0007}"), "Кира");
    }

    #[test]
    fn a_presence_word_tells_its_balance_and_level_after_the_ground() {
        assert_eq!(said("F12N34A5W6G7C1200L3Q"), (Some(1200), Some(3)));
        assert_eq!(said("F12N34A5W6G7C1200Q"), (Some(1200), Some(-1)), "the held tags named and no level: kept to itself");
        assert_eq!(said("F12N34A5W6G7L5"), (None, Some(5)), "the coins hidden, the level said");
        assert_eq!(said("F12N34A5W6G7C-1"), (Some(-1), Some(-1)), "a negative balance is a withdrawal");
        assert_eq!(said("F12N34"), (None, None), "a build before the ground names nothing");
        // the rank: 0 at the lowest reported level, 1 at the highest, the middle by the counts between
        let bins = [(1, 10), (3, 10), (5, 10)];
        assert_eq!((rank(1, &bins), rank(5, &bins), rank(0, &bins)), (Some(0.0), Some(1.0), Some(0.0)));
        assert_eq!(rank(3, &bins), Some(0.5));
        assert_eq!(rank(3, &[]), None);
    }

    #[test]
    fn what_a_pair_tells_is_shown_only_as_far_as_its_chain_proves() {
        let mut st = State::default();
        let dir = std::env::temp_dir().join(format!("mt-board-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        let v = Vault::at(&dir).unwrap();
        st.heard_coins.insert("p".into(), Told { v: 1_000_000_000, at: 5.0 });
        st.heard_level.insert("p".into(), Told { v: 13, at: 5.0 });
        settle(&v, &mut st, "p");
        assert!(st.kept.told.is_empty() && st.kept.levels.is_empty(), "a chain not read: nothing worn");
        st.chain.insert("p".into(), (314, 0.0));
        settle(&v, &mut st, "p");
        assert_eq!(st.kept.told["p"].v, 314, "the chain's number, never the told one");
        assert_eq!(st.kept.levels["p"].v, 3, "the level at most the wallet level of the chain's coins");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
