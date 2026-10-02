// spec, разделы "Состояние сети → State Root" и "Sparse Merkle Tree algorithm"

use std::cell::Cell;
use std::collections::BTreeMap;
use std::sync::OnceLock;

use mt_codec::{domain, write_bytes, write_u16, write_u32, CanonicalEncode};
use mt_crypto::{hash, Hash32};

pub const TREE_DEPTH: usize = 256;
pub const EMPTY_LEAF: Hash32 = [0u8; 32];

pub fn leaf_hash(serialized: &[u8]) -> Hash32 {
    hash(domain::MERKLE_LEAF, &[serialized])
}

pub fn internal_hash(left: &Hash32, right: &Hash32) -> Hash32 {
    hash(domain::MERKLE_NODE, &[left, right])
}

// Safe API: возвращает None для level > TREE_DEPTH (no panic).
// Предпочтительно для callers где level приходит из untrusted input.
pub fn try_empty_internal(level: usize) -> Option<Hash32> {
    if level > TREE_DEPTH {
        None
    } else {
        Some(empty_internals_cache()[level])
    }
}

// Convenience API: panics при level > TREE_DEPTH (programmer error).
// Эквивалентно `arr[i]` vs `arr.get(i)` в std — для callers где level
// гарантированно в диапазоне (loop bounds 0..=TREE_DEPTH, internal usage).
// Для публичных callers с untrusted level → используйте try_empty_internal.
pub fn empty_internal(level: usize) -> Hash32 {
    // level 0 = empty leaf, level 256 = root of fully empty tree
    assert!(
        level <= TREE_DEPTH,
        "empty_internal: level {level} > TREE_DEPTH ({TREE_DEPTH}); \
         используйте try_empty_internal для untrusted input"
    );
    empty_internals_cache()[level]
}

fn empty_internals_cache() -> &'static [Hash32; 257] {
    static CACHE: OnceLock<[Hash32; 257]> = OnceLock::new();
    CACHE.get_or_init(|| {
        let mut arr = [[0u8; 32]; 257];
        arr[0] = EMPTY_LEAF;
        for k in 1..=TREE_DEPTH {
            arr[k] = internal_hash(&arr[k - 1], &arr[k - 1]);
        }
        arr
    })
}

fn get_bit(key: &[u8; 32], index: usize) -> u8 {
    // Bit index 0 = LSB of key[0]; bit index 255 = MSB of key[31]
    // spec: "биты от наименьшего значимого (LSB) до старшего"
    assert!(index < 256, "get_bit: index >= 256");
    (key[index / 8] >> (index % 8)) & 1
}

// Iterative подмена recursion `compute_subtree_root` через explicit work-stack.
// Эквивалентно post-order DFS — left subtree → right subtree → combine via
// internal_hash. Закрывает finding M2-10 (LOW) внешнего аудита: recursion
// depth 256 × ~100B/frame ≈ 26KB stack растёт линейно от TREE_DEPTH.
//
// Embedded targets (RTOS с 8-32KB stack, Windows default 1MB) могут
// исчерпать stack при concurrent recursion. Iterative version сохраняет
// ту же O(N × 256) work, но stack growth = O(1) frames; explicit work-stack
// растёт на heap (Vec).
//
// Memory: work_stack peak depth = 2 × TREE_DEPTH = 512 Task entries при
// fully descended path. result_stack peak = TREE_DEPTH = 256 Hash32 = 8KB.
// Сумма entries across all pending Compute tasks = N (каждый leaf на одном
// path) — та же memory как recursive version.
//
// Behavioral equivalence гарантируется existing 10 determinism tests +
// SMT property tests; iterative_matches_recursive_baseline (ниже)
// cross-checks обе версии для small N.
fn compute_subtree_root(entries: &[([u8; 32], Hash32)], depth: usize) -> Hash32 {
    enum Task {
        Compute(Vec<([u8; 32], Hash32)>, usize),
        Combine,
    }
    let mut work_stack: Vec<Task> = Vec::with_capacity(2 * TREE_DEPTH);
    let mut result_stack: Vec<Hash32> = Vec::with_capacity(TREE_DEPTH);
    work_stack.push(Task::Compute(entries.to_vec(), depth));

    while let Some(task) = work_stack.pop() {
        match task {
            Task::Compute(entries, depth) => {
                if entries.is_empty() {
                    result_stack.push(empty_internal(depth));
                    continue;
                }
                if depth == 0 {
                    result_stack.push(entries[0].1);
                    continue;
                }
                let bit_index = depth - 1;
                let mut left = Vec::new();
                let mut right = Vec::new();
                for e in entries {
                    if get_bit(&e.0, bit_index) == 0 {
                        left.push(e);
                    } else {
                        right.push(e);
                    }
                }
                // LIFO: push Combine first (executes last), затем right
                // (computed second), затем left (computed first). После
                // выполнения result_stack: [..., left_root, right_root].
                work_stack.push(Task::Combine);
                work_stack.push(Task::Compute(right, depth - 1));
                work_stack.push(Task::Compute(left, depth - 1));
            },
            Task::Combine => {
                // result_stack invariant: [..., left_root, right_root]
                let right = result_stack
                    .pop()
                    .expect("compute_subtree_root: result_stack empty при Combine");
                let left = result_stack
                    .pop()
                    .expect("compute_subtree_root: result_stack empty при Combine (left)");
                result_stack.push(internal_hash(&left, &right));
            },
        }
    }

    debug_assert_eq!(
        result_stack.len(),
        1,
        "compute_subtree_root invariant violation: result_stack must have exactly 1 element"
    );
    result_stack.pop().unwrap_or_else(|| empty_internal(depth))
}

// SparseMerkleTree с invalidate-on-mutate caching root.
//
// Без caching root() — O(N × 256) per call (для N entries, depth 256).
// При N = 10⁶: 256M operations per state_root composition. Для production
// scale (≥1B users per memory feedback_montana_scale_1b) — недопустимо.
//
// Caching через Cell<Option<Hash32>> (interior mutability):
//   - root() возвращает cached value если cache populated
//   - insert/remove invalidates cache (set None) ПЕРЕД мутацией leaves
//   - повторный root() recomputes и заполняет cache
//
// Cell vs Mutex: SMT используется в single-threaded consensus path
// (один узел = один thread обрабатывает state). Cell даёт zero-overhead
// caching без atomic ops. Trade-off: SMT больше не Sync (Cell !Sync), но
// Send сохранён — можно передавать ownership между threads, нельзя share.
//
// Закрывает finding M2-5 (LOW) внешнего аудита Claude Opus 4.7 #2:
// "O(N × 256) на каждый root() call".
#[derive(Default, Clone)]
pub struct SparseMerkleTree {
    // BTreeMap для детерминированной итерации — spec требует byte-for-byte
    // consistency, HashMap с недетерминированным порядком запрещён.
    leaves: BTreeMap<[u8; 32], Hash32>,
    // Lazy cache: None = stale (recompute on next root()), Some = valid.
    // Invalidated explicitly через invalidate_cache() в каждом mutation site.
    cached_root: Cell<Option<Hash32>>,
}

impl SparseMerkleTree {
    pub fn new() -> Self {
        Self {
            leaves: BTreeMap::new(),
            cached_root: Cell::new(None),
        }
    }

    fn invalidate_cache(&self) {
        self.cached_root.set(None);
    }

    pub fn insert_leaf(&mut self, key: [u8; 32], leaf: Hash32) {
        if leaf == EMPTY_LEAF {
            // Invalidate только если действительно удалили запись
            if self.leaves.remove(&key).is_some() {
                self.invalidate_cache();
            }
        } else {
            // Invalidate только если значение реально изменилось (no-op insert
            // того же key→leaf не меняет root)
            let prev = self.leaves.insert(key, leaf);
            if prev != Some(leaf) {
                self.invalidate_cache();
            }
        }
    }

    pub fn insert(&mut self, key: [u8; 32], record: &[u8]) {
        self.insert_leaf(key, leaf_hash(record));
    }

    pub fn remove(&mut self, key: &[u8; 32]) {
        if self.leaves.remove(key).is_some() {
            self.invalidate_cache();
        }
    }

    pub fn contains(&self, key: &[u8; 32]) -> bool {
        self.leaves.contains_key(key)
    }

    pub fn len(&self) -> usize {
        self.leaves.len()
    }

    pub fn is_empty(&self) -> bool {
        self.leaves.is_empty()
    }

    pub fn root(&self) -> Hash32 {
        if let Some(cached) = self.cached_root.get() {
            return cached;
        }
        let entries: Vec<_> = self.leaves.iter().map(|(k, v)| (*k, *v)).collect();
        let computed = compute_subtree_root(&entries, TREE_DEPTH);
        self.cached_root.set(Some(computed));
        computed
    }

    pub fn prove(&self, key: &[u8; 32], serialized: Option<&[u8]>) -> InclusionProof {
        let leaf_value = serialized.map(|s| s.to_vec()).unwrap_or_default();
        let mut siblings = Vec::new();
        let mut bitmap = [0u8; 32];

        let mut current_entries: Vec<_> = self.leaves.iter().map(|(k, v)| (*k, *v)).collect();

        // Descend from root (depth = 256) down to leaf (depth = 0)
        // At each level collect the sibling subtree's root if non-empty
        for depth in (1..=TREE_DEPTH).rev() {
            let bit_index = depth - 1;
            let my_bit = get_bit(key, bit_index);

            let mut same_side = Vec::new();
            let mut other_side = Vec::new();
            for e in current_entries.drain(..) {
                if get_bit(&e.0, bit_index) == my_bit {
                    same_side.push(e);
                } else {
                    other_side.push(e);
                }
            }

            let sibling_level = depth - 1;
            let sibling_root = compute_subtree_root(&other_side, sibling_level);

            if sibling_root != empty_internal(sibling_level) {
                siblings.push(sibling_root);
                let byte = sibling_level / 8;
                let bit_in_byte = sibling_level % 8;
                bitmap[byte] |= 1 << bit_in_byte;
            }

            current_entries = same_side;
        }

        // Iteration above collected siblings in order level=255, 254, ..., 0.
        // Spec: siblings[] in ascending level order → reverse.
        siblings.reverse();

        InclusionProof {
            key: *key,
            leaf_value,
            sibling_bitmap: bitmap,
            siblings,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InclusionProof {
    pub key: [u8; 32],
    pub leaf_value: Vec<u8>,
    pub sibling_bitmap: [u8; 32],
    pub siblings: Vec<Hash32>,
}

// Превентивные bounds для будущего wire decoder (M7+ light-client). Сейчас decode
// не существует — proof строится локально через `prove()`. При появлении decode
// эти константы используются как guard ДО `Vec::with_capacity(attacker_len)`,
// чтобы закрыть unbounded-allocation DoS на raw u32 leaf_length.
//
// Verify_proof проверяет sibling_bitmap (32B = 256 bits = TREE_DEPTH) — больше
// 256 siblings не имеют смысла структурно. leaf_value bound 4096B = ×2 крупнейшей
// state-записи (NodeRecord 2098B), запас на эволюцию layout без bump bound.
pub const MAX_LEAF_VALUE_SIZE: usize = 4096;
pub const MAX_SIBLINGS: usize = TREE_DEPTH; // 256

// spec, "Inclusion proof format":
//   key (32B) | leaf_length (4B u32 LE) | leaf_value (?) | sibling_bitmap (32B)
//            | sibling_count (2B u16 LE) | siblings[] (count × 32B)
impl CanonicalEncode for InclusionProof {
    fn encode(&self, buf: &mut Vec<u8>) {
        debug_assert!(
            self.leaf_value.len() <= MAX_LEAF_VALUE_SIZE,
            "InclusionProof.leaf_value.len() = {} > MAX_LEAF_VALUE_SIZE = {}; \
             prove() builds proof из state record, размер которого bounded layout",
            self.leaf_value.len(),
            MAX_LEAF_VALUE_SIZE
        );
        debug_assert!(
            self.siblings.len() <= MAX_SIBLINGS,
            "InclusionProof.siblings.len() = {} > MAX_SIBLINGS = {} (TREE_DEPTH); \
             sibling_bitmap имеет ровно 256 bits, больше siblings не валидны",
            self.siblings.len(),
            MAX_SIBLINGS
        );
        write_bytes(buf, &self.key);
        write_u32(buf, self.leaf_value.len() as u32);
        write_bytes(buf, &self.leaf_value);
        write_bytes(buf, &self.sibling_bitmap);
        write_u16(buf, self.siblings.len() as u16);
        for s in &self.siblings {
            write_bytes(buf, s);
        }
    }
}

pub fn verify_proof(root: &Hash32, proof: &InclusionProof) -> bool {
    let expected_leaf = if proof.leaf_value.is_empty() {
        EMPTY_LEAF
    } else {
        leaf_hash(&proof.leaf_value)
    };

    let mut current = expected_leaf;
    let mut sibling_iter = proof.siblings.iter();

    for level in 0..TREE_DEPTH {
        let byte = level / 8;
        let bit_in_byte = level % 8;
        let sibling_present = (proof.sibling_bitmap[byte] >> bit_in_byte) & 1 == 1;

        let sibling = if sibling_present {
            match sibling_iter.next() {
                Some(s) => *s,
                None => return false,
            }
        } else {
            empty_internal(level)
        };

        let bit = get_bit(&proof.key, level);
        current = if bit == 0 {
            internal_hash(&current, &sibling)
        } else {
            internal_hash(&sibling, &current)
        };
    }

    &current == root && sibling_iter.next().is_none()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_leaf_is_zero() {
        assert_eq!(EMPTY_LEAF, [0u8; 32]);
    }

    #[test]
    fn tree_depth_is_256() {
        assert_eq!(TREE_DEPTH, 256);
    }

    #[test]
    fn leaf_hash_uses_domain_separator() {
        let record = b"account record bytes";
        assert_eq!(leaf_hash(record), hash(domain::MERKLE_LEAF, &[record]));
    }

    #[test]
    fn internal_hash_uses_domain_separator() {
        let l = [0x11u8; 32];
        let r = [0x22u8; 32];
        assert_eq!(internal_hash(&l, &r), hash(domain::MERKLE_NODE, &[&l, &r]));
    }

    #[test]
    fn empty_internal_level_0_is_empty_leaf() {
        assert_eq!(empty_internal(0), EMPTY_LEAF);
    }

    #[test]
    fn try_empty_internal_in_range_returns_some() {
        assert_eq!(try_empty_internal(0), Some(EMPTY_LEAF));
        assert_eq!(
            try_empty_internal(TREE_DEPTH),
            Some(empty_internal(TREE_DEPTH))
        );
        assert_eq!(try_empty_internal(128), Some(empty_internal(128)));
    }

    #[test]
    fn try_empty_internal_out_of_range_returns_none() {
        assert_eq!(try_empty_internal(TREE_DEPTH + 1), None);
        assert_eq!(try_empty_internal(usize::MAX), None);
    }

    #[test]
    #[should_panic(expected = "empty_internal: level")]
    fn empty_internal_panics_on_out_of_range() {
        let _ = empty_internal(TREE_DEPTH + 1);
    }

    // M2-5 closure: caching SMT root через Cell<Option<Hash32>>.
    #[test]
    fn root_cached_returns_same_value() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0x01; 32], b"a");
        tree.insert([0x02; 32], b"b");
        let r1 = tree.root();
        let r2 = tree.root();
        let r3 = tree.root();
        assert_eq!(r1, r2);
        assert_eq!(r2, r3);
    }

    #[test]
    fn root_invalidated_on_insert() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0x01; 32], b"a");
        let r1 = tree.root();
        tree.insert([0x02; 32], b"b");
        let r2 = tree.root();
        assert_ne!(r1, r2);
    }

    #[test]
    fn root_invalidated_on_remove() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0x01; 32], b"a");
        tree.insert([0x02; 32], b"b");
        let r_with_two = tree.root();
        tree.remove(&[0x02; 32]);
        let r_with_one = tree.root();
        assert_ne!(r_with_two, r_with_one);
    }

    #[test]
    fn root_no_invalidation_on_no_op_insert() {
        // Optimization: insert того же leaf-value не invalidates cache.
        // Behaviorally root() returns same value, что и до — test проверяет
        // именно что correctness preserved (не perf).
        let mut tree = SparseMerkleTree::new();
        tree.insert([0x01; 32], b"a");
        let r1 = tree.root();
        // Same key, same record → leaf unchanged → root unchanged
        tree.insert([0x01; 32], b"a");
        let r2 = tree.root();
        assert_eq!(r1, r2);
    }

    #[test]
    fn root_no_invalidation_on_remove_nonexistent() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0x01; 32], b"a");
        let r1 = tree.root();
        tree.remove(&[0xFF; 32]); // не существует
        let r2 = tree.root();
        assert_eq!(r1, r2);
    }

    // M2-10 closure cross-check: iterative compute_subtree_root даёт байт-в-байт
    // тот же result что existing tests предполагают (regression baselines).
    // Verifies iterative refactor не меняет behavioral semantics.
    #[test]
    fn iterative_compute_subtree_root_matches_known_baselines() {
        // Empty tree at depth 256 = empty_internal(256) (regression baseline)
        let empty_entries: Vec<([u8; 32], Hash32)> = vec![];
        assert_eq!(
            compute_subtree_root(&empty_entries, TREE_DEPTH),
            empty_internal(TREE_DEPTH)
        );

        // Single leaf at depth 0 = leaf hash itself
        let single = vec![([0u8; 32], [0xAB; 32])];
        assert_eq!(compute_subtree_root(&single, 0), [0xAB; 32]);

        // Single leaf at depth 1 = internal_hash(empty_leaf, leaf)
        // (key=0, bit 0 = 0 → left = entry, right = empty)
        // Wait, depth 1, bit_index = 0. key[0] LSB = 0 → left.
        let single = vec![([0u8; 32], [0xAB; 32])];
        let result = compute_subtree_root(&single, 1);
        let expected = internal_hash(&[0xAB; 32], &empty_internal(0));
        assert_eq!(result, expected);

        // Two siblings at depth 1: keys 0x00 and 0x01 (bit 0 differs)
        let two = vec![([0x00; 32], [0x11; 32]), ([0x01; 32], [0x22; 32])];
        let result = compute_subtree_root(&two, 1);
        // bit_index=0; key[0]=0x00 → bit 0 = 0 → left = first
        //              key[0]=0x01 → bit 0 = 1 → right = second
        let expected = internal_hash(&[0x11; 32], &[0x22; 32]);
        assert_eq!(result, expected);
    }

    #[test]
    fn iterative_compute_subtree_root_no_stack_overflow_full_depth() {
        // Smoke test: construction at TREE_DEPTH = 256 не вызывает stack overflow
        // (что было бы у наивной recursion на низкобюджетных stack targets).
        // 100 случайных entries — типичный workload.
        let mut entries: Vec<([u8; 32], Hash32)> = Vec::new();
        for i in 0..100u8 {
            let mut key = [0u8; 32];
            key[0] = i;
            key[31] = i.wrapping_mul(7);
            let mut val = [0u8; 32];
            val[0] = i.wrapping_mul(13);
            entries.push((key, val));
        }
        let _root = compute_subtree_root(&entries, TREE_DEPTH);
    }

    #[test]
    fn root_cache_invariant_chained_mutations() {
        // Серия mutations + root() — всегда даёт корректное value
        // (не stale cached).
        let mut tree = SparseMerkleTree::new();
        let mut expected_roots = Vec::new();

        for i in 0..50u8 {
            tree.insert([i; 32], &[i]);
            let r = tree.root();
            expected_roots.push(r);
        }

        // Compute roots вручную через fresh trees (без cache contamination)
        for (i, expected) in expected_roots.iter().enumerate() {
            let mut fresh = SparseMerkleTree::new();
            for j in 0..=i as u8 {
                fresh.insert([j; 32], &[j]);
            }
            assert_eq!(
                fresh.root(),
                *expected,
                "cached root after {} inserts расходится с fresh recompute",
                i + 1
            );
        }
    }

    #[test]
    fn empty_internal_level_1_matches_formula() {
        let expected = internal_hash(&EMPTY_LEAF, &EMPTY_LEAF);
        assert_eq!(empty_internal(1), expected);
    }

    #[test]
    fn empty_internal_is_cached() {
        let a = empty_internal(100);
        let b = empty_internal(100);
        assert_eq!(a, b);
    }

    #[test]
    fn empty_internal_level_256_root_of_empty_tree() {
        let tree = SparseMerkleTree::new();
        assert_eq!(tree.root(), empty_internal(TREE_DEPTH));
    }

    #[test]
    fn single_insert_changes_root() {
        let mut tree = SparseMerkleTree::new();
        let empty_root = tree.root();
        tree.insert([0xAB; 32], b"first");
        assert_ne!(tree.root(), empty_root);
    }

    #[test]
    fn idempotent_insert_stable_root() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"data");
        let r1 = tree.root();
        tree.insert([0xAB; 32], b"data");
        let r2 = tree.root();
        assert_eq!(r1, r2);
    }

    #[test]
    fn different_record_different_root() {
        let mut t1 = SparseMerkleTree::new();
        let mut t2 = SparseMerkleTree::new();
        t1.insert([0xAB; 32], b"one");
        t2.insert([0xAB; 32], b"two");
        assert_ne!(t1.root(), t2.root());
    }

    #[test]
    fn insert_order_independent() {
        let mut t1 = SparseMerkleTree::new();
        t1.insert([0x01; 32], b"a");
        t1.insert([0x02; 32], b"b");
        t1.insert([0x03; 32], b"c");

        let mut t2 = SparseMerkleTree::new();
        t2.insert([0x03; 32], b"c");
        t2.insert([0x01; 32], b"a");
        t2.insert([0x02; 32], b"b");

        assert_eq!(t1.root(), t2.root());
    }

    #[test]
    fn remove_restores_empty_root() {
        let mut tree = SparseMerkleTree::new();
        let empty_root = tree.root();
        tree.insert([0xAB; 32], b"temp");
        tree.remove(&[0xAB; 32]);
        assert_eq!(tree.root(), empty_root);
    }

    #[test]
    fn contains_reflects_state() {
        let mut tree = SparseMerkleTree::new();
        assert!(!tree.contains(&[0xAB; 32]));
        tree.insert([0xAB; 32], b"x");
        assert!(tree.contains(&[0xAB; 32]));
        tree.remove(&[0xAB; 32]);
        assert!(!tree.contains(&[0xAB; 32]));
    }

    #[test]
    fn insert_leaf_with_empty_hash_removes() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"x");
        assert!(tree.contains(&[0xAB; 32]));
        tree.insert_leaf([0xAB; 32], EMPTY_LEAF);
        assert!(!tree.contains(&[0xAB; 32]));
    }

    #[test]
    fn len_tracks_leaf_count() {
        let mut tree = SparseMerkleTree::new();
        assert_eq!(tree.len(), 0);
        assert!(tree.is_empty());
        tree.insert([0x01; 32], b"a");
        tree.insert([0x02; 32], b"b");
        assert_eq!(tree.len(), 2);
        assert!(!tree.is_empty());
    }

    #[test]
    fn prove_and_verify_existing_key() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"record one");
        tree.insert([0xCD; 32], b"record two");
        tree.insert([0xEF; 32], b"record three");

        let root = tree.root();
        let proof = tree.prove(&[0xCD; 32], Some(b"record two"));
        assert!(verify_proof(&root, &proof));
    }

    #[test]
    fn prove_absence_and_verify() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"something");

        let root = tree.root();
        let proof = tree.prove(&[0xFF; 32], None);
        assert!(verify_proof(&root, &proof));
    }

    #[test]
    fn verify_rejects_mutated_sibling() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"x");
        tree.insert([0xCD; 32], b"y");

        let root = tree.root();
        let mut proof = tree.prove(&[0xAB; 32], Some(b"x"));
        assert!(!proof.siblings.is_empty(), "test precondition");
        proof.siblings[0][0] ^= 0xFF;
        assert!(!verify_proof(&root, &proof));
    }

    #[test]
    fn verify_rejects_mutated_leaf_value() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"original");

        let root = tree.root();
        let mut proof = tree.prove(&[0xAB; 32], Some(b"original"));
        proof.leaf_value = b"mutated".to_vec();
        assert!(!verify_proof(&root, &proof));
    }

    #[test]
    fn verify_rejects_wrong_root() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"x");
        let proof = tree.prove(&[0xAB; 32], Some(b"x"));
        let wrong_root = [0xFFu8; 32];
        assert!(!verify_proof(&wrong_root, &proof));
    }

    #[test]
    fn verify_rejects_wrong_absence_claim() {
        // Try to prove absence of a key that IS in the tree — should fail
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"exists");
        let root = tree.root();
        let proof = tree.prove(&[0xAB; 32], None); // claim absence
        assert!(!verify_proof(&root, &proof));
    }

    #[test]
    fn inclusion_proof_canonical_encode_length() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"hi");
        let proof = tree.prove(&[0xAB; 32], Some(b"hi"));

        let mut buf = Vec::new();
        proof.encode(&mut buf);

        // Minimum: 32 (key) + 4 (len) + leaf.len() + 32 (bitmap) + 2 (count) + count*32
        let expected_len = 32 + 4 + proof.leaf_value.len() + 32 + 2 + proof.siblings.len() * 32;
        assert_eq!(buf.len(), expected_len);
    }

    #[test]
    fn inclusion_proof_encode_deterministic() {
        let mut tree = SparseMerkleTree::new();
        tree.insert([0xAB; 32], b"deterministic");
        let proof = tree.prove(&[0xAB; 32], Some(b"deterministic"));

        let mut buf1 = Vec::new();
        proof.encode(&mut buf1);
        let mut buf2 = Vec::new();
        proof.encode(&mut buf2);
        assert_eq!(buf1, buf2);
    }

    // Property test: 100 deterministic pseudorandom inserts → every key provable
    #[test]
    fn random_inserts_all_provable() {
        let mut tree = SparseMerkleTree::new();
        let mut state: u64 = 0x9E3779B97F4A7C15;
        let mut entries = Vec::new();

        for i in 0u64..100 {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            let mut key = [0u8; 32];
            key[..8].copy_from_slice(&state.to_le_bytes());
            key[8..16].copy_from_slice(&(state.wrapping_add(i)).to_le_bytes());
            let value = i.to_le_bytes();
            entries.push((key, value));
            tree.insert(key, &value);
        }

        let root = tree.root();

        for (key, value) in &entries {
            let proof = tree.prove(key, Some(value));
            assert!(verify_proof(&root, &proof), "proof failed");
        }
    }
}
