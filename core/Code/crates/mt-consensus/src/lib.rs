// spec, sections "Proposal header" + "Signed scope, identity and aggregation" (R1, R2)
// + "Canonical acceptance" + "Fallback cascade" + "Lookback Leadership".

use mt_codec::{domain, write_bytes, write_u128, write_u32, write_u64, write_u8, CanonicalEncode};
use mt_crypto::{hash, suite_id_from_u16, verify, Hash32, PublicKey, Signature, SuiteId};
use mt_state::{NodeId, NodeTable};

// Header layout per spec v31.0.0 (winner_class byte removed; lottery is single-class,
// the winner is always a node; signature ML-DSA-65):
//   prev_proposal_hash     32
//   window_index            8   u64 LE
//   protocol_version        4   u32 LE
//   control_root           32
//   node_root              32
//   candidate_root         32
//   account_root           32
//   state_root             32
//   timechain_value        32
//   included_bundles_root  32
//   included_reveals_root  32
//   winner_endpoint        32
//   winner_id              32
//   proposer_node_id       32
//   target                 16   u128 LE Q64.64 (per [I-9] P5)
//   fallback_depth          1   u8 ∈ [1, 255]
//   signature            3309   ML-DSA-65 (was Falcon-512 666)
//   ------------------------
//   total                3722
pub const PROPOSAL_HEADER_SIZE: usize = 3722;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProposalHeader {
    pub prev_proposal_hash: Hash32,
    pub window_index: u64,
    pub protocol_version: u32,
    pub control_root: Hash32,
    pub node_root: Hash32,
    pub candidate_root: Hash32,
    pub account_root: Hash32,
    pub state_root: Hash32,
    pub timechain_value: Hash32,
    pub included_bundles_root: Hash32,
    pub included_reveals_root: Hash32,
    pub winner_endpoint: Hash32,
    pub winner_id: Hash32,
    pub proposer_node_id: NodeId,
    pub target: u128,
    pub fallback_depth: u8,
    pub signature: Signature,
}

impl ProposalHeader {
    // spec R1: signed_scope = canonical_bytes without signature (last SIGNATURE_SIZE bytes)
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        write_bytes(buf, &self.prev_proposal_hash);
        write_u64(buf, self.window_index);
        write_u32(buf, self.protocol_version);
        write_bytes(buf, &self.control_root);
        write_bytes(buf, &self.node_root);
        write_bytes(buf, &self.candidate_root);
        write_bytes(buf, &self.account_root);
        write_bytes(buf, &self.state_root);
        write_bytes(buf, &self.timechain_value);
        write_bytes(buf, &self.included_bundles_root);
        write_bytes(buf, &self.included_reveals_root);
        write_bytes(buf, &self.winner_endpoint);
        write_bytes(buf, &self.winner_id);
        write_bytes(buf, &self.proposer_node_id);
        write_u128(buf, self.target);
        write_u8(buf, self.fallback_depth);
    }
}

impl CanonicalEncode for ProposalHeader {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

// spec R2: proposal_hash = SHA-256("mt-proposal" || signed_scope(header))
pub fn proposal_hash(header: &ProposalHeader) -> Hash32 {
    let mut scope = Vec::new();
    header.encode_signed_scope(&mut scope);
    hash(domain::PROPOSAL, &[&scope])
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HeaderError {
    UnknownProposer,
    UnsupportedSuite,
    InvalidSignature,
    WindowNotMonotone,
    ProtocolVersionDecreased,
    ProtocolVersionUnsupported,
    FallbackDepthZero,
}

// spec "Proposal header invariants" + R1 signature verification.
// Checks:
//   (a) proposer_node_id is registered in NodeTable, suite Mldsa65
//   (b) signature verifies with NodeTable[proposer_node_id].node_pubkey over signed_scope
//   (c) window_index == prev.window_index + 1 (the caller supplies prev.window_index)
//   (d) protocol_version >= prev.protocol_version
//   (e) protocol_version <= local_max_supported_version (the node must reject unknown)
//   (f) fallback_depth ≥ 1 (spec: 1 = first place, 0 is invalid)
pub fn validate_header(
    header: &ProposalHeader,
    node_table: &NodeTable,
    prev_window_index: u64,
    prev_protocol_version: u32,
    local_max_supported_version: u32,
) -> Result<(), HeaderError> {
    // fallback_depth check (structural)
    if header.fallback_depth == 0 {
        return Err(HeaderError::FallbackDepthZero);
    }
    // window monotone — checked_add guards against u64::MAX overflow
    // (M4-LOW-4 closure; horizon ~3.5×10^12 years at τ₁=60s, practically
    // unreachable but defense-in-depth: on overflow trigger we return
    // WindowNotMonotone instead of a silent wrap to 0).
    let expected = prev_window_index
        .checked_add(1)
        .ok_or(HeaderError::WindowNotMonotone)?;
    if header.window_index != expected {
        return Err(HeaderError::WindowNotMonotone);
    }
    // protocol version monotone
    if header.protocol_version < prev_protocol_version {
        return Err(HeaderError::ProtocolVersionDecreased);
    }
    if header.protocol_version > local_max_supported_version {
        return Err(HeaderError::ProtocolVersionUnsupported);
    }
    verify_header_signature(header, node_table)
}

// (a) + (b) alone: the proposer is in the Node Table under ML-DSA-65 and the signature
// verifies over the signed scope. A header of a window already applied is checked by this
// alone (issue #18, S4): its window is no longer the next one.
pub fn verify_header_signature(
    header: &ProposalHeader,
    node_table: &NodeTable,
) -> Result<(), HeaderError> {
    let proposer = node_table
        .get(&header.proposer_node_id)
        .ok_or(HeaderError::UnknownProposer)?;
    match suite_id_from_u16(proposer.suite_id) {
        Some(SuiteId::Mldsa65) => {},
        None => return Err(HeaderError::UnsupportedSuite),
    }
    let mut scope = Vec::new();
    header.encode_signed_scope(&mut scope);
    let pk = PublicKey::from_array(proposer.node_pubkey);
    if !verify(&pk, &scope, &header.signature) {
        return Err(HeaderError::InvalidSignature);
    }
    Ok(())
}

// ============ Phase B: the proposer of a window (issue #18) ============
//
// The author's decision 279 (constitution chain record 288) removes the lottery and carries
// over the rule of core/Montana-Core: the lowest ticket by the aggregate. core/docs, Consensus,
// "The runner's draw": every machine of the electorate draws its ticket from "the cemented
// aggregate of the window two before the one being drawn", the threshold of the draw is the width
// (Canon, "The threshold of the draw"), so no machine is excluded and the ticket only orders the
// runners, and "the machine whose ticket is lowest usually carries the decision first and alone"
// (Consensus, "The threshold of the draw, and the order of the runners").
//
// What core/Code carries over is the rule, not the construction (docs/SPEC_DEVIATIONS.md,
// DEV-055). core/Montana-Core draws the ticket from the machine's secret and proves its clearing
// in zero knowledge; core/Code has no such proof, so a ticket a follower can check is drawn from
// what every verifier holds: the aggregate and the node_id. Its order is therefore public one
// window ahead, as the lottery's was. The aggregate is mt-timechain
// `cemented_bundle_aggregate(W-2, cemented confirmers of W-2)`, the confirmers being those the
// proposal of W-1 included.
//
//   ticket(W, node)  = SHA-256("mt-ticket" || 0x00 || aggregate(W-2) || node_id)
//   order(W)         = the electorate of W, ascending by (ticket, node_id), compared unsigned
//                      and big-endian over the full width
//   proposer(W, d)   = order(W)[d-1]; d = fallback_depth, 1 = the lowest ticket
//
// The cascade of fallback_depth is the existing liveness rule of core/Code (DEV-023, DEV-043),
// walked over this order instead of over the lottery's candidates of W-2.
//
// Before window 2, with no electorate, or past the cascade there is no canonical proposer, and
// NO_PROPOSER (zero NodeId) is returned. No node stands in the Node Table under it, so
// validate_header refuses every header that names it. How a network with no electorate opens
// is not decided by this rule (the author's decision 280, issue #17).
pub const NO_PROPOSER: NodeId = [0u8; 32];

pub fn ticket(aggregate_w_minus_2: &Hash32, node_id: &NodeId) -> Hash32 {
    hash(domain::TICKET, &[aggregate_w_minus_2, node_id])
}

// The electorate of W in the order of its tickets. Each node counts once whatever order, and
// however many times, it was handed in.
pub fn proposer_order(aggregate_w_minus_2: &Hash32, electorate: &[NodeId]) -> Vec<NodeId> {
    let mut keyed: Vec<(Hash32, NodeId)> = electorate
        .iter()
        .map(|id| (ticket(aggregate_w_minus_2, id), *id))
        .collect();
    keyed.sort_unstable();
    keyed.dedup();
    keyed.into_iter().map(|(_, id)| id).collect()
}

// fallback_depth 1 = the lowest ticket, 2 = the next, and so on; a cascade past the electorate,
// or a window before 2, has no canonical proposer.
pub fn proposer_at(
    window: u64,
    aggregate_w_minus_2: &Hash32,
    electorate: &[NodeId],
    fallback_depth: u8,
) -> NodeId {
    if window < 2 || fallback_depth == 0 {
        return NO_PROPOSER;
    }
    proposer_order(aggregate_w_minus_2, electorate)
        .get(usize::from(fallback_depth) - 1)
        .copied()
        .unwrap_or(NO_PROPOSER)
}

// ============ Phase C: control_set formula ============

// spec, "control_set(proposal of window W)" lines 1192-1202:
//   control_set = { c : c.cemented_window > previous_proposal.window
//                        AND c.cemented_window <= W }
//   sorting: (cemented_window asc, op_hash lex asc)
//
// A ControlObject is represented by its op_hash + cemented_window (sufficient for the formula).
// The full ControlObject structure (NodeRegistration 0x11 etc.) is applied through
// mt-entry / mt-account.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ControlObjectRef {
    pub op_hash: Hash32,
    pub cemented_window: u64,
}

// Deterministic filter + sort. Returns a sorted Vec per spec.
// The proposer MUST include the entire control_set; the validator checks by equality.
pub fn compute_control_set(
    all_cemented: &[ControlObjectRef],
    previous_proposal_window: u64,
    current_window: u64,
) -> Vec<ControlObjectRef> {
    let mut filtered: Vec<ControlObjectRef> = all_cemented
        .iter()
        .filter(|c| {
            c.cemented_window > previous_proposal_window && c.cemented_window <= current_window
        })
        .copied()
        .collect();
    // Canonical sort: (cemented_window asc, op_hash lex asc)
    filtered.sort_by(|a, b| {
        a.cemented_window
            .cmp(&b.cemented_window)
            .then_with(|| a.op_hash.cmp(&b.op_hash))
    });
    filtered
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ControlSetError {
    Mismatch,
}

// Check: proposer's control_set == expected control_set (canonical).
// Used by the validator in the Canonical acceptance step.
pub fn validate_control_set(
    proposer_set: &[ControlObjectRef],
    all_cemented: &[ControlObjectRef],
    previous_proposal_window: u64,
    current_window: u64,
) -> Result<(), ControlSetError> {
    let expected = compute_control_set(all_cemented, previous_proposal_window, current_window);
    if proposer_set == expected.as_slice() {
        Ok(())
    } else {
        Err(ControlSetError::Mismatch)
    }
}

// ============ Phase D: Canonical acceptance validation ============

// Canonical acceptance of the proposal of window W, as core/Code checks it after issue #18:
//   (a) proposer = proposer_at(W, aggregate(W-2), electorate(W), fallback_depth)
//   (b) included_bundles ≥ 67% active_chain_length
//   (c) state_root is correct (independent recomputation — delegated to mt-account::apply_proposal)
//   (d) target, included_reveals_root, winner_endpoint and winner_id are zero
// The former (c) included_reveals and (d) winner_{W-1} = argmin are removed with the lottery.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AcceptanceError {
    ProposerNotCanonical,
    InsufficientBundles,
    RetiredFieldNotZero,
}

// The four fields of the lottery stay in the signed 3722-byte layout and carry zeros (issue #18,
// the author's decision 279: "the fields target/reveals_root/winner in the header -- zeros, with
// no change of the wire"). A header in which any of them is not zero is refused: nothing in
// core/Code gives them a value, so a value there is a header no honest proposer wrote.
pub fn validate_retired_fields(header: &ProposalHeader) -> Result<(), AcceptanceError> {
    if header.target != 0
        || header.included_reveals_root != [0u8; 32]
        || header.winner_endpoint != [0u8; 32]
        || header.winner_id != [0u8; 32]
    {
        return Err(AcceptanceError::RetiredFieldNotZero);
    }
    Ok(())
}

// (a) proposer canonical check, at the fallback_depth the signed header declares.
pub fn validate_proposer_is_canonical(
    header: &ProposalHeader,
    aggregate_w_minus_2: &Hash32,
    electorate: &[NodeId],
) -> Result<(), AcceptanceError> {
    let expected = proposer_at(
        header.window_index,
        aggregate_w_minus_2,
        electorate,
        header.fallback_depth,
    );
    if header.proposer_node_id != expected {
        return Err(AcceptanceError::ProposerNotCanonical);
    }
    Ok(())
}

// (b) included_bundles ≥ 67% active_chain_length.
// cemented_sum = Σ chain_length of the nodes whose BundledConfirmation made it into included_bundles.
pub fn validate_bundles_threshold(
    cemented_sum: u64,
    active_chain_length: u64,
) -> Result<(), AcceptanceError> {
    if mt_lottery::is_cemented(cemented_sum, active_chain_length) {
        Ok(())
    } else {
        Err(AcceptanceError::InsufficientBundles)
    }
}

// ============ Phase E: Finalization flow ============

// spec, "Window closure" + "Finalization" (lines 1045-1049):
//   If 67% of active_chain_length sign proposal_W → cemented.
//   If < 67% → proposal rejected, fallback cascade.
// (The winner and its reward are removed by issue #18: every living node of W-1 is credited
// and the proposer of a window is proposer_at above.)
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FinalizationStatus {
    Cemented,
    Rejected,
}

pub fn finalization_status(
    signatures_chain_length_sum: u64,
    active_chain_length: u64,
) -> FinalizationStatus {
    if mt_lottery::is_cemented(signatures_chain_length_sum, active_chain_length) {
        FinalizationStatus::Cemented
    } else {
        FinalizationStatus::Rejected
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair, sign, SECRET_KEY_SIZE, SIGNATURE_SIZE};
    use mt_state::{derive_node_id, NodeRecord};

    fn make_node(pubkey: [u8; mt_crypto::PUBLIC_KEY_SIZE]) -> (NodeId, NodeRecord) {
        let node_id = derive_node_id(&pubkey);
        let rec = NodeRecord {
            node_id,
            node_pubkey: pubkey,
            suite_id: SuiteId::Mldsa65 as u16,
            operator_account_id: [0x11; 32],
            start_window: 1,
            chain_length: 10,
            chain_length_snapshot: 10,
            chain_length_checkpoints: [10; 6],
            last_confirmation_window: 10,
        };
        (node_id, rec)
    }

    fn stub_header(proposer_node_id: NodeId) -> ProposalHeader {
        ProposalHeader {
            prev_proposal_hash: [0x01; 32],
            window_index: 100,
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
            target: 0x1234_5678_9ABC_DEF0_1122_3344_5566_7788u128,
            fallback_depth: 1,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        }
    }

    fn sign_header(header: &mut ProposalHeader, sk: &mt_crypto::SecretKey) {
        let mut scope = Vec::new();
        header.encode_signed_scope(&mut scope);
        header.signature = sign(sk, &scope).expect("sign ProposalHeader scope");
    }

    #[test]
    fn header_size_constant() {
        assert_eq!(PROPOSAL_HEADER_SIZE, 3722);
    }

    #[test]
    fn encode_matches_spec_layout() {
        let h = stub_header([0xAA; 32]);
        let mut buf = Vec::new();
        h.encode(&mut buf);
        assert_eq!(buf.len(), PROPOSAL_HEADER_SIZE);

        // prev_proposal_hash 0..32
        assert_eq!(&buf[0..32], &[0x01; 32]);
        // window_index 32..40 u64 LE = 100
        assert_eq!(&buf[32..40], &100u64.to_le_bytes());
        // protocol_version 40..44 u32 LE = 1
        assert_eq!(&buf[40..44], &1u32.to_le_bytes());
        // control_root 44..76
        assert_eq!(&buf[44..76], &[0x02; 32]);
        // node_root 76..108
        assert_eq!(&buf[76..108], &[0x03; 32]);
        // candidate_root 108..140
        assert_eq!(&buf[108..140], &[0x04; 32]);
        // account_root 140..172
        assert_eq!(&buf[140..172], &[0x05; 32]);
        // state_root 172..204
        assert_eq!(&buf[172..204], &[0x06; 32]);
        // timechain_value 204..236
        assert_eq!(&buf[204..236], &[0x07; 32]);
        // included_bundles_root 236..268
        assert_eq!(&buf[236..268], &[0x08; 32]);
        // included_reveals_root 268..300
        assert_eq!(&buf[268..300], &[0x09; 32]);
        // winner_endpoint 300..332
        assert_eq!(&buf[300..332], &[0x0A; 32]);
        // winner_id 332..364
        assert_eq!(&buf[332..364], &[0x0B; 32]);
        // proposer_node_id 364..396
        assert_eq!(&buf[364..396], &[0xAA; 32]);
        // target 396..412 u128 LE
        let expected_target = 0x1234_5678_9ABC_DEF0_1122_3344_5566_7788u128.to_le_bytes();
        assert_eq!(&buf[396..412], &expected_target);
        // fallback_depth 412 = 1
        assert_eq!(buf[412], 1);
        // signature 413..3722 (3309B ML-DSA-65)
        assert_eq!(&buf[413..3722], &[0u8; SIGNATURE_SIZE]);
    }

    #[test]
    fn signed_scope_excludes_signature() {
        let h = stub_header([0xAA; 32]);
        let mut scope = Vec::new();
        h.encode_signed_scope(&mut scope);
        let mut full = Vec::new();
        h.encode(&mut full);
        assert_eq!(full.len(), scope.len() + SIGNATURE_SIZE);
        assert_eq!(scope.len(), PROPOSAL_HEADER_SIZE - SIGNATURE_SIZE);
        assert_eq!(scope.len(), 413); // 3722 - 3309 (ML-DSA-65 signature)
    }

    #[test]
    fn signed_scope_stable_across_resign() {
        let mut h = stub_header([0xAA; 32]);
        let mut scope1 = Vec::new();
        h.encode_signed_scope(&mut scope1);
        h.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
        let mut scope2 = Vec::new();
        h.encode_signed_scope(&mut scope2);
        assert_eq!(scope1, scope2);
    }

    #[test]
    fn proposal_hash_domain_mt_proposal() {
        let h = stub_header([0xAA; 32]);
        let mut scope = Vec::new();
        h.encode_signed_scope(&mut scope);
        let expected = hash(b"mt-proposal", &[&scope]);
        assert_eq!(proposal_hash(&h), expected);
    }

    #[test]
    fn proposal_hash_stable_across_resign() {
        let mut h = stub_header([0x01; 32]);
        let h1 = proposal_hash(&h);
        h.signature = Signature::from_array([0xCD; SIGNATURE_SIZE]);
        let h2 = proposal_hash(&h);
        assert_eq!(h1, h2);
    }

    #[test]
    fn proposal_hash_sensitive_to_content() {
        let mut h = stub_header([0x01; 32]);
        let h1 = proposal_hash(&h);
        h.target = h.target.wrapping_add(1);
        let h2 = proposal_hash(&h);
        assert_ne!(h1, h2);
    }

    #[test]
    fn target_encoding_is_u128_le() {
        let mut h = stub_header([0xAA; 32]);
        h.target = 1u128;
        let mut buf = Vec::new();
        h.encode(&mut buf);
        // target at offset 396..412
        let mut expected = [0u8; 16];
        expected[0] = 1; // LE: byte[0] = low
        assert_eq!(&buf[396..412], &expected);
    }

    #[test]
    fn validate_accepts_valid_header() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        sign_header(&mut h, &sk);
        assert_eq!(validate_header(&h, &nt, 99, 1, 1), Ok(()));
    }

    #[test]
    fn validate_rejects_unknown_proposer() {
        let (pk, sk) = keypair();
        let (node_id, _rec) = make_node(*pk.as_bytes());
        let nt = NodeTable::new();
        let mut h = stub_header(node_id);
        sign_header(&mut h, &sk);
        assert_eq!(
            validate_header(&h, &nt, 99, 1, 1),
            Err(HeaderError::UnknownProposer)
        );
    }

    #[test]
    fn validate_rejects_unsupported_suite() {
        let (pk, sk) = keypair();
        let (node_id, mut rec) = make_node(*pk.as_bytes());
        rec.suite_id = 0xFFFF;
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        sign_header(&mut h, &sk);
        assert_eq!(
            validate_header(&h, &nt, 99, 1, 1),
            Err(HeaderError::UnsupportedSuite)
        );
    }

    #[test]
    fn validate_rejects_window_not_monotone() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        sign_header(&mut h, &sk);
        // prev window = 100, header says 100 (should be 101)
        assert_eq!(
            validate_header(&h, &nt, 100, 1, 1),
            Err(HeaderError::WindowNotMonotone)
        );
    }

    #[test]
    fn validate_rejects_protocol_decreased() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        h.protocol_version = 1;
        sign_header(&mut h, &sk);
        assert_eq!(
            validate_header(&h, &nt, 99, 2, 5),
            Err(HeaderError::ProtocolVersionDecreased)
        );
    }

    #[test]
    fn validate_rejects_protocol_unsupported() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        h.protocol_version = 10;
        sign_header(&mut h, &sk);
        assert_eq!(
            validate_header(&h, &nt, 99, 1, 5),
            Err(HeaderError::ProtocolVersionUnsupported)
        );
    }

    #[test]
    fn validate_rejects_fallback_depth_zero() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        h.fallback_depth = 0;
        sign_header(&mut h, &sk);
        assert_eq!(
            validate_header(&h, &nt, 99, 1, 1),
            Err(HeaderError::FallbackDepthZero)
        );
    }

    // spec v30.7.0+: winner_class byte removed from the proposal header.
    // Tests validate_rejects_invalid_winner_class and validate_accepts_valid_winner_classes
    // removed as obsolete. Lottery is single-class, the winner is always a node.

    #[test]
    fn validate_rejects_bad_signature() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        sign_header(&mut h, &sk);
        let mut sig_bytes = *h.signature.as_bytes();
        sig_bytes[0] ^= 0xFF;
        sig_bytes[200] ^= 0xAA;
        h.signature = Signature::from_array(sig_bytes);
        assert_eq!(
            validate_header(&h, &nt, 99, 1, 1),
            Err(HeaderError::InvalidSignature)
        );
    }

    #[test]
    fn validate_rejects_signature_from_different_key() {
        let (pk, _sk) = keypair();
        let (_other_pk, other_sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let mut h = stub_header(node_id);
        sign_header(&mut h, &other_sk);
        assert_eq!(
            validate_header(&h, &nt, 99, 1, 1),
            Err(HeaderError::InvalidSignature)
        );
    }

    #[test]
    fn encode_determinism() {
        let h = stub_header([0x42; 32]);
        let mut a = Vec::new();
        h.encode(&mut a);
        let mut b = Vec::new();
        h.encode(&mut b);
        assert_eq!(a, b);
    }

    #[test]
    fn secret_key_size_sanity() {
        assert_eq!(SECRET_KEY_SIZE, 4032);
    }

    #[test]
    fn target_u128_max_encodes_correctly() {
        // Check that the u128::MAX target is encoded as 16 bytes 0xFF
        let mut h = stub_header([0xAA; 32]);
        h.target = u128::MAX;
        let mut buf = Vec::new();
        h.encode(&mut buf);
        assert_eq!(&buf[396..412], &[0xFFu8; 16]);
    }

    #[test]
    fn target_zero_encodes_correctly() {
        let mut h = stub_header([0xAA; 32]);
        h.target = 0;
        let mut buf = Vec::new();
        h.encode(&mut buf);
        assert_eq!(&buf[396..412], &[0u8; 16]);
    }

    #[test]
    fn header_size_sum_matches_layout() {
        // prev_hash 32 + window 8 + version 4
        // + 8 × 32-byte roots (control/node/candidate/account/state/timechain/bundles/reveals)
        // + (winner_endpoint + winner_id + proposer_node_id) × 32
        // + target 16 + fallback_depth 1 + signature 3309 (ML-DSA-65) = 3722
        let calc = 32 + 8 + 4 + 32 * 8 + 32 * 3 + 16 + 1 + SIGNATURE_SIZE;
        assert_eq!(calc, PROPOSAL_HEADER_SIZE);
    }

    // ============ Phase B: the proposer of a window (issue #18) ============

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn ids(bytes: &[u8]) -> Vec<NodeId> {
        bytes.iter().map(|b| [*b; 32]).collect()
    }

    // The ticket against an independent oracle: Python hashlib,
    // sha256(b"mt-ticket" + b"\x00" + bytes([0x22]) * 32 + bytes([0x33]) * 32).
    // Rejects a ticket under another domain, without the separator byte, or over its inputs in
    // another order.
    #[test]
    fn the_ticket_is_the_frozen_value() {
        assert_eq!(
            hex(&ticket(&[0x22; 32], &[0x33; 32])),
            "031819bb8ae6922c06505d97e36a946ef73aa1bcc53669362bf4b2c8f8fa1d1e"
        );
    }

    // Rejects a proposer that is anything but the lowest ticket by the aggregate (the first
    // lottery candidate of W-2, the first node by id, the highest ticket).
    #[test]
    fn the_proposer_is_the_lowest_ticket() {
        let agg = [0x5A; 32];
        let electorate = ids(&[0x11, 0x22, 0x33, 0x44]);
        let lowest = *electorate
            .iter()
            .min_by_key(|id| ticket(&agg, id))
            .expect("four nodes");
        assert_eq!(proposer_at(7, &agg, &electorate, 1), lowest);
        let order = proposer_order(&agg, &electorate);
        assert_eq!(order[0], lowest);
        assert!(order
            .windows(2)
            .all(|pair| ticket(&agg, &pair[0]) < ticket(&agg, &pair[1])));
    }

    // Issue #18, S1: a window's proposer is the same on every order the electorate arrived in,
    // and a node handed in twice counts once. Rejects an order taken from arrival (the first
    // seen, the last seen) or one that a repeated node shifts.
    #[test]
    fn the_proposer_is_the_same_on_every_order_of_the_electorate() {
        let agg = [0xC3; 32];
        let base = ids(&[0x01, 0x02, 0x03, 0x04]);
        let expected: Vec<NodeId> = proposer_order(&agg, &base);
        let mut orders: Vec<Vec<NodeId>> = vec![Vec::new()];
        for id in &base {
            let mut next = Vec::new();
            for o in &orders {
                for pos in 0..=o.len() {
                    let mut p = o.clone();
                    p.insert(pos, *id);
                    next.push(p);
                }
            }
            orders = next;
        }
        assert_eq!(orders.len(), 24);
        for o in &orders {
            assert_eq!(proposer_order(&agg, o), expected, "order {o:?}");
            let mut twice = o.clone();
            twice.push(o[0]);
            assert_eq!(proposer_order(&agg, &twice), expected, "repeat {twice:?}");
            for depth in 1..=4u8 {
                assert_eq!(
                    proposer_at(9, &agg, o, depth),
                    expected[usize::from(depth) - 1]
                );
            }
        }
    }

    // The aggregate enters the ticket: two aggregates give two tickets for one node.
    #[test]
    fn the_ticket_moves_with_the_aggregate_and_the_node() {
        assert_ne!(
            ticket(&[0x01; 32], &[0x11; 32]),
            ticket(&[0x02; 32], &[0x11; 32])
        );
        assert_ne!(
            ticket(&[0x01; 32], &[0x11; 32]),
            ticket(&[0x01; 32], &[0x12; 32])
        );
    }

    #[test]
    fn no_proposer_before_window_two_with_no_electorate_or_past_the_cascade() {
        let agg = [0x5A; 32];
        let electorate = ids(&[0x11, 0x22]);
        assert_eq!(proposer_at(0, &agg, &electorate, 1), NO_PROPOSER);
        assert_eq!(proposer_at(1, &agg, &electorate, 1), NO_PROPOSER);
        assert_eq!(proposer_at(5, &agg, &[], 1), NO_PROPOSER);
        assert_eq!(proposer_at(5, &agg, &electorate, 3), NO_PROPOSER);
        assert_eq!(proposer_at(5, &agg, &electorate, 0), NO_PROPOSER);
        assert_ne!(proposer_at(5, &agg, &electorate, 2), NO_PROPOSER);
    }

    // ============ Phase C: control_set ============

    fn co(op_hash_byte: u8, cemented_window: u64) -> ControlObjectRef {
        ControlObjectRef {
            op_hash: [op_hash_byte; 32],
            cemented_window,
        }
    }

    #[test]
    fn control_set_empty_input() {
        let r = compute_control_set(&[], 5, 10);
        assert!(r.is_empty());
    }

    #[test]
    fn control_set_filters_cemented_window_range() {
        let all = vec![
            co(0x01, 3),  // ≤ prev (5), excluded
            co(0x02, 6),  // in range (5, 10]
            co(0x03, 10), // in range (inclusive upper)
            co(0x04, 11), // > current (10), excluded
        ];
        let r = compute_control_set(&all, 5, 10);
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].op_hash, [0x02; 32]);
        assert_eq!(r[1].op_hash, [0x03; 32]);
    }

    #[test]
    fn control_set_sorts_by_window_then_hash() {
        // Two objects with same window — sort by op_hash lex asc
        let all = vec![co(0xFF, 6), co(0x11, 6), co(0xAA, 7)];
        let r = compute_control_set(&all, 5, 10);
        assert_eq!(r[0].op_hash, [0x11; 32]); // window 6, hash 0x11
        assert_eq!(r[1].op_hash, [0xFF; 32]); // window 6, hash 0xFF
        assert_eq!(r[2].op_hash, [0xAA; 32]); // window 7
    }

    #[test]
    fn control_set_strict_lower_bound() {
        // cemented_window > previous_proposal.window (strictly greater)
        let all = vec![co(0x01, 5), co(0x02, 6)];
        let r = compute_control_set(&all, 5, 10);
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].op_hash, [0x02; 32]);
    }

    #[test]
    fn control_set_inclusive_upper_bound() {
        // cemented_window <= W (inclusive)
        let all = vec![co(0x01, 10)];
        let r = compute_control_set(&all, 5, 10);
        assert_eq!(r.len(), 1);
    }

    #[test]
    fn control_set_deterministic_on_permutation() {
        let obj1 = co(0x02, 6);
        let obj2 = co(0x03, 7);
        let obj3 = co(0x04, 6);
        let r1 = compute_control_set(&[obj1, obj2, obj3], 5, 10);
        let r2 = compute_control_set(&[obj3, obj2, obj1], 5, 10);
        assert_eq!(r1, r2);
    }

    #[test]
    fn validate_control_set_accepts_canonical() {
        let all = vec![co(0x02, 6), co(0x03, 7)];
        let expected = compute_control_set(&all, 5, 10);
        assert_eq!(validate_control_set(&expected, &all, 5, 10), Ok(()));
    }

    #[test]
    fn validate_control_set_rejects_missing_object() {
        let all = vec![co(0x02, 6), co(0x03, 7)];
        let proposer_set = vec![co(0x02, 6)]; // missing 0x03
        assert_eq!(
            validate_control_set(&proposer_set, &all, 5, 10),
            Err(ControlSetError::Mismatch)
        );
    }

    #[test]
    fn validate_control_set_rejects_extra_object() {
        let all = vec![co(0x02, 6)];
        let proposer_set = vec![co(0x02, 6), co(0x99, 6)]; // extra 0x99 not in cemented
        assert_eq!(
            validate_control_set(&proposer_set, &all, 5, 10),
            Err(ControlSetError::Mismatch)
        );
    }

    #[test]
    fn validate_control_set_rejects_wrong_order() {
        let all = vec![co(0xFF, 6), co(0x11, 6)];
        let wrong_order = vec![co(0xFF, 6), co(0x11, 6)]; // should be (0x11, 0xFF) sorted
        assert_eq!(
            validate_control_set(&wrong_order, &all, 5, 10),
            Err(ControlSetError::Mismatch)
        );
    }

    // ============ Phase D: Canonical acceptance ============

    #[test]
    fn validate_proposer_accepts_the_lowest_ticket_at_depth_1() {
        let agg = [0x5A; 32];
        let electorate = ids(&[0x11, 0x22, 0x33]);
        let mut h = stub_header(proposer_at(100, &agg, &electorate, 1));
        h.fallback_depth = 1;
        assert_eq!(
            validate_proposer_is_canonical(&h, &agg, &electorate),
            Ok(())
        );
        h.fallback_depth = 2;
        h.proposer_node_id = proposer_at(100, &agg, &electorate, 2);
        assert_eq!(
            validate_proposer_is_canonical(&h, &agg, &electorate),
            Ok(())
        );
    }

    // Rejects acceptance of a proposer other than the one the ticket names at the declared depth.
    #[test]
    fn validate_proposer_rejects_any_other_node() {
        let agg = [0x5A; 32];
        let electorate = ids(&[0x11, 0x22, 0x33]);
        let canonical = proposer_at(100, &agg, &electorate, 1);
        for other in electorate.iter().filter(|id| **id != canonical) {
            let mut h = stub_header(*other);
            h.fallback_depth = 1;
            assert_eq!(
                validate_proposer_is_canonical(&h, &agg, &electorate),
                Err(AcceptanceError::ProposerNotCanonical)
            );
        }
    }

    #[test]
    fn validate_proposer_no_proposer_on_empty() {
        // Genesis cold-start: empty electorate → expected proposer = NO_PROPOSER.
        // A header claiming NO_PROPOSER as its proposer validates; any real id rejects.
        let agg = [0u8; 32];
        let mut h = stub_header(NO_PROPOSER);
        h.fallback_depth = 1;
        assert_eq!(validate_proposer_is_canonical(&h, &agg, &[]), Ok(()));
        let mut h2 = stub_header([0x11; 32]);
        h2.fallback_depth = 1;
        assert_eq!(
            validate_proposer_is_canonical(&h2, &agg, &[]),
            Err(AcceptanceError::ProposerNotCanonical)
        );
    }

    // Issue #18, S3. Rejects a follower that reads, or lets through, a value in a field of the
    // lottery: each of the four, set to anything but zero, is refused; all four zero pass.
    #[test]
    fn a_header_with_a_non_zero_lottery_field_is_refused() {
        let mut zero = stub_header([0x55; 32]);
        zero.target = 0;
        zero.included_reveals_root = [0u8; 32];
        zero.winner_endpoint = [0u8; 32];
        zero.winner_id = [0u8; 32];
        assert_eq!(validate_retired_fields(&zero), Ok(()));
        let edits: [fn(&mut ProposalHeader); 5] = [
            |h| h.target = 1,
            |h| h.target = u128::MAX,
            |h| h.included_reveals_root[31] = 1,
            |h| h.winner_endpoint[0] = 1,
            |h| h.winner_id[16] = 0x80,
        ];
        for edit in edits {
            let mut h = zero.clone();
            edit(&mut h);
            assert_eq!(
                validate_retired_fields(&h),
                Err(AcceptanceError::RetiredFieldNotZero)
            );
        }
    }

    #[test]
    fn validate_bundles_threshold_at_quorum() {
        assert_eq!(validate_bundles_threshold(67, 100), Ok(()));
    }

    #[test]
    fn validate_bundles_threshold_below() {
        assert_eq!(
            validate_bundles_threshold(66, 100),
            Err(AcceptanceError::InsufficientBundles)
        );
    }

    #[test]
    fn validate_bundles_threshold_above() {
        assert_eq!(validate_bundles_threshold(100, 100), Ok(()));
    }

    // ============ Phase E: Finalization ============

    #[test]
    fn finalization_cemented_at_quorum() {
        assert_eq!(finalization_status(67, 100), FinalizationStatus::Cemented);
    }

    #[test]
    fn finalization_rejected_below_quorum() {
        assert_eq!(finalization_status(66, 100), FinalizationStatus::Rejected);
    }

    #[test]
    fn finalization_cemented_above_quorum() {
        assert_eq!(finalization_status(100, 100), FinalizationStatus::Cemented);
    }
}
