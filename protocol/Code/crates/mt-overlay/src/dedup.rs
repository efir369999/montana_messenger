//! Dedup of msg_id with a sliding window (Stage 1, mechanics step 4).
//! Local transport cache, not consensus state.

use std::collections::{HashSet, VecDeque};

use crate::frame::MsgId;

pub const DEDUP_WINDOW_CAP: usize = 4096;

pub struct DedupWindow {
    seen: HashSet<MsgId>,
    order: VecDeque<MsgId>,
    cap: usize,
}

impl Default for DedupWindow {
    fn default() -> Self {
        Self::with_capacity(DEDUP_WINDOW_CAP)
    }
}

impl DedupWindow {
    pub fn with_capacity(cap: usize) -> Self {
        // DEV-050(b): lazy — seen/order grow as items are inserted, NOT an eager-prealloc of cap
        // elements. Otherwise every first relay-subscribe of a new queue would allocate
        // ~160KB (HashSet+VecDeque for 4096) → node-DoS ×32 amplifier under mass
        // registration. cap stays the logical ceiling of the sliding window.
        Self {
            seen: HashSet::new(),
            order: VecDeque::new(),
            cap: cap.max(1),
        }
    }

    /// true — msg_id is new (accept); false — duplicate (drop).
    pub fn check_and_insert(&mut self, id: &MsgId) -> bool {
        if self.seen.contains(id) {
            return false;
        }
        if self.order.len() == self.cap {
            if let Some(old) = self.order.pop_front() {
                self.seen.remove(&old);
            }
        }
        self.order.push_back(*id);
        self.seen.insert(*id);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_rejected_fresh_accepted() {
        let mut w = DedupWindow::with_capacity(8);
        assert!(w.check_and_insert(&[1; 16]));
        assert!(!w.check_and_insert(&[1; 16]));
        assert!(w.check_and_insert(&[2; 16]));
    }

    #[test]
    fn window_slides_and_evicts_oldest() {
        let mut w = DedupWindow::with_capacity(2);
        assert!(w.check_and_insert(&[1; 16]));
        assert!(w.check_and_insert(&[2; 16]));
        assert!(w.check_and_insert(&[3; 16])); // evicts [1]
        assert!(w.check_and_insert(&[1; 16])); // new again after eviction
        assert!(!w.check_and_insert(&[3; 16]));
    }
}
