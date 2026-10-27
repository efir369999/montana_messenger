// Automated determinism invariants for mt-consensus.
// M4 audit prep — proposal header / canonical proposer / control_set /
// canonical acceptance / finalization. Any non-determinism = consensus fork.
// The invariants catch regressions if a refactor breaks byte-exact header encode,
// proposal_hash R2, the proposer order by ticket, control_set sort, or
// quorum threshold.

use mt_codec::CanonicalEncode;
use mt_consensus::{
    compute_control_set, finalization_status, proposal_hash, proposer_at, proposer_order, ticket,
    validate_bundles_threshold, validate_proposer_is_canonical, AcceptanceError, ControlObjectRef,
    ControlSetError, FinalizationStatus, HeaderError, ProposalHeader, NO_PROPOSER,
    PROPOSAL_HEADER_SIZE,
};
use mt_crypto::{Signature, SIGNATURE_SIZE};
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
    // R2: the signature is NOT part of the hash. Guards against scheme-specific signature randomness.
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

// ---------- the proposer of a window: the lowest ticket by the aggregate (issue #18) ----------

#[test]
fn proposer_empty_electorate_is_no_proposer() {
    // Genesis cold-start: no electorate → no canonical proposer.
    assert_eq!(proposer_at(5, &[0x22; 32], &[], 1), NO_PROPOSER);
}

#[test]
fn proposer_depth_1_is_the_lowest_ticket_and_depth_2_the_next() {
    let agg = [0x22; 32];
    let electorate: Vec<NodeId> = vec![[0x01; 32], [0x02; 32], [0x03; 32]];
    let mut by_ticket = electorate.clone();
    by_ticket.sort_by_key(|id| ticket(&agg, id));
    assert_eq!(proposer_at(5, &agg, &electorate, 1), by_ticket[0]);
    assert_eq!(proposer_at(5, &agg, &electorate, 2), by_ticket[1]);
    assert_eq!(proposer_order(&agg, &electorate), by_ticket);
}

#[test]
fn proposer_exhausted_cascade_is_no_proposer() {
    let electorate: Vec<NodeId> = vec![[0x01; 32]];
    assert_eq!(proposer_at(5, &[0x22; 32], &electorate, 5), NO_PROPOSER);
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
    let agg = [0x22; 32];
    let electorate: Vec<NodeId> = vec![[0x01; 32], [0x02; 32]];
    let header = sample_header(2, proposer_at(2, &agg, &electorate, 1));
    assert!(validate_proposer_is_canonical(&header, &agg, &electorate).is_ok());
}

#[test]
fn validate_proposer_canonical_fail_on_wrong_proposer() {
    let agg = [0x22; 32];
    let electorate: Vec<NodeId> = vec![[0x01; 32], [0x02; 32]];
    // Header claims proposer = [0xAA; 32] but the canonical one is the lowest ticket
    let header = sample_header(2, [0xAA; 32]);
    let result = validate_proposer_is_canonical(&header, &agg, &electorate);
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

// ---------- finalization_status ----------

#[test]
fn finalization_status_cemented_at_quorum() {
    assert_eq!(finalization_status(67, 100), FinalizationStatus::Cemented);
}

#[test]
fn finalization_status_rejected_below_quorum() {
    assert_eq!(finalization_status(66, 100), FinalizationStatus::Rejected);
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
    let _: AcceptanceError = AcceptanceError::InsufficientBundles;
    let _: ControlSetError = ControlSetError::Mismatch;
}
