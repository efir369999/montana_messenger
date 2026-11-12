// The two Merkle constructions of Montana, under the family a table no circuit walks folds in.
// The set states them in `docs/Montana Canon.md`, "The Merkle constructions": a sparse tree keyed
// by a value holds sets and an append-only tree indexed by position holds a growing sequence. Each
// use names its own leaf and node domains, and the frozen empty values and roots are asserted by
// the conformance harness, parsed out of the set.
//
// The uses a circuit walks — the tree of notes, the tree of admitted machines, the tree of records
// and the fabric of time — fold under the proof hash and live in `mt-proof`, since the doors of
// that family live there. The shape of the walk is the same and is written twice for that reason
// alone: a crate of the state cannot reach the family of proofs without a cycle.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

use mt_codec::encode::{take, CanonicalDecode, CanonicalEncode, DecodeError};
use mt_codec::{hash, hash_of_one, Domain, Part};
use std::collections::BTreeMap;

mt_codec::constants! {
    DEPTHS:
    /// The sparse tree is keyed by 32 bytes, so its depth is the bits of a key.
    pub const KEY_BITS: usize = 256, writes "The tree is sparse with a depth of 256";
}

#[derive(Debug, PartialEq, Eq)]
pub enum VerifyError {
    PositionBeyondDepth,
    SiblingCountMismatch,
    LeafBeyondLength,
    RootMismatch,
}

#[derive(Debug, PartialEq, Eq)]
pub struct TreeFull;

#[derive(Debug, PartialEq, Eq)]
pub struct EmptyRecord;

// Level 0 holds the empty leaf, which is the leaf domain of the construction applied to no bytes;
// level k+1 folds two empties of level k under the node domain. Each construction computes its own
// array once and keeps it.
//
// The empty leaf takes that shape rather than thirty-two zeros so that what a root says about
// absence stands on the form and not on the function: a leaf of this construction is its domain
// over a body of at least one byte, and no such preimage is the preimage of no bytes at all. Under
// zeros the same property rested on no leaf hashing to zero — a property of SHA-256, which an ideal
// oracle does not repair and a successor function need not carry.
pub fn empty_internals(leaf_domain: Domain, node_domain: Domain, levels: usize) -> Vec<[u8; 32]> {
    let mut out = Vec::with_capacity(levels + 1);
    out.push(hash_of_one(leaf_domain, &[]));
    for k in 0..levels {
        let e = out[k];
        out.push(hash(node_domain, &[Part::of(&e), Part::of(&e)]));
    }
    out
}

// Bit L of a 32-byte value is bit L & 7 of byte L >> 3, least significant first — one
// convention for the key of the sparse tree, the bitmap of a proof, and the walk.
fn bit_at(value: &[u8; 32], level: usize) -> bool {
    (value[level >> 3] >> (level & 7)) & 1 == 1
}

fn fold(node_domain: Domain, left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    hash(node_domain, &[Part::of(left), Part::of(right)])
}

fn popcount(bitmap: &[u8; 32]) -> usize {
    bitmap.iter().map(|b| b.count_ones() as usize).sum()
}

// Folds one level upward: pairs fold left with right, an odd tail folds with the empty of
// this level.
fn next_level(node_domain: Domain, empty: &[u8; 32], level: &[[u8; 32]]) -> Vec<[u8; 32]> {
    let mut out = Vec::with_capacity(level.len().div_ceil(2));
    for pair in level.chunks(2) {
        let right = pair.get(1).unwrap_or(empty);
        out.push(fold(node_domain, &pair[0], right));
    }
    out
}

fn fold_filled(
    node_domain: Domain,
    depth: usize,
    empties: &[[u8; 32]],
    level0: Vec<[u8; 32]>,
) -> [u8; 32] {
    let mut level = level0;
    for empty in empties.iter().take(depth) {
        if level.is_empty() {
            break;
        }
        level = next_level(node_domain, empty, &level);
    }
    level.first().copied().unwrap_or(empties[depth])
}

// The sparse tree, keyed by a value: depth 256, bits of the key read from the least
// significant, a bit of 0 to the left. One record per key; writing a key that exists
// replaces its record.
pub struct SparseTree {
    leaf_domain: Domain,
    node_domain: Domain,
    empties: Vec<[u8; 32]>,
    entries: BTreeMap<[u8; 32], Vec<u8>>,
}

impl SparseTree {
    pub fn new(leaf_domain: Domain, node_domain: Domain) -> Self {
        Self {
            leaf_domain,
            node_domain,
            empties: empty_internals(leaf_domain, node_domain, KEY_BITS),
            entries: BTreeMap::new(),
        }
    }

    // The set: `serialize(record)` is at least one byte and a zero leaf_length denotes
    // absence alone, so an empty record is refused rather than held unprovably.
    pub fn insert(&mut self, key: [u8; 32], record: Vec<u8>) -> Result<(), EmptyRecord> {
        if record.is_empty() {
            return Err(EmptyRecord);
        }
        self.entries.insert(key, record);
        Ok(())
    }

    pub fn get(&self, key: &[u8; 32]) -> Option<&[u8]> {
        self.entries.get(key).map(Vec::as_slice)
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn root(&self) -> [u8; 32] {
        self.node(KEY_BITS, &self.leaves())
    }

    fn leaves(&self) -> Vec<([u8; 32], [u8; 32])> {
        self.entries
            .iter()
            .map(|(k, v)| (*k, hash_of_one(self.leaf_domain, v.as_slice())))
            .collect()
    }

    // The node at `height` over the entries below it: a subtree with no entries is the empty
    // internal of its level, and a subtree of height zero is one leaf — keys are unique, so
    // no two entries reach the same position.
    fn node(&self, height: usize, below: &[([u8; 32], [u8; 32])]) -> [u8; 32] {
        if below.is_empty() {
            return self.empties[height];
        }
        if height == 0 {
            return below[0].1;
        }
        let split = height - 1;
        let (left, right): (Vec<_>, Vec<_>) = below
            .iter()
            .copied()
            .partition(|(key, _)| !bit_at(key, split));
        fold(
            self.node_domain,
            &self.node(split, &left),
            &self.node(split, &right),
        )
    }

    pub fn prove(&self, key: &[u8; 32]) -> MerkleProof {
        let mut bitmap = [0u8; 32];
        let mut siblings = Vec::new();
        let mut path = self.leaves();
        for level in (0..KEY_BITS).rev() {
            let (zeros, ones): (Vec<_>, Vec<_>) = path
                .into_iter()
                .partition(|(entry_key, _)| !bit_at(entry_key, level));
            let (next, sibling) = if bit_at(key, level) {
                (ones, zeros)
            } else {
                (zeros, ones)
            };
            if !sibling.is_empty() {
                bitmap[level >> 3] |= 1u8 << (level & 7);
                siblings.push(self.node(level, &sibling));
            }
            path = next;
        }
        siblings.reverse();
        MerkleProof {
            key: *key,
            leaf_value: self.entries.get(key).cloned().unwrap_or_default(),
            sibling_bitmap: bitmap,
            siblings,
        }
    }
}

// MerkleProof, by the layout of the set: key, leaf_length and leaf_value, the sibling
// bitmap, the sibling count, then the non-empty siblings ascending by level. A proof
// carries no root.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MerkleProof {
    key: [u8; 32],
    // Empty exactly when the proof asserts absence.
    leaf_value: Vec<u8>,
    sibling_bitmap: [u8; 32],
    siblings: Vec<[u8; 32]>,
}

impl MerkleProof {
    // The one door for a proof built outside this crate: the count of siblings must match
    // the bitmap and the record must fit its length field, so no reachable value of the
    // type disagrees with its own encoding.
    pub fn try_new(
        key: [u8; 32],
        leaf_value: Vec<u8>,
        sibling_bitmap: [u8; 32],
        siblings: Vec<[u8; 32]>,
    ) -> Result<Self, VerifyError> {
        if siblings.len() != popcount(&sibling_bitmap) {
            return Err(VerifyError::SiblingCountMismatch);
        }
        if leaf_value.len() > u32::MAX as usize {
            return Err(VerifyError::LeafBeyondLength);
        }
        Ok(Self {
            key,
            leaf_value,
            sibling_bitmap,
            siblings,
        })
    }

    pub fn key(&self) -> &[u8; 32] {
        &self.key
    }

    pub fn leaf_value(&self) -> &[u8] {
        &self.leaf_value
    }

    pub fn sibling_bitmap(&self) -> &[u8; 32] {
        &self.sibling_bitmap
    }

    pub fn siblings(&self) -> &[[u8; 32]] {
        &self.siblings
    }
}

impl CanonicalEncode for MerkleProof {
    fn encode_into(&self, out: &mut Vec<u8>) {
        // PANIC-OK: the siblings are one per set bit of the bitmap, so their count is at most
        // 256, and a record beyond a u32 length cannot be built: the one door of a proof built
        // outside this crate compares both, and a proof read off the wire is refused before its
        // elements are read. A value reaching these is a defect of this tree rather than an input
        // a stranger can send.
        assert!(self.siblings.len() == popcount(&self.sibling_bitmap));
        assert!(self.leaf_value.len() <= u32::MAX as usize);
        self.key.encode_into(out);
        (self.leaf_value.len() as u32).encode_into(out);
        out.extend_from_slice(&self.leaf_value);
        self.sibling_bitmap.encode_into(out);
        // The layout names the count field, sized u16 by the table of the set.
        (self.siblings.len() as u16).encode_into(out);
        for sibling in &self.siblings {
            sibling.encode_into(out);
        }
    }
}

impl CanonicalDecode for MerkleProof {
    fn decode_from(input: &mut &[u8]) -> Result<Self, DecodeError> {
        let key = <[u8; 32]>::decode_from(input)?;
        let leaf_length = u32::decode_from(input)? as usize;
        let leaf_value = take(input, leaf_length)?.to_vec();
        let sibling_bitmap = <[u8; 32]>::decode_from(input)?;
        let declared = usize::from(u16::decode_from(input)?);
        let implied = popcount(&sibling_bitmap);
        if declared != implied {
            return Err(DecodeError::CountMismatch { declared, implied });
        }
        let mut siblings = Vec::with_capacity(declared);
        for _ in 0..declared {
            siblings.push(<[u8; 32]>::decode_from(input)?);
        }
        Ok(Self {
            key,
            leaf_value,
            sibling_bitmap,
            siblings,
        })
    }
}

impl MerkleProof {
    // Recomputes the root from the leaf upward and compares it with a root already held; the
    // proof is never trusted for a root, because it carries none.
    pub fn verify(
        &self,
        leaf_domain: Domain,
        node_domain: Domain,
        root: &[u8; 32],
    ) -> Result<(), VerifyError> {
        if self.siblings.len() != popcount(&self.sibling_bitmap) {
            return Err(VerifyError::SiblingCountMismatch);
        }
        let empties = empty_internals(leaf_domain, node_domain, KEY_BITS);
        // No branch for absence: a leaf value of no bytes is the empty leaf by the same formula
        // every present leaf takes, so the walk asks nothing about which case it is in.
        let mut current = hash_of_one(leaf_domain, self.leaf_value.as_slice());
        let mut used = 0;
        for (level, empty) in empties.iter().take(KEY_BITS).enumerate() {
            let sibling = if bit_at(&self.sibling_bitmap, level) {
                let s = self
                    .siblings
                    .get(used)
                    .copied()
                    .ok_or(VerifyError::SiblingCountMismatch)?;
                used += 1;
                s
            } else {
                *empty
            };
            current = if bit_at(&self.key, level) {
                fold(node_domain, &sibling, &current)
            } else {
                fold(node_domain, &current, &sibling)
            };
        }
        if current == *root {
            Ok(())
        } else {
            Err(VerifyError::RootMismatch)
        }
    }
}

// The append-only tree, indexed by position: leaves fill from position zero and a leaf once
// written never moves. What enters the fold at level zero is the commitment under the leaf
// domain; the walk reads the bits of the position from the least significant, zero to the
// left — the same convention as the sparse tree.
pub struct AppendTree {
    leaf_domain: Domain,
    node_domain: Domain,
    depth: usize,
    empties: Vec<[u8; 32]>,
    commitments: Vec<[u8; 32]>,
}

impl AppendTree {
    pub fn new(leaf_domain: Domain, node_domain: Domain, depth: usize) -> Self {
        Self {
            leaf_domain,
            node_domain,
            depth,
            empties: empty_internals(leaf_domain, node_domain, depth),
            commitments: Vec::new(),
        }
    }

    pub fn push(&mut self, commitment: [u8; 32]) -> Result<u64, TreeFull> {
        if self.depth < 64 && self.commitments.len() as u64 >= 1u64 << self.depth {
            return Err(TreeFull);
        }
        self.commitments.push(commitment);
        Ok(self.commitments.len() as u64 - 1)
    }

    pub fn len(&self) -> u64 {
        self.commitments.len() as u64
    }

    pub fn is_empty(&self) -> bool {
        self.commitments.is_empty()
    }

    fn level0(&self) -> Vec<[u8; 32]> {
        self.commitments
            .iter()
            .map(|c| hash_of_one(self.leaf_domain, c))
            .collect()
    }

    pub fn root(&self) -> [u8; 32] {
        fold_filled(self.node_domain, self.depth, &self.empties, self.level0())
    }

    pub fn prove(&self, position: u64) -> Option<AppendProof> {
        let index = usize::try_from(position).ok()?;
        let commitment = *self.commitments.get(index)?;
        let mut siblings = Vec::with_capacity(self.depth);
        let mut level = self.level0();
        let mut idx = index;
        for empty in self.empties.iter().take(self.depth) {
            siblings.push(level.get(idx ^ 1).copied().unwrap_or(*empty));
            level = next_level(self.node_domain, empty, &level);
            idx >>= 1;
        }
        Some(AppendProof {
            position,
            leaf_value: commitment,
            siblings,
        })
    }
}

// AppendProof, by the layout of the set: position, the commitment at it, then exactly depth
// siblings ascending by level — no bitmap and no count, because an append-only path has no
// absent levels.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppendProof {
    position: u64,
    leaf_value: [u8; 32],
    siblings: Vec<[u8; 32]>,
}

impl AppendProof {
    // The count of siblings is judged against a depth only verify knows, so construction
    // holds no invariant of its own.
    pub fn new(position: u64, leaf_value: [u8; 32], siblings: Vec<[u8; 32]>) -> Self {
        Self {
            position,
            leaf_value,
            siblings,
        }
    }

    pub fn position(&self) -> u64 {
        self.position
    }

    pub fn leaf_value(&self) -> &[u8; 32] {
        &self.leaf_value
    }

    pub fn siblings(&self) -> &[[u8; 32]] {
        &self.siblings
    }
}

impl AppendProof {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(8 + 32 + 32 * self.siblings.len());
        self.position.encode_into(&mut out);
        self.leaf_value.encode_into(&mut out);
        for sibling in &self.siblings {
            sibling.encode_into(&mut out);
        }
        out
    }

    // The count of siblings is the depth of the construction, known from the Decree rather
    // than from the wire; an input of any other length is refused before it is parsed.
    pub fn decode_exact(bytes: &[u8], depth: usize) -> Result<Self, DecodeError> {
        let expected = 8 + 32 + 32 * depth;
        if bytes.len() < expected {
            return Err(DecodeError::UnexpectedEnd {
                needed: expected,
                remaining: bytes.len(),
            });
        }
        if bytes.len() > expected {
            return Err(DecodeError::TrailingBytes {
                remaining: bytes.len() - expected,
            });
        }
        let mut input = bytes;
        let position = u64::decode_from(&mut input)?;
        let leaf_value = <[u8; 32]>::decode_from(&mut input)?;
        let mut siblings = Vec::with_capacity(depth);
        for _ in 0..depth {
            siblings.push(<[u8; 32]>::decode_from(&mut input)?);
        }
        Ok(Self {
            position,
            leaf_value,
            siblings,
        })
    }

    // Recomputes the root and compares it with a root already held; the root a proof would
    // carry is never trusted, and here it is never carried.
    pub fn verify(
        &self,
        leaf_domain: Domain,
        node_domain: Domain,
        depth: usize,
        root: &[u8; 32],
    ) -> Result<(), VerifyError> {
        if self.siblings.len() != depth {
            return Err(VerifyError::SiblingCountMismatch);
        }
        if depth < 64 && self.position >> depth != 0 {
            return Err(VerifyError::PositionBeyondDepth);
        }
        let mut current = hash_of_one(leaf_domain, &self.leaf_value);
        let mut position = self.position;
        for sibling in &self.siblings {
            current = if position & 1 == 1 {
                fold(node_domain, sibling, &current)
            } else {
                fold(node_domain, &current, sibling)
            };
            position >>= 1;
        }
        if current == *root {
            Ok(())
        } else {
            Err(VerifyError::RootMismatch)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_codec::domain::{MT_MERKLE_LEAF, MT_MERKLE_NODE};

    // xorshift64*, seeded once: the same run on every machine.
    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            let mut x = self.0;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            self.0 = x;
            x.wrapping_mul(0x2545_F491_4F6C_DD1D)
        }

        fn bytes32(&mut self) -> [u8; 32] {
            let mut out = [0u8; 32];
            for byte in out.iter_mut() {
                *byte = self.next() as u8;
            }
            out
        }
    }

    fn sample_tree(n: usize) -> (SparseTree, Vec<[u8; 32]>) {
        let mut rng = Rng(0x4D54_2D4D_4552_4B31);
        let mut tree = SparseTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE);
        let mut keys = Vec::new();
        for i in 0..n {
            let key = rng.bytes32();
            tree.insert(key, format!("record {i}").into_bytes())
                .expect("a record is admitted");
            keys.push(key);
        }
        (tree, keys)
    }

    #[test]
    fn an_empty_sparse_tree_stands_at_the_empty_internal_of_its_top() {
        let tree = SparseTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE);
        let empties = empty_internals(MT_MERKLE_LEAF, MT_MERKLE_NODE, KEY_BITS);
        assert_eq!(tree.root(), empties[KEY_BITS]);
    }

    #[test]
    fn the_sparse_root_does_not_depend_on_insertion_order() {
        let (tree, keys) = sample_tree(8);
        let mut reversed = SparseTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE);
        for (i, key) in keys.iter().enumerate().rev() {
            reversed
                .insert(*key, format!("record {i}").into_bytes())
                .expect("a record is admitted");
        }
        assert_eq!(tree.root(), reversed.root());
    }

    #[test]
    fn a_present_key_proves_and_verifies() {
        let (tree, keys) = sample_tree(8);
        let root = tree.root();
        for (i, key) in keys.iter().enumerate() {
            let proof = tree.prove(key);
            assert_eq!(proof.leaf_value, format!("record {i}").into_bytes());
            proof
                .verify(MT_MERKLE_LEAF, MT_MERKLE_NODE, &root)
                .expect("a present key verifies");
        }
    }

    #[test]
    fn an_absent_key_proves_absence() {
        let (tree, _) = sample_tree(8);
        let root = tree.root();
        let absent = [0x5Au8; 32];
        let proof = tree.prove(&absent);
        assert!(proof.leaf_value.is_empty());
        proof
            .verify(MT_MERKLE_LEAF, MT_MERKLE_NODE, &root)
            .expect("absence verifies");
    }

    #[test]
    fn a_doctored_sibling_fails_the_root() {
        let (tree, keys) = sample_tree(8);
        let root = tree.root();
        let mut proof = tree.prove(&keys[0]);
        proof.siblings[0][0] ^= 1;
        assert_eq!(
            proof.verify(MT_MERKLE_LEAF, MT_MERKLE_NODE, &root),
            Err(VerifyError::RootMismatch)
        );
    }

    #[test]
    fn a_proof_against_a_moved_root_fails() {
        let (mut tree, keys) = sample_tree(8);
        let proof = tree.prove(&keys[0]);
        tree.insert([0x77u8; 32], b"a record the proof predates".to_vec())
            .expect("a record is admitted");
        assert_eq!(
            proof.verify(MT_MERKLE_LEAF, MT_MERKLE_NODE, &tree.root()),
            Err(VerifyError::RootMismatch)
        );
    }

    #[test]
    fn a_count_that_disagrees_with_the_bitmap_is_refused_at_decode() {
        let (tree, keys) = sample_tree(4);
        let proof = tree.prove(&keys[0]);
        let mut bytes = proof.encode();
        // The count field sits after key, leaf_length, leaf_value and the bitmap.
        let count_at = 32 + 4 + proof.leaf_value.len() + 32;
        bytes[count_at] = bytes[count_at].wrapping_add(1);
        match MerkleProof::decode_exact(&bytes) {
            Err(DecodeError::CountMismatch { .. }) => {}
            other => panic!("expected a count mismatch, got {other:?}"),
        }
    }

    #[test]
    fn a_popped_sibling_is_refused_at_verify() {
        let (tree, keys) = sample_tree(4);
        let root = tree.root();
        let mut proof = tree.prove(&keys[0]);
        proof.siblings.pop();
        assert_eq!(
            proof.verify(MT_MERKLE_LEAF, MT_MERKLE_NODE, &root),
            Err(VerifyError::SiblingCountMismatch)
        );
    }

    #[test]
    fn the_sparse_proof_round_trips_both_ways() {
        let (tree, keys) = sample_tree(8);
        for key in keys.iter().chain([[0x5Au8; 32]].iter()) {
            let proof = tree.prove(key);
            let bytes = proof.encode();
            let back = MerkleProof::decode_exact(&bytes).expect("the proof decodes");
            assert_eq!(back, proof);
            assert_eq!(back.encode(), bytes);
        }
    }

    #[test]
    fn an_empty_append_tree_stands_at_the_empty_internal_of_its_depth() {
        let depth = 8;
        let tree = AppendTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth);
        let empties = empty_internals(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth);
        assert_eq!(tree.root(), empties[depth]);
    }

    #[test]
    fn pushed_commitments_prove_and_verify() {
        let depth = 8;
        let mut rng = Rng(0x4D54_2D4D_4552_4B32);
        let mut tree = AppendTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth);
        let mut commitments = Vec::new();
        for _ in 0..5 {
            let c = rng.bytes32();
            tree.push(c).expect("the tree admits it");
            commitments.push(c);
        }
        let root = tree.root();
        for (i, c) in commitments.iter().enumerate() {
            let proof = tree.prove(i as u64).expect("a written position proves");
            assert_eq!(proof.leaf_value, *c);
            proof
                .verify(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth, &root)
                .expect("a written position verifies");
        }
        assert!(tree.prove(5).is_none());
    }

    #[test]
    fn the_append_walk_places_odd_positions_on_the_right() {
        let depth = 2;
        let mut tree = AppendTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth);
        let a = [0xA1u8; 32];
        let b = [0xB2u8; 32];
        tree.push(a).expect("admitted");
        tree.push(b).expect("admitted");
        let empties = empty_internals(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth);
        let left = fold(
            MT_MERKLE_NODE,
            &hash_of_one(MT_MERKLE_LEAF, &a),
            &hash_of_one(MT_MERKLE_LEAF, &b),
        );
        assert_eq!(tree.root(), fold(MT_MERKLE_NODE, &left, &empties[1]));
    }

    #[test]
    fn a_full_append_tree_refuses_the_next_leaf() {
        let depth = 2;
        let mut tree = AppendTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth);
        for i in 0..4u8 {
            tree.push([i; 32]).expect("the tree admits four");
        }
        assert_eq!(tree.push([9u8; 32]), Err(TreeFull));
    }

    #[test]
    fn a_position_beyond_the_depth_is_refused() {
        let depth = 4;
        let proof = AppendProof::new(1 << depth, [1u8; 32], vec![[0u8; 32]; depth]);
        assert_eq!(
            proof.verify(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth, &[0u8; 32]),
            Err(VerifyError::PositionBeyondDepth)
        );
    }

    #[test]
    fn an_append_proof_of_the_wrong_length_is_refused_before_parse() {
        let depth = 4;
        let mut tree = AppendTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE, depth);
        tree.push([3u8; 32]).expect("admitted");
        let bytes = tree.prove(0).expect("proves").encode();
        assert!(matches!(
            AppendProof::decode_exact(&bytes[..bytes.len() - 1], depth),
            Err(DecodeError::UnexpectedEnd { .. })
        ));
        let mut long = bytes.clone();
        long.push(0);
        assert!(matches!(
            AppendProof::decode_exact(&long, depth),
            Err(DecodeError::TrailingBytes { .. })
        ));
        let back = AppendProof::decode_exact(&bytes, depth).expect("the proof decodes");
        assert_eq!(back.encode(), bytes);
    }

    #[test]
    fn an_empty_record_is_refused_rather_than_held_unprovably() {
        let mut tree = SparseTree::new(MT_MERKLE_LEAF, MT_MERKLE_NODE);
        assert_eq!(tree.insert([0x07u8; 32], Vec::new()), Err(EmptyRecord));
        assert!(tree.is_empty());
    }

    #[test]
    fn the_one_door_of_a_proof_refuses_a_count_that_disagrees() {
        assert_eq!(
            MerkleProof::try_new([0u8; 32], b"record".to_vec(), [0u8; 32], vec![[1u8; 32]]),
            Err(VerifyError::SiblingCountMismatch)
        );
        let mut bitmap = [0u8; 32];
        bitmap[0] = 1;
        let proof = MerkleProof::try_new([0u8; 32], Vec::new(), bitmap, vec![[1u8; 32]])
            .expect("a matching count passes the door");
        assert_eq!(proof.siblings().len(), 1);
    }

    #[test]
    fn the_decoders_survive_a_storm_of_doctored_bytes() {
        let mut rng = Rng(0x4D54_2D4D_4552_4B33);
        let (tree, keys) = sample_tree(4);
        let valid = tree.prove(&keys[0]).encode();
        for cut in 0..valid.len() {
            assert!(MerkleProof::decode_exact(&valid[..cut]).is_err());
        }
        for i in 0..valid.len() {
            let mut doctored = valid.clone();
            doctored[i] ^= 1;
            if let Ok(proof) = MerkleProof::decode_exact(&doctored) {
                assert_eq!(proof.encode(), doctored);
            }
        }
        for _ in 0..2000 {
            let len = (rng.next() % 400) as usize;
            let bytes: Vec<u8> = (0..len).map(|_| rng.next() as u8).collect();
            if let Ok(proof) = MerkleProof::decode_exact(&bytes) {
                assert_eq!(proof.encode(), bytes);
            }
            if let Ok(proof) = AppendProof::decode_exact(&bytes, 8) {
                assert_eq!(proof.encode(), bytes);
            }
        }
    }
}
