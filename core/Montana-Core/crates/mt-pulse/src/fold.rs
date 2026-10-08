// The fold of a window and the cement. The set states both in `docs/Montana Canon.md` — the
// invariants of the round derivations and the section on the commitment that carries standing:
//
//   the cement is the **running sum** of the commitments of the heavy attestations published so
//   far, each part-nullifier contributing once, added in the ring and carrying no proof; every
//   verifier recomputes it from what it holds, and a beacon whose state is not that sum is refused
//
//   the tree of **fresh** commitments and node proofs is built once when the window closes, over
//   the same leaves ascending by part-nullifier; a node at level L, index I holds the children
//   (L-1, 2I) and (L-1, 2I+1), the odd node of a level rising unchanged to the next, and the node
//   is produced by the machine holding the leaf at I·2^L + (int_le(fold_work[0..8]) mod 2^L), and
//   by the next leaf under it in ascending order where that one is absent
//
// The two are different objects and the difference is the whole of why the tree exists: the sum
// accumulates randomness and binds nothing, and the tree commits afresh at every node.

use crate::PulseError;
use mt_suite::standing::Commitment;
use std::collections::BTreeSet;

// One leaf of the fold: a heavy attestation, named by the part-nullifier that makes it one per
// machine per window, carrying the commitment of the standing that machine answers with.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Leaf {
    pub part_nullifier: [u8; 32],
    pub commitment: Commitment,
}

// The cement of a window: the running sum, each part-nullifier contributing once. A repetition
// within one window adds nothing and is lawful — what a sanction rests on is one part-nullifier
// under two proposal identifiers of one height, which is a rule of Consensus and not of this sum.
#[derive(Clone, Debug, Default)]
pub struct Cement {
    // A set rather than a list, and for a reason that is not tidiness: the cement of a window
    // takes an attestation from every living machine, and a list would compare each new one
    // against every one before it — work that grows with the square of the population at exactly
    // the moment the population is what an attacker is spending.
    seen: BTreeSet<[u8; 32]>,
    state: Option<Commitment>,
}

impl Cement {
    pub fn new() -> Self {
        Self::default()
    }

    // Whether this attestation moved the cement. A second appearance of one part-nullifier is
    // answered `false` rather than refused: the set calls the repetition lawful and says only that
    // it adds nothing.
    //
    // Nothing else is refused here, and no count of machines stands over it. The set's rule of a
    // cement is one part-nullifier at most once and no other, so a bound on the count would be a
    // rule this tree invented — and it would be the rule that makes a machine of a growing network
    // unlawful. What keeps a structure from being sized by whoever sends is the budget of a link,
    // where the set already puts it: what exceeds a link's share is dropped without an answer and
    // without being remembered, and needs no ceiling of its own.
    pub fn add(&mut self, leaf: &Leaf) -> Result<bool, PulseError> {
        if self.seen.contains(&leaf.part_nullifier) {
            return Ok(false);
        }
        self.seen.insert(leaf.part_nullifier);
        self.state = Some(match &self.state {
            Some(held) => held.add(&leaf.commitment),
            None => leaf.commitment.clone(),
        });
        Ok(true)
    }

    // Whether this part-nullifier already stands in the cement. A caller that must verify a proof
    // before folding asks this first: a repetition adds nothing, and a repetition that adds nothing
    // must cost nothing either, or a machine standing at a round spends a core re-verifying what it
    // has already taken.
    pub fn holds(&self, part_nullifier: &[u8; 32]) -> bool {
        self.seen.contains(part_nullifier)
    }

    pub fn count(&self) -> usize {
        self.seen.len()
    }

    // The state a beacon carries. A window that cemented nothing carries no state, and a beacon of
    // such a window is a beacon before the first attestation of its chain.
    pub fn state(&self) -> Option<&Commitment> {
        self.state.as_ref()
    }
}

// The leaves of a window, ascending by part-nullifier: the order the tree is built over and the
// order every verifier reaches independently.
//
// A repeated part-nullifier is **refused** here rather than deduplicated. Which of two attestations
// under one nullifier enters the cement is decided by arrival — the first one — and a rule that
// picked one of them by sorting would let two verifiers holding the same pair in two arrival orders
// carry two different commitments into one tree, and therefore two different roots for one window.
// The cement is where that choice is made; the tree asks for leaves that have already passed it.
pub fn ordered(mut leaves: Vec<Leaf>) -> Result<Vec<Leaf>, PulseError> {
    leaves.sort_by(|a, b| a.part_nullifier.cmp(&b.part_nullifier));
    if leaves
        .windows(2)
        .any(|pair| pair[0].part_nullifier == pair[1].part_nullifier)
    {
        return Err(PulseError::RepeatedPart);
    }
    Ok(leaves)
}

// The shape of the tree over `count` leaves: the count of nodes at every level, the odd node of a
// level rising unchanged to the next.
pub fn levels(count: usize) -> Vec<usize> {
    if count == 0 {
        return Vec::new();
    }
    let mut out = vec![count];
    let mut width = count;
    while width > 1 {
        width = width.div_ceil(2);
        out.push(width);
    }
    out
}

// Which leaf's machine produces the node at (level, index), and the next leaf under it in
// ascending order where that one is absent. The draw is a function of the window, the level and
// the index alone, so every machine computes the same assignment and no one is asked.
pub fn producer(window: u64, level: u8, index: u64, leaves: usize) -> Result<usize, PulseError> {
    if leaves == 0 {
        return Err(PulseError::NoLeaves);
    }
    let work = mt_derive::fold_work(window, level, index);
    let mut eight = [0u8; 8];
    eight.copy_from_slice(&work[..8]);
    let drawn = u64::from_le_bytes(eight);
    let span = 1u64
        .checked_shl(u32::from(level))
        .ok_or(PulseError::CountBeyondWidth)?;
    let at = index
        .checked_mul(span)
        .and_then(|v| v.checked_add(drawn % span))
        .ok_or(PulseError::CountBeyondWidth)?;
    // The next leaf under it in ascending order where the drawn one is absent: the leaves of a
    // level are a prefix, so what stands under an index past the end is the last of them.
    Ok(usize::try_from(at)
        .map_err(|_| PulseError::CountBeyondWidth)?
        .min(leaves - 1))
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_suite::standing::weight_commit;

    fn leaf(nullifier: u8, standing: u64) -> Leaf {
        Leaf {
            part_nullifier: [nullifier; 32],
            // A factor of one window, stated where it is drawn: the door consumes it, so a leaf of
            // this population cannot carry a factor another leaf already stood behind.
            commitment: weight_commit(
                standing,
                0,
                0,
                mt_suite::standing::Blind::of([nullifier; 32], 0),
            )
            .expect("bounded"),
        }
    }

    #[test]
    fn the_cement_is_the_running_sum_and_a_repeat_adds_nothing() {
        let mut cement = Cement::new();
        assert!(cement.state().is_none());
        assert_eq!(cement.add(&leaf(1, 100)), Ok(true));
        let after_one = cement.state().cloned().expect("a state stands");
        assert_eq!(
            cement.add(&leaf(1, 100)),
            Ok(false),
            "a repeat moved the cement"
        );
        assert_eq!(cement.state(), Some(&after_one));
        assert_eq!(cement.count(), 1);
        assert_eq!(cement.add(&leaf(2, 250)), Ok(true));
        assert_eq!(cement.count(), 2);
        assert_eq!(
            cement.state(),
            Some(&after_one.add(&leaf(2, 250).commitment))
        );
    }

    #[test]
    fn every_verifier_reaches_one_cement_whatever_order_it_saw_them_in() {
        let leaves: Vec<Leaf> = (1..=6u8).map(|i| leaf(i, u64::from(i) * 10)).collect();
        let mut forward = Cement::new();
        for l in &leaves {
            forward.add(l).expect("within the population");
        }
        let mut backward = Cement::new();
        for l in leaves.iter().rev() {
            backward.add(l).expect("within the population");
        }
        assert_eq!(forward.state(), backward.state());
    }

    #[test]
    fn the_leaves_ascend_and_hold_one_entry_per_part_nullifier() {
        let held = ordered(vec![leaf(3, 1), leaf(1, 2), leaf(2, 4)]).expect("no repeat");
        let names: Vec<u8> = held.iter().map(|l| l.part_nullifier[0]).collect();
        assert_eq!(names, vec![1, 2, 3]);
        // The named wrong implementation: a rule that deduplicates instead of refusing. Two
        // attestations under one nullifier carry two commitments, and which one a sort keeps is
        // the arrival order of whoever sorted — two verifiers, two roots, one window.
        let a = leaf(3, 1);
        let b = Leaf {
            part_nullifier: a.part_nullifier,
            commitment: leaf(3, 9).commitment,
        };
        assert_ne!(a.commitment, b.commitment);
        assert_eq!(ordered(vec![a, b]), Err(PulseError::RepeatedPart));
    }

    #[test]
    fn the_tree_over_n_leaves_holds_n_minus_one_nodes_and_the_odd_one_rises() {
        assert_eq!(levels(0), Vec::<usize>::new());
        assert_eq!(levels(1), vec![1]);
        assert_eq!(levels(2), vec![2, 1]);
        assert_eq!(levels(5), vec![5, 3, 2, 1]);
        // The set: the tree over N leaves holds N - 1 nodes. A level folds its pairs and its odd
        // member rises unchanged, so what a level adds is the count of its pairs and not the width
        // of the level above it — a count taken the other way would claim more nodes than leaves.
        for count in 1..64usize {
            let shape = levels(count);
            let nodes: usize = shape.iter().map(|width| width / 2).sum();
            assert_eq!(nodes, count - 1, "count = {count}");
            assert_eq!(*shape.last().expect("a root"), 1);
        }
    }

    #[test]
    fn the_producer_of_a_node_is_a_function_of_the_window_the_level_and_the_index() {
        let leaves = 64;
        let a = producer(1000, 3, 5, leaves).expect("computes");
        assert_eq!(a, producer(1000, 3, 5, leaves).expect("computes"));
        // The draw moves with the window: over a run of windows one node is not always produced
        // by one machine, which is what spreads the work of a fold evenly.
        let across: Vec<usize> = (1000..1064)
            .map(|w| producer(w, 3, 5, leaves).expect("computes"))
            .collect();
        let mut distinct = across.clone();
        distinct.sort_unstable();
        distinct.dedup();
        assert!(
            distinct.len() > 4,
            "the producer of one node stands still across windows: {distinct:?}"
        );
        // The node of level L, index I draws from the leaves it stands over and from no others,
        // wherever its span begins inside them. A span that begins past the last leaf has no
        // leaf of its own, and what produces it is the last one present — the rule the set gives
        // for a drawn leaf that is absent, applied to a whole span that is.
        for level in 0..6u8 {
            let span = 1u64 << level;
            for index in 0..4u64 {
                let held = producer(1000, level, index, leaves).expect("computes") as u64;
                if index * span < leaves as u64 {
                    assert!(held >= index * span, "level {level} index {index}");
                    assert!(held < (index + 1) * span, "level {level} index {index}");
                } else {
                    assert_eq!(held, leaves as u64 - 1, "level {level} index {index}");
                }
            }
        }
    }

    #[test]
    fn a_node_over_leaves_that_are_absent_falls_to_the_last_one_present() {
        // Five leaves, a node of level three: its span reaches eight, and what stands under an
        // index past the end is the last leaf in ascending order.
        for index in 0..2u64 {
            let held = producer(1000, 3, index, 5).expect("computes");
            assert!(held < 5);
        }
        assert_eq!(producer(1000, 0, 0, 0), Err(PulseError::NoLeaves));
    }
}

#[cfg(test)]
mod population_tests {
    use super::*;
    use mt_suite::standing::weight_commit;

    // A cement holds one leaf per part-nullifier and stands under no count of machines. The named
    // wrong implementation this refuses is the one that bounded it by a row of the Decree: it made
    // the machine past that row not slow but unlawful, and a network whose growth is unlawful is
    // not the one the set describes. What keeps a structure from being sized by whoever sends is
    // the budget of a link, and that is where the set puts it.
    #[test]
    fn a_cement_grows_with_the_population_and_stands_under_no_ceiling() {
        let one = weight_commit(1, 0, 0, mt_suite::standing::Blind::of([0x11u8; 32], 0))
            .expect("bounded");
        let mut cement = Cement::new();
        let far_past_any_ceiling_this_tree_ever_held = 8_192usize;
        for i in 0..far_past_any_ceiling_this_tree_ever_held {
            let mut nullifier = [0u8; 32];
            nullifier[..8].copy_from_slice(&(i as u64).to_le_bytes());
            let leaf = Leaf {
                part_nullifier: nullifier,
                commitment: one.clone(),
            };
            assert_eq!(cement.add(&leaf), Ok(true), "at {i}");
        }
        assert_eq!(cement.count(), far_past_any_ceiling_this_tree_ever_held);
        // And the one rule the set does state still stands: a repeat adds nothing and is not an
        // error, whatever the count.
        let mut repeated = [0u8; 32];
        repeated[..8].copy_from_slice(&0u64.to_le_bytes());
        assert_eq!(
            cement.add(&Leaf {
                part_nullifier: repeated,
                commitment: one.clone(),
            }),
            Ok(false)
        );
        assert_eq!(cement.count(), far_past_any_ceiling_this_tree_ever_held);
    }
}
