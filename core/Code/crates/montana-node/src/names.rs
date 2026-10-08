//! Names layer on the node: batch, index, bucket, intake of requests (checklist C-14, C-16..C-18).
//!
//! **The subsystem is disabled by default.** Until the author has verified it live, the node
//! behaves exactly as before: `NamesService::disabled()` assembles no batches, does not scan the
//! chain and does not answer requests. No existing node branch calls this module — enabling it is
//! explicit and a separate decision.

use mt_account::Anchor;
use mt_crypto::Hash32;
use mt_names::{NameCommit, NameRenew, NameReveal, ServeError};
use mt_state::AccountId;
use std::collections::VecDeque;

/// How many windows the node holds a request for an absent owner.
/// One window: longer would mean storing someone else's data, and third-party storage is absent
/// from the model.
pub const REQUEST_HOLD_WINDOWS: u32 = 1;

/// What the node collected during a window and what of it goes to the chain.
#[derive(Default)]
pub struct NamesBatch {
    objects: Vec<Vec<u8>>,
}

impl NamesBatch {
    fn objects_push(&mut self, o: Vec<u8>) {
        self.objects.push(o);
    }
    pub fn push_commit(&mut self, c: &NameCommit) {
        self.objects.push(c.encode());
    }
    pub fn push_reveal(&mut self, r: &NameReveal) {
        self.objects.push(r.encode());
    }
    pub fn push_renew(&mut self, r: &NameRenew) {
        self.objects.push(r.encode());
    }
    pub fn len(&self) -> usize {
        self.objects.len()
    }
    pub fn is_empty(&self) -> bool {
        self.objects.is_empty()
    }
    /// Batch root. Only it and `app_id` go to the chain — no name, no cell, no anchor.
    pub fn root(&self) -> [u8; 32] {
        mt_names::batch_root(&self.objects)
    }
    /// Anchor for the chain. The sender is THE NODE ITSELF: a client does not anchor layer objects
    /// from its own account, otherwise anchoring would reveal who exactly took a name.
    pub fn anchor_op(&self, node_account: AccountId, prev_hash: Hash32) -> Option<Anchor> {
        if self.is_empty() {
            return None;
        }
        Some(Anchor {
            prev_hash,
            sender: node_account,
            app_id: mt_names::app_id(),
            data_hash: self.root(),
            // The caller signs: the node key does not live here. Empty is the "unsigned" marker,
            // and the node must sign before sending; the chain will not accept an unsigned anchor.
            signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
        })
    }
    pub fn take(&mut self) -> Vec<Vec<u8>> {
        std::mem::take(&mut self.objects)
    }
}

/// A request waiting for its owner.
pub struct HeldRequest {
    pub slot: [u8; 32],
    pub sealed: Vec<u8>,
    pub window: u32,
}

/// Names layer on the node. Created disabled; enabled by an explicit decision.
pub struct NamesService {
    enabled: bool,
    batch: NamesBatch,
    index: Vec<[u8; 32]>,
    held: VecDeque<HeldRequest>,
}

impl NamesService {
    /// Disabled service: the node behaves exactly as before the layer existed.
    pub fn disabled() -> Self {
        Self {
            enabled: false,
            batch: NamesBatch::default(),
            index: Vec::new(),
            held: VecDeque::new(),
        }
    }
    pub fn enabled() -> Self {
        Self {
            enabled: true,
            ..Self::disabled()
        }
    }
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// The occupancy index is built by scanning REVEALS from the proposal chain, not the state
    /// table: it is derived and is not authoritative.
    pub fn rebuild_index(&mut self, reveals: &[NameReveal]) {
        if !self.enabled {
            return;
        }
        self.index = mt_names::occupancy_index(reveals);
    }
    pub fn occupied(&self) -> u64 {
        self.index.len() as u64
    }

    /// Hand out the whole bucket. A request for a single cell is rejected — the node must not learn
    /// whom the asker is interested in.
    pub fn serve(
        &self,
        wanted_bucket: u64,
        single_slot: bool,
    ) -> Result<Vec<[u8; 32]>, ServeError> {
        if single_slot {
            return Err(ServeError::SingleSlotRequested);
        }
        Ok(mt_names::serve_bucket(
            &self.index,
            wanted_bucket,
            self.occupied(),
        ))
    }

    /// Accept a request for an owner: the puzzle is checked with one hash, and only then is the
    /// request queued. If the owner is offline, the request waits EXACTLY one window.
    pub fn accept(
        &mut self,
        slot: [u8; 32],
        eph_pk: &[u8],
        nonce: &[u8],
        sealed: Vec<u8>,
        window: u32,
    ) -> Result<(), ServeError> {
        if !self.enabled {
            return Ok(()); // disabled — silently do nothing, node behaviour is unchanged
        }
        mt_names::accept_request(&slot, eph_pk, nonce, false)?;
        self.held.push_back(HeldRequest {
            slot,
            sealed,
            window,
        });
        Ok(())
    }

    /// Take the requests for an owner and drop the expired ones. Storage of others' data does not
    /// accumulate.
    pub fn drain_for(&mut self, slot: &[u8; 32], now: u32) -> Vec<Vec<u8>> {
        self.held
            .retain(|r| now.saturating_sub(r.window) <= REQUEST_HOLD_WINDOWS);
        let mut out = Vec::new();
        let mut keep = VecDeque::new();
        while let Some(r) = self.held.pop_front() {
            if r.slot == *slot {
                out.push(r.sealed);
            } else {
                keep.push_back(r);
            }
        }
        self.held = keep;
        out
    }
    pub fn held_count(&self) -> usize {
        self.held.len()
    }

    /// Intake of a layer object from a client: it accumulates until the end of the window and goes
    /// to the chain as ONE batch.
    /// A batch instead of separate anchors is not a saving but a cover: one anchor per object would
    /// show how many names are being taken right now.
    pub fn intake(&mut self, object: Vec<u8>) {
        if !self.enabled {
            return;
        }
        self.batch.objects_push(object);
    }
    pub fn batch_len(&self) -> usize {
        self.batch.len()
    }

    /// Assemble the window anchor and clear the batch. Returns an UNSIGNED anchor: the caller signs
    /// with the node key — the key lives in identity, not in this module.
    pub fn take_anchor(&mut self, node_account: AccountId, prev_hash: Hash32) -> Option<Anchor> {
        if !self.enabled || self.batch.is_empty() {
            return None;
        }
        let a = self.batch.anchor_op(node_account, prev_hash);
        self.batch = NamesBatch::default();
        a
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reveal(name: &str) -> NameReveal {
        NameReveal {
            slot: mt_names::slot(name),
            anchor: [0; 32],
            nonce: [0; 32],
            commit_win: 1,
        }
    }

    /// A disabled service does NOTHING: the node behaves as before the layer existed.
    #[test]
    fn disabled_service_is_inert() {
        let mut s = NamesService::disabled();
        s.rebuild_index(&[reveal("alicemontana")]);
        assert_eq!(s.occupied(), 0, "a disabled service builds no index");
        assert_eq!(s.accept([0; 32], &[], &[], vec![1, 2, 3], 1), Ok(()));
        assert_eq!(s.held_count(), 0, "a disabled service holds nothing");
    }

    /// An empty batch is not anchored: an empty anchor would be an "the layer is alive" message,
    /// i.e. noise in the chain.
    #[test]
    fn empty_batch_is_not_anchored() {
        let b = NamesBatch::default();
        assert!(b.anchor_op([1; 32], [0; 32]).is_none());
    }

    /// The chain receives the layer app_id and the batch root — and nothing else.
    #[test]
    fn anchor_carries_only_app_id_and_root() {
        let mut b = NamesBatch::default();
        b.push_commit(&NameCommit { commit: [7; 32] });
        let a = b.anchor_op([1; 32], [2; 32]).expect("batch is non-empty");
        assert_eq!(a.app_id, mt_names::app_id());
        assert_eq!(a.data_hash, b.root());
        assert_eq!(a.sender, [1; 32], "the sender is the node, not the client");
    }

    #[test]
    fn index_and_bucket_serving() {
        let mut s = NamesService::enabled();
        let names: Vec<String> = (0..600).map(|i| format!("user{i:05}")).collect();
        let reveals: Vec<NameReveal> = names.iter().map(|n| reveal(n)).collect();
        s.rebuild_index(&reveals);
        assert_eq!(s.occupied(), 600);
        let target = mt_names::slot(&names[0]);
        let b = mt_names::bucket(&target, s.occupied());
        let served = s.serve(b, false).expect("bucket is served");
        assert!(served.contains(&target));
        assert!(
            served.len() > 1,
            "the bucket holds more than one cell — otherwise there is no cover"
        );
        assert_eq!(s.serve(b, true), Err(ServeError::SingleSlotRequested));
    }

    /// A request waits exactly one window: storage of others' data does not accumulate.
    #[test]
    fn request_is_held_for_one_window_only() {
        let mut s = NamesService::enabled();
        let sl = mt_names::slot("anna");
        let eph = vec![0x5A; 1184];
        let nonce = 810_487u64.to_le_bytes();
        assert_eq!(s.accept(sl, &eph, &nonce, vec![9, 9], 100), Ok(()));
        assert_eq!(s.held_count(), 1);
        assert!(s.drain_for(&sl, 102).is_empty(), "the expired one is dropped");
        assert_eq!(s.held_count(), 0);

        assert_eq!(s.accept(sl, &eph, &nonce, vec![9, 9], 100), Ok(()));
        assert_eq!(s.drain_for(&sl, 101).len(), 1, "within the deadline — handed out");
    }

    /// An unsolved puzzle is rejected before any queueing.
    #[test]
    fn unsolved_puzzle_never_enters_the_queue() {
        let mut s = NamesService::enabled();
        let sl = mt_names::slot("anna");
        assert_eq!(
            s.accept(sl, &[0x5A; 1184], &[0; 8], vec![1], 1),
            Err(ServeError::PuzzleUnsolved)
        );
        assert_eq!(s.held_count(), 0);
    }

    /// Another owner's request is not handed out: the slot is checked.
    #[test]
    fn other_slot_is_not_handed_over() {
        let mut s = NamesService::enabled();
        let mine = mt_names::slot("anna");
        let other = mt_names::slot("bobbbb");
        let eph = vec![0x5A; 1184];
        let nonce = 810_487u64.to_le_bytes();
        let _ = s.accept(mine, &eph, &nonce, vec![1], 5);
        assert!(s.drain_for(&other, 5).is_empty());
        assert_eq!(s.held_count(), 1, "the foreign request stays with its own owner");
    }
}

#[cfg(test)]
mod publish_tests {
    use super::*;

    /// A disabled service accepts nothing and gives no anchor — the chain does not change by a
    /// single byte.
    #[test]
    fn disabled_publishes_nothing() {
        let mut s = NamesService::disabled();
        s.intake(vec![1, 2, 3]);
        assert_eq!(s.batch_len(), 0);
        assert!(s.take_anchor([1; 32], [0; 32]).is_none());
    }

    /// Enabled: objects accumulate and go out as ONE batch, after which the batch is empty.
    #[test]
    fn enabled_publishes_one_anchor_per_window() {
        let mut s = NamesService::enabled();
        s.intake(NameCommit { commit: [1; 32] }.encode());
        s.intake(NameCommit { commit: [2; 32] }.encode());
        assert_eq!(s.batch_len(), 2);
        let a = s.take_anchor([9; 32], [7; 32]).expect("batch is non-empty");
        assert_eq!(a.app_id, mt_names::app_id());
        assert_eq!(a.sender, [9; 32]);
        assert_eq!(s.batch_len(), 0, "the batch went out whole");
        assert!(
            s.take_anchor([9; 32], [7; 32]).is_none(),
            "an empty window gives no anchor"
        );
    }

    /// The number of objects in a window is not visible from the anchor: two different sets give an
    /// anchor of the same size.
    #[test]
    fn anchor_size_hides_the_count() {
        let mut a = NamesService::enabled();
        a.intake(NameCommit { commit: [1; 32] }.encode());
        let one = a.take_anchor([9; 32], [7; 32]).unwrap();
        let mut b = NamesService::enabled();
        for i in 0..50u8 {
            b.intake(NameCommit { commit: [i; 32] }.encode());
        }
        let fifty = b.take_anchor([9; 32], [7; 32]).unwrap();
        assert_eq!(one.data_hash.len(), fifty.data_hash.len());
        assert_ne!(one.data_hash, fifty.data_hash);
    }
}
