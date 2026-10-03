// Automated determinism invariants для mt-consensus.
// M4 audit prep — proposal header / canonical proposer / control_set /
// canonical acceptance / finalization. Любое non-determinism = consensus fork.
// Invariants ловят regression если refactor ломает byte-exact encode header,
// proposal_hash R2, canonical_proposer ordering, control_set sort, или
// quorum threshold.

use mt_codec::CanonicalEncode;
use mt_consensus::{
    canonical_proposer, compute_control_set, fallback_proposer, finalization_status,
    leader_penalty_excluded_node, proposal_hash, validate_bundles_threshold,
    validate_included_reveals, validate_proposer_is_canonical, validate_winner, AcceptanceError,
    ControlObjectRef, ControlSetError, FinalizationStatus, HeaderError, ProposalHeader,
    NO_PROPOSER, PROPOSAL_HEADER_SIZE,
};
use mt_crypto::{Signature, SIGNATURE_SIZE};
use mt_lottery::{Candidate, WINNER_CLASS_NODE};
use mt_state::NodeId;

// ---------- Helpers ----------

fn sample_header(window_index: u64, proposer_node_id: NodeId) -> ProposalHeader {
    ProposalHeader {
        prev_proposal_hash: [0x01; 32],
        window_index,
        protocol_version: 1,
        control_root: [0x02; 32],
        node_root: [0x03; 32],
        candidate_root: [0x04; 32],
        account_root: [0x05; 32],
        state_root: [0x06; 32],
        timechain_value: [0x07; 32],
        included_bundles_root: [0x08; 32],
        included_reveals_root: [0x09; 32],
        winner_endpoint: [0x0A; 32],
        winner_id: [0x0B; 32],
        proposer_node_id,
        target: 100u128,
        fallback_depth: 1,
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    }
}

// ---------- Encoded size matches constant ([I-9] determinism) ----------

#[test]
fn proposal_header_encoded_size_constant() {
    let h = sample_header(100, [0x42; 32]);
    let mut buf = Vec::new();
    h.encode(&mut buf);
    assert_eq!(
        buf.len(),
        PROPOSAL_HEADER_SIZE,
        "ProposalHeader encoded size drift: expected {}, got {}",
        PROPOSAL_HEADER_SIZE,
        buf.len()
    );
}

// ---------- proposal_hash R2 invariant ----------

#[test]
fn proposal_hash_deterministic() {
    let h = sample_header(100, [0x42; 32]);
    assert_eq!(proposal_hash(&h), proposal_hash(&h));
}

#[test]
fn proposal_hash_stable_under_signature_mutation() {
    // R2: signature НЕ входит в hash. Защита от scheme-specific signature randomness.
    let mut a = sample_header(100, [0x42; 32]);
    let mut b = a.clone();
    b.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
    assert_eq!(proposal_hash(&a), proposal_hash(&b));
    a.signature = Signature::from_array([0x99; SIGNATURE_SIZE]);
    assert_eq!(proposal_hash(&a), proposal_hash(&b));
}

#[test]
fn proposal_hash_changes_on_field_mutation() {
    let base = sample_header(100, [0x42; 32]);
    let m_window = sample_header(101, [0x42; 32]);
    let m_proposer = sample_header(100, [0xFF; 32]);
    let m_state = {
        let mut x = base.clone();
        x.state_root = [0xFF; 32];
        x
    };
    let m_target = {
        let mut x = base.clone();
        x.target = 99999u128;
        x
    };
    let m_fallback = {
        let mut x = base.clone();
        x.fallback_depth = 5;
        x
    };
    assert_ne!(proposal_hash(&base), proposal_hash(&m_window));
    assert_ne!(proposal_hash(&base), proposal_hash(&m_proposer));
    assert_ne!(proposal_hash(&base), proposal_hash(&m_state));
    assert_ne!(proposal_hash(&base), proposal_hash(&m_target));
    assert_ne!(proposal_hash(&base), proposal_hash(&m_fallback));
}

// ---------- canonical_proposer / fallback_proposer (Lookback Leadership) ----------

#[test]
fn canonical_proposer_empty_is_no_proposer() {
    let empty: Vec<Candidate> = vec![];
    // Genesis cold-start / degraded mode: empty W-2 → no canonical proposer.
    assert_eq!(canonical_proposer(&empty), NO_PROPOSER);
}

#[test]
fn canonical_proposer_picks_first_node_candidate() {
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let c2 = Candidate {
        ticket: 200,
        class: WINNER_CLASS_NODE,
        id: [0x02; 32],
    };
    let proposer = canonical_proposer(&[c1, c2]);
    assert_eq!(proposer, c1.id);
}

#[test]
fn fallback_proposer_depth_1_equals_canonical() {
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let c2 = Candidate {
        ticket: 200,
        class: WINNER_CLASS_NODE,
        id: [0x02; 32],
    };
    let canonical = canonical_proposer(&[c1, c2]);
    let fallback_1 = fallback_proposer(&[c1, c2], 1);
    assert_eq!(canonical, fallback_1);
}

#[test]
fn fallback_proposer_depth_2_picks_second() {
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let c2 = Candidate {
        ticket: 200,
        class: WINNER_CLASS_NODE,
        id: [0x02; 32],
    };
    let fallback_2 = fallback_proposer(&[c1, c2], 2);
    assert_eq!(fallback_2, c2.id);
}

#[test]
fn fallback_proposer_exhausted_cascade_is_no_proposer() {
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    // Только 1 candidate, request fallback_depth 5 — cascade exhausted.
    let proposer = fallback_proposer(&[c1], 5);
    assert_eq!(proposer, NO_PROPOSER);
}

// ---------- compute_control_set canonical sort ----------

#[test]
fn compute_control_set_filter_by_window() {
    let all = vec![
        ControlObjectRef {
            op_hash: [0x01; 32],
            cemented_window: 5,
        },
        ControlObjectRef {
            op_hash: [0x02; 32],
            cemented_window: 10,
        },
        ControlObjectRef {
            op_hash: [0x03; 32],
            cemented_window: 15,
        },
        ControlObjectRef {
            op_hash: [0x04; 32],
            cemented_window: 20,
        },
    ];
    let result = compute_control_set(&all, 5, 15);
    // window > 5 AND window <= 15 → [10, 15]
    assert_eq!(result.len(), 2);
    assert_eq!(result[0].cemented_window, 10);
    assert_eq!(result[1].cemented_window, 15);
}

#[test]
fn compute_control_set_sort_canonical() {
    // Same window — sort by op_hash lex asc
    let all = vec![
        ControlObjectRef {
            op_hash: [0xFF; 32],
            cemented_window: 10,
        },
        ControlObjectRef {
            op_hash: [0x01; 32],
            cemented_window: 10,
        },
        ControlObjectRef {
            op_hash: [0x80; 32],
            cemented_window: 10,
        },
    ];
    let result = compute_control_set(&all, 5, 15);
    assert_eq!(result.len(), 3);
    assert_eq!(result[0].op_hash, [0x01; 32]);
    assert_eq!(result[1].op_hash, [0x80; 32]);
    assert_eq!(result[2].op_hash, [0xFF; 32]);
}

#[test]
fn compute_control_set_input_order_independent() {
    let a = vec![
        ControlObjectRef {
            op_hash: [0x01; 32],
            cemented_window: 10,
        },
        ControlObjectRef {
            op_hash: [0x02; 32],
            cemented_window: 12,
        },
        ControlObjectRef {
            op_hash: [0x03; 32],
            cemented_window: 14,
        },
    ];
    let mut b = a.clone();
    b.reverse();
    assert_eq!(
        compute_control_set(&a, 5, 15),
        compute_control_set(&b, 5, 15)
    );
}

// ---------- validate_proposer_is_canonical ----------

#[test]
fn validate_proposer_canonical_pass_at_depth_1() {
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    let header = sample_header(2, c1.id);
    let result = validate_proposer_is_canonical(&header, &[c1]);
    assert!(result.is_ok());
}

#[test]
fn validate_proposer_canonical_fail_on_wrong_proposer() {
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x01; 32],
    };
    // Header заявляет proposer = [0xAA; 32] но canonical = c1.id
    let header = sample_header(2, [0xAA; 32]);
    let result = validate_proposer_is_canonical(&header, &[c1]);
    assert!(matches!(result, Err(AcceptanceError::ProposerNotCanonical)));
}

// ---------- validate_bundles_threshold ----------

#[test]
fn validate_bundles_threshold_ok_at_quorum() {
    // active = 100, quorum = 67; cemented_sum = 67 → cemented
    assert!(validate_bundles_threshold(67, 100).is_ok());
    assert!(validate_bundles_threshold(100, 100).is_ok());
}

#[test]
fn validate_bundles_threshold_below_quorum() {
    assert!(matches!(
        validate_bundles_threshold(66, 100),
        Err(AcceptanceError::InsufficientBundles)
    ));
}

// ---------- validate_included_reveals byte-exact equality ----------

#[test]
fn validate_included_reveals_equal_passes() {
    let reveals = vec![[0x01; 32], [0x02; 32], [0x03; 32]];
    assert!(validate_included_reveals(&reveals, &reveals).is_ok());
}

#[test]
fn validate_included_reveals_mismatch() {
    let proposer = vec![[0x01; 32], [0x02; 32]];
    let cemented = vec![[0x01; 32], [0x03; 32]];
    assert!(matches!(
        validate_included_reveals(&proposer, &cemented),
        Err(AcceptanceError::IncludedRevealsMismatch)
    ));
}

// ---------- validate_winner argmin canonical ----------

#[test]
fn validate_winner_correct_argmin() {
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
    let mut header = sample_header(100, [0x77; 32]);
    header.winner_id = c2.id; // argmin = c2 (ticket 100)
    let result = validate_winner(&header, &[c1, c2]);
    assert!(result.is_ok());
}

#[test]
fn validate_winner_wrong_winner_id() {
    let c1 = Candidate {
        ticket: 100,
        class: WINNER_CLASS_NODE,
        id: [0x02; 32],
    };
    let mut header = sample_header(100, [0x77; 32]);
    header.winner_id = [0xFF; 32]; // wrong
    assert!(matches!(
        validate_winner(&header, &[c1]),
        Err(AcceptanceError::WrongWinner)
    ));
}

#[test]
fn validate_winner_empty_candidates_rejected() {
    let header = sample_header(100, [0x77; 32]);
    assert!(matches!(
        validate_winner(&header, &[]),
        Err(AcceptanceError::WrongWinner)
    ));
}

// ---------- finalization_status ----------

#[test]
fn finalization_status_cemented_at_quorum() {
    assert_eq!(finalization_status(67, 100), FinalizationStatus::Cemented);
}

#[test]
fn finalization_status_rejected_below_quorum() {
    assert_eq!(finalization_status(66, 100), FinalizationStatus::Rejected);
}

// ---------- leader_penalty_excluded_node ----------

#[test]
fn leader_penalty_returns_proposer_node_id() {
    let proposer: NodeId = [0xAB; 32];
    let header = sample_header(100, proposer);
    assert_eq!(leader_penalty_excluded_node(&header), proposer);
}

// ---------- Static API invariants ----------

#[test]
fn proposal_header_size_constant_positive() {
    const _: () = assert!(PROPOSAL_HEADER_SIZE > 0);
    const _: () = assert!(PROPOSAL_HEADER_SIZE == 3722);
}

#[test]
fn header_error_acceptance_error_variants_compile() {
    // Compile-time verification of error enum surface (regression detection)
    let _: HeaderError = HeaderError::FallbackDepthZero;
    let _: HeaderError = HeaderError::WindowNotMonotone;
    let _: AcceptanceError = AcceptanceError::ProposerNotCanonical;
    let _: AcceptanceError = AcceptanceError::WrongWinner;
    let _: ControlSetError = ControlSetError::Mismatch;
}
