// Automated determinism invariants для mt-timechain.
// M2 batch 3 audit prep — TimeChain SSHA + Adaptive D + cemented_bundle_aggregate
// = критическая консенсус-поверхность с защитой [I-8] Network-Bound
// Unpredictability. Любой non-determinism = consensus fork.

use mt_genesis::genesis_params;
use mt_state::NodeId;
use mt_timechain::{cemented_bundle_aggregate, next_d, ssha_step, ssha_verify};

// ---------- SSHA determinism ----------

#[test]
#[should_panic(expected = "outside the protocol-accepted band")]
fn ssha_step_zero_iterations_panics() {
    // Honest proposer never produces d=0; an adversarial input must not
    // be silently accepted as identity (would let the proposer forge any
    // (prev, d=0, claim=prev) triple). ssha_step panics on d=0.
    let prev = [0u8; 32];
    let _ = ssha_step(&prev, 0);
}

#[test]
fn ssha_step_deterministic() {
    let prev = [0x33u8; 32];
    let a = ssha_step(&prev, 100);
    let b = ssha_step(&prev, 100);
    assert_eq!(a, b);
}

#[test]
fn ssha_step_changes_with_iterations() {
    let prev = [0x55u8; 32];
    let a = ssha_step(&prev, 1);
    let b = ssha_step(&prev, 2);
    let c = ssha_step(&prev, 3);
    assert_ne!(a, b);
    assert_ne!(b, c);
    assert_ne!(a, c);
}

#[test]
fn ssha_step_changes_with_prev_input() {
    assert_ne!(ssha_step(&[0x00u8; 32], 50), ssha_step(&[0xFFu8; 32], 50));
}

#[test]
fn ssha_verify_accepts_correct_chain() {
    let prev = [0x77u8; 32];
    let claim = ssha_step(&prev, 42);
    assert!(ssha_verify(&prev, 42, &claim));
}

#[test]
fn ssha_verify_rejects_wrong_claim() {
    let prev = [0x88u8; 32];
    let claim = ssha_step(&prev, 50);
    let bad_claim = [0x99u8; 32];
    // Positive + negative checks
    assert!(ssha_verify(&prev, 50, &claim));
    assert!(!ssha_verify(&prev, 50, &bad_claim));
}

#[test]
fn ssha_verify_rejects_wrong_iteration_count() {
    let prev = [0xAAu8; 32];
    let claim = ssha_step(&prev, 100);
    assert!(ssha_verify(&prev, 100, &claim));
    assert!(!ssha_verify(&prev, 99, &claim));
    assert!(!ssha_verify(&prev, 101, &claim));
}

#[test]
fn ssha_chain_composition() {
    // ssha_step(ssha_step(prev, A), B) == ssha_step(prev, A+B)
    let prev = [0xBBu8; 32];
    let a = 30u64;
    let b = 70u64;
    let intermediate = ssha_step(&prev, a);
    let chained = ssha_step(&intermediate, b);
    let direct = ssha_step(&prev, a + b);
    assert_eq!(chained, direct, "SSHA chain composition non-associative");
}

// ---------- next_d Adaptive D feedback ----------

#[test]
fn next_d_dead_zone_unchanged() {
    let params = genesis_params();
    let current_d = 252_000_000u64;
    // dead_zone middle (90%) → unchanged
    let result = next_d(current_d, 900, params);
    assert_eq!(
        result, current_d,
        "next_d in dead zone должен быть unchanged"
    );
}

#[test]
fn next_d_above_high_threshold_increases() {
    let params = genesis_params();
    let current_d = 252_000_000u64;
    let result = next_d(current_d, 1000, params); // 100% > high (95%)
    assert!(
        result > current_d,
        "next_d above high threshold должен расти"
    );
}

#[test]
fn next_d_below_low_threshold_decreases() {
    let params = genesis_params();
    let current_d = 252_000_000u64;
    let result = next_d(current_d, 0, params); // 0% < low (85%)
    assert!(
        result < current_d,
        "next_d below low threshold должен уменьшаться"
    );
}

#[test]
fn next_d_deterministic() {
    let params = genesis_params();
    let current_d = 252_000_000u64;
    for ratio in [0u32, 500, 850, 900, 950, 1000] {
        let a = next_d(current_d, ratio, params);
        let b = next_d(current_d, ratio, params);
        assert_eq!(a, b, "next_d non-deterministic at ratio {ratio}");
    }
}

// ---------- cemented_bundle_aggregate determinism + [I-8] ----------

#[test]
fn cba_window_zero_returns_genesis_zero() {
    let nodes: Vec<NodeId> = vec![[0x11; 32], [0x22; 32]];
    assert_eq!(cemented_bundle_aggregate(0, &nodes), [0u8; 32]);
    assert_eq!(cemented_bundle_aggregate(1, &nodes), [0u8; 32]);
}

#[test]
fn cba_empty_cemented_returns_empty_marker() {
    let result = cemented_bundle_aggregate(100, &[]);
    // Must not be all-zeros (genesis case) AND deterministic
    assert_ne!(result, [0u8; 32]);
    assert_eq!(cemented_bundle_aggregate(100, &[]), result);
}

#[test]
fn cba_changes_on_window() {
    let nodes: Vec<NodeId> = vec![[0x33; 32]];
    assert_ne!(
        cemented_bundle_aggregate(100, &nodes),
        cemented_bundle_aggregate(101, &nodes)
    );
}

#[test]
fn cba_changes_on_node_ids() {
    let nodes_a: Vec<NodeId> = vec![[0x11; 32]];
    let nodes_b: Vec<NodeId> = vec![[0x22; 32]];
    assert_ne!(
        cemented_bundle_aggregate(100, &nodes_a),
        cemented_bundle_aggregate(100, &nodes_b)
    );
}

#[test]
fn cba_deterministic() {
    let nodes: Vec<NodeId> = vec![[0x11; 32], [0x22; 32], [0x33; 32]];
    let a = cemented_bundle_aggregate(500, &nodes);
    let b = cemented_bundle_aggregate(500, &nodes);
    assert_eq!(a, b);
}

#[test]
fn cba_canonical_sort_independence_от_порядка_входа() {
    // Spec: sorted by node_id asc — input order не должен влиять.
    let nodes_forward: Vec<NodeId> = vec![[0x11; 32], [0x22; 32], [0x33; 32]];
    let nodes_reverse: Vec<NodeId> = vec![[0x33; 32], [0x22; 32], [0x11; 32]];
    assert_eq!(
        cemented_bundle_aggregate(500, &nodes_forward),
        cemented_bundle_aggregate(500, &nodes_reverse),
        "cemented_bundle_aggregate input order должен быть нерелевантен (canonical sort)"
    );
}

#[test]
fn cba_empty_vs_nonempty_distinct() {
    let with_nodes: Vec<NodeId> = vec![[0x11; 32]];
    assert_ne!(
        cemented_bundle_aggregate(100, &[]),
        cemented_bundle_aggregate(100, &with_nodes),
        "empty cemented set должен давать разный CBA от non-empty"
    );
}
