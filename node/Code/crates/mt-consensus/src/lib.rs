// spec, разделы "Proposal header" + "Signed scope, identity и aggregation" (R1, R2)
// + "Canonical acceptance" + "Fallback cascade" + "Lookback Leadership".

use mt_codec::{domain, write_bytes, write_u128, write_u32, write_u64, write_u8, CanonicalEncode};
use mt_crypto::{hash, suite_id_from_u16, verify, Hash32, PublicKey, Signature, SuiteId};
use mt_lottery::{Candidate, WINNER_CLASS_NODE};
use mt_state::{NodeId, NodeTable};

// Header layout per spec v31.0.0 (winner_class byte удалён; лотерея single-class,
// winner всегда узел; signature ML-DSA-65):
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
    // spec R1: signed_scope = canonical_bytes без signature (last SIGNATURE_SIZE bytes)
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

// spec "Инварианты Proposal header" + R1 signature verification.
// Проверки:
//   (a) proposer_node_id зарегистрирован в NodeTable, suite Mldsa65
//   (b) signature verify с NodeTable[proposer_node_id].node_pubkey над signed_scope
//   (c) window_index == prev.window_index + 1 (caller даёт prev.window_index)
//   (d) protocol_version >= prev.protocol_version
//   (e) protocol_version <= local_max_supported_version (узел обязан отклонить unknown)
//   (f) fallback_depth ≥ 1 (spec: 1 = первое место, 0 невалидно)
pub fn validate_header(
    header: &ProposalHeader,
    node_table: &NodeTable,
    prev_window_index: u64,
    prev_protocol_version: u32,
    local_max_supported_version: u32,
) -> Result<(), HeaderError> {
    // fallback_depth check (структурный)
    if header.fallback_depth == 0 {
        return Err(HeaderError::FallbackDepthZero);
    }
    // window monotone — checked_add защищает от u64::MAX overflow
    // (M4-LOW-4 closure; horizon ~3.5×10^12 лет at τ₁=60s, practically
    // unreachable но defense-in-depth: на overflow trigger возвращаем
    // WindowNotMonotone вместо silent wrap до 0).
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
    // proposer lookup + suite check + signature
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

// ============ Phase B: Lookback Leadership ============

// spec, "Определение winner-а (Lookback Leadership)":
//   proposer_W = winner_{W-2} (канонически из proposal_{W-1}).
//   proposer = ближайший node-кандидат по weighted_ticket — первый Candidate с
//   class=Node в sorted candidates of W-2.
//
// **Empty W-2 cemented set — нет канонического ведущего.**
//
// Genesis = пустое окно 0: нет baked bootstrap-узла. Когда
// sorted_candidates_w_minus_2 пуст либо не содержит ни одного
// `WINNER_CLASS_NODE` (genesis cold-start до первого зацементированного
// кандидата, либо degraded mode при одновременном offline всех confirmer-ов)
// — канонического ведущего нет, возвращается NO_PROPOSER (zero NodeId).
//
// Solo cold-start закрывается через существующий admission path: одиночный узел
// при нулевом Active-наборе self-admit-ит себя (selection_slots(0)=1) и
// зацементирует собственную цепочку (quorum(1)=1); его собственное предложение и
// есть цепочка. Распознавание NO_PROPOSER и подача собственного предложения —
// ответственность вызывающей стороны (узел знает свой node_id).
pub const NO_PROPOSER: NodeId = [0u8; 32];

pub fn canonical_proposer(sorted_candidates_w_minus_2: &[Candidate]) -> NodeId {
    // Извлечь первого node-кандидата из sorted list (минимальный weighted_ticket среди nodes)
    for c in sorted_candidates_w_minus_2 {
        if c.class == WINNER_CLASS_NODE {
            return c.id;
        }
    }
    // No node candidates в cemented set W-2 — канонического ведущего нет.
    NO_PROPOSER
}

// spec, "Fallback cascade":
//   fallback_1 = second_min(weighted_ticket) окна W-2, fallback_2 = third_min, etc.
// fallback_depth 1 = canonical proposer, 2 = first fallback, и т.д.
pub fn fallback_proposer(sorted_candidates_w_minus_2: &[Candidate], fallback_depth: u8) -> NodeId {
    let mut skip = (fallback_depth as usize).saturating_sub(1);
    for c in sorted_candidates_w_minus_2 {
        if c.class == WINNER_CLASS_NODE {
            if skip == 0 {
                return c.id;
            }
            skip -= 1;
        }
    }
    // Cascade exhausted — канонического ведущего нет.
    NO_PROPOSER
}

// ============ Phase C: control_set формула ============

// spec, "control_set(proposal окна W)" строки 1192-1202:
//   control_set = { c : c.cemented_window > previous_proposal.window
//                        AND c.cemented_window <= W }
//   сортировка: (cemented_window asc, op_hash lex asc)
//
// ControlObject представлен его op_hash + cemented_window (достаточно для формулы).
// Полная структура ControlObject (NodeRegistration 0x11 etc.) применяется через
// mt-entry / mt-account.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ControlObjectRef {
    pub op_hash: Hash32,
    pub cemented_window: u64,
}

// Детерминированный фильтр + сортировка. Возвращает sorted Vec per spec.
// Proposer ОБЯЗАН включить весь control_set целиком; валидатор сверяет через равенство.
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

// Проверка: proposer's control_set == expected control_set (каноничен).
// Используется валидатором в Canonical acceptance step.
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

// spec, "Canonical acceptance" (строка 1114):
//   (a) proposer = winner_{W-2}
//   (b) included_bundles ≥ 67% active_chain_length
//   (c) included_reveals = cemented set SSHA_Reveals окна W-1
//   (d) winner_{W-1} = argmin из (cemented reveals ∪ account_candidates)
//   (e) state_root корректен (independent recomputation — delegated в mt-account::apply_proposal)
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AcceptanceError {
    ProposerNotCanonical,
    InsufficientBundles,
    IncludedRevealsMismatch,
    WrongWinner,
}

// (a) proposer canonical check.
pub fn validate_proposer_is_canonical(
    header: &ProposalHeader,
    sorted_candidates_w_minus_2: &[Candidate],
) -> Result<(), AcceptanceError> {
    // При fallback_depth > 1 proposer = fallback_N, не canonical.
    // Валидация: proposer совпадает с fallback_proposer(depth).
    let expected = fallback_proposer(sorted_candidates_w_minus_2, header.fallback_depth);
    if header.proposer_node_id != expected {
        return Err(AcceptanceError::ProposerNotCanonical);
    }
    Ok(())
}

// (b) included_bundles ≥ 67% active_chain_length.
// cemented_sum = Σ chain_length узлов чьи BundledConfirmation попали в included_bundles.
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

// (c) included_reveals == cemented set SSHA_Reveals W-1 (каноничен).
// Compare via sorted Vec equality — caller sorts both before call.
pub fn validate_included_reveals(
    proposer_reveal_hashes: &[Hash32],
    cemented_reveal_hashes: &[Hash32],
) -> Result<(), AcceptanceError> {
    // Both are canonical sorted (by lex asc per spec «Canonical ordering» строки 2520-2521).
    if proposer_reveal_hashes == cemented_reveal_hashes {
        Ok(())
    } else {
        Err(AcceptanceError::IncludedRevealsMismatch)
    }
}

// (d) winner_{W-1} == argmin by canonical rule из (cemented reveals ∪ account candidates).
//
// **Caller contract (M4-MED-2):**
//
// Эта функция **строго отвергает** любой winner_id если cemented set окна W-1
// пуст (т.е. нет ни одного SSHA_Reveal от node-кандидата). Это правильно для
// **post-genesis** окон: в стационарном режиме сеть всегда имеет ≥1 candidate
// в W-1; пустой cemented set = либо все nodes одновременно offline (degenerate
// scenario, network в degraded mode), либо attacker подаёт fabricated proposal.
//
// **Для genesis cold-start** (первые окна где cemented W-1 candidates пустые
// потому что сеть ещё не накопила SSHA_Reveals) caller ОБЯЗАН skip
// `validate_winner`: при empty W-2 cemented set `canonical_proposer` возвращает
// `NO_PROPOSER`, и одиночный узел подаёт собственное предложение (self-admit
// через selection_slots(0)=1, self-cement через quorum(1)=1). Genesis bypass —
// caller responsibility (mt-account orchestrator знает window_index и может skip
// validate_winner для окон где cemented W-1 set по design пуст).
//
// Не вводим `validate_winner_genesis_aware` отдельно — это усложнит API
// без structural benefit (caller всё равно знает window_index и canonical
// fallback path). Документация contract в этом комментарии — authoritative.
pub fn validate_winner(
    header: &ProposalHeader,
    sorted_candidates_w_minus_1: &[Candidate],
) -> Result<(), AcceptanceError> {
    let expected = mt_lottery::determine_winner(sorted_candidates_w_minus_1);
    match expected {
        Some(w) => {
            if w.class == WINNER_CLASS_NODE && header.winner_id == w.id {
                Ok(())
            } else {
                Err(AcceptanceError::WrongWinner)
            }
        },
        None => {
            // Empty W-1 cemented set: post-genesis это либо degraded mode
            // (all nodes offline), либо attacker fabricated proposal — оба
            // случая reject. Genesis bootstrap — caller skip-ит validate_winner
            // (см. doc выше).
            Err(AcceptanceError::WrongWinner)
        },
    }
}

// ============ Phase E: Finalization flow ============

// spec, "Закрытие окна" + "Finalization" (строки 1045-1049):
//   Если 67% active_chain_length подписывают proposal_W → cemented.
//   Winner_{W-1} получает reward(W-1). Winner_{W-1} становится proposer_{W+1}.
//   Если < 67% → proposal отклонён, fallback cascade.
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

// spec строка 1333 "Leader penalty при отклонении":
//   endpoint proposer-а, чей proposal отклонён, исключается из lottery пула окна W.
// Helper: возвращает node_id для exclusion (caller использует в lottery candidate filter).
pub fn leader_penalty_excluded_node(header: &ProposalHeader) -> NodeId {
    header.proposer_node_id
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

    // spec v30.7.0+: winner_class byte удалён из proposal header.
    // Тесты validate_rejects_invalid_winner_class и validate_accepts_valid_winner_classes
    // удалены как obsolete. Лотерея single-class, winner всегда узел.

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
        // Проверка что u128::MAX target encoded как 16 bytes 0xFF
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

    // ============ Phase B: Lookback Leadership ============

    use mt_lottery::{Candidate, WINNER_CLASS_NODE};

    fn node_cand(ticket: u128, id_byte: u8) -> Candidate {
        Candidate {
            ticket,
            class: WINNER_CLASS_NODE,
            id: [id_byte; 32],
        }
    }

    #[test]
    fn proposer_empty_candidates_is_no_proposer() {
        // Genesis cold-start / degraded mode: empty W-2 set → no canonical proposer.
        assert_eq!(canonical_proposer(&[]), NO_PROPOSER);
    }

    #[test]
    fn proposer_is_first_node_candidate() {
        let cands = vec![
            node_cand(100, 0x11),
            node_cand(200, 0x22),
            node_cand(300, 0x33),
        ];
        let p = canonical_proposer(&cands);
        assert_eq!(p, [0x11; 32]);
    }

    #[test]
    fn fallback_depth_1_is_canonical() {
        let cands = vec![
            node_cand(100, 0x11),
            node_cand(200, 0x22),
            node_cand(300, 0x33),
        ];
        let canon = canonical_proposer(&cands);
        let fallback_1 = fallback_proposer(&cands, 1);
        assert_eq!(canon, fallback_1);
        assert_eq!(fallback_1, [0x11; 32]);
    }

    #[test]
    fn fallback_depth_2_is_second_node() {
        let cands = vec![
            node_cand(100, 0x11),
            node_cand(200, 0x22),
            node_cand(300, 0x33),
        ];
        let f2 = fallback_proposer(&cands, 2);
        assert_eq!(f2, [0x22; 32]);
    }

    // spec: лотерея single-class, кандидаты только узлы; fallback_skips_accounts удалён как obsolete.

    #[test]
    fn fallback_exhausted_is_no_proposer() {
        let cands = vec![node_cand(100, 0x11), node_cand(200, 0x22)];
        let f100 = fallback_proposer(&cands, 100);
        assert_eq!(f100, NO_PROPOSER);
    }

    #[test]
    fn fallback_empty_candidates_is_no_proposer() {
        assert_eq!(fallback_proposer(&[], 5), NO_PROPOSER);
        assert_eq!(fallback_proposer(&[], 1), NO_PROPOSER);
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
    fn validate_proposer_canonical_depth_1() {
        let cands = vec![node_cand(100, 0x11), node_cand(200, 0x22)];
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes());
        let _ = (node_id, rec, pk, sk);
        let mut h = stub_header([0x11; 32]); // matches first node candidate
        h.fallback_depth = 1;
        assert_eq!(validate_proposer_is_canonical(&h, &cands), Ok(()));
    }

    #[test]
    fn validate_proposer_rejects_mismatch() {
        let cands = vec![node_cand(100, 0x11), node_cand(200, 0x22)];
        let mut h = stub_header([0x99; 32]); // doesn't match
        h.fallback_depth = 1;
        assert_eq!(
            validate_proposer_is_canonical(&h, &cands),
            Err(AcceptanceError::ProposerNotCanonical)
        );
    }

    #[test]
    fn validate_proposer_no_proposer_on_empty() {
        // Genesis cold-start: empty W-2 set → expected proposer = NO_PROPOSER.
        // A header claiming NO_PROPOSER as its proposer validates; any real id rejects.
        let mut h = stub_header(NO_PROPOSER);
        h.fallback_depth = 1;
        assert_eq!(validate_proposer_is_canonical(&h, &[]), Ok(()));
        let mut h2 = stub_header([0x11; 32]);
        h2.fallback_depth = 1;
        assert_eq!(
            validate_proposer_is_canonical(&h2, &[]),
            Err(AcceptanceError::ProposerNotCanonical)
        );
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

    #[test]
    fn validate_included_reveals_matching() {
        let reveals = vec![[0x11; 32], [0x22; 32], [0x33; 32]];
        assert_eq!(validate_included_reveals(&reveals, &reveals), Ok(()));
    }

    #[test]
    fn validate_included_reveals_missing() {
        let proposer = vec![[0x11; 32], [0x22; 32]];
        let cemented = vec![[0x11; 32], [0x22; 32], [0x33; 32]];
        assert_eq!(
            validate_included_reveals(&proposer, &cemented),
            Err(AcceptanceError::IncludedRevealsMismatch)
        );
    }

    #[test]
    fn validate_included_reveals_extra() {
        let proposer = vec![[0x11; 32], [0x22; 32], [0x99; 32]];
        let cemented = vec![[0x11; 32], [0x22; 32]];
        assert_eq!(
            validate_included_reveals(&proposer, &cemented),
            Err(AcceptanceError::IncludedRevealsMismatch)
        );
    }

    #[test]
    fn validate_winner_matches_argmin() {
        let cands = vec![node_cand(100, 0x11), node_cand(200, 0x22)];
        let mut h = stub_header([0x55; 32]);
        h.winner_id = [0x11; 32];
        assert_eq!(validate_winner(&h, &cands), Ok(()));
    }

    #[test]
    fn validate_winner_mismatch_id() {
        let cands = vec![node_cand(100, 0x11)];
        let mut h = stub_header([0x55; 32]);
        h.winner_id = [0x99; 32]; // wrong id
        assert_eq!(
            validate_winner(&h, &cands),
            Err(AcceptanceError::WrongWinner)
        );
    }

    #[test]
    fn validate_winner_empty_candidates() {
        let h = stub_header([0x55; 32]);
        assert_eq!(validate_winner(&h, &[]), Err(AcceptanceError::WrongWinner));
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

    #[test]
    fn leader_penalty_returns_proposer() {
        let h = stub_header([0xDE; 32]);
        assert_eq!(leader_penalty_excluded_node(&h), [0xDE; 32]);
    }
}
