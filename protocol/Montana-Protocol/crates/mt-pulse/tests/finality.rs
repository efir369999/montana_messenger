use mt_pulse::close::{closes, quorum_reached, restart_admitted};

#[test]
fn overlapping_quorums_cannot_be_authorized_by_waiting() {
    // Honest sets A and B each hold 49; the Byzantine overlap holds 2 and
    // signs both. A disjoint-partition test cannot represent this attack.
    let honest_a = 49;
    let honest_b = 49;
    let equivocating = 2;
    let total = honest_a + honest_b + equivocating;
    for rounds in [0, 2_840, 3_124, u64::MAX] {
        let a = closes(honest_a + equivocating, total, rounds).unwrap();
        let b = closes(honest_b + equivocating, total, rounds).unwrap();
        assert!(!(a && b), "two conflicting certificates at round {rounds}");
    }
}

#[test]
fn every_round_preserves_the_parent_quorum() {
    for total in 1..=100u128 {
        for cemented in 0..=total {
            for rounds in [0, 2_840, 3_124, u64::MAX] {
                assert_eq!(
                    closes(cemented, total, rounds),
                    quorum_reached(cemented, total)
                );
            }
        }
    }
}

#[test]
fn rounds_do_not_authorize_a_new_denominator() {
    for rounds in [0, 3_407, 3_408, u64::MAX] {
        assert!(!restart_admitted(rounds).unwrap());
    }
}
