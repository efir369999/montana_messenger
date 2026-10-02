// spec, раздел "Хранение" + "Fast Sync".
// Persistence layer для state + proposal archive.
// Minimal filesystem-backed store (без RocksDB/sled — pure std::fs + fixed-size records).

use mt_consensus::{ProposalHeader, PROPOSAL_HEADER_SIZE};
use mt_crypto::{Signature, PUBLIC_KEY_SIZE, SIGNATURE_SIZE};
use mt_state::{
    AccountRecord, AccountTable, CandidatePool, CandidateRecord, NodeRecord, NodeTable,
    ACCOUNT_RECORD_SIZE, CANDIDATE_RECORD_SIZE, NODE_RECORD_SIZE,
};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

// ============ Phase A: FsStore — filesystem-backed KV ============

#[derive(Debug)]
pub struct FsStore {
    root: PathBuf,
}

#[derive(Debug)]
pub enum StoreError {
    Io(io::Error),
    CorruptedLength(String),
    ParseFailed(String),
    NotFound(String),
}

impl From<io::Error> for StoreError {
    fn from(e: io::Error) -> Self {
        StoreError::Io(e)
    }
}

impl FsStore {
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self, StoreError> {
        let root = path.as_ref().to_path_buf();
        fs::create_dir_all(&root)?;
        let proposals_dir = root.join("proposals");
        fs::create_dir_all(&proposals_dir)?;
        // M5-LOW-8 closure: cleanup orphaned `.tmp` файлов от прошлого
        // crashed write_atomic (process killed между fs::write tmp и
        // fs::rename → tmp file остаётся на диске). Multiple crashes без
        // cleanup → накопление tmp в root + proposals/.
        // Tmp файлы не influence load_* (load ищет по точному имени без
        // .tmp suffix), но это storage waste. Cleanup на open() — ленивая
        // recovery без impact на normal write path.
        Self::cleanup_orphan_tmp(&root);
        Self::cleanup_orphan_tmp(&proposals_dir);
        Ok(Self { root })
    }

    fn cleanup_orphan_tmp(dir: &Path) {
        // Best-effort: pri ошибке read_dir / fs::remove_file просто skip
        // (не failure для open — tmp cleanup advisory, не load-bearing).
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_file()
                    && path
                        .extension()
                        .and_then(|e| e.to_str())
                        .map(|e| e == "tmp")
                        .unwrap_or(false)
                {
                    // DEV-041: удалять ТОЛЬКО устаревшие .tmp (>60с). In-flight
                    // write_atomic temp живого узла младше секунды; конкурентный
                    // FsStore::open (status / collector на том же data dir) НЕ
                    // должен его сносить между fs::write и fs::rename — иначе
                    // rename падает NotFound и узел умирает.
                    let stale = entry
                        .metadata()
                        .and_then(|m| m.modified())
                        .ok()
                        .and_then(|t| t.elapsed().ok())
                        .map(|age| age.as_secs() > 60)
                        .unwrap_or(false);
                    if stale {
                        let _ = fs::remove_file(&path);
                    }
                }
            }
        }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    fn path(&self, name: &str) -> PathBuf {
        self.root.join(name)
    }

    fn proposal_path(&self, window: u64) -> PathBuf {
        self.root
            .join("proposals")
            .join(format!("{:020}.bin", window))
    }

    // R5 atomic rename pattern: writes go в `<name>.tmp` ДО fs::rename
    // на final path. POSIX `rename(2)` atomic per single filesystem —
    // observers видят либо old либо new content, не partial. Защита от
    // power-loss / SIGKILL mid-write либо disk-full corruption.
    //
    // Для full crash-safety узел дополнительно использует fsync (в M6
    // operator layer); rename atomicity достаточна для filesystem-level
    // consistency без user-space syncing.
    fn write_atomic(&self, name: &str, data: &[u8]) -> Result<(), StoreError> {
        let final_path = self.path(name);
        let tmp_path = self.path(&format!("{name}.tmp"));
        fs::write(&tmp_path, data)?;
        fs::rename(&tmp_path, &final_path)?;
        Ok(())
    }

    fn write_atomic_to(&self, final_path: &Path, data: &[u8]) -> Result<(), StoreError> {
        let parent = final_path
            .parent()
            .ok_or_else(|| StoreError::ParseFailed("path has no parent".into()))?;
        let file_name = final_path
            .file_name()
            .ok_or_else(|| StoreError::ParseFailed("path has no file name".into()))?;
        let tmp_path = parent.join(format!("{}.tmp", file_name.to_string_lossy()));
        fs::write(&tmp_path, data)?;
        fs::rename(&tmp_path, final_path)?;
        Ok(())
    }
}

// ============ Phase B: Table persistence ============

// AccountRecord fixed-size decode (inverse CanonicalEncode).
// Layout (ACCOUNT_RECORD_SIZE = 2059 B под ML-DSA-65) — см. spec раздел
// "Account — содержимое блока":
//   account_id 32 + balance 16 + suite_id 2 + is_node_operator 1 + frontier_hash 32
//   + op_height 4 + account_chain_length 4 + account_chain_length_snapshot 4
//   + current_pubkey 1952 + creation_window 4 + last_op_window 4
//   + last_activation_window 4
fn read_32_at(bytes: &[u8], off: usize) -> [u8; 32] {
    let mut h = [0u8; 32];
    h.copy_from_slice(&bytes[off..off + 32]);
    h
}

fn read_u16_at(bytes: &[u8], off: usize) -> u16 {
    let mut b = [0u8; 2];
    b.copy_from_slice(&bytes[off..off + 2]);
    u16::from_le_bytes(b)
}

fn read_u32_at(bytes: &[u8], off: usize) -> u32 {
    let mut b = [0u8; 4];
    b.copy_from_slice(&bytes[off..off + 4]);
    u32::from_le_bytes(b)
}

fn read_u64_at(bytes: &[u8], off: usize) -> u64 {
    let mut b = [0u8; 8];
    b.copy_from_slice(&bytes[off..off + 8]);
    u64::from_le_bytes(b)
}

fn read_u128_at(bytes: &[u8], off: usize) -> u128 {
    let mut b = [0u8; 16];
    b.copy_from_slice(&bytes[off..off + 16]);
    u128::from_le_bytes(b)
}

fn read_pubkey_at(bytes: &[u8], off: usize) -> [u8; PUBLIC_KEY_SIZE] {
    let mut pk = [0u8; PUBLIC_KEY_SIZE];
    pk.copy_from_slice(&bytes[off..off + PUBLIC_KEY_SIZE]);
    pk
}

fn decode_account_record(bytes: &[u8]) -> Result<AccountRecord, StoreError> {
    if bytes.len() != ACCOUNT_RECORD_SIZE {
        return Err(StoreError::CorruptedLength(format!(
            "AccountRecord expect {ACCOUNT_RECORD_SIZE}, got {}",
            bytes.len()
        )));
    }
    let account_id = read_32_at(bytes, 0);
    let balance = read_u128_at(bytes, 32);
    let suite_id = read_u16_at(bytes, 48);
    let is_node_operator = bytes[50] != 0;
    let frontier_hash = read_32_at(bytes, 51);
    let op_height = read_u32_at(bytes, 83);
    let account_chain_length = read_u32_at(bytes, 87);
    let account_chain_length_snapshot = read_u32_at(bytes, 91);
    let current_pubkey = read_pubkey_at(bytes, 95);
    let creation_window = read_u32_at(bytes, 95 + PUBLIC_KEY_SIZE);
    let last_op_window = read_u32_at(bytes, 99 + PUBLIC_KEY_SIZE);
    let last_activation_window = read_u32_at(bytes, 103 + PUBLIC_KEY_SIZE);
    Ok(AccountRecord {
        account_id,
        balance,
        suite_id,
        is_node_operator,
        frontier_hash,
        op_height,
        account_chain_length,
        account_chain_length_snapshot,
        current_pubkey,
        creation_window,
        last_op_window,
        last_activation_window,
    })
}

// NodeRecord fixed-size decode (NODE_RECORD_SIZE = 2098 B под ML-DSA-65):
//   node_id 32 + node_pubkey 1952 + suite_id 2 + operator_account_id 32
//   + start_window 8 + chain_length 8 + chain_length_snapshot 8
//   + chain_length_checkpoints [u64;6] = 48 + last_confirmation_window 8
fn decode_node_record(bytes: &[u8]) -> Result<NodeRecord, StoreError> {
    if bytes.len() != NODE_RECORD_SIZE {
        return Err(StoreError::CorruptedLength(format!(
            "NodeRecord expect {NODE_RECORD_SIZE}, got {}",
            bytes.len()
        )));
    }
    // Offsets: 32 + 1952 + 2 + 32 + 8 + 8 + 8 + 48 (6×u64) + 8 = 2098
    let node_id = read_32_at(bytes, 0);
    let node_pubkey = read_pubkey_at(bytes, 32);
    let suite_id = read_u16_at(bytes, 32 + PUBLIC_KEY_SIZE);
    let operator_account_id = read_32_at(bytes, 34 + PUBLIC_KEY_SIZE);
    let base = 66 + PUBLIC_KEY_SIZE;
    let start_window = read_u64_at(bytes, base);
    let chain_length = read_u64_at(bytes, base + 8);
    let chain_length_snapshot = read_u64_at(bytes, base + 16);
    let mut chain_length_checkpoints = [0u64; 6];
    for (i, cp) in chain_length_checkpoints.iter_mut().enumerate() {
        *cp = read_u64_at(bytes, base + 24 + i * 8);
    }
    let last_confirmation_window = read_u64_at(bytes, base + 24 + 48);
    Ok(NodeRecord {
        node_id,
        node_pubkey,
        suite_id,
        operator_account_id,
        start_window,
        chain_length,
        chain_length_snapshot,
        chain_length_checkpoints,
        last_confirmation_window,
    })
}

// CandidateRecord fixed-size decode (CANDIDATE_RECORD_SIZE = 2082 B под ML-DSA-65):
//   node_id 32 + node_pubkey 1952 + suite_id 2 + operator_account_id 32
//   + proof_endpoint 32 + w_start 8 + ssha_chain_length 8
//   + registration_window 8 + expires 8
fn decode_candidate_record(bytes: &[u8]) -> Result<CandidateRecord, StoreError> {
    if bytes.len() != CANDIDATE_RECORD_SIZE {
        return Err(StoreError::CorruptedLength(format!(
            "CandidateRecord expect {CANDIDATE_RECORD_SIZE}, got {}",
            bytes.len()
        )));
    }
    // Offsets: 32 + 1952 + 2 + 32 + 32 + 8 + 8 + 8 + 8 = 2082
    let node_id = read_32_at(bytes, 0);
    let node_pubkey = read_pubkey_at(bytes, 32);
    let suite_id = read_u16_at(bytes, 32 + PUBLIC_KEY_SIZE);
    let operator_account_id = read_32_at(bytes, 34 + PUBLIC_KEY_SIZE);
    let proof_endpoint = read_32_at(bytes, 66 + PUBLIC_KEY_SIZE);
    let base = 98 + PUBLIC_KEY_SIZE;
    let w_start = read_u64_at(bytes, base);
    let ssha_chain_length = read_u64_at(bytes, base + 8);
    let registration_window = read_u64_at(bytes, base + 16);
    let expires = read_u64_at(bytes, base + 24);
    Ok(CandidateRecord {
        node_id,
        node_pubkey,
        suite_id,
        operator_account_id,
        proof_endpoint,
        w_start,
        ssha_chain_length,
        registration_window,
        expires,
    })
}

impl FsStore {
    pub fn save_account_table(&self, table: &AccountTable) -> Result<(), StoreError> {
        use mt_codec::CanonicalEncode;
        let mut buf = Vec::with_capacity(table.len() * ACCOUNT_RECORD_SIZE);
        for rec in table.iter() {
            rec.encode(&mut buf);
        }
        self.write_atomic("accounts.bin", &buf)?;
        Ok(())
    }

    pub fn load_account_table(&self) -> Result<AccountTable, StoreError> {
        let path = self.path("accounts.bin");
        if !path.exists() {
            return Ok(AccountTable::new());
        }
        let bytes = fs::read(&path)?;
        if bytes.len() % ACCOUNT_RECORD_SIZE != 0 {
            return Err(StoreError::CorruptedLength(format!(
                "accounts.bin length {} не кратна {ACCOUNT_RECORD_SIZE}",
                bytes.len()
            )));
        }
        let mut table = AccountTable::new();
        for chunk in bytes.chunks_exact(ACCOUNT_RECORD_SIZE) {
            let rec = decode_account_record(chunk)?;
            table.insert(rec);
        }
        Ok(table)
    }

    pub fn save_node_table(&self, table: &NodeTable) -> Result<(), StoreError> {
        use mt_codec::CanonicalEncode;
        let mut buf = Vec::with_capacity(table.len() * NODE_RECORD_SIZE);
        for rec in table.iter() {
            rec.encode(&mut buf);
        }
        self.write_atomic("nodes.bin", &buf)?;
        Ok(())
    }

    pub fn load_node_table(&self) -> Result<NodeTable, StoreError> {
        let path = self.path("nodes.bin");
        if !path.exists() {
            return Ok(NodeTable::new());
        }
        let bytes = fs::read(&path)?;
        if bytes.len() % NODE_RECORD_SIZE != 0 {
            return Err(StoreError::CorruptedLength(format!(
                "nodes.bin length {} не кратна {NODE_RECORD_SIZE}",
                bytes.len()
            )));
        }
        let mut table = NodeTable::new();
        for chunk in bytes.chunks_exact(NODE_RECORD_SIZE) {
            let rec = decode_node_record(chunk)?;
            table.insert(rec);
        }
        Ok(table)
    }

    pub fn save_candidate_pool(&self, pool: &CandidatePool) -> Result<(), StoreError> {
        use mt_codec::CanonicalEncode;
        let mut buf = Vec::with_capacity(pool.len() * CANDIDATE_RECORD_SIZE);
        for rec in pool.iter() {
            rec.encode(&mut buf);
        }
        self.write_atomic("candidates.bin", &buf)?;
        Ok(())
    }

    pub fn load_candidate_pool(&self) -> Result<CandidatePool, StoreError> {
        let path = self.path("candidates.bin");
        if !path.exists() {
            return Ok(CandidatePool::new());
        }
        let bytes = fs::read(&path)?;
        if bytes.len() % CANDIDATE_RECORD_SIZE != 0 {
            return Err(StoreError::CorruptedLength(format!(
                "candidates.bin length {} не кратна {CANDIDATE_RECORD_SIZE}",
                bytes.len()
            )));
        }
        let mut pool = CandidatePool::new();
        for chunk in bytes.chunks_exact(CANDIDATE_RECORD_SIZE) {
            let rec = decode_candidate_record(chunk)?;
            pool.insert(rec);
        }
        Ok(pool)
    }
}

// ============ Phase C: Proposal archive ============

fn decode_proposal_header(bytes: &[u8]) -> Result<ProposalHeader, StoreError> {
    if bytes.len() != PROPOSAL_HEADER_SIZE {
        return Err(StoreError::CorruptedLength(format!(
            "ProposalHeader expect {PROPOSAL_HEADER_SIZE}, got {}",
            bytes.len()
        )));
    }
    // Offsets per spec v31.0.0 (winner_class byte удалён; header 3722 B
    // под ML-DSA-65; signed-scope без signature = 413 B; structural offsets
    // 0..413 без изменений):
    // 0..32 prev_proposal_hash, 32..40 window_index (u64),
    // 40..44 protocol_version (u32), 44..76 control_root, 76..108 node_root,
    // 108..140 candidate_root, 140..172 account_root, 172..204 state_root,
    // 204..236 timechain_value, 236..268 included_bundles_root,
    // 268..300 included_reveals_root,
    // 300..332 winner_endpoint, 332..364 winner_id, 364..396 proposer_node_id,
    // 396..412 target (u128), 412 fallback_depth (u8),
    // 413..3722 signature (3309B ML-DSA-65)
    let prev_proposal_hash = read_32_at(bytes, 0);
    let window_index = read_u64_at(bytes, 32);
    let protocol_version = read_u32_at(bytes, 40);
    let control_root = read_32_at(bytes, 44);
    let node_root = read_32_at(bytes, 76);
    let candidate_root = read_32_at(bytes, 108);
    let account_root = read_32_at(bytes, 140);
    let state_root = read_32_at(bytes, 172);
    let timechain_value = read_32_at(bytes, 204);
    let included_bundles_root = read_32_at(bytes, 236);
    let included_reveals_root = read_32_at(bytes, 268);
    let winner_endpoint = read_32_at(bytes, 300);
    let winner_id = read_32_at(bytes, 332);
    let proposer_node_id = read_32_at(bytes, 364);
    let target = read_u128_at(bytes, 396);
    let fallback_depth = bytes[412];
    let mut sig_bytes = [0u8; SIGNATURE_SIZE];
    sig_bytes.copy_from_slice(&bytes[413..413 + SIGNATURE_SIZE]);
    let signature = Signature::from_array(sig_bytes);
    Ok(ProposalHeader {
        prev_proposal_hash,
        window_index,
        protocol_version,
        control_root,
        node_root,
        candidate_root,
        account_root,
        state_root,
        timechain_value,
        included_bundles_root,
        included_reveals_root,
        winner_endpoint,
        winner_id,
        proposer_node_id,
        target,
        fallback_depth,
        signature,
    })
}

impl FsStore {
    pub fn archive_proposal(&self, header: &ProposalHeader) -> Result<(), StoreError> {
        use mt_codec::CanonicalEncode;
        let mut buf = Vec::with_capacity(PROPOSAL_HEADER_SIZE);
        header.encode(&mut buf);
        self.write_atomic_to(&self.proposal_path(header.window_index), &buf)?;
        Ok(())
    }

    /// Build 31: archive the FULL cemented envelope (header + bundle_count u16 + bundles).
    /// Explorer can then read bundles array from archive, not just header.
    pub fn archive_proposal_envelope(
        &self,
        window: u64,
        envelope: &[u8],
    ) -> Result<(), StoreError> {
        if envelope.len() < PROPOSAL_HEADER_SIZE {
            return Err(StoreError::CorruptedLength(format!(
                "archive_proposal_envelope: too small {} < {}",
                envelope.len(),
                PROPOSAL_HEADER_SIZE
            )));
        }
        self.write_atomic_to(&self.proposal_path(window), envelope)?;
        Ok(())
    }

    pub fn get_proposal_by_window(
        &self,
        window: u64,
    ) -> Result<Option<ProposalHeader>, StoreError> {
        let path = self.proposal_path(window);
        if !path.exists() {
            return Ok(None);
        }
        let bytes = fs::read(&path)?;
        Ok(Some(decode_proposal_header(&bytes)?))
    }

    // Сырые байты архивированного конверта (header + списки подтверждений) —
    // для восстановления пооконных историй консенсуса после рестарта узла.
    pub fn load_proposal_envelope(&self, window: u64) -> Result<Option<Vec<u8>>, StoreError> {
        let path = self.proposal_path(window);
        if !path.exists() {
            return Ok(None);
        }
        Ok(Some(fs::read(&path)?))
    }
}

// ============ Phase D: Crash recovery (meta last_cemented_window) ============

impl FsStore {
    pub fn save_meta_last_cemented(&self, window: u64) -> Result<(), StoreError> {
        self.write_atomic("meta_last_cemented.bin", &window.to_le_bytes())?;
        Ok(())
    }

    pub fn load_meta_last_cemented(&self) -> Result<Option<u64>, StoreError> {
        let path = self.path("meta_last_cemented.bin");
        if !path.exists() {
            return Ok(None);
        }
        let bytes = fs::read(&path)?;
        if bytes.len() != 8 {
            return Err(StoreError::CorruptedLength(format!(
                "meta_last_cemented.bin expect 8, got {}",
                bytes.len()
            )));
        }
        let mut b = [0u8; 8];
        b.copy_from_slice(&bytes);
        Ok(Some(u64::from_le_bytes(b)))
    }

    // Restart consistency: meta — последний целостный commit. При reopen
    // проверяем что proposal (meta.last_cemented_window) существует в archive.
    // Иначе: crash between commit и meta write → fallback на предыдущий.
    pub fn verify_consistency(&self) -> Result<u64, StoreError> {
        let last = self.load_meta_last_cemented()?.unwrap_or(0);
        // Проверка: proposal_{last} существует (если > 0)
        if last > 0 && self.get_proposal_by_window(last)?.is_none() {
            return Err(StoreError::NotFound(format!(
                "meta_last_cemented = {last}, но proposals/{:020}.bin отсутствует",
                last
            )));
        }
        Ok(last)
    }
}

// ============ Phase E: Pruning ============

impl FsStore {
    // Удалить proposals с window_index < threshold.
    // Возвращает Vec<u64> удалённых window indices.
    pub fn prune_proposals_before(&self, threshold: u64) -> Result<Vec<u64>, StoreError> {
        let proposals_dir = self.root.join("proposals");
        let mut removed = Vec::new();
        if !proposals_dir.exists() {
            return Ok(removed);
        }
        for entry in fs::read_dir(&proposals_dir)? {
            let entry = entry?;
            let file_name = entry.file_name();
            let name = file_name.to_string_lossy();
            if !name.ends_with(".bin") {
                continue;
            }
            let stem = &name[..name.len() - 4];
            let window: u64 = match stem.parse() {
                Ok(w) => w,
                Err(_) => continue,
            };
            if window < threshold {
                fs::remove_file(entry.path())?;
                removed.push(window);
            }
        }
        removed.sort();
        Ok(removed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_codec::CanonicalEncode;
    use mt_crypto::SECRET_KEY_SIZE;
    use mt_state::derive_account_id;

    fn tmp_dir(suffix: &str) -> PathBuf {
        let base = std::env::temp_dir().join(format!("mt-store-test-{suffix}-{}", rand_suffix()));
        let _ = fs::remove_dir_all(&base);
        base
    }

    fn rand_suffix() -> u64 {
        // Псевдо-рандом через nano system time (не consensus-critical)
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.subsec_nanos() as u64 ^ (d.as_secs() << 32))
            .unwrap_or(0)
    }

    fn make_account(seed: u8) -> AccountRecord {
        let pubkey = [seed; PUBLIC_KEY_SIZE];
        AccountRecord {
            account_id: derive_account_id(1, &pubkey),
            balance: 1000 + seed as u128,
            suite_id: 1,
            is_node_operator: seed % 2 == 0,
            frontier_hash: [seed; 32],
            op_height: seed as u32,
            account_chain_length: seed as u32,
            account_chain_length_snapshot: (seed / 2) as u32,
            current_pubkey: pubkey,
            creation_window: seed as u32,
            last_op_window: seed as u32,
            last_activation_window: 0,
        }
    }

    fn make_node(seed: u8) -> NodeRecord {
        NodeRecord {
            node_id: [seed; 32],
            node_pubkey: [seed; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [seed; 32],
            start_window: seed as u64,
            chain_length: (seed as u64 + 1) * 100,
            chain_length_snapshot: (seed as u64 + 1) * 50,
            chain_length_checkpoints: [(seed as u64) * 10; 6],
            last_confirmation_window: seed as u64,
        }
    }

    fn make_candidate(seed: u8) -> CandidateRecord {
        CandidateRecord {
            node_id: [seed; 32],
            node_pubkey: [seed; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [seed; 32],
            proof_endpoint: [seed; 32],
            w_start: seed as u64,
            ssha_chain_length: seed as u64 * 1000,
            registration_window: seed as u64,
            expires: seed as u64 + 10_000,
        }
    }

    fn make_header(window: u64) -> ProposalHeader {
        ProposalHeader {
            prev_proposal_hash: [(window % 256) as u8; 32],
            window_index: window,
            protocol_version: 1,
            control_root: [0x02; 32],
            node_root: [0x03; 32],
            candidate_root: [0x04; 32],
            account_root: [0x05; 32],
            state_root: [0x06; 32],
            timechain_value: [0x07; 32],
            included_bundles_root: [0x08; 32],
            included_reveals_root: [0x09; 32],
            winner_endpoint: [0x0A; 32],
            winner_id: [0x0B; 32],
            proposer_node_id: [0xAA; 32],
            target: u128::from(window),
            fallback_depth: 1,
            signature: Signature::from_array([(window % 256) as u8; SIGNATURE_SIZE]),
        }
    }

    // Phase A

    #[test]
    fn open_creates_directories() {
        let p = tmp_dir("open");
        let _store = FsStore::open(&p).unwrap();
        assert!(p.exists());
        assert!(p.join("proposals").exists());
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn reopen_existing_is_idempotent() {
        let p = tmp_dir("reopen");
        let s1 = FsStore::open(&p).unwrap();
        let s2 = FsStore::open(&p).unwrap();
        assert_eq!(s1.root(), s2.root());
        fs::remove_dir_all(&p).ok();
    }

    // M5-LOW-8 closure: anti-regression — orphan .tmp files (от crashed
    // write_atomic) cleanup при FsStore::open. Без cleanup multiple crashes
    // → накопление tmp в root + proposals/.
    #[test]
    fn open_cleans_aged_orphan_tmp_but_keeps_fresh() {
        use std::time::{Duration, SystemTime};
        let p = tmp_dir("orphan_tmp");
        // Pre-create directories + simulated orphan .tmp от crashed write
        fs::create_dir_all(&p).unwrap();
        fs::create_dir_all(p.join("proposals")).unwrap();
        let orphan_root = p.join("accounts.bin.tmp");
        let orphan_proposal = p.join("proposals").join("00000000000000000042.bin.tmp");
        let fresh_tmp = p.join("nodes.bin.tmp");
        let normal_file = p.join("accounts.bin");
        fs::write(&orphan_root, b"crashed-write").unwrap();
        fs::write(&orphan_proposal, b"crashed-write").unwrap();
        fs::write(&fresh_tmp, b"in-flight-write").unwrap();
        fs::write(&normal_file, b"valid").unwrap();

        // DEV-041: cleanup removes ONLY .tmp older than 60s (in-flight writes of a
        // live node must survive a concurrent `status` open). Age the two orphans
        // past the guard; leave fresh_tmp new.
        let aged = SystemTime::now() - Duration::from_secs(120);
        for f in [&orphan_root, &orphan_proposal] {
            fs::OpenOptions::new()
                .write(true)
                .open(f)
                .unwrap()
                .set_modified(aged)
                .unwrap();
        }

        let _store = FsStore::open(&p).unwrap();
        assert!(!orphan_root.exists(), "aged orphan root .tmp not cleaned");
        assert!(
            !orphan_proposal.exists(),
            "aged orphan proposal .tmp not cleaned"
        );
        assert!(
            fresh_tmp.exists(),
            "fresh in-flight .tmp must survive the 60s age-guard (DEV-041)"
        );
        assert!(normal_file.exists(), "non-tmp file mistakenly removed");

        fs::remove_dir_all(&p).ok();
    }

    // Phase B — AccountTable

    #[test]
    fn account_table_save_load_roundtrip() {
        let p = tmp_dir("acc");
        let store = FsStore::open(&p).unwrap();
        let mut t = AccountTable::new();
        for i in 1u8..=5 {
            t.insert(make_account(i));
        }
        let root_before = t.root();
        store.save_account_table(&t).unwrap();
        let loaded = store.load_account_table().unwrap();
        assert_eq!(loaded.len(), 5);
        assert_eq!(loaded.root(), root_before);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn account_table_load_missing_returns_empty() {
        let p = tmp_dir("acc-empty");
        let store = FsStore::open(&p).unwrap();
        let t = store.load_account_table().unwrap();
        assert_eq!(t.len(), 0);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn account_table_decode_is_inverse_of_encode() {
        let a = make_account(42);
        let mut buf = Vec::new();
        a.encode(&mut buf);
        let decoded = decode_account_record(&buf).unwrap();
        assert_eq!(decoded, a);
    }

    #[test]
    fn account_table_decode_wrong_size_fails() {
        let result = decode_account_record(&[0u8; 100]);
        assert!(matches!(result, Err(StoreError::CorruptedLength(_))));
    }

    // Phase B — NodeTable

    #[test]
    fn node_table_save_load_roundtrip() {
        let p = tmp_dir("nodes");
        let store = FsStore::open(&p).unwrap();
        let mut t = NodeTable::new();
        for i in 1u8..=3 {
            t.insert(make_node(i));
        }
        let root_before = t.root();
        store.save_node_table(&t).unwrap();
        let loaded = store.load_node_table().unwrap();
        assert_eq!(loaded.len(), 3);
        assert_eq!(loaded.root(), root_before);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn node_table_decode_inverse() {
        let n = make_node(77);
        let mut buf = Vec::new();
        n.encode(&mut buf);
        let decoded = decode_node_record(&buf).unwrap();
        assert_eq!(decoded, n);
    }

    // Phase B — CandidatePool

    #[test]
    fn candidate_pool_save_load_roundtrip() {
        let p = tmp_dir("cands");
        let store = FsStore::open(&p).unwrap();
        let mut pool = CandidatePool::new();
        for i in 1u8..=4 {
            pool.insert(make_candidate(i));
        }
        let root_before = pool.root();
        store.save_candidate_pool(&pool).unwrap();
        let loaded = store.load_candidate_pool().unwrap();
        assert_eq!(loaded.len(), 4);
        assert_eq!(loaded.root(), root_before);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn candidate_decode_inverse() {
        let c = make_candidate(99);
        let mut buf = Vec::new();
        c.encode(&mut buf);
        let decoded = decode_candidate_record(&buf).unwrap();
        assert_eq!(decoded, c);
    }

    // Phase C — Proposal archive

    #[test]
    fn archive_and_fetch_proposal() {
        let p = tmp_dir("prop");
        let store = FsStore::open(&p).unwrap();
        let h = make_header(100);
        store.archive_proposal(&h).unwrap();
        let loaded = store.get_proposal_by_window(100).unwrap().unwrap();
        assert_eq!(loaded, h);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn fetch_missing_proposal_returns_none() {
        let p = tmp_dir("prop-none");
        let store = FsStore::open(&p).unwrap();
        assert!(store.get_proposal_by_window(12345).unwrap().is_none());
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn archive_100_proposals_random_access() {
        let p = tmp_dir("prop-many");
        let store = FsStore::open(&p).unwrap();
        for w in 1..=100u64 {
            store.archive_proposal(&make_header(w)).unwrap();
        }
        // Random access
        for w in [1u64, 50, 99, 100] {
            let h = store.get_proposal_by_window(w).unwrap().unwrap();
            assert_eq!(h.window_index, w);
        }
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn proposal_header_decode_inverse() {
        let h = make_header(42);
        let mut buf = Vec::new();
        h.encode(&mut buf);
        let decoded = decode_proposal_header(&buf).unwrap();
        assert_eq!(decoded, h);
    }

    // Phase D — Crash recovery

    #[test]
    fn meta_last_cemented_save_load() {
        let p = tmp_dir("meta");
        let store = FsStore::open(&p).unwrap();
        store.save_meta_last_cemented(12345).unwrap();
        let loaded = store.load_meta_last_cemented().unwrap();
        assert_eq!(loaded, Some(12345));
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn meta_missing_returns_none() {
        let p = tmp_dir("meta-none");
        let store = FsStore::open(&p).unwrap();
        assert_eq!(store.load_meta_last_cemented().unwrap(), None);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn verify_consistency_fresh_store_returns_zero() {
        let p = tmp_dir("consist-fresh");
        let store = FsStore::open(&p).unwrap();
        assert_eq!(store.verify_consistency().unwrap(), 0);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn verify_consistency_detects_missing_proposal() {
        // meta указывает на window 100, но proposal не archive'd → inconsistency
        let p = tmp_dir("consist-bad");
        let store = FsStore::open(&p).unwrap();
        store.save_meta_last_cemented(100).unwrap();
        assert!(matches!(
            store.verify_consistency(),
            Err(StoreError::NotFound(_))
        ));
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn verify_consistency_success_with_proposal() {
        let p = tmp_dir("consist-ok");
        let store = FsStore::open(&p).unwrap();
        store.archive_proposal(&make_header(50)).unwrap();
        store.save_meta_last_cemented(50).unwrap();
        assert_eq!(store.verify_consistency().unwrap(), 50);
        fs::remove_dir_all(&p).ok();
    }

    // Phase E — Pruning

    #[test]
    fn prune_removes_old_proposals() {
        let p = tmp_dir("prune");
        let store = FsStore::open(&p).unwrap();
        for w in 1..=20u64 {
            store.archive_proposal(&make_header(w)).unwrap();
        }
        let removed = store.prune_proposals_before(10).unwrap();
        // removed: windows 1..=9
        assert_eq!(removed.len(), 9);
        // Current state proposals 10..20 должны оставаться
        for w in 10..=20u64 {
            assert!(store.get_proposal_by_window(w).unwrap().is_some());
        }
        // Pruned — absent
        for w in 1..=9u64 {
            assert!(store.get_proposal_by_window(w).unwrap().is_none());
        }
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn prune_does_not_touch_tables() {
        let p = tmp_dir("prune-tables");
        let store = FsStore::open(&p).unwrap();
        // Save tables
        let mut at = AccountTable::new();
        at.insert(make_account(1));
        store.save_account_table(&at).unwrap();
        // Archive and prune proposals
        store.archive_proposal(&make_header(5)).unwrap();
        store.prune_proposals_before(100).unwrap();
        // AccountTable intact
        let loaded = store.load_account_table().unwrap();
        assert_eq!(loaded.len(), 1);
        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn prune_empty_proposals_returns_empty() {
        let p = tmp_dir("prune-empty");
        let store = FsStore::open(&p).unwrap();
        let removed = store.prune_proposals_before(100).unwrap();
        assert!(removed.is_empty());
        fs::remove_dir_all(&p).ok();
    }

    // Integration: full restart cycle

    #[test]
    fn full_restart_cycle_state_preserved() {
        let p = tmp_dir("restart");

        // === Session 1 ===
        let store = FsStore::open(&p).unwrap();
        let mut at = AccountTable::new();
        for i in 1u8..=3 {
            at.insert(make_account(i));
        }
        let mut nt = NodeTable::new();
        for i in 1u8..=2 {
            nt.insert(make_node(i));
        }
        let mut pool = CandidatePool::new();
        pool.insert(make_candidate(10));

        let at_root_before = at.root();
        let nt_root_before = nt.root();
        let pool_root_before = pool.root();

        store.save_account_table(&at).unwrap();
        store.save_node_table(&nt).unwrap();
        store.save_candidate_pool(&pool).unwrap();
        store.archive_proposal(&make_header(50)).unwrap();
        store.save_meta_last_cemented(50).unwrap();

        drop(store); // close

        // === Session 2 (restart) ===
        let store2 = FsStore::open(&p).unwrap();
        let at2 = store2.load_account_table().unwrap();
        let nt2 = store2.load_node_table().unwrap();
        let pool2 = store2.load_candidate_pool().unwrap();
        let last = store2.verify_consistency().unwrap();

        assert_eq!(at2.root(), at_root_before);
        assert_eq!(nt2.root(), nt_root_before);
        assert_eq!(pool2.root(), pool_root_before);
        assert_eq!(last, 50);

        // Proposals can still be fetched
        let prop = store2.get_proposal_by_window(50).unwrap().unwrap();
        assert_eq!(prop.window_index, 50);

        fs::remove_dir_all(&p).ok();
    }

    #[test]
    fn sig_size_sanity() {
        // ML-DSA-65 (FIPS 204 level 3) sizes
        assert_eq!(SECRET_KEY_SIZE, 4032);
        assert_eq!(SIGNATURE_SIZE, 3309);
    }
}
