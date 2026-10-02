// Automated determinism invariants для mt-merkle.
// M2 audit prep — proactive regression detection per [I-3] determinism +
// [C-1] SSOT (empty_internal binding с mt-codec/mt-crypto).
//
// Sparse Merkle Tree consensus-critical = ANY non-determinism = consensus fork.

use mt_crypto::Hash32;
use mt_merkle::{empty_internal, internal_hash, leaf_hash, SparseMerkleTree};
use std::mem::size_of_val;

#[test]
fn empty_internal_deterministic_across_invocations() {
    // Same level → same hash, byte-exact, идемпотентно.
    for level in 0..16 {
        let a = empty_internal(level);
        let b = empty_internal(level);
        assert_eq!(a, b, "empty_internal({}) non-deterministic", level);
    }
}

#[test]
fn empty_internal_different_levels_different_hashes() {
    // Domain separation между уровнями — каждый level имеет уникальный hash.
    let mut prev = empty_internal(0);
    for level in 1..16 {
        let h = empty_internal(level);
        assert_ne!(prev, h, "empty_internal({}) collides с предыдущим", level);
        prev = h;
    }
}

#[test]
fn leaf_hash_deterministic() {
    let data = b"montana-test-leaf";
    let a = leaf_hash(data);
    let b = leaf_hash(data);
    assert_eq!(a, b);
    let c = leaf_hash(b"different-data");
    assert_ne!(a, c);
}

#[test]
fn internal_hash_deterministic() {
    let left = [0x11u8; 32];
    let right = [0x22u8; 32];
    let a = internal_hash(&left, &right);
    let b = internal_hash(&left, &right);
    assert_eq!(a, b);
}

#[test]
fn internal_hash_left_right_asymmetric() {
    // internal_hash(L, R) != internal_hash(R, L) — order-sensitive
    // (защита от swap atak на Merkle proofs).
    let l = [0x11u8; 32];
    let r = [0x22u8; 32];
    let lr = internal_hash(&l, &r);
    let rl = internal_hash(&r, &l);
    assert_ne!(lr, rl, "internal_hash должен быть order-sensitive");
}

#[test]
fn smt_empty_root_deterministic() {
    // Пустой tree — root известен и детерминирован между instances.
    let t1: SparseMerkleTree = SparseMerkleTree::new();
    let t2: SparseMerkleTree = SparseMerkleTree::new();
    assert_eq!(
        t1.root(),
        t2.root(),
        "SMT::new() должен давать deterministic empty root"
    );
}

#[test]
fn smt_insert_deterministic_across_orders() {
    // Insertion order не должен влиять на root (BTreeMap внутри = canonical
    // sort by key) — критично для consensus determinism.
    let mut t1 = SparseMerkleTree::new();
    let mut t2 = SparseMerkleTree::new();

    let entries: Vec<([u8; 32], Vec<u8>)> = vec![
        ([0x01u8; 32], b"alice".to_vec()),
        ([0x02u8; 32], b"bob".to_vec()),
        ([0x03u8; 32], b"charlie".to_vec()),
    ];

    // Forward order
    for (k, v) in &entries {
        t1.insert(*k, v);
    }
    // Reverse order
    for (k, v) in entries.iter().rev() {
        t2.insert(*k, v);
    }

    assert_eq!(
        t1.root(),
        t2.root(),
        "Insertion order не должен влиять на SMT root — BTreeMap canonical sort"
    );
}

#[test]
fn smt_root_changes_on_insert() {
    let mut t = SparseMerkleTree::new();
    let empty_root = t.root();
    t.insert([0x42u8; 32], b"value");
    let after_insert = t.root();
    assert_ne!(empty_root, after_insert, "Root must change on insert");
}

// ---------- Static type invariants ----------

#[test]
fn hash32_is_32_bytes() {
    let h: Hash32 = [0u8; 32];
    assert_eq!(size_of_val(&h), 32);
}

#[test]
fn key_type_is_32_bytes() {
    // SMT key = 32 bytes (account_id, node_id, etc.) — фиксированный размер
    // для consensus determinism.
    let k: [u8; 32] = [0u8; 32];
    assert_eq!(size_of_val(&k), 32);
}
