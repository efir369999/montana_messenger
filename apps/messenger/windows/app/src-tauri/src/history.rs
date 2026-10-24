//! THE HISTORY UNDER THE WORDS (iOS MontanaArchive in MontanaPQ.swift, MontanaBackup.swift, MTKeeping's light copy): every
//! letter is also written into an archive the core seals under keys only the 24 words derive (mt_archive_append:
//! <base>/Chats/<label>/conversation.mtlog), each folder headed by the correspondence's secret («s:») and name («n:»). A copy
//! of it (.mtbak, version 2) is that archive in equal sealed frames; a device restored from the words reads a copy -- a file
//! the person hands it, or the light copy another device of the words laid on the nodes -- and the heads give the pipes
//! back, the blocks give the letters back.

use crate::abi::*;
use crate::book::{Book, Msg};
use crate::wire::{self, hex, hmac, sha, unb64};
use crate::{crypto, doors, media, seed};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::ChaCha20Poly1305;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::ffi::CString;
use std::path::{Path, PathBuf};

const FRAME: usize = 1 << 20;
const FRAME_PLAIN: usize = FRAME - 28;
const PIECE: usize = (1 << 20) - 4096;
const KIND_TAIL: u8 = 0;
pub const KIND_BLOCK: u8 = 1;
const KIND_STORE: u8 = 4;
/// A file of a correspondence's own folder in the archive, sealed as it lies there (iOS kindMedia): the face among them.
const KIND_MEDIA: u8 = 2;
/// The correspondent's face, sealed beside their letters under the media key of the seed (iOS MontanaArchive.faceBlob): a restore
/// by the same words wears it again.
pub const FACE_BLOB: &str = "face";
/// A name a copy may write in a folder: one plain file, never a path out of its place (iOS MontanaBackup.plainName).
fn plain(n: &str) -> bool {
    !n.is_empty() && n != ".." && !n.contains(['/', '\\', ':']) && !n.starts_with('.')
}
/// The account card (iOS MontanaBackup kindCard, seedCard / layCard): a JSON map of the person's own values, each key tagged
/// by its form («s:» a word). An iPhone's card carries its whole store; Windows holds of it the person's own words.
pub const KIND_CARD: u8 = 3;
pub const CARD_WORDS: [&str; 3] = ["userName", "profileBio", "profileLink"];
pub(crate) const HEAD_DIR: u8 = 2;
pub const APP: &str = "quest.montana.app";

/// The keys of the history, all from the words: the entropy, the history key, the media key, the owner (account id).
#[derive(Clone)]
pub struct Keys {
    pub entropy: [u8; 32],
    pub hk: [u8; 32],
    pub mk: [u8; 32],
    pub owner: [u8; 32],
}

impl Drop for Keys {
    fn drop(&mut self) {
        self.entropy.fill(0);
        self.hk.fill(0);
        self.mk.fill(0);
        self.owner.fill(0);
    }
}

pub fn keys(words: &str) -> Option<Keys> {
    let c = CString::new(seed::normal(words)).ok()?;
    let mut k = Keys { entropy: [0; 32], hk: [0; 32], mk: [0; 32], owner: [0; 32] };
    // SAFETY: a NUL-terminated phrase and 32-byte buffers
    unsafe {
        if mt_mnemonic_to_entropy(c.as_ptr(), k.entropy.as_mut_ptr()) != MT_OK
            || mt_history_key(k.entropy.as_ptr(), k.hk.as_mut_ptr()) != MT_OK
            || mt_media_key(k.entropy.as_ptr(), k.mk.as_mut_ptr()) != MT_OK
        {
            return None;
        }
    }
    k.owner.copy_from_slice(&seed::role_seed(words, b"mt-owner-key")?);
    Some(k)
}

/// A folder's name (iOS folderLabel): the keyed hash of the correspondence's reference -- nobody but the owner derives it.
pub fn label(hk: &[u8], r: &str) -> String {
    hex(&sha(&[b"mt-archive-label\0", hk, b"\0", r.as_bytes()])[..16])
}

/// HKDF-SHA-256 (RFC 5869), as iOS CryptoKit derives the copy's keys.
fn hkdf(ikm: &[u8], salt: &[u8], info: &[u8]) -> [u8; 32] {
    let h = hkdf::Hkdf::<sha2::Sha256>::new(Some(salt), ikm);
    let mut out = [0u8; 32];
    h.expand(info, &mut out).expect("32 bytes are within HKDF's reach");
    out
}

fn copy_key(entropy: &[u8], salt: &[u8]) -> [u8; 32] {
    hkdf(entropy, salt, b"mt-backup-key-v2")
}

/// The copy's file name (iOS nameNow): its moment and sixteen hex of HMAC over it under a key of the words -- the owner alone
/// recognises it.
pub fn copy_name(entropy: &[u8], moment: &str) -> String {
    let owner = hkdf(entropy, &[], b"mt-backup-owner-v1");
    format!("montana-{moment}-{}.mtbak", &hex(&hmac(&owner, moment.as_bytes()))[..16])
}

/// One record of a copy, its pieces joined.
#[derive(Debug, Clone, PartialEq)]
pub struct Record {
    pub kind: u8,
    pub name: String,
    pub data: Vec<u8>,
}

/// THE COPY, WRITTEN (iOS Framer): the records cut into pieces, joined into one stream, cut into frames of one length, each
/// sealed under the copy's key with the salt, its number and «final» as associated data; the tail signs every record.
pub fn write_copy(entropy: &[u8], records: &[Record]) -> Option<Vec<u8>> {
    let salt = crypto::random(32)?;
    let key = copy_key(entropy, &salt);
    let mut stream: Vec<u8> = vec![];
    let mut digest = sha2::Sha256::default();
    use sha2::Digest;
    let mut tally = (0usize, 0usize, 0usize, 0usize);
    let put = |stream: &mut Vec<u8>, digest: &mut sha2::Sha256, kind: u8, name: &str, data: &[u8], more: bool| {
        let mut p = vec![kind, more as u8];
        p.extend_from_slice(&(name.len() as u16).to_le_bytes());
        p.extend_from_slice(name.as_bytes());
        p.extend_from_slice(&(data.len() as u32).to_le_bytes());
        p.extend_from_slice(data);
        if kind != KIND_TAIL {
            digest.update(&p);
        }
        stream.extend_from_slice(&p);
    };
    for r in records {
        let pieces: Vec<&[u8]> = if r.data.is_empty() { vec![&[][..]] } else { r.data.chunks(PIECE).collect() };
        for (i, piece) in pieces.iter().enumerate() {
            put(&mut stream, &mut digest, r.kind, &r.name, piece, i + 1 < pieces.len());
        }
        match r.kind {
            KIND_BLOCK => tally.1 += 1,
            KIND_STORE => tally.2 += 1,
            _ => {}
        }
        tally.3 += r.data.len();
    }
    let tail = json!({ "tally": { "chats": tally.0, "records": tally.1, "media": tally.2, "bytes": tally.3, "skipped": 0 },
                       "digest": hex(&digest.finalize()) });
    put(&mut stream, &mut sha2::Sha256::default(), KIND_TAIL, "", tail.to_string().as_bytes(), false);
    let frames = stream.len().div_ceil(FRAME_PLAIN).max(1);
    stream.resize(frames * FRAME_PLAIN, 0);
    let aead = ChaCha20Poly1305::new((&key).into());
    let mut out = salt.clone();
    for (i, plain) in stream.chunks(FRAME_PLAIN).enumerate() {
        let nonce = crypto::random(12)?;
        let mut aad = salt.clone();
        aad.extend_from_slice(&(i as u64).to_le_bytes());
        aad.push((i + 1 == frames) as u8);
        let ct = aead.encrypt(nonce.as_slice().into(), Payload { msg: plain, aad: &aad }).ok()?;
        out.extend_from_slice(&nonce);
        out.extend_from_slice(&ct);
    }
    Some(out)
}

/// Why a copy did not open.
#[derive(Debug, PartialEq, serde::Serialize)]
pub enum Refusal {
    /// these words do not open it (or it is no copy at all: a version-2 copy carries no mark)
    Unopened,
    /// cut short, or its tail does not sign what came before
    Torn,
}

/// THE COPY, READ (iOS Taker): every frame opened under the words, the stream read record by record, the pieces joined, the
/// tail's digest checked against everything before it.
pub fn read_copy(entropy: &[u8], file: &[u8]) -> Result<Vec<Record>, Refusal> {
    if file.len() < 32 + FRAME || !(file.len() - 32).is_multiple_of(FRAME) {
        return Err(Refusal::Unopened);
    }
    let salt = &file[..32];
    let key = copy_key(entropy, salt);
    let aead = ChaCha20Poly1305::new((&key).into());
    let frames = (file.len() - 32) / FRAME;
    let mut stream = Vec::with_capacity(frames * FRAME_PLAIN);
    for i in 0..frames {
        let f = &file[32 + i * FRAME..32 + (i + 1) * FRAME];
        let mut aad = salt.to_vec();
        aad.extend_from_slice(&(i as u64).to_le_bytes());
        aad.push((i + 1 == frames) as u8);
        let plain = aead.decrypt(f[..12].into(), Payload { msg: &f[12..], aad: &aad }).map_err(|_| if i == 0 { Refusal::Unopened } else { Refusal::Torn })?;
        stream.extend_from_slice(&plain);
    }
    use sha2::Digest;
    let mut digest = sha2::Sha256::default();
    let mut out: Vec<Record> = vec![];
    let mut open: Option<Record> = None;
    let mut at = 0;
    loop {
        if at + 8 > stream.len() {
            return Err(Refusal::Torn);
        }
        let (kind, more) = (stream[at], stream[at + 1] == 1);
        let nl = u16::from_le_bytes([stream[at + 2], stream[at + 3]]) as usize;
        if at + 8 + nl > stream.len() {
            return Err(Refusal::Torn);
        }
        let name = String::from_utf8_lossy(&stream[at + 4..at + 4 + nl]).into_owned();
        let dl = u32::from_le_bytes(stream[at + 4 + nl..at + 8 + nl].try_into().unwrap()) as usize;
        let end = at + 8 + nl + dl;
        if end > stream.len() {
            return Err(Refusal::Torn);
        }
        let data = &stream[at + 8 + nl..end];
        if kind == KIND_TAIL {
            let tail: Value = serde_json::from_slice(data).map_err(|_| Refusal::Torn)?;
            if tail["digest"].as_str() != Some(hex(&digest.finalize()).as_str()) {
                return Err(Refusal::Torn);
            }
            return Ok(out);
        }
        digest.update(&stream[at..end]);
        match open.as_mut() {
            Some(r) if r.kind == kind && r.name == name => r.data.extend_from_slice(data),
            _ => {
                if let Some(r) = open.take() {
                    out.push(r);
                }
                open = Some(Record { kind, name, data: data.to_vec() });
            }
        }
        if !more {
            out.extend(open.take());
        }
        at = end;
    }
}

/// THE ARCHIVE OF THIS MACHINE: the core's folders under <data>/archive, one per correspondence, sealed under the words.
#[derive(Clone)]
pub struct Archive {
    base: PathBuf,
    keys: Keys,
    device: [u8; 16],
}

/// One item of a block: the correspondence (SHA-256 of its reference), mine/theirs/head, the moment (seconds), the content.
pub struct Item {
    pub conv: [u8; 32],
    pub dir: u8,
    pub at: u64,
    pub content: Vec<u8>,
}

fn cstr(p: &Path) -> Option<CString> {
    CString::new(p.to_string_lossy().as_bytes()).ok()
}

impl Archive {
    pub fn new(base: &Path, keys: Keys, device: [u8; 16]) -> Archive {
        let _ = std::fs::create_dir_all(base);
        Archive { base: base.to_path_buf(), keys, device }
    }

    pub fn keys(&self) -> &Keys {
        &self.keys
    }

    /// One row into the correspondence's folder (iOS MontanaArchive.archive): 0 mine, 1 theirs, 2 a head.
    pub fn append(&self, r: &str, dir: u8, at_secs: u64, content: &[u8]) -> bool {
        let (Some(base), Ok(folder)) = (cstr(&self.base), CString::new(label(&self.keys.hk, r))) else { return false };
        let conv = sha(&[r.as_bytes()]);
        // SAFETY: NUL-terminated paths, 32-byte keys, a 16-byte device id, the content of its length
        unsafe {
            mt_archive_append(base.as_ptr(), folder.as_ptr(), self.keys.hk.as_ptr(), self.keys.owner.as_ptr(), self.device.as_ptr(),
                              conv.as_ptr(), dir, at_secs, content.as_ptr(), content.len()) == 0
        }
    }

    /// A sealed block laid into a folder as it was sealed (a restore): the core keeps one of each.
    pub fn ingest(&self, r: &str, sealed: &[u8]) -> bool {
        self.ingest_into(&label(&self.keys.hk, r), sealed) >= 0
    }

    /// The same into a folder by its name: 1 filed, 0 held already, below 0 refused (it does not open under these words).
    pub fn ingest_into(&self, folder: &str, sealed: &[u8]) -> i32 {
        let (Some(base), Ok(folder)) = (cstr(&self.base), CString::new(folder)) else { return -1 };
        // SAFETY: as in append
        unsafe { mt_archive_ingest(base.as_ptr(), folder.as_ptr(), self.keys.hk.as_ptr(), self.keys.owner.as_ptr(), sealed.as_ptr(), sealed.len()) }
    }

    /// A file sealed into a correspondence's folder under the media key (iOS MontanaArchive.putMedia: the core's own seal).
    pub fn put_media(&self, r: &str, blob: &str, data: &[u8]) -> bool {
        let (Some(base), Ok(folder), Ok(bid)) = (cstr(&self.base), CString::new(label(&self.keys.hk, r)), CString::new(blob)) else { return false };
        // SAFETY: NUL-terminated paths and names, the 32-byte media key and account id, the data of its length
        unsafe {
            mt_archive_put_media(base.as_ptr(), folder.as_ptr(), bid.as_ptr(), self.keys.mk.as_ptr(), self.keys.owner.as_ptr(),
                                 if data.is_empty() { std::ptr::null() } else { data.as_ptr() }, data.len()) == 0
        }
    }
    /// A folder's file opened (iOS getMedia): none when it is not there or does not open under these words. A face is its own
    /// folder's or none -- never searched for in another folder (iOS 04.10).
    pub fn get_media(&self, folder: &str, blob: &str) -> Option<Vec<u8>> {
        let path = self.base.join("Chats").join(folder).join("Media").join(blob);
        let cap = std::fs::metadata(&path).ok()?.len() as usize + 1024;
        let (Some(base), Ok(name), Ok(bid)) = (cstr(&self.base), CString::new(folder), CString::new(blob)) else { return None };
        let mut out = vec![0u8; cap];
        // SAFETY: as in put_media; a buffer of the sealed file's size, which no plaintext passes
        let n = unsafe {
            mt_archive_get_media(base.as_ptr(), name.as_ptr(), bid.as_ptr(), self.keys.mk.as_ptr(), self.keys.owner.as_ptr(), out.as_mut_ptr(), out.len())
        };
        (n > 0).then(|| { out.truncate(n as usize); out })
    }
    /// The sealed files of a folder's own media, as they lie (a copy carries them so: iOS kindMedia «folder/name»).
    pub fn media_files(&self, folder: &str) -> Vec<(String, Vec<u8>)> {
        let Ok(dir) = std::fs::read_dir(self.base.join("Chats").join(folder).join("Media")) else { return vec![] };
        let mut names: Vec<String> = dir.flatten().filter(|e| e.path().is_file()).map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| plain(n)).collect();
        names.sort();
        names.into_iter().filter_map(|n| std::fs::read(self.base.join("Chats").join(folder).join("Media").join(&n)).ok().map(|b| (n, b))).collect()
    }
    /// A sealed file of a copy laid back in its folder (iOS restore of kindMedia): a file already there is never overwritten -- a
    /// copy adds, it does not erase.
    pub fn lay_media(&self, folder: &str, name: &str, sealed: &[u8]) -> bool {
        if !plain(folder) || !plain(name) {
            return false;
        }
        let dir = self.base.join("Chats").join(folder).join("Media");
        let path = dir.join(name);
        if path.exists() {
            return false;
        }
        std::fs::create_dir_all(&dir).is_ok() && std::fs::write(&path, sealed).is_ok()
    }

    /// This machine's tag among the devices of the words (iOS writerTag): SHA-256 over the device id, by the core.
    pub fn writer_tag(&self) -> Option<[u8; 4]> {
        let mut tag = [0u8; 4];
        // SAFETY: the 16-byte device id and a 4-byte buffer
        (unsafe { mt_writer_tag(self.device.as_ptr(), tag.as_mut_ptr()) } == MT_OK).then_some(tag)
    }

    pub fn device(&self) -> [u8; 16] {
        self.device
    }

    /// The folders of this machine's archive (iOS conversations): their names, which say nothing.
    pub fn folders(&self) -> Vec<String> {
        let Ok(dirs) = std::fs::read_dir(self.base.join("Chats")) else { return vec![] };
        let mut out: Vec<String> = dirs.flatten().filter(|d| d.path().is_dir()).map(|d| d.file_name().to_string_lossy().into_owned())
            .filter(|n| !n.starts_with('.')).collect();
        out.sort();
        out
    }

    /// The blocks a writer sealed in one folder from a number on (iOS export): (its number, the sealed block), as the core
    /// reads them out of the log.
    pub fn export(&self, folder: &str, writer: &[u8; 4], from: u64) -> Vec<(u64, Vec<u8>)> {
        let (Some(base), Ok(name)) = (cstr(&self.base), CString::new(folder)) else { return vec![] };
        let size = std::fs::metadata(self.base.join("Chats").join(folder).join("conversation.mtlog")).map_or(0, |m| m.len() as usize);
        let mut buf = vec![0u8; size + 1024];
        // SAFETY: NUL-terminated strings, a 4-byte tag, a buffer of its capacity (the whole log fits, as the core promises)
        let n = unsafe { mt_archive_export(base.as_ptr(), name.as_ptr(), writer.as_ptr(), from, buf.as_mut_ptr(), buf.len()) };
        if n <= 0 {
            return vec![];
        }
        let d = &buf[..n as usize];
        let mut out = vec![];
        let mut i = 0;
        while i + 4 <= d.len() {
            let len = u32::from_le_bytes(d[i..i + 4].try_into().unwrap()) as usize;
            i += 4;
            if len == 0 || i + len > d.len() {
                break;
            }
            let sealed = d[i..i + len].to_vec();
            i += len;
            let (mut tag, mut seq) = ([0u8; 4], 0u64);
            // SAFETY: the sealed block of its length, a 4-byte tag and a number to write
            if unsafe { mt_archive_block_id(sealed.as_ptr(), sealed.len(), tag.as_mut_ptr(), &mut seq) } == MT_OK {
                out.push((seq, sealed));
            }
        }
        out
    }

    /// Which correspondence a sealed block belongs to (iOS peekConv): the SHA-256 of its reference, read only under the words.
    pub fn peek_conv(&self, sealed: &[u8]) -> Option<[u8; 32]> {
        let mut out = [0u8; 32];
        // SAFETY: 32-byte keys, the sealed block of its length, a 32-byte buffer
        let rc = unsafe { mt_archive_peek_conv(self.keys.hk.as_ptr(), self.keys.owner.as_ptr(), sealed.as_ptr(), sealed.len(), out.as_mut_ptr()) };
        (rc == MT_OK).then_some(out)
    }

    /// Every sealed block of every folder (the log: u32 LE length ‖ sealed, as the core writes it).
    pub fn blocks(&self) -> Vec<Vec<u8>> {
        self.blocks_except(&std::collections::HashSet::new())
    }
    /// The same but for the folders named in `out` (a conversation left out of a copy, by its label).
    pub fn blocks_except(&self, out_of: &std::collections::HashSet<String>) -> Vec<Vec<u8>> {
        let mut out = vec![];
        let Ok(dirs) = std::fs::read_dir(self.base.join("Chats")) else { return out };
        for d in dirs.flatten().filter(|d| !out_of.contains(d.file_name().to_string_lossy().as_ref())) {
            let Ok(log) = std::fs::read(d.path().join("conversation.mtlog")) else { continue };
            let mut i = 0;
            while i + 4 <= log.len() {
                let n = u32::from_le_bytes(log[i..i + 4].try_into().unwrap()) as usize;
                i += 4;
                if n == 0 || i + n > log.len() {
                    break;
                }
                out.push(log[i..i + n].to_vec());
                i += n;
            }
        }
        out
    }

    /// A sealed block opened by the core (iOS openBlock): block_seq u64 ‖ count u32 ‖ (conv 32 ‖ dir 1 ‖ at 8 ‖ len 4 ‖ content)×.
    pub fn open_block(&self, sealed: &[u8]) -> Vec<Item> {
        let mut buf = vec![0u8; (sealed.len() + 64).max(1024)];
        // SAFETY: 32-byte keys, the sealed block of its length, a buffer of its capacity
        let n = unsafe { mt_archive_open_block(self.keys.hk.as_ptr(), self.keys.owner.as_ptr(), sealed.as_ptr(), sealed.len(), buf.as_mut_ptr(), buf.len()) };
        if n <= 12 {
            return vec![];
        }
        let d = &buf[..n as usize];
        let u32_at = |o: usize| u32::from_le_bytes(d[o..o + 4].try_into().unwrap()) as usize;
        let count = u32_at(8);
        let mut o = 12;
        let mut items = vec![];
        for _ in 0..count {
            if o + 45 > d.len() {
                break;
            }
            let conv: [u8; 32] = d[o..o + 32].try_into().unwrap();
            let dir = d[o + 32];
            let at = u64::from_le_bytes(d[o + 33..o + 41].try_into().unwrap());
            let len = u32_at(o + 41);
            o += 45;
            if o + len > d.len() {
                break;
            }
            items.push(Item { conv, dir, at, content: d[o..o + len].to_vec() });
            o += len;
        }
        items
    }
}

/// What a restore brought back.
#[derive(serde::Serialize, Default, Debug, PartialEq)]
pub struct Restored {
    pub chats: usize,
    pub records: usize,
    pub media: usize,
    #[serde(default)]
    pub faces: usize,
}

/// A restored row's name (iOS: «arc:» + 12 bytes of SHA-256 over «seconds|mine|words»): the same letter restored twice is
/// one row.
/// A row's words for telling the same letter under two names: its words, or a file's kind, name and caption (the name a file is
/// kept under follows the letter's name, so it is left out).
fn archived_words(text: &str) -> String {
    match text.strip_prefix(media::MARK) {
        Some(j) => {
            let m: Value = serde_json::from_str(j).unwrap_or_default();
            format!("{}|{}|{}", m["k"].as_str().unwrap_or(""), m["n"].as_str().unwrap_or(""), m["cap"].as_str().unwrap_or(""))
        }
        None => text.to_string(),
    }
}

pub(crate) fn arc_mid(at: u64, mine: bool, text: &str) -> String {
    format!("arc:{}", hex(&sha(&[format!("{at}|{}|{text}", if mine { 1 } else { 0 }).as_bytes()])[..12]))
}

/// THE COPY LAID BACK (iOS MontanaBackup.restore + MontanaArchive.restore): the heads give the pipes back («s:» the secret,
/// «n:» the name, «x:» closed -- the last head decides), the blocks are kept in this machine's archive, the letters become rows;
/// an attachment the copy carries is kept beside its row.
pub fn restore(archive: &Archive, book: &Book, store: &media::Store, faces: Option<&media::Store>, records: &[Record]) -> Restored {
    let mut done = Restored::default();
    // a feed of Saved Messages held here is the truth -- its deletions too: the blocks are kept, no row laid (iOS restoreFromArchive)
    let saved_held = book.chat(crate::book::SAVED).is_some();
    // the files of the folders first (iOS kindMedia): the faces among them, laid where the archive looks for them
    for r in records.iter().filter(|r| r.kind == KIND_MEDIA) {
        if let Some((folder, name)) = r.name.split_once('/') {
            archive.lay_media(folder, name, &r.data);
        }
    }
    let files: std::collections::HashMap<&str, &[u8]> = records.iter().filter(|r| r.kind == KIND_STORE).map(|r| (r.name.as_str(), r.data.as_slice())).collect();
    let blocks: Vec<(&Record, Vec<Item>)> = records.iter().filter(|r| r.kind == KIND_BLOCK).map(|r| (r, archive.open_block(&r.data))).collect();
    // the heads first: which correspondence each SHA-256 of a reference is, and its name
    type Head = (Option<Vec<u8>>, bool, Option<String>);
    let mut heads: std::collections::HashMap<[u8; 32], Head> = Default::default();
    let mut ordered: Vec<&Item> = blocks.iter().flat_map(|(_, it)| it.iter()).filter(|i| i.dir == HEAD_DIR).collect();
    ordered.sort_by_key(|i| i.at);
    for i in ordered {
        let s = String::from_utf8_lossy(&i.content).into_owned();
        let h = heads.entry(i.conv).or_default();
        if let Some(sec) = s.strip_prefix("s:").and_then(unb64).filter(|x| x.len() == 32) {
            h.0 = Some(sec);
            h.1 = false;
        } else if s.starts_with("x:") {
            h.1 = true;
        } else if let Some(n) = s.strip_prefix("n:") {
            h.2 = Some(n.chars().take(64).collect());
        }
    }
    let mut refs: std::collections::HashMap<[u8; 32], String> = Default::default();
    for (conv, (secret, closed, name)) in &heads {
        let Some(secret) = secret else { continue };
        let r = wire::reference(secret);
        if sha(&[r.as_bytes()]) != *conv {
            continue; // a head that does not belong to its folder
        }
        // A PIPE CLOSED AT THE OTHER END STANDS BY ITS NAME, NEVER ANSWERED (iOS restore: «x:» -- the name, no revival): its letters
        // are the person's history all the same, kept and laid; a secret the book refused to keep keeps its letters too
        if !*closed && book.establish(secret).is_none() {
            continue;
        }
        let fresh = book.chat(&r).is_none();
        book.open(&r, name.as_deref().unwrap_or(""), false);
        if fresh {
            done.chats += 1;
        }
        // THE FACE RIDES WITH THE LETTERS (iOS RestoredChat.face, 15.10.4): a restore by the same words wears it again
        if let Some(faces) = faces.filter(|f| !f.has(&r)) {
            if let Some(face) = archive.get_media(&label(&archive.keys.hk, &r), FACE_BLOB).filter(|f| !f.is_empty()) {
                if faces.put(&r, &face) {
                    book.edit(&r, |c| c.face_at = c.face_at.max(1));
                    done.faces += 1;
                }
            }
        }
        refs.insert(*conv, r);
    }
    // SAVED MESSAGES HAS NO SECRET (iOS MontanaPQ restore: the folder of its own key, head «a:»): its blocks are known by the
    // SHA-256 of its key, the same for every person
    refs.insert(sha(&[crate::book::SAVED.as_bytes()]), crate::book::SAVED.to_string());
    for (rec, items) in &blocks {
        let Some(conv) = items.first().map(|i| i.conv) else { continue };
        let Some(r) = refs.get(&conv) else {
            // A BLOCK NO HEAD NAMES IS KEPT ALL THE SAME (the owner's word 24.10.2026: no loss; iOS files it under its folder): a
            // group's, a channel's, a folder whose head came in another copy -- filed under its conversation's own SHA-256, it rides
            // the next copy whole and stands once its head comes
            archive.ingest_into(&hex(&conv), &rec.data);
            continue;
        };
        archive.ingest(r, &rec.data);
        if saved_held && crate::book::is_saved(r) {
            continue;
        }
        let mut rows: Vec<Msg> = vec![];
        for i in items.iter().filter(|i| i.dir != HEAD_DIR) {
            let Some(text) = String::from_utf8(i.content.clone()).ok().filter(|t| !t.is_empty()) else { continue };
            let mine = i.dir == 0;
            let mid = arc_mid(i.at, mine, &text);
            let mut text = text;
            if let Some(j) = text.strip_prefix(media::MARK) {
                // the archive's own form of a file ({cap, f, k, n}): the file rides the copy under «f»
                let a: Value = serde_json::from_str(j).unwrap_or_default();
                let f = a["f"].as_str().unwrap_or("");
                let ext = f.rsplit('.').next().filter(|e| *e != f).unwrap_or("bin");
                let mut m = json!({ "k": a["k"].as_str().unwrap_or("doc"), "e": ext });
                for k in ["n", "cap"] {
                    if let Some(v) = a[k].as_str().filter(|v| !v.is_empty()) {
                        m[k] = json!(v);
                    }
                }
                if let Some(bytes) = files.get(f) {
                    m["sz"] = json!(bytes.len());
                    if store.put(&mid, bytes) {
                        done.media += 1;
                    }
                }
                text = format!("{}{}", media::MARK, m);
            }
            rows.push(Msg { mid, text, mine, at: (i.at * 1000) as i64, state: if mine { 2 } else { 0 }, ..Default::default() });
        }
        book.edit(r, |c| {
            // A ROW THE FEED ALREADY HOLDS IS NOT LAID TWICE (iOS archiveSig: the second, the side, the words): the same letter under
            // its wire name, under an archive name, or buried here -- a copy laid on a living feed fills its gaps and nothing more
            let held: std::collections::HashSet<(i64, bool, String)> =
                c.msgs.iter().map(|x| (x.at / 1000, x.mine, archived_words(&x.text))).collect();
            for m in rows {
                let sig = (m.at / 1000, m.mine, archived_words(&m.text));
                let buried = c.graves.iter().any(|g| *g == m.mid || crate::book::birth_ms(g).is_some_and(|b| b / 1000 == m.at / 1000));
                if !c.msgs.iter().any(|x| x.mid == m.mid) && !held.contains(&sig) && !buried {
                    c.msgs.push(m);
                    done.records += 1;
                }
            }
            c.msgs.sort_by_key(|m| m.at);
            c.hidden = false;
        });
    }
    done
}

/// WHAT A PERSON LEFT OUT OF A COPY (iOS CopyPlan, «mt.backup.plan»): a conversation, a kind of attachment, or one file --
/// everything goes by default; kept in this machine's vault.
#[derive(Serialize, Deserialize, Default, Clone, Debug, PartialEq)]
pub struct Plan {
    #[serde(rename = "skipChats", default)]
    pub skip_chats: Vec<String>,
    #[serde(rename = "skipKinds", default)]
    pub skip_kinds: Vec<String>,
    #[serde(rename = "skipFiles", default)]
    pub skip_files: Vec<String>,
}
const PLAN: &str = "copyPlan";
impl Plan {
    pub fn load(v: &crate::vault::Vault) -> Plan {
        v.get(PLAN).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
    }
    pub fn save(&self, v: &crate::vault::Vault) -> bool {
        v.set(PLAN, &serde_json::to_vec(self).unwrap_or_default())
    }
    pub fn takes_chat(&self, r: &str) -> bool {
        !self.skip_chats.iter().any(|x| x == r)
    }
    pub fn takes_kind(&self, k: &str) -> bool {
        !self.skip_kinds.iter().any(|x| x == k)
    }
    /// A file goes when its conversation, its kind and the file itself all go (iOS Scope.takes(file:)).
    pub fn takes_file(&self, r: &str, kind: &str, name: &str) -> bool {
        self.takes_chat(r) && self.takes_kind(kind) && !self.skip_files.iter().any(|x| x == name)
    }
}

/// A letter's file by its kind as the copy names kinds (iOS MontanaBackup.Kind: photo, video, voice, file).
pub fn kind_of(text: &str) -> &'static str {
    let m: Value = serde_json::from_str(text.strip_prefix(media::MARK).unwrap_or("{}")).unwrap_or_default();
    match m["k"].as_str() {
        Some("img") => "photo",
        Some("vid") => "video",
        Some("aud") => "voice",
        _ => "file",
    }
}

/// THE COPY OF THIS MACHINE (iOS MontanaBackup.create): every sealed block, then every file of a letter under the name its
/// archive row gives it; the tail signs them.
#[cfg(test)]
pub fn make_copy(archive: &Archive, book: &Book, store: &media::Store, card: Option<Record>) -> Option<Vec<u8>> {
    make_copy_planned(archive, book, store, card, &Plan::default(), &std::collections::HashSet::new())
}
/// THE COPY AS THE PERSON PLANNED IT (iOS CopyInventory.scope): a conversation left out is not read at all -- none of its blocks,
/// none of its files; a kind or a file left out stays out; `skip` adds the files a copy for the node leaves to the node's book.
pub fn make_copy_planned(archive: &Archive, book: &Book, store: &media::Store, card: Option<Record>, plan: &Plan,
    skip: &std::collections::HashSet<String>) -> Option<Vec<u8>> {
    let out: std::collections::HashSet<String> = plan.skip_chats.iter().map(|r| label(&archive.keys.hk, r)).collect();
    let mut records: Vec<Record> = archive.blocks_except(&out).into_iter().map(|b| Record { kind: KIND_BLOCK, name: String::new(), data: b }).collect();
    // the files of every folder the copy takes, sealed as they lie (iOS kindMedia): the faces among them
    for folder in archive.folders().into_iter().filter(|f| !out.contains(f)) {
        for (n, sealed) in archive.media_files(&folder) {
            records.push(Record { kind: KIND_MEDIA, name: format!("{folder}/{n}"), data: sealed });
        }
    }
    for c in book.all() {
        for m in c.msgs.iter().filter(|m| m.text.starts_with(media::MARK)) {
            let name = file_name(&m.mid, &m.text);
            if skip.contains(&name) || !plan.takes_file(&c.reference, kind_of(&m.text), &name) {
                continue;
            }
            if let Some(bytes) = store.get(&m.mid) {
                records.push(Record { kind: KIND_STORE, name, data: bytes });
            }
        }
    }
    records.extend(card); // last, after every letter and file (iOS)
    write_copy(&archive.keys.entropy, &records)
}

/// THE CARD A COPY OF THIS MACHINE CARRIES (iOS seedCard «s:»): the person's own words that are not empty; none -- no card.
pub fn card_record(words: &[(&str, String)]) -> Option<Record> {
    let m: Map<String, Value> = words.iter().filter(|(_, v)| !v.is_empty()).map(|(k, v)| (format!("s:{k}"), json!(v))).collect();
    (!m.is_empty()).then(|| Record { kind: KIND_CARD, name: String::new(), data: Value::Object(m).to_string().into_bytes() })
}

/// The person's own words a copy's card carries (iOS layCard «s:»), each of CARD_WORDS it names.
pub fn card_words(records: &[Record]) -> Vec<(&'static str, String)> {
    let data: Vec<u8> = records.iter().filter(|r| r.kind == KIND_CARD).flat_map(|r| r.data.iter().copied()).collect();
    let m: Map<String, Value> = serde_json::from_slice(&data).unwrap_or_default();
    CARD_WORDS.iter().filter_map(|k| m.get(&format!("s:{k}")).and_then(|v| v.as_str()).map(|v| (*k, v.to_string()))).collect()
}

/// The name a letter's file is kept under in the archive and in a copy (iOS «f»): its own, with the extension it came with.
pub fn file_name(mid: &str, text: &str) -> String {
    let m: Value = serde_json::from_str(text.strip_prefix(media::MARK).unwrap_or("{}")).unwrap_or_default();
    let ext: String = m["e"].as_str().unwrap_or("bin").chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect();
    format!("{}.{ext}", &hex(&sha(&[mid.as_bytes()]))[..16])
}

/// The archive's own form of a letter's file (iOS: {cap, f, k, n}, the keys in order).
pub fn archive_media(mid: &str, text: &str) -> String {
    let m: Value = serde_json::from_str(text.strip_prefix(media::MARK).unwrap_or("{}")).unwrap_or_default();
    let mut a = serde_json::Map::new();
    if let Some(c) = m["cap"].as_str() {
        a.insert("cap".into(), json!(c));
    }
    a.insert("f".into(), json!(file_name(mid, text)));
    a.insert("k".into(), json!(m["k"].as_str().unwrap_or("doc")));
    if let Some(n) = m["n"].as_str() {
        a.insert("n".into(), json!(n));
    }
    // a voice's length in seconds (iOS archiveRow: «d» when above zero)
    if let Some(d) = m["du"].as_f64().filter(|d| *d > 0.0) {
        a.insert("d".into(), json!(d));
    }
    format!("{}{}", media::MARK, Value::Object(a))
}

/// THE LIGHT COPY ANOTHER DEVICE LAID (iOS MTKeeping.takeLight): the pipe of light, derived from the words, read across the
/// box's term and never confirmed (it stays for the others); the newest copy of each writer fetched by its road, checked
/// against its digest, read. The copies' records, newest writer first.
pub fn take_light(words: &str, twin: &str, entropy: &[u8]) -> Vec<Vec<Record>> {
    let Some(light) = seed::role_seed(words, b"mt-keep-light") else { return vec![] };
    let w0 = wire::day();
    let subs: Vec<String> = ((w0 - 8)..=(w0 + 1)).map(|d| wire::conv_w(&light, d)).collect();
    let page = json!({ "subs": subs, "sids": subs.iter().map(|c| wire::sub_id(c, twin)).collect::<Vec<_>>() });
    let mut best: std::collections::HashMap<String, Value> = Default::default();
    for (code, v) in doors::read_each("/fetch", &page, 8_000) {
        if code != 200 {
            continue;
        }
        for l in v.as_ref().and_then(|v| v["letters"].as_array()).cloned().unwrap_or_default() {
            let Some(sealed) = l["e"].as_str().and_then(unb64) else { continue };
            let Some(plain) = wire::open_boxed(&sealed, &light, l["at"].as_i64().unwrap_or(wire::now_ms() / 1000)) else { continue };
            let f = wire::fields(&plain, 0, 2);
            let Some(o) = f[1].strip_prefix("\u{200B}\u{200B}KP:").and_then(|j| serde_json::from_str::<Value>(j).ok()) else { continue };
            if o["w"].as_str() != Some("light") {
                continue;
            }
            // the newest road of every device and app that lays one (iOS: two apps of one phone are two writers)
            let who = format!("{}/{}", o["v"].as_str().unwrap_or(""), o["a"].as_str().unwrap_or(""));
            if best.get(&who).is_none_or(|b| b["g"].as_i64() < o["g"].as_i64()) {
                best.insert(who, o);
            }
        }
    }
    let mut roads: Vec<Value> = best.into_values().collect();
    roads.sort_by_key(|o| std::cmp::Reverse(o["z"].as_i64().unwrap_or(0)));
    roads.iter().filter_map(|o| {
        let file = fetch_road(o)?;
        (hex(&sha(&[&file])) == o["d"].as_str()?).then_some(())?;
        read_copy(entropy, &file).ok()
    }).collect()
}

/// THE LIGHT COPY LAID (iOS MTKeeping.layLight + nameLight): every block of the archive -- no attachment -- sealed as every
/// copy is, laid on the nodes by the cargo road, and named by one silent letter in the pipe of light under the name «light»
/// (never this person's own reference: the node keeps a letter from the sid that laid it, and every device of the words reads
/// under that reference). Generation `g`; true when a door boxed the letter.
pub fn lay_light(words: &str, archive: &Archive, g: u64, card: Option<Record>) -> bool {
    let Some(light) = seed::role_seed(words, b"mt-keep-light") else { return false };
    let mut records: Vec<Record> = archive.blocks().into_iter().map(|b| Record { kind: KIND_BLOCK, name: String::new(), data: b }).collect();
    if records.is_empty() {
        return false;
    }
    records.extend(card);
    let Some(file) = write_copy(&archive.keys.entropy, &records) else { return false };
    let Some(mut road) = lay_road(&file) else { return false };
    let mut tag = [0u8; 4];
    // SAFETY: the 16-byte device id and a 4-byte buffer
    if unsafe { mt_writer_tag(archive.device.as_ptr(), tag.as_mut_ptr()) } != MT_OK {
        return false;
    }
    road["w"] = json!("light");
    road["g"] = json!(g);
    road["d"] = json!(hex(&sha(&[&file])));
    road["v"] = json!(hex(&tag));
    road["a"] = json!(APP);
    knock(&light, "light", &format!("\u{200B}\u{200B}KP:{road}"))
}

/// A file onto the cargo road (iOS MTKeeping.lay): its pieces sealed under a fresh key, the list of pieces sealed under
/// another and laid by its own name; the road {z, bk, mref, mk}.
pub(crate) fn lay_road(file: &[u8]) -> Option<Value> {
    lay_road_from(&media::Source::Bytes(file))
}

/// The road of a file, a big one laid a piece at a time.
pub(crate) fn lay_road_from(file: &media::Source) -> Option<Value> {
    let bk: [u8; 32] = crypto::random(32)?.try_into().ok()?;
    let pieces = media::upload_from(file, &bk)?;
    let mk = crypto::random(32)?;
    let sealed = crypto::seal(&mk, Value::Array(pieces).to_string().as_bytes())?;
    let mref = hex(&crypto::blob_id(&sealed)?);
    if !doors::put_new_blob(&mref, &sealed) {
        return None;
    }
    Some(json!({ "z": file.len(), "bk": wire::b64(&bk), "mref": mref, "mk": wire::b64(&mk) }))
}

/// A road's file kept under a letter's name: a big one received piece by piece into the store (media::download_into), the
/// rest whole. Its size.
pub(crate) fn fetch_road_into(o: &Value, store: &media::Store, mid: &str) -> Option<u64> {
    if o["z"].as_u64()? <= media::MAX_SEND as u64 {
        let bytes = fetch_road(o)?;
        return store.put(mid, &bytes).then_some(bytes.len() as u64);
    }
    let (mref, mk) = (o["mref"].as_str()?, unb64(o["mk"].as_str()?)?);
    let media::Got::Data(sealed) = media::fetch_blob(mref) else { return None };
    let pieces: Value = serde_json::from_slice(&crypto::open(&mk, &sealed)?).ok()?;
    let m = json!({ "bk": o["bk"], "chunks": pieces });
    media::download_into(&m, store, mid).ok().filter(|z| Some(*z) == o["z"].as_u64())
}

/// One letter into a derived pipe (iOS MTNodeWire.knockLetter): mid‖0 words‖0‖0‖0 padded to one envelope, no author field,
/// silent; the first door that boxes it ends the walk.
pub(crate) fn knock(secret: &[u8], sender: &str, text: &str) -> bool {
    knock_as(secret, sender, text, true)
}

/// The same knock, silent or loud: a loud one rings the keeper's screen (iOS MTKeeping.knock silent: false).
pub(crate) fn knock_as(secret: &[u8], sender: &str, text: &str, silent: bool) -> bool {
    let Some(r) = crypto::random(16) else { return false };
    let h = hex(&r).to_uppercase();
    let mid = format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32]);
    let mut body = [mid.as_bytes(), &[0], text.as_bytes(), &[0, 0, 0]].concat();
    if body.len() > wire::ENVELOPE {
        return false;
    }
    body.resize(wire::ENVELOPE, 0);
    let cw = wire::conv_w(secret, wire::day());
    for door in doors::write_order() {
        let Some(env) = wire::seal(&wire::body_key(secret, wire::minute()), &body) else { return false };
        let req = json!({ "conv": cw, "from_id": wire::sub_id(&cw, sender), "mid": mid, "env": wire::b64(&env), "silent": silent });
        if doors::post_at(&door, "/wake", &req, crate::http::POST_DEADLINE_MS).0 == 200 {
            return true;
        }
    }
    false
}

/// A file by the cargo road (iOS MTKeeping.fetch): the manifest of pieces sealed under «mk» at «mref», each piece checked
/// against its name, opened under «bk», cut to its size; the whole as long as «z» says.
pub(crate) fn fetch_road(o: &Value) -> Option<Vec<u8>> {
    let (mref, mk, bk, z) = (o["mref"].as_str()?, unb64(o["mk"].as_str()?)?, unb64(o["bk"].as_str()?)?, o["z"].as_u64()?);
    let media::Got::Data(sealed) = media::fetch_blob(mref) else { return None };
    let manifest: Value = serde_json::from_slice(&crypto::open(&mk, &sealed)?).ok()?;
    let mut out = Vec::with_capacity(z as usize);
    for p in manifest.as_array()? {
        let (bid, cs) = (p["bid"].as_str()?, p["cs"].as_u64()? as usize);
        let media::Got::Data(s) = media::fetch_blob(bid) else { return None };
        if hex(&sha(&[&s])) != bid {
            return None;
        }
        let mut plain = crypto::open(&bk, &s)?;
        plain.truncate(cs);
        out.extend_from_slice(&plain);
    }
    (out.len() as u64 == z).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::b64;

    #[test]
    fn the_card_carries_the_persons_own_words_and_reads_back() {
        let card = card_record(&[("userName", "Алиса".into()), ("profileBio", String::new()), ("profileLink", "https://a.example".into())]).unwrap();
        assert_eq!(card.kind, KIND_CARD);
        let v: Value = serde_json::from_slice(&card.data).unwrap();
        assert_eq!(v, json!({ "s:userName": "Алиса", "s:profileLink": "https://a.example" }), "the iPhone's own tags; nothing empty");
        // an iPhone's card holds its whole store: Windows takes the words it keeps, in pieces as they came
        let ios = br#"{"s:userName":"Bob","n:notifSound":"1","d:mt_chat_rows":"W10=","s:profileBio":"hi"}"#;
        let pieces = [Record { kind: KIND_BLOCK, name: String::new(), data: vec![1] },
                      Record { kind: KIND_CARD, name: String::new(), data: ios[..20].to_vec() },
                      Record { kind: KIND_CARD, name: String::new(), data: ios[20..].to_vec() }];
        assert_eq!(card_words(&pieces), vec![("userName", "Bob".to_string()), ("profileBio", "hi".to_string())]);
        assert!(card_record(&[("userName", String::new())]).is_none());
    }

    #[test]
    fn the_copys_keys_and_name_are_ios_own() {
        let counting: Vec<u8> = (0..32).collect();
        let after: Vec<u8> = (32..64).collect();
        assert_eq!(hex(&hkdf(&[0x55; 32], &[0; 32], b"mt-backup-key-v1")), "bdd50e3824fb05ed88e25d379fa70b2de845cc5de0d27f037d201b39a9fb6792");
        assert_eq!(hex(&hkdf(&counting, &after, b"mt-backup-key-v1")), "cb836de01e5c7468cf1b7f8e4c604a1d8ff5af1a2f683e9d9ea091713d04e6dd");
        assert_eq!(hex(&copy_key(&counting, &after)), "ec63f219255c63640c9916705b59e10f71ec3f8a296bb048db4ed08ed4ad48e4");
        assert_eq!(hex(&hkdf(&counting, &[], b"mt-backup-owner-v1")), "a07f0e82f8b0d5a375684f7b23a9e8a5d9015b4207620f869c9c6aa1e28750bc");
        assert_eq!(copy_name(&counting, "2026-09-23-143542"), "montana-2026-09-23-143542-fc4380015be1598a.mtbak");
    }

    #[test]
    fn a_copy_reads_back_whole_and_a_cut_or_strange_one_is_refused() {
        let e = [9u8; 32];
        let big: Vec<u8> = (0..2_500_000u32).map(|i| (i % 241) as u8).collect();
        let recs = vec![
            Record { kind: KIND_BLOCK, name: String::new(), data: vec![1, 2, 3] },
            Record { kind: KIND_STORE, name: "a.jpg".into(), data: big },
            Record { kind: KIND_BLOCK, name: String::new(), data: vec![4; 10] },
        ];
        let file = write_copy(&e, &recs).unwrap();
        assert_eq!((file.len() - 32) % FRAME, 0, "every frame one length");
        assert_eq!(read_copy(&e, &file).unwrap(), recs);
        assert_eq!(read_copy(&[8u8; 32], &file), Err(Refusal::Unopened), "other words open nothing");
        assert!(read_copy(&e, &file[..file.len() - FRAME]).is_err(), "a copy cut at a frame's edge is told from a whole one");
    }

    #[test]
    fn the_archive_keeps_a_head_and_letters_and_a_copy_gives_the_pipe_back() {
        let root = std::env::temp_dir().join(format!("montana-history-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let a = Archive::new(&root.join("a"), keys(&words).unwrap(), [1; 16]);
        let secret = vec![5u8; 32];
        let r = wire::reference(&secret);
        assert!(a.append(&r, HEAD_DIR, 100, format!("s:{}", b64(&secret)).as_bytes()));
        assert!(a.append(&r, HEAD_DIR, 101, "n:Боб".as_bytes()));
        assert!(a.append(&r, 1, 102, "привет".as_bytes()));
        assert!(a.append(&r, 0, 103, "и тебе".as_bytes()));
        // their face sealed beside the letters (iOS saveAvatar): it opens under these words and is its own folder's alone
        assert!(a.put_media(&r, FACE_BLOB, b"their face"));
        assert_eq!(a.get_media(&label(&a.keys.hk, &r), FACE_BLOB).as_deref(), Some(&b"their face"[..]));
        assert_eq!(a.get_media("another", FACE_BLOB), None);
        let blocks = a.blocks();
        assert!(!blocks.is_empty());
        let items: Vec<Item> = blocks.iter().flat_map(|b| a.open_block(b)).collect();
        assert_eq!(items.iter().filter(|i| i.dir != HEAD_DIR).count(), 2);
        // a new machine, the same words: the copy gives the pipe, the name and the letters back
        let v = crate::vault::Vault::at(&root.join("v")).unwrap();
        let book = Book::new(v);
        let store = media::Store::at(&root.join("m")).unwrap();
        let file = make_copy(&a, &Book::new(crate::vault::Vault::at(&root.join("v0")).unwrap()), &store, None).unwrap();
        let b = Archive::new(&root.join("b"), keys(&words).unwrap(), [2; 16]);
        let faces = media::Store::at(&root.join("f")).unwrap();
        let done = restore(&b, &book, &store, Some(&faces), &read_copy(&keys(&words).unwrap().entropy, &file).unwrap());
        assert_eq!(done, Restored { chats: 1, records: 2, media: 0, faces: 1 });
        assert_eq!(faces.get(&r).as_deref(), Some(&b"their face"[..]), "the face rides with the letters");
        assert_eq!(book.chat(&r).unwrap().face_at, 1);
        assert_eq!(book.secret(&r), Some(secret));
        let c = book.chat(&r).unwrap();
        assert_eq!((c.name.as_str(), c.msgs.len(), c.msgs[0].text.as_str(), c.msgs[1].mine), ("Боб", 2, "привет", true));
        assert_eq!(restore(&b, &book, &store, Some(&faces), &read_copy(&keys(&words).unwrap().entropy, &file).unwrap()), Restored::default(), "twice is once");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_copy_on_a_living_feed_fills_its_gaps_only_and_keeps_what_no_head_names() {
        let root = std::env::temp_dir().join(format!("montana-history-gap-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let a = Archive::new(&root.join("a"), keys(&words).unwrap(), [1; 16]);
        let (open, closed) = (vec![5u8; 32], vec![6u8; 32]);
        let (r, rc) = (wire::reference(&open), wire::reference(&closed));
        assert!(a.append(&r, HEAD_DIR, 100, format!("s:{}", b64(&open)).as_bytes()));
        assert!(a.append(&r, 1, 102, "привет".as_bytes()));
        assert!(a.append(&r, 0, 103, "и тебе".as_bytes()));
        assert!(a.append(&r, 1, 104, "удалённое здесь".as_bytes()));
        // a pipe closed at the other end, and a folder no head names (a group's)
        assert!(a.append(&rc, HEAD_DIR, 100, format!("s:{}", b64(&closed)).as_bytes()));
        assert!(a.append(&rc, HEAD_DIR, 101, "n:Ушедший".as_bytes()));
        assert!(a.append(&rc, HEAD_DIR, 105, "x:".as_bytes()));
        assert!(a.append(&rc, 1, 106, "последнее".as_bytes()));
        assert!(a.append("grp:someone", 1, 107, "в группе".as_bytes()));
        let store = media::Store::at(&root.join("m")).unwrap();
        let file = make_copy(&a, &Book::new(crate::vault::Vault::at(&root.join("v0")).unwrap()), &store, None).unwrap();
        // the living feed: the same letters under their wire names, one deleted here, nothing of the closed pipe
        let book = Book::new(crate::vault::Vault::at(&root.join("v")).unwrap());
        assert!(book.establish(&open).is_some());
        let (m1, m2, m3) = ("t102000-A".to_string(), "t103000-B".to_string(), "t104000-C".to_string());
        book.edit(&r, |c| {
            c.msgs.push(Msg { mid: m1.clone(), text: "привет".into(), mine: false, at: 102_000, ..Default::default() });
            c.msgs.push(Msg { mid: m2.clone(), text: "и тебе".into(), mine: true, at: 103_000, ..Default::default() });
            c.msgs.push(Msg { mid: m3.clone(), text: "удалённое здесь".into(), mine: false, at: 104_000, ..Default::default() });
            c.bury(&m3);
        });
        let b = Archive::new(&root.join("b"), keys(&words).unwrap(), [2; 16]);
        restore(&b, &book, &store, None, &read_copy(&keys(&words).unwrap().entropy, &file).unwrap());
        let c = book.chat(&r).unwrap();
        assert_eq!(c.msgs.iter().map(|m| m.mid.as_str()).collect::<Vec<_>>(), [m1.as_str(), m2.as_str()], "no letter twice, the deleted stays deleted");
        // the closed pipe stands by its name with its letters, never answered; the unnamed folder is kept whole in the archive
        let gone = book.chat(&rc).expect("the closed pipe's history stands");
        assert_eq!((gone.name.as_str(), gone.msgs.len()), ("Ушедший", 1));
        assert!(book.secret(&rc).is_none(), "a closed pipe is not revived");
        let unnamed = hex(&sha(&[b"grp:someone"]));
        assert!(b.folders().contains(&unnamed), "the block no head names is kept under its conversation's SHA-256");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_copy_leaves_out_what_the_person_planned_out() {
        let root = std::env::temp_dir().join(format!("montana-history-plan-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let words = seed::generate().unwrap();
        let a = Archive::new(&root.join("a"), keys(&words).unwrap(), [1; 16]);
        let (ra, rb) = (wire::reference(&[5u8; 32]), wire::reference(&[6u8; 32]));
        for (r, said) in [(&ra, "с Анной"), (&rb, "с Борисом")] {
            assert!(a.append(r, HEAD_DIR, 100, format!("s:{}", b64(&[0u8; 32])).as_bytes()));
            assert!(a.append(r, 1, 102, said.as_bytes()));
        }
        let book = Book::new(crate::vault::Vault::at(&root.join("v")).unwrap());
        let store = media::Store::at(&root.join("m")).unwrap();
        let letter = |r: &str, mid: &str, k: &str, bytes: &[u8]| {
            assert!(store.put(mid, bytes));
            let text = format!("{}{}", media::MARK, json!({ "k": k, "e": if k == "img" { "jpg" } else { "pdf" }, "sz": bytes.len() }));
            book.edit(r, |c| c.msgs.push(Msg { mid: mid.into(), text, mine: true, ..Default::default() }));
        };
        letter(&ra, "t1-a-photo", "img", b"photo of Anna");
        letter(&ra, "t2-a-file", "doc", b"file of Anna");
        letter(&rb, "t3-b-file", "doc", b"file of Boris");
        let names = |file: &[u8]| -> (usize, Vec<String>) {
            let recs = read_copy(&keys(&words).unwrap().entropy, file).unwrap();
            let blocks = recs.iter().filter(|r| r.kind == KIND_BLOCK).count();
            let mut files: Vec<String> = recs.iter().filter(|r| r.kind == KIND_STORE).map(|r| String::from_utf8_lossy(&r.data).to_string()).collect();
            files.sort();
            (blocks, files)
        };
        let whole = names(&make_copy(&a, &book, &store, None).unwrap());
        assert_eq!(whole.1, ["file of Anna", "file of Boris", "photo of Anna"], "everything goes by default");
        // Boris's conversation left out: none of its blocks, none of its files; photos left out: Anna's photo stays home
        let plan = Plan { skip_chats: vec![rb.clone()], skip_kinds: vec!["photo".into()], skip_files: vec![] };
        let planned = names(&make_copy_planned(&a, &book, &store, None, &plan, &Default::default()).unwrap());
        assert_eq!(planned.1, ["file of Anna"]);
        assert!(planned.0 < whole.0, "the blocks of the conversation left out are not read: {} of {}", planned.0, whole.0);
        // one file left out on its own
        let one = Plan { skip_files: vec![file_name("t2-a-file", &book.chat(&ra).unwrap().msgs[1].text)], ..Plan::default() };
        assert_eq!(names(&make_copy_planned(&a, &book, &store, None, &one, &Default::default()).unwrap()).1, ["file of Boris", "photo of Anna"]);
        let v = crate::vault::Vault::at(&root.join("v")).unwrap();
        assert!(plan.save(&v));
        assert_eq!(Plan::load(&v), plan, "the plan is kept on this computer");
        let _ = std::fs::remove_dir_all(&root);
    }
}
