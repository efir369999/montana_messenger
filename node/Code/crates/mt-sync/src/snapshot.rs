//! Snapshot — typed wrapper over the raw bytes delivered by the
//! FastSyncResponse chunks. The wire format delivers each consensus table
//! (Account, Node, Candidate) as a sequence of fixed-size canonical-encoded
//! records; this module reassembles them into a tagged collection and
//! exposes both a verifier that recomputes `state_root` via the production
//! Sparse Merkle algorithm in `mt_state` and a `build_tables` constructor
//! that yields typed `AccountTable` / `NodeTable` / `CandidatePool` ready
//! for swap into a follower's `LocalState`.

use mt_state::{
    compute_state_root, AccountRecord, AccountTable, CandidatePool, CandidateRecord, NodeRecord,
    NodeTable, RecordDecodeError, ACCOUNT_RECORD_SIZE, CANDIDATE_RECORD_SIZE, NODE_RECORD_SIZE,
};

use crate::response::FastSyncTableId;

pub type Hash32 = [u8; 32];

/// Hard upper bound on the number of records a single Snapshot accumulator
/// can hold across all three tables. Caps the receiver-side memory budget
/// against a malicious server that streams unbounded chunks. The bound is
/// picked at the order of magnitude of one Montana account table on the
/// v1.0.x cohort (≈ 10^7 accounts × ≈ 2 KiB per record ≈ 20 GiB worst case);
/// production-scale fast-sync streaming will replace `Vec<Vec<u8>>` with a
/// disk-backed accumulator and lift this cap.
pub const MAX_FAST_SYNC_RECORDS: usize = 10_000_000;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Snapshot {
    pub anchor_window: u64,
    pub accounts: Vec<Vec<u8>>, // each entry == ACCOUNT_RECORD_SIZE bytes
    pub nodes: Vec<Vec<u8>>,    // each entry == NODE_RECORD_SIZE bytes
    pub candidates: Vec<Vec<u8>>, // each entry == CANDIDATE_RECORD_SIZE bytes
}

impl Snapshot {
    pub fn new(anchor_window: u64) -> Self {
        Snapshot {
            anchor_window,
            accounts: Vec::new(),
            nodes: Vec::new(),
            candidates: Vec::new(),
        }
    }

    pub fn add_record(
        &mut self,
        table: FastSyncTableId,
        bytes: Vec<u8>,
    ) -> Result<(), SnapshotError> {
        let expected = match table {
            FastSyncTableId::Account => ACCOUNT_RECORD_SIZE,
            FastSyncTableId::Node => NODE_RECORD_SIZE,
            FastSyncTableId::Candidate => CANDIDATE_RECORD_SIZE,
            FastSyncTableId::Proposals => {
                return Err(SnapshotError::ProposalsNotImplementedYet);
            },
        };
        if bytes.len() != expected {
            return Err(SnapshotError::WrongRecordSize {
                table,
                expected,
                actual: bytes.len(),
            });
        }
        if self.record_count() >= MAX_FAST_SYNC_RECORDS {
            return Err(SnapshotError::CapacityExceeded {
                cap: MAX_FAST_SYNC_RECORDS,
            });
        }
        match table {
            FastSyncTableId::Account => self.accounts.push(bytes),
            FastSyncTableId::Node => self.nodes.push(bytes),
            FastSyncTableId::Candidate => self.candidates.push(bytes),
            FastSyncTableId::Proposals => unreachable!(),
        }
        Ok(())
    }

    pub fn record_count(&self) -> usize {
        self.accounts.len() + self.nodes.len() + self.candidates.len()
    }

    /// Decode every raw record back into its typed form and insert into a
    /// fresh `AccountTable` / `NodeTable` / `CandidatePool`. This is the
    /// typed-insertion path that drives the production SMT verifier and the
    /// follower's LocalState replacement during fast-sync apply.
    ///
    /// Invariant: insertion order is the wire-delivery order. The Sparse
    /// Merkle root is order-independent (see `mt_state` tests), so the
    /// resulting `root()` byte-equals the proposer's recorded state_root
    /// for the same record set.
    pub fn build_tables(&self) -> Result<TypedTables, SnapshotError> {
        let mut accounts = AccountTable::new();
        for raw in &self.accounts {
            let rec = AccountRecord::decode(raw).map_err(|e| SnapshotError::DecodeFailed {
                table: FastSyncTableId::Account,
                err: e,
            })?;
            // Fail-stop on duplicate account_id: a stream that re-sends the
            // same record under a tampered intermediate state must not be
            // silently accepted (BTreeMap.insert otherwise overwrites without
            // signal).
            if accounts.contains(&rec.account_id) {
                return Err(SnapshotError::DuplicateRecord {
                    table: FastSyncTableId::Account,
                });
            }
            accounts.insert(rec);
        }
        let mut nodes = NodeTable::new();
        for raw in &self.nodes {
            let rec = NodeRecord::decode(raw).map_err(|e| SnapshotError::DecodeFailed {
                table: FastSyncTableId::Node,
                err: e,
            })?;
            if nodes.contains(&rec.node_id) {
                return Err(SnapshotError::DuplicateRecord {
                    table: FastSyncTableId::Node,
                });
            }
            nodes.insert(rec);
        }
        let mut candidates = CandidatePool::new();
        for raw in &self.candidates {
            let rec = CandidateRecord::decode(raw).map_err(|e| SnapshotError::DecodeFailed {
                table: FastSyncTableId::Candidate,
                err: e,
            })?;
            if candidates.contains(&rec.node_id) {
                return Err(SnapshotError::DuplicateRecord {
                    table: FastSyncTableId::Candidate,
                });
            }
            candidates.insert(rec);
        }
        Ok(TypedTables {
            accounts,
            nodes,
            candidates,
        })
    }
}

/// Typed result of `Snapshot::build_tables`. The follower applies fast-sync
/// by replacing its `LocalState.{accounts, nodes, candidates}` with these
/// fields after verification succeeds.
pub struct TypedTables {
    pub accounts: AccountTable,
    pub nodes: NodeTable,
    pub candidates: CandidatePool,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum SnapshotError {
    CapacityExceeded {
        cap: usize,
    },
    DuplicateRecord {
        table: FastSyncTableId,
    },
    WrongRecordSize {
        table: FastSyncTableId,
        expected: usize,
        actual: usize,
    },
    ProposalsNotImplementedYet,
    DecodeFailed {
        table: FastSyncTableId,
        err: RecordDecodeError,
    },
    StateRootMismatch {
        expected: Hash32,
        actual: Hash32,
    },
}

/// Production-grade state_root verifier. Decodes every record back into its
/// typed form, builds typed `mt_state` tables, and recomputes the
/// `state_root` via the same Sparse Merkle algorithm and the same
/// `compute_state_root` domain-separated combiner the proposer used to write
/// the anchor ProposalHeader. Byte-equal output across implementations is
/// the integrity contract M7 fast-sync depends on.
pub struct SnapshotVerifier;

impl SnapshotVerifier {
    pub fn verify(snapshot: &Snapshot, expected_state_root: &Hash32) -> Result<(), SnapshotError> {
        let tables = snapshot.build_tables()?;
        let computed = compute_state_root(
            &tables.nodes.root(),
            &tables.candidates.root(),
            &tables.accounts.root(),
        );
        if &computed != expected_state_root {
            return Err(SnapshotError::StateRootMismatch {
                expected: *expected_state_root,
                actual: computed,
            });
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::PUBLIC_KEY_SIZE;

    fn sample_account_bytes(seed: u8) -> Vec<u8> {
        let rec = AccountRecord {
            account_id: [seed; 32],
            balance: 1_000u128.wrapping_add(seed as u128),
            suite_id: 1,
            is_node_operator: seed % 2 == 0,
            frontier_hash: [seed; 32],
            op_height: seed as u32,
            account_chain_length: seed as u32,
            account_chain_length_snapshot: seed as u32,
            current_pubkey: [seed; PUBLIC_KEY_SIZE],
            creation_window: 0,
            last_op_window: 0,
            last_activation_window: 0,
        };
        let mut buf = Vec::with_capacity(ACCOUNT_RECORD_SIZE);
        use mt_codec::CanonicalEncode;
        rec.encode(&mut buf);
        buf
    }

    fn sample_node_bytes(seed: u8) -> Vec<u8> {
        let rec = NodeRecord {
            node_id: [seed; 32],
            node_pubkey: [seed; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [seed; 32],
            start_window: 0,
            chain_length: seed as u64,
            chain_length_snapshot: seed as u64,
            chain_length_checkpoints: [0; 6],
            last_confirmation_window: 0,
        };
        let mut buf = Vec::with_capacity(NODE_RECORD_SIZE);
        use mt_codec::CanonicalEncode;
        rec.encode(&mut buf);
        buf
    }

    fn sample_candidate_bytes(seed: u8) -> Vec<u8> {
        let rec = CandidateRecord {
            node_id: [seed; 32],
            node_pubkey: [seed; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [seed; 32],
            proof_endpoint: [seed; 32],
            w_start: 0,
            ssha_chain_length: 20_160,
            registration_window: seed as u64,
            expires: 90_480,
        };
        let mut buf = Vec::with_capacity(CANDIDATE_RECORD_SIZE);
        use mt_codec::CanonicalEncode;
        rec.encode(&mut buf);
        buf
    }

    #[test]
    fn add_record_size_check() {
        let mut s = Snapshot::new(0);
        let wrong = vec![0u8; 100];
        let err = s.add_record(FastSyncTableId::Account, wrong).unwrap_err();
        assert!(matches!(err, SnapshotError::WrongRecordSize { .. }));
    }

    #[test]
    fn add_record_accepts_correct_size() {
        let mut s = Snapshot::new(75850);
        s.add_record(FastSyncTableId::Account, sample_account_bytes(0xAB))
            .unwrap();
        s.add_record(FastSyncTableId::Node, sample_node_bytes(0xCD))
            .unwrap();
        s.add_record(FastSyncTableId::Candidate, sample_candidate_bytes(0xEF))
            .unwrap();
        assert_eq!(s.record_count(), 3);
        assert_eq!(s.anchor_window, 75850);
    }

    #[test]
    fn build_tables_typed_insertion_succeeds() {
        let mut s = Snapshot::new(0);
        s.add_record(FastSyncTableId::Account, sample_account_bytes(0x11))
            .unwrap();
        s.add_record(FastSyncTableId::Account, sample_account_bytes(0x22))
            .unwrap();
        s.add_record(FastSyncTableId::Node, sample_node_bytes(0x33))
            .unwrap();
        s.add_record(FastSyncTableId::Candidate, sample_candidate_bytes(0x44))
            .unwrap();
        let tables = s.build_tables().expect("build_tables");
        assert_eq!(tables.accounts.len(), 2);
        assert_eq!(tables.nodes.len(), 1);
        assert_eq!(tables.candidates.len(), 1);
    }

    #[test]
    fn build_tables_rejects_corrupt_account_record() {
        let mut s = Snapshot::new(0);
        let mut bad = sample_account_bytes(0x55);
        bad[50] = 7; // BadBoolByte
        s.accounts.push(bad);
        match s.build_tables() {
            Err(SnapshotError::DecodeFailed {
                table: FastSyncTableId::Account,
                err: RecordDecodeError::BadBoolByte(7),
            }) => {},
            Err(e) => panic!("expected DecodeFailed BadBoolByte, got Err {e:?}"),
            Ok(_) => panic!("expected DecodeFailed BadBoolByte, got Ok"),
        }
    }

    #[test]
    fn verifier_rejects_mismatched_root() {
        let mut s = Snapshot::new(0);
        s.add_record(FastSyncTableId::Account, sample_account_bytes(0xAB))
            .unwrap();
        let bogus_root = [0xFFu8; 32];
        let result = SnapshotVerifier::verify(&s, &bogus_root);
        assert!(matches!(
            result,
            Err(SnapshotError::StateRootMismatch { .. })
        ));
    }

    #[test]
    fn verifier_accepts_byte_equal_smt_root() {
        // Build a snapshot from typed records, then independently compute the
        // expected state_root via the very same SMT path the verifier uses
        // (mt_state::*Table::root()). The two must byte-equal.
        let mut s = Snapshot::new(75900);
        s.add_record(FastSyncTableId::Account, sample_account_bytes(0x11))
            .unwrap();
        s.add_record(FastSyncTableId::Account, sample_account_bytes(0x22))
            .unwrap();
        s.add_record(FastSyncTableId::Node, sample_node_bytes(0x33))
            .unwrap();
        s.add_record(FastSyncTableId::Candidate, sample_candidate_bytes(0x44))
            .unwrap();

        let tables = s.build_tables().expect("build_tables");
        let expected = compute_state_root(
            &tables.nodes.root(),
            &tables.candidates.root(),
            &tables.accounts.root(),
        );

        SnapshotVerifier::verify(&s, &expected).expect("verify");
    }

    #[test]
    fn verifier_order_independent_for_same_record_set() {
        // Two snapshots with the same records inserted in different order
        // MUST verify against the same expected state_root — the Sparse Merkle
        // root is order-independent by mt_state contract.
        let mut s1 = Snapshot::new(0);
        s1.add_record(FastSyncTableId::Account, sample_account_bytes(0x01))
            .unwrap();
        s1.add_record(FastSyncTableId::Account, sample_account_bytes(0x02))
            .unwrap();
        s1.add_record(FastSyncTableId::Account, sample_account_bytes(0x03))
            .unwrap();

        let mut s2 = Snapshot::new(0);
        s2.add_record(FastSyncTableId::Account, sample_account_bytes(0x03))
            .unwrap();
        s2.add_record(FastSyncTableId::Account, sample_account_bytes(0x01))
            .unwrap();
        s2.add_record(FastSyncTableId::Account, sample_account_bytes(0x02))
            .unwrap();

        let t1 = s1.build_tables().unwrap();
        let t2 = s2.build_tables().unwrap();
        assert_eq!(t1.accounts.root(), t2.accounts.root());

        let expected =
            compute_state_root(&t1.nodes.root(), &t1.candidates.root(), &t1.accounts.root());
        SnapshotVerifier::verify(&s1, &expected).expect("verify s1");
        SnapshotVerifier::verify(&s2, &expected).expect("verify s2");
    }
}

// ── Construction from live state + wire-chunk encoding ────────────────────────

impl Snapshot {
    /// Construct a Snapshot from the live `AccountTable` / `NodeTable` /
    /// `CandidatePool` by re-encoding each record into its canonical byte
    /// form (the same form delivered on the wire). Used by the M7
    /// server-side to serialize its current state at the requested
    /// `anchor_window`.
    pub fn from_tables(
        anchor_window: u64,
        accounts: &AccountTable,
        nodes: &NodeTable,
        candidates: &CandidatePool,
    ) -> Snapshot {
        use mt_codec::CanonicalEncode;
        let mut snap = Snapshot::new(anchor_window);
        for rec in accounts.iter() {
            let mut buf = Vec::with_capacity(ACCOUNT_RECORD_SIZE);
            rec.encode(&mut buf);
            snap.accounts.push(buf);
        }
        for rec in nodes.iter() {
            let mut buf = Vec::with_capacity(NODE_RECORD_SIZE);
            rec.encode(&mut buf);
            snap.nodes.push(buf);
        }
        for rec in candidates.iter() {
            let mut buf = Vec::with_capacity(CANDIDATE_RECORD_SIZE);
            rec.encode(&mut buf);
            snap.candidates.push(buf);
        }
        snap
    }

    /// Encode this Snapshot into a flat sequence of wire chunks suitable for
    /// FastSyncResponseChunk delivery. `records_per_chunk` bounds the per-
    /// chunk payload to avoid breaching the network envelope size limit;
    /// 32 records × 2059 B ≈ 64 KiB per chunk fits well inside Yamux frames.
    ///
    /// Chunks are flat-indexed across all three tables: e.g. if accounts
    /// produce 3 chunks and nodes produce 2 chunks and candidates produce
    /// 1 chunk, the wire envelope shows chunk_index 0..6 with
    /// total_chunks == 6.
    pub fn to_wire_chunks(&self, records_per_chunk: usize) -> Vec<WireChunk> {
        assert!(records_per_chunk > 0, "records_per_chunk must be > 0");
        let mut out: Vec<WireChunk> = Vec::new();
        push_table_chunks(
            &mut out,
            FastSyncTableId::Account,
            &self.accounts,
            records_per_chunk,
        );
        push_table_chunks(
            &mut out,
            FastSyncTableId::Node,
            &self.nodes,
            records_per_chunk,
        );
        push_table_chunks(
            &mut out,
            FastSyncTableId::Candidate,
            &self.candidates,
            records_per_chunk,
        );
        let total = out.len() as u32;
        for (i, c) in out.iter_mut().enumerate() {
            c.chunk_index = i as u32;
            c.total_chunks = total;
        }
        out
    }
}

/// Wire-format chunk identical in structure to `mt_net::FastSyncResponseChunk`
/// but defined in mt-sync so the snapshot layer stays independent of the
/// network crate's NetError type. The follower-side network adapter maps
/// these into `FastSyncResponseChunk` envelopes (1:1, no field rename).
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WireChunk {
    pub chunk_index: u32,
    pub total_chunks: u32,
    pub table_id: FastSyncTableId,
    pub records: Vec<Vec<u8>>,
}

fn push_table_chunks(
    out: &mut Vec<WireChunk>,
    table: FastSyncTableId,
    records: &[Vec<u8>],
    per_chunk: usize,
) {
    if records.is_empty() {
        return;
    }
    for batch in records.chunks(per_chunk) {
        out.push(WireChunk {
            chunk_index: 0,
            total_chunks: 0,
            table_id: table,
            records: batch.to_vec(),
        });
    }
}

#[cfg(test)]
mod wire_tests {
    use super::*;
    use mt_crypto::PUBLIC_KEY_SIZE;
    use mt_state::{AccountRecord, CandidateRecord, NodeRecord};

    fn make_account(seed: u8) -> AccountRecord {
        AccountRecord {
            account_id: [seed; 32],
            balance: 100,
            suite_id: 1,
            is_node_operator: false,
            frontier_hash: [seed; 32],
            op_height: 0,
            account_chain_length: 0,
            account_chain_length_snapshot: 0,
            current_pubkey: [seed; PUBLIC_KEY_SIZE],
            creation_window: 0,
            last_op_window: 0,
            last_activation_window: 0,
        }
    }
    fn make_node(seed: u8) -> NodeRecord {
        NodeRecord {
            node_id: [seed; 32],
            node_pubkey: [seed; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [seed; 32],
            start_window: 0,
            chain_length: seed as u64,
            chain_length_snapshot: seed as u64,
            chain_length_checkpoints: [0; 6],
            last_confirmation_window: 0,
        }
    }
    fn make_candidate(seed: u8) -> CandidateRecord {
        CandidateRecord {
            node_id: [seed; 32],
            node_pubkey: [seed; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [seed; 32],
            proof_endpoint: [seed; 32],
            w_start: 0,
            ssha_chain_length: 20_160,
            registration_window: seed as u64,
            expires: 90_480,
        }
    }

    #[test]
    fn from_tables_recovers_record_counts() {
        let mut accounts = AccountTable::new();
        accounts.insert(make_account(0x01));
        accounts.insert(make_account(0x02));
        let mut nodes = NodeTable::new();
        nodes.insert(make_node(0x10));
        let candidates = CandidatePool::new();

        let snap = Snapshot::from_tables(100, &accounts, &nodes, &candidates);
        assert_eq!(snap.anchor_window, 100);
        assert_eq!(snap.accounts.len(), 2);
        assert_eq!(snap.nodes.len(), 1);
        assert_eq!(snap.candidates.len(), 0);
    }

    #[test]
    fn from_tables_roundtrips_state_root() {
        let mut accounts = AccountTable::new();
        for i in 0..10u8 {
            accounts.insert(make_account(i + 1));
        }
        let mut nodes = NodeTable::new();
        for i in 0..3u8 {
            nodes.insert(make_node(i + 0x10));
        }
        let mut candidates = CandidatePool::new();
        for i in 0..2u8 {
            candidates.insert(make_candidate(i + 0x80));
        }

        let expected = compute_state_root(&nodes.root(), &candidates.root(), &accounts.root());

        let snap = Snapshot::from_tables(75900, &accounts, &nodes, &candidates);
        SnapshotVerifier::verify(&snap, &expected).expect("verify roundtrips state_root");
    }

    #[test]
    fn to_wire_chunks_indexes_and_totals() {
        let mut accounts = AccountTable::new();
        for i in 0..70u8 {
            accounts.insert(make_account(i + 1));
        }
        let nodes = NodeTable::new();
        let candidates = CandidatePool::new();
        let snap = Snapshot::from_tables(0, &accounts, &nodes, &candidates);

        let chunks = snap.to_wire_chunks(32);
        // 70 accounts / 32 per_chunk = 3 chunks (32 + 32 + 6)
        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0].chunk_index, 0);
        assert_eq!(chunks[0].total_chunks, 3);
        assert_eq!(chunks[2].chunk_index, 2);
        assert_eq!(chunks[2].total_chunks, 3);
        assert_eq!(chunks[0].records.len(), 32);
        assert_eq!(chunks[1].records.len(), 32);
        assert_eq!(chunks[2].records.len(), 6);
        for c in &chunks {
            assert_eq!(c.table_id, FastSyncTableId::Account);
        }
    }

    #[test]
    fn to_wire_chunks_spans_three_tables() {
        let mut accounts = AccountTable::new();
        accounts.insert(make_account(1));
        let mut nodes = NodeTable::new();
        nodes.insert(make_node(2));
        let mut candidates = CandidatePool::new();
        candidates.insert(make_candidate(3));
        let snap = Snapshot::from_tables(0, &accounts, &nodes, &candidates);

        let chunks = snap.to_wire_chunks(16);
        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0].table_id, FastSyncTableId::Account);
        assert_eq!(chunks[1].table_id, FastSyncTableId::Node);
        assert_eq!(chunks[2].table_id, FastSyncTableId::Candidate);
        for (i, c) in chunks.iter().enumerate() {
            assert_eq!(c.chunk_index, i as u32);
            assert_eq!(c.total_chunks, 3);
        }
    }
}
