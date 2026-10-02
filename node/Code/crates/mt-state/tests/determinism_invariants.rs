// Automated determinism invariants для mt-state.
// M2 batch 2 audit prep — state layer = consensus state foundation;
// любое non-determinism = consensus fork. Эти invariants ловят regression
// если refactor случайно ломает determinism / SSOT / сериализацию.

use mt_codec::CanonicalEncode;
use mt_crypto::PUBLIC_KEY_SIZE;
use mt_state::{
    compute_state_root, derive_account_id, derive_node_id, is_active, AccountRecord, AccountTable,
    CandidatePool, CandidateRecord, NodeRecord, NodeTable, ACCOUNT_RECORD_SIZE,
    CANDIDATE_RECORD_SIZE, NODE_RECORD_SIZE, WINNER_CLASS_NODE,
};

fn sample_account(id_byte: u8) -> AccountRecord {
    AccountRecord {
        account_id: [id_byte; 32],
        balance: 1_000_000_000_000u128,
        suite_id: 1,
        is_node_operator: false,
        frontier_hash: [0xBB; 32],
        op_height: 5,
        account_chain_length: 10,
        account_chain_length_snapshot: 9,
        current_pubkey: [0xCC; PUBLIC_KEY_SIZE],
        creation_window: 100,
        last_op_window: 200,
        last_activation_window: 0,
    }
}

fn sample_node(id_byte: u8) -> NodeRecord {
    NodeRecord {
        node_id: [id_byte; 32],
        node_pubkey: [0x33; PUBLIC_KEY_SIZE],
        suite_id: 1,
        operator_account_id: [0x77; 32],
        start_window: 1000,
        chain_length: 42,
        chain_length_snapshot: 40,
        chain_length_checkpoints: [0u64; 6],
        last_confirmation_window: 5000,
    }
}

fn sample_candidate(id_byte: u8) -> CandidateRecord {
    CandidateRecord {
        node_id: [id_byte; 32],
        node_pubkey: [0x44; PUBLIC_KEY_SIZE],
        suite_id: 1,
        operator_account_id: [0x55; 32],
        proof_endpoint: [0x66; 32],
        w_start: 500,
        ssha_chain_length: 100,
        registration_window: 500,
        expires: 5000,
    }
}

// ---------- Derivation determinism ----------

#[test]
fn derive_account_id_deterministic() {
    let pk = [0xAAu8; PUBLIC_KEY_SIZE];
    let a = derive_account_id(1, &pk);
    let b = derive_account_id(1, &pk);
    assert_eq!(a, b);
}

#[test]
fn derive_account_id_changes_on_suite_id() {
    let pk = [0xAAu8; PUBLIC_KEY_SIZE];
    let a = derive_account_id(1, &pk);
    let b = derive_account_id(2, &pk);
    assert_ne!(a, b, "suite_id должен влиять на account_id");
}

#[test]
fn derive_account_id_changes_on_pubkey() {
    let a = derive_account_id(1, &[0xAA; PUBLIC_KEY_SIZE]);
    let b = derive_account_id(1, &[0xBB; PUBLIC_KEY_SIZE]);
    assert_ne!(a, b);
}

#[test]
fn derive_node_id_deterministic() {
    let pk = [0xCCu8; PUBLIC_KEY_SIZE];
    let a = derive_node_id(&pk);
    let b = derive_node_id(&pk);
    assert_eq!(a, b);
}

#[test]
fn derive_account_node_id_different() {
    // Same pubkey → different account_id и node_id (разные domain separators).
    let pk = [0xDD; PUBLIC_KEY_SIZE];
    let aid = derive_account_id(1, &pk);
    let nid = derive_node_id(&pk);
    assert_ne!(
        aid, nid,
        "account_id и node_id должны различаться даже от того же pubkey"
    );
}

// ---------- Encoded sizes match constants ([I-9] determinism) ----------

#[test]
fn account_record_encoded_size_constant() {
    let mut buf = Vec::new();
    sample_account(0xAA).encode(&mut buf);
    assert_eq!(
        buf.len(),
        ACCOUNT_RECORD_SIZE,
        "AccountRecord encoded size drift: expected {}, got {}",
        ACCOUNT_RECORD_SIZE,
        buf.len()
    );
}

#[test]
fn node_record_encoded_size_constant() {
    let mut buf = Vec::new();
    sample_node(0x11).encode(&mut buf);
    assert_eq!(
        buf.len(),
        NODE_RECORD_SIZE,
        "NodeRecord encoded size drift: expected {}, got {}",
        NODE_RECORD_SIZE,
        buf.len()
    );
}

#[test]
fn candidate_record_encoded_size_constant() {
    let mut buf = Vec::new();
    sample_candidate(0x22).encode(&mut buf);
    assert_eq!(
        buf.len(),
        CANDIDATE_RECORD_SIZE,
        "CandidateRecord encoded size drift: expected {}, got {}",
        CANDIDATE_RECORD_SIZE,
        buf.len()
    );
}

// ---------- Encoding determinism ----------

#[test]
fn account_record_encoding_deterministic() {
    let r = sample_account(0xCC);
    let mut a = Vec::new();
    let mut b = Vec::new();
    r.encode(&mut a);
    r.encode(&mut b);
    assert_eq!(a, b);
}

// ---------- Table determinism (BTreeMap canonical sort) ----------

#[test]
fn account_table_root_deterministic_across_insertion_orders() {
    let r1 = sample_account(0x01);
    let r2 = sample_account(0x02);
    let r3 = sample_account(0x03);

    let mut t_forward = AccountTable::new();
    t_forward.insert(r1.clone());
    t_forward.insert(r2.clone());
    t_forward.insert(r3.clone());

    let mut t_reverse = AccountTable::new();
    t_reverse.insert(r3.clone());
    t_reverse.insert(r2.clone());
    t_reverse.insert(r1.clone());

    assert_eq!(
        t_forward.root(),
        t_reverse.root(),
        "AccountTable root зависит от insertion order — нарушение [I-3] determinism"
    );
}

#[test]
fn node_table_root_deterministic_across_insertion_orders() {
    let n1 = sample_node(0x10);
    let n2 = sample_node(0x20);
    let n3 = sample_node(0x30);

    let mut t1 = NodeTable::new();
    t1.insert(n1.clone());
    t1.insert(n2.clone());
    t1.insert(n3.clone());

    let mut t2 = NodeTable::new();
    t2.insert(n3.clone());
    t2.insert(n1.clone());
    t2.insert(n2.clone());

    assert_eq!(t1.root(), t2.root());
}

#[test]
fn candidate_pool_root_deterministic_across_insertion_orders() {
    let c1 = sample_candidate(0x40);
    let c2 = sample_candidate(0x50);

    let mut p1 = CandidatePool::new();
    p1.insert(c1.clone());
    p1.insert(c2.clone());

    let mut p2 = CandidatePool::new();
    p2.insert(c2.clone());
    p2.insert(c1.clone());

    assert_eq!(p1.root(), p2.root());
}

// ---------- compute_state_root determinism + dependence ----------

#[test]
fn compute_state_root_deterministic() {
    let n = [0x11u8; 32];
    let c = [0x22u8; 32];
    let a = [0x33u8; 32];
    assert_eq!(
        compute_state_root(&n, &c, &a),
        compute_state_root(&n, &c, &a)
    );
}

#[test]
fn compute_state_root_changes_on_each_root() {
    let n = [0x11u8; 32];
    let c = [0x22u8; 32];
    let a = [0x33u8; 32];
    let base = compute_state_root(&n, &c, &a);

    assert_ne!(base, compute_state_root(&[0x00u8; 32], &c, &a));
    assert_ne!(base, compute_state_root(&n, &[0x00u8; 32], &a));
    assert_ne!(base, compute_state_root(&n, &c, &[0x00u8; 32]));
}

#[test]
fn compute_state_root_order_sensitive() {
    // Order аргументов влияет — node_root vs candidate_root vs account_root
    // нельзя поменять местами.
    let a = [0x11u8; 32];
    let b = [0x22u8; 32];
    let c = [0x33u8; 32];
    assert_ne!(
        compute_state_root(&a, &b, &c),
        compute_state_root(&b, &a, &c),
        "compute_state_root должен быть order-sensitive"
    );
}

// ---------- is_active boundary ----------

#[test]
fn is_active_window_zero_correct_with_saturating_sub() {
    // current_window < last_confirmation_window → saturating_sub = 0 → active
    let n = NodeRecord {
        last_confirmation_window: 100,
        ..sample_node(0x99)
    };
    assert!(is_active(&n, 50, 1000));
}

#[test]
fn is_active_at_2_tau2_boundary_inclusive() {
    let n = NodeRecord {
        last_confirmation_window: 1000,
        ..sample_node(0x88)
    };
    let tau2 = 100;
    // current - last = 200 = 2×τ₂ — inclusive, active
    assert!(is_active(&n, 1200, tau2));
    // current - last = 201 — beyond, inactive
    assert!(!is_active(&n, 1201, tau2));
}

// ---------- Static API invariants ----------

#[test]
fn winner_class_node_is_one() {
    // SSOT [I-10]: WINNER_CLASS_NODE = 1 константа.
    // Если кто-то случайно меняет — этот test fails.
    assert_eq!(WINNER_CLASS_NODE, 1);
}

#[test]
fn record_sizes_positive() {
    // Compile-time const checks — defensive sanity, не runtime check.
    const _: () = assert!(ACCOUNT_RECORD_SIZE > 0);
    const _: () = assert!(NODE_RECORD_SIZE > 0);
    const _: () = assert!(CANDIDATE_RECORD_SIZE > 0);
}

#[test]
fn empty_tables_have_consistent_empty_root() {
    let a = AccountTable::new();
    let b = AccountTable::new();
    assert_eq!(
        a.root(),
        b.root(),
        "Empty AccountTable roots должны совпадать"
    );

    let n1 = NodeTable::new();
    let n2 = NodeTable::new();
    assert_eq!(n1.root(), n2.root());

    let c1 = CandidatePool::new();
    let c2 = CandidatePool::new();
    assert_eq!(c1.root(), c2.root());
}

#[test]
fn account_table_remove_inverse_of_insert() {
    let r = sample_account(0xEE);
    let id = r.account_id;

    let mut t = AccountTable::new();
    let empty_root = t.root();

    t.insert(r);
    assert!(t.contains(&id));
    let after_insert_root = t.root();
    assert_ne!(empty_root, after_insert_root);

    t.remove(&id);
    assert!(!t.contains(&id));
    assert_eq!(
        t.root(),
        empty_root,
        "Insert + remove должно возвращать root к empty state"
    );
}
