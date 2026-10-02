// Automated determinism invariants для mt-entry.
// M4 audit prep — node admission flow: NodeRegistration / candidate_ssha_init /
// selection event / Adaptive SSHA / nr_sort_key. Любое non-determinism =
// consensus fork. Invariants ловят regression в byte-exact encode,
// hash composition, sort orders, либо state transition apply_*_batch.

use mt_codec::CanonicalEncode;
use mt_crypto::{Hash32, Signature, PUBLIC_KEY_SIZE, SIGNATURE_SIZE};
use mt_entry::{
    candidate_ssha_init, compute_expiry_window, compute_node_id, is_selection_window, nodereg_hash,
    nr_sort_key, rank_candidates_for_selection, required_ssha_length, selection_slots,
    selection_sort_key, NodeRegistration, NODE_REGISTRATION_SIZE, TYPE_NODE_REGISTRATION,
};
use mt_state::{CandidatePool, CandidateRecord, NodeId};

// ---------- Helpers ----------

fn sample_node_registration(seed: u8) -> NodeRegistration {
    NodeRegistration {
        suite_id: 1,
        node_pubkey: [seed; PUBLIC_KEY_SIZE],
        operator_account_id: [seed.wrapping_add(1); 32],
        proof_endpoint: [seed.wrapping_add(2); 32],
        w_start: 100,
        ssha_chain_length: 20_160,
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    }
}

fn sample_candidate(seed: u8, w_start: u64) -> CandidateRecord {
    CandidateRecord {
        node_id: [seed; 32],
        node_pubkey: [seed; PUBLIC_KEY_SIZE],
        suite_id: 1,
        operator_account_id: [seed.wrapping_add(1); 32],
        proof_endpoint: [seed.wrapping_add(2); 32],
        w_start,
        ssha_chain_length: 20_160,
        registration_window: w_start,
        expires: w_start + 60_480,
    }
}

// ---------- Encoded size matches constant ([I-9] determinism) ----------

#[test]
fn node_registration_encoded_size_constant() {
    let nr = sample_node_registration(0xAB);
    let mut buf = Vec::new();
    nr.encode(&mut buf);
    assert_eq!(
        buf.len(),
        NODE_REGISTRATION_SIZE,
        "NodeRegistration encoded size drift: expected {}, got {}",
        NODE_REGISTRATION_SIZE,
        buf.len()
    );
}

#[test]
fn type_node_registration_stable() {
    // SSOT [I-10]: type code immutable. Изменение = consensus fork.
    assert_eq!(TYPE_NODE_REGISTRATION, 0x11);
}

// ---------- nodereg_hash R2 invariant ----------

#[test]
fn nodereg_hash_deterministic() {
    let nr = sample_node_registration(0xAB);
    assert_eq!(nodereg_hash(&nr), nodereg_hash(&nr));
}

#[test]
fn nodereg_hash_stable_under_signature_mutation() {
    // R2: signature НЕ входит в hash.
    let mut a = sample_node_registration(0xAB);
    let mut b = a.clone();
    b.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
    assert_eq!(nodereg_hash(&a), nodereg_hash(&b));
    a.signature = Signature::from_array([0x42; SIGNATURE_SIZE]);
    assert_eq!(nodereg_hash(&a), nodereg_hash(&b));
}

#[test]
fn nodereg_hash_changes_on_field_mutation() {
    let base = sample_node_registration(0xAB);
    let m_pubkey = sample_node_registration(0xFF);
    let m_w_start = {
        let mut x = base.clone();
        x.w_start = 999;
        x
    };
    let m_ssha = {
        let mut x = base.clone();
        x.ssha_chain_length = 99999;
        x
    };
    let m_operator = {
        let mut x = base.clone();
        x.operator_account_id = [0xFF; 32];
        x
    };
    assert_ne!(nodereg_hash(&base), nodereg_hash(&m_pubkey));
    assert_ne!(nodereg_hash(&base), nodereg_hash(&m_w_start));
    assert_ne!(nodereg_hash(&base), nodereg_hash(&m_ssha));
    assert_ne!(nodereg_hash(&base), nodereg_hash(&m_operator));
}

// ---------- compute_node_id determinism ----------

#[test]
fn compute_node_id_deterministic() {
    let pubkey = [0xCC; PUBLIC_KEY_SIZE];
    assert_eq!(compute_node_id(&pubkey), compute_node_id(&pubkey));
}

#[test]
fn compute_node_id_changes_on_pubkey() {
    assert_ne!(
        compute_node_id(&[0xAA; PUBLIC_KEY_SIZE]),
        compute_node_id(&[0xBB; PUBLIC_KEY_SIZE])
    );
}

// ---------- candidate_ssha_init / [I-8] binding ----------

#[test]
fn candidate_ssha_init_deterministic() {
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let node_id: NodeId = [0x33; 32];
    assert_eq!(
        candidate_ssha_init(&t_r, &cba, &node_id),
        candidate_ssha_init(&t_r, &cba, &node_id)
    );
}

#[test]
fn candidate_ssha_init_changes_on_each_input() {
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let node_id: NodeId = [0x33; 32];
    let base = candidate_ssha_init(&t_r, &cba, &node_id);
    assert_ne!(base, candidate_ssha_init(&[0xFF; 32], &cba, &node_id));
    assert_ne!(base, candidate_ssha_init(&t_r, &[0xFF; 32], &node_id));
    assert_ne!(base, candidate_ssha_init(&t_r, &cba, &[0xFF; 32]));
}

// ---------- compute_expiry_window ----------

#[test]
fn compute_expiry_window_three_tau2() {
    // [C-1] SSOT: candidate_expiry_windows читается из ProtocolParams (60_480 = 3τ₂ at genesis)
    let p = mt_genesis::genesis_params();
    assert_eq!(p.candidate_expiry_windows, 3 * p.tau2_windows);
    assert_eq!(p.candidate_expiry_windows, 60_480);
    assert_eq!(compute_expiry_window(100, p), 100 + 60_480);
    assert_eq!(compute_expiry_window(0, p), 60_480);
}

// ---------- selection_slots + is_selection_window ----------

#[test]
fn selection_slots_admission_divisor_130() {
    // [C-1] SSOT: admission_divisor читается из ProtocolParams (130 at genesis)
    let p = mt_genesis::genesis_params();
    assert_eq!(p.admission_divisor, 130);
    // active = 0 → max(1, 0) = 1 (защита от division/zero edge)
    assert_eq!(selection_slots(0, p), 1);
    // 130 → 130/130 = 1; max(1, 1) = 1
    assert_eq!(selection_slots(130, p), 1);
    // 1300 → 10
    assert_eq!(selection_slots(1300, p), 10);
    // 1% rule sanity: 100k active → 100k/130 ≈ 769 slots
    assert_eq!(selection_slots(100_000, p), 100_000 / 130);
}

#[test]
fn selection_slots_at_least_one() {
    // max(1, ...) гарантирует ≥ 1 slot для bootstrap (genesis with 1 node)
    let p = mt_genesis::genesis_params();
    for active in [0u64, 1, 50, 129] {
        assert_eq!(selection_slots(active, p), 1, "active={}", active);
    }
}

#[test]
fn is_selection_window_at_interval() {
    // [C-1] SSOT: selection_interval читается из ProtocolParams (devnet TEST
    // CONFIG = 1; production = 336). Window 0 is always excluded (genesis).
    let p = mt_genesis::genesis_params();
    let si = p.selection_interval;
    assert!(!is_selection_window(0, p)); // window 0 — особый случай (нет selection)
    assert!(is_selection_window(si, p));
    assert!(is_selection_window(2 * si, p));
    assert!(is_selection_window(si * 100, p));
    if si > 1 {
        assert!(!is_selection_window(si - 1, p));
        assert!(!is_selection_window(si + 1, p));
    }
}

// ---------- selection_sort_key + rank_candidates_for_selection ----------

#[test]
fn selection_sort_key_deterministic() {
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let node_id: NodeId = [0x33; 32];
    assert_eq!(
        selection_sort_key(&t_r, &cba, &node_id),
        selection_sort_key(&t_r, &cba, &node_id)
    );
}

#[test]
fn rank_candidates_canonical_order() {
    // Sort by sort_key asc — input order не влияет.
    let mut p1 = CandidatePool::new();
    p1.insert(sample_candidate(0x10, 100));
    p1.insert(sample_candidate(0x20, 100));
    p1.insert(sample_candidate(0x30, 100));

    let mut p2 = CandidatePool::new();
    p2.insert(sample_candidate(0x30, 100));
    p2.insert(sample_candidate(0x10, 100));
    p2.insert(sample_candidate(0x20, 100));

    let r1 = rank_candidates_for_selection(&p1, &[0xAA; 32], &[0xBB; 32]);
    let r2 = rank_candidates_for_selection(&p2, &[0xAA; 32], &[0xBB; 32]);
    // Same sort_keys derived → same order
    let keys1: Vec<Hash32> = r1.iter().map(|(k, _)| *k).collect();
    let keys2: Vec<Hash32> = r2.iter().map(|(k, _)| *k).collect();
    assert_eq!(keys1, keys2);
    // Sorted asc
    for w in keys1.windows(2) {
        assert!(w[0] <= w[1]);
    }
}

// ---------- required_ssha_length / Adaptive SSHA ----------

#[test]
fn required_ssha_length_no_active_returns_tau2() {
    // Genesis edge case: no active nodes
    assert_eq!(required_ssha_length(5, 0, 20_160), 20_160);
}

#[test]
fn required_ssha_length_below_threshold_returns_tau2() {
    // pressure_permille ≤ 10 (1%) → base τ₂
    // 5 pending / 1000 active = 5 permille (= 0.5%, < 1%)
    assert_eq!(required_ssha_length(5, 1000, 20_160), 20_160);
    // 10 pending / 1000 active = 10 permille = 1% (boundary, ≤ 10)
    assert_eq!(required_ssha_length(10, 1000, 20_160), 20_160);
}

#[test]
fn required_ssha_length_above_threshold_scales() {
    // 20 pending / 1000 active = 20 permille (2%, > 10)
    // → required = τ₂ × 20 / 10 = τ₂ × 2 = 40_320
    assert_eq!(required_ssha_length(20, 1000, 20_160), 40_320);
    // 100 pending / 1000 active = 100 permille = 10%
    // → required = τ₂ × 100 / 10 = τ₂ × 10
    assert_eq!(required_ssha_length(100, 1000, 20_160), 201_600);
}

// ---------- nr_sort_key ----------

#[test]
fn nr_sort_key_deterministic() {
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let pubkey = [0x33; PUBLIC_KEY_SIZE];
    assert_eq!(
        nr_sort_key(&t_r, &cba, &pubkey),
        nr_sort_key(&t_r, &cba, &pubkey)
    );
}

#[test]
fn nr_sort_key_changes_on_each_input() {
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let pubkey = [0x33; PUBLIC_KEY_SIZE];
    let base = nr_sort_key(&t_r, &cba, &pubkey);
    assert_ne!(base, nr_sort_key(&[0xFF; 32], &cba, &pubkey));
    assert_ne!(base, nr_sort_key(&t_r, &[0xFF; 32], &pubkey));
    assert_ne!(base, nr_sort_key(&t_r, &cba, &[0xFF; PUBLIC_KEY_SIZE]));
}

// ---------- Cross-distinctness of similar hash compositions ----------

#[test]
fn distinct_domains_for_three_hash_compositions() {
    // selection_sort_key, candidate_ssha_init, nr_sort_key все принимают (timechain, cba, identity).
    // Domain separators различают:
    //   selection_sort_key:   "mt-selection"
    //   candidate_ssha_init:   "mt-candidate-ssha-init"
    //   nr_sort_key:          "mt-nodereg-sort"
    let t_r = [0x11; 32];
    let cba = [0x22; 32];
    let node_id: NodeId = [0x33; 32];
    let pubkey = [0x33; PUBLIC_KEY_SIZE];

    let sel = selection_sort_key(&t_r, &cba, &node_id);
    let ssha = candidate_ssha_init(&t_r, &cba, &node_id);
    let nr = nr_sort_key(&t_r, &cba, &pubkey);

    assert_ne!(
        sel, ssha,
        "selection vs candidate-ssha-init domains must differ"
    );
    assert_ne!(
        ssha, nr,
        "candidate-ssha-init vs nodereg-sort domains must differ"
    );
    assert_ne!(sel, nr, "selection vs nodereg-sort domains must differ");
}

// ---------- Static API invariants ----------

#[test]
fn record_size_positive() {
    const _: () = assert!(NODE_REGISTRATION_SIZE > 0);
    const _: () = assert!(NODE_REGISTRATION_SIZE == 5344);
}

#[test]
fn admission_divisor_one_percent_cap() {
    // 1% / 100 = 1/100; admission_divisor = 130 даёт ≤ ~0.77% per event
    // (130 ≥ 100 чтобы slots = 1% или меньше). [C-1] SSOT: значение читается
    // из ProtocolParams, не hardcoded const.
    let p = mt_genesis::genesis_params();
    assert!(p.admission_divisor >= 100);
}

#[test]
fn selection_interval_factors_into_tau2() {
    // selection_interval = 336 ≤ τ₂ = 20_160 (60×336 = 20_160). [C-1] SSOT:
    // значение читается из ProtocolParams, не hardcoded const.
    let p = mt_genesis::genesis_params();
    assert!(p.selection_interval < p.tau2_windows);
    assert_eq!(p.tau2_windows % p.selection_interval, 0);
}
