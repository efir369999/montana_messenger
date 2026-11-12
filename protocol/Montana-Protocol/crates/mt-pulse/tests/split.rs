// Arithmetic partition/rejoin scenarios. These are not a network certificate test: the complete
// verifier must additionally authenticate the parent electorate, the distinct parts and signing locks.
use mt_pulse::close::{closes, restart_admitted, resume_share_num};

#[test]
fn neither_subquorum_partition_closes_in_any_order_of_rounds() {
    let horizon = 4_000;
    let forward: Vec<u64> = (0..=horizon).collect();
    let backward: Vec<u64> = (0..=horizon).rev().collect();
    let shuffled: Vec<u64> = (0..=horizon).map(|r| (r * 7919) % (horizon + 1)).collect();
    for order in [forward, backward, shuffled] {
        for round in order {
            assert!(!closes(600, 1000, round).unwrap());
            assert!(!closes(400, 1000, round).unwrap());
            assert_eq!(resume_share_num(round), Ok(67));
        }
    }
}

#[test]
fn rejoining_restores_the_original_quorum_without_rebasing() {
    for round in [0, 2_840, 3_124, 3_408, u64::MAX] {
        assert!(!closes(500, 1000, round).unwrap());
        assert!(!closes(500 + 169, 1000, round).unwrap());
        assert!(closes(500 + 170, 1000, round).unwrap());
        assert!(closes(1000, 1000, round).unwrap());
        assert!(!restart_admitted(round).unwrap());
    }
}

#[test]
fn overlapping_byzantine_machines_cannot_close_two_competing_parts() {
    // Exhaust every split at this total below the strict intersection bound. A Byzantine part
    // signs both; honest parts sign only their own proposal. Disjoint-only tests miss this case.
    let total = 100u128;
    for byzantine in 0..34 {
        for honest_a in 0..=total - byzantine {
            let honest_b = total - byzantine - honest_a;
            for round in [0, 3_124, u64::MAX] {
                assert!(
                    !(closes(honest_a + byzantine, total, round).unwrap()
                        && closes(honest_b + byzantine, total, round).unwrap())
                );
            }
        }
    }
    // At the bound the assumption is false: two 67 certificates overlap in 34, all Byzantine.
    assert!(closes(33 + 34, total, 0).unwrap());
}
