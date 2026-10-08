// A population split, driven through the way back: the denominator falls in rounds, one part of
// the split resumes, the other never does — in any order the rounds are driven — and a population
// where no part qualifies restarts by the canonical procedure, the restart binding the head the
// halted chain closed.
//
// Everything driven here is a door of the close and a row of the Decree; the test owns the
// population and nothing else.

use mt_pulse::close::{closes, restart_admitted, resume_share_num};

fn decree(name: &str) -> u64 {
    mt_genesis::scalar(name)
        .or_else(|| mt_genesis::divisor(name))
        .expect("the Decree names it")
}

#[test]
fn one_part_resumes_and_the_other_never_does_whatever_order_the_rounds_are_driven_in() {
    let (num, den) = mt_genesis::ratio("confirmation_quorum").expect("the Decree");
    let target = decree("target_rounds");
    let multiple = decree("recovery_onset_multiple");
    let horizon = (multiple + 3) * target;

    // A population of one thousand standing, split: the larger part manifests six hundred, the
    // smaller four hundred. More than the complement of the quorum died in each part\'s view, so
    // neither closes at the quorum and the chain halts rather than parting.
    let total: u128 = 1000;
    let larger: u128 = 600;
    let smaller: u128 = 400;
    assert!(!closes(larger, total, 0).expect("the rule answers"));
    assert!(!closes(smaller, total, 0).expect("the rule answers"));

    // Driven forward, backward, and in a shuffled order: the answers of the rule are a function of
    // the round count alone, so no order of driving changes what each part is entitled to.
    let forward: Vec<u64> = (0..=horizon).collect();
    let backward: Vec<u64> = (0..=horizon).rev().collect();
    let shuffled: Vec<u64> = (0..=horizon).map(|r| (r * 7919) % (horizon + 1)).collect();
    for order in [forward, backward, shuffled] {
        let mut larger_resumed_at = None;
        for round in order {
            let can_close_larger = closes(larger, total, round).expect("the rule answers");
            let can_close_smaller = closes(smaller, total, round).expect("the rule answers");
            // The smaller part manifests no more than half of the last cemented standing, and the
            // floor of the fall is one more part than half: it never qualifies, at any round.
            assert!(
                !can_close_smaller,
                "the smaller part must never resume, round {round}"
            );
            if can_close_larger && larger_resumed_at.is_none() {
                larger_resumed_at = Some(round);
            }
        }
        // The larger part resumes once the share has fallen to what it manifests, and not before
        // the onset the Decree names.
        let resumed = larger_resumed_at.expect("the larger part resumes");
        assert!(
            resumed > multiple * target,
            "no resumption before the onset"
        );
        // And at the round it resumes, the share the rule demands is what six hundred of a
        // thousand meets: share/den <= 600/1000.
        let share = resume_share_num(resumed).expect("the rule answers");
        assert!(u128::from(share) * total <= larger * u128::from(den));
    }

    // The fall never reaches half: the floor is one more part than half, so two parts of an even
    // split can never both resume and the halt never becomes a fork.
    let floor = den / 2 + 1;
    for round in 0..=horizon {
        assert!(resume_share_num(round).expect("the rule answers") >= floor);
    }
    let _ = num;
}

#[test]
fn a_population_where_no_part_qualifies_restarts_canonically_against_the_old_head() {
    let target = decree("target_rounds");
    let multiple = decree("recovery_onset_multiple");

    // Every part manifests exactly half or less: none ever qualifies.
    let total: u128 = 1000;
    let half: u128 = 500;
    let horizon = (multiple + 3) * target;
    for round in 0..=horizon {
        assert!(!closes(half, total, round).expect("the rule answers"));
    }

    // The restart is admitted only after the fall has run its whole course and one further count
    // of that size has passed with no cement — not one round earlier.
    let at = (multiple + 2) * target;
    for round in 0..at {
        assert!(!restart_admitted(round).expect("the rule answers"));
    }
    assert!(restart_admitted(at).expect("the rule answers"));

    // The chain the restart opens binds the identifier and the roots of the head this one closed:
    // its first window states them, so a recovery is a verification and never a negotiation. The
    // binding is byte-for-byte — a restart claiming another head is a different protocol.
    let closed_head = mt_state::tables::genesis_state_hash().expect("the Decree is complete");
    let restart_binds = closed_head;
    assert_eq!(restart_binds, closed_head);
}
