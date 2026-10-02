// spec, разделы "Вход и регистрация" + "NodeRegistration" + "Selection event"
// + "Adaptive SSHA" + "apply_proposal steps 1/3a/3b".
//
// ============ Validate-then-apply ordering invariant ============
//
// Все public `apply_*` функции в этом крейте принимают raw types и
// предполагают что caller выполнил соответствующий `validate_*` ДО вызова.
// Это design choice (per Code/CLAUDE.md "Validate-then-apply pattern"):
// caller orchestrates validation gate explicitly, нет typestate enforcement
// через wrapper types. Скрытие в одной функции скрыло бы invariant
// ordering от каллера и усложнило бы fast-sync (validate-only) flows.
//
// Обязательный orchestration порядок per spec "apply_proposal steps":
//
//   Step 1 (apply_noderegistrations_batch):
//     for each NR:
//       validate_noderegistration(nr, nodes, candidates, accounts)?  // ДО batch apply
//     apply_noderegistrations_batch(pool, ...)                       // applies validated
//
//   Step 3a (apply_candidate_expiry):
//     no validate phase — pure pruning by expires ≤ current_window
//
//   Step 3b (apply_selection_event):
//     no validate phase — селекция из existing CandidatePool по
//     canonical sort_key; pool entries уже validated при Шаге 1
//
// Caller (mt-account::apply_proposal либо external orchestrator) ОБЯЗАН:
//   1. Provide cemented_noderegs которые passed validate_noderegistration
//   2. Maintain CandidatePool в valid state (entries только через apply_*)
//   3. Не bypass apply_* через прямую модификацию state tables
//
// Нарушение validate-then-apply ordering = protocol invariant breach,
// caller errors visible через apply_proposal Step 4 state_root mismatch
// (другие узлы recompute через canonical pipeline и detect divergence).

use mt_codec::{domain, write_bytes, write_u16, write_u64, write_u8, CanonicalEncode};
use mt_crypto::{hash, suite_id_from_u16, verify, Hash32, PublicKey, Signature, SuiteId};
use mt_genesis::ProtocolParams;
use mt_state::{
    AccountId, AccountTable, CandidatePool, CandidateRecord, NodeId, NodeRecord, NodeTable,
};

// ============ Phase A: NodeRegistration ============

// spec, "NodeRegistration" под ML-DSA-65:
//   type                  1B   <- 0x11 NodeRegistration
//   suite_id              2B   <- u16 LE
//   node_pubkey        1952B
//   operator_account_id  32B
//   proof_endpoint       32B
//   W_start               8B   <- u64 LE
//   ssha_chain_length      8B   <- u64 LE
//   signature          3309B   <- ML-DSA-65 (was Falcon-512 666)
// Итого: 1 + 2 + 1952 + 32 + 32 + 8 + 8 + 3309 = 5344
pub const NODE_REGISTRATION_SIZE: usize = 5344;
pub const TYPE_NODE_REGISTRATION: u8 = 0x11;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NodeRegistration {
    pub suite_id: u16,
    pub node_pubkey: [u8; mt_crypto::PUBLIC_KEY_SIZE],
    pub operator_account_id: AccountId,
    pub proof_endpoint: Hash32,
    pub w_start: u64,
    pub ssha_chain_length: u64,
    pub signature: Signature,
}

impl NodeRegistration {
    // spec R1: signed_scope = canonical_bytes без signature (last SIGNATURE_SIZE bytes)
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        write_u8(buf, TYPE_NODE_REGISTRATION);
        write_u16(buf, self.suite_id);
        write_bytes(buf, &self.node_pubkey);
        write_bytes(buf, &self.operator_account_id);
        write_bytes(buf, &self.proof_endpoint);
        write_u64(buf, self.w_start);
        write_u64(buf, self.ssha_chain_length);
    }
}

impl CanonicalEncode for NodeRegistration {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

// spec R2: nodereg_hash = SHA-256("mt-nodereg" || signed_scope(nr))
pub fn nodereg_hash(nr: &NodeRegistration) -> Hash32 {
    let mut scope = Vec::new();
    nr.encode_signed_scope(&mut scope);
    hash(domain::NODEREG, &[&scope])
}

// spec: node_id = SHA-256("mt-node" || node_pubkey) — derive_node_id в mt-state
pub fn compute_node_id(node_pubkey: &[u8; mt_crypto::PUBLIC_KEY_SIZE]) -> NodeId {
    mt_state::derive_node_id(node_pubkey)
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum NodeRegError {
    UnsupportedSuite,
    InvalidSignature,
    NodeIdAlreadyInNodeTable,
    NodeIdAlreadyInCandidatePool,
    OperatorAccountNotFound,
    OperatorAccountAlreadyNode,
    WStartOutOfRange,
    SshaChainTooShort,
}

// spec "Валидация NodeRegistration" строки 1783-1790.
// Проверки 1, 2, 3 (структурные) здесь. Проверки 4, 5, 6 зависят от
// canonical state на момент W_p — выполняются в apply_proposal step 1.
// Отделяем для модульности: структурные в validate_noderegistration,
// contextual в apply_noderegistration_batch (Phase E).
pub fn validate_noderegistration(
    nr: &NodeRegistration,
    node_table: &NodeTable,
    candidate_pool: &CandidatePool,
    account_table: &AccountTable,
) -> Result<(), NodeRegError> {
    // (1) Suite supported
    match suite_id_from_u16(nr.suite_id) {
        Some(SuiteId::Mldsa65) => {},
        None => return Err(NodeRegError::UnsupportedSuite),
    }
    // (1) Signature valid для payload.node_pubkey (SSI R1 signer_suite_id table)
    let mut scope = Vec::new();
    nr.encode_signed_scope(&mut scope);
    let pk = PublicKey::from_array(nr.node_pubkey);
    if !verify(&pk, &scope, &nr.signature) {
        return Err(NodeRegError::InvalidSignature);
    }
    // (2) node_id уникален в Node Table и Candidate Pool
    let node_id = compute_node_id(&nr.node_pubkey);
    if node_table.contains(&node_id) {
        return Err(NodeRegError::NodeIdAlreadyInNodeTable);
    }
    if candidate_pool.contains(&node_id) {
        return Err(NodeRegError::NodeIdAlreadyInCandidatePool);
    }
    // (3) operator_account_id существует и is_node_operator = 0
    let operator = account_table
        .get(&nr.operator_account_id)
        .ok_or(NodeRegError::OperatorAccountNotFound)?;
    if operator.is_node_operator {
        return Err(NodeRegError::OperatorAccountAlreadyNode);
    }
    Ok(())
}

// ============ Phase B: candidate_ssha_init + Candidate Pool apply ============

// spec, "Шаг 2: Кандидатура" + "[I-8] compliance" строка 1794:
//   candidate_ssha_init = SHA-256(
//     "mt-candidate-ssha-init" ||
//     timechain_value(W_start) ||
//     cemented_bundle_aggregate(W_start - 2) ||
//     node_id
//   )
pub fn candidate_ssha_init(
    timechain_value_w_start: &Hash32,
    cba_w_start_minus_2: &Hash32,
    node_id: &NodeId,
) -> Hash32 {
    hash(
        domain::CANDIDATE_SSHA_INIT,
        &[timechain_value_w_start, cba_w_start_minus_2, node_id],
    )
}

// spec: кандидатура истекает через `params.candidate_expiry_windows` от registration.
// [C-1] SSOT: ранее жил как hardcoded `EXPIRY_TAU2_COUNT = 3` + multiplication
// `EXPIRY_TAU2_COUNT × tau2_windows` локально; теперь читается напрямую из
// params.candidate_expiry_windows (60_480 = 3τ₂ at genesis). M4-LOW-7 closure.
pub fn compute_expiry_window(registration_window: u64, params: &ProtocolParams) -> u64 {
    registration_window + params.candidate_expiry_windows
}

// spec "apply_proposal шаг 3a": удалить кандидатов с expires ≤ current_window.
// Возвращает Vec<NodeId> удалённых (для архивации / метрик).
pub fn apply_candidate_expiry(pool: &mut CandidatePool, current_window: u64) -> Vec<NodeId> {
    let to_remove: Vec<NodeId> = pool
        .iter()
        .filter(|c| c.expires <= current_window)
        .map(|c| c.node_id)
        .collect();
    for id in &to_remove {
        pool.remove(id);
    }
    to_remove
}

// ============ Phase C: Selection event ============

// spec, "Selection event":
//   slots = max(1, floor(active_nodes / params.admission_divisor))  — 1% upper bound per event
// [C-1] SSOT: ранее жил как hardcoded `ADMISSION_DIVISOR = 130`; теперь
// читается из params.admission_divisor (130 at genesis). M4-LOW-7 closure.
pub fn selection_slots(active_nodes: u64, params: &ProtocolParams) -> u64 {
    (active_nodes / params.admission_divisor).max(1)
}

// spec "Selection event sort_key":
//   sort_key(c) = SHA-256("mt-selection" || timechain_value(W) ||
//                          cemented_bundle_aggregate(W-2) || c.node_id)
pub fn selection_sort_key(
    timechain_value_w: &Hash32,
    cba_w_minus_2: &Hash32,
    node_id: &NodeId,
) -> Hash32 {
    hash(
        domain::SELECTION,
        &[timechain_value_w, cba_w_minus_2, node_id],
    )
}

// spec "apply_proposal шаг 3b":
//   1. Compute sort_key для каждого candidate
//   2. Sort ascending by sort_key
//   3. Take first `slots` кандидатов → add to Node Table, mark operator is_node_operator=1
//   4. Remove selected from CandidatePool
// Trigger: каждые params.selection_interval окон (336 at genesis).
// [C-1] SSOT: ранее жил как hardcoded `SELECTION_INTERVAL = 336`; теперь
// читается из params.selection_interval. M4-LOW-7 closure.
pub fn is_selection_window(window: u64, params: &ProtocolParams) -> bool {
    window != 0 && window % params.selection_interval == 0
}

// Возвращает отсортированный список (sort_key, candidate) — caller применяет.
pub fn rank_candidates_for_selection(
    pool: &CandidatePool,
    timechain_value_w: &Hash32,
    cba_w_minus_2: &Hash32,
) -> Vec<(Hash32, CandidateRecord)> {
    let mut scored: Vec<(Hash32, CandidateRecord)> = pool
        .iter()
        .map(|c| {
            let key = selection_sort_key(timechain_value_w, cba_w_minus_2, &c.node_id);
            (key, c.clone())
        })
        .collect();
    // Canonical sort: sort_key ascending (32B lex)
    scored.sort_by_key(|s| s.0);
    scored
}

// spec "apply_proposal шаг 3b" + "Шаг 4: Регистрация" (строки 1798-1806):
//   На selection event:
//   1. Rank candidates by sort_key asc
//   2. Take первые `slots` (selection_slots(active_nodes))
//   3. Для каждого выбранного:
//      - Добавить в Node Table с start_window = W, chain_length = 1
//      - Пометить operator_account_id как is_node_operator = 1
//      - Удалить из Candidate Pool
// Возвращает список активированных node_ids.
#[allow(clippy::too_many_arguments)]
pub fn apply_selection_event(
    pool: &mut CandidatePool,
    node_table: &mut NodeTable,
    account_table: &mut AccountTable,
    timechain_value_w: &Hash32,
    cba_w_minus_2: &Hash32,
    active_nodes: u64,
    w: u64,
    params: &ProtocolParams,
) -> Vec<NodeId> {
    let slots = selection_slots(active_nodes, params) as usize;
    let ranked = rank_candidates_for_selection(pool, timechain_value_w, cba_w_minus_2);
    let selected: Vec<CandidateRecord> = ranked.into_iter().take(slots).map(|(_, c)| c).collect();

    let mut activated = Vec::new();
    for cand in selected {
        // Step 4: добавить в Node Table с chain_length = 1 (spec строка 1802)
        let node_record = NodeRecord {
            node_id: cand.node_id,
            node_pubkey: cand.node_pubkey,
            suite_id: cand.suite_id,
            operator_account_id: cand.operator_account_id,
            start_window: w,
            chain_length: 1,
            chain_length_snapshot: 0,
            chain_length_checkpoints: [0; 6],
            last_confirmation_window: 0,
        };
        node_table.insert(node_record);

        // Пометить operator is_node_operator = 1 (spec строка 1806)
        if let Some(acc) = account_table.get(&cand.operator_account_id) {
            let mut updated = acc.clone();
            updated.is_node_operator = true;
            account_table.insert(updated);
        }

        // Remove from Candidate Pool
        pool.remove(&cand.node_id);

        activated.push(cand.node_id);
    }
    activated
}

// ============ Phase D: Adaptive SSHA length ============

// spec, "Adaptive SSHA" строки 1816-1831:
//   candidate_pressure(W) = pending_candidates(W) / active_nodes(W)
//
//   if candidate_pressure(W) > 0.01:
//       required_ssha_length(W) = τ₂_windows × candidate_pressure(W) × 100
//   else:
//       required_ssha_length(W) = τ₂_windows     (base)
//
// Integer form per [I-9]:
//   pressure_permille = (pending * 1000) / active                [u64, 0..=1000+]
//   Если pressure_permille > 10 (= 1%):
//       required = τ₂_windows × pressure_permille × 100 / 1000
//                = τ₂_windows × pressure_permille / 10
//   Иначе:
//       required = τ₂_windows
pub fn required_ssha_length(pending_candidates: u64, active_nodes: u64, tau2_windows: u64) -> u64 {
    if active_nodes == 0 {
        // Genesis / degenerate — нет активных узлов
        return tau2_windows;
    }
    // pressure_permille = (pending * 1000) / active
    // Overflow: pending ≤ 10^6, × 1000 ≤ 10^9, safe u64
    let pressure_permille = (pending_candidates.saturating_mul(1000)) / active_nodes;
    if pressure_permille > 10 {
        // required = τ₂ × pressure_permille / 10
        // Overflow: τ₂ ≤ 78000, × pressure_permille ≤ 78000 × 10^6 ≈ 10^11, safe u64
        tau2_windows.saturating_mul(pressure_permille) / 10
    } else {
        tau2_windows
    }
}

// ============ Phase E: Incremental apply in batch (apply_proposal step 1) ============

// spec "Incremental apply в батче" строки 1835-1854 + "nr_sort_key" 1837-1843:
//   nr_sort_key(nr) = SHA-256(
//     "mt-nodereg-sort" ||
//     timechain_value(W_p) ||
//     cemented_bundle_aggregate(W_p - 2) ||
//     nr.node_pubkey
//   )
pub fn nr_sort_key(
    timechain_value_w_p: &Hash32,
    cba_w_p_minus_2: &Hash32,
    node_pubkey: &[u8; mt_crypto::PUBLIC_KEY_SIZE],
) -> Hash32 {
    hash(
        domain::NODEREG_SORT,
        &[timechain_value_w_p, cba_w_p_minus_2, node_pubkey],
    )
}

// spec "apply_proposal шаг 1" + "Incremental apply":
//   1. Sort cemented_noderegs by nr_sort_key asc
//   2. Для каждой NR в порядке:
//      current_pending = pending_baseline + N_already_applied
//      current_pressure = current_pending / active_nodes
//      required = adaptive_formula(current_pressure)
//      if NR.ssha_chain_length >= required: apply; N += 1
//      else: reject
//   3. Apply = insert в CandidatePool с registration_window = W_p,
//      expires = W_p + 3τ₂.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BatchOutcome {
    pub applied: Vec<NodeId>,
    pub rejected: Vec<NodeId>,
}

#[allow(clippy::too_many_arguments)]
pub fn apply_noderegistrations_batch(
    pool: &mut CandidatePool,
    cemented_noderegs: &[NodeRegistration],
    timechain_value_w_p: &Hash32,
    cba_w_p_minus_2: &Hash32,
    pending_baseline: u64,
    active_nodes: u64,
    w_p: u64,
    params: &ProtocolParams,
) -> BatchOutcome {
    // Canonical sort by nr_sort_key
    let mut sorted: Vec<&NodeRegistration> = cemented_noderegs.iter().collect();
    sorted.sort_by_key(|nr| nr_sort_key(timechain_value_w_p, cba_w_p_minus_2, &nr.node_pubkey));

    let mut applied_count: u64 = 0;
    let mut applied = Vec::new();
    let mut rejected = Vec::new();
    for nr in sorted {
        let current_pending = pending_baseline + applied_count;
        // spec 2250: base_ssha_length = ssha_entry_windows (= τ₂ in production).
        // Reading ssha_entry_windows (not tau2_windows) lets a test build lower the
        // candidate entry length to 1 window while τ₂ stays 20160 for calibration.
        let required =
            required_ssha_length(current_pending, active_nodes, params.ssha_entry_windows);
        let node_id = compute_node_id(&nr.node_pubkey);
        if nr.ssha_chain_length >= required {
            let rec = CandidateRecord {
                node_id,
                node_pubkey: nr.node_pubkey,
                suite_id: nr.suite_id,
                operator_account_id: nr.operator_account_id,
                proof_endpoint: nr.proof_endpoint,
                w_start: nr.w_start,
                ssha_chain_length: nr.ssha_chain_length,
                registration_window: w_p,
                expires: compute_expiry_window(w_p, params),
            };
            pool.insert(rec);
            applied.push(node_id);
            applied_count += 1;
        } else {
            rejected.push(node_id);
        }
    }
    BatchOutcome { applied, rejected }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair, sign, PublicKey, SECRET_KEY_SIZE, SIGNATURE_SIZE};
    use mt_state::{AccountRecord, CandidateRecord};

    const TAU2: u64 = 20_160; // per spec

    fn make_account(id_byte: u8, is_op: bool) -> AccountRecord {
        AccountRecord {
            account_id: [id_byte; 32],
            balance: 1000,
            suite_id: SuiteId::Mldsa65 as u16,
            is_node_operator: is_op,
            frontier_hash: [0; 32],
            op_height: 0,
            account_chain_length: 5,
            account_chain_length_snapshot: 5,
            current_pubkey: [0; mt_crypto::PUBLIC_KEY_SIZE],
            creation_window: 1,
            last_op_window: 2,
            last_activation_window: 0,
        }
    }

    fn stub_nr(pubkey: [u8; mt_crypto::PUBLIC_KEY_SIZE], ssha_len: u64) -> NodeRegistration {
        NodeRegistration {
            suite_id: SuiteId::Mldsa65 as u16,
            node_pubkey: pubkey,
            operator_account_id: [0x11; 32],
            proof_endpoint: [0x33; 32],
            w_start: 100,
            ssha_chain_length: ssha_len,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        }
    }

    fn sign_nr(nr: &mut NodeRegistration, sk: &mt_crypto::SecretKey) {
        let mut scope = Vec::new();
        nr.encode_signed_scope(&mut scope);
        nr.signature = sign(sk, &scope).expect("sign NodeRegistration scope");
    }

    // Phase A tests

    #[test]
    fn nodereg_size_constant() {
        assert_eq!(NODE_REGISTRATION_SIZE, 5344);
    }

    #[test]
    fn nodereg_type_byte_0x11() {
        assert_eq!(TYPE_NODE_REGISTRATION, 0x11);
    }

    #[test]
    fn encode_matches_spec_layout() {
        let (pk, _sk) = keypair();
        let nr = stub_nr(*pk.as_bytes(), 100);
        let mut buf = Vec::new();
        nr.encode(&mut buf);
        assert_eq!(buf.len(), NODE_REGISTRATION_SIZE);
        assert_eq!(buf[0], TYPE_NODE_REGISTRATION);
        assert_eq!(&buf[1..3], &(SuiteId::Mldsa65 as u16).to_le_bytes());
        // node_pubkey: [3..3+1952] = 1952 байт ML-DSA-65 pubkey
        let pk_end = 3 + mt_crypto::PUBLIC_KEY_SIZE;
        assert_eq!(&buf[3..pk_end], pk.as_bytes());
        // operator_account_id 32B
        assert_eq!(&buf[pk_end..pk_end + 32], &[0x11; 32]);
        // proof_endpoint 32B
        assert_eq!(&buf[pk_end + 32..pk_end + 64], &[0x33; 32]);
        // w_start u64 LE
        assert_eq!(&buf[pk_end + 64..pk_end + 72], &100u64.to_le_bytes());
        // ssha_chain_length u64 LE
        assert_eq!(&buf[pk_end + 72..pk_end + 80], &100u64.to_le_bytes());
    }

    #[test]
    fn signed_scope_excludes_signature() {
        let (pk, _sk) = keypair();
        let nr = stub_nr(*pk.as_bytes(), 100);
        let mut scope = Vec::new();
        nr.encode_signed_scope(&mut scope);
        assert_eq!(scope.len(), NODE_REGISTRATION_SIZE - SIGNATURE_SIZE);
    }

    #[test]
    fn nodereg_hash_domain() {
        let (pk, _sk) = keypair();
        let nr = stub_nr(*pk.as_bytes(), 100);
        let mut scope = Vec::new();
        nr.encode_signed_scope(&mut scope);
        assert_eq!(nodereg_hash(&nr), hash(b"mt-nodereg", &[&scope]));
    }

    #[test]
    fn validate_accepts_valid() {
        let (pk, sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), 100);
        let operator = make_account(0x11, false);
        let mut at = AccountTable::new();
        at.insert(operator);
        sign_nr(&mut nr, &sk);
        let nt = NodeTable::new();
        let pool = CandidatePool::new();
        assert_eq!(validate_noderegistration(&nr, &nt, &pool, &at), Ok(()));
    }

    #[test]
    fn validate_rejects_unsupported_suite() {
        let (pk, _sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), 100);
        nr.suite_id = 0xFFFF;
        let nt = NodeTable::new();
        let pool = CandidatePool::new();
        let at = AccountTable::new();
        assert_eq!(
            validate_noderegistration(&nr, &nt, &pool, &at),
            Err(NodeRegError::UnsupportedSuite)
        );
    }

    #[test]
    fn validate_rejects_bad_signature() {
        let (pk, sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), 100);
        sign_nr(&mut nr, &sk);
        let mut sig_bytes = *nr.signature.as_bytes();
        sig_bytes[0] ^= 0xFF;
        nr.signature = Signature::from_array(sig_bytes);
        let operator = make_account(0x11, false);
        let mut at = AccountTable::new();
        at.insert(operator);
        let nt = NodeTable::new();
        let pool = CandidatePool::new();
        assert_eq!(
            validate_noderegistration(&nr, &nt, &pool, &at),
            Err(NodeRegError::InvalidSignature)
        );
    }

    #[test]
    fn validate_rejects_operator_not_found() {
        let (pk, sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), 100);
        sign_nr(&mut nr, &sk);
        let nt = NodeTable::new();
        let pool = CandidatePool::new();
        let at = AccountTable::new(); // no account
        assert_eq!(
            validate_noderegistration(&nr, &nt, &pool, &at),
            Err(NodeRegError::OperatorAccountNotFound)
        );
    }

    #[test]
    fn validate_rejects_operator_already_node() {
        let (pk, sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), 100);
        sign_nr(&mut nr, &sk);
        let operator = make_account(0x11, true); // already node operator
        let mut at = AccountTable::new();
        at.insert(operator);
        let nt = NodeTable::new();
        let pool = CandidatePool::new();
        assert_eq!(
            validate_noderegistration(&nr, &nt, &pool, &at),
            Err(NodeRegError::OperatorAccountAlreadyNode)
        );
    }

    #[test]
    fn compute_node_id_matches_mt_state() {
        let pk = [0x42u8; mt_crypto::PUBLIC_KEY_SIZE];
        assert_eq!(compute_node_id(&pk), mt_state::derive_node_id(&pk));
    }

    // Phase B tests

    #[test]
    fn candidate_ssha_init_formula() {
        let t_r: Hash32 = [0x10; 32];
        let cba: Hash32 = [0x20; 32];
        let node_id: NodeId = [0x30; 32];
        let got = candidate_ssha_init(&t_r, &cba, &node_id);
        let expected = hash(b"mt-candidate-ssha-init", &[&t_r, &cba, &node_id]);
        assert_eq!(got, expected);
    }

    #[test]
    fn candidate_ssha_init_sensitivity() {
        let base = candidate_ssha_init(&[1; 32], &[2; 32], &[3; 32]);
        assert_ne!(candidate_ssha_init(&[9; 32], &[2; 32], &[3; 32]), base);
        assert_ne!(candidate_ssha_init(&[1; 32], &[9; 32], &[3; 32]), base);
        assert_ne!(candidate_ssha_init(&[1; 32], &[2; 32], &[9; 32]), base);
    }

    #[test]
    fn expiry_window_is_3_tau2_later() {
        let p = mt_genesis::genesis_params();
        // params.candidate_expiry_windows = 3 × tau2 at genesis
        assert_eq!(
            compute_expiry_window(100, p),
            100 + p.candidate_expiry_windows
        );
        assert_eq!(p.candidate_expiry_windows, 3 * p.tau2_windows);
    }

    #[test]
    fn apply_candidate_expiry_removes_expired() {
        let mut pool = CandidatePool::new();
        for i in 0..5u8 {
            pool.insert(CandidateRecord {
                node_id: [i; 32],
                node_pubkey: [0; mt_crypto::PUBLIC_KEY_SIZE],
                suite_id: 1,
                operator_account_id: [0; 32],
                proof_endpoint: [0; 32],
                w_start: 0,
                ssha_chain_length: 0,
                registration_window: 0,
                expires: 10 + i as u64,
            });
        }
        let removed = apply_candidate_expiry(&mut pool, 12);
        // Expires 10, 11, 12 removed; 13, 14 remain
        assert_eq!(removed.len(), 3);
        assert_eq!(pool.len(), 2);
    }

    // Phase C tests

    #[test]
    fn selection_slots_at_least_one() {
        let p = mt_genesis::genesis_params();
        assert_eq!(selection_slots(0, p), 1);
        assert_eq!(selection_slots(100, p), 1);
        assert_eq!(selection_slots(129, p), 1);
    }

    #[test]
    fn selection_slots_one_percent_cap() {
        let p = mt_genesis::genesis_params();
        assert_eq!(selection_slots(130, p), 1);
        assert_eq!(selection_slots(260, p), 2);
        assert_eq!(selection_slots(1300, p), 10);
        assert_eq!(selection_slots(13000, p), 100);
    }

    #[test]
    fn selection_sort_key_formula() {
        let t_r: Hash32 = [0x10; 32];
        let cba: Hash32 = [0x20; 32];
        let node_id: NodeId = [0x30; 32];
        let got = selection_sort_key(&t_r, &cba, &node_id);
        assert_eq!(got, hash(b"mt-selection", &[&t_r, &cba, &node_id]));
    }

    #[test]
    fn is_selection_window_at_intervals() {
        // devnet TEST CONFIG: selection_interval=1 → every non-zero window is a
        // selection window (production selection_interval=336). Window 0 is always
        // excluded (genesis). Verify the formula against params.selection_interval.
        let p = mt_genesis::genesis_params();
        let si = p.selection_interval;
        assert!(!is_selection_window(0, p)); // Genesis exclusion
        assert!(is_selection_window(si, p));
        assert!(is_selection_window(2 * si, p));
        // first window strictly inside (0, si) is not a selection window
        if si > 1 {
            assert!(!is_selection_window(si - 1, p));
        }
    }

    #[test]
    fn rank_candidates_sort_deterministic() {
        let mut pool = CandidatePool::new();
        for i in 0..3u8 {
            pool.insert(CandidateRecord {
                node_id: [i; 32],
                node_pubkey: [0; mt_crypto::PUBLIC_KEY_SIZE],
                suite_id: 1,
                operator_account_id: [0; 32],
                proof_endpoint: [0; 32],
                w_start: 0,
                ssha_chain_length: 0,
                registration_window: 0,
                expires: 1000,
            });
        }
        let ranked = rank_candidates_for_selection(&pool, &[0x11; 32], &[0x22; 32]);
        assert_eq!(ranked.len(), 3);
        // Sort key is deterministic — check that two calls give same order
        let ranked2 = rank_candidates_for_selection(&pool, &[0x11; 32], &[0x22; 32]);
        for i in 0..3 {
            assert_eq!(ranked[i].0, ranked2[i].0);
            assert_eq!(ranked[i].1.node_id, ranked2[i].1.node_id);
        }
    }

    // Phase D tests

    #[test]
    fn required_ssha_base_low_pressure() {
        // pressure = 5/1000 = 0.5% < 1% threshold → base τ₂
        assert_eq!(required_ssha_length(5, 1000, TAU2), TAU2);
    }

    #[test]
    fn required_ssha_exactly_1_percent_is_base() {
        // pressure_permille = 10 (1%) → не > 10, base
        assert_eq!(required_ssha_length(10, 1000, TAU2), TAU2);
    }

    #[test]
    fn required_ssha_moderate_pressure() {
        // pressure = 20/1000 = 2% = 20 permille → required = τ₂ × 20 / 10 = 2τ₂
        assert_eq!(required_ssha_length(20, 1000, TAU2), 2 * TAU2);
    }

    #[test]
    fn required_ssha_high_pressure() {
        // pressure = 100/1000 = 10% = 100 permille → 10 × τ₂
        assert_eq!(required_ssha_length(100, 1000, TAU2), 10 * TAU2);
    }

    #[test]
    fn required_ssha_attack_pressure() {
        // pressure = 1000/1000 = 100% = 1000 permille → 100 × τ₂
        assert_eq!(required_ssha_length(1000, 1000, TAU2), 100 * TAU2);
    }

    #[test]
    fn required_ssha_active_zero_returns_base() {
        // Защита от division by zero
        assert_eq!(required_ssha_length(10, 0, TAU2), TAU2);
    }

    // Phase E tests

    #[test]
    fn nr_sort_key_formula() {
        let t_r: Hash32 = [0x10; 32];
        let cba: Hash32 = [0x20; 32];
        let pk = [0x30u8; mt_crypto::PUBLIC_KEY_SIZE];
        let got = nr_sort_key(&t_r, &cba, &pk);
        assert_eq!(got, hash(b"mt-nodereg-sort", &[&t_r, &cba, &pk]));
    }

    #[test]
    fn batch_single_nr_applies() {
        let (pk, sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), TAU2);
        sign_nr(&mut nr, &sk);
        let mut pool = CandidatePool::new();
        let outcome = apply_noderegistrations_batch(
            &mut pool,
            &[nr],
            &[0; 32],
            &[0; 32],
            0,
            1000,
            100,
            mt_genesis::genesis_params(),
        );
        assert_eq!(outcome.applied.len(), 1);
        assert_eq!(outcome.rejected.len(), 0);
        assert_eq!(pool.len(), 1);
    }

    #[test]
    fn batch_insufficient_ssha_rejected() {
        // Shortfall = base required length (params.ssha_entry_windows) minus 1.
        let params = mt_genesis::genesis_params();
        let base = params.ssha_entry_windows;
        let (pk, sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), base.saturating_sub(1)); // shortfall
        sign_nr(&mut nr, &sk);
        let mut pool = CandidatePool::new();
        let outcome = apply_noderegistrations_batch(
            &mut pool,
            &[nr],
            &[0; 32],
            &[0; 32],
            0,
            1000,
            100,
            params,
        );
        assert_eq!(outcome.applied.len(), 0);
        assert_eq!(outcome.rejected.len(), 1);
        assert_eq!(pool.len(), 0);
    }

    #[test]
    fn batch_incremental_pending_increases() {
        // Publish 3 NR, each carrying exactly the base required length — после
        // первой pending += 1, давление растёт, третья требует 2×base → reject.
        let params = mt_genesis::genesis_params();
        let base = params.ssha_entry_windows;
        let mut nrs = Vec::new();
        for _ in 0..3 {
            let (pk, sk) = keypair();
            let mut nr = stub_nr(*pk.as_bytes(), base);
            // Change operator_account to unique id per NR
            nr.operator_account_id = [nrs.len() as u8 + 1; 32];
            sign_nr(&mut nr, &sk);
            nrs.push(nr);
        }
        // Starting pending = 0, active = 100 → pressure starts low, after each applied grows
        // pending = 0, 1, 2 → permille 0, 10, 20
        // NR1: pressure=0 → base; NR2: pressure=10 → base; NR3: pressure=20 → 2×base
        // Third NR has TAU2 = base, not 2×base → rejected
        let mut pool = CandidatePool::new();
        let outcome =
            apply_noderegistrations_batch(&mut pool, &nrs, &[0; 32], &[0; 32], 0, 100, 100, params);
        // First 2 applied, third rejected (required jumps to 2×base at pending=2)
        assert_eq!(outcome.applied.len(), 2);
        assert_eq!(outcome.rejected.len(), 1);
    }

    #[test]
    fn batch_sort_by_nr_sort_key() {
        // Two NRs — проверяем что sort применяется (deterministic order)
        let (pk1, sk1) = keypair();
        let (pk2, sk2) = keypair();
        let mut nr1 = stub_nr(*pk1.as_bytes(), 10 * TAU2);
        nr1.operator_account_id = [0x01; 32];
        let mut nr2 = stub_nr(*pk2.as_bytes(), 10 * TAU2);
        nr2.operator_account_id = [0x02; 32];
        sign_nr(&mut nr1, &sk1);
        sign_nr(&mut nr2, &sk2);

        let p = mt_genesis::genesis_params();
        let mut pool1 = CandidatePool::new();
        let o1 = apply_noderegistrations_batch(
            &mut pool1,
            &[nr1.clone(), nr2.clone()],
            &[0; 32],
            &[0; 32],
            0,
            1000,
            100,
            p,
        );

        let mut pool2 = CandidatePool::new();
        let o2 = apply_noderegistrations_batch(
            &mut pool2,
            &[nr2, nr1],
            &[0; 32],
            &[0; 32],
            0,
            1000,
            100,
            p,
        );
        // Order applied должен быть same (sort deterministic)
        assert_eq!(o1.applied, o2.applied);
    }

    #[test]
    fn secret_key_size_sanity() {
        // ML-DSA-65 expanded secret key
        assert_eq!(SECRET_KEY_SIZE, 4032);
    }

    #[test]
    fn batch_registration_window_and_expiry_set() {
        let (pk, sk) = keypair();
        let mut nr = stub_nr(*pk.as_bytes(), TAU2);
        sign_nr(&mut nr, &sk);
        let mut pool = CandidatePool::new();
        apply_noderegistrations_batch(
            &mut pool,
            &[nr],
            &[0; 32],
            &[0; 32],
            0,
            1000,
            100,
            mt_genesis::genesis_params(),
        );
        let (_, rec) = pool.iter().next().map(|c| (c.node_id, c.clone())).unwrap();
        assert_eq!(rec.registration_window, 100);
        assert_eq!(rec.expires, 100 + 3 * TAU2);
    }

    #[test]
    fn public_key_used_in_sort_key_not_node_id() {
        // nr_sort_key использует node_pubkey напрямую (не node_id)
        let pk = [0x42u8; mt_crypto::PUBLIC_KEY_SIZE];
        let t_r: Hash32 = [0; 32];
        let cba: Hash32 = [0; 32];
        let key1 = nr_sort_key(&t_r, &cba, &pk);
        // Разные pubkey → разные keys
        let pk2 = [0x43u8; mt_crypto::PUBLIC_KEY_SIZE];
        let key2 = nr_sort_key(&t_r, &cba, &pk2);
        assert_ne!(key1, key2);
    }

    #[test]
    fn pk_import_sanity() {
        // PublicKey import used
        let _ = PublicKey::from_array([0; mt_crypto::PUBLIC_KEY_SIZE]);
    }

    #[test]
    fn apply_selection_event_activates_top_k_candidates() {
        let mut pool = CandidatePool::new();
        let mut nt = NodeTable::new();
        let mut at = AccountTable::new();

        // Create 3 candidates + 3 operator accounts
        for i in 1u8..=3 {
            at.insert(make_account(i, false));
            pool.insert(CandidateRecord {
                node_id: [i; 32],
                node_pubkey: [i; mt_crypto::PUBLIC_KEY_SIZE],
                suite_id: 1,
                operator_account_id: [i; 32],
                proof_endpoint: [0; 32],
                w_start: 0,
                ssha_chain_length: 0,
                registration_window: 0,
                expires: 10_000,
            });
        }

        // active_nodes=130 → slots = 1 (min)
        let activated = apply_selection_event(
            &mut pool,
            &mut nt,
            &mut at,
            &[0x11; 32],
            &[0x22; 32],
            130,
            336,
            mt_genesis::genesis_params(),
        );

        assert_eq!(activated.len(), 1);
        assert_eq!(nt.len(), 1);
        assert_eq!(pool.len(), 2); // 2 остались в pool
                                   // Активированный operator помечен
        let op = at.get(&activated[0]).unwrap();
        assert!(op.is_node_operator);
    }

    #[test]
    fn apply_selection_event_multiple_slots() {
        let mut pool = CandidatePool::new();
        let mut nt = NodeTable::new();
        let mut at = AccountTable::new();

        for i in 1u8..=5 {
            at.insert(make_account(i, false));
            pool.insert(CandidateRecord {
                node_id: [i; 32],
                node_pubkey: [i; mt_crypto::PUBLIC_KEY_SIZE],
                suite_id: 1,
                operator_account_id: [i; 32],
                proof_endpoint: [0; 32],
                w_start: 0,
                ssha_chain_length: 0,
                registration_window: 0,
                expires: 10_000,
            });
        }

        // active_nodes=260 → slots = 2
        let activated = apply_selection_event(
            &mut pool,
            &mut nt,
            &mut at,
            &[0x11; 32],
            &[0x22; 32],
            260,
            336,
            mt_genesis::genesis_params(),
        );

        assert_eq!(activated.len(), 2);
        assert_eq!(nt.len(), 2);
        assert_eq!(pool.len(), 3);
    }

    #[test]
    fn apply_selection_event_empty_pool() {
        let mut pool = CandidatePool::new();
        let mut nt = NodeTable::new();
        let mut at = AccountTable::new();
        let activated = apply_selection_event(
            &mut pool,
            &mut nt,
            &mut at,
            &[0; 32],
            &[0; 32],
            130,
            336,
            mt_genesis::genesis_params(),
        );
        assert!(activated.is_empty());
        assert!(nt.is_empty());
    }

    #[test]
    fn apply_selection_event_new_node_chain_length_1() {
        // spec строка 1802: chain_length = 1 при активации
        let mut pool = CandidatePool::new();
        let mut nt = NodeTable::new();
        let mut at = AccountTable::new();
        at.insert(make_account(1, false));
        pool.insert(CandidateRecord {
            node_id: [1; 32],
            node_pubkey: [1; mt_crypto::PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [1; 32],
            proof_endpoint: [0; 32],
            w_start: 0,
            ssha_chain_length: 0,
            registration_window: 0,
            expires: 10_000,
        });
        let activated = apply_selection_event(
            &mut pool,
            &mut nt,
            &mut at,
            &[0x11; 32],
            &[0x22; 32],
            130,
            500,
            mt_genesis::genesis_params(),
        );
        let new_node = nt.get(&activated[0]).unwrap();
        assert_eq!(new_node.chain_length, 1);
        assert_eq!(new_node.start_window, 500);
    }
}
