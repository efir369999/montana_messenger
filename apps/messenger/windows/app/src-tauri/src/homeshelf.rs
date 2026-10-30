//! THE FILES ON YOUR NODE (iOS MTHomeShelf, MTHomeBook, MTHomeKeep in MontanaHomeNode.swift; the author's word 18.10.2026 20:1x MSK:
//! «make my node my personal storage, so I clear the cache in the app and it weighs nothing, and even after deleting the app I come
//! back and load everything from my own node»). Every file of the letters is sealed by this computer under a key of its own --
//! from the words and the file's name, so a pass cut short goes on from what the node already holds -- cut into the pieces the
//! doors already carry, and laid on the shelf of the words' token beside the copies (/home-put). Which file is which pieces is THE
//! BOOK; it lies on the node as well, sealed under a key the words alone derive and named by a name the words alone derive -- so
//! the 24 words bring the book back, and the book every file. The node holds what it says it holds (/home-have): a file leaves
//! this computer only when the node has just named every one of its pieces, and comes back at a look or a tap.

use crate::homenode;
use crate::http::{self, Body, Sink};
use crate::media::{self, Source, Store, CHUNK};
use crate::vault::Vault;
use crate::wire::{b64, hex, hmac, unb64};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
use std::sync::Mutex;

/// The book in this person's vault (iOS HomeBook/book-<person>.json, a cache of the one on the node).
const BOOK: &str = "homeBook";
/// The person's term for a file nobody opened (days; 0 -- for ever) and the ceiling of the cache (GB; 0 -- none).
pub const KEEP_DAYS: &str = "homeKeepDays";
pub const LIMIT_GB: &str = "homeCacheLimit";

/// A file the node was given: its size, its pieces in order, and when the node named them all.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Entry {
    pub z: u64,
    pub p: Vec<String>,
    pub at: f64,
}

/// The keys the words derive for the shelf's files, held by the run once the person's words were read (never the words).
#[derive(Clone)]
pub struct Keys {
    book: [u8; 32],
    token: String,
}
static KEYS: Mutex<Option<Keys>> = Mutex::new(None);
pub fn arm(entropy: &[u8]) {
    *KEYS.lock().unwrap() = Some(keys(entropy));
}
pub fn keys(entropy: &[u8]) -> Keys {
    Keys { book: book_key(entropy), token: homenode::token_hex(entropy) }
}
fn armed() -> Option<Keys> {
    KEYS.lock().unwrap().clone()
}

// ── the keys (iOS frozen vectors) ──
pub fn book_key(entropy: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let _ = hkdf::Hkdf::<sha2::Sha256>::new(Some(&[]), entropy).expand(b"mt-home-book-key", &mut out);
    out
}
pub fn book_name(book_key: &[u8; 32]) -> String {
    hex(&hmac(book_key, b"mt-home-book-name"))
}
/// A file's key, from the words and the file's name: the same file sealed again gives the same pieces.
pub fn file_key(book_key: &[u8; 32], name: &str) -> [u8; 32] {
    hmac(book_key, &[b"mt-home-file-key".as_slice(), name.as_bytes()].concat())
}

/// Files go to the node while its copies do (the switch, the node's level); taking one's own files back asks no level.
pub fn bringing(v: &Vault) -> bool {
    !homenode::host(v).is_empty() && armed().is_some()
}

// ── the book ──
pub fn book(v: &Vault) -> BTreeMap<String, Entry> {
    v.get(BOOK).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}
fn save(v: &Vault, b: &BTreeMap<String, Entry>) {
    if let Ok(d) = serde_json::to_vec(b) {
        v.set(BOOK, &d);
    }
}
/// The names whose every piece the node named: a copy for the node leaves them out (iOS HomeNodeWatch.send, MTHomeBook.kept).
pub fn kept(v: &Vault) -> HashSet<String> {
    book(v).into_iter().filter(|(_, e)| 0.0 < e.at).map(|(n, _)| n).collect()
}

// ── the wire ──
fn post(v: &Vault, k: &Keys, path: &str, body: &Value) -> Option<(i32, Value)> {
    let (h, p) = (homenode::host(v), homenode::pin(v));
    let b = homenode::base(&h, &p)?;
    let body = body.to_string();
    let a = http::exchange("POST", &format!("{b}{path}"), &[("X-Montana-Vault", &k.token), ("Content-Type", "application/json")],
                           Body::Bytes(body.as_bytes()), Sink::Memory(16 << 20), (!p.is_empty()).then_some(p.as_str()), 30_000, &|_| {}).ok()?;
    Some((a.code, serde_json::from_slice(&a.body).unwrap_or_default()))
}
pub fn get(v: &Vault, k: &Keys, bid: &str) -> Option<Vec<u8>> {
    let (code, j) = post(v, k, "/home-get", &json!({ "bid": bid }))?;
    (code == 200).then(|| j["data"].as_str().and_then(unb64)).flatten()
}
/// The node's own word on which of these pieces it holds; None when it did not answer.
pub fn have(v: &Vault, k: &Keys, bids: &[String]) -> Option<HashSet<String>> {
    let mut out = HashSet::new();
    for part in bids.chunks(4096) {
        let (code, j) = post(v, k, "/home-have", &json!({ "bids": part }))?;
        if code != 200 {
            return None;
        }
        out.extend(j["have"].as_array()?.iter().filter_map(|x| x.as_str().map(str::to_string)));
    }
    Some(out)
}
/// True only on the node's «held».
pub fn put(v: &Vault, k: &Keys, bid: &str, sealed: &[u8], over: bool) -> bool {
    post(v, k, "/home-put", &json!({ "bid": bid, "data": b64(sealed), "over": over })).is_some_and(|(code, j)| code == 200 && j["held"].as_bool() == Some(true))
}
pub fn put_book(v: &Vault, k: &Keys) -> bool {
    let Ok(plain) = serde_json::to_vec(&book(v)) else { return false };
    let Some(sealed) = crate::crypto::seal(&k.book, &plain) else { return false };
    let ok = put(v, k, &book_name(&k.book), &sealed, true);
    crate::trace_line(&format!("home_book put files={} bytes={} held={}", book(v).len(), sealed.len(), ok as u8));
    ok
}
/// The node's book joins this computer's: what either names stays named. The files it named.
pub fn take_book(v: &Vault, k: &Keys) -> usize {
    let Some(theirs) = get(v, k, &book_name(&k.book)).and_then(|s| crate::crypto::open(&k.book, &s))
        .and_then(|p| serde_json::from_slice::<BTreeMap<String, Entry>>(&p).ok()) else {
        crate::trace_line("home_book none on your node");
        return 0;
    };
    let mut mine = book(v);
    let n = theirs.len();
    for (name, e) in theirs {
        mine.entry(name).or_insert(e);
    }
    save(v, &mine);
    crate::trace_line(&format!("home_book taken files={n}"));
    n
}

/// A file of the letters: its letter's name (the store's key), its name as iOS keeps it (history::file_name) and its size.
#[derive(Clone, Debug)]
pub struct File {
    pub mid: String,
    pub name: String,
    pub size: u64,
}
/// Every file of the letters this computer holds, named as iOS names its store's files.
pub fn files(b: &crate::book::Book, store: &Store) -> Vec<File> {
    let mut out = vec![];
    for c in b.all() {
        for m in c.msgs.iter().filter(|m| m.text.starts_with(media::MARK)) {
            if !store.has(&m.mid) {
                continue;
            }
            // the size the letter's manifest names, else the file's own (read once)
            let named = serde_json::from_str::<Value>(&m.text[media::MARK.len()..]).ok().and_then(|j| j["sz"].as_u64());
            let size = store.big(&m.mid).or(named).or_else(|| store.get(&m.mid).map(|x| x.len() as u64)).unwrap_or(0);
            if size > 0 {
                out.push(File { mid: m.mid.clone(), name: crate::history::file_name(&m.mid, &m.text), size });
            }
        }
    }
    out
}
/// Where a file's pieces come from: a big one's kept pieces, a whole one's bytes.
fn with_source<R>(store: &Store, f: &File, act: impl FnOnce(&Source) -> R) -> Option<R> {
    match store.big(&f.mid) {
        Some(size) => Some(act(&Source::Parts(store, &f.mid, size))),
        None => store.get(&f.mid).map(|b| act(&Source::Bytes(&b))),
    }
}

/// A FILE TO THE NODE (iOS keepFile): every piece's name first (each sealed once to learn it), the node's word on them, then what
/// it lacks. The book's entry, or None when a piece did not go.
pub fn keep_file(v: &Vault, k: &Keys, store: &Store, f: &File) -> Option<Entry> {
    let key = file_key(&k.book, &f.name);
    with_source(store, f, |src| {
        let bids: Vec<String> = (0..src.count()).map(|i| src.piece(i).and_then(|p| media::seal_piece(&p, &key, i)).map(|x| x.1)).collect::<Option<_>>()?;
        let held = have(v, k, &bids)?;
        for (i, bid) in bids.iter().enumerate().filter(|(_, b)| !held.contains(*b)) {
            let (sealed, again) = media::seal_piece(&src.piece(i)?, &key, i)?;
            if &again != bid || !put(v, k, bid, &sealed, false) {
                return None; // the file changed under us, or the node did not take it
            }
        }
        Some(Entry { z: f.size, p: bids, at: crate::wire::now_ms() as f64 / 1000.0 })
    }).flatten()
}

/// What the node holds of the book, in its own word asked now: (files held whole, their bytes); None -- it did not answer.
pub fn word(v: &Vault, k: &Keys) -> Option<(usize, u64)> {
    let all = book(v);
    let held = have(v, k, &all.values().flat_map(|e| e.p.clone()).collect::<Vec<_>>())?;
    let whole: Vec<&Entry> = all.values().filter(|e| e.p.iter().all(|b| held.contains(b))).collect();
    Some((whole.len(), whole.iter().map(|e| e.z).sum()))
}

/// THE PASS (iOS keepPass): every file the book does not name at its size goes to the node; the book follows every twenty-five
/// files and at the end. The answer is the node's word on the whole book.
pub fn keep_pass(v: &Vault, k: &Keys, b: &crate::book::Book, store: &Store, progress: &dyn Fn(f64)) -> Option<(usize, u64)> {
    let mut bk = book(v);
    if bk.is_empty() {
        take_book(v, k);
        bk = book(v);
    }
    let todo: Vec<File> = files(b, store).into_iter().filter(|f| bk.get(&f.name).map(|e| e.z) != Some(f.size)).collect();
    let total = todo.iter().map(|f| f.size).sum::<u64>().max(1);
    crate::trace_line(&format!("home_keep begin files={} bytes={total} kept={}", todo.len(), bk.len()));
    let (mut done, mut laid, mut since, mut refused) = (0u64, 0, 0, 0);
    for f in &todo {
        match keep_file(v, k, store, f) {
            Some(e) => {
                bk.insert(f.name.clone(), e);
                laid += 1;
                since += 1;
            }
            None => {
                refused += 1;
                if 3 <= refused && laid == 0 {
                    break; // the node does not take anything now: the next pass goes on
                }
            }
        }
        done += f.size;
        progress(done as f64 / total as f64);
        if 25 <= since {
            save(v, &bk);
            put_book(v, k);
            since = 0;
        }
    }
    if 0 < since {
        save(v, &bk);
        put_book(v, k);
    }
    crate::trace_line(&format!("home_keep end laid={laid} refused={refused} kept={}", bk.len()));
    word(v, k)
}

/// A FILE LEAVES THIS COMPUTER ONLY ON THE NODE'S WORD ASKED NOW (iOS removeHeld): the files the book names at their size, not in
/// hand, whose every piece the node has just named; `only` names them, None takes every file. No letter is touched.
pub fn remove_held(v: &Vault, k: &Keys, b: &crate::book::Book, store: &Store, only: Option<&HashSet<String>>) -> Option<(usize, u64)> {
    let bk = book(v);
    let candidates: Vec<(File, Entry)> = files(b, store).into_iter()
        .filter(|f| only.is_none_or(|o| o.contains(&f.name)))
        .filter_map(|f| bk.get(&f.name).filter(|e| e.z == f.size).cloned().map(|e| (f, e))).collect();
    let held = have(v, k, &candidates.iter().flat_map(|(_, e)| e.p.clone()).collect::<Vec<_>>())?;
    let (mut gone, mut bytes) = (0, 0u64);
    for (f, e) in candidates.iter().filter(|(_, e)| e.p.iter().all(|x| held.contains(x))) {
        let Some(_hand) = media::in_hand(&f.mid) else { continue }; // a file going up or coming down stays
        store.delete(&f.mid);
        gone += 1;
        bytes += e.z;
    }
    crate::trace_line(&format!("home_clear files={gone} bytes={bytes} of={} kept={} chosen={}", candidates.len(), bk.len(), only.map_or(-1, |o| o.len() as i64)));
    Some((gone, bytes))
}

/// THE CACHE KEEPS ITSELF (iOS trimPass, the reference's «keep media» and «maximum cache size»): a file the node holds and nobody
/// opened within the person's term leaves this computer, and past the ceiling the files opened longest ago leave first -- each
/// only on the node's word asked now.
pub fn trim_pass(v: &Vault, k: &Keys, b: &crate::book::Book, store: &Store, days: u64, limit_gb: u64) -> Option<(usize, u64)> {
    if days + limit_gb == 0 {
        return Some((0, 0));
    }
    let bk = book(v);
    let now = std::time::SystemTime::now();
    let mut fs: Vec<(File, std::time::SystemTime, bool)> = files(b, store).into_iter().map(|f| {
        let at = store.touched(&f.mid).unwrap_or(now);
        let kept = bk.get(&f.name).is_some_and(|e| e.z == f.size);
        (f, at, kept)
    }).collect();
    let edge = now - std::time::Duration::from_secs(days * 86_400);
    let mut going: HashSet<String> = fs.iter().filter(|(_, at, kept)| *kept && 0 < days && *at < edge).map(|(f, _, _)| f.name.clone()).collect();
    if 0 < limit_gb {
        let mut total: u64 = fs.iter().filter(|(f, _, _)| !going.contains(&f.name)).map(|(f, _, _)| f.size).sum();
        let ceiling = limit_gb * (1 << 30);
        fs.sort_by_key(|(_, at, _)| *at);
        for (f, _, kept) in &fs {
            if total <= ceiling {
                break;
            }
            if *kept && going.insert(f.name.clone()) {
                total -= f.size;
            }
        }
    }
    if going.is_empty() {
        return Some((0, 0));
    }
    let r = remove_held(v, k, b, store, Some(&going));
    crate::trace_line(&format!("home_trim files={} days={days} limit_gb={limit_gb}", r.map_or(-1, |x| x.0 as i64)));
    r
}

/// A FILE BACK FROM THE NODE INTO THE STORE (iOS bring): every piece fetched, its name checked against the seal, opened under the
/// file's key and cut to its size; a big one kept a piece at a time.
pub fn bring(v: &Vault, k: &Keys, store: &Store, mid: &str, name: &str) -> bool {
    let Some(e) = book(v).get(name).cloned() else { return false };
    let Some(_hand) = media::in_hand(mid) else { return false };
    let key = file_key(&k.book, name);
    let big = e.z as usize > media::MAX_SEND;
    let mut whole = Vec::with_capacity(if big { 0 } else { e.z as usize });
    for (i, bid) in e.p.iter().enumerate() {
        let Some(sealed) = get(v, k, bid) else {
            crate::trace_line(&format!("home_bring FAIL name={} -- your node did not give every piece", &name[..name.len().min(20)]));
            return false;
        };
        let cs = (e.z - (i * CHUNK) as u64).min(CHUNK as u64) as usize;
        let ok = crate::crypto::blob_id(&sealed).map(|b| hex(&b)).as_deref() == Some(bid.as_str());
        let Some(mut piece) = crate::crypto::open(&key, &sealed).filter(|_| ok) else {
            crate::trace_line(&format!("home_bring FAIL name={} -- the pieces did not open", &name[..name.len().min(20)]));
            return false;
        };
        piece.truncate(cs);
        if big {
            if !store.put_piece(mid, i, &piece) {
                return false;
            }
        } else {
            whole.extend_from_slice(&piece);
        }
    }
    let kept = if big { store.close_big(mid, e.z) } else { store.put(mid, &whole) };
    crate::trace_line(&format!("home_bring name={} bytes={} kept={}", &name[..name.len().min(20)], e.z, kept as u8));
    kept
}
/// A file the book names and this computer no longer holds comes from the node, by its letter (iOS MTHomeKeep.want / bring).
pub fn bring_letter(v: &Vault, store: &Store, mid: &str, text: &str) -> bool {
    let Some(k) = armed() else { return false };
    let name = crate::history::file_name(mid, text);
    !homenode::host(v).is_empty() && book(v).contains_key(&name) && bring(v, &k, store, mid, &name)
}
pub fn armed_keys() -> Option<Keys> {
    armed()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_book_and_the_files_keys_hold_ios_frozen_vectors() {
        let counting: Vec<u8> = (0..32).collect();
        let k = book_key(&counting);
        assert_eq!(hex(&k), "9bece1c15302a5154b382514015c9d888be32876f01e00963cecdaf7156bb992");
        assert_eq!(book_name(&k), "5d536d3dc037f357cc0430d317072ac117cc72efaafcae76d4a9e923edbe28a1");
        assert_eq!(hex(&file_key(&k, "img_a1.jpg")), "0362e58cd7c26c3fd0735391a2b64c012744647e42bacbe6745d1373d6775901");
    }

    /// A FILE GOES TO ONE'S OWN NODE IN PIECES AND COMES BACK (live: iOS's own door in WSL, tools\homenode-door.ps1, its digest in
    /// MONTANA_HOME_PIN; throwaway words): a letter's file of three pieces is laid and named in the book; the cache cleared, it
    /// leaves this computer on the node's word alone; it comes back byte for byte; a new device of the same words takes the book
    /// from the node and brings the file too.
    #[test]
    #[ignore]
    fn a_file_goes_to_ones_own_node_in_pieces_leaves_this_computer_and_comes_back() {
        let Ok(pin) = std::env::var("MONTANA_HOME_PIN") else { return };
        let dir = std::env::temp_dir().join(format!("mt-shelf-{}", crate::board::fresh_id()));
        let device = |n: &str| {
            let v = Vault::at(&dir.join(format!("{n}-v"))).unwrap();
            homenode::set_host(&v, "127.0.0.1");
            homenode::set_pin(&v, &pin);
            (v.clone(), Store::at(&dir.join(format!("{n}-m"))).unwrap(), crate::book::Book::new(Vault::at(&dir.join(format!("{n}-b"))).unwrap()))
        };
        let (v, store, b) = device("a");
        let k = keys(&crate::crypto::random(32).unwrap());
        let seed = crate::crypto::random(32).unwrap();
        let bytes: Vec<u8> = (0..(CHUNK * 2 + 4321)).map(|i| seed[i % 32] ^ (i >> 7) as u8).collect();
        let (mid, text) = ("t1792730000000-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE".to_string(), format!("{}{}", media::MARK, json!({ "k": "img", "e": "jpg", "sz": bytes.len() })));
        b.edit("r1", |c| c.msgs.push(crate::book::Msg { mid: mid.clone(), text: text.clone(), ..Default::default() }));
        assert!(store.put(&mid, &bytes));
        let name = crate::history::file_name(&mid, &text);
        assert_eq!(keep_pass(&v, &k, &b, &store, &|_| {}), Some((1, bytes.len() as u64)), "the node holds the file whole");
        assert_eq!(book(&v).get(&name).map(|e| e.p.len()), Some(3), "three pieces named in the book");
        assert_eq!(keep_pass(&v, &k, &b, &store, &|_| {}), Some((1, bytes.len() as u64)), "a second pass lays nothing new");
        assert_eq!(remove_held(&v, &k, &b, &store, None), Some((1, bytes.len() as u64)));
        assert!(!store.has(&mid), "cleared from this computer on the node's word");
        assert!(bring(&v, &k, &store, &mid, &name));
        assert_eq!(store.get(&mid).as_deref(), Some(bytes.as_slice()), "back byte for byte");
        // a new device of the same words: the book from the node, then the file
        let (v2, store2, _) = device("b");
        assert_eq!(take_book(&v2, &k), 1);
        assert!(bring(&v2, &k, &store2, &mid, &name));
        assert_eq!(store2.get(&mid).as_deref(), Some(bytes.as_slice()));
        let _ = std::fs::remove_dir_all(dir);
    }
}
