//! Stage 4 (second front) — cross-device reconciliation. A device that was offline catches up on what
//! it missed by dedup on (writer_tag, block_seq): it knows its per-writer watermarks (the highest
//! block_seq per writer), sends ArchiveSyncRequest (Stage 3) with from_block_seq = min over writers
//! (a lower bound), receives blocks block_seq ≥ from_block_seq, and dedups by (writer_tag, block_seq) —
//! catching up losslessly and without duplicates.
//!
//! Convergence criterion: after catch-up ArchiveRoot (Stage 2) is identical across all live devices.
//! A bare head_block_seq is insufficient under per-writer numbering (spec §178). The min-watermark
//! from is an optimization for the common case (a device behind on writers it already knows); a
//! writer the device has never seen (watermark absent) forces a full from=0 pull — signalled by an
//! ArchiveRoot mismatch, not by head_block_seq.
//!
//! Conflict on (writer_tag, block_seq) is impossible under the protocol (spec §179): block_seq is
//! assigned by the authoring device monotonically per writer, writer_tag is unique per writer; foreign
//! blocks arrive by fan-out under their own writer_tag and are not overwritten. Ingest still detects a
//! divergent-content collision defensively and reports it rather than silently overwriting.

use crate::archive::{block_hash, block_seq_of, block_writer_tag, open_block};
use crate::merkle::archive_root as merkle_archive_root;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ingest {
    New,
    Duplicate,
    Conflict,
    Invalid,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ReconcileReport {
    pub new: usize,
    pub duplicate: usize,
    pub conflict: usize,
    pub invalid: usize,
}

/// Archive as a set of blocks keyed by (writer_tag, block_seq) → H(open block). The BTreeMap iterates
/// in canonical (writer_tag, block_seq) order — exactly the ArchiveRoot leaf order (spec §97).
#[derive(Debug, Clone, Default)]
pub struct ArchiveIndex {
    blocks: BTreeMap<([u8; 4], u64), [u8; 32]>,
}

impl ArchiveIndex {
    pub fn new() -> Self {
        Self {
            blocks: BTreeMap::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.blocks.len()
    }

    pub fn is_empty(&self) -> bool {
        self.blocks.is_empty()
    }

    pub fn contains(&self, writer_tag: [u8; 4], block_seq: u64) -> bool {
        self.blocks.contains_key(&(writer_tag, block_seq))
    }

    /// Insert a (writer_tag, block_seq) → H(block) entry with dedup. Present + same hash → Duplicate;
    /// present + different hash → Conflict (keep the first, report). Absent → New.
    pub fn insert(&mut self, writer_tag: [u8; 4], block_seq: u64, h: [u8; 32]) -> Ingest {
        match self.blocks.get(&(writer_tag, block_seq)) {
            Some(existing) if *existing == h => Ingest::Duplicate,
            Some(_) => Ingest::Conflict,
            None => {
                self.blocks.insert((writer_tag, block_seq), h);
                Ingest::New
            },
        }
    }

    /// Ingest one as-stored sealed block: recover (writer_tag, block_seq) from the nonce prefix, open
    /// under history_key to H(open block). Any framing/decrypt failure → Invalid (never panic).
    pub fn ingest_sealed(
        &mut self,
        history_key: &[u8; 32],
        account_id: &[u8; 32],
        sealed: &[u8],
    ) -> Ingest {
        let (wt, seq) = match (block_writer_tag(sealed), block_seq_of(sealed)) {
            (Some(wt), Some(seq)) => (wt, seq),
            _ => return Ingest::Invalid,
        };
        let block = match open_block(history_key, account_id, sealed) {
            Some(b) => b,
            None => return Ingest::Invalid,
        };
        self.insert(wt, seq, block_hash(&block))
    }

    /// Per-writer watermarks: the highest block_seq seen for each writer_tag.
    pub fn watermarks(&self) -> BTreeMap<[u8; 4], u64> {
        let mut w: BTreeMap<[u8; 4], u64> = BTreeMap::new();
        for (wt, seq) in self.blocks.keys() {
            let e = w.entry(*wt).or_insert(0);
            if *seq > *e {
                *e = *seq;
            }
        }
        w
    }

    /// Lower bound for ArchiveSyncRequest.from_block_seq: the minimum per-writer watermark. Empty → 0
    /// (onboarding = full archive). This is an optimization; ArchiveRoot equality is the real criterion.
    pub fn catchup_from(&self) -> u64 {
        self.watermarks().values().copied().min().unwrap_or(0)
    }

    /// Indicator only (spec §156): the maximum block_seq across writers. Not a convergence criterion.
    pub fn head_block_seq(&self) -> u64 {
        self.blocks.keys().map(|(_, seq)| *seq).max().unwrap_or(0)
    }

    /// ArchiveRoot over all blocks in canonical (writer_tag, block_seq) order. None when the archive is
    /// empty (not anchored, spec §100). Identical across devices ⇔ converged.
    pub fn archive_root(&self) -> Option<[u8; 32]> {
        if self.blocks.is_empty() {
            return None;
        }
        let ordered: Vec<[u8; 32]> = self.blocks.values().copied().collect();
        merkle_archive_root(&ordered)
    }
}

/// Apply an ArchiveSyncResponse's as-stored sealed blocks into the local index with dedup by
/// (writer_tag, block_seq). Idempotent: a repeated (writer_tag, block_seq) is ignored (spec §176).
pub fn reconcile(
    local: &mut ArchiveIndex,
    history_key: &[u8; 32],
    account_id: &[u8; 32],
    response_sealed_blocks: &[Vec<u8>],
) -> ReconcileReport {
    let mut r = ReconcileReport::default();
    for sealed in response_sealed_blocks {
        match local.ingest_sealed(history_key, account_id, sealed) {
            Ingest::New => r.new += 1,
            Ingest::Duplicate => r.duplicate += 1,
            Ingest::Conflict => r.conflict += 1,
            Ingest::Invalid => r.invalid += 1,
        }
    }
    r
}

/// Responder side (a live device): from its stored sealed blocks, select those with block_seq ≥
/// from_block_seq across all writers, returned in canonical (writer_tag, block_seq) order (spec §156).
pub fn select_for_sync(stored_sealed: &[Vec<u8>], from_block_seq: u64) -> Vec<Vec<u8>> {
    let mut selected: Vec<([u8; 4], u64, Vec<u8>)> = stored_sealed
        .iter()
        .filter_map(|s| {
            let seq = block_seq_of(s)?;
            let wt = block_writer_tag(s)?;
            if seq >= from_block_seq {
                Some((wt, seq, s.clone()))
            } else {
                None
            }
        })
        .collect();
    selected.sort_by(|a, b| (a.0, a.1).cmp(&(b.0, b.1)));
    selected.into_iter().map(|(_, _, s)| s).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::archive::{history_key, seal_block, HistoryBlock, HistoryItem, DIR_OUT};

    const ACCT: [u8; 32] = [0x33u8; 32];
    const DEV_A: [u8; 16] = [0x01u8; 16];
    const DEV_B: [u8; 16] = [0x02u8; 16];
    const DEV_C: [u8; 16] = [0x03u8; 16];

    fn hk() -> [u8; 32] {
        history_key(&[0x55u8; 32])
    }

    fn sealed(device_id: &[u8; 16], seq: u64, tag: u8) -> Vec<u8> {
        let b = HistoryBlock {
            block_seq: seq,
            items: vec![HistoryItem {
                conv_id: [tag; 32],
                dir: DIR_OUT,
                send_time: 1000 + seq,
                content: vec![tag, seq as u8],
            }],
        };
        seal_block(&hk(), &ACCT, device_id, &b)
    }

    fn index_from(blocks: &[Vec<u8>]) -> ArchiveIndex {
        let mut idx = ArchiveIndex::new();
        for s in blocks {
            assert_ne!(idx.ingest_sealed(&hk(), &ACCT, s), Ingest::Invalid);
        }
        idx
    }

    #[test]
    fn dedup_idempotent() {
        let s = sealed(&DEV_A, 0, 0xa0);
        let mut idx = ArchiveIndex::new();
        assert_eq!(idx.ingest_sealed(&hk(), &ACCT, &s), Ingest::New);
        assert_eq!(idx.ingest_sealed(&hk(), &ACCT, &s), Ingest::Duplicate);
        assert_eq!(idx.ingest_sealed(&hk(), &ACCT, &s), Ingest::Duplicate);
        assert_eq!(idx.len(), 1);
    }

    #[test]
    fn watermarks_and_from() {
        // wA: seq 0,1,2 ; wB: seq 0,1
        let blocks = vec![
            sealed(&DEV_A, 0, 0xa0),
            sealed(&DEV_A, 1, 0xa1),
            sealed(&DEV_A, 2, 0xa2),
            sealed(&DEV_B, 0, 0xb0),
            sealed(&DEV_B, 1, 0xb1),
        ];
        let idx = index_from(&blocks);
        let w = idx.watermarks();
        assert_eq!(w.len(), 2);
        assert_eq!(idx.head_block_seq(), 2);
        assert_eq!(idx.catchup_from(), 1); // min(2,1)
    }

    #[test]
    fn conflict_detected_not_overwritten() {
        // Same (writer_tag, block_seq), different content → Conflict, first kept.
        let s1 = sealed(&DEV_A, 0, 0xa0);
        let s2 = sealed(&DEV_A, 0, 0xff); // different content, same device+seq
        let mut idx = ArchiveIndex::new();
        assert_eq!(idx.ingest_sealed(&hk(), &ACCT, &s1), Ingest::New);
        assert_eq!(idx.ingest_sealed(&hk(), &ACCT, &s2), Ingest::Conflict);
        assert_eq!(idx.len(), 1);
    }

    #[test]
    fn converges_min_watermark_optimization() {
        // Full archive: wA seq 0,1,2 ; wB seq 0,1,2.
        let full = vec![
            sealed(&DEV_A, 0, 0xa0),
            sealed(&DEV_A, 1, 0xa1),
            sealed(&DEV_A, 2, 0xa2),
            sealed(&DEV_B, 0, 0xb0),
            sealed(&DEV_B, 1, 0xb1),
            sealed(&DEV_B, 2, 0xb2),
        ];
        let full_idx = index_from(&full);

        // Offline device C had wA 0,1 and wB 0,1 (behind by one on each known writer).
        let mut c = index_from(&[
            sealed(&DEV_A, 0, 0xa0),
            sealed(&DEV_A, 1, 0xa1),
            sealed(&DEV_B, 0, 0xb0),
            sealed(&DEV_B, 1, 0xb1),
        ]);
        assert_ne!(c.archive_root(), full_idx.archive_root());

        let from = c.catchup_from(); // min(1,1) = 1 — skips seq-0 blocks
        assert_eq!(from, 1);
        let response = select_for_sync(&full, from);
        // response must NOT include seq-0 blocks (already held), must include the missed seq-2 ones
        assert_eq!(response.len(), 4); // (wA,1),(wA,2),(wB,1),(wB,2)

        let report = reconcile(&mut c, &hk(), &ACCT, &response);
        assert_eq!(report.new, 2); // (wA,2),(wB,2)
        assert_eq!(report.duplicate, 2); // (wA,1),(wB,1)
        assert_eq!(report.conflict, 0);
        assert_eq!(c.archive_root(), full_idx.archive_root()); // converged
    }

    #[test]
    fn new_writer_forces_full_pull() {
        // Honest boundary: min-watermark under-fetches a writer the device has never seen.
        // Full archive adds wC (new) with seq 0,1 the offline device never saw.
        let full = vec![
            sealed(&DEV_A, 0, 0xa0),
            sealed(&DEV_A, 1, 0xa1),
            sealed(&DEV_B, 0, 0xb0),
            sealed(&DEV_B, 1, 0xb1),
            sealed(&DEV_C, 0, 0xc0),
            sealed(&DEV_C, 1, 0xc1),
        ];
        let full_idx = index_from(&full);

        // Device knows only wA,wB up to seq 1 → from = min(1,1) = 1.
        let mut d = index_from(&[
            sealed(&DEV_A, 0, 0xa0),
            sealed(&DEV_A, 1, 0xa1),
            sealed(&DEV_B, 0, 0xb0),
            sealed(&DEV_B, 1, 0xb1),
        ]);
        let from = d.catchup_from();
        assert_eq!(from, 1);

        // from=1 misses (wC,0) → ArchiveRoot mismatch (non-convergence is detected).
        let partial = select_for_sync(&full, from);
        reconcile(&mut d, &hk(), &ACCT, &partial);
        assert_ne!(
            d.archive_root(),
            full_idx.archive_root(),
            "min-watermark under-fetches a fresh writer; mismatch must be visible"
        );

        // Convergence criterion (ArchiveRoot) triggers a full from=0 re-pull → converges.
        let full_response = select_for_sync(&full, 0);
        reconcile(&mut d, &hk(), &ACCT, &full_response);
        assert_eq!(d.archive_root(), full_idx.archive_root());
    }

    #[test]
    fn gap_below_watermark_forces_full_pull() {
        // Reception gap: device holds (wA,0) and (wA,2) but missed (wA,1). block_seq is gapless on the
        // WRITER side (spec §69), but a receiver can have holes. Watermark wA=2 → from=2 misses (wA,1);
        // ArchiveRoot mismatch signals it (not silently lost) → full from=0 re-pull converges.
        let full = vec![
            sealed(&DEV_A, 0, 0xa0),
            sealed(&DEV_A, 1, 0xa1),
            sealed(&DEV_A, 2, 0xa2),
        ];
        let full_idx = index_from(&full);

        let mut d = index_from(&[sealed(&DEV_A, 0, 0xa0), sealed(&DEV_A, 2, 0xa2)]);
        assert_eq!(d.catchup_from(), 2); // min watermark = 2, over the gap at 1
        let partial = select_for_sync(&full, 2);
        reconcile(&mut d, &hk(), &ACCT, &partial);
        assert_ne!(
            d.archive_root(),
            full_idx.archive_root(),
            "gap must remain visible"
        );

        reconcile(&mut d, &hk(), &ACCT, &select_for_sync(&full, 0));
        assert_eq!(d.archive_root(), full_idx.archive_root());
    }

    #[test]
    fn tombstone_replicates_as_ordinary_block() {
        // A deletion tombstone (control-Content, first front) rides as an ordinary HistoryBlock and
        // replicates by (writer_tag, block_seq) like any other — reconcile is content-agnostic (spec §174).
        let receipt = crate::content::encode_receipt(
            crate::content::TYPE_DELIVERY,
            &[0x11u8; 16],
            2000,
            &[0x22u8; 16],
        );
        let tomb = HistoryBlock {
            block_seq: 1,
            items: vec![HistoryItem {
                conv_id: [0xa0u8; 32],
                dir: DIR_OUT,
                send_time: 1001,
                content: receipt,
            }],
        };
        let sealed_tomb = seal_block(&hk(), &ACCT, &DEV_A, &tomb);

        let full = vec![sealed(&DEV_A, 0, 0xa0), sealed_tomb.clone()];
        let full_idx = index_from(&full);
        let mut d = index_from(&[sealed(&DEV_A, 0, 0xa0)]);
        assert_ne!(d.archive_root(), full_idx.archive_root());
        let from = d.catchup_from();
        reconcile(&mut d, &hk(), &ACCT, &select_for_sync(&full, from));
        assert_eq!(d.archive_root(), full_idx.archive_root());
    }

    #[test]
    fn order_independent_convergence() {
        // Same block set applied in different receive orders → identical ArchiveRoot (canonical order).
        let full = vec![
            sealed(&DEV_A, 0, 0xa0),
            sealed(&DEV_A, 1, 0xa1),
            sealed(&DEV_B, 0, 0xb0),
        ];
        let idx1 = index_from(&full);
        let mut rev = full.clone();
        rev.reverse();
        let idx2 = index_from(&rev);
        assert_eq!(idx1.archive_root(), idx2.archive_root());
        assert!(idx1.archive_root().is_some());
    }

    #[test]
    fn empty_archive_no_root() {
        let idx = ArchiveIndex::new();
        assert_eq!(idx.archive_root(), None);
        assert_eq!(idx.catchup_from(), 0);
        assert_eq!(idx.head_block_seq(), 0);
    }

    #[test]
    fn invalid_sealed_reported() {
        let mut idx = ArchiveIndex::new();
        assert_eq!(idx.ingest_sealed(&hk(), &ACCT, &[0u8; 5]), Ingest::Invalid); // too short
                                                                                 // wrong account → open fails → Invalid
        let s = sealed(&DEV_A, 0, 0xa0);
        assert_eq!(idx.ingest_sealed(&hk(), &[0x44u8; 32], &s), Ingest::Invalid);
        assert_eq!(idx.len(), 0);
    }
}
