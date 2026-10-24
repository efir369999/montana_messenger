//! THE BOOK RIDES THE SEED (iOS MTCoinVault, MTWalletCore.swift; the author's words 04.10.2026 13:36-13:42 MSK: «I must log in by my
//! seed on another device and my balance must surely be kept»). Every move of the coin book is sealed under a key only the words
//! derive (HKDF «mt-coins-vault-key-v1», ChaCha20-Poly1305 bound to «mt.coins.vault») over the moves' JSON packed by LZFSE, and laid
//! on every node in pieces, under two rows a node: its own (HMAC of the node's host under the owner key) and the common one. Any
//! device of the same words gathers the union -- a move is its name, so the union is the book. A node answers with the names of
//! the pieces it keeps and the pieces this device lacks; it is sent the moves its pieces lack, never more; past `FOLD` pieces on a
//! row the whole book is laid there anew and the old pieces go in the same breath (the last part carries the replace).

use crate::coins::{self, Entry};
use crate::vault::Vault;
use crate::wire::{b64, hex, sha, unb64};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

const AAD: &[u8] = b"mt.coins.vault";
/// How many pieces a row keeps before the whole book is laid there as one; a piece carries `SPAN` moves at most (iOS fold, span).
const FOLD: usize = 192;
const SPAN: usize = 8000;

/// What this run knows of the rows: a piece's name -> the names of the moves it carries (opened once); a row -> the pieces it keeps;
/// the rows that refused a piece as full (laid whole next); whether a node answered this seed's book.
#[derive(Default)]
struct State {
    pieces: HashMap<String, HashSet<String>>,
    held: HashMap<String, Vec<String>>,
    full: HashSet<String>,
    heard: bool,
}
static STATE: Mutex<Option<State>> = Mutex::new(None);

/// The moves sealed as a piece (iOS MTCoinVault.seal): JSON, LZFSE, ChaCha20-Poly1305 -- the nonce, the text, the tag.
pub fn seal(moves: &[Entry], key: &[u8; 32]) -> Option<Vec<u8>> {
    let plain = serde_json::to_vec(moves).ok()?;
    let mut packed = Vec::with_capacity(plain.len() / 3 + 64);
    lzfse_rust::encode_bytes(&plain, &mut packed).ok()?;
    let nonce = crate::crypto::random(12)?;
    let ct = ChaCha20Poly1305::new(key.into()).encrypt(Nonce::from_slice(&nonce), Payload { msg: &packed, aad: AAD }).ok()?;
    Some([nonce, ct].concat())
}
/// A piece opened (iOS MTCoinVault.open); None -- not ours, broken, or not moves.
pub fn open(sealed: &[u8], key: &[u8; 32]) -> Option<Vec<Entry>> {
    if sealed.len() < 28 {
        return None;
    }
    let packed = ChaCha20Poly1305::new(key.into()).decrypt(Nonce::from_slice(&sealed[..12]), Payload { msg: &sealed[12..], aad: AAD }).ok()?;
    let mut plain = Vec::with_capacity(packed.len() * 4);
    lzfse_rust::decode_bytes(&packed, &mut plain).ok()?;
    serde_json::from_slice(&plain).ok()
}

/// A node's host from its door (https://host/pushwake): its own row is named by it.
fn host_of(door: &str) -> String {
    door.split("://").nth(1).unwrap_or(door).split('/').next().unwrap_or(door).to_string()
}
/// Every node's two rows (iOS rows): its own first, then the common one -- (the row's name here, the door, the token).
fn rows(doors: &[String], k: &coins::VaultKeys) -> Vec<(String, String, String)> {
    let common = hex(&k.token);
    doors.iter().flat_map(|d| [(format!("{d}#own"), d.clone(), hex(&k.node_token(&host_of(d)))), (d.clone(), d.clone(), common.clone())]).collect()
}

/// A node answered this seed's book since the launch (iOS heard): a letter mints only then -- the tally of letters paid lives on
/// this machine alone, so words opened anew would pay every letter again at today's level before the seed's book answered.
/// A seat's move starts the process anew (seats), so the run knows one person.
pub fn heard() -> bool {
    STATE.lock().unwrap().as_ref().is_some_and(|s| s.heard)
}
/// The run's memory of the rows let go (iOS forget; a check's second device in the same process).
#[cfg(test)]
pub fn forget() {
    *STATE.lock().unwrap() = None;
}

/// The next gathering asked and why (iOS dueAt): the nearest ask wins.
static DUE: Mutex<Option<(f64, String)>> = Mutex::new(None);
/// A GATHERING SOON (iOS MTCoinVault.soon): the moves of a minute -- the minting's own window -- ride one piece, never one each; a
/// move between people asks within a second, so it reaches the seed's other devices at once.
pub fn soon(why: &str, after_s: f64) {
    let at = crate::wire::now_ms() as f64 / 1000.0 + after_s;
    let mut d = DUE.lock().unwrap();
    if d.as_ref().is_some_and(|(t, _)| *t <= at) {
        return;
    }
    *d = Some((at, why.to_string()));
}
/// The gathering whose time came, taken (the coin walk asks every second while no gathering runs).
pub fn due() -> Option<String> {
    let mut d = DUE.lock().unwrap();
    if d.as_ref().is_some_and(|(t, _)| *t <= crate::wire::now_ms() as f64 / 1000.0) {
        return d.take().map(|(_, why)| why);
    }
    None
}

/// THE GATHER (iOS MTCoinVault.gather): every row asked for what it lacks here, the pieces it gives opened and joined into the book
/// by their names; then (when `write`) every answered row is laid the moves its pieces lack, or the whole book past the fold.
/// What it did: (rows answered, rows asked, moves gathered, moves joined, moves laid); the caller walks the letters that waited.
pub fn gather(vault: &Vault, entropy: &[u8; 32], why: &str, write: bool) -> (usize, usize, usize, usize, usize) {
    let k = coins::vault_keys(entropy);
    let doors: Vec<String> = crate::doors::all();
    if doors.is_empty() {
        return (0, 0, 0, 0, 0);
    }
    let all_rows = rows(&doors, &k);
    let mut answered: Vec<String> = vec![];
    let mut got: Vec<Entry> = vec![];
    for (slot, door, token) in &all_rows {
        let have: Vec<String> = {
            let g = STATE.lock().unwrap();
            g.as_ref().map(|s| s.held.get(slot).cloned().unwrap_or_default().into_iter().filter(|p| s.pieces.contains_key(p)).take(256).collect()).unwrap_or_default()
        };
        let (code, o) = crate::doors::post_machine(door, "/vault-get", &json!({ "token": token, "have": have }), 20_000);
        let Some(o) = o.filter(|_| code == 200) else { continue };
        let Some(ids) = o["held"].as_array().map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_string)).collect::<Vec<_>>()) else { continue };
        let mut g = STATE.lock().unwrap();
        let st = g.get_or_insert_with(State::default);
        for x in o["pieces"].as_array().cloned().unwrap_or_default() {
            let (Some(id), Some(b)) = (x["piece"].as_str(), x["blob"].as_str().and_then(unb64)) else { continue };
            if hex(&sha(&[&b])) != id {
                continue; // a piece is its own name
            }
            let Some(moves) = open(&b, &k.seal) else { continue };
            st.pieces.insert(id.to_string(), moves.iter().map(Entry::id).collect());
            got.extend(moves);
        }
        st.held.insert(slot.clone(), ids);
        answered.push(slot.clone());
    }
    if answered.is_empty() {
        crate::trace_line(&format!("coins_vault why={why} rows=0/{}", all_rows.len()));
        return (0, all_rows.len(), 0, 0, 0);
    }
    {
        let mut g = STATE.lock().unwrap();
        g.get_or_insert_with(State::default).heard = true;
    }
    let joined = coins::join(vault, &got);
    let book = coins::all_moves(vault);
    let (mut laid, mut whole) = (0, 0);
    if write {
        for slot in &answered {
            let Some((_, door, token)) = all_rows.iter().find(|(s, _, _)| s == slot) else { continue };
            let (ids, carried, anew) = {
                let g = STATE.lock().unwrap();
                let st = g.as_ref().unwrap();
                let ids = st.held.get(slot).cloned().unwrap_or_default();
                let mut carried = HashSet::new();
                for id in &ids {
                    if let Some(p) = st.pieces.get(id) {
                        carried.extend(p.iter().cloned());
                    }
                }
                let anew = FOLD <= ids.len() || st.full.contains(slot);
                (ids, carried, anew)
            };
            let lacking: Vec<Entry> = if anew { book.clone() } else { book.iter().filter(|e| !carried.contains(&e.id())).cloned().collect() };
            if lacking.is_empty() {
                continue;
            }
            // ONLY A PIECE READ HERE IS REPLACED (iOS, the coin audit's third point): a piece that would not open stays beside the whole
            let mut replace: Vec<String> = if anew {
                let names: HashSet<String> = book.iter().map(Entry::id).collect();
                let g = STATE.lock().unwrap();
                let st = g.as_ref().unwrap();
                ids.iter().filter(|id| st.pieces.get(*id).is_some_and(|m| m.is_subset(&names))).cloned().collect()
            } else {
                vec![]
            };
            for (i, part) in lacking.chunks(SPAN).enumerate() {
                let last = (i + 1) * SPAN >= lacking.len();
                let Some(sealed) = seal(part, &k.seal) else { break };
                let (code, o) = crate::doors::post_machine(door, "/vault-put", &json!({ "token": token, "blob": b64(&sealed), "replace": if last { replace.clone() } else { vec![] } }), 30_000);
                let mut g = STATE.lock().unwrap();
                let st = g.get_or_insert_with(State::default);
                if code == 413 {
                    st.full.insert(slot.clone());
                    break;
                }
                let Some(id) = o.as_ref().and_then(|o| o["piece"].as_str()).filter(|_| code == 200).map(str::to_string) else { break };
                st.pieces.insert(id.clone(), part.iter().map(Entry::id).collect());
                let gone: Vec<String> = if last { replace.clone() } else { vec![] };
                let mut now: Vec<String> = st.held.get(slot).cloned().unwrap_or_default().into_iter().filter(|p| !gone.contains(p)).collect();
                now.push(id);
                st.held.insert(slot.clone(), now);
                if last {
                    replace.clear();
                }
                laid += part.len();
                if anew {
                    whole += 1;
                }
            }
            if anew && whole > 0 {
                if let Some(st) = STATE.lock().unwrap().as_mut() {
                    st.full.remove(slot);
                }
            }
        }
        let mut g = STATE.lock().unwrap();
        if let Some(st) = g.as_mut() {
            let live: HashSet<String> = st.held.values().flatten().cloned().collect();
            st.pieces.retain(|k, _| live.contains(k)); // a piece no node keeps is forgotten here too
        }
    }
    crate::trace_line(&format!("coins_vault why={why} rows={}/{} got={} joined={joined} laid={laid} whole={whole} moves={}", answered.len(), all_rows.len(), got.len(), book.len()));
    (answered.len(), all_rows.len(), got.len(), joined, laid)
}

/// A PERSON ON THE SHELF IS CREDITED IN THEIR OWN BOOK (iOS MTCoinVault.lay, 07.10, MTShelfPost): the moves sealed under the key
/// only their words derive and laid on every node under both their rows, exactly as their own gather lays them; their gather, or
/// any device of their words, takes the union. The rows that took the piece.
pub fn lay(moves: &[Entry], entropy: &[u8; 32]) -> usize {
    if moves.is_empty() {
        return 0;
    }
    let k = coins::vault_keys(entropy);
    let doors = crate::doors::all();
    let Some(sealed) = seal(moves, &k.seal) else { return 0 };
    let blob = b64(&sealed);
    rows(&doors, &k).iter().filter(|(_, door, token)| {
        crate::doors::post_machine(door, "/vault-put", &json!({ "token": token, "blob": blob, "replace": Vec::<String>::new() }), 30_000).0 == 200
    }).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_piece_seals_the_moves_and_opens_them_as_ios_lays_them() {
        // the frozen vectors of the keys (iOS MTCoinVault.keyKAT): the counting bytes 0x00..0x1f
        let e: Vec<u8> = (0..32u8).collect();
        let k = coins::vault_keys(&e);
        assert_eq!(hex(&k.seal), "e9720340e7dcb4b6c2befea9a657718560646f727614f732971bf9ea7d3795fb");
        assert_eq!(hex(&k.token), "4b7fc64e903945bee08b4fc45f7ca094d9b61ae2c96f4d97ebd1ccd8b4b9ab86");
        assert_eq!(hex(&sha(&[&k.token])), "9e34605e5200c5f339f4a527f0654af5436a96b629f66835f91495b65e0ba245");
        let moves = vec![
            Entry { k: "earn".into(), c: 1, refr: "t1791303000000-0F6C1D5E-3A2B-4C1D-9E8F-112233445566".into(), peer: Some("K".into()), on: None, at: 1791303000.5 },
            Entry { k: "send".into(), c: 10, refr: "tx:ab".into(), peer: Some("K".into()), on: Some("post:P".into()), at: 1791303001.0 },
        ];
        let sealed = seal(&moves, &k.seal).unwrap();
        assert_eq!(open(&sealed, &k.seal).unwrap(), moves);
        let mut other = k.seal;
        other[0] ^= 1;
        assert!(open(&sealed, &other).is_none(), "another seed's key opens nothing");
        // what iOS writes: the moves' JSON (Swift JSONEncoder: k, c, ref, peer, on, at -- the nils left out) packed by LZFSE
        let ios = br#"[{"k":"receive","c":5,"ref":"mid:t1-AA","peer":"P","at":1.5},{"k":"burn","c":2,"ref":"cmt-burn:R","at":2}]"#;
        let mut packed = vec![];
        lzfse_rust::encode_bytes(ios, &mut packed).unwrap();
        let nonce = [7u8; 12];
        let ct = ChaCha20Poly1305::new((&k.seal).into()).encrypt(Nonce::from_slice(&nonce), Payload { msg: &packed, aad: AAD }).unwrap();
        let back = open(&[nonce.to_vec(), ct].concat(), &k.seal).unwrap();
        assert_eq!((back[0].k.as_str(), back[0].c, back[0].peer.as_deref(), back[1].on.as_deref()), ("receive", 5, Some("P"), None));
        assert_eq!(host_of("https://montana.xxx/pushwake"), "montana.xxx");
        let r = rows(&["https://a.b/pushwake".into()], &k);
        assert_eq!((r[0].0.as_str(), r[1].0.as_str(), r[1].2.as_str()), ("https://a.b/pushwake#own", "https://a.b/pushwake", hex(&k.token).as_str()));
        assert_ne!(r[0].2, r[1].2, "a node's own row is not the common one");
    }

    #[test]
    fn a_gathering_asked_twice_keeps_the_nearest() {
        soon("moves", 60.0);
        soon("move", 0.0);
        soon("moves", 60.0);
        assert_eq!(due().as_deref(), Some("move"));
        assert_eq!(due(), None, "taken once");
    }

    /// THE BOOK COMES BACK BY THE WORDS (live, MONTANA_LIVE=1; a throwaway seed, never a person's): the moves one device laid on the
    /// nodes are gathered whole by another device of the same words that never held them -- the same balance; a second gather of the
    /// first device lays nothing, and other words open none of them.
    #[test]
    #[ignore]
    fn a_device_of_the_same_words_gathers_the_book_another_laid() {
        if std::env::var("MONTANA_LIVE").is_err() {
            return;
        }
        let fresh_vault = || {
            let dir = std::env::temp_dir().join(format!("mt-vault-{}", crate::board::fresh_id()));
            (Vault::at(&dir).unwrap(), dir)
        };
        let e: [u8; 32] = crate::crypto::random(32).unwrap().try_into().unwrap();
        let (va, da) = fresh_vault();
        coins::test_second(Some(crate::cointx::TIME_CUT - 1000)); // the book mints only before the time cut
        assert_eq!(coins::in_window(&va, 300, coins::TAP, 300, false), 300);
        coins::test_second(None);
        coins::close_windows(&va, true);
        assert!(coins::moved(&va, "send", 10, &format!("tx:{}", crate::board::fresh_id()), Some("K"), None));
        let book = coins::all_moves(&va);
        assert_eq!(book.len(), 2);
        forget();
        let (answered, asked, _, _, laid) = gather(&va, &e, "test-lay", true);
        assert!(answered > 0 && laid >= book.len(), "the rows answered {answered}/{asked} and took {laid} moves");
        let (_, _, _, _, again) = gather(&va, &e, "test-again", true);
        assert_eq!(again, 0, "every row carries the book: nothing laid twice");
        forget(); // the other device: another process, its own memory of the rows
        let (vb, db) = fresh_vault();
        let (answered, _, got, joined, laid) = gather(&vb, &e, "test-restore", false);
        assert!(answered > 0 && got >= book.len(), "the restore read the rows: {answered} answered, {got} moves");
        assert_eq!((joined, laid), (book.len(), 0));
        assert_eq!(coins::balance(&vb), coins::balance(&va), "the same words show the same coins");
        forget();
        let (vc, dc) = fresh_vault();
        let other: [u8; 32] = crate::crypto::random(32).unwrap().try_into().unwrap();
        assert_eq!(gather(&vc, &other, "test-other", false).3, 0, "other words open nothing of this book");
        forget();
        for d in [da, db, dc] {
            let _ = std::fs::remove_dir_all(d);
        }
    }
}
