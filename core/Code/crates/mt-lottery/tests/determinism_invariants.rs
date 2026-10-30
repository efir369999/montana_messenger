// Automated determinism invariants for mt-lottery.
// M4 audit prep — bundled confirmation / quorum. Any non-determinism = consensus fork.
// The invariants catch a regression if a refactor breaks byte-exact encode,
// bundle_hash R2, or the quorum threshold. The lottery (reveals, tickets, weights,
// winner) is removed by issue #18, and its invariants with it.

use mt_crypto::{Hash32, Signature, SIGNATURE_SIZE};
use mt_lottery::{
    bundle_hash, is_cemented, quorum, BundleError, BundledConfirmation, BUNDLE_FIXED_OVERHEAD,
};
use mt_state::NodeId;

// ---------- Helpers ----------

fn sample_bundle(node_id: NodeId, ops: Vec<Hash32>, reveals: Vec<Hash32>) -> BundledConfirmation {
    BundledConfirmation {
        node_id,
        endpoint: [0xAB; 32],
        window_index: 42,
        op_hashes: ops,
        reveal_hashes: reveals,
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    }
}

// ---------- bundle_hash determinism (R2 invariant) ----------

#[test]
fn bundle_hash_deterministic() {
    let bc = sample_bundle([0x01; 32], vec![[0x10; 32], [0x11; 32]], vec![[0x20; 32]]);
    assert_eq!(bundle_hash(&bc), bundle_hash(&bc));
}

#[test]
fn bundle_hash_stable_under_signature_mutation() {
    // R2 (spec): bundle_hash = SHA-256("mt-bundle" || signed_scope) — signature
    // NOT part of the hash. Guards against scheme-specific signature randomness.
    let mut a = sample_bundle([0x01; 32], vec![[0x10; 32]], vec![[0x20; 32]]);
    let mut b = a.clone();
    b.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
    assert_eq!(bundle_hash(&a), bundle_hash(&b));
    a.signature = Signature::from_array([0x42; SIGNATURE_SIZE]);
    assert_eq!(bundle_hash(&a), bundle_hash(&b));
}

#[test]
fn bundle_hash_changes_on_content_mutation() {
    let base = sample_bundle([0x01; 32], vec![[0x10; 32]], vec![[0x20; 32]]);
    let mutated_node_id = sample_bundle([0xFF; 32], vec![[0x10; 32]], vec![[0x20; 32]]);
    let mutated_endpoint = {
        let mut x = base.clone();
        x.endpoint = [0xFF; 32];
        x
    };
    let mutated_window = {
        let mut x = base.clone();
        x.window_index = 100;
        x
    };
    let mutated_ops = sample_bundle([0x01; 32], vec![[0xFF; 32]], vec![[0x20; 32]]);
    let mutated_reveals = sample_bundle([0x01; 32], vec![[0x10; 32]], vec![[0xFF; 32]]);
    assert_ne!(bundle_hash(&base), bundle_hash(&mutated_node_id));
    assert_ne!(bundle_hash(&base), bundle_hash(&mutated_endpoint));
    assert_ne!(bundle_hash(&base), bundle_hash(&mutated_window));
    assert_ne!(bundle_hash(&base), bundle_hash(&mutated_ops));
    assert_ne!(bundle_hash(&base), bundle_hash(&mutated_reveals));
}

// ---------- quorum / is_cemented ----------

#[test]
fn quorum_67_percent_ceiling() {
    // (67 × X + 99) / 100 = ceiling(0.67 × X)
    assert_eq!(quorum(0), 0);
    assert_eq!(quorum(100), 67);
    assert_eq!(quorum(1000), 670);
    assert_eq!(quorum(1), 1); // ceiling(0.67) = 1
    assert_eq!(quorum(2), 2); // ceiling(1.34) = 2
    assert_eq!(quorum(3), 3); // ceiling(2.01) = 3
}

#[test]
fn is_cemented_threshold() {
    let active = 100u64;
    let q = quorum(active); // = 67
    assert!(!is_cemented(q - 1, active)); // 66 < 67
    assert!(is_cemented(q, active)); // 67 ≥ 67
    assert!(is_cemented(q + 1, active));
    assert!(is_cemented(active, active));
}

#[test]
fn is_cemented_zero_active_zero_quorum() {
    // active = 0 → quorum = 0; 0 ≥ 0 = true. Edge case, defensive correctness.
    assert!(is_cemented(0, 0));
}

// ---------- Static API invariants ----------

#[test]
fn record_sizes_positive() {
    const _: () = assert!(BUNDLE_FIXED_OVERHEAD > 0);
}

// ---------- M4-1 closure: Vec u16 length cap ----------

#[test]
fn validate_bundle_rejects_too_many_ops() {
    // M4-1 closure: when op_hashes.len() > u16::MAX = 65535, an explicit error
    // BEFORE ML-DSA verify (guards against silent encode truncation).
    use mt_state::NodeTable;
    let node_table = NodeTable::new();
    let too_many: Vec<Hash32> = (0..(u16::MAX as usize + 1))
        .map(|i| {
            let mut h = [0u8; 32];
            h[..8].copy_from_slice(&(i as u64).to_le_bytes());
            h
        })
        .collect();
    let bc = sample_bundle([0x01; 32], too_many, vec![]);
    let result = mt_lottery::validate_bundle(&bc, &node_table, &[0xAB; 32]);
    // Note: validate_bundle first checks UnknownNode (node not registered),
    // so this test gets UnknownNode. The positive test for TooManyOps
    // with a registered node is below (validate_bundle_rejects_too_many_ops_with_registered_node).
    assert!(matches!(result, Err(BundleError::UnknownNode)));
}

// M4-LOW-6 closure: positive functional test for BundleError::TooManyOps
// with a registered node (the previous test was intercepted at UnknownNode and did not
// reach the cap-check). This test guarantees that the cap-check actually fires
// when op_hashes.len() > u16::MAX even though the node is registered and the suite is
// supported. A regression happens if someone reorders the validate_bundle checks.
#[test]
fn validate_bundle_rejects_too_many_ops_with_registered_node() {
    use mt_crypto::{keypair, PUBLIC_KEY_SIZE};
    use mt_state::{derive_node_id, NodeRecord, NodeTable};

    let (pk, _sk) = keypair();
    let node_id = derive_node_id(pk.as_bytes());
    let node = NodeRecord {
        node_id,
        node_pubkey: *pk.as_bytes(),
        suite_id: 1,
        operator_account_id: [0u8; 32],
        start_window: 0,
        chain_length: 1,
        chain_length_snapshot: 1,
        chain_length_checkpoints: [1; 6],
        last_confirmation_window: 0,
    };
    let mut nt = NodeTable::new();
    nt.insert(node);

    let too_many: Vec<Hash32> = (0..(u16::MAX as usize + 1))
        .map(|i| {
            let mut h = [0u8; 32];
            h[..8].copy_from_slice(&(i as u64).to_le_bytes());
            h
        })
        .collect();
    let mut bc = sample_bundle(node_id, too_many, vec![]);
    bc.endpoint = [0xAB; 32];
    // The signature is not valid (placeholder), but the cap-check must fire BEFORE verify.
    // Validate_bundle order: UnknownNode → UnsupportedSuite → WrongEndpoint
    //   → TooManyOps → TooManyReveals → OpsOutOfOrder → InvalidSignature
    // The node is registered, the suite is supported, the endpoint matches: the next
    // check, TooManyOps, must fire.
    let result = mt_lottery::validate_bundle(&bc, &nt, &[0xAB; 32]);
    assert_eq!(result, Err(BundleError::TooManyOps));

    let _ = PUBLIC_KEY_SIZE; // suppress unused import warning if not needed
}

#[test]
fn validate_bundle_rejects_too_many_reveals_with_registered_node() {
    // Symmetric test for TooManyReveals.
    use mt_crypto::keypair;
    use mt_state::{derive_node_id, NodeRecord, NodeTable};

    let (pk, _sk) = keypair();
    let node_id = derive_node_id(pk.as_bytes());
    let node = NodeRecord {
        node_id,
        node_pubkey: *pk.as_bytes(),
        suite_id: 1,
        operator_account_id: [0u8; 32],
        start_window: 0,
        chain_length: 1,
        chain_length_snapshot: 1,
        chain_length_checkpoints: [1; 6],
        last_confirmation_window: 0,
    };
    let mut nt = NodeTable::new();
    nt.insert(node);

    let too_many_reveals: Vec<Hash32> = (0..(u16::MAX as usize + 1))
        .map(|i| {
            let mut h = [0u8; 32];
            h[..8].copy_from_slice(&(i as u64).to_le_bytes());
            h
        })
        .collect();
    let mut bc = sample_bundle(node_id, vec![], too_many_reveals);
    bc.endpoint = [0xAB; 32];
    let result = mt_lottery::validate_bundle(&bc, &nt, &[0xAB; 32]);
    assert_eq!(result, Err(BundleError::TooManyReveals));
}

#[test]
fn bundle_error_variants_compile() {
    let _: BundleError = BundleError::TooManyOps;
    let _: BundleError = BundleError::TooManyReveals;
}
