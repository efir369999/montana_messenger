//! Stage 1 (second front — data decentralization) — history archive.
//! HistoryBlock = block_seq u64 LE ‖ item_count u32 LE
//!   ‖ [ conv_id 32 ‖ dir 1 ‖ send_time u64 LE ‖ content_len u32 LE ‖ Content ]×item_count
//! writer_tag = SHA-256("mt-history-writer" ‖ 0x00 ‖ device_id)[0:4] — splits nonce across writers under one history_key.
//! nonce  = block_seq_le8 (8) ‖ writer_tag (4) = 12 B; sealed = nonce ‖ ChaCha20-Poly1305(history_key, nonce, block,
//!          AD = "mt-history" ‖ 0x00 ‖ account_id).  H(HistoryBlock) = SHA-256(open block) — stable across reseal (Stage 2/6).
//! history_key = HKDF-SHA-256(0×32, entropy_32, "mt-history-key", 32) — SSOT (first front, Stage 12).
//! media_key   = HKDF-SHA-256(0×32, entropy_32, "mt-media-key", 32)  — separate seed branch (≠ history_key).
//! block_seq — global counter per-identity (seq.bin in base), not per-chat: otherwise nonce reuse (spec s.2 v0.3.1).
//! Parsing is invalid-safe (Gate 13): any violation → None, NEVER panic.

use crate::kdf::hkdf_sha256;
use crate::ratchet::{open, seal};
use mt_codec::domain::{
    MSG_HISTORY, MSG_HISTORY_KEY, MSG_HISTORY_WRITER, MSG_MEDIA_KEY, MSG_MEDIA_VAULT,
};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

pub const CONV_ID_LEN: usize = 32;
pub const DIR_OUT: u8 = 0x00;
pub const DIR_IN: u8 = 0x01;
pub const SEQ_FILE: &str = "seq.bin";

pub fn history_key(entropy_32: &[u8; 32]) -> [u8; 32] {
    let k = hkdf_sha256(&[0u8; 32], entropy_32, MSG_HISTORY_KEY, 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&k);
    out
}

/// Separate seed branch for media at-rest — does not overlap with history_key (different nonce spaces).
pub fn media_key(entropy_32: &[u8; 32]) -> [u8; 32] {
    let k = hkdf_sha256(&[0u8; 32], entropy_32, MSG_MEDIA_KEY, 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&k);
    out
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryItem {
    pub conv_id: [u8; CONV_ID_LEN],
    pub dir: u8,
    pub send_time: u64,
    pub content: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryBlock {
    pub block_seq: u64,
    pub items: Vec<HistoryItem>,
}

pub fn encode_block(b: &HistoryBlock) -> Vec<u8> {
    let mut o = Vec::new();
    o.extend_from_slice(&b.block_seq.to_le_bytes());
    o.extend_from_slice(&(b.items.len() as u32).to_le_bytes());
    for it in &b.items {
        o.extend_from_slice(&it.conv_id);
        o.push(it.dir);
        o.extend_from_slice(&it.send_time.to_le_bytes());
        o.extend_from_slice(&(it.content.len() as u32).to_le_bytes());
        o.extend_from_slice(&it.content);
    }
    o
}

pub fn decode_block(buf: &[u8]) -> Option<HistoryBlock> {
    if buf.len() < 12 {
        return None;
    }
    let block_seq = u64::from_le_bytes(buf[0..8].try_into().ok()?);
    let item_count = u32::from_le_bytes(buf[8..12].try_into().ok()?) as usize;
    let mut off = 12usize;
    let mut items = Vec::new();
    for _ in 0..item_count {
        if off + 32 + 1 + 8 + 4 > buf.len() {
            return None;
        }
        let mut conv_id = [0u8; CONV_ID_LEN];
        conv_id.copy_from_slice(&buf[off..off + 32]);
        off += 32;
        let dir = buf[off];
        off += 1;
        let send_time = u64::from_le_bytes(buf[off..off + 8].try_into().ok()?);
        off += 8;
        let content_len = u32::from_le_bytes(buf[off..off + 4].try_into().ok()?) as usize;
        off += 4;
        if off + content_len > buf.len() {
            return None;
        }
        let content = buf[off..off + content_len].to_vec();
        off += content_len;
        items.push(HistoryItem {
            conv_id,
            dir,
            send_time,
            content,
        });
    }
    if off != buf.len() {
        return None;
    }
    Some(HistoryBlock { block_seq, items })
}

/// writer_tag = SHA-256("mt-history-writer" ‖ 0x00 ‖ device_id)[0:4]. Splits the nonce space across
/// writers sharing one history_key (multiple devices of one seed, DeviceRegistry): different writers
/// differ by writer_tag, one writer stays monotonic by block_seq → nonce reuse is impossible.
pub fn writer_tag(device_id: &[u8; 16]) -> [u8; 4] {
    let mut h = Sha256::new();
    h.update(MSG_HISTORY_WRITER);
    h.update([0x00]);
    h.update(device_id);
    let d: [u8; 32] = h.finalize().into();
    [d[0], d[1], d[2], d[3]]
}

fn block_nonce(block_seq: u64, writer_tag: &[u8; 4]) -> [u8; 12] {
    let mut n = [0u8; 12];
    n[0..8].copy_from_slice(&block_seq.to_le_bytes());
    n[8..12].copy_from_slice(writer_tag);
    n
}

fn history_ad(account_id: &[u8; 32]) -> Vec<u8> {
    let mut ad = MSG_HISTORY.to_vec();
    ad.push(0x00);
    ad.extend_from_slice(account_id);
    ad
}

pub fn seal_block(
    history_key: &[u8; 32],
    account_id: &[u8; 32],
    device_id: &[u8; 16],
    b: &HistoryBlock,
) -> Vec<u8> {
    let nonce = block_nonce(b.block_seq, &writer_tag(device_id));
    let pt = encode_block(b);
    let ct = seal(history_key, &nonce, &pt, &history_ad(account_id));
    let mut out = Vec::with_capacity(12 + ct.len());
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&ct);
    out
}

pub fn open_block(
    history_key: &[u8; 32],
    account_id: &[u8; 32],
    sealed: &[u8],
) -> Option<HistoryBlock> {
    if sealed.len() < 12 {
        return None;
    }
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&sealed[..12]);
    let pt = open(history_key, &nonce, &sealed[12..], &history_ad(account_id))?;
    let block = decode_block(&pt)?;
    // Self-consistency: the block_seq half of the nonce must match the decoded block_seq.
    // The writer_tag half (nonce[8..12]) is stored as-is — read back without recomputation.
    if nonce[0..8] != block.block_seq.to_le_bytes() {
        return None;
    }
    Some(block)
}

fn media_ad(account_id: &[u8; 32]) -> Vec<u8> {
    let mut ad = MSG_MEDIA_VAULT.to_vec();
    ad.push(0x00);
    ad.extend_from_slice(account_id);
    ad
}

fn media_nonce(blob_ref: &str) -> [u8; 12] {
    let h: [u8; 32] = Sha256::digest(blob_ref.as_bytes()).into();
    let mut n = [0u8; 12];
    n.copy_from_slice(&h[..12]);
    n
}

/// Seal media under media_key (≠ history_key). blob_ref — unique blob label → unique nonce.
pub fn seal_media(
    media_key: &[u8; 32],
    account_id: &[u8; 32],
    blob_ref: &str,
    plaintext: &[u8],
) -> Vec<u8> {
    let nonce = media_nonce(blob_ref);
    let ct = seal(media_key, &nonce, plaintext, &media_ad(account_id));
    let mut out = Vec::with_capacity(12 + ct.len());
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&ct);
    out
}

pub fn open_media(media_key: &[u8; 32], account_id: &[u8; 32], sealed: &[u8]) -> Option<Vec<u8>> {
    if sealed.len() < 12 {
        return None;
    }
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&sealed[..12]);
    open(media_key, &nonce, &sealed[12..], &media_ad(account_id))
}

pub fn sealed_block_id(sealed: &[u8]) -> [u8; 32] {
    Sha256::digest(sealed).into()
}

/// writer_tag of a sealed block (nonce[8..12]) — the block's writer identity for (writer_tag, block_seq)
/// dedup/order (Stage 2/4). None if the buffer is shorter than the 12-byte nonce.
pub fn block_writer_tag(sealed: &[u8]) -> Option<[u8; 4]> {
    if sealed.len() < 12 {
        return None;
    }
    Some([sealed[8], sealed[9], sealed[10], sealed[11]])
}

/// block_seq of a sealed block (nonce[0..8], u64 LE). None if the buffer is shorter than the nonce.
pub fn block_seq_of(sealed: &[u8]) -> Option<u64> {
    if sealed.len() < 12 {
        return None;
    }
    Some(u64::from_le_bytes(sealed[0..8].try_into().ok()?))
}

/// H(HistoryBlock) = SHA-256(open block) — over the canonical encoding of the open block, before seal.
/// Stable across reseal (Stage 6): ArchiveRoot (Stage 2) and anchor check (Stage 7) do not depend on
/// which device's key sealed the slice. Feeds the Merkle leaf ("mt-msg-leaf" ‖ 0x00 ‖ H(HistoryBlock)).
pub fn block_hash(b: &HistoryBlock) -> [u8; 32] {
    Sha256::digest(encode_block(b)).into()
}

/// conv_id of a sealed block (decrypt + first item). One block — exactly one conv_id (Stage 1
/// invariant), so the first item identifies the chat for routing. None on decrypt failure or an
/// empty block.
pub fn peek_conv(history_key: &[u8; 32], account_id: &[u8; 32], sealed: &[u8]) -> Option<[u8; 32]> {
    let b = open_block(history_key, account_id, sealed)?;
    b.items.first().map(|it| it.conv_id)
}

// ============ ArchiveStore — local hierarchy "Montana/Chats/<chat name>/" ============
// Mirrors the app structure: <base>/Chats/<label>/conversation.mtlog + <base>/Chats/<label>/Media/<blob_ref>.
// Label (folder name) is user-navigable; log contents are sealed (at-rest, seed required).
// The global block_seq counter is stored in <base>/seq.bin (per-identity, not per-chat).

pub const CHATS_DIR: &str = "Chats";
pub const MEDIA_DIR: &str = "Media";
pub const LOG_FILE: &str = "conversation.mtlog";

pub struct ArchiveStore {
    base: PathBuf,
}

fn sanitize(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '\0' => '_',
            c => c,
        })
        .collect();
    let t = cleaned.trim().trim_matches('.').trim();
    if t.is_empty() {
        "_".to_string()
    } else {
        t.to_string()
    }
}

impl ArchiveStore {
    pub fn open(base: impl AsRef<Path>) -> io::Result<Self> {
        let base = base.as_ref().to_path_buf();
        fs::create_dir_all(base.join(CHATS_DIR))?;
        Ok(Self { base })
    }

    fn chat_dir(&self, chat_name: &str) -> PathBuf {
        self.base.join(CHATS_DIR).join(sanitize(chat_name))
    }

    /// Assign the next global block_seq (per-identity): reads seq.bin, returns the current value,
    /// stores current+1 atomically (write tmp → rename). First call → 0.
    pub fn next_block_seq(&self) -> io::Result<u64> {
        let path = self.base.join(SEQ_FILE);
        let cur = match fs::read(&path) {
            Ok(d) if d.len() >= 8 => u64::from_le_bytes(d[..8].try_into().unwrap()),
            _ => 0,
        };
        let next = cur
            .checked_add(1)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "block_seq overflow"))?;
        let tmp = self.base.join("seq.bin.tmp");
        fs::write(&tmp, next.to_le_bytes())?;
        fs::rename(&tmp, &path)?;
        Ok(cur)
    }

    /// Single entry point for writing one item into the archive: the core assigns block_seq (counter SSOT),
    /// builds a single-item HistoryBlock, seals under history_key, appends to the chat log.
    /// Returns the assigned block_seq.
    #[allow(clippy::too_many_arguments)]
    pub fn append_item(
        &self,
        chat_name: &str,
        history_key: &[u8; 32],
        account_id: &[u8; 32],
        device_id: &[u8; 16],
        conv_id: &[u8; 32],
        dir: u8,
        send_time: u64,
        content: &[u8],
    ) -> io::Result<u64> {
        let seq = self.next_block_seq()?;
        let block = HistoryBlock {
            block_seq: seq,
            items: vec![HistoryItem {
                conv_id: *conv_id,
                dir,
                send_time,
                content: content.to_vec(),
            }],
        };
        let sealed = seal_block(history_key, account_id, device_id, &block);
        self.append_block(chat_name, &sealed)?;
        Ok(seq)
    }

    /// Append a sealed block to the chat log: <base>/Chats/<label>/conversation.mtlog (length-prefixed u32 LE ‖ sealed).
    pub fn append_block(&self, chat_name: &str, sealed_block: &[u8]) -> io::Result<()> {
        let dir = self.chat_dir(chat_name);
        fs::create_dir_all(&dir)?;
        let mut f = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(dir.join(LOG_FILE))?;
        f.write_all(&(sealed_block.len() as u32).to_le_bytes())?;
        f.write_all(sealed_block)?;
        Ok(())
    }

    /// Read all sealed blocks of the chat log in order.
    pub fn read_blocks(&self, chat_name: &str) -> io::Result<Vec<Vec<u8>>> {
        let path = self.chat_dir(chat_name).join(LOG_FILE);
        let data = match fs::read(&path) {
            Ok(d) => d,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(vec![]),
            Err(e) => return Err(e),
        };
        let mut out = Vec::new();
        let mut off = 0usize;
        while off + 4 <= data.len() {
            let len = u32::from_le_bytes(data[off..off + 4].try_into().unwrap()) as usize;
            off += 4;
            if off + len > data.len() {
                break;
            }
            out.push(data[off..off + len].to_vec());
            off += len;
        }
        Ok(out)
    }

    /// Encrypt media under media_key and store it in <base>/Chats/<label>/Media/<blob_ref>.
    /// Other apps see only ciphertext; only the client decrypts using the seed.
    pub fn put_media(
        &self,
        chat_name: &str,
        blob_ref: &str,
        media_key: &[u8; 32],
        account_id: &[u8; 32],
        plaintext: &[u8],
    ) -> io::Result<()> {
        let mdir = self.chat_dir(chat_name).join(MEDIA_DIR);
        fs::create_dir_all(&mdir)?;
        let sealed = seal_media(media_key, account_id, blob_ref, plaintext);
        fs::write(mdir.join(sanitize(blob_ref)), sealed)
    }

    /// Read and decrypt media. None if the file is missing or decryption failed.
    pub fn get_media(
        &self,
        chat_name: &str,
        blob_ref: &str,
        media_key: &[u8; 32],
        account_id: &[u8; 32],
    ) -> Option<Vec<u8>> {
        let path = self
            .chat_dir(chat_name)
            .join(MEDIA_DIR)
            .join(sanitize(blob_ref));
        let sealed = fs::read(path).ok()?;
        open_media(media_key, account_id, &sealed)
    }

    pub fn media_path(&self, chat_name: &str, blob_ref: &str) -> PathBuf {
        self.chat_dir(chat_name)
            .join(MEDIA_DIR)
            .join(sanitize(blob_ref))
    }

    /// Export this writer's sealed blocks of one chat with block_seq >= from_seq, as the on-disk
    /// length-prefixed stream (u32 LE ‖ sealed)×N — transport framing for block replication (Stage 3/4).
    pub fn export_mine(
        &self,
        chat_name: &str,
        writer_tag: &[u8; 4],
        from_seq: u64,
    ) -> io::Result<Vec<u8>> {
        let mut out = Vec::new();
        for sealed in self.read_blocks(chat_name)? {
            let (Some(wt), Some(seq)) = (block_writer_tag(&sealed), block_seq_of(&sealed)) else {
                continue;
            };
            if &wt == writer_tag && seq >= from_seq {
                out.extend_from_slice(&(sealed.len() as u32).to_le_bytes());
                out.extend_from_slice(&sealed);
            }
        }
        Ok(out)
    }

    /// Ingest a replicated sealed block as-stored (Stage 4): AEAD-authenticate under history_key,
    /// dedup by (writer_tag, block_seq) within the chat's log, append unchanged (identity preserved —
    /// ArchiveRoot converges across devices). Ok(true)=appended, Ok(false)=duplicate.
    pub fn ingest_block(
        &self,
        chat_name: &str,
        history_key: &[u8; 32],
        account_id: &[u8; 32],
        sealed: &[u8],
    ) -> io::Result<bool> {
        if open_block(history_key, account_id, sealed).is_none() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "sealed block does not authenticate",
            ));
        }
        let (Some(wt), Some(seq)) = (block_writer_tag(sealed), block_seq_of(sealed)) else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "short sealed block",
            ));
        };
        for existing in self.read_blocks(chat_name)? {
            if block_writer_tag(&existing) == Some(wt) && block_seq_of(&existing) == Some(seq) {
                return Ok(false);
            }
        }
        self.append_block(chat_name, sealed)?;
        Ok(true)
    }

    /// ArchiveRoot over the whole local archive (all chat logs under Chats/): ingest every sealed block
    /// into an index keyed by (writer_tag, block_seq), fold the Merkle root (Stage 2). None when empty.
    /// This is the local archive fingerprint the app anchors and compares across devices for convergence.
    pub fn archive_root(
        &self,
        history_key: &[u8; 32],
        account_id: &[u8; 32],
    ) -> io::Result<Option<[u8; 32]>> {
        let mut idx = crate::reconcile::ArchiveIndex::new();
        let chats = self.base.join(CHATS_DIR);
        let dir = match fs::read_dir(&chats) {
            Ok(d) => d,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(e),
        };
        for entry in dir.flatten() {
            let label = match entry.file_name().into_string() {
                Ok(l) => l,
                Err(_) => continue,
            };
            for sealed in self.read_blocks(&label)? {
                idx.ingest_sealed(history_key, account_id, &sealed);
            }
        }
        Ok(idx.archive_root())
    }

    /// Migrate the chat folder when the label is renamed (conversation identity = conv_address, not the label).
    pub fn rename_chat(&self, old_label: &str, new_label: &str) -> io::Result<()> {
        let so = sanitize(old_label);
        let sn = sanitize(new_label);
        if so == sn {
            return Ok(());
        }
        let src = self.base.join(CHATS_DIR).join(&so);
        let dst = self.base.join(CHATS_DIR).join(&sn);
        if src.exists() && !dst.exists() {
            fs::rename(&src, &dst)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEV: [u8; 16] = [0x44u8; 16];

    fn sample_block() -> HistoryBlock {
        HistoryBlock {
            block_seq: 0,
            items: vec![HistoryItem {
                conv_id: [0x22u8; 32],
                dir: DIR_OUT,
                send_time: 1000,
                content: b"montana".to_vec(),
            }],
        }
    }

    #[test]
    fn history_key_kat() {
        let hk = history_key(&[0x55u8; 32]);
        assert_eq!(
            hex::encode(hk),
            "e6a7dc51003770589d9f731c1231c1523be7348c7769383875dd34bd6c578def"
        );
    }

    #[test]
    fn media_key_differs_from_history_key() {
        let ent = [0x55u8; 32];
        assert_ne!(
            history_key(&ent),
            media_key(&ent),
            "key branches must differ"
        );
    }

    #[test]
    fn block_roundtrip() {
        let b = sample_block();
        let enc = encode_block(&b);
        assert_eq!(decode_block(&enc), Some(b));
    }

    #[test]
    fn decode_trailing_rejected() {
        let mut enc = encode_block(&sample_block());
        enc.push(0xff);
        assert_eq!(decode_block(&enc), None);
    }

    #[test]
    fn decode_truncated_rejected() {
        let enc = encode_block(&sample_block());
        assert_eq!(decode_block(&enc[..enc.len() - 1]), None);
    }

    #[test]
    fn seal_open_roundtrip() {
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let b = sample_block();
        let sealed = seal_block(&hk, &acct, &DEV, &b);
        assert_eq!(open_block(&hk, &acct, &sealed), Some(b));
    }

    #[test]
    fn seal_deterministic() {
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let b = sample_block();
        assert_eq!(
            seal_block(&hk, &acct, &DEV, &b),
            seal_block(&hk, &acct, &DEV, &b)
        );
    }

    #[test]
    fn open_wrong_account_fails() {
        let hk = history_key(&[0x55u8; 32]);
        let b = sample_block();
        let sealed = seal_block(&hk, &[0x33u8; 32], &DEV, &b);
        assert_eq!(open_block(&hk, &[0x44u8; 32], &sealed), None);
    }

    #[test]
    fn media_seal_open_roundtrip() {
        let mk = media_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let sealed = seal_media(&mk, &acct, "voice_abc", b"\x89PNG demo");
        assert_eq!(
            open_media(&mk, &acct, &sealed),
            Some(b"\x89PNG demo".to_vec())
        );
    }

    #[test]
    fn media_wrong_key_fails() {
        let mk = media_key(&[0x55u8; 32]);
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let sealed = seal_media(&mk, &acct, "voice_abc", b"secret");
        // history_key does NOT open media (separate branches)
        assert_eq!(open_media(&hk, &acct, &sealed), None);
    }

    #[test]
    fn writer_tag_kat() {
        // spec §79/§81: device_id=44×16 → writer_tag=0efd9315.
        assert_eq!(hex::encode(writer_tag(&[0x44u8; 16])), "0efd9315");
    }

    #[test]
    fn history_block_kat() {
        // spec §81: entropy=55×32; block_seq=0, one item conv_id=22×32, dir=0x00, send_time=1000,
        // Content=text(msg_id=11×16, sent_at=2000, reply_to=0×16, "montana"); account_id=33×32;
        // device_id=44×16 → writer_tag=0efd9315 → nonce=00000000000000000efd9315; sealed 137 B.
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let content = crate::content::encode_text(&[0x11u8; 16], 2000, &[0x00u8; 16], b"montana");
        let block = HistoryBlock {
            block_seq: 0,
            items: vec![HistoryItem {
                conv_id: [0x22u8; 32],
                dir: DIR_OUT,
                send_time: 1000,
                content,
            }],
        };
        let sealed = seal_block(&hk, &acct, &[0x44u8; 16], &block);
        assert_eq!(
            &sealed[..12],
            &hex::decode("00000000000000000efd9315").unwrap()[..]
        );
        assert_eq!(sealed.len(), 137);
        assert_eq!(
            hex::encode(sealed_block_id(&sealed)),
            "fcbbe5c859fdc99d564c22ea9e4519cf58183f43e7456320aacbb9481bbfcd73"
        );
        // open round-trips, and (writer_tag, block_seq) are recoverable from the sealed prefix.
        assert_eq!(open_block(&hk, &acct, &sealed).as_ref(), Some(&block));
        assert_eq!(block_writer_tag(&sealed), Some([0x0e, 0xfd, 0x93, 0x15]));
        assert_eq!(block_seq_of(&sealed), Some(0));
    }

    #[test]
    fn two_writers_no_nonce_reuse() {
        // Same history_key, same block_seq, different device → different nonce (writer_tag differs).
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let b = sample_block();
        let sa = seal_block(&hk, &acct, &[0x01u8; 16], &b);
        let sb = seal_block(&hk, &acct, &[0x02u8; 16], &b);
        assert_ne!(&sa[..12], &sb[..12], "writer_tag must split the nonce");
        assert_ne!(block_writer_tag(&sa), block_writer_tag(&sb));
        assert_eq!(block_seq_of(&sa), block_seq_of(&sb)); // same seq, safe under distinct writer_tag
    }

    #[test]
    fn block_hash_stable_over_open_block() {
        // H(HistoryBlock) = SHA-256(open block) — independent of which device sealed it.
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let b = sample_block();
        let h = block_hash(&b);
        let s1 = seal_block(&hk, &acct, &[0x01u8; 16], &b);
        let s2 = seal_block(&hk, &acct, &[0x02u8; 16], &b);
        assert_eq!(block_hash(&open_block(&hk, &acct, &s1).unwrap()), h);
        assert_eq!(block_hash(&open_block(&hk, &acct, &s2).unwrap()), h);
    }

    #[test]
    fn seq_counter_monotonic_across_chats() {
        let tmp = std::env::temp_dir().join("mt_archive_seq_test");
        let _ = fs::remove_dir_all(&tmp);
        let st = ArchiveStore::open(&tmp).unwrap();
        // global counter: different chats do not reset seq
        assert_eq!(st.next_block_seq().unwrap(), 0);
        assert_eq!(st.next_block_seq().unwrap(), 1);
        assert_eq!(st.next_block_seq().unwrap(), 2);
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn append_item_assigns_global_seq() {
        let tmp = std::env::temp_dir().join("mt_archive_append_item_test");
        let _ = fs::remove_dir_all(&tmp);
        let st = ArchiveStore::open(&tmp).unwrap();
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let conv_a = [0x01u8; 32];
        let conv_b = [0x02u8; 32];
        // chat A first message → seq 0; chat B first → seq 1 (NOT 0 — no nonce reuse)
        let s0 = st
            .append_item("Alice", &hk, &acct, &DEV, &conv_a, DIR_OUT, 1000, b"hi")
            .unwrap();
        let s1 = st
            .append_item("Bob", &hk, &acct, &DEV, &conv_b, DIR_OUT, 1001, b"yo")
            .unwrap();
        assert_eq!(s0, 0);
        assert_eq!(s1, 1);
        // read chat B's block — seq 1
        let blocks_b = st.read_blocks("Bob").unwrap();
        assert_eq!(blocks_b.len(), 1);
        let blk = open_block(&hk, &acct, &blocks_b[0]).unwrap();
        assert_eq!(blk.block_seq, 1);
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn store_hierarchy_roundtrip() {
        let tmp = std::env::temp_dir().join("mt_archive_test_store");
        let _ = fs::remove_dir_all(&tmp);
        let st = ArchiveStore::open(&tmp).unwrap();
        let hk = history_key(&[0x55u8; 32]);
        let mk = media_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];

        let sealed = seal_block(&hk, &acct, &DEV, &sample_block());
        st.append_block("Alice", &sealed).unwrap();
        st.put_media("Alice", "voice_ref", &mk, &acct, b"\x89PNG demo")
            .unwrap();

        // hierarchy created
        assert!(tmp.join("Chats").join("Alice").join(LOG_FILE).exists());
        assert!(tmp
            .join("Chats")
            .join("Alice")
            .join(MEDIA_DIR)
            .join("voice_ref")
            .exists());

        // log reads back and decrypts
        let blocks = st.read_blocks("Alice").unwrap();
        assert_eq!(blocks.len(), 1);
        assert_eq!(open_block(&hk, &acct, &blocks[0]), Some(sample_block()));

        // media reads back under media_key
        assert_eq!(
            st.get_media("Alice", "voice_ref", &mk, &acct),
            Some(b"\x89PNG demo".to_vec())
        );

        // folder migration on rename
        st.rename_chat("Alice", "Alice Smith").unwrap();
        assert!(tmp
            .join("Chats")
            .join("Alice Smith")
            .join(LOG_FILE)
            .exists());
        assert_eq!(
            st.get_media("Alice Smith", "voice_ref", &mk, &acct),
            Some(b"\x89PNG demo".to_vec())
        );

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn store_archive_root_over_all_chats() {
        let tmp = std::env::temp_dir().join("mt_archive_root_test");
        let _ = fs::remove_dir_all(&tmp);
        let st = ArchiveStore::open(&tmp).unwrap();
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let dev = [0x44u8; 16];
        assert_eq!(st.archive_root(&hk, &acct).unwrap(), None); // empty → not anchored
        st.append_item(
            "Alice",
            &hk,
            &acct,
            &dev,
            &[0x01u8; 32],
            DIR_OUT,
            1000,
            b"hi",
        )
        .unwrap();
        st.append_item("Bob", &hk, &acct, &dev, &[0x02u8; 32], DIR_OUT, 1001, b"yo")
            .unwrap();
        let r1 = st.archive_root(&hk, &acct).unwrap();
        assert!(r1.is_some());
        // deterministic: recomputing yields the same root
        assert_eq!(st.archive_root(&hk, &acct).unwrap(), r1);
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn export_ingest_replication_converges() {
        let ta = std::env::temp_dir().join("mt_arch_repl_a");
        let tb = std::env::temp_dir().join("mt_arch_repl_b");
        let _ = fs::remove_dir_all(&ta);
        let _ = fs::remove_dir_all(&tb);
        let a = ArchiveStore::open(&ta).unwrap();
        let b = ArchiveStore::open(&tb).unwrap();
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        let dev_a = [0x01u8; 16];
        let dev_b = [0x02u8; 16];
        let conv = [0x07u8; 32];
        // A writes two blocks, B writes one — different writers, same chat.
        a.append_item("Chat", &hk, &acct, &dev_a, &conv, DIR_OUT, 1000, b"a0")
            .unwrap();
        a.append_item("Chat", &hk, &acct, &dev_a, &conv, DIR_IN, 1001, b"a1")
            .unwrap();
        b.append_item("Chat", &hk, &acct, &dev_b, &conv, DIR_IN, 1002, b"b0")
            .unwrap();
        // Exchange: push A's blocks into B, B's into A (as-stored frames).
        let wt_a = writer_tag(&dev_a);
        let wt_b = writer_tag(&dev_b);
        let frames_a = a.export_mine("Chat", &wt_a, 0).unwrap();
        let frames_b = b.export_mine("Chat", &wt_b, 0).unwrap();
        for (src, dst) in [(&frames_a, &b), (&frames_b, &a)] {
            let mut off = 0usize;
            while off + 4 <= src.len() {
                let len = u32::from_le_bytes(src[off..off + 4].try_into().unwrap()) as usize;
                off += 4;
                let sealed = &src[off..off + len];
                off += len;
                assert!(dst.ingest_block("Chat", &hk, &acct, sealed).unwrap());
                // re-ingest → duplicate
                assert!(!dst.ingest_block("Chat", &hk, &acct, sealed).unwrap());
            }
        }
        // Convergence: identical ArchiveRoot on both devices.
        let ra = a.archive_root(&hk, &acct).unwrap();
        let rb = b.archive_root(&hk, &acct).unwrap();
        assert!(ra.is_some());
        assert_eq!(ra, rb, "union of writers must converge to one ArchiveRoot");
        // peek_conv routes replicated blocks to the right chat.
        let mut off = 0usize;
        let len = u32::from_le_bytes(frames_a[off..off + 4].try_into().unwrap()) as usize;
        off += 4;
        assert_eq!(peek_conv(&hk, &acct, &frames_a[off..off + len]), Some(conv));
    }

    #[test]
    fn ingest_rejects_garbage() {
        let tmp = std::env::temp_dir().join("mt_arch_ingest_bad");
        let _ = fs::remove_dir_all(&tmp);
        let st = ArchiveStore::open(&tmp).unwrap();
        let hk = history_key(&[0x55u8; 32]);
        let acct = [0x33u8; 32];
        assert!(st.ingest_block("Chat", &hk, &acct, &[0u8; 40]).is_err());
        let _ = fs::remove_dir_all(&tmp);
    }
}
