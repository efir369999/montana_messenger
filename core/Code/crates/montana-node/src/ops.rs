//! User-operations plane of the node — Stage 1: intake and local validation.
//!
//! **This module does NOT change network state.** It only accepts operations, validates them against
//! the current rules (`mt_account::validate`) and holds them in memory until the window
//! takes them into an attestation. While the receiver is off — and by default it is off — the node
//! behaves exactly as before: `op_hashes` in the attestation stays empty, the state root
//! is computed the same way.
//!
//! Why intake is separate from application. Applying an operation means changing the state root;
//! a node that applied what the others did not drops out of the quorum. Intake changes nothing
//! and is therefore safe on its own — it can be enabled and observed without risking the network.

use mt_account::{op_hash, validate, OpError, Operation, ValidationContext};
use mt_crypto::Hash32;
use mt_state::AccountTable;
use std::collections::BTreeMap;

/// Intake queue ceiling. Without it the node would grow in memory from a foreign stream — the same
/// slow-bloat, only in RAM instead of state.
pub const MEMPOOL_MAX: usize = 4096;

/// Why an operation was not accepted.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum IntakeError {
    Disabled,
    Full,
    Duplicate,
    Invalid(OpError),
}

/// Intake queue. Storage order is lexicographic by `op_hash`: this is the canonical
/// application order (spec, "settle (apply at window close)"), and keeping it from the start is cheaper than
/// sorting at window time.
pub struct OpMempool {
    enabled: bool,
    pending: BTreeMap<Hash32, Operation>,
}

impl OpMempool {
    /// A disabled receiver: the node behaves as before the operations plane appeared.
    pub fn disabled() -> Self {
        Self {
            enabled: false,
            pending: BTreeMap::new(),
        }
    }
    pub fn enabled() -> Self {
        Self {
            enabled: true,
            pending: BTreeMap::new(),
        }
    }
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }
    pub fn len(&self) -> usize {
        self.pending.len()
    }
    pub fn is_empty(&self) -> bool {
        self.pending.is_empty()
    }

    /// Accept an operation. Validation uses the same rules as application: the node does not take into
    /// an attestation what it itself considers invalid.
    pub fn submit(
        &mut self,
        op: Operation,
        state: &AccountTable,
        ctx: &ValidationContext,
    ) -> Result<Hash32, IntakeError> {
        if !self.enabled {
            return Err(IntakeError::Disabled);
        }
        if self.pending.len() >= MEMPOOL_MAX {
            return Err(IntakeError::Full);
        }
        validate(&op, state, ctx).map_err(IntakeError::Invalid)?;
        let h = op_hash(&op);
        if self.pending.contains_key(&h) {
            return Err(IntakeError::Duplicate);
        }
        self.pending.insert(h, op);
        Ok(h)
    }

    /// What the node is ready to attest in this window: the first `limit` hashes in canonical order.
    /// The order is canonical, not "as it arrived": otherwise two honest nodes would attest different things
    /// given the same set, and the quorum would fall apart for no reason.
    pub fn attest(&self, limit: usize) -> Vec<Hash32> {
        self.pending.keys().copied().take(limit).collect()
    }

    /// Take the operations pinned by the quorum, in canonical application order.
    /// Unpinned ones stay waiting for the next window — they must not be lost.
    pub fn take_cemented(&mut self, cemented: &[Hash32]) -> Vec<Operation> {
        let mut out = Vec::new();
        let mut ordered: Vec<Hash32> = cemented.to_vec();
        ordered.sort_unstable();
        ordered.dedup();
        for h in ordered {
            if let Some(op) = self.pending.remove(&h) {
                out.push(op);
            }
        }
        out
    }

    /// Drop what has ceased to be valid (for example, the sender managed to advance
    /// its chain with another operation). Otherwise the queue would accumulate dead entries.
    pub fn prune_invalid(&mut self, state: &AccountTable, ctx: &ValidationContext) {
        if !self.enabled {
            return;
        }
        self.pending
            .retain(|_, op| validate(op, state, ctx).is_ok());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_account::Anchor;
    use mt_crypto::{Signature, SIGNATURE_SIZE};

    fn ctx() -> ValidationContext {
        ValidationContext {
            current_window: 10,
            tau2_windows: 20_160,
        }
    }

    fn anchor(data: u8) -> Operation {
        Operation::Anchor(Anchor {
            prev_hash: [0x44; 32],
            sender: [0xAA; 32],
            app_id: [0x88; 32],
            data_hash: [data; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        })
    }

    /// A disabled receiver accepts nothing: node behaviour is unchanged.
    #[test]
    fn disabled_takes_nothing() {
        let mut m = OpMempool::disabled();
        let st = AccountTable::new();
        assert_eq!(m.submit(anchor(1), &st, &ctx()), Err(IntakeError::Disabled));
        assert!(m.is_empty());
        assert!(m.attest(10).is_empty());
    }

    /// An invalid operation does not enter the queue: the node does not attest what it itself
    /// considers unfit. Here the sender is absent from the table — that is the rejection.
    #[test]
    fn invalid_operation_is_refused() {
        let mut m = OpMempool::enabled();
        let st = AccountTable::new();
        assert_eq!(
            m.submit(anchor(1), &st, &ctx()),
            Err(IntakeError::Invalid(OpError::AccountNotFound))
        );
        assert!(m.is_empty(), "the unfit operation did not enter the queue");
    }

    /// Attestation order is canonical: two nodes with the same set attest the same thing.
    #[test]
    fn attestation_order_is_canonical() {
        let mut a = OpMempool::enabled();
        let mut b = OpMempool::enabled();
        let ops = [anchor(3), anchor(1), anchor(2)];
        // arrival order is DIFFERENT
        for op in [&ops[0], &ops[1], &ops[2]] {
            a.pending.insert(op_hash(op), op.clone());
        }
        for op in [&ops[2], &ops[0], &ops[1]] {
            b.pending.insert(op_hash(op), op.clone());
        }
        assert_eq!(
            a.attest(10),
            b.attest(10),
            "attestation does not depend on arrival order"
        );
        let mut sorted = a.attest(10);
        sorted.sort_unstable();
        assert_eq!(a.attest(10), sorted, "order is lexicographic");
    }

    /// Pinned ones leave, unpinned ones stay waiting: an operation must not be lost.
    #[test]
    fn cemented_leave_others_stay() {
        let mut m = OpMempool::enabled();
        let ops = [anchor(1), anchor(2), anchor(3)];
        for op in &ops {
            m.pending.insert(op_hash(op), op.clone());
        }
        let taken = m.take_cemented(&[op_hash(&ops[0]), op_hash(&ops[2])]);
        assert_eq!(taken.len(), 2);
        assert_eq!(m.len(), 1, "the unpinned one stayed waiting for the next window");
    }

    /// What is taken is returned in canonical order, regardless of the order in the pinned list.
    #[test]
    fn cemented_are_returned_in_canonical_order() {
        let mut m = OpMempool::enabled();
        let ops = [anchor(1), anchor(2), anchor(3)];
        for op in &ops {
            m.pending.insert(op_hash(op), op.clone());
        }
        let mut hashes: Vec<Hash32> = ops.iter().map(op_hash).collect();
        hashes.reverse();
        let taken = m.take_cemented(&hashes);
        let got: Vec<Hash32> = taken.iter().map(op_hash).collect();
        let mut want = got.clone();
        want.sort_unstable();
        assert_eq!(got, want);
    }

    /// The queue ceiling holds: a foreign stream does not grow the node in memory without bound.
    #[test]
    fn mempool_has_a_ceiling() {
        let mut m = OpMempool::enabled();
        for i in 0..MEMPOOL_MAX {
            let op = anchor((i % 251) as u8);
            let mut o = op;
            if let Operation::Anchor(ref mut a) = o {
                a.prev_hash[0] = (i % 256) as u8;
                a.prev_hash[1] = (i / 256) as u8;
            }
            m.pending.insert(op_hash(&o), o);
        }
        assert_eq!(m.len(), MEMPOOL_MAX);
        let st = AccountTable::new();
        assert_eq!(m.submit(anchor(9), &st, &ctx()), Err(IntakeError::Full));
    }
}

/// Which operations are pinned by the quorum in the window.
///
/// An operation is pinned if its `op_hash` appears in the attestations of nodes whose total weight
/// has reached `need`. Node weight is the length of its chain, the same quantity as in the window quorum:
/// there is no second measure of weight in the protocol, and none may be introduced here.
///
/// The result order is canonical (lexicographic by `op_hash`) — the same one in which
/// operations are applied at window close.
pub fn cemented_op_hashes(confirmations: &[(Hash32, u64, Vec<Hash32>)], need: u64) -> Vec<Hash32> {
    let mut weight: BTreeMap<Hash32, u64> = BTreeMap::new();
    let mut counted: BTreeMap<Hash32, Vec<Hash32>> = BTreeMap::new();
    for (node, node_weight, hashes) in confirmations {
        for h in hashes {
            // One node is counted ONCE per operation, however many times it names it:
            // otherwise a repeat in its own attestation would give weight out of thin air.
            let seen = counted.entry(*h).or_default();
            if seen.contains(node) {
                continue;
            }
            seen.push(*node);
            *weight.entry(*h).or_insert(0) += *node_weight;
        }
    }
    weight
        .into_iter()
        .filter(|(_, w)| *w >= need)
        .map(|(h, _)| h)
        .collect()
}

#[cfg(test)]
mod cementing_tests {
    use super::*;

    fn h(b: u8) -> Hash32 {
        [b; 32]
    }

    /// An operation is pinned when the weight of the attesters has reached the threshold, and not before.
    #[test]
    fn quorum_by_weight_not_by_count() {
        let conf = vec![
            (h(1), 30u64, vec![h(0xAA)]),
            (h(2), 20u64, vec![h(0xAA)]),
            (h(3), 10u64, vec![h(0xBB)]),
        ];
        assert_eq!(cemented_op_hashes(&conf, 50), vec![h(0xAA)]);
        assert_eq!(cemented_op_hashes(&conf, 51), Vec::<Hash32>::new());
        assert_eq!(cemented_op_hashes(&conf, 10), vec![h(0xAA), h(0xBB)]);
    }

    /// A repeat in its own attestation adds no weight.
    #[test]
    fn repeat_in_one_confirmation_adds_nothing() {
        let conf = vec![(h(1), 40u64, vec![h(0xAA), h(0xAA), h(0xAA)])];
        assert_eq!(cemented_op_hashes(&conf, 41), Vec::<Hash32>::new());
        assert_eq!(cemented_op_hashes(&conf, 40), vec![h(0xAA)]);
    }

    /// The result is canonically ordered: all nodes have the same list.
    #[test]
    fn result_is_canonically_ordered() {
        let conf = vec![(h(1), 100u64, vec![h(0xCC), h(0xAA), h(0xBB)])];
        assert_eq!(
            cemented_op_hashes(&conf, 1),
            vec![h(0xAA), h(0xBB), h(0xCC)]
        );
    }

    /// An empty set of attestations pins emptiness — and that is not an error but an ordinary quiet window.
    #[test]
    fn empty_confirmations_cement_nothing() {
        assert_eq!(cemented_op_hashes(&[], 1), Vec::<Hash32>::new());
    }
}
