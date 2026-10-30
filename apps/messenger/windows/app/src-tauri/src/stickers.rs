//! STICKERS (iOS MontanaStickerBook / MontanaStickerWire): my own set and the sets taken from others -- one book. A sticker of
//! my set leaves by the picture road (a picture letter whose manifest carries the card sticker's name, `montana-card`, which
//! every build draws without a bubble), and right behind it the letter's passport in a service word of its own, «SP:»: which set
//! it belongs to and which sticker it is. A build that does not know the word buries it unread. The person on the other side
//! meets the set by the passport and may ask the giver for it («ask»); only the owner of a set answers, in pages («pack»).

use crate::book::mint_mid;
use crate::media::Store;
use crate::post::Desk;
use crate::vault::Vault;
use crate::wire::{b64, hex, unb64};
use crate::crypto;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;

pub const MARK: &str = "\u{200B}\u{200B}SP:";
/// The card sticker's name: a picture letter carrying it is a sticker, drawn bare (iOS MontanaCardPlate.stickerName).
pub const CARD: &str = "montana-card";
const BOOK: &str = "stickerBook";
/// A person's own set, not a warehouse: the oldest leaves with its picture.
const CEILING: usize = 120;
/// Stickers in one page of a set.
const PAGE: usize = 6;

#[derive(Serialize, Deserialize, Clone, Default, Debug)]
pub struct Pack {
    pub id: String,
    pub title: String,
    pub owner: String,
    pub names: Vec<String>,
    pub expected: usize,
}

/// What a sticker letter says about itself (iOS Passport): its set, the sticker, the set's title and owner.
#[derive(Serialize, Deserialize, Clone, Default, Debug)]
pub struct Passport {
    pub pack: String,
    pub sticker: String,
    pub title: String,
    pub owner: String,
}

#[derive(Serialize, Deserialize, Default, Debug)]
struct Book {
    #[serde(default)]
    pack_id: String,
    #[serde(default)]
    mine: Vec<String>,
    #[serde(default)]
    packs: Vec<Pack>,
    #[serde(default)]
    passports: BTreeMap<String, Passport>,
    #[serde(default)]
    givers: BTreeMap<String, String>,
    /// a sticker's content name -> its name here (the book knows a sticker by its bytes without reading the disk)
    #[serde(default)]
    ids: BTreeMap<String, String>,
}

fn load(v: &Vault) -> Book {
    v.get(BOOK).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}
fn save(v: &Vault, b: &Book) {
    v.set(BOOK, serde_json::to_vec(b).unwrap_or_default().as_slice());
}

/// A letter's name without the «mid:» some builds wear on the wire (iOS bare).
pub fn bare(letter: &str) -> &str {
    letter.strip_prefix("mid:").unwrap_or(letter)
}

/// A sticker's own name inside a set: the content itself (iOS blobIdHex), so two machines holding the same picture hold the
/// same sticker.
pub fn sticker_id(bytes: &[u8]) -> String {
    crypto::blob_id(bytes).map(|b| hex(&b)).unwrap_or_default()
}

/// What the bytes are, for the name's suffix: an «ftyp» box is HEIC, else PNG (iOS MontanaStickerCut.suffix); a GIF is a GIF.
fn suffix(bytes: &[u8]) -> &'static str {
    if bytes.starts_with(b"GIF8") {
        "gif"
    } else if bytes.len() > 12 && &bytes[4..8] == b"ftyp" {
        "heic"
    } else if bytes.starts_with(b"\xFF\xD8") {
        "jpg"
    } else if bytes.len() > 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        "webp"
    } else {
        "png"
    }
}

fn mint_name(bytes: &[u8]) -> String {
    let r = crypto::random(8).unwrap_or_else(|| vec![0; 8]);
    format!("stk_{}.{}", hex(&r), suffix(bytes))
}

/// The name of this machine's set, minted once and never moved: sha of my address and sixteen bytes of my own randomness.
pub fn mine_id(v: &Vault, owner: &str) -> String {
    let mut b = load(v);
    if b.pack_id.is_empty() {
        let seed = [owner.as_bytes(), &crypto::random(16).unwrap_or_default()].concat();
        b.pack_id = sticker_id(&seed);
        save(v, &b);
    }
    b.pack_id
}

/// A STICKER USED IS A STICKER KEPT, AND KEPT ONCE: the same picture again moves to the front; a new one is filed under a name
/// born once. The name, or None when the store refused.
pub fn add(v: &Vault, store: &Store, bytes: &[u8]) -> Option<String> {
    if bytes.is_empty() || bytes.len() > 2 << 20 {
        return None;
    }
    let mut b = load(v);
    let id = sticker_id(bytes);
    if let Some(known) = b.ids.get(&id).cloned().filter(|k| b.mine.contains(k)) {
        b.mine.retain(|x| *x != known);
        b.mine.insert(0, known.clone());
        save(v, &b);
        return Some(known);
    }
    let name = mint_name(bytes);
    if !store.put(&name, bytes) {
        return None;
    }
    b.mine.insert(0, name.clone());
    b.ids.insert(id, name.clone());
    while b.mine.len() > CEILING {
        if let Some(last) = b.mine.pop() {
            b.ids.retain(|_, n| *n != last);
            store.delete(&last);
        }
    }
    save(v, &b);
    Some(name)
}

pub fn forget(v: &Vault, store: &Store, name: &str) {
    let mut b = load(v);
    if b.mine.iter().any(|x| x == name) {
        b.mine.retain(|x| x != name);
        b.ids.retain(|_, n| n != name);
        store.delete(name);
        save(v, &b);
    }
}

/// A set's word arrived: the set is known by name before a single sticker of it has landed.
fn meet(b: &mut Book, id: &str, title: &str, owner: &str, expected: usize) {
    match b.packs.iter_mut().find(|p| p.id == id) {
        Some(p) => {
            p.title = title.to_string();
            p.owner = owner.to_string();
            if expected > 0 {
                p.expected = expected;
            }
        }
        None => b.packs.insert(0, Pack { id: id.into(), title: title.into(), owner: owner.into(), names: vec![], expected }),
    }
}

/// A sticker of another person's set landed: filed under its own name, once.
fn land(b: &mut Book, store: &Store, pack: &str, sticker: &str, bytes: &[u8]) -> bool {
    let Some(i) = b.packs.iter().position(|p| p.id == pack) else { return false };
    if b.ids.get(sticker).is_some_and(|n| b.packs[i].names.contains(n)) {
        return false;
    }
    if bytes.is_empty() || bytes.len() > 2 << 20 || sticker_id(bytes) != sticker {
        return false; // a sticker is its content: one whose bytes are not its name is no sticker of the set
    }
    let name = mint_name(bytes);
    if !store.put(&name, bytes) {
        return false;
    }
    b.packs[i].names.push(name.clone());
    b.ids.insert(sticker.to_string(), name);
    true
}

/// THE BOOK AS THE PANEL DRAWS IT: my set (names), the sets of others (title, the stickers landed, how many are expected, and
/// whether there is somebody to ask).
pub fn state(v: &Vault, owner: &str) -> Value {
    let b = load(v);
    let mine = mine_id(v, owner);
    json!({
        "mine": b.mine,
        "packs": b.packs.iter().filter(|p| p.id != mine).map(|p| json!({
            "id": p.id, "title": p.title, "names": p.names, "expected": p.expected,
            "giver": b.givers.get(&p.id).cloned().unwrap_or_else(|| p.owner.clone()),
        })).collect::<Vec<_>>(),
    })
}

/// The passport of a sticker letter here, and whether its set is held (for the letter's own page).
pub fn passport(v: &Vault, letter: &str, owner: &str) -> Option<Value> {
    let b = load(v);
    let p = b.passports.get(bare(letter))?;
    let held = p.pack == mine_id(v, owner) || b.packs.iter().any(|x| x.id == p.pack && !x.names.is_empty());
    Some(json!({ "pack": p.pack, "title": p.title, "held": held }))
}

/// One service word of the set into a correspondence: durable, silent, never a row.
fn say(d: &Desk, chat: &str, o: &Value) {
    d.word_kept(chat, &mint_mid(), &format!("{MARK}{o}"));
}

/// A STICKER OF MY SET LEAVES BY THE PICTURE ROAD (iOS sendStickerFile + sendPassport): a picture letter named as the card
/// sticker, then its passport named by the SAME letter. The letter's mid.
pub fn send(d: &Desk, store: &Store, chat: &str, name: &str, qt: &str, qm: &str) -> Option<String> {
    let bytes = store.get(name)?;
    let manifest = json!({ "k": "img", "e": suffix(&bytes), "n": CARD });
    let mid = d.draft_media(chat, &bytes, manifest, qt, qm)?;
    d.post(chat, &mid);
    let mine = mine_id(d.vault, &d.twin);
    let b = load(d.vault);
    let sid = b.ids.iter().find(|(_, n)| *n == name).map(|(k, _)| k.clone()).unwrap_or_else(|| sticker_id(&bytes));
    let (pack, title, count) = match b.packs.iter().find(|p| p.names.iter().any(|n| n == name)) {
        Some(p) => (p.id.clone(), p.title.clone(), p.expected.max(p.names.len())),
        None => (mine, "Montana".to_string(), b.mine.len()),
    };
    if !crate::groups::is_group(chat) {
        // a group's key is no pipe: its sticker rides without a passport here
        let mut o = json!({ "t": "id", "m": bare(&mid), "p": pack, "s": sid, "n": title, "c": count, "o": d.twin });
        if !qt.is_empty() {
            o["rq"] = json!(qt);
            o["rm"] = json!(qm);
        }
        say(d, chat, &o);
    }
    if b.mine.iter().any(|n| n == name) {
        add(d.vault, store, &bytes); // the sticker used moves to the front
    }
    Some(mid)
}

/// «Send me that set» -- asked of the one who gave it, never of a stranger.
pub fn ask(d: &Desk, pack: &str) -> bool {
    let b = load(d.vault);
    // the conversation the set's passport came on: the one who handed it over is asked there
    let Some(chat) = b.givers.get(pack).cloned().filter(|c| d.book.secret(c).is_some()) else { return false };
    say(d, &chat, &json!({ "t": "ask", "p": pack }));
    true
}

/// THE SET ITSELF, IN PAGES: only a set this machine owns is answered -- what it holds of someone else's is their word to give.
fn answer(d: &Desk, store: &Store, chat: &str, pack: &str) {
    if pack != mine_id(d.vault, &d.twin) {
        return;
    }
    let b = load(d.vault);
    let pages: Vec<&[String]> = if b.mine.is_empty() { vec![&[]] } else { b.mine.chunks(PAGE).collect() };
    for (i, names) in pages.iter().enumerate() {
        let pages = pages.len();
        let items: Vec<Value> = names.iter().filter_map(|n| {
            let bytes = store.get(n)?;
            let sid = b.ids.iter().find(|(_, x)| *x == n).map(|(k, _)| k.clone()).unwrap_or_else(|| sticker_id(&bytes));
            Some(json!({ "s": sid, "d": b64(&bytes) }))
        }).collect();
        say(d, chat, &json!({ "t": "pack", "p": pack, "n": "Montana", "o": d.twin, "i": i, "of": pages, "c": b.mine.len(), "items": items }));
    }
}

/// A WORD OF THE SET ARRIVED (iOS MontanaStickerWire.handle): a passport is noted and its set met; an ask of my set is answered;
/// a page of a set lands its stickers. True when the set's book moved.
pub fn heard(d: &Desk, store: &Store, chat: &str, text: &str) -> bool {
    let Some(o) = text.strip_prefix(MARK).and_then(|j| serde_json::from_str::<Map<String, Value>>(j).ok()) else { return false };
    let s = |k: &str| o.get(k).and_then(|v| v.as_str()).unwrap_or("").to_string();
    let n = |k: &str| o.get(k).and_then(|v| v.as_u64()).unwrap_or(0) as usize;
    match s("t").as_str() {
        "id" => {
            let (letter, pack) = (s("m"), s("p"));
            if letter.is_empty() || pack.is_empty() || pack.len() > 128 {
                return false;
            }
            let title = Some(s("n")).filter(|t| !t.is_empty()).unwrap_or_else(|| "Montana".into());
            let owner = Some(s("o")).filter(|t| !t.is_empty()).unwrap_or_else(|| chat.to_string());
            let mut b = load(d.vault);
            b.passports.insert(bare(&letter).to_string(), Passport { pack: pack.clone(), sticker: s("s"), title: title.clone(), owner: owner.clone() });
            while b.passports.len() > 2000 {
                let k = b.passports.keys().next().cloned().unwrap_or_default();
                b.passports.remove(&k);
            }
            if pack != b.pack_id {
                meet(&mut b, &pack, &title, &owner, n("c")); // known or not: the passport says how many the set holds now
            }
            b.givers.insert(pack, chat.to_string()); // the one who handed it over is asked, by the conversation it came on
            save(d.vault, &b);
            true
        }
        "ask" => {
            answer(d, store, chat, &s("p"));
            false
        }
        "pack" => {
            let pack = s("p");
            if pack.is_empty() {
                return false;
            }
            let mut b = load(d.vault);
            let title = Some(s("n")).filter(|t| !t.is_empty()).unwrap_or_else(|| "Montana".into());
            meet(&mut b, &pack, &title, &Some(s("o")).filter(|t| !t.is_empty()).unwrap_or_else(|| chat.to_string()), n("c"));
            let mut landed = 0;
            for item in o.get("items").and_then(|v| v.as_array()).cloned().unwrap_or_default() {
                let (Some(sid), Some(bytes)) = (item["s"].as_str(), item["d"].as_str().and_then(unb64)) else { continue };
                if land(&mut b, store, &pack, sid, &bytes) {
                    landed += 1;
                }
            }
            save(d.vault, &b);
            landed > 0
        }
        _ => false, // a shape from a newer build: buried in silence
    }
}

/// The picture of a sticker of the book, by its name here.
#[cfg(test)]
pub fn picture(store: &Store, name: &str) -> Option<Vec<u8>> {
    if !name.starts_with("stk_") || name.len() > 64 {
        return None;
    }
    store.get(name)
}

/// The kind of a sticker's picture, for the window's address of it.
#[cfg(test)]
pub fn kind_of(name: &str) -> &'static str {
    match name.rsplit('.').next() {
        Some("gif") => "image/gif",
        Some("jpg") => "image/jpeg",
        Some("webp") => "image/webp",
        Some("heic") => "image/heic",
        _ => "image/png",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn place(name: &str) -> (Vault, Store, std::path::PathBuf) {
        let d = std::env::temp_dir().join(format!("montana-stickers-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        (Vault::at(&d.join("v")).unwrap(), Store::at(&d.join("s")).unwrap(), d)
    }

    #[test]
    fn a_sticker_used_again_is_kept_once_and_moves_to_the_front() {
        let (v, s, d) = place("book");
        let png = |n: u8| [b"\x89PNG\r\n\x1a\n".as_slice(), &[n; 40]].concat();
        let a = add(&v, &s, &png(1)).unwrap();
        let b2 = add(&v, &s, &png(2)).unwrap();
        assert!(a.starts_with("stk_") && a.ends_with(".png"));
        assert_eq!(load(&v).mine, vec![b2.clone(), a.clone()]);
        assert_eq!(add(&v, &s, &png(1)).as_deref(), Some(a.as_str()), "the same picture is the same sticker");
        assert_eq!(load(&v).mine, vec![a.clone(), b2.clone()], "used again, it stands first");
        assert_eq!(picture(&s, &a).unwrap(), png(1));
        forget(&v, &s, &a);
        assert_eq!(load(&v).mine, vec![b2]);
        assert!(picture(&s, &a).is_none());
        let id = mine_id(&v, "me");
        assert_eq!(id.len(), 64);
        assert_eq!(mine_id(&v, "me"), id, "the set's name is born once");
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn a_set_lands_only_stickers_whose_bytes_are_their_names() {
        let (v, s, d) = place("land");
        let mut b = load(&v);
        meet(&mut b, "p1", "Montana", "owner", 2);
        let good = b"\x89PNG\r\n\x1a\nGOOD".to_vec();
        assert!(land(&mut b, &s, "p1", &sticker_id(&good), &good));
        assert!(!land(&mut b, &s, "p1", &sticker_id(&good), &good), "once");
        assert!(!land(&mut b, &s, "p1", "ff".repeat(32).as_str(), b"\x89PNG\r\n\x1a\nBAD"), "a picture that is not its name");
        assert!(!land(&mut b, &s, "p2", &sticker_id(&good), &good), "a set never met");
        assert_eq!(b.packs[0].names.len(), 1);
        assert_eq!(bare("mid:t1-A"), "t1-A");
        assert_eq!(suffix(b"GIF89a.."), "gif");
        assert_eq!(kind_of("stk_ab.heic"), "image/heic");
        let _ = std::fs::remove_dir_all(d);
    }
}
