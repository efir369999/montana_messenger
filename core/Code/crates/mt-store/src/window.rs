// Issue #19 K5: the window record — everything one window changes, written whole.
//
// One file, `window.bin`, is the commit point of a settle and of a fast sync. It carries the
// window number, the clock values the node closed it with, the three consensus tables and,
// for a settle, the cemented envelope of that window. The record is written to a temporary
// file, the file is flushed, renamed over the record and the directory is flushed; after a
// failure at any of these steps the record on disk is wholly the old one or wholly the new one.
//
// Layout (version 1, little-endian):
//   magic b"mtwr" 4 | version 1 | reserved 3 | window u64 | t_r 32 | current_d u64
//   | last_window u64 | state_root of the three tables 32            (the head, 96 bytes)
//   | n u64 | n × AccountRecord   | n u64 | n × NodeRecord | n u64 | n × CandidateRecord
//   | envelope length u64 | envelope
//   | SHA-256 of every byte before it, 32
// A record whose checksum, magic, version, lengths or state_root do not hold is refused whole.

use super::{decode_account_record, decode_candidate_record, decode_node_record, FsStore};
use super::{fault, StoreError};
use mt_codec::CanonicalEncode;
use mt_state::{
    compute_state_root, AccountTable, CandidatePool, NodeTable, ACCOUNT_RECORD_SIZE,
    CANDIDATE_RECORD_SIZE, NODE_RECORD_SIZE,
};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::{Read, Write};

pub const WINDOW_RECORD_FILE: &str = "window.bin";
const WINDOW_RECORD_TMP: &str = "window.bin.tmp";
const MAGIC: &[u8; 4] = b"mtwr";
const VERSION: u8 = 1;
const HEAD_SIZE: usize = 96;
const SUM_SIZE: usize = 32;

/// The head of a record: the window, the clock and the root of the tables it carries.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct WindowHead {
    pub window: u64,
    pub t_r: [u8; 32],
    pub current_d: u64,
    pub last_window: u64,
    pub state_root: [u8; 32],
}

#[derive(Clone, Default)]
pub struct WindowRecord {
    /// The last window this node applied.
    pub window: u64,
    /// The clock: the value of `last_window`, the iterations per window, the window it reached.
    pub t_r: [u8; 32],
    pub current_d: u64,
    pub last_window: u64,
    pub accounts: AccountTable,
    pub nodes: NodeTable,
    pub candidates: CandidatePool,
    /// The cemented envelope of `window` (empty after a fast sync, which receives none).
    pub envelope: Vec<u8>,
}

impl WindowRecord {
    pub fn state_root(&self) -> [u8; 32] {
        compute_state_root(
            &self.nodes.root(),
            &self.candidates.root(),
            &self.accounts.root(),
        )
    }

    pub fn head(&self) -> WindowHead {
        WindowHead {
            window: self.window,
            t_r: self.t_r,
            current_d: self.current_d,
            last_window: self.last_window,
            state_root: self.state_root(),
        }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(
            HEAD_SIZE
                + 32
                + self.accounts.len() * ACCOUNT_RECORD_SIZE
                + self.nodes.len() * NODE_RECORD_SIZE
                + self.candidates.len() * CANDIDATE_RECORD_SIZE
                + self.envelope.len()
                + SUM_SIZE,
        );
        buf.extend_from_slice(MAGIC);
        buf.push(VERSION);
        buf.extend_from_slice(&[0u8; 3]);
        buf.extend_from_slice(&self.window.to_le_bytes());
        buf.extend_from_slice(&self.t_r);
        buf.extend_from_slice(&self.current_d.to_le_bytes());
        buf.extend_from_slice(&self.last_window.to_le_bytes());
        buf.extend_from_slice(&self.state_root());
        buf.extend_from_slice(&(self.accounts.len() as u64).to_le_bytes());
        for rec in self.accounts.iter() {
            rec.encode(&mut buf);
        }
        buf.extend_from_slice(&(self.nodes.len() as u64).to_le_bytes());
        for rec in self.nodes.iter() {
            rec.encode(&mut buf);
        }
        buf.extend_from_slice(&(self.candidates.len() as u64).to_le_bytes());
        for rec in self.candidates.iter() {
            rec.encode(&mut buf);
        }
        buf.extend_from_slice(&(self.envelope.len() as u64).to_le_bytes());
        buf.extend_from_slice(&self.envelope);
        let sum = Sha256::digest(&buf);
        buf.extend_from_slice(&sum);
        buf
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, StoreError> {
        let refused = |why: &str| StoreError::ParseFailed(format!("window record: {why}"));
        if bytes.len() < SUM_SIZE {
            return Err(StoreError::CorruptedLength(format!(
                "window record: {} bytes, shorter than its checksum",
                bytes.len()
            )));
        }
        let (body, sum) = bytes.split_at(bytes.len() - SUM_SIZE);
        if Sha256::digest(body).as_slice() != sum {
            return Err(refused(
                "the checksum does not match the body (torn or foreign)",
            ));
        }
        let head = decode_head(body)?;
        let mut r = Reader {
            bytes: body,
            at: HEAD_SIZE,
        };
        let mut accounts = AccountTable::new();
        let n = r.u64()?;
        for chunk in r
            .records(n, ACCOUNT_RECORD_SIZE)?
            .chunks_exact(ACCOUNT_RECORD_SIZE)
        {
            accounts.insert(decode_account_record(chunk)?);
        }
        let mut nodes = NodeTable::new();
        let m = r.u64()?;
        for chunk in r
            .records(m, NODE_RECORD_SIZE)?
            .chunks_exact(NODE_RECORD_SIZE)
        {
            nodes.insert(decode_node_record(chunk)?);
        }
        let mut candidates = CandidatePool::new();
        let c = r.u64()?;
        for chunk in r
            .records(c, CANDIDATE_RECORD_SIZE)?
            .chunks_exact(CANDIDATE_RECORD_SIZE)
        {
            candidates.insert(decode_candidate_record(chunk)?);
        }
        if accounts.len() as u64 != n || nodes.len() as u64 != m || candidates.len() as u64 != c {
            return Err(refused("a table names one row twice"));
        }
        let e = r.u64()?;
        let envelope = r.records(e, 1)?.to_vec();
        if r.at != body.len() {
            return Err(refused("bytes after the envelope"));
        }
        let record = WindowRecord {
            window: head.window,
            t_r: head.t_r,
            current_d: head.current_d,
            last_window: head.last_window,
            accounts,
            nodes,
            candidates,
            envelope,
        };
        if record.state_root() != head.state_root {
            return Err(refused(
                "the tables are not those whose state_root the head names",
            ));
        }
        Ok(record)
    }
}

fn decode_head(bytes: &[u8]) -> Result<WindowHead, StoreError> {
    let mut r = Reader { bytes, at: 0 };
    if r.take(4)? != MAGIC.as_slice() {
        return Err(StoreError::ParseFailed("window record: wrong magic".into()));
    }
    let version_and_reserved = r.take(4)?;
    let version = version_and_reserved[0];
    if version != VERSION {
        return Err(StoreError::ParseFailed(format!(
            "window record: unsupported version {version}"
        )));
    }
    if version_and_reserved[1..] != [0u8; 3] {
        return Err(StoreError::ParseFailed(
            "window record: reserved bytes are not zero".into(),
        ));
    }
    let window = r.u64()?;
    let t_r = r.hash()?;
    let current_d = r.u64()?;
    let last_window = r.u64()?;
    let state_root = r.hash()?;
    Ok(WindowHead {
        window,
        t_r,
        current_d,
        last_window,
        state_root,
    })
}

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], StoreError> {
        let end = self
            .at
            .checked_add(n)
            .filter(|&end| end <= self.bytes.len())
            .ok_or_else(|| {
                StoreError::CorruptedLength(format!(
                    "window record: {n} bytes wanted at {}, {} held",
                    self.at,
                    self.bytes.len()
                ))
            })?;
        let out = &self.bytes[self.at..end];
        self.at = end;
        Ok(out)
    }

    fn u64(&mut self) -> Result<u64, StoreError> {
        let mut b = [0u8; 8];
        b.copy_from_slice(self.take(8)?);
        Ok(u64::from_le_bytes(b))
    }

    fn hash(&mut self) -> Result<[u8; 32], StoreError> {
        let mut h = [0u8; 32];
        h.copy_from_slice(self.take(32)?);
        Ok(h)
    }

    fn records(&mut self, count: u64, size: usize) -> Result<&'a [u8], StoreError> {
        let len = usize::try_from(count)
            .ok()
            .and_then(|c| c.checked_mul(size))
            .ok_or_else(|| {
                StoreError::CorruptedLength(format!("window record: {count} rows of {size}"))
            })?;
        self.take(len)
    }
}

impl FsStore {
    /// The commit point of a window: the record written whole. Five file operations, each
    /// one a point of the fault hook: create the temporary, write it, flush it, rename it over
    /// the record, flush the directory. Before the rename the old record stands; after it
    /// the new one.
    pub fn commit_window(&self, record: &WindowRecord) -> Result<(), StoreError> {
        let bytes = record.encode();
        let tmp = self.path(WINDOW_RECORD_TMP);
        fault::step()?;
        let mut file = fs::File::create(&tmp)?;
        if let Err(e) = fault::step() {
            // A death in the middle of the write leaves a torn temporary.
            let _ = file.write_all(&bytes[..bytes.len() / 2]);
            return Err(e.into());
        }
        file.write_all(&bytes)?;
        fault::step()?;
        file.sync_all()?;
        drop(file);
        fault::step()?;
        fs::rename(&tmp, self.path(WINDOW_RECORD_FILE))?;
        fault::step()?;
        fs::File::open(&self.root)?.sync_all()?;
        Ok(())
    }

    /// The record, if this store holds one. A record that does not decode is an error,
    /// never an absent record.
    pub fn load_window_record(&self) -> Result<Option<WindowRecord>, StoreError> {
        let path = self.path(WINDOW_RECORD_FILE);
        if !path.exists() {
            return Ok(None);
        }
        Ok(Some(WindowRecord::decode(&fs::read(&path)?)?))
    }

    /// The head of the record, read without its body or checksum: only to tell whether a
    /// running node's memory has moved from its last record, never as the truth of a start.
    pub fn load_window_head(&self) -> Result<Option<WindowHead>, StoreError> {
        let path = self.path(WINDOW_RECORD_FILE);
        if !path.exists() {
            return Ok(None);
        }
        let mut head = [0u8; HEAD_SIZE];
        fs::File::open(&path)?.read_exact(&mut head)?;
        Ok(Some(decode_head(&head)?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::PUBLIC_KEY_SIZE;
    use mt_state::{AccountRecord, CandidateRecord, NodeRecord};
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static SEQ: AtomicU64 = AtomicU64::new(0);

    fn dir(tag: &str) -> PathBuf {
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let p =
            std::env::temp_dir().join(format!("mt-store-window-{tag}-{}-{n}", std::process::id()));
        let _ = fs::remove_dir_all(&p);
        p
    }

    fn record(window: u64, balance: u128) -> WindowRecord {
        let mut r = WindowRecord {
            window,
            t_r: [window as u8; 32],
            current_d: 1000 + window,
            last_window: window + 1,
            envelope: vec![0xE5; 3722 + window as usize],
            ..WindowRecord::default()
        };
        r.accounts.insert(AccountRecord {
            account_id: [0x11; 32],
            balance,
            suite_id: 1,
            is_node_operator: true,
            frontier_hash: [0u8; 32],
            op_height: 0,
            account_chain_length: 0,
            account_chain_length_snapshot: 0,
            current_pubkey: [0x11; PUBLIC_KEY_SIZE],
            creation_window: 0,
            last_op_window: 0,
            last_activation_window: 0,
        });
        r.nodes.insert(NodeRecord {
            node_id: [0x22; 32],
            node_pubkey: [0x22; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [0x11; 32],
            start_window: 1,
            chain_length: window,
            chain_length_snapshot: 0,
            chain_length_checkpoints: [0; 6],
            last_confirmation_window: window,
        });
        r.candidates.insert(CandidateRecord {
            node_id: [0x33; 32],
            node_pubkey: [0x33; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [0x33; 32],
            proof_endpoint: [0x33; 32],
            w_start: 1,
            ssha_chain_length: 7,
            registration_window: 1,
            expires: 99,
        });
        r
    }

    #[test]
    fn a_record_decodes_to_the_bytes_it_was_encoded_from() {
        let bytes = record(9, 5).encode();
        assert_eq!(WindowRecord::decode(&bytes).unwrap().encode(), bytes);
    }

    // Rejects a commit that is not whole: a death at every file operation of the commit leaves
    // on disk the old record or the new one, byte for byte, and reopening reads that one.
    #[test]
    fn a_commit_dying_at_every_file_operation_leaves_the_old_or_the_new_record() {
        let (old, new) = (record(4, 10), record(5, 20));
        fault::fail_at(None);
        let p = dir("count");
        FsStore::open(&p).unwrap().commit_window(&new).unwrap();
        let ops = fault::done();
        assert_eq!(ops, 5, "the commit is five file operations");
        let _ = fs::remove_dir_all(&p);
        for k in 1..=ops {
            let p = dir("death");
            let store = FsStore::open(&p).unwrap();
            store.commit_window(&old).unwrap();
            fault::fail_at(Some(k));
            assert!(store.commit_window(&new).is_err(), "death at {k} not seen");
            fault::fail_at(None);
            drop(store);
            let held = fs::read(p.join(WINDOW_RECORD_FILE)).unwrap();
            let want = if k <= 4 { old.encode() } else { new.encode() };
            assert!(
                held == want,
                "death at {k}: neither the old nor the new record"
            );
            let reopened = FsStore::open(&p).unwrap().load_window_record().unwrap();
            assert_eq!(reopened.unwrap().encode(), want, "death at {k}: reopen");
            let _ = fs::remove_dir_all(&p);
        }
    }

    // Rejects a decoder that trusts what it reads: a record cut short at any length, or with
    // any one byte flipped, is refused.
    #[test]
    fn a_torn_or_flipped_record_is_refused() {
        let bytes = record(5, 20).encode();
        for len in 0..bytes.len() {
            assert!(WindowRecord::decode(&bytes[..len]).is_err(), "cut at {len}");
        }
        for at in 0..bytes.len() {
            let mut b = bytes.clone();
            b[at] ^= 0x01;
            assert!(WindowRecord::decode(&b).is_err(), "byte {at} flipped");
        }
    }
}
