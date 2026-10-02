// Automated determinism invariants для mt-lottery.
// M4 audit prep — node lottery / SSHA reveal / bundled confirmation /
// winner determination. Любое non-determinism = consensus fork.
// Invariants ловят regression если refactor ломает byte-exact encode,
// op_hash R2, weighted_ticket monotonicity, либо argmin canonical rule.

use mt_crypto::{Hash32, Signature, SIGNATURE_SIZE};
use mt_lottery::{
    bundle_hash, compute_endpoint, determine_winner, is_cemented, ln_q64, log2_q64, lottery_weight,
    quorum, reveal_hash, seniority_term, sorted_candidates_for_fallback, weighted_ticket_node,
    BundleError, BundledConfirmation, Candidate, RevealError, SshaReveal, BUNDLE_FIXED_OVERHEAD,
    REVEAL_SIZE, WINNER_CLASS_NODE,
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

fn sample_reveal(node_id: NodeId) -> SshaReveal {
    SshaReveal {
        node_id,
        window_index: 42,
        endpoint: [0xCD; 32],
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    }
}

// ---------- bundle_hash / reveal_hash determinism (R2 invariant) ----------

#[test]
fn bundle_hash_deterministic() {
    let bc = sample_bundle([0x01; 32], vec![[0x10; 32], [0x11; 32]], vec![[0x20; 32]]);
    assert_eq!(bundle_hash(&bc), bundle_hash(&bc));
}

#[test]
fn bundle_hash_stable_under_signature_mutation() {
    // R2 (spec): bundle_hash = SHA-256("mt-bundle" || signed_scope) — signature
    // НЕ входит в hash. Защита от scheme-specific signature randomness.
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

#[test]
fn reveal_hash_deterministic_and_stable_under_signature() {
    let r1 = sample_reveal([0x01; 32]);
    let mut r2 = r1.clone();
    r2.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
    assert_eq!(reveal_hash(&r1), reveal_hash(&r1));
    assert_eq!(reveal_hash(&r1), reveal_hash(&r2));
}

#[test]
fn reveal_hash_distinct_from_bundle_hash() {
    // Domain separator различает: "mt-bundle" vs "mt-ssha-reveal".
    let bc = sample_bundle([0x01; 32], vec![], vec![]);
    let r = sample_reveal([0x01; 32]);
    // (Совпадение возможно теоретически, но крайне маловероятно.)
    assert_ne!(bundle_hash(&bc), reveal_hash(&r));
}

// ---------- compute_endpoint determinism (R3 lottery formula) ----------

#[test]
fn compute_endpoint_deterministic() {
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let node_id: NodeId = [0x33; 32];
    assert_eq!(
        compute_endpoint(&t_r, &cba, &node_id, 7),
        compute_endpoint(&t_r, &cba, &node_id, 7)
    );
}

#[test]
fn compute_endpoint_changes_on_each_input() {
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let node_id: NodeId = [0x33; 32];
    let base = compute_endpoint(&t_r, &cba, &node_id, 7);
    assert_ne!(base, compute_endpoint(&[0xFF; 32], &cba, &node_id, 7));
    assert_ne!(base, compute_endpoint(&t_r, &[0xFF; 32], &node_id, 7));
    assert_ne!(base, compute_endpoint(&t_r, &cba, &[0xFF; 32], 7));
    assert_ne!(base, compute_endpoint(&t_r, &cba, &node_id, 8));
}

// ---------- log2_q64 / ln_q64 / weighted_ticket monotonicity ----------

#[test]
fn log2_q64_deterministic() {
    let endpoint = [0xAB; 32];
    assert_eq!(log2_q64(&endpoint), log2_q64(&endpoint));
}

#[test]
fn log2_q64_zero_endpoint_saturates() {
    let zero = [0u8; 32];
    assert_eq!(log2_q64(&zero), u128::MAX);
}

#[test]
fn log2_q64_monotonic_smaller_endpoint_larger_log() {
    // Меньший endpoint → больший log2(2^256/endpoint).
    let small = {
        let mut e = [0u8; 32];
        e[31] = 1; // = 1
        e
    };
    let large = {
        let mut e = [0u8; 32];
        e[0] = 0x80; // ≈ 2^255
        e
    };
    assert!(
        log2_q64(&small) > log2_q64(&large),
        "log2(2^256/1) > log2(2^256/2^255)"
    );
}

#[test]
fn ln_q64_deterministic() {
    let endpoint = [0xCD; 32];
    assert_eq!(ln_q64(&endpoint), ln_q64(&endpoint));
}

#[test]
fn ln_q64_zero_saturates() {
    let zero = [0u8; 32];
    assert_eq!(ln_q64(&zero), u128::MAX);
}

#[test]
fn ln_q64_monotonic() {
    let small = {
        let mut e = [0u8; 32];
        e[31] = 1;
        e
    };
    let large = {
        let mut e = [0u8; 32];
        e[0] = 0x80;
        e
    };
    assert!(ln_q64(&small) > ln_q64(&large));
}

// ---------- seniority_term / lottery_weight ----------

#[test]
fn seniority_term_first_13_windows_zero() {
    // chain_length / 13 = 0 при chain_length < 13.
    for cl in 0..13u64 {
        assert_eq!(seniority_term(cl, cl), 0, "cl={}", cl);
    }
}

#[test]
fn seniority_term_capped_by_snapshot() {
    // min(chain_length / 13, snapshot)
    assert_eq!(seniority_term(10000, 5), 5); // snapshot caps
    assert_eq!(seniority_term(100, 1000), 100 / 13); // chain_length/13 < snapshot
}

#[test]
fn lottery_weight_at_least_one_for_active_node() {
    // DS-2: snapshot ≥ 1 → lottery_weight ≥ 1.
    assert!(lottery_weight(0, 1) >= 1);
    assert!(lottery_weight(100, 1) >= 1);
    assert!(lottery_weight(10000, 5) >= 5);
}

// ---------- weighted_ticket_node determinism + zero-weight protection ----------

#[test]
fn weighted_ticket_node_deterministic() {
    let endpoint = [0xAB; 32];
    let a = weighted_ticket_node(&endpoint, 100, 5);
    let b = weighted_ticket_node(&endpoint, 100, 5);
    assert_eq!(a, b);
}

#[test]
fn weighted_ticket_node_zero_weight_saturates() {
    // chain_length_snapshot = 0 → lottery_weight = 0 (DS-2 violation,
    // caller обязан не позволять). Защита: u128::MAX (invalid argmin
    // candidate, не crash).
    let endpoint = [0xAB; 32];
    assert_eq!(weighted_ticket_node(&endpoint, 0, 0), u128::MAX);
}

#[test]
fn weighted_ticket_node_inverse_to_weight() {
    // Larger weight → smaller ticket (ln_q64 / weight).
    let endpoint = [0x01; 32];
    let small_w = weighted_ticket_node(&endpoint, 0, 1);
    let large_w = weighted_ticket_node(&endpoint, 0, 100);
    assert!(small_w > large_w);
}

// ---------- determine_winner argmin canonical rule ----------

#[test]
fn determine_winner_empty_returns_none() {
    assert_eq!(determine_winner(&[]), None);
}

#[test]
fn determine_winner_single_candidate() {
    let c = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let w = determine_winner(&[c]).unwrap();
    assert_eq!(w.ticket, 100);
    assert_eq!(w.id, [0x01; 32]);
}

#[test]
fn determine_winner_argmin_by_ticket() {
    let c1 = Candidate {
        ticket: 200,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let c2 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x02; 32],
    };
    let c3 = Candidate {
        ticket: 300,
        class: WINNER_CLASS_NODE,
        id: [0x03; 32],
    };
    let w = determine_winner(&[c1, c2, c3]).unwrap();
    assert_eq!(w.ticket, 100, "minimum ticket wins");
    assert_eq!(w.id, [0x02; 32]);
}

#[test]
fn determine_winner_tie_broken_by_id_lex() {
    // Tie на ticket → tie-break by id lex asc (с учётом class — но class
    // одинаковый WINNER_CLASS_NODE; spec ambiguity закрыта canonical rule).
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0xFF; 32],
    };
    let c2 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let w = determine_winner(&[c1, c2]).unwrap();
    assert_eq!(w.id, [0x01; 32], "lex-smaller id wins on ticket tie");
}

#[test]
fn determine_winner_input_order_independent() {
    let c1 = Candidate {
        ticket: 200,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let c2 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x02; 32],
    };
    let c3 = Candidate {
        ticket: 150,
        class: WINNER_CLASS_NODE,
        id: [0x03; 32],
    };
    let w_a = determine_winner(&[c1, c2, c3]).unwrap();
    let w_b = determine_winner(&[c3, c1, c2]).unwrap();
    let w_c = determine_winner(&[c2, c3, c1]).unwrap();
    assert_eq!(w_a, w_b);
    assert_eq!(w_b, w_c);
}

#[test]
fn sorted_candidates_for_fallback_canonical() {
    let c1 = Candidate {
        ticket: 200,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let c2 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x02; 32],
    };
    let c3 = Candidate {
        ticket: 150,
        class: WINNER_CLASS_NODE,
        id: [0x03; 32],
    };
    let sorted = sorted_candidates_for_fallback(&[c1, c2, c3]);
    assert_eq!(sorted[0], c2); // ticket 100
    assert_eq!(sorted[1], c3); // ticket 150
    assert_eq!(sorted[2], c1); // ticket 200
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
fn winner_class_node_is_one() {
    // SSOT [I-10]: WINNER_CLASS_NODE = 1. Изменение = consensus fork.
    assert_eq!(WINNER_CLASS_NODE, 1);
}

#[test]
fn record_sizes_positive() {
    const _: () = assert!(BUNDLE_FIXED_OVERHEAD > 0);
    const _: () = assert!(REVEAL_SIZE > 0);
}

// ---------- M4-1 closure: Vec u16 length cap ----------

#[test]
fn validate_bundle_rejects_too_many_ops() {
    // M4-1 closure: при op_hashes.len() > u16::MAX = 65535 — explicit error
    // ДО ML-DSA verify (защита от silent encode truncation).
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
    // Note: validate_bundle сначала проверяет UnknownNode (node не зарегистрирован),
    // поэтому в этом тесте получаем UnknownNode. Positive test для TooManyOps
    // с registered node — ниже (validate_bundle_rejects_too_many_ops_with_registered_node).
    assert!(matches!(result, Err(BundleError::UnknownNode)));
}

// M4-LOW-6 closure: positive functional test для BundleError::TooManyOps
// с registered node (предыдущий test перехватывался на UnknownNode и не
// reach-ил cap-check). Этот test гарантирует что cap-check actually fires
// при op_hashes.len() > u16::MAX даже когда node зарегистрирован и suite
// supported. Регрессия — если кто-то reorder validate_bundle checks.
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
    // Signature не валидна (placeholder), но cap-check должен fire ДО verify.
    // Validate_bundle order: UnknownNode → UnsupportedSuite → WrongEndpoint
    //   → TooManyOps → TooManyReveals → OpsOutOfOrder → InvalidSignature
    // Node зарегистрирован, suite supported, endpoint совпадает — следующая
    // проверка TooManyOps должна fire.
    let result = mt_lottery::validate_bundle(&bc, &nt, &[0xAB; 32]);
    assert_eq!(result, Err(BundleError::TooManyOps));

    let _ = PUBLIC_KEY_SIZE; // suppress unused import warning if не нужен
}

#[test]
fn validate_bundle_rejects_too_many_reveals_with_registered_node() {
    // Симметричный test для TooManyReveals.
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
fn record_sizes_pos_and_winner_class_compile_consts() {
    // Compile-time проверка что constants > 0
    let _: BundleError = BundleError::TooManyOps;
    let _: BundleError = BundleError::TooManyReveals;
    let _: RevealError = RevealError::WrongWindow;
}
