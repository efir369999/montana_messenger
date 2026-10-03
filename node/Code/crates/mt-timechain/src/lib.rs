// spec: разделы "Двигатели → TimeChain SSHA — осциллятор", "Адаптация D через
// participation-ratio feedback", "Cemented bundle aggregate"

use mt_codec::{domain, write_u64};
use mt_crypto::{hash, Hash32};
use mt_genesis::ProtocolParams;
use mt_state::NodeId;
use sha2::{Digest, Sha256};

pub type WindowIndex = u64;

// Upper bound on the per-window SSHA iteration count accepted by both
// ssha_step (consensus path) and ssha_verify (validator path). Honest
// production D values live in the [D0/8, D0*8] band (calibrated to one
// τ₁ window on commodity x86_64); a malicious proposer that forges a
// header with `d > MAX_D` would be able to wedge every follower's
// ssha_verify loop for ≈ 2^32 SHA-256 rounds otherwise. Capping at
// 2^32 - 1 keeps the verifier cost bounded while leaving multiple
// orders of magnitude of headroom over the calibrated regime.
pub const MAX_D: u64 = u32::MAX as u64;

// spec: T_r = SHA-256^d(prev). d must satisfy 1 ≤ d ≤ MAX_D; values outside
// the range are protocol violations and `ssha_step` panics, which is the
// correct consensus-halt behaviour on the proposer path (state machine
// must never run forever / never run zero iterations). Validator path
// runs through `ssha_verify`, which returns `false` instead of panicking.
pub fn ssha_step(prev: &Hash32, d: u64) -> Hash32 {
    assert!(
        (1..=MAX_D).contains(&d),
        "ssha_step: d = {d} outside the protocol-accepted band [1, MAX_D = {}]",
        MAX_D
    );
    let mut current = *prev;
    for _ in 0..d {
        current = Sha256::digest(current).into();
    }
    current
}

// Validator-side: accepts a proposer's claimed (prev, d, claim) triple and
// returns whether ssha_step(prev, d) == claim. Returns false for any d
// outside the [1, MAX_D] band, so a malicious proposer cannot wedge the
// verifier with `d = 0` (trivial identity acceptance) or `d = u64::MAX`
// (≈ 2^64 SHA-256 rounds per validate call).
pub fn ssha_verify(prev: &Hash32, d: u64, claim: &Hash32) -> bool {
    if !(1..=MAX_D).contains(&d) {
        return false;
    }
    &ssha_step(prev, d) == claim
}

// spec: Adaptive D feedback on τ₂ boundary. Integer form per [I-9].
//   median ≥ dead_zone_high (95%) → D × (rate_den + rate_num) / rate_den
//   median ≤ dead_zone_low  (85%) → D × (rate_den - rate_num) / rate_den
//   else (dead zone)              → D unchanged
//
// median_ratio_permille: 0..=1000 (85% = 850, 95% = 950). Permille для
// [I-3]/[I-9] determinism: unsigned integer arithmetic, byte-exact between
// implementations.
//
// Overflow detection через checked_mul:
// при D₀ = 252M и max growth 1.03 per τ₂, u64::MAX достигается через
// log_1.03(u64::MAX / D₀) ≈ 850 monetary epochs последовательных +3% шагов
// (~1.5M лет). Practical horizon недостижим — D флаппает в dead zone.
// Halt при overflow = correct behavior (encoded arithmetic horizon),
// не attacker-triggered (median_ratio derived канонически из cemented set).
pub fn next_d(current_d: u64, median_ratio_permille: u32, params: &ProtocolParams) -> u64 {
    let low_permille = u32::from(params.participation_dead_zone_low) * 10;
    let high_permille = u32::from(params.participation_dead_zone_high) * 10;

    let rate_num = u64::from(params.d_adjustment_rate_num);
    let rate_den = u64::from(params.d_adjustment_rate_den);

    if median_ratio_permille >= high_permille {
        current_d
            .checked_mul(rate_den + rate_num)
            .unwrap_or_else(|| {
                panic!(
                    "next_d overflow при +3% step: current_d = {current_d} × \
                     (rate_den + rate_num) = {} exceeds u64. Encoded arithmetic \
                     horizon reached — protocol upgrade required.",
                    rate_den + rate_num
                )
            })
            / rate_den
    } else if median_ratio_permille <= low_permille {
        // rate_den > rate_num по конструкции (rate_num=3, rate_den=100), вычитание
        // безопасно. checked_mul защищает от overflow при крупном D.
        current_d
            .checked_mul(rate_den - rate_num)
            .unwrap_or_else(|| {
                panic!(
                    "next_d overflow при -3% step: current_d = {current_d} × \
                     (rate_den - rate_num) = {} exceeds u64.",
                    rate_den - rate_num
                )
            })
            / rate_den
    } else {
        current_d
    }
}

// spec: cemented_bundle_aggregate(W) — Правило R3 (aggregate over signer_node_id, не signatures).
// Три ветви:
//   W < 2                      → 0x00 × 32                                        (Genesis)
//   |cemented| == 0            → SHA-256("mt-bc-aggregate-empty" || W)             (fallback)
//   иначе                       → SHA-256("mt-bc-aggregate" || concat(sorted node_ids) || W)
//
// Aggregate строится только над node_ids cemented confirmers + context window_index.
// Signatures и content (op_hashes[]/reveal_hashes[]) ИСКЛЮЧЕНЫ из input:
//   - Ноль grinding surface через σ (signature исключена из hash input;
//     инвариант сохраняется при любой схеме подписи независимо от
//     deterministic/randomized свойств)
//   - Ноль grinding surface через op_hashes[] subset selection confirmer-ом
//   - [I-8] binding сохранён через quorum emergence S_W
pub fn cemented_bundle_aggregate(window: WindowIndex, cemented_node_ids: &[NodeId]) -> Hash32 {
    let mut w_bytes: Vec<u8> = Vec::with_capacity(8);
    write_u64(&mut w_bytes, window);

    if window < 2 {
        return [0u8; 32];
    }
    if cemented_node_ids.is_empty() {
        return hash(domain::BC_AGGREGATE_EMPTY, &[&w_bytes]);
    }

    // Sorted by node_id asc (детерминизм; node_id канонически commit-нут в NodeTable)
    let mut sorted: Vec<NodeId> = cemented_node_ids.to_vec();
    sorted.sort();

    // Concat node_ids + context (window_index) → hash с domain separator
    let mut concat: Vec<u8> = Vec::with_capacity(sorted.len() * 32);
    for id in &sorted {
        concat.extend_from_slice(id);
    }
    hash(domain::BC_AGGREGATE, &[&concat, &w_bytes])
}

#[cfg(test)]
mod tests {
    use super::*;

    // ============ SSHA ============

    // Per the MAX_D guard hardening, ssha_step now panics on d outside [1, MAX_D].
    // ssha_verify returns false for the same range without panic — that is the
    // correct validator-side behaviour on adversarial input.
    #[test]
    #[should_panic(expected = "outside the protocol-accepted band")]
    fn ssha_step_d_zero_panics() {
        let prev = [0xABu8; 32];
        let _ = ssha_step(&prev, 0);
    }

    #[test]
    #[should_panic(expected = "outside the protocol-accepted band")]
    fn ssha_step_d_above_max_panics() {
        let prev = [0xABu8; 32];
        let _ = ssha_step(&prev, MAX_D + 1);
    }

    #[test]
    fn ssha_verify_rejects_d_zero() {
        let prev = [0xABu8; 32];
        let claim = prev; // identity claim would historically pass for d=0
        assert!(!ssha_verify(&prev, 0, &claim));
    }

    #[test]
    fn ssha_verify_rejects_d_above_max() {
        let prev = [0xABu8; 32];
        let bogus = [0u8; 32];
        assert!(!ssha_verify(&prev, MAX_D + 1, &bogus));
        assert!(!ssha_verify(&prev, u64::MAX, &bogus));
    }

    #[test]
    fn ssha_step_d_one_is_single_sha256() {
        let prev = [0xABu8; 32];
        let expected: Hash32 = Sha256::digest(prev).into();
        assert_eq!(ssha_step(&prev, 1), expected);
    }

    #[test]
    fn ssha_step_d_ten_chains_ten_hashes() {
        let prev = [0x01u8; 32];
        let result = ssha_step(&prev, 10);
        // Вычислим вручную 10 итераций и сравним
        let mut manual: Hash32 = prev;
        for _ in 0..10 {
            manual = Sha256::digest(manual).into();
        }
        assert_eq!(result, manual);
    }

    #[test]
    fn ssha_step_deterministic() {
        let prev = [0xCDu8; 32];
        let a = ssha_step(&prev, 100);
        let b = ssha_step(&prev, 100);
        assert_eq!(a, b);
    }

    #[test]
    fn ssha_verify_roundtrip() {
        let prev = [0xEFu8; 32];
        let claim = ssha_step(&prev, 50);
        assert!(ssha_verify(&prev, 50, &claim));
    }

    #[test]
    fn ssha_verify_rejects_mutated_claim() {
        let prev = [0x11u8; 32];
        let mut claim = ssha_step(&prev, 25);
        claim[0] ^= 0xFF;
        assert!(!ssha_verify(&prev, 25, &claim));
    }

    #[test]
    fn ssha_verify_rejects_wrong_d() {
        let prev = [0x22u8; 32];
        let claim = ssha_step(&prev, 10);
        assert!(!ssha_verify(&prev, 9, &claim));
        assert!(!ssha_verify(&prev, 11, &claim));
    }

    // ============ Adaptive D ============

    #[test]
    fn next_d_median_at_or_above_high_increases() {
        let params = mt_genesis::genesis_params();
        let d = 252_000_000u64;
        // 950 permille = 95% ровно = boundary high
        assert_eq!(next_d(d, 950, params), d * 103 / 100);
        // 1000 = 100%
        assert_eq!(next_d(d, 1000, params), d * 103 / 100);
        // 980
        assert_eq!(next_d(d, 980, params), d * 103 / 100);
    }

    #[test]
    fn next_d_median_at_or_below_low_decreases() {
        let params = mt_genesis::genesis_params();
        let d = 252_000_000u64;
        // 850 permille = 85% = boundary low
        assert_eq!(next_d(d, 850, params), d * 97 / 100);
        // 0
        assert_eq!(next_d(d, 0, params), d * 97 / 100);
        // 700
        assert_eq!(next_d(d, 700, params), d * 97 / 100);
    }

    #[test]
    fn next_d_dead_zone_unchanged() {
        let params = mt_genesis::genesis_params();
        let d = 252_000_000u64;
        // 900 permille = 90% = середина dead zone
        assert_eq!(next_d(d, 900, params), d);
        // 851 = чуть выше low
        assert_eq!(next_d(d, 851, params), d);
        // 949 = чуть ниже high
        assert_eq!(next_d(d, 949, params), d);
    }

    #[test]
    fn next_d_boundary_850_is_decrease() {
        // spec: "<=" означает включительное сравнение с low
        let params = mt_genesis::genesis_params();
        let d = 252_000_000u64;
        assert_eq!(next_d(d, 850, params), d * 97 / 100);
    }

    #[test]
    fn next_d_boundary_950_is_increase() {
        // spec: ">=" означает включительное сравнение с high
        let params = mt_genesis::genesis_params();
        let d = 252_000_000u64;
        assert_eq!(next_d(d, 950, params), d * 103 / 100);
    }

    #[test]
    fn next_d_precision_on_real_d0() {
        // Реальное значение D₀ должно точно умножиться на 103/100
        let params = mt_genesis::genesis_params();
        let d = 252_000_000u64;
        let increased = next_d(d, 1000, params);
        assert_eq!(increased, 252_000_000 * 103 / 100);
        assert_eq!(increased, 259_560_000);

        let decreased = next_d(d, 0, params);
        assert_eq!(decreased, 252_000_000 * 97 / 100);
        assert_eq!(decreased, 244_440_000);
    }

    // ============ cemented_bundle_aggregate (SSI R3: aggregate over node_ids) ============

    #[test]
    fn aggregate_window_zero_is_all_zeros() {
        let ids: Vec<NodeId> = vec![];
        assert_eq!(cemented_bundle_aggregate(0, &ids), [0u8; 32]);
    }

    #[test]
    fn aggregate_window_one_is_all_zeros() {
        let ids: Vec<NodeId> = vec![];
        assert_eq!(cemented_bundle_aggregate(1, &ids), [0u8; 32]);
    }

    #[test]
    fn aggregate_empty_set_uses_fallback_with_window() {
        let ids: Vec<NodeId> = vec![];
        let result = cemented_bundle_aggregate(5, &ids);

        let mut w_bytes: Vec<u8> = Vec::with_capacity(8);
        write_u64(&mut w_bytes, 5u64);
        let expected = hash(domain::BC_AGGREGATE_EMPTY, &[&w_bytes]);
        assert_eq!(result, expected);
    }

    #[test]
    fn aggregate_empty_fallback_depends_on_window() {
        let ids: Vec<NodeId> = vec![];
        let r5 = cemented_bundle_aggregate(5, &ids);
        let r6 = cemented_bundle_aggregate(6, &ids);
        assert_ne!(r5, r6);
    }

    #[test]
    fn aggregate_single_node_id() {
        let ids: Vec<NodeId> = vec![[0xAAu8; 32]];
        let result = cemented_bundle_aggregate(10, &ids);

        let concat: Vec<u8> = ids[0].to_vec();
        let mut w_bytes: Vec<u8> = Vec::with_capacity(8);
        write_u64(&mut w_bytes, 10u64);
        let expected = hash(domain::BC_AGGREGATE, &[&concat, &w_bytes]);
        assert_eq!(result, expected);
    }

    #[test]
    fn aggregate_order_independent() {
        let mk = |order: [u8; 3]| -> Vec<NodeId> { order.iter().map(|b| [*b; 32]).collect() };
        let r1 = cemented_bundle_aggregate(10, &mk([0x01, 0x02, 0x03]));
        let r2 = cemented_bundle_aggregate(10, &mk([0x03, 0x01, 0x02]));
        let r3 = cemented_bundle_aggregate(10, &mk([0x02, 0x03, 0x01]));
        assert_eq!(r1, r2);
        assert_eq!(r2, r3);
    }

    #[test]
    fn aggregate_detects_node_id_change() {
        let original: Vec<NodeId> = vec![[0x01u8; 32], [0x02u8; 32]];
        let mutated: Vec<NodeId> = vec![[0x01u8; 32], [0x03u8; 32]]; // изменён второй
        let r1 = cemented_bundle_aggregate(10, &original);
        let r2 = cemented_bundle_aggregate(10, &mutated);
        assert_ne!(r1, r2);
    }

    #[test]
    fn aggregate_depends_on_window_in_non_empty_branch() {
        // SSI R3: context (W) включается в input hash всегда, не только в empty-ветви.
        // Grinding resistance: разные окна дают разный aggregate даже при identical S_W.
        let ids: Vec<NodeId> = vec![[0x01u8; 32]];
        let r5 = cemented_bundle_aggregate(5, &ids);
        let r100 = cemented_bundle_aggregate(100, &ids);
        assert_ne!(r5, r100);
    }

    #[test]
    fn aggregate_uses_bc_aggregate_domain() {
        let ids: Vec<NodeId> = vec![[0xABu8; 32]];
        let result = cemented_bundle_aggregate(10, &ids);

        let concat: Vec<u8> = ids[0].to_vec();
        let mut w_bytes: Vec<u8> = Vec::with_capacity(8);
        write_u64(&mut w_bytes, 10u64);
        let expected = hash(domain::BC_AGGREGATE, &[&concat, &w_bytes]);
        assert_eq!(result, expected);
    }

    #[test]
    fn aggregate_uses_empty_domain_for_empty_set() {
        let result = cemented_bundle_aggregate(10, &[]);
        let mut w_bytes: Vec<u8> = Vec::with_capacity(8);
        write_u64(&mut w_bytes, 10u64);
        let expected = hash(domain::BC_AGGREGATE_EMPTY, &[&w_bytes]);
        assert_eq!(result, expected);
    }

    #[test]
    fn aggregate_independent_of_signature_type() {
        // Positive test for SSI R3: cemented_bundle_aggregate API больше не принимает
        // Signature — grinding surface через σ устранена конструктивно (signature
        // физически не может попасть в input hash, отсутствует в type сигнатуре функции).
        // Test проверяет компилируемость API только над &[NodeId].
        let ids: Vec<NodeId> = vec![[0x42u8; 32], [0x43u8; 32]];
        let _ = cemented_bundle_aggregate(100, &ids);
    }
}
