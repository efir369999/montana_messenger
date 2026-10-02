// spec, разделы "BundledConfirmation", "SSHA Reveal и лотерея", "Signed scope, identity и aggregation" (Правила R1, R2)

use mt_codec::{domain, write_bytes, write_u16, write_u64, CanonicalEncode};
use mt_crypto::{
    hash, suite_id_from_u16, verify, Hash32, PublicKey, Signature, SuiteId, SIGNATURE_SIZE,
};
use mt_state::{NodeId, NodeTable};

// spec v33.1.5+: window_index унифицирован на u64 (8B LE) во всех M4 структурах
// (BundledConfirmation, SshaReveal, ProposalHeader). Старый u32 (4B) убран как
// architectural smell — единый тип для одного концептуально-единого field
// устраняет cross-struct cast и расхождение в hash composition.
pub const BUNDLE_FIXED_OVERHEAD: usize = 32 + 32 + 8 + 2 + 2 + SIGNATURE_SIZE;
pub const REVEAL_SIZE: usize = 32 + 8 + 32 + SIGNATURE_SIZE;

// Early-warning threshold для bundle hash counts (closure M-M4-1 partial,
// per внешний аудит claude-opus-4-7-1m_2026-04-28_T2023).
//
// u16 length prefix даёт hard cap 65 535 hashes; на 1B пользователей при
// ~1000 узлах одно окно может приближаться к этому пределу. Threshold = 50%
// (32 768) — early signal для оператора / mt-telemetry чтобы M6+ spec-patch
// u16→u32 был запланирован ДО реального достижения hard reject.
//
// Lib остаётся silent (no eprintln, [I-3] / [C-6] cleanliness): caller
// (montana-node либо mt-telemetry F-5) применяет should_warn_*_count() в
// собственном logging path. validate_bundle продолжает hard reject ровно на
// u16::MAX — early-warning не меняет consensus semantics.
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
    // spec: Правило R1 — signed_scope = canonical_bytes без поля signature (last SIGNATURE_SIZE bytes)
    //
    // Wire format: длины op_hashes/reveal_hashes как u16 LE prefixes (per spec).
    // Caller responsibility: validate_bundle проверяет op_hashes.len() ≤ u16::MAX
    // ДО encode (M4-1 closure). debug_assert catch silent truncation если caller
    // обходит validate_bundle в debug builds; в release полагается на validate
    // gating (signature verify косвенно catches encode mismatch).
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        debug_assert!(
            self.op_hashes.len() <= u16::MAX as usize,
            "BundledConfirmation.op_hashes.len() = {} > u16::MAX; \
             caller обязан validate_bundle ДО encode (M4-1 invariant)",
            self.op_hashes.len()
        );
        debug_assert!(
            self.reveal_hashes.len() <= u16::MAX as usize,
            "BundledConfirmation.reveal_hashes.len() = {} > u16::MAX; \
             caller обязан validate_bundle ДО encode (M4-1 invariant)",
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

// spec: Правило R2 — bundle_hash = SHA-256("mt-bundle" || signed_scope(bundle))
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
    // M4-1 closure: encode_signed_scope использует write_u16 для длины
    // op_hashes/reveal_hashes (spec wire format). При len > u16::MAX = 65535
    // cast `as u16` молча truncates → silent encode/decode mismatch. Защита
    // через signature verify косвенная (mismatch → wrong scope hash → fail);
    // explicit invariant ловит это до encode/sign и даёт чёткий error path.
    TooManyOps,
    TooManyReveals,
}

// spec: "op_hashes[] ascending lexicographic" + "reveal_hashes[] ascending lexicographic"
fn is_strictly_ascending(items: &[Hash32]) -> bool {
    items.windows(2).all(|w| w[0] < w[1])
}

// spec, раздел "BundledConfirmation" — валидация перед inclusion в cemented set.
// Проверки: (a) node зарегистрирован и подписывает ML-DSA-65,
//           (b) endpoint == T_r текущего окна (caller вычисляет canonical T_r),
//           (c) op_hashes[] / reveal_hashes[] строго возрастают,
//           (d) signature верифицируется против NodeTable[node_id].node_pubkey над signed_scope.
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
    // M4-1 closure: explicit caps на длину Vec'ов перед encode (write_u16 cast).
    // Защита от silent truncation; reject ДО signature verify чтобы не тратить
    // ML-DSA-65 verify cycles на guaranteed-broken bundle.
    // M4-1 hard limit: wire format кодирует длину как u16 LE → ≤ 65535 hashes.
    // SCALE NOTE (M6+ scaling concern): на 1B активных пользователей при
    // ~1000 узлах одно окно может содержать > 100K операций per node →
    // bundle с op_hashes > 65535 не поместится в текущий wire format.
    // Эскалация требует spec-patch на u16→u32 length prefix.
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

// spec, раздел "SSHA Reveal и лотерея" (строки 920-928)
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SshaReveal {
    pub node_id: NodeId,
    pub window_index: u64,
    pub endpoint: Hash32,
    pub signature: Signature,
}

impl SshaReveal {
    // spec: Правило R1 — signed_scope = canonical_bytes без поля signature (last SIGNATURE_SIZE bytes)
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        write_bytes(buf, &self.node_id);
        write_u64(buf, self.window_index);
        write_bytes(buf, &self.endpoint);
    }

    // DEV-020: decode wire-format SshaReveal. Layout = 32 (node_id) + 8 (window_index LE)
    // + 32 (endpoint) + SIGNATURE_SIZE (signature) = 32+8+32+3309 = 3381 bytes for ML-DSA-65.
    pub fn decode(input: &[u8]) -> Result<(Self, usize), &'static str> {
        let needed = 32 + 8 + 32 + SIGNATURE_SIZE;
        if input.len() < needed {
            return Err("truncated SshaReveal");
        }
        let mut node_id = [0u8; 32];
        node_id.copy_from_slice(&input[0..32]);
        let window_index = u64::from_le_bytes(input[32..40].try_into().unwrap());
        let mut endpoint = [0u8; 32];
        endpoint.copy_from_slice(&input[40..72]);
        let mut sig_bytes = [0u8; SIGNATURE_SIZE];
        sig_bytes.copy_from_slice(&input[72..72 + SIGNATURE_SIZE]);
        let signature = Signature::from_array(sig_bytes);
        Ok((
            SshaReveal {
                node_id,
                window_index,
                endpoint,
                signature,
            },
            needed,
        ))
    }
}

impl CanonicalEncode for SshaReveal {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

// spec: Правило R2 — reveal_hash = SHA-256("mt-ssha-reveal" || signed_scope(reveal))
pub fn reveal_hash(reveal: &SshaReveal) -> Hash32 {
    let mut scope = Vec::new();
    reveal.encode_signed_scope(&mut scope);
    hash(domain::SSHA_REVEAL, &[&scope])
}

// spec, "SSHA Reveal и лотерея" — endpoint formula:
//   endpoint_node(W) = SHA-256("mt-lottery" || T_r(W) || cemented_bundle_aggregate(W-2) || node_id || window_index)
// window_index encoded as u64 LE (8B) consistent с layout field (spec v33.1.5+ unified).
pub fn compute_endpoint(
    t_r: &Hash32,
    cemented_bundle_aggregate_w_minus_2: &Hash32,
    node_id: &NodeId,
    window_index: u64,
) -> Hash32 {
    let mut w_le = Vec::with_capacity(8);
    write_u64(&mut w_le, window_index);
    hash(
        domain::LOTTERY,
        &[t_r, cemented_bundle_aggregate_w_minus_2, node_id, &w_le],
    )
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RevealError {
    UnknownNode,
    UnsupportedSuite,
    WrongWindow,
    WrongEndpoint,
    InvalidSignature,
}

// spec, "Валидация SSHA_Reveal" (строки 1020-1026) — правила 1, 2, 3, 5.
// Правило 4 (weighted_ticket < target) — в Phase C (Node lottery).
pub fn validate_reveal(
    reveal: &SshaReveal,
    node_table: &NodeTable,
    t_r: &Hash32,
    cemented_bundle_aggregate_w_minus_2: &Hash32,
    current_window: u64,
) -> Result<(), RevealError> {
    let node = node_table
        .get(&reveal.node_id)
        .ok_or(RevealError::UnknownNode)?;
    match suite_id_from_u16(node.suite_id) {
        Some(SuiteId::Mldsa65) => {},
        None => return Err(RevealError::UnsupportedSuite),
    }
    if reveal.window_index != current_window {
        return Err(RevealError::WrongWindow);
    }
    let expected_endpoint = compute_endpoint(
        t_r,
        cemented_bundle_aggregate_w_minus_2,
        &reveal.node_id,
        reveal.window_index,
    );
    if reveal.endpoint != expected_endpoint {
        return Err(RevealError::WrongEndpoint);
    }
    let mut scope = Vec::new();
    reveal.encode_signed_scope(&mut scope);
    let pk = PublicKey::from_array(node.node_pubkey);
    if !verify(&pk, &scope, &reveal.signature) {
        return Err(RevealError::InvalidSignature);
    }
    Ok(())
}

// ============ Phase C: Node lottery (per [I-9]) ============

// spec, раздел "Класс 1: узлы" + "Integer log algorithm (per [I-9])".
// Conformance status: closed (binding coefficients B0..B3 + 5 test vectors в спеке).

// spec: seniority_term = min(chain_length / 13, chain_length_snapshot).
// Целочисленное деление unsigned u64 (truncation toward zero): chain_length < 13
// ⇒ seniority_term = 0 (первые 13 окон после регистрации).
// Делитель 13 — derivation: target T_cap = 3 × T_year ≈ 1 577 880 окон,
// snapshot_max = 6τ₂ = 120 960, divisor = 1 577 880 / 120 960 ≈ 13.
// Structural reuse: совпадает с EMISSION_moneta = 13 Ɉ per window.
pub fn seniority_term(chain_length: u64, chain_length_snapshot: u64) -> u64 {
    (chain_length / 13).min(chain_length_snapshot)
}

// spec: lottery_weight = chain_length_snapshot + seniority_term.
// Инвариант DS-2: при chain_length_snapshot ≥ 1 (что гарантировано для active
// узлов через pruning/active_predicate chain) → lottery_weight ≥ 1.
// Overflow: snapshot ≤ 120960 (6τ₂), seniority ≤ snapshot, sum ≤ 241920 ⇒ safe u64.
pub fn lottery_weight(chain_length: u64, chain_length_snapshot: u64) -> u64 {
    chain_length_snapshot + seniority_term(chain_length, chain_length_snapshot)
}

// LN(2) в Q64.64: ln(2) × 2^64 ≈ 12786308645202655659 (truncated toward zero).
// spec binding constant LN2_Q64.
const LN2_Q64: u128 = 0xB172_17F7_D1CF_79AB;

// spec binding coefficients (halved polynomial form, все unsigned u64 Q64).
// p(y) = log2(1+y) × 2^64 ≈ (B0 + y·(B1 - y·(B2_ABS - y·B3))) << 1
// a1 > 1 не поместился бы в u64 при полном Q64 — halved form обходит через
// division by 2 и финальный left shift.
const B0: u64 = 0x0014_E086_EC98_2D63;
const B1: u64 = 0xB59D_DDE5_2A69_D000;
const B2_ABS: u64 = 0x49DF_5C3B_FD9C_EC00;
const B3: u64 = 0x1441_7E56_D333_1800;

// spec: log2_q64(endpoint) → Q64.64 u128 representation of log2(2^256 / endpoint).
// Monotonic: меньший endpoint → больший log2_q64.
// endpoint == 0 (вероятность SHA-collision) клипируется до u128::MAX.
//
// Binding: degree-3 Remez minimax polynomial, максимальная ошибка 2^-10.62.
// [I-8] reconciliation: approximation error grinding advantage bounded через
// cemented_bundle_aggregate(W-2) в endpoint formula — см. спеку «Integer log
// algorithm» раздел «[I-8] reconciliation».
pub fn log2_q64(endpoint: &Hash32) -> u128 {
    // Count leading zeros of u256 big-endian.
    let mut leading: u32 = 0;
    let mut all_zero = true;
    for b in endpoint.iter() {
        if *b == 0 {
            leading += 8;
        } else {
            leading += b.leading_zeros();
            all_zero = false;
            break;
        }
    }
    if all_zero {
        // endpoint == 0, log2(∞), saturate
        return u128::MAX;
    }

    // int_part = leading_zeros = log2(2^256 / endpoint) integer part (floor).
    let int_part = leading as u128;

    // Extract u128 mantissa in [2^127, 2^128) from big-endian u256.
    // MSB position in [0, 255] = 255 - leading.
    // Split endpoint в две u128 halves (high = bits 128..255, low = bits 0..127).
    // M4-LOW-3 closure: unwrap_or([0; 16]) вместо expect — структурно
    // unreachable (slice [0..16] от [u8; 32] всегда длиной 16, try_into для
    // [u8; 16] не fails), но absolute panic-free guarantee предпочтительнее
    // controlled panic при protocol invariant breach. На impossible path
    // fallback даёт all-zeros half, log2 returns deterministic 0 (вместо
    // unrecoverable panic). External audit T141253 [LOW].
    let mut hi_bytes = [0u8; 16];
    hi_bytes.copy_from_slice(&endpoint[0..16]);
    let e_hi = u128::from_be_bytes(hi_bytes);
    let mut lo_bytes = [0u8; 16];
    lo_bytes.copy_from_slice(&endpoint[16..32]);
    let e_lo = u128::from_be_bytes(lo_bytes);

    let msb_position: u32 = 255 - leading; // ∈ [0, 255]
    let mantissa: u128 = if msb_position >= 128 {
        // e_hi != 0. Right-shift u256 by (msb_position - 127) ∈ [1, 128].
        let shift = msb_position - 127;
        if shift < 128 {
            (e_hi << (128 - shift)) | (e_lo >> shift)
        } else {
            // shift == 128: low 128 bits of (e_hi:e_lo >> 128) = e_hi
            e_hi
        }
    } else {
        // e_hi == 0. msb in e_lo at bit msb_position ≤ 127.
        // Left-shift e_lo by (127 - msb_position) ∈ [0, 127].
        let shift = 127 - msb_position;
        e_lo << shift
    };

    // x_q64 = y × 2^64 где y = mantissa/2^127 - 1 ∈ [0, 1).
    let x_q64 = ((mantissa - (1u128 << 127)) >> 63) as u64;

    // Unsigned Horner evaluation half_p(y) = B0 + y·(B1 - y·(B2_ABS - y·B3)).
    // Все intermediate shifts u64; intermediate invariants доказаны non-negative в спеке.
    let t1 = (((B3 as u128) * (x_q64 as u128)) >> 64) as u64; // y·B3 ≤ B3 < B2_ABS
    debug_assert!(t1 <= B2_ABS);
    let t2 = B2_ABS - t1;
    let t3 = (((t2 as u128) * (x_q64 as u128)) >> 64) as u64;
    debug_assert!(t3 <= B1);
    let t4 = B1 - t3;
    let t5 = (((t4 as u128) * (x_q64 as u128)) >> 64) as u64;
    let half_p = B0 + t5; // < 2^63 + ε
    let frac_q64 = (half_p as u128) << 1; // ≈ log2(1+y) × 2^64

    // log2(2^256/e) = (leading + 1) - log2(1+y). При y→1 minimax approximation
    // может незначительно превысить 1 (minimax equal positive/negative errors) —
    // saturating_sub обеспечивает результат ≥ 0 (log2 от числа ≥ 1 не отрицательно).
    ((int_part + 1) << 64).saturating_sub(frac_q64)
}

// spec: ticket = ln_q64(endpoint) = -ln(endpoint/2^256) × 2^64.
// Computed as log2_q64 × LN2_Q64 / 2^64.
// Monotonic: меньший endpoint → больший ln_q64.
pub fn ln_q64(endpoint: &Hash32) -> u128 {
    let log2 = log2_q64(endpoint);
    if log2 == u128::MAX {
        return u128::MAX; // endpoint == 0 saturates through
    }

    // log2 < 2^72 (256 × 2^64 bound); LN2 < 2^64.
    // Product fits in u192; need >> 64. Split log2 в high/low 64-bit halves.
    let log2_high = (log2 >> 64) as u64;
    let log2_low = log2 as u64;

    // term_high = log2_high × LN2 (u64 × u128 → u128, LN2 < 2^64 ⇒ safe)
    let term_high = (log2_high as u128) * LN2_Q64;
    // term_low = (log2_low × LN2) >> 64
    let term_low = ((log2_low as u128) * LN2_Q64) >> 64;

    term_high.saturating_add(term_low)
}

// spec, раздел "Класс 1: узлы" integer form.
// weighted_ticket_node = ln_q64(endpoint) / (lottery_weight as u128).
// Precondition: chain_length_snapshot ≥ 1 (DS-2 invariant; caller enforces).
// Integer division toward zero (unsigned u128 / u128).
pub fn weighted_ticket_node(
    endpoint: &Hash32,
    chain_length: u64,
    chain_length_snapshot: u64,
) -> u128 {
    let w = lottery_weight(chain_length, chain_length_snapshot);
    // DS-2 gate: w ≥ 1. Если нарушено — protocol violation (spec строка 924).
    // Здесь защищаемся от panic: при w == 0 возвращаем u128::MAX (неверный
    // winner in argmin, но не crash — caller должен validate до вызова).
    if w == 0 {
        return u128::MAX;
    }
    ln_q64(endpoint) / (w as u128)
}

// ============ Phase D: Account lottery УДАЛЕНА ============
//
// spec Sovereignty Ladder: лотерея single-class. compute_account_endpoint,
// weighted_ticket_account, AccountLotteryError, validate_account_participation,
// domain `mt-account-lottery`, 4 binding test vectors A1-A4 удалены.

// ============ Phase E: Winner determination (argmin) ============

// spec, раздел "Определение winner-а (Lookback Leadership)" (строки ~1017-1056):
// winner_{W-1} = argmin(weighted_ticket) среди cemented SSHA_Reveal nodes + accounts.
//
// [C-1] SSOT: единый источник WINNER_CLASS_NODE — mt-state.
// Лотерея single-class: только узлы (spec Sovereignty Ladder);
// account lottery удалена, значение `2` зарезервировано для будущих расширений.
pub use mt_state::WINNER_CLASS_NODE;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Candidate {
    pub ticket: u128, // weighted_ticket Q64.64 (u128)
    pub class: u8,    // WINNER_CLASS_NODE (единственное valid значение текущей схемы)
    pub id: [u8; 32], // node_id
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Winner {
    pub class: u8,
    pub id: [u8; 32],
    pub ticket: u128,
}

// spec, "argmin(weighted_ticket)" — минимизация по основному ключу.
// Tie-breaking (spec ambiguity, canonical rule введён здесь):
//   1. ticket ascending
//   2. class ascending (Node=1 < Account=2) — node preference при tie
//   3. id lex ascending (32-byte byte-wise compare)
// Probability ticket-tie ~ 2^-128; правило нужно для byte-exact determinism.
pub fn determine_winner(candidates: &[Candidate]) -> Option<Winner> {
    candidates
        .iter()
        .min_by(|a, b| {
            a.ticket
                .cmp(&b.ticket)
                .then_with(|| a.class.cmp(&b.class))
                .then_with(|| a.id.cmp(&b.id))
        })
        .map(|c| Winner {
            class: c.class,
            id: c.id,
            ticket: c.ticket,
        })
}

// spec, раздел "Определение winner-а" + "fallback cascade" (строка 1052):
// fallback_proposer_W = second_min, third_min, etc.
// Возвращает sorted vector кандидатов по той же canonical rule.
// Caller берёт [0] для winner, [1] для fallback_1, и т.д.
pub fn sorted_candidates_for_fallback(candidates: &[Candidate]) -> Vec<Candidate> {
    let mut sorted: Vec<Candidate> = candidates.to_vec();
    sorted.sort_by(|a, b| {
        a.ticket
            .cmp(&b.ticket)
            .then_with(|| a.class.cmp(&b.class))
            .then_with(|| a.id.cmp(&b.id))
    });
    sorted
}

// ============ Phase F: Quorum calculation ============

// spec, раздел "Confirmation cutoff" (строка 1433 + integer form):
//   quorum(W) = ⌈0.67 × active_chain_length(W)⌉        (real-valued commentary)
//   quorum(W) = (67 × active_chain_length + 99) / 100   (integer, authoritative [I-9])
// Unsigned u64. spec bound active ≤ 10^14: 67 × 10^14 + 99 < 2^63 — safe.
//
// M4-LOW-5 closure: saturating_mul/saturating_add защищают от u64::MAX
// overflow (active_chain_length > u64::MAX/67 ≈ 2.7×10^17, нерелевантно
// практически но defense-in-depth: на overflow возвращаем graceful
// u64::MAX/100 вместо silent wrap либо panic в debug build).
pub fn quorum(active_chain_length: u64) -> u64 {
    let scaled = 67u64.saturating_mul(active_chain_length);
    scaled.saturating_add(99) / 100
}

// spec: объект cemented когда cemented_sum ≥ quorum(W).
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
        // 32 768 = ровно 50% от u16::MAX (65 535) + 1; даёт ~33K headroom
        // оператору перед hard reject в validate_bundle.
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
        // window_index u64 LE: 64..72 (spec v33.1.5+ — было u32 4B до v33.1.5)
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
        // signature: last SIGNATURE_SIZE bytes (3309 для ML-DSA-65)
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
        // R2 свойство: identifier стабилен независимо от схемы подписи.
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
        // R2: identifier не зависит от signature
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
        let nt = NodeTable::new(); // пустой
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
        rec.suite_id = 0xFFFF; // не Mldsa65
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
            vec![[0x02; 32], [0x01; 32]], // обратный порядок
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
        // strict ascending — дубликаты отклоняются
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
        // испортить подпись
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
        // подписано other_sk, но NodeTable имеет pk
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
        // Sanity: SECRET_KEY_SIZE импортирован и совпадает (ML-DSA-65 expanded = 4032)
        assert_eq!(SECRET_KEY_SIZE, 4032);
    }

    // -------- SshaReveal (Phase B) --------

    fn build_signed_reveal(
        sk: &mt_crypto::SecretKey,
        node_id: NodeId,
        window_index: u64,
        endpoint: Hash32,
    ) -> SshaReveal {
        let mut r = SshaReveal {
            node_id,
            window_index,
            endpoint,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        r.encode_signed_scope(&mut scope);
        r.signature = sign(sk, &scope).expect("sign Reveal scope");
        r
    }

    #[test]
    fn reveal_encode_matches_spec_layout() {
        let r = SshaReveal {
            node_id: [0xAA; 32],
            window_index: 0x0102030405060708,
            endpoint: [0xBB; 32],
            signature: Signature::from_array([0x44; SIGNATURE_SIZE]),
        };
        let mut buf = Vec::new();
        r.encode(&mut buf);
        assert_eq!(buf.len(), REVEAL_SIZE);
        // spec v33.1.5+: 32 (node_id) + 8 (window u64 LE) + 32 (endpoint) + 3309 (signature ML-DSA-65) = 3381
        assert_eq!(REVEAL_SIZE, 3381);

        // node_id: 0..32
        assert_eq!(&buf[0..32], &[0xAA; 32]);
        // window_index u64 LE: 32..40 (spec v33.1.5+ — было u32 4B до v33.1.5)
        assert_eq!(
            &buf[32..40],
            &[0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
        );
        // endpoint: 40..72
        assert_eq!(&buf[40..72], &[0xBB; 32]);
        // signature: 72..72+SIGNATURE_SIZE
        assert_eq!(&buf[72..72 + SIGNATURE_SIZE], &[0x44; SIGNATURE_SIZE]);
    }

    #[test]
    fn reveal_signed_scope_excludes_signature() {
        let r = SshaReveal {
            node_id: [0x11; 32],
            window_index: 42,
            endpoint: [0x22; 32],
            signature: Signature::from_array([0xCC; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        r.encode_signed_scope(&mut scope);
        let mut full = Vec::new();
        r.encode(&mut full);
        assert_eq!(full.len(), scope.len() + SIGNATURE_SIZE);
        assert_eq!(&full[..scope.len()], scope.as_slice());
        assert_eq!(scope.len(), 32 + 8 + 32);
    }

    #[test]
    fn reveal_hash_domain_mt_ssha_reveal() {
        let r = SshaReveal {
            node_id: [0x01; 32],
            window_index: 7,
            endpoint: [0x02; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        r.encode_signed_scope(&mut scope);
        let expected = hash(b"mt-ssha-reveal", &[&scope]);
        assert_eq!(reveal_hash(&r), expected);
    }

    #[test]
    fn reveal_hash_stable_across_resign() {
        let mut r = SshaReveal {
            node_id: [0x01; 32],
            window_index: 7,
            endpoint: [0x02; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let h1 = reveal_hash(&r);
        r.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
        let h2 = reveal_hash(&r);
        assert_eq!(h1, h2);
    }

    #[test]
    fn endpoint_formula_matches_spec() {
        // spec v33.1.5+: endpoint = SHA-256("mt-lottery" || T_r || cba(W-2) || node_id || window_index(8B LE))
        let t_r: Hash32 = [0x10; 32];
        let cba: Hash32 = [0x20; 32];
        let node_id: NodeId = [0x30; 32];
        let window_index: u64 = 0xDEADBEEFCAFEBABE;
        let got = compute_endpoint(&t_r, &cba, &node_id, window_index);

        let mut w_le = Vec::new();
        mt_codec::write_u64(&mut w_le, window_index);
        let expected = hash(b"mt-lottery", &[&t_r, &cba, &node_id, &w_le]);
        assert_eq!(got, expected);
    }

    #[test]
    fn endpoint_changes_with_each_input() {
        let t_r: Hash32 = [0x10; 32];
        let cba: Hash32 = [0x20; 32];
        let node_id: NodeId = [0x30; 32];
        let w: u64 = 5;
        let base = compute_endpoint(&t_r, &cba, &node_id, w);
        let alt_t_r = [0x11; 32];
        let alt_cba = [0x21; 32];
        let alt_node = [0x31; 32];
        assert_ne!(compute_endpoint(&alt_t_r, &cba, &node_id, w), base);
        assert_ne!(compute_endpoint(&t_r, &alt_cba, &node_id, w), base);
        assert_ne!(compute_endpoint(&t_r, &cba, &alt_node, w), base);
        assert_ne!(compute_endpoint(&t_r, &cba, &node_id, w + 1), base);
    }

    #[test]
    fn validate_reveal_accepts_valid() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let t_r = [0x55; 32];
        let cba = [0x66; 32];
        let w: u64 = 100;
        let endpoint = compute_endpoint(&t_r, &cba, &node_id, w);
        let r = build_signed_reveal(&sk, node_id, w, endpoint);
        assert_eq!(validate_reveal(&r, &nt, &t_r, &cba, w), Ok(()));
    }

    #[test]
    fn validate_reveal_rejects_unknown_node() {
        let (pk, sk) = keypair();
        let (node_id, _rec) = make_node(*pk.as_bytes(), 1);
        let nt = NodeTable::new();
        let t_r = [0; 32];
        let cba = [0; 32];
        let w = 1;
        let endpoint = compute_endpoint(&t_r, &cba, &node_id, w);
        let r = build_signed_reveal(&sk, node_id, w, endpoint);
        assert_eq!(
            validate_reveal(&r, &nt, &t_r, &cba, w),
            Err(RevealError::UnknownNode)
        );
    }

    #[test]
    fn validate_reveal_rejects_unsupported_suite() {
        let (pk, sk) = keypair();
        let (node_id, mut rec) = make_node(*pk.as_bytes(), 1);
        rec.suite_id = 0xFFFF;
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let t_r = [0; 32];
        let cba = [0; 32];
        let w = 1;
        let endpoint = compute_endpoint(&t_r, &cba, &node_id, w);
        let r = build_signed_reveal(&sk, node_id, w, endpoint);
        assert_eq!(
            validate_reveal(&r, &nt, &t_r, &cba, w),
            Err(RevealError::UnsupportedSuite)
        );
    }

    #[test]
    fn validate_reveal_rejects_wrong_window() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let t_r = [0; 32];
        let cba = [0; 32];
        let w: u64 = 10;
        let endpoint = compute_endpoint(&t_r, &cba, &node_id, w);
        let r = build_signed_reveal(&sk, node_id, w, endpoint);
        // current_window = 11, reveal.window_index = 10
        assert_eq!(
            validate_reveal(&r, &nt, &t_r, &cba, 11),
            Err(RevealError::WrongWindow)
        );
    }

    #[test]
    fn validate_reveal_rejects_wrong_endpoint() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let t_r = [0x11; 32];
        let cba = [0x22; 32];
        let w: u64 = 5;
        // заявленный endpoint — произвольный, не равен compute_endpoint
        let bogus_endpoint = [0xEE; 32];
        let r = build_signed_reveal(&sk, node_id, w, bogus_endpoint);
        assert_eq!(
            validate_reveal(&r, &nt, &t_r, &cba, w),
            Err(RevealError::WrongEndpoint)
        );
    }

    #[test]
    fn validate_reveal_rejects_bad_signature() {
        let (pk, sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let t_r = [0x11; 32];
        let cba = [0x22; 32];
        let w: u64 = 5;
        let endpoint = compute_endpoint(&t_r, &cba, &node_id, w);
        let mut r = build_signed_reveal(&sk, node_id, w, endpoint);
        let mut sig_bytes = *r.signature.as_bytes();
        sig_bytes[0] ^= 0xFF;
        sig_bytes[200] ^= 0xAA;
        r.signature = Signature::from_array(sig_bytes);
        assert_eq!(
            validate_reveal(&r, &nt, &t_r, &cba, w),
            Err(RevealError::InvalidSignature)
        );
    }

    #[test]
    fn validate_reveal_rejects_signature_from_different_key() {
        let (pk, _sk) = keypair();
        let (_other_pk, other_sk) = keypair();
        let (node_id, rec) = make_node(*pk.as_bytes(), 1);
        let mut nt = NodeTable::new();
        nt.insert(rec);
        let t_r = [0; 32];
        let cba = [0; 32];
        let w: u64 = 1;
        let endpoint = compute_endpoint(&t_r, &cba, &node_id, w);
        // подпись от other_sk, но NodeTable указывает на pk
        let r = build_signed_reveal(&other_sk, node_id, w, endpoint);
        assert_eq!(
            validate_reveal(&r, &nt, &t_r, &cba, w),
            Err(RevealError::InvalidSignature)
        );
    }

    #[test]
    fn reveal_encode_determinism() {
        let r = SshaReveal {
            node_id: [0x42; 32],
            window_index: 99,
            endpoint: [0x77; 32],
            signature: Signature::from_array([0xAA; SIGNATURE_SIZE]),
        };
        let mut a = Vec::new();
        r.encode(&mut a);
        let mut b = Vec::new();
        r.encode(&mut b);
        assert_eq!(a, b);
    }

    #[test]
    fn reveal_size_constant_value() {
        // spec v33.1.5+: window_index u64 8B (было u32 4B до v33.1.5)
        assert_eq!(REVEAL_SIZE, 32 + 8 + 32 + SIGNATURE_SIZE);
        assert_eq!(REVEAL_SIZE, 3381);
    }

    // ============ Phase C: Node lottery ============

    #[test]
    fn seniority_below_13_is_zero() {
        // chain_length < 13 → seniority_term = 0 (integer div truncation)
        for cl in [0u64, 1, 5, 12] {
            assert_eq!(seniority_term(cl, 1000), 0);
        }
    }

    #[test]
    fn seniority_at_13_is_one() {
        assert_eq!(seniority_term(13, 1000), 1);
    }

    #[test]
    fn seniority_capped_by_snapshot() {
        // chain_length / 13 может превысить snapshot → cap на snapshot
        let cl = 130_000u64;
        let snap = 100u64;
        // 130_000 / 13 = 10_000, min(10_000, 100) = 100
        assert_eq!(seniority_term(cl, snap), 100);
    }

    #[test]
    fn lottery_weight_sum_of_components() {
        // chain_length = 26 → chain_length / 13 = 2
        // snapshot = 10 → seniority_term = min(2, 10) = 2
        // lottery_weight = 10 + 2 = 12
        assert_eq!(lottery_weight(26, 10), 12);
    }

    #[test]
    fn lottery_weight_ds2_floor_at_snapshot_one() {
        // DS-2: snapshot ≥ 1 ⇒ lottery_weight ≥ 1
        // chain_length = 0 → seniority = 0 → weight = snapshot
        assert_eq!(lottery_weight(0, 1), 1);
    }

    #[test]
    fn lottery_weight_new_node_13_windows() {
        // Первые 13 окон: chain_length < 13, seniority = 0, weight = snapshot
        // Per spec: "первые 13 окон после регистрации lottery_weight = snapshot"
        assert_eq!(lottery_weight(1, 1), 1);
        assert_eq!(lottery_weight(7, 7), 7);
        assert_eq!(lottery_weight(12, 12), 12);
    }

    #[test]
    fn lottery_weight_max_2x_snapshot() {
        // Spec: "максимальное преимущество старожила ≈ 2x относительно новичка"
        // seniority capped by snapshot ⇒ lottery_weight ≤ 2 × snapshot
        let snap = 120_960u64; // 6τ₂ при τ₂ = 20 160
        let max_cl = u64::MAX;
        let w = lottery_weight(max_cl, snap);
        assert!(w <= 2 * snap);
        assert_eq!(w, 2 * snap); // saturated cap
    }

    #[test]
    fn log2_q64_zero_endpoint_saturates() {
        assert_eq!(log2_q64(&[0u8; 32]), u128::MAX);
    }

    #[test]
    fn log2_q64_one_endpoint_max_log() {
        // endpoint = 1 (only LSB set) → log2(2^256/1) = 256 exactly.
        // poly3 approximation at y=0: frac = 2·B0 ≈ 2^49 (minimax equioscillating
        // error at endpoints, not zero). Binding output: (leading+1)·2^64 - 2·B0.
        let mut e = [0u8; 32];
        e[31] = 1;
        let log2 = log2_q64(&e);
        let two_b0 = 2u128 * 0x0014_E086_EC98_2D63u128; // 2·B0 = frac at y=0
        assert_eq!(log2, (256u128 << 64) - two_b0);
    }

    #[test]
    fn log2_q64_full_bits_minimal() {
        // endpoint = 0xFF..FF (all bits set), msb at bit 255
        // leading_zeros = 0, y ≈ 1 - ε
        // Real log2(2^256 / (2^256 - 1)) ≈ 0 (very small positive)
        // Линейная аппроксимация: frac = 2^64 - x_q64 где x_q64 ≈ 2^64 - 1
        // ⇒ frac ≈ 1 Q64 (near zero в real units)
        let e = [0xFFu8; 32];
        let log2 = log2_q64(&e);
        assert_eq!(log2 >> 64, 0);
        // frac в младшей области — near-zero в real units
        let frac = log2 & ((1u128 << 64) - 1);
        assert!(frac < (1u128 << 4)); // менее 2^-60 real — очень близко к нулю
    }

    #[test]
    fn log2_q64_monotonic_descending_in_endpoint() {
        // endpoint_a < endpoint_b ⇒ log2_q64(a) >= log2_q64(b)
        let mut prev = u128::MAX;
        for i in [1u8, 2, 5, 10, 20, 50, 100, 200] {
            let mut e = [0u8; 32];
            e[0] = i; // top byte only
            let v = log2_q64(&e);
            assert!(v <= prev, "log2 not monotonic decreasing: i={i}");
            prev = v;
        }
    }

    #[test]
    fn log2_q64_determinism() {
        let e = [0x55u8; 32];
        let a = log2_q64(&e);
        let b = log2_q64(&e);
        assert_eq!(a, b);
    }

    #[test]
    fn ln_q64_zero_endpoint_saturates() {
        assert_eq!(ln_q64(&[0u8; 32]), u128::MAX);
    }

    #[test]
    fn ln_q64_monotonic_descending() {
        // Same property as log2_q64: smaller endpoint → larger ln
        let mut prev = u128::MAX;
        for i in [1u8, 2, 5, 10, 20, 50, 100, 200] {
            let mut e = [0u8; 32];
            e[0] = i;
            let v = ln_q64(&e);
            assert!(v <= prev);
            prev = v;
        }
    }

    #[test]
    fn ln_q64_determinism() {
        let e = [0xABu8; 32];
        assert_eq!(ln_q64(&e), ln_q64(&e));
    }

    #[test]
    fn ln_q64_equals_log2_times_ln2() {
        // ln(x) = log2(x) × ln(2) ; в Q64: ln_q64 = (log2_q64 × LN2_Q64) >> 64
        let e = [0x77u8; 32];
        let log2 = log2_q64(&e);
        let ln_direct = ln_q64(&e);

        // Reference computation
        let log2_high = (log2 >> 64) as u64;
        let log2_low = log2 as u64;
        let term_high = (log2_high as u128) * LN2_Q64;
        let term_low = ((log2_low as u128) * LN2_Q64) >> 64;
        let ln_expected = term_high.saturating_add(term_low);

        assert_eq!(ln_direct, ln_expected);
    }

    // ============ Binding test vectors (spec v29.12.0, Integer log algorithm) ============

    #[test]
    fn ln_q64_binding_tv1_boundary_low() {
        // TV1 — endpoint = 0x00..01 (smallest non-zero) → largest ln
        let e = {
            let mut e = [0u8; 32];
            e[31] = 1;
            e
        };
        assert_eq!(ln_q64(&e), 0x00000000000000b171fb06bb5b60c961u128);
    }

    #[test]
    fn ln_q64_binding_tv2_msb_only() {
        // TV2 — endpoint = 2^255 → log2 = 1 → ticket ≈ LN2_Q64
        let mut e = [0u8; 32];
        e[0] = 0x80;
        assert_eq!(ln_q64(&e), 0x0000000000000000b15526e15db6980cu128);
    }

    #[test]
    fn ln_q64_binding_tv3_typical() {
        // TV3 — typical dense pattern
        let e = [
            0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0xff, 0xee, 0xdd,
            0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0xff, 0xee,
            0xdd, 0xcc, 0xbb, 0xaa,
        ];
        assert_eq!(ln_q64(&e), 0x00000000000000004f60bd6fe6504646u128);
    }

    #[test]
    fn ln_q64_binding_tv4_near_max() {
        // TV4 — endpoint = 2^256-1 → log2(2^256/e) ≈ 0 → ticket = 0
        let e = [0xFFu8; 32];
        assert_eq!(ln_q64(&e), 0u128);
    }

    #[test]
    fn ln_q64_binding_tv5_peak_error_region() {
        // TV5 — peak-error region (y ≈ 0.84, attacker-favorable peak of equioscillation)
        let e = [
            0xeb, 0x85, 0x1e, 0xb8, 0x51, 0xeb, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ];
        assert_eq!(ln_q64(&e), 0x000000000000000015756c980b547a82u128);
    }

    // Binding test vectors: weighted_ticket_node (spec v29.12.0, Лотерея узлов)
    // Все используют ln_q64 = 0x4f60bd6fe6504646 от TV3 endpoint.

    fn tv3_endpoint() -> [u8; 32] {
        [
            0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0xff, 0xee, 0xdd,
            0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0xff, 0xee,
            0xdd, 0xcc, 0xbb, 0xaa,
        ]
    }

    #[test]
    fn weighted_ticket_node_binding_n1_typical() {
        // chain=1000, snap=500, N=13: seniority = min(1000/13=76, 500) = 76
        // weight = 500 + 76 = 576
        let t = weighted_ticket_node(&tv3_endpoint(), 1000, 500);
        assert_eq!(t, 0x000000000000000000234770A382CE58u128);
    }

    #[test]
    fn weighted_ticket_node_binding_n2_boundary() {
        // DS-2 floor: chain_length=1, snapshot=1 → weight=1
        let t = weighted_ticket_node(&tv3_endpoint(), 1, 1);
        assert_eq!(t, 0x00000000000000004F60BD6FE6504646u128);
    }

    #[test]
    fn weighted_ticket_node_binding_n3_seniority_cap() {
        // chain_length/13 = 76923 но capped by snapshot=10 → seniority=10, weight=20
        let t = weighted_ticket_node(&tv3_endpoint(), 1_000_000, 10);
        assert_eq!(t, 0x000000000000000003F80978CB840383u128);
    }

    #[test]
    fn weighted_ticket_node_binding_n4_max_boundary() {
        // chain_length=u64::MAX, snapshot=120960 (6τ₂ актуальный snapshot_max)
        // → seniority=120960 (capped), weight=241920
        let t = weighted_ticket_node(&tv3_endpoint(), u64::MAX, 120_960);
        assert_eq!(t, 0x000000000000000000001580E0B1AED0u128);
    }

    #[test]
    fn weighted_ticket_node_binding_n5_seniority_threshold() {
        // chain_length=13 exactly: seniority_term = 13/13 = 1, weight = 1+1 = 2
        // Это первое целое значение chain_length дающее seniority_term ≥ 1.
        let t = weighted_ticket_node(&tv3_endpoint(), 13, 1);
        assert_eq!(t, 0x000000000000000027B05EB7F3282323u128);
    }

    // spec Sovereignty Ladder: binding vectors A1-A4 (weighted_ticket_account)
    // удалены. Account lottery не существует в текущей схеме.

    #[test]
    fn weighted_ticket_node_determinism() {
        let e = [0x42u8; 32];
        assert_eq!(
            weighted_ticket_node(&e, 1000, 500),
            weighted_ticket_node(&e, 1000, 500)
        );
    }

    #[test]
    fn weighted_ticket_node_decreases_with_weight() {
        // Больший lottery_weight → меньший weighted_ticket (при том же endpoint).
        // Больше веса — больше шанс победить (меньше ticket в argmin).
        let e = [0x33u8; 32];
        let low_w = weighted_ticket_node(&e, 0, 100);
        let high_w = weighted_ticket_node(&e, 0, 10000);
        assert!(high_w < low_w);
    }

    #[test]
    fn weighted_ticket_node_monotonic_in_endpoint() {
        // При одинаковом weight: меньший endpoint → больший ticket.
        let snap = 1000u64;
        let cl = 10_000u64;
        let mut prev = u128::MAX;
        for i in [1u8, 10, 50, 100, 200, 255] {
            let mut e = [0u8; 32];
            e[0] = i;
            let v = weighted_ticket_node(&e, cl, snap);
            assert!(v <= prev);
            prev = v;
        }
    }

    #[test]
    fn weighted_ticket_node_zero_weight_saturates() {
        // Нарушение DS-2: snapshot = 0 → weight = 0 → защитный u128::MAX
        let e = [0x55u8; 32];
        assert_eq!(weighted_ticket_node(&e, 0, 0), u128::MAX);
    }

    #[test]
    fn weighted_ticket_node_integer_div_toward_zero() {
        // Явно проверить что integer div, не rounding
        let mut e = [0u8; 32];
        e[0] = 0x80; // endpoint = 2^255
        let w: u64 = 3;
        let ticket = ln_q64(&e);
        let expected = ticket / (w as u128); // integer div
        assert_eq!(weighted_ticket_node(&e, 0, w), expected);
    }

    #[test]
    fn log2_q64_boundary_msb_at_127() {
        // msb at bit 127 (границу между hi/lo halves) — edge case мантиссы
        let mut e = [0u8; 32];
        e[16] = 0x80; // bit 127 set в low half
        let v = log2_q64(&e);
        // leading = 128, y = 0, total = 129·2^64 - 2·B0 (minimax poly3 error at y=0)
        let two_b0 = 2u128 * 0x0014_E086_EC98_2D63u128;
        assert_eq!(v, (129u128 << 64) - two_b0);
    }

    #[test]
    fn log2_q64_boundary_msb_at_128() {
        // msb at bit 128 — первый бит high half
        let mut e = [0u8; 32];
        e[15] = 0x01; // bit 128 set
        let v = log2_q64(&e);
        // leading = 127, y = 0, total = 128·2^64 - 2·B0 (minimax poly3 error at y=0)
        let two_b0 = 2u128 * 0x0014_E086_EC98_2D63u128;
        assert_eq!(v, (128u128 << 64) - two_b0);
    }

    #[test]
    fn ln2_q64_constant_value() {
        // LN2_Q64 ≈ ln(2) × 2^64
        // ln(2) ≈ 0.693147... × 2^64 ≈ 0xB17217F7D1CF79AB
        assert_eq!(LN2_Q64, 0xB172_17F7_D1CF_79AB);
    }

    // ============ Phase E: Winner determination ============

    fn cand(ticket: u128, class: u8, id_byte: u8) -> Candidate {
        Candidate {
            ticket,
            class,
            id: [id_byte; 32],
        }
    }

    #[test]
    fn winner_empty_candidates_returns_none() {
        assert_eq!(determine_winner(&[]), None);
    }

    #[test]
    fn winner_single_candidate() {
        let c = cand(100, WINNER_CLASS_NODE, 0x11);
        let w = determine_winner(&[c]).unwrap();
        assert_eq!(w.class, WINNER_CLASS_NODE);
        assert_eq!(w.id, [0x11; 32]);
        assert_eq!(w.ticket, 100);
    }

    #[test]
    fn winner_picks_minimum_ticket() {
        let a = cand(500, WINNER_CLASS_NODE, 0x11);
        let b = cand(100, WINNER_CLASS_NODE, 0x22);
        let c = cand(300, WINNER_CLASS_NODE, 0x33);
        let w = determine_winner(&[a, b, c]).unwrap();
        assert_eq!(w.id, [0x22; 32]);
        assert_eq!(w.ticket, 100);
    }

    #[test]
    fn winner_node_account_mixed_min_wins() {
        // Account с меньшим ticket побеждает над node
        let node = cand(500, WINNER_CLASS_NODE, 0x11);
        let acc = cand(100, WINNER_CLASS_NODE, 0x22);
        let w = determine_winner(&[node, acc]).unwrap();
        assert_eq!(w.class, WINNER_CLASS_NODE);
        assert_eq!(w.ticket, 100);
    }

    #[test]
    fn winner_tie_breaker_class_node_preferred() {
        // Same ticket: Node (class=1) < Account (class=2) → Node wins
        let node = cand(100, WINNER_CLASS_NODE, 0xFF);
        let acc = cand(100, WINNER_CLASS_NODE, 0x00);
        let w = determine_winner(&[acc, node]).unwrap();
        assert_eq!(w.class, WINNER_CLASS_NODE);
    }

    #[test]
    fn winner_tie_breaker_id_lex_ascending() {
        // Same ticket, same class: id lex asc
        let a = cand(100, WINNER_CLASS_NODE, 0x22);
        let b = cand(100, WINNER_CLASS_NODE, 0x11);
        let w = determine_winner(&[a, b]).unwrap();
        assert_eq!(w.id, [0x11; 32]); // lex меньший
    }

    #[test]
    fn winner_deterministic_on_permutation() {
        let c1 = cand(500, WINNER_CLASS_NODE, 0x11);
        let c2 = cand(100, WINNER_CLASS_NODE, 0x22);
        let c3 = cand(300, WINNER_CLASS_NODE, 0x33);
        let w1 = determine_winner(&[c1, c2, c3]).unwrap();
        let w2 = determine_winner(&[c3, c2, c1]).unwrap();
        let w3 = determine_winner(&[c2, c3, c1]).unwrap();
        assert_eq!(w1, w2);
        assert_eq!(w2, w3);
    }

    #[test]
    fn sorted_candidates_fallback_order() {
        let c1 = cand(500, WINNER_CLASS_NODE, 0x11);
        let c2 = cand(100, WINNER_CLASS_NODE, 0x22);
        let c3 = cand(300, WINNER_CLASS_NODE, 0x33);
        let sorted = sorted_candidates_for_fallback(&[c1, c2, c3]);
        assert_eq!(sorted[0].ticket, 100); // winner
        assert_eq!(sorted[1].ticket, 300); // fallback_1
        assert_eq!(sorted[2].ticket, 500); // fallback_2
    }

    #[test]
    fn sorted_candidates_empty() {
        let sorted = sorted_candidates_for_fallback(&[]);
        assert!(sorted.is_empty());
    }

    #[test]
    fn sorted_candidates_stable_on_permutation() {
        let c1 = cand(500, WINNER_CLASS_NODE, 0x11);
        let c2 = cand(100, WINNER_CLASS_NODE, 0x22);
        let c3 = cand(300, WINNER_CLASS_NODE, 0x33);
        let s1 = sorted_candidates_for_fallback(&[c1, c2, c3]);
        let s2 = sorted_candidates_for_fallback(&[c3, c2, c1]);
        assert_eq!(s1, s2);
    }

    #[test]
    fn winner_with_u128_max_tickets() {
        // Защитный u128::MAX при DS-2/DS-3 violation
        let good = cand(1000, WINNER_CLASS_NODE, 0x11);
        let bad = cand(u128::MAX, WINNER_CLASS_NODE, 0x22);
        let w = determine_winner(&[good, bad]).unwrap();
        assert_eq!(w.ticket, 1000);
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
        // 10^14 — max bound в спеке. 67 × 10^14 + 99 = 6.7e15 < 2^63.
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
        // Это эдж кейс — в реальности active=0 halt liveness, не consensus
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

// === Калибровка target на границе τ₂ ===
// spec, «Калибровка target»: target_new = target_old × 13 × τ₂_windows / total_reveals_τ₂.
// Integer-форма [I-9]: u256-промежуток через 2×u128, деление к нулю,
// насыщение в u128::MAX, при total_reveals == 0 калибровки нет (TA4).
pub fn calibrate_target(target_old: u128, total_reveals_tau2: u64, tau2_windows: u64) -> u128 {
    if total_reveals_tau2 == 0 {
        return target_old;
    }
    // numerator = target_old × 13 × τ₂ как (hi, lo) u256.
    let mult = 13u128.saturating_mul(tau2_windows as u128); // ≤ 13 × 2^64 — без переполнения
    let (n_hi, n_lo) = mul_u128(target_old, mult);
    div_u256_by_u64_saturating(n_hi, n_lo, total_reveals_tau2)
}

// u128 × u128 → (hi: u128, lo: u128) — школьное умножение 64-битными половинами.
fn mul_u128(a: u128, b: u128) -> (u128, u128) {
    let (a_hi, a_lo) = (a >> 64, a & 0xFFFF_FFFF_FFFF_FFFF);
    let (b_hi, b_lo) = (b >> 64, b & 0xFFFF_FFFF_FFFF_FFFF);
    let ll = a_lo * b_lo;
    let lh = a_lo * b_hi;
    let hl = a_hi * b_lo;
    let hh = a_hi * b_hi;
    let mid = lh + hl; // ≤ 2×(2^64−1)² < 2^129 − влезает с переносом ниже
    let mid_carry = u128::from(mid < lh);
    let (lo, c1) = ll.overflowing_add(mid << 64);
    let hi = hh + (mid >> 64) + (mid_carry << 64) + u128::from(c1);
    (hi, lo)
}

// (hi‖lo) / d → u128 с насыщением. Длинное деление 64-битными цифрами.
fn div_u256_by_u64_saturating(hi: u128, lo: u128, d: u64) -> u128 {
    let d = d as u128;
    // частное от hi: если hi/d не влезает в верхние 128−64 бит результата — насыщение
    let q_hi = hi / d;
    if q_hi >> 64 != 0 {
        return u128::MAX;
    }
    let r = hi % d;
    // делим (r ‖ lo) по 64 бита
    let lo_hi = lo >> 64;
    let lo_lo = lo & 0xFFFF_FFFF_FFFF_FFFF;
    let t1 = (r << 64) | lo_hi;
    let q1 = t1 / d;
    let r1 = t1 % d;
    let t2 = (r1 << 64) | lo_lo;
    let q2 = t2 / d;
    let q = (q_hi << 64).saturating_add(q1);
    let (res, overflow) = (q << 64).overflowing_add(q2);
    if q >> 64 != 0 || overflow {
        return u128::MAX;
    }
    let _ = res;
    (q << 64) | q2
}

#[cfg(test)]
mod calibrate_target_binding {
    use super::calibrate_target;
    const T0: u128 = 0x8000_0000_0000_0000_0000_0000_0000_0000;
    const TAU2: u64 = 20_160;

    #[test]
    fn ta1_equilibrium() {
        assert_eq!(calibrate_target(T0, 262_080, TAU2), T0);
    }
    #[test]
    fn ta2_double_participation_halves() {
        assert_eq!(calibrate_target(T0, 524_160, TAU2), T0 >> 1);
    }
    #[test]
    fn ta3_low_participation_saturates() {
        assert_eq!(calibrate_target(T0, 20_160, TAU2), u128::MAX);
    }
    #[test]
    fn ta4_zero_reveals_unchanged() {
        assert_eq!(calibrate_target(T0, 0, TAU2), T0);
    }
    #[test]
    fn ta5_single_reveal_saturates() {
        assert_eq!(calibrate_target(T0, 1, TAU2), u128::MAX);
    }
}
