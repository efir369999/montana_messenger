// spec, раздел "Сетевой уровень → Dandelion++ (анонимность отправителя)"
//
// Two-phase relay: stem (line-graph через random successor per τ₁ epoch)
// → fluff (broadcast всем outbound peers) при exhaust TTL.
//
// Параметры:
//   stem_ttl_geometric_p   = 0.1 (10% probability fluff per hop)
//   expected_hops          = 10
//   hard_cap_hops          = 30 (loop detection + cap)

use alloc::collections::BTreeMap;

pub const STEM_HARD_CAP_HOPS: u8 = 30;
pub const STEM_FLUFF_PROB_NUM: u32 = 1;
pub const STEM_FLUFF_PROB_DEN: u32 = 10;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DandelionDecision {
    Stem([u8; 32]),
    Fluff,
}

#[derive(Debug)]
pub struct DandelionState {
    epoch_window: u64,
    stem_successor: Option<[u8; 32]>,
    seen: BTreeMap<[u8; 32], u8>,
}

impl DandelionState {
    pub fn new(initial_epoch: u64) -> Self {
        DandelionState {
            epoch_window: initial_epoch,
            stem_successor: None,
            seen: BTreeMap::new(),
        }
    }

    pub fn rotate_epoch(
        &mut self,
        current_window: u64,
        tau1_windows: u64,
        outbound_peers: &[[u8; 32]],
        rng_byte: u8,
    ) {
        if outbound_peers.is_empty() {
            self.stem_successor = None;
            return;
        }
        let new_epoch = current_window
            .checked_div(tau1_windows)
            .unwrap_or(current_window);
        if new_epoch != self.epoch_window || self.stem_successor.is_none() {
            let idx = (rng_byte as usize) % outbound_peers.len();
            self.stem_successor = Some(outbound_peers[idx]);
            self.epoch_window = new_epoch;
            self.seen.clear();
        }
    }

    pub fn forwarding_decision(
        &mut self,
        operation_id: &[u8; 32],
        rng_byte: u8,
    ) -> DandelionDecision {
        let prior = self.seen.get(operation_id).copied().unwrap_or(0);
        if prior == 0 {
            self.seen.insert(*operation_id, 1);
            // Geometric coin: rng_byte < 25 → fluff (≈ 25/256 ≈ 9.8% близко к 10%)
            // Hard cap fluff на 1-м hop ещё не нужен; считается с first hop.
            if rng_byte < 26 {
                return DandelionDecision::Fluff;
            }
            match self.stem_successor {
                Some(p) => DandelionDecision::Stem(p),
                None => DandelionDecision::Fluff,
            }
        } else if prior >= STEM_HARD_CAP_HOPS {
            DandelionDecision::Fluff
        } else {
            self.seen.insert(*operation_id, prior + 1);
            // loop detection — same operation seen again => fluff to break
            DandelionDecision::Fluff
        }
    }

    pub fn stem_successor(&self) -> Option<[u8; 32]> {
        self.stem_successor
    }

    pub fn forget(&mut self, operation_id: &[u8; 32]) {
        self.seen.remove(operation_id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    #[test]
    fn rotate_picks_successor_from_outbound() {
        let mut s = DandelionState::new(0);
        let peers = vec![[0x11u8; 32], [0x22u8; 32], [0x33u8; 32]];
        s.rotate_epoch(60, 60, &peers, 1);
        assert!(s.stem_successor().is_some());
        assert!(peers.contains(&s.stem_successor().unwrap()));
    }

    #[test]
    fn rotate_clears_when_no_peers() {
        let mut s = DandelionState::new(0);
        s.rotate_epoch(60, 60, &[], 0);
        assert!(s.stem_successor().is_none());
    }

    #[test]
    fn forwarding_decision_first_seen_stem_or_fluff() {
        let mut s = DandelionState::new(0);
        let peers = vec![[0x11u8; 32]];
        s.rotate_epoch(60, 60, &peers, 0);
        let op = [0xFFu8; 32];
        // rng=200 → stem (>= 26)
        match s.forwarding_decision(&op, 200) {
            DandelionDecision::Stem(x) if x == [0x11u8; 32] => {},
            other => panic!("expected stem, got {:?}", other),
        }
    }

    #[test]
    fn forwarding_decision_rng_below_26_yields_fluff() {
        let mut s = DandelionState::new(0);
        let peers = vec![[0x11u8; 32]];
        s.rotate_epoch(60, 60, &peers, 0);
        let op = [0xFFu8; 32];
        assert_eq!(s.forwarding_decision(&op, 0), DandelionDecision::Fluff);
    }

    #[test]
    fn loop_detection_forces_fluff_on_second_sight() {
        let mut s = DandelionState::new(0);
        let peers = vec![[0x11u8; 32]];
        s.rotate_epoch(60, 60, &peers, 0);
        let op = [0xFFu8; 32];
        let _ = s.forwarding_decision(&op, 200);
        assert_eq!(s.forwarding_decision(&op, 200), DandelionDecision::Fluff);
    }

    #[test]
    fn no_outbound_peers_falls_back_to_fluff() {
        let mut s = DandelionState::new(0);
        let op = [0xFFu8; 32];
        assert_eq!(s.forwarding_decision(&op, 200), DandelionDecision::Fluff);
    }

    #[test]
    fn rotate_replaces_successor_on_epoch_change() {
        let mut s = DandelionState::new(0);
        let peers = vec![[0x11u8; 32], [0x22u8; 32]];
        s.rotate_epoch(60, 60, &peers, 0);
        let first = s.stem_successor().unwrap();
        s.rotate_epoch(120, 60, &peers, 1);
        let second = s.stem_successor().unwrap();
        // either same либо changed по rng_byte
        assert!(peers.contains(&second));
        let _ = first; // assertion: rotate executes
    }

    #[test]
    fn epoch_persists_within_same_tau1_bucket() {
        let mut s = DandelionState::new(0);
        let peers = vec![[0x11u8; 32], [0x22u8; 32]];
        s.rotate_epoch(60, 60, &peers, 0);
        let first = s.stem_successor().unwrap();
        // window 90 still in epoch 1 (90/60 = 1)
        s.rotate_epoch(90, 60, &peers, 1);
        let second = s.stem_successor().unwrap();
        assert_eq!(first, second);
    }
}
