// spec, sections "BundledConfirmation", "Signed scope, identity and aggregation" (Rules R1, R2).
// The SSHA Reveal and the lottery (ticket, weight, winner) are removed by issue #18 (the
// author's decision 279): the proposer of a window is the lowest ticket by the aggregate
// (mt-consensus, Phase B), and a window credits every living node (mt-account).

use mt_codec::{domain, write_bytes, write_u16, write_u64, CanonicalEncode};
use mt_crypto::{
    hash, suite_id_from_u16, verify, Hash32, PublicKey, Signature, SuiteId, SIGNATURE_SIZE,
};
use mt_state::{NodeId, NodeTable};

// spec v33.1.5+: window_index is unified to u64 (8B LE) in all M4 structures
// (BundledConfirmation, ProposalHeader). The old u32 (4B) was removed as an
// architectural smell: a single type for one conceptually single field
// removes the cross-struct cast and the divergence in hash composition.
pub const BUNDLE_FIXED_OVERHEAD: usize = 32 + 32 + 8 + 2 + 2 + SIGNATURE_SIZE;

// Early-warning threshold for bundle hash counts (closure M-M4-1 partial,
// per external audit claude-opus-4-7-1m_2026-04-28_T2023).
//
// The u16 length prefix gives a hard cap of 65 535 hashes; at 1B users with
// ~1000 nodes one window may approach this limit. Threshold = 50%
// (32 768): an early signal for the operator / mt-telemetry so that the M6+ spec-patch
// u16→u32 is planned BEFORE the hard reject is actually reached.
//
// The lib stays silent (no eprintln, [I-3] / [C-6] cleanliness): the caller
// (montana-node or mt-telemetry F-5) applies should_warn_*_count() in its
// own logging path. validate_bundle keeps the hard reject exactly at
// u16::MAX; early-warning does not change consensus semantics.
pub const HASH_COUNT_EARLY_WARNING_THRESHOLD: usize = 32_768;

#[inline]
pub fn should_warn_op_hashes_count(count: usize) -> bool {
    count >= HASH_COUNT_EARLY_WARNING_THRESHOLD
}

#[inline]
pub fn should_warn_reveal_hashes_count(count: usize) -> bool {
    count >= HASH_COUNT_EARLY_WARNING_THRESHOLD
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BundledConfirmation {
    pub node_id: NodeId,
    pub endpoint: Hash32,
    pub window_index: u64,
    pub op_hashes: Vec<Hash32>,
    pub reveal_hashes: Vec<Hash32>,
    pub signature: Signature,
}

impl BundledConfirmation {
    // spec: Rule R1 — signed_scope = canonical_bytes without the signature field (last SIGNATURE_SIZE bytes)
    //
    // Wire format: lengths of op_hashes/reveal_hashes as u16 LE prefixes (per spec).
    // Caller responsibility: validate_bundle checks op_hashes.len() ≤ u16::MAX
    // BEFORE encode (M4-1 closure). debug_assert catches silent truncation if the caller
    // bypasses validate_bundle in debug builds; in release it relies on validate
    // gating (signature verify indirectly catches an encode mismatch).
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        debug_assert!(
            self.op_hashes.len() <= u16::MAX as usize,
            "BundledConfirmation.op_hashes.len() = {} > u16::MAX; \
             caller must run validate_bundle BEFORE encode (M4-1 invariant)",
            self.op_hashes.len()
        );
        debug_assert!(
            self.reveal_hashes.len() <= u16::MAX as usize,
            "BundledConfirmation.reveal_hashes.len() = {} > u16::MAX; \
             caller must run validate_bundle BEFORE encode (M4-1 invariant)",
            self.reveal_hashes.len()
        );
        write_bytes(buf, &self.node_id);
        write_bytes(buf, &self.endpoint);
        write_u64(buf, self.window_index);
        write_u16(buf, self.op_hashes.len() as u16);
        for h in &self.op_hashes {
            write_bytes(buf, h);
        }
        write_u16(buf, self.reveal_hashes.len() as u16);
        for h in &self.reveal_hashes {
            write_bytes(buf, h);
        }
    }
}

impl CanonicalEncode for BundledConfirmation {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum BcDecodeError {
    Truncated,
    HashCountOverflow,
}

impl BundledConfirmation {
    pub fn decode(input: &[u8]) -> Result<(Self, usize), BcDecodeError> {
        // node_id 32 + endpoint 32 + window 8 + u16 op_count + op_count*32 +
        // u16 reveal_count + reveal_count*32 + signature SIGNATURE_SIZE
        let mut o = 0;
        if input.len() < 32 + 32 + 8 + 2 {
            return Err(BcDecodeError::Truncated);
        }
        let mut node_id = [0u8; 32];
        node_id.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let mut endpoint = [0u8; 32];
        endpoint.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let mut w = [0u8; 8];
        w.copy_from_slice(&input[o..o + 8]);
        let window_index = u64::from_le_bytes(w);
        o += 8;
        let mut c = [0u8; 2];
        c.copy_from_slice(&input[o..o + 2]);
        let op_count = u16::from_le_bytes(c) as usize;
        o += 2;
        if input.len() < o + op_count * 32 + 2 {
            return Err(BcDecodeError::Truncated);
        }
        let mut op_hashes = Vec::with_capacity(op_count);
        for _ in 0..op_count {
            let mut h = [0u8; 32];
            h.copy_from_slice(&input[o..o + 32]);
            op_hashes.push(h);
            o += 32;
        }
        let mut rc = [0u8; 2];
        rc.copy_from_slice(&input[o..o + 2]);
        let reveal_count = u16::from_le_bytes(rc) as usize;
        o += 2;
        if input.len() < o + reveal_count * 32 + SIGNATURE_SIZE {
            return Err(BcDecodeError::Truncated);
        }
        let mut reveal_hashes = Vec::with_capacity(reveal_count);
        for _ in 0..reveal_count {
            let mut h = [0u8; 32];
            h.copy_from_slice(&input[o..o + 32]);
            reveal_hashes.push(h);
            o += 32;
        }
        let mut sig_bytes = [0u8; SIGNATURE_SIZE];
        sig_bytes.copy_from_slice(&input[o..o + SIGNATURE_SIZE]);
        o += SIGNATURE_SIZE;
        Ok((
            BundledConfirmation {
                node_id,
                endpoint,
                window_index,
                op_hashes,
                reveal_hashes,
                signature: Signature::from_array(sig_bytes),
            },
            o,
        ))
    }
}

// spec: Rule R2 — bundle_hash = SHA-256("mt-bundle" || signed_scope(bundle))
pub fn bundle_hash(bc: &BundledConfirmation) -> Hash32 {
    let mut scope = Vec::new();
    bc.encode_signed_scope(&mut scope);
    hash(domain::BUNDLE, &[&scope])
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum BundleError {
    UnknownNode,
    UnsupportedSuite,
    OpsOutOfOrder,
    RevealsOutOfOrder,
    WrongEndpoint,
    InvalidSignature,
    // M4-1 closure: encode_signed_scope uses write_u16 for the length of
    // op_hashes/reveal_hashes (spec wire format). At len > u16::MAX = 65535 the
    // cast `as u16` silently truncates → silent encode/decode mismatch. Protection
    // via signature verify is indirect (mismatch → wrong scope hash → fail);
    // the explicit invariant catches this before encode/sign and gives a clear error path.
    TooManyOps,
    TooManyReveals,
}

// spec: "op_hashes[] ascending lexicographic" + "reveal_hashes[] ascending lexicographic"
fn is_strictly_ascending(items: &[Hash32]) -> bool {
    items.windows(2).all(|w| w[0] < w[1])
}

// spec, section "BundledConfirmation" — validation before inclusion in the cemented set.
// Checks: (a) the node is registered and signs with ML-DSA-65,
//         (b) endpoint == T_r of the current window (the caller computes the canonical T_r),
//         (c) op_hashes[] / reveal_hashes[] are strictly increasing,
//         (d) the signature verifies against NodeTable[node_id].node_pubkey over signed_scope.
pub fn validate_bundle(
    bc: &BundledConfirmation,
    node_table: &NodeTable,
    expected_endpoint: &Hash32,
) -> Result<(), BundleError> {
    let node = node_table
        .get(&bc.node_id)
        .ok_or(BundleError::UnknownNode)?;
    match suite_id_from_u16(node.suite_id) {
        Some(SuiteId::Mldsa65) => {},
        None => return Err(BundleError::UnsupportedSuite),
    }
    if bc.endpoint != *expected_endpoint {
        return Err(BundleError::WrongEndpoint);
    }
    // M4-1 closure: explicit caps on Vec lengths before encode (write_u16 cast).
    // Protection from silent truncation; reject BEFORE signature verify so as not to spend
    // ML-DSA-65 verify cycles on a guaranteed-broken bundle.
    // M4-1 hard limit: the wire format encodes the length as u16 LE → ≤ 65535 hashes.
    // SCALE NOTE (M6+ scaling concern): at 1B active users with
    // ~1000 nodes one window may contain > 100K operations per node →
    // a bundle with op_hashes > 65535 will not fit in the current wire format.
    // Escalation requires a spec-patch to a u16→u32 length prefix.
    if bc.op_hashes.len() > u16::MAX as usize {
        return Err(BundleError::TooManyOps);
    }
    if bc.reveal_hashes.len() > u16::MAX as usize {
        return Err(BundleError::TooManyReveals);
    }
    if !is_strictly_ascending(&bc.op_hashes) {
        return Err(BundleError::OpsOutOfOrder);
    }
    if !is_strictly_ascending(&bc.reveal_hashes) {
        return Err(BundleError::RevealsOutOfOrder);
    }
    let mut scope = Vec::new();
    bc.encode_signed_scope(&mut scope);
    let pk = PublicKey::from_array(node.node_pubkey);
    if !verify(&pk, &scope, &bc.signature) {
        return Err(BundleError::InvalidSignature);
    }
    Ok(())
}

// ============ Phase F: Quorum calculation ============

// spec, section "Confirmation cutoff" (line 1433 + integer form):
//   quorum(W) = ⌈0.67 × active_chain_length(W)⌉        (real-valued commentary)
//   quorum(W) = (67 × active_chain_length + 99) / 100   (integer, authoritative [I-9])
// Unsigned u64. spec bound active ≤ 10^14: 67 × 10^14 + 99 < 2^63 — safe.
//
// M4-LOW-5 closure: saturating_mul/saturating_add protect against u64::MAX
// overflow (active_chain_length > u64::MAX/67 ≈ 2.7×10^17, irrelevant
// in practice but defense-in-depth: on overflow return a graceful
// u64::MAX/100 instead of a silent wrap or a panic in a debug build).
pub fn quorum(active_chain_length: u64) -> u64 {
    let scaled = 67u64.saturating_mul(active_chain_length);
    scaled.saturating_add(99) / 100
}

// spec: an object is cemented when cemented_sum ≥ quorum(W).
pub fn is_cemented(cemented_sum: u64, active_chain_length: u64) -> bool {
    cemented_sum >= quorum(active_chain_length)
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair, sign, SECRET_KEY_SIZE, SIGNATURE_SIZE};
    use mt_state::{derive_node_id, NodeRecord};

    #[test]
    fn early_warning_threshold_is_half_u16_max() {
        // 32 768 = exactly 50% of u16::MAX (65 535) + 1; gives ~33K headroom
        // to the operator before the hard reject in validate_bundle.
        assert_eq!(HASH_COUNT_EARLY_WARNING_THRESHOLD, 32_768);
        assert!(HASH_COUNT_EARLY_WARNING_THRESHOLD < u16::MAX as usize);
    }

    #[test]
    fn warn_helpers_trigger_at_threshold_boundary() {
        assert!(!should_warn_op_hashes_count(0));
        assert!(!should_warn_op_hashes_count(
            HASH_COUNT_EARLY_WARNING_THRESHOLD - 1
        ));
        assert!(should_warn_op_hashes_count(
            HASH_COUNT_EARLY_WARNING_THRESHOLD
        ));
        assert!(should_warn_op_hashes_count(u16::MAX as usize));

        assert!(!should_warn_reveal_hashes_count(0));
        assert!(!should_warn_reveal_hashes_count(
            HASH_COUNT_EARLY_WARNING_THRESHOLD - 1
        ));
        assert!(should_warn_reveal_hashes_count(
            HASH_COUNT_EARLY_WARNING_THRESHOLD
        ));
    }

    fn make_node(
        pubkey: [u8; mt_crypto::PUBLIC_KEY_SIZE],
        start_window: u64,
    ) -> (NodeId, NodeRecord) {
        let node_id = derive_node_id(&pubkey);
        let rec = NodeRecord {
            node_id,
            node_pubkey: pubkey,
            suite_id: SuiteId::Mldsa65 as u16,
            operator_account_id: [0x11; 32],
            start_window,
            chain_length: 1,
            chain_length_snapshot: 1,
            chain_length_checkpoints: [1; 6],
            last_confirmation_window: start_window,
        };
        (node_id, rec)
    }

    fn build_signed_bc(
        sk: &mt_crypto::SecretKey,
        node_id: NodeId,
        endpoint: Hash32,
        window_index: u64,
        op_hashes: Vec<Hash32>,
        reveal_hashes: Vec<Hash32>,
    ) -> BundledConfirmation {
        let mut bc = BundledConfirmation {
            node_id,
            endpoint,
            window_index,
            op_hashes,
            reveal_hashes,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        bc.encode_signed_scope(&mut scope);
        bc.signature = sign(sk, &scope).expect("sign BundledConfirmation scope");
        bc
    }

    #[test]
    fn encode_matches_spec_layout() {
        let bc = BundledConfirmation {
            node_id: [0xAA; 32],
            endpoint: [0xBB; 32],
            window_index: 0x0102030405060708,
            op_hashes: vec![[0x11; 32], [0x22; 32]],
            reveal_hashes: vec![[0x33; 32]],
            signature: Signature::from_array([0x44; SIGNATURE_SIZE]),
        };
        let mut buf = Vec::new();
        bc.encode(&mut buf);

        let expected_size = BUNDLE_FIXED_OVERHEAD + 32 * 2 + 32;
        assert_eq!(buf.len(), expected_size);

        // node_id: 0..32
        assert_eq!(&buf[0..32], &[0xAA; 32]);
        // endpoint: 32..64
        assert_eq!(&buf[32..64], &[0xBB; 32]);
        // window_index u64 LE: 64..72 (spec v33.1.5+ — was u32 4B before v33.1.5)
        assert_eq!(
            &buf[64..72],
            &[0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
        );
        // op_count LE: 72..74 = 2
        assert_eq!(&buf[72..74], &[0x02, 0x00]);
        // op_hashes: 74..106 (first), 106..138 (second)
        assert_eq!(&buf[74..106], &[0x11; 32]);
        assert_eq!(&buf[106..138], &[0x22; 32]);
        // reveal_count LE: 138..140 = 1
        assert_eq!(&buf[138..140], &[0x01, 0x00]);
        // reveal_hashes: 140..172
        assert_eq!(&buf[140..172], &[0x33; 32]);
        // signature: last SIGNATURE_SIZE bytes (3309 for ML-DSA-65)
        assert_eq!(&buf[172..172 + SIGNATURE_SIZE], &[0x44; SIGNATURE_SIZE]);
    }

    #[test]
    fn encode_empty_bundle_fixed_overhead() {
        let bc = BundledConfirmation {
            node_id: [0; 32],
            endpoint: [0; 32],
            window_index: 0,
            op_hashes: vec![],
            reveal_hashes: vec![],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut buf = Vec::new();
        bc.encode(&mut buf);
        assert_eq!(buf.len(), BUNDLE_FIXED_OVERHEAD);
    }

    #[test]
    fn signed_scope_excludes_signature() {
        let bc = BundledConfirmation {
            node_id: [0xAA; 32],
            endpoint: [0xBB; 32],
            window_index: 7,
            op_hashes: vec![[0x01; 32]],
            reveal_hashes: vec![],
            signature: Signature::from_array([0xCC; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        bc.encode_signed_scope(&mut scope);
        let mut full = Vec::new();
        bc.encode(&mut full);
        assert_eq!(full.len(), scope.len() + SIGNATURE_SIZE);
        assert_eq!(&full[..scope.len()], scope.as_slice());
        assert_eq!(&full[scope.len()..], &[0xCC; SIGNATURE_SIZE]);
    }

    #[test]
    fn signed_scope_same_for_different_signatures() {
        // R2 property: the identifier is stable regardless of the signature scheme.
        let mut bc1 = BundledConfirmation {
            node_id: [0xAA; 32],
            endpoint: [0xBB; 32],
            window_index: 7,
            op_hashes: vec![],
            reveal_hashes: vec![],
            signature: Signature::from_array([0x00; SIGNATURE_SIZE]),
        };
        let mut scope1 = Vec::new();
        bc1.encode_signed_scope(&mut scope1);
        bc1.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
        let mut scope2 = Vec::new();
        bc1.encode_signed_scope(&mut scope2);
        assert_eq!(scope1, scope2);
    }

    #[test]
    fn bundle_hash_domain_mt_bundle() {
        let bc = BundledConfirmation {
            node_id: [0x01; 32],
            endpoint: [0x02; 32],
            window_index: 1,
            op_hashes: vec![],
            reveal_hashes: vec![],
            signature: Signature::from_array([0x00; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        bc.encode_signed_scope(&mut scope);
        let expected = hash(b"mt-bundle", &[&scope]);
        assert_eq!(bundle_hash(&bc), expected);
    }

    #[test]
    fn bundle_hash_stable_across_resign() {
        // R2: the identifier does not depend on the signature
        let mut bc = BundledConfirmation {
            node_id: [0x01; 32],
            endpoint: [0x02; 32],
            window_index: 1,
            op_hashes: vec![[0xAB; 32]],
            reveal_hashes: vec![],
            signature: Signature::from_array([0x00; SIGNATURE_SIZE]),
        };
        let h1 = bundle_hash(&bc);
        bc.signature = Signature::from_array([0xCD; SIGNATURE_SIZE]);
        let h2 = bundle_hash(&bc);
        assert_eq!(h1, h2);
    }

    #[test]
    fn bundle_hash_changes_with_content() {
        let mut bc = BundledConfirmation {
            node_id: [0x01; 32],
            endpoint: [0x02; 32],
            window_index: 1,
            op_hashes: vec![],
            reveal_hashes: vec![],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let h1 = bundle_hash(&bc);
        bc.op_hashes.push([0xAB; 32]);
        let h2 = bundle_hash(&bc);
        assert_ne!(h1, h2);
    }

    #[test]
    fn validate_accepts_valid_bundle() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 10);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0x55; 32];
        let bc = build_signed_bc(
            &sk,
            node_id,
            endpoint,
            42,
            vec![[0x01; 32], [0x02; 32]],
            vec![[0x10; 32]],
        );
        assert_eq!(validate_bundle(&bc, &nt, &endpoint), Ok(()));
    }

    #[test]
    fn validate_accepts_empty_ops_and_reveals() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0x77; 32];
        let bc = build_signed_bc(&sk, node_id, endpoint, 5, vec![], vec![]);
        assert_eq!(validate_bundle(&bc, &nt, &endpoint), Ok(()));
    }

    #[test]
    fn validate_rejects_unknown_node() {
        let (pk, sk) = keypair();
        let (node_id, _rec) = make_node(*pk.as_bytes(), 1);
        let nt = NodeTable::new(); // empty
        let endpoint = [0; 32];
        let bc = build_signed_bc(&sk, node_id, endpoint, 1, vec![], vec![]);
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::UnknownNode)
        );
    }

    #[test]
    fn validate_rejects_unsupported_suite() {
        let (pk, sk) = keypair();
        let (node_id, mut rec) = make_node(*pk.as_bytes(), 1);
        rec.suite_id = 0xFFFF; // not Mldsa65
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0; 32];
        let bc = build_signed_bc(&sk, node_id, endpoint, 1, vec![], vec![]);
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::UnsupportedSuite)
        );
    }

    #[test]
    fn validate_rejects_wrong_endpoint() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0xAA; 32];
        let expected = [0xBB; 32];
        let bc = build_signed_bc(&sk, node_id, endpoint, 1, vec![], vec![]);
        assert_eq!(
            validate_bundle(&bc, &nt, &expected),
            Err(BundleError::WrongEndpoint)
        );
    }

    #[test]
    fn validate_rejects_unsorted_ops() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0; 32];
        let bc = build_signed_bc(
            &sk,
            node_id,
            endpoint,
            1,
            vec![[0x02; 32], [0x01; 32]], // reverse order
            vec![],
        );
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::OpsOutOfOrder)
        );
    }

    #[test]
    fn validate_rejects_duplicate_ops() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0; 32];
        // strict ascending — duplicates are rejected
        let bc = build_signed_bc(
            &sk,
            node_id,
            endpoint,
            1,
            vec![[0x01; 32], [0x01; 32]],
            vec![],
        );
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::OpsOutOfOrder)
        );
    }

    #[test]
    fn validate_rejects_unsorted_reveals() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0; 32];
        let bc = build_signed_bc(
            &sk,
            node_id,
            endpoint,
            1,
            vec![],
            vec![[0x99; 32], [0x11; 32]],
        );
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::RevealsOutOfOrder)
        );
    }

    #[test]
    fn validate_rejects_duplicate_reveals() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0; 32];
        let bc = build_signed_bc(
            &sk,
            node_id,
            endpoint,
            1,
            vec![],
            vec![[0x05; 32], [0x05; 32]],
        );
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::RevealsOutOfOrder)
        );
    }

    #[test]
    fn validate_rejects_bad_signature() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0; 32];
        let mut bc = build_signed_bc(&sk, node_id, endpoint, 1, vec![], vec![]);
        // corrupt the signature
        let mut sig_bytes = *bc.signature.as_bytes();
        sig_bytes[0] ^= 0xFF;
        sig_bytes[100] ^= 0xAA;
        bc.signature = Signature::from_array(sig_bytes);
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::InvalidSignature)
        );
    }

    #[test]
    fn validate_rejects_signature_from_different_key() {
        let (pk, _sk) = keypair();
        let (_other_pk, other_sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let endpoint = [0; 32];
        // signed by other_sk, but NodeTable has pk
        let bc = build_signed_bc(&other_sk, node_id, endpoint, 1, vec![], vec![]);
        assert_eq!(
            validate_bundle(&bc, &nt, &endpoint),
            Err(BundleError::InvalidSignature)
        );
    }

    #[test]
    fn encode_determinism() {
        let bc = BundledConfirmation {
            node_id: [0x01; 32],
            endpoint: [0x02; 32],
            window_index: 42,
            op_hashes: vec![[0x03; 32]],
            reveal_hashes: vec![[0x04; 32]],
            signature: Signature::from_array([0x05; SIGNATURE_SIZE]),
        };
        let mut a = Vec::new();
        bc.encode(&mut a);
        let mut b = Vec::new();
        bc.encode(&mut b);
        assert_eq!(a, b);
    }

    #[test]
    fn encoded_counts_are_le() {
        let bc = BundledConfirmation {
            node_id: [0; 32],
            endpoint: [0; 32],
            window_index: 0,
            op_hashes: vec![[0; 32]; 0x1234],
            reveal_hashes: vec![[0; 32]; 0x0056],
            signature: Signature::from_array([0; SIGNATURE_SIZE]),
        };
        let mut buf = Vec::new();
        bc.encode(&mut buf);
        // spec v33.1.5+: window_index 8B → op_count at offset 72..74
        assert_eq!(&buf[72..74], &[0x34, 0x12]);
        // reveal_count at offset 74 + 0x1234*32 = 74 + 149504 = 149578
        let reveal_count_offset = 74 + 0x1234 * 32;
        assert_eq!(
            &buf[reveal_count_offset..reveal_count_offset + 2],
            &[0x56, 0x00]
        );
    }

    #[test]
    fn encoded_window_index_is_le() {
        let bc = BundledConfirmation {
            node_id: [0; 32],
            endpoint: [0; 32],
            window_index: 0xDEADBEEFCAFEBABE,
            op_hashes: vec![],
            reveal_hashes: vec![],
            signature: Signature::from_array([0; SIGNATURE_SIZE]),
        };
        let mut buf = Vec::new();
        bc.encode(&mut buf);
        // spec v33.1.5+: window_index u64 LE 8B at offset 64..72
        assert_eq!(
            &buf[64..72],
            &[0xBE, 0xBA, 0xFE, 0xCA, 0xEF, 0xBE, 0xAD, 0xDE]
        );
    }

    #[test]
    fn bundle_hash_is_32_bytes() {
        let bc = BundledConfirmation {
            node_id: [0; 32],
            endpoint: [0; 32],
            window_index: 0,
            op_hashes: vec![],
            reveal_hashes: vec![],
            signature: Signature::from_array([0; SIGNATURE_SIZE]),
        };
        let h = bundle_hash(&bc);
        assert_eq!(h.len(), 32);
    }

    #[test]
    fn bundle_fixed_overhead_value() {
        // spec v33.1.5+: 32 (node_id) + 32 (endpoint) + 8 (window_index u64) + 2 (op_count) + 2 (reveal_count)
        // + 3309 (signature ML-DSA-65) = 3385
        assert_eq!(BUNDLE_FIXED_OVERHEAD, 3385);
    }

    #[test]
    fn secret_key_size_constant_available() {
        // Sanity: SECRET_KEY_SIZE is imported and matches (ML-DSA-65 expanded = 4032)
        assert_eq!(SECRET_KEY_SIZE, 4032);
    }

    // ============ Phase F: Quorum ============

    #[test]
    fn quorum_spec_test_vectors() {
        // Spec v29.8.0 binding test vectors (P3):
        assert_eq!(quorum(1), 1);
        assert_eq!(quorum(100), 67);
        assert_eq!(quorum(149), 100);
        assert_eq!(quorum(150), 101);
        assert_eq!(quorum(1000), 670);
    }

    #[test]
    fn quorum_zero_active_is_zero() {
        // Edge case — no active nodes
        assert_eq!(quorum(0), 0);
    }

    #[test]
    fn quorum_monotonic_non_decreasing() {
        let mut prev = 0u64;
        for x in [0u64, 1, 10, 100, 1000, 10_000, 100_000] {
            let q = quorum(x);
            assert!(q >= prev);
            prev = q;
        }
    }

    #[test]
    fn quorum_large_no_overflow() {
        // 10^14 — the max bound in the spec. 67 × 10^14 + 99 = 6.7e15 < 2^63.
        let big = 100_000_000_000_000u64;
        let q = quorum(big);
        // ~67% of big
        assert!(q > big / 2);
        assert!(q < big);
    }

    #[test]
    fn is_cemented_at_exact_quorum() {
        // cemented_sum == quorum → cemented (>=)
        assert!(is_cemented(67, 100));
    }

    #[test]
    fn is_cemented_below_quorum() {
        assert!(!is_cemented(66, 100));
    }

    #[test]
    fn is_cemented_above_quorum() {
        assert!(is_cemented(100, 100));
    }

    #[test]
    fn is_cemented_zero_active_zero_cemented() {
        // quorum(0) = 0, cemented_sum = 0 ≥ 0 → cemented
        // This is an edge case — in reality active=0 halts liveness, not consensus
        assert!(is_cemented(0, 0));
    }
    #[test]
    fn bc_encode_decode_roundtrip() {
        let bc = BundledConfirmation {
            node_id: [0x11; 32],
            endpoint: [0x22; 32],
            window_index: 12345,
            op_hashes: vec![[0xAA; 32], [0xBB; 32], [0xCC; 32]],
            reveal_hashes: vec![[0xDD; 32]],
            signature: Signature::from_array([0xEE; SIGNATURE_SIZE]),
        };
        let mut buf = Vec::new();
        bc.encode(&mut buf);
        let (decoded, consumed) = BundledConfirmation::decode(&buf).expect("decode ok");
        assert_eq!(consumed, buf.len());
        assert_eq!(decoded, bc);
    }

    #[test]
    fn bc_decode_truncated_returns_error() {
        let mut buf = vec![0u8; 50];
        assert!(matches!(
            BundledConfirmation::decode(&buf),
            Err(BcDecodeError::Truncated)
        ));
        buf.clear();
        assert!(matches!(
            BundledConfirmation::decode(&buf),
            Err(BcDecodeError::Truncated)
        ));
    }
}
