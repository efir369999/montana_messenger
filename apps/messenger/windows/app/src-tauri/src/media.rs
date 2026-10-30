//! THE PICTURES, FILMS, VOICES AND FILES (iOS MontanaMediaKit 139-272, ChatStore media; Android Media.kt): a file cut into
//! pieces of 512 KiB, each padded by the core (mt_e2e_pad_len) and sealed under the letter's key with a nonce derived from
//! the key, the piece's number and its bytes -- so a resend names the same pieces -- and laid on the node under the core's
//! name of the seal. The manifest (kind, extension, key, size, pieces, caption, thumbnail) rides the letter (MD:), or, when
//! it outgrows 1900 bytes, is itself a sealed blob the letter names ({mref, mk, sz}). A file kept here is sealed by DPAPI;
//! a file larger than 200 MB is kept as its pieces, each sealed by DPAPI, and is never held whole (iOS MediaSource.file).

use crate::crypto;
use crate::doors;
use crate::http;
use crate::vault::Vault;
use crate::wire::{b64, hex, le8, unb64};
use serde_json::{json, Value};
use std::borrow::Cow;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

pub const CHUNK: usize = 512 * 1024;
pub const MARK: &str = "\u{200B}\u{200B}MD:";
/// The largest file kept and carried whole (one value of the vault, in memory while it is sealed); a larger one is kept as its
/// pieces and goes one piece at a time (iOS MediaSource.file: the peak is a piece, not the file).
pub const MAX_SEND: usize = 200 * 1024 * 1024;
/// The pieces a file kept whole may have; a manifest of more is received piece by piece.
const WHOLE_PIECES: usize = MAX_SEND / CHUNK;

/// The files of letters, sealed on this machine (the app's local folder `media`).
#[derive(Clone)]
pub struct Store {
    vault: Vault,
}

fn name_of(mid: &str) -> String {
    hex(&crate::wire::sha(&[b"mt-media-file\0", mid.as_bytes()])[..16])
}
/// The name a file is kept under on disk (a letter's, a wall's), for a measure of the store.
pub fn key_of(mid: &str) -> String {
    name_of(mid)
}

impl Store {
    pub fn at(dir: &std::path::Path) -> std::io::Result<Store> {
        Ok(Store { vault: Vault::at(dir)? })
    }
    pub fn put(&self, mid: &str, bytes: &[u8]) -> bool {
        self.vault.set(&name_of(mid), bytes)
    }
    pub fn get(&self, mid: &str) -> Option<Vec<u8>> {
        self.vault.get(&name_of(mid))
    }
    pub fn has(&self, mid: &str) -> bool {
        self.vault.has(&name_of(mid)) || self.big(mid).is_some()
    }
    /// The store's own folder.
    pub fn dir(&self) -> &Path {
        self.vault.dir()
    }
    pub fn delete(&self, mid: &str) {
        self.vault.delete(&name_of(mid));
        let _ = std::fs::remove_dir_all(self.parts_dir(mid));
    }

    // ── a big file, kept as its pieces (iOS MediaSource.file, downloadToFile) ──

    fn parts_dir(&self, mid: &str) -> PathBuf {
        self.vault.dir().join(format!("{}.parts", name_of(mid)))
    }
    fn parts(&self, mid: &str) -> Option<Vault> {
        Vault::at(&self.parts_dir(mid)).ok()
    }
    /// A big file's size, once every piece is kept: the mark «whole» is laid last.
    pub fn big(&self, mid: &str) -> Option<u64> {
        let dir = self.parts_dir(mid);
        if !dir.is_dir() {
            return None;
        }
        let w = Vault::at(&dir).ok()?.get("whole")?;
        Some(u64::from_le_bytes(w.get(..8)?.try_into().ok()?))
    }
    /// Piece `i` of a big file being kept: the bytes from i·512 KiB, a whole piece but the last.
    pub fn put_piece(&self, mid: &str, i: usize, bytes: &[u8]) -> bool {
        bytes.len() <= CHUNK && self.parts(mid).is_some_and(|v| v.set(&format!("p{i:07}"), bytes))
    }
    pub fn has_piece(&self, mid: &str, i: usize) -> bool {
        self.parts_dir(mid).join(format!("p{i:07}.sealed")).exists()
    }
    pub fn piece(&self, mid: &str, i: usize) -> Option<Vec<u8>> {
        self.parts(mid)?.get(&format!("p{i:07}"))
    }
    /// The pieces kept whole: every piece of that size is here, then the mark.
    pub fn close_big(&self, mid: &str, size: u64) -> bool {
        let count = size.div_ceil(CHUNK as u64) as usize;
        size > 0 && (0..count).all(|i| self.has_piece(mid, i)) && self.parts(mid).is_some_and(|v| v.set("whole", &size.to_le_bytes()))
    }
    /// A big file's pieces under another letter's name (a forward): the sealed files as they are -- DPAPI seals them for this
    /// person on this machine alone, whatever the name.
    pub fn copy_big(&self, from: &str, to: &str) -> bool {
        let (Some(size), Ok(entries)) = (self.big(from), std::fs::read_dir(self.parts_dir(from))) else { return false };
        let dir = self.parts_dir(to);
        if std::fs::create_dir_all(&dir).is_err() {
            return false;
        }
        for e in entries.flatten() {
            if e.file_name() != "whole.sealed" && std::fs::copy(e.path(), dir.join(e.file_name())).is_err() {
                return false;
            }
        }
        self.close_big(to, size)
    }
    /// A stretch of a file from `at`, at most `most` bytes, and the file's size (a player's ranges): a big file reads only the
    /// pieces the stretch crosses.
    pub fn stretch(&self, mid: &str, at: u64, most: usize) -> Option<(Vec<u8>, u64)> {
        let Some(size) = self.big(mid) else {
            let whole = self.get(mid)?;
            let from = (at as usize).min(whole.len());
            return Some((whole[from..(from + most).min(whole.len())].to_vec(), whole.len() as u64));
        };
        let end = (at + most as u64).min(size);
        let mut out = Vec::with_capacity(end.saturating_sub(at) as usize);
        let mut i = (at / CHUNK as u64) as usize;
        while (i as u64) * (CHUNK as u64) < end {
            let piece = self.piece(mid, i)?;
            let base = i as u64 * CHUNK as u64;
            let (from, to) = (at.max(base) - base, (end - base).min(piece.len() as u64));
            out.extend_from_slice(piece.get(from as usize..to as usize)?);
            i += 1;
        }
        Some((out, size))
    }
    /// A file written out to a path, a big one piece by piece.
    pub fn write_to(&self, mid: &str, path: &Path) -> bool {
        let Some(size) = self.big(mid) else { return self.get(mid).is_some_and(|b| std::fs::write(path, b).is_ok()) };
        let Ok(mut f) = std::fs::File::create(path) else { return false };
        let ok = (0..size.div_ceil(CHUNK as u64) as usize).all(|i| self.piece(mid, i).is_some_and(|p| f.write_all(&p).is_ok()));
        if !ok {
            drop(f);
            let _ = std::fs::remove_file(path);
        }
        ok
    }
    /// A FILE ON DISK TAKEN AS THIS LETTER'S FILE in place of what was kept (iOS MontanaMediaStore.adopt: the name given at birth
    /// never changes): whole when it fits, else as its pieces, laid aside first and put in place only once whole -- what was kept
    /// stays if anything fails. The size taken.
    pub fn take_file(&self, mid: &str, path: &Path) -> Option<u64> {
        let size = std::fs::metadata(path).ok()?.len();
        if size == 0 {
            return None;
        }
        if size as usize <= MAX_SEND {
            if !self.vault.set(&name_of(mid), &std::fs::read(path).ok()?) {
                return None;
            }
            let _ = std::fs::remove_dir_all(self.parts_dir(mid));
            return Some(size);
        }
        let aside = format!("{mid}~taken");
        let _ = std::fs::remove_dir_all(self.parts_dir(&aside));
        let mut f = std::fs::File::open(path).ok()?;
        let mut buf = vec![0u8; CHUNK];
        let mut i = 0;
        loop {
            let mut n = 0;
            while n < CHUNK {
                match f.read(&mut buf[n..]) {
                    Ok(0) => break,
                    Ok(k) => n += k,
                    Err(_) => return None,
                }
            }
            if n == 0 {
                break;
            }
            if !self.put_piece(&aside, i, &buf[..n]) {
                return None;
            }
            i += 1;
        }
        if !self.close_big(&aside, size) {
            return None;
        }
        let _ = std::fs::remove_dir_all(self.parts_dir(mid));
        std::fs::rename(self.parts_dir(&aside), self.parts_dir(mid)).ok()?;
        self.vault.delete(&name_of(mid));
        Some(size)
    }
    /// Whether a file on disk holds this file's very bytes, read side by side a piece at a time.
    pub fn same_as(&self, mid: &str, path: &Path) -> bool {
        let Some(size) = self.big(mid) else { return self.get(mid).is_some_and(|b| std::fs::read(path).ok().as_deref() == Some(b.as_slice())) };
        let Ok(mut f) = std::fs::File::open(path) else { return false };
        if f.metadata().map(|m| m.len()).ok() != Some(size) {
            return false;
        }
        let mut theirs = vec![0u8; CHUNK];
        (0..size.div_ceil(CHUNK as u64) as usize).all(|i| {
            self.piece(mid, i).is_some_and(|p| f.read_exact(&mut theirs[..p.len()]).is_ok() && theirs[..p.len()] == p[..])
        })
    }
    /// When a file was last looked at here (iOS contentAccessDate, else its modification): the sealed file, or a big file's mark.
    pub fn touched(&self, mid: &str) -> Option<std::time::SystemTime> {
        let whole = self.vault.dir().join(format!("{}.sealed", name_of(mid)));
        let path = if whole.exists() { whole } else { self.parts_dir(mid).join("whole.sealed") };
        let m = std::fs::metadata(path).ok()?;
        m.accessed().or_else(|_| m.modified()).ok()
    }

    /// Pieces of a file that never became whole -- a window closed while handing them, a download let go -- after a day.
    pub fn sweep(&self) {
        let day = std::time::Duration::from_secs(86_400);
        for e in std::fs::read_dir(self.vault.dir()).into_iter().flatten().flatten() {
            let p = e.path();
            let old = e.metadata().and_then(|m| m.modified()).ok().and_then(|t| t.elapsed().ok()).is_some_and(|a| a > day);
            if old && p.extension().is_some_and(|x| x == "parts") && !p.join("whole.sealed").exists() {
                let _ = std::fs::remove_dir_all(p);
            }
        }
    }
}

/// A file in hand: its pieces going up or coming down. A second walk for the same file -- the walk and a tap, two taps --
/// steps aside while the first one goes (a big file's going takes minutes, and two would lay each piece twice).
pub struct Hand(String);

static IN_HAND: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

pub fn in_hand(mid: &str) -> Option<Hand> {
    let mut h = IN_HAND.lock().unwrap();
    if h.iter().any(|x| x == mid) {
        return None;
    }
    h.push(mid.to_string());
    Some(Hand(mid.to_string()))
}

impl Drop for Hand {
    fn drop(&mut self) {
        IN_HAND.lock().unwrap().retain(|x| *x != self.0);
    }
}

// ── a file of mine on its way (iOS MTTransferBoard: one ring on the bubble for the whole road -- a film 0…30 % its writing, 30…100 %
// its pieces; anything else 0…100 % its pieces), and the word over it: «queue» while another film is written, «squeeze» once its
// own writing began, «squeeze N» -- N per cent of it ──

type Tell = Box<dyn Fn(&str, Option<(f64, String)>) + Send + Sync>;
static TELL: std::sync::OnceLock<Tell> = std::sync::OnceLock::new();
static BOARD: std::sync::Mutex<Vec<(String, f64, String)>> = std::sync::Mutex::new(Vec::new());
static STOPS: std::sync::Mutex<Vec<(String, std::sync::Arc<std::sync::atomic::AtomicBool>)>> = std::sync::Mutex::new(Vec::new());

/// Who hears the board (the window, through the run).
pub fn on_transfer(f: Tell) {
    let _ = TELL.set(f);
}
/// A file's share and word; None -- it is no longer on its way.
pub fn tell(mid: &str, now: Option<(f64, &str)>) {
    {
        let mut b = BOARD.lock().unwrap();
        b.retain(|x| x.0 != mid);
        if let Some((share, word)) = now {
            b.push((mid.to_string(), share, word.to_string()));
        }
    }
    if let Some(f) = TELL.get() {
        f(mid, now.map(|(s, w)| (s, w.to_string())));
    }
}
/// The files on their way now, for a window that opens in the middle.
pub fn board() -> Vec<(String, f64, String)> {
    BOARD.lock().unwrap().clone()
}
/// The flag that ends a file's way: the letter deleted while it rides (iOS: «stopping is an explicit act -- delete the bubble;
/// its transport dies with the row»).
pub fn stop_flag(mid: &str) -> std::sync::Arc<std::sync::atomic::AtomicBool> {
    let mut s = STOPS.lock().unwrap();
    if let Some(x) = s.iter().find(|x| x.0 == mid) {
        return x.1.clone();
    }
    let f = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    s.push((mid.to_string(), f.clone()));
    f
}
pub fn stop(mid: &str) {
    stop_flag(mid).store(true, std::sync::atomic::Ordering::SeqCst);
}
pub fn stopped(mid: &str) -> bool {
    STOPS.lock().unwrap().iter().any(|x| x.0 == mid && x.1.load(std::sync::atomic::Ordering::SeqCst))
}
/// The way over: the flag goes, unless the letter was deleted (its flag keeps any later walk from taking it).
pub fn let_go(mid: &str) {
    STOPS.lock().unwrap().retain(|x| x.0 != mid || x.1.load(std::sync::atomic::Ordering::SeqCst));
}

/// Where a file's pieces come from: the bytes in hand, or a big file's pieces in the store.
pub enum Source<'a> {
    Bytes(&'a [u8]),
    Parts(&'a Store, &'a str, u64),
}

impl Source<'_> {
    pub fn len(&self) -> u64 {
        match self {
            Source::Bytes(b) => b.len() as u64,
            Source::Parts(_, _, size) => *size,
        }
    }
    pub fn count(&self) -> usize {
        self.len().div_ceil(CHUNK as u64) as usize
    }
    pub fn piece(&self, i: usize) -> Option<Cow<'_, [u8]>> {
        match self {
            Source::Bytes(b) => b.chunks(CHUNK).nth(i).map(Cow::Borrowed),
            Source::Parts(store, mid, _) => store.piece(mid, i).map(Cow::Owned),
        }
    }
}

fn id_hex(sealed: &[u8]) -> Option<String> {
    crypto::blob_id(sealed).map(|b| hex(&b))
}

/// THE LETTER'S KEY (iOS letterBlobKey): from the letter's name and this device's own seed, so a second attempt names the
/// same pieces, and one file in two letters gives two unrelated sets.
pub fn letter_key(vault: &Vault, mid: &str) -> Option<[u8; 32]> {
    let seed = match vault.get("blobKeySeed").filter(|s| s.len() == 32) {
        Some(s) => s,
        None => {
            let fresh = crypto::random(32)?;
            if !vault.set("blobKeySeed", &fresh) {
                return None;
            }
            fresh
        }
    };
    crypto::blob_id(&[b"mt-blob-key".as_slice(), mid.as_bytes(), &seed].concat())
}

/// One piece sealed (iOS sealOne): padded by the core, the nonce SHA of key ‖ LE64(index) ‖ padded bytes, cut to twelve.
pub fn seal_piece(piece: &[u8], key: &[u8; 32], index: usize) -> Option<(Vec<u8>, String)> {
    let mut padded = piece.to_vec();
    let target = crypto::pad_len(piece.len());
    if target > padded.len() {
        padded.resize(target, 0);
    }
    let nonce = crypto::blob_id(&[key.as_slice(), &le8(index as i64), &padded].concat())?;
    let sealed = crypto::seal_with(key, &nonce[..12], &padded)?;
    let bid = id_hex(&sealed)?;
    Some((sealed, bid))
}

type SealedName = (Option<Vec<u8>>, String, usize);

/// Every piece sealed, for its name and size: a file in hand keeps its seals for the laying; a big one lets each go, and
/// the laying seals it again -- the nonce is derived, so the seal is the same.
fn sealed_names(src: &Source, key: &[u8; 32]) -> Option<Vec<SealedName>> {
    let keep = matches!(src, Source::Bytes(_));
    (0..src.count()).map(|i| {
        let piece = src.piece(i)?;
        let (sealed, bid) = seal_piece(&piece, key, i)?;
        Some((keep.then_some(sealed), bid, piece.len()))
    }).collect()
}

/// The pieces onto the node (iOS sealAndUpload + the store's put): each under its name with the cargo's tag -- the first 32
/// hex of the SHA of all the names -- the last one marked; pieces the node already holds are not laid twice. The manifest's
/// list of pieces, or None when a piece did not go. A big file is read a piece at a time, twice: once for the names, once
/// for the laying.
pub fn upload(bytes: &[u8], key: &[u8; 32]) -> Option<Vec<Value>> {
    upload_from(&Source::Bytes(bytes), key)
}

pub fn upload_from(src: &Source, key: &[u8; 32]) -> Option<Vec<Value>> {
    upload_told(src, key, None)
}

/// The same for a letter's file: its share told on the board from `base` to the whole a piece at a time, and its way ended when
/// the letter is deleted.
pub fn upload_told(src: &Source, key: &[u8; 32], told: Option<(&str, f64)>) -> Option<Vec<Value>> {
    let pieces = sealed_names(src, key)?;
    if pieces.is_empty() {
        return None;
    }
    let names: String = pieces.iter().map(|p| p.1.as_str()).collect();
    let cargo = hex(&crate::wire::sha(&[names.as_bytes()]))[..32].to_string();
    let held: Vec<String> = if pieces.len() >= 3 {
        let ask = json!({ "bids": pieces.iter().map(|p| p.1.clone()).collect::<Vec<_>>() });
        doors::write_order().iter().find_map(|d| {
            let (code, v) = doors::post_at(d, "/blob-have", &ask, http::POST_DEADLINE_MS);
            (code == 200).then(|| v.and_then(|v| v["have"].as_array().cloned()).unwrap_or_default())
        })
        .unwrap_or_default().iter().filter_map(|x| x.as_str().map(str::to_string)).collect()
    } else {
        vec![]
    };
    let last = pieces.len() - 1;
    let said = |i: usize| {
        if let Some((mid, base)) = told {
            tell(mid, Some((base + (1.0 - base) * (i + 1) as f64 / pieces.len() as f64, "")));
        }
    };
    for (i, (kept, bid, _)) in pieces.iter().enumerate() {
        if told.is_some_and(|(mid, _)| stopped(mid)) {
            return None;
        }
        if held.contains(bid) {
            said(i);
            continue;
        }
        let sealed = match kept {
            Some(s) => Cow::Borrowed(s.as_slice()),
            None => Cow::Owned(seal_piece(&src.piece(i)?, key, i).filter(|(_, b)| b == bid)?.0),
        };
        let mut body = json!({ "bid": bid, "data": b64(&sealed), "cg": cargo });
        if i == last {
            body["last"] = json!(true);
        }
        let mut ok = false;
        for attempt in 0..4 {
            if doors::write_mirrored("/blob-put", &body, http::cargo_timeout_ms(sealed.len())) {
                ok = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(1500 << attempt));
        }
        if !ok {
            return None;
        }
        said(i);
    }
    Some(pieces.iter().map(|(_, bid, cs)| json!({ "bid": bid, "cs": cs })).collect())
}

/// Whether a manifest's file is received piece by piece into the store (more pieces than a file kept whole may have).
pub fn is_big(m: &Value) -> bool {
    m["chunks"].as_array().is_some_and(|p| p.len() > WHOLE_PIECES)
}

/// THE MANIFEST AS A LETTER (iOS manifestLetter): inside the letter when MD:+json fits 1900 bytes; else sealed under a fresh
/// key as a blob, and the letter names it -- {"mref","mk","sz"} written in that order, as iOS writes it.
pub fn manifest_letter(manifest: &Value) -> Option<String> {
    let body = manifest.to_string();
    let plain = format!("{MARK}{body}");
    if plain.len() <= 1900 {
        return Some(plain);
    }
    let mk = crypto::random(32)?;
    let sealed = crypto::seal(&mk, body.as_bytes())?;
    let mbid = id_hex(&sealed)?;
    if !doors::put_new_blob(&mbid, &sealed) {
        return None;
    }
    let sz = manifest["sz"].as_i64().map(|s| format!(",\"sz\":{s}")).unwrap_or_default();
    Some(format!("{MARK}{{\"mref\":\"{mbid}\",\"mk\":\"{}\"{sz}}}", b64(&mk)))
}

/// What a blob store said of one name.
pub enum Got {
    Data(Vec<u8>),
    Gone,
    Later,
}

/// A blob from any store (iOS askBlob): 404 from every store is «gone»; a busy or silent store leaves it «later».
pub fn fetch_blob(bid: &str) -> Got {
    let (mut gone, mut data) = (true, None);
    doors::read_machines("/blob-get", &json!({ "bid": bid }), 20_000, |code, v| {
        if code == 200 {
            data = v.as_ref().and_then(|v| v["data"].as_str()).and_then(unb64);
        }
        if code != 404 {
            gone = false;
        }
        data.is_some()
    });
    match data {
        Some(d) => Got::Data(d),
        None if gone => Got::Gone,
        None => Got::Later,
    }
}

/// The manifest a letter carries, unfolded from the node when the letter only names it (mref).
pub fn manifest_of(text: &str) -> Result<Value, bool> {
    let o: Value = serde_json::from_str(text.strip_prefix(MARK).ok_or(true)?).map_err(|_| true)?;
    let (Some(mref), Some(mk)) = (o["mref"].as_str(), o["mk"].as_str().and_then(unb64)) else { return Ok(o) };
    match fetch_blob(mref) {
        Got::Data(sealed) => {
            let plain = crypto::open(&mk, &sealed).ok_or(true)?;
            serde_json::from_slice(&plain).map_err(|_| true)
        }
        Got::Gone => Err(true),
        Got::Later => Err(false),
    }
}

/// THE FILE OF A MANIFEST (iOS receive): every piece in order, its name checked against the seal before it is opened, cut to
/// its size. Err(true) when a piece is gone from every store, Err(false) when it may still come.
pub fn download(m: &Value) -> Result<Vec<u8>, bool> {
    let key = m["bk"].as_str().and_then(unb64).filter(|k| k.len() == 32).ok_or(true)?;
    let pieces = m["chunks"].as_array().ok_or(true)?;
    let mut out = Vec::with_capacity(m["sz"].as_u64().unwrap_or(0).min(MAX_SEND as u64 * 4) as usize);
    for p in pieces {
        let (Some(bid), Some(cs)) = (p["bid"].as_str(), p["cs"].as_u64()) else { return Err(true) };
        let sealed = match fetch_blob(bid) {
            Got::Data(d) => d,
            Got::Gone => return Err(true),
            Got::Later => return Err(false),
        };
        if id_hex(&sealed).as_deref() != Some(bid) {
            return Err(false); // not the piece of that name: another store may hold the true one
        }
        let mut padded = crypto::open(&key, &sealed).ok_or(true)?;
        padded.truncate(cs as usize);
        out.extend_from_slice(&padded);
    }
    Ok(out)
}

/// A BIG FILE RECEIVED AS A STREAM (iOS downloadToFile): a piece fetched, its name checked against the seal, opened, kept and
/// let go -- the memory is a piece whatever the file -- and a piece already kept is not fetched again when the walk comes
/// back. Every piece but the last is a whole 512 KiB, as every Montana sends them. The file's size, or Err(true) when a
/// piece is gone from every store or the manifest is not one, Err(false) when it may still come.
pub fn download_into(m: &Value, store: &Store, mid: &str) -> Result<u64, bool> {
    let _hand = in_hand(mid).ok_or(false)?;
    let key = m["bk"].as_str().and_then(unb64).filter(|k| k.len() == 32).ok_or(true)?;
    let pieces = m["chunks"].as_array().ok_or(true)?;
    let mut size = 0u64;
    for (i, p) in pieces.iter().enumerate() {
        let (Some(bid), Some(cs)) = (p["bid"].as_str(), p["cs"].as_u64()) else { return Err(true) };
        if cs == 0 || cs > CHUNK as u64 || (i + 1 < pieces.len() && cs != CHUNK as u64) {
            return Err(true);
        }
        size += cs;
        if store.has_piece(mid, i) {
            continue;
        }
        let sealed = match fetch_blob(bid) {
            Got::Data(d) => d,
            Got::Gone => return Err(true),
            Got::Later => return Err(false),
        };
        if id_hex(&sealed).as_deref() != Some(bid) {
            return Err(false);
        }
        let mut padded = crypto::open(&key, &sealed).ok_or(true)?;
        padded.truncate(cs as usize);
        if !store.put_piece(mid, i, &padded) {
            return Err(false);
        }
    }
    if store.close_big(mid, size) { Ok(size) } else { Err(false) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_big_file_is_kept_by_its_pieces_and_seals_as_the_same_file_in_hand() {
        let dir = std::env::temp_dir().join(format!("mt-big-{}", hex(&crypto::random(6).unwrap())));
        let store = Store::at(&dir).unwrap();
        let file: Vec<u8> = (0..(2 * CHUNK + 1000)).map(|i| (i * 7 % 251) as u8).collect();
        for (i, p) in file.chunks(CHUNK).enumerate() {
            assert!(store.put_piece("A-1", i, p));
        }
        assert!(store.big("A-1").is_none() && !store.has("A-1"), "not whole before the mark");
        assert!(!store.close_big("A-1", file.len() as u64 + CHUNK as u64), "a piece missing: not whole");
        assert!(store.close_big("A-1", file.len() as u64));
        assert_eq!(store.big("A-1"), Some(file.len() as u64));
        assert!(store.has("A-1") && store.get("A-1").is_none(), "a big file is never handed whole");
        // a stretch across two pieces, and the tail
        let (s, size) = store.stretch("A-1", CHUNK as u64 - 10, 30).unwrap();
        assert_eq!((s.as_slice(), size), (&file[CHUNK - 10..CHUNK + 20], file.len() as u64));
        assert_eq!(store.stretch("A-1", file.len() as u64 - 5, 100).unwrap().0, &file[file.len() - 5..]);
        // the seals: the same names as the file in hand gives
        let key = [9u8; 32];
        let a: Vec<_> = sealed_names(&Source::Bytes(&file), &key).unwrap().into_iter().map(|p| (p.1, p.2)).collect();
        let b: Vec<_> = sealed_names(&Source::Parts(&store, "A-1", file.len() as u64), &key).unwrap().into_iter().map(|p| (p.1, p.2)).collect();
        assert_eq!(a, b);
        // written out, compared, forwarded, deleted
        let out = dir.join("out.bin");
        assert!(store.write_to("A-1", &out) && std::fs::read(&out).unwrap() == file && store.same_as("A-1", &out));
        std::fs::write(&out, &file[..file.len() - 1]).unwrap();
        assert!(!store.same_as("A-1", &out));
        assert!(store.copy_big("A-1", "B-2") && store.stretch("B-2", 0, 10).unwrap().0 == file[..10]);
        store.delete("A-1");
        assert!(!store.has("A-1") && store.has("B-2"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_piece_is_named_by_the_cores_sha_and_opens_cut_to_its_size() {
        let key = [7u8; 32];
        let piece = vec![42u8; 1000];
        let (sealed, bid) = seal_piece(&piece, &key, 3).unwrap();
        assert_eq!(bid, hex(&crate::wire::sha(&[&sealed])), "the core's blob id is the SHA-256 of the seal");
        let (again, bid2) = seal_piece(&piece, &key, 3).unwrap();
        assert_eq!((again, bid2.clone()), (sealed.clone(), bid.clone()), "the same piece under the same key names itself alike");
        let mut open = crypto::open(&key, &sealed).unwrap();
        assert!(open.len() >= piece.len() && open.len() == crypto::pad_len(piece.len()));
        open.truncate(piece.len());
        assert_eq!(open, piece);
        assert_ne!(seal_piece(&piece, &key, 4).unwrap().1, bid, "another number, another nonce");
    }

    #[test]
    fn a_small_manifest_rides_inside_the_letter() {
        let m = json!({ "k": "doc", "e": "txt", "bk": b64(&[1u8; 32]), "sz": 5, "chunks": [{ "bid": "ab", "cs": 5 }], "n": "a.txt" });
        let l = manifest_letter(&m).unwrap();
        assert!(l.starts_with(MARK));
        assert_eq!(manifest_of(&l).unwrap(), m);
    }
}
