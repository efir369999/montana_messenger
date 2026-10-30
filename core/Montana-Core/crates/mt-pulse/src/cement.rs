// The cement of a window: the set of distinct machines, by the nullifier of their part, whose heavy
// attestations verified. The set states it in `docs/Montana Canon.md`, "The round of a chain, in
// integers": the state a beacon carries is the aggregate over the part-nullifiers of the heavy
// attestations published so far, each at most once, with the window as its context, beside their
// count; every verifier recomputes both from the attestations it holds.
//
// **A set and not a sum.** What the quorum counts is distinct machines of the electorate, and a
// part-nullifier is one per machine per window; the aggregate over the sorted set is binding and
// order-free, so two verifiers holding one set of attestations in two arrival orders carry one
// state. Nothing here weighs anybody: a part counts once or not at all.

use crate::ordered::Set;
use crate::PulseError;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Cement {
    // A set rather than a list, and for a reason that is not tidiness: the cement of a window takes
    // an attestation from every living machine, and a list would compare each new one against every
    // one before it — work that grows with the square of the population at exactly the moment the
    // population is what an attacker is spending.
    seen: Set<[u8; 32]>,
}

impl Cement {
    pub fn new() -> Self {
        Self::default()
    }

    // Whether this part moved the cement. A second appearance of one part-nullifier is answered
    // `false` rather than refused: the set calls the repetition lawful and says only that it adds
    // nothing. No count of machines stands over it: what keeps a structure from being sized by
    // whoever sends is the budget of a link, where the set already puts it.
    pub fn add(&mut self, part_nullifier: [u8; 32]) -> bool {
        self.seen.insert(part_nullifier)
    }

    // Whether this part-nullifier already stands in the cement. A caller that must verify a proof
    // before adding asks this first: a repetition adds nothing, and a repetition that adds nothing
    // must cost nothing either.
    pub fn holds(&self, part_nullifier: &[u8; 32]) -> bool {
        self.seen.contains(part_nullifier)
    }

    pub fn count(&self) -> u64 {
        self.seen.len() as u64
    }

    // The parts in ascending order: what the aggregate folds and what a certificate names.
    pub fn parts(&self) -> Vec<[u8; 32]> {
        self.seen.iter().copied().collect()
    }

    // The state a beacon carries: the aggregate over the parts with the window as its context. A
    // cement that holds nothing carries the aggregate of the empty set, which the set gives a domain
    // of its own, so an empty cement of one window is not an empty cement of another.
    pub fn aggregate(&self, window: u64) -> Result<[u8; 32], PulseError> {
        mt_derive::aggregate::aggregate(&self.parts(), window).map_err(|_| PulseError::RepeatedPart)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn part(byte: u8) -> [u8; 32] {
        [byte; 32]
    }

    #[test]
    fn a_part_enters_once_and_a_repeat_adds_nothing() {
        let mut cement = Cement::new();
        assert_eq!(cement.count(), 0);
        assert!(cement.add(part(1)));
        assert!(!cement.add(part(1)), "a repeat moved the cement");
        assert!(cement.holds(&part(1)));
        assert!(!cement.holds(&part(2)));
        assert!(cement.add(part(2)));
        assert_eq!(cement.count(), 2);
    }

    #[test]
    fn every_verifier_reaches_one_state_whatever_order_it_saw_the_parts_in() {
        let parts: Vec<[u8; 32]> = (1..=6u8).map(part).collect();
        let mut forward = Cement::new();
        for p in &parts {
            forward.add(*p);
        }
        let mut backward = Cement::new();
        for p in parts.iter().rev() {
            backward.add(*p);
        }
        let mut doubled = Cement::new();
        for p in parts.iter().chain(parts.iter()) {
            doubled.add(*p);
        }
        assert_eq!(forward.aggregate(1_000), backward.aggregate(1_000));
        assert_eq!(forward.aggregate(1_000), doubled.aggregate(1_000));
        assert_eq!(forward.count(), 6);
        assert_eq!(doubled.count(), 6);
        // A cement missing one part is another cement, and one window's cement is not another's.
        let mut short = Cement::new();
        for p in parts.iter().skip(1) {
            short.add(*p);
        }
        assert_ne!(forward.aggregate(1_000), short.aggregate(1_000));
        assert_ne!(forward.aggregate(1_000), forward.aggregate(1_001));
    }

    #[test]
    fn an_empty_cement_carries_the_aggregate_of_the_empty_set() {
        let cement = Cement::new();
        assert_eq!(
            cement.aggregate(1_000),
            Ok(mt_derive::aggregate::aggregate(&[], 1_000).expect("the empty set"))
        );
    }

    // The named wrong implementation this refuses is the one that bounded the cement by a row of the
    // Decree: it made the machine past that row not slow but unlawful.
    #[test]
    fn a_cement_grows_with_the_population_and_stands_under_no_ceiling() {
        let mut cement = Cement::new();
        let far_past_any_ceiling_this_tree_ever_held = 8_192u64;
        for i in 0..far_past_any_ceiling_this_tree_ever_held {
            let mut nullifier = [0u8; 32];
            nullifier[..8].copy_from_slice(&i.to_le_bytes());
            assert!(cement.add(nullifier), "at {i}");
        }
        assert_eq!(cement.count(), far_past_any_ceiling_this_tree_ever_held);
    }
}
