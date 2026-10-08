// The tree of records: sparse, keyed by a value, of the proof hash family. A candidacy proves its
// continuity out of the record that holds it, so a circuit walks this tree — and a walk of a tree
// sparse at the width of a key costs, under SHA-256, several times the whole height the memory of a
// commodity device admits, while under this family it is a fraction of it.
//
// **This is the one place the boundary of the set answers twice**, and the set names the price
// rather than hiding it: a machine of the network also recomputes this root from state with no
// proof in hand, which is the case the boundary sends to SHA-256. The walk decides, because the
// recomputation is carriage and carriage is not judgement — so the membership of a record stands
// on a function younger than SHA-256, and that sentence is written in the set as well as here.

use crate::poseidon::{self, Digest};
use mt_codec::domain;
use std::collections::BTreeMap;

// The key is 32 bytes and its bits are read from the least significant: bit L is bit L & 7 of byte
// L >> 3. One convention carries the key, the bitmap of a proof and the walk — the same one the
// construction under SHA-256 takes, since only the family differs.
fn bit_at(key: &[u8; 32], level: usize) -> bool {
    (key[level >> 3] >> (level & 7)) & 1 == 1
}

pub fn leaf(record: &[u8]) -> Digest {
    poseidon::hash_bytes(domain::MT_RECORD_LEAF, record)
}

pub fn empty_leaf() -> Digest {
    poseidon::hash_elements(domain::MT_RECORD_LEAF, &[])
}

pub fn node(left: &Digest, right: &Digest) -> Digest {
    poseidon::node(domain::MT_RECORD_NODE, left, right)
}

pub fn empty_internals(depth: usize) -> Vec<Digest> {
    let mut out = Vec::with_capacity(depth + 1);
    out.push(empty_leaf());
    for level in 0..depth {
        let below = out[level];
        out.push(node(&below, &below));
    }
    out
}

pub fn key_bits() -> usize {
    mt_merkle::KEY_BITS
}

pub fn empty_root() -> Digest {
    let depth = key_bits();
    empty_internals(depth)[depth]
}

// The root over the records held, walked one key at a time from the leaf upward. A tree of one
// record folds that record with the empty of every level, so the walk is what the frozen root over
// one record pins: an implementation reading the key from the wrong end, taking the wrong bit of a
// byte, or folding left where right is meant reproduces none of it.
pub fn root_of(records: &BTreeMap<[u8; 32], Vec<u8>>) -> Digest {
    root_of_leaves(
        &records
            .iter()
            .map(|(key, record)| (*key, leaf(record)))
            .collect(),
    )
}

// The same walk over the leaves themselves. A machine holds these and never the records they fold:
// a record of a person is never published, so what reaches the network is the commitment, and a
// machine that demanded the preimage would be demanding what the plane exists to withhold.
pub fn root_of_leaves(leaves: &BTreeMap<[u8; 32], Digest>) -> Digest {
    let depth = key_bits();
    let empties = empty_internals(depth);
    if leaves.is_empty() {
        return empties[depth];
    }
    let mut level: Vec<([u8; 32], Digest)> = leaves.iter().map(|(key, l)| (*key, *l)).collect();
    for (height, empty) in empties.iter().enumerate().take(depth) {
        let mut above: Vec<([u8; 32], Digest)> = Vec::with_capacity(level.len());
        let mut at = 0;
        while at < level.len() {
            let (key, value) = level[at];
            let pairs = at + 1 < level.len() && {
                let (next, _) = level[at + 1];
                same_prefix_above(&key, &next, height)
            };
            let folded = if pairs {
                let (_, sibling) = level[at + 1];
                at += 2;
                if bit_at(&key, height) {
                    node(&sibling, &value)
                } else {
                    node(&value, &sibling)
                }
            } else {
                at += 1;
                if bit_at(&key, height) {
                    node(empty, &value)
                } else {
                    node(&value, empty)
                }
            };
            above.push((key, folded));
        }
        level = above;
    }
    level
        .first()
        .map(|(_, root)| *root)
        .unwrap_or_else(|| empties[depth])
}

// Two keys share a parent at the level above `height` when every bit strictly above it agrees.
fn same_prefix_above(left: &[u8; 32], right: &[u8; 32], height: usize) -> bool {
    ((height + 1)..key_bits()).all(|level| bit_at(left, level) == bit_at(right, level))
}

// The siblings a walk of this tree meets from the leaf upward at one key, and nothing where the key
// holds no record. It is the same walk the root is folded by — a second walk written elsewhere
// would agree with this one only until one of them was edited — and it is what a proof about a
// record is witnessed with.
pub fn path_of(records: &BTreeMap<[u8; 32], Vec<u8>>, key: &[u8; 32]) -> Option<Vec<Digest>> {
    path_of_leaves(
        &records
            .iter()
            .map(|(k, record)| (*k, leaf(record)))
            .collect(),
        key,
    )
}

pub fn path_of_leaves(leaves: &BTreeMap<[u8; 32], Digest>, key: &[u8; 32]) -> Option<Vec<Digest>> {
    if !leaves.contains_key(key) {
        return None;
    }
    let depth = key_bits();
    let empties = empty_internals(depth);
    let mut out = Vec::with_capacity(depth);
    // At every level the sibling is the root over the records whose key agrees with this one above
    // that level and differs at it. Folding that subtree through the same door keeps one walk.
    for height in 0..depth {
        let mut of_the_sibling: BTreeMap<[u8; 32], Digest> = BTreeMap::new();
        for (other, held) in leaves.iter() {
            if other == key {
                continue;
            }
            if same_prefix_above(key, other, height) && bit_at(other, height) != bit_at(key, height)
            {
                of_the_sibling.insert(*other, *held);
            }
        }
        if of_the_sibling.is_empty() {
            out.push(empties[height]);
            continue;
        }
        // The subtree of the sibling stands `height` levels tall, and its root is the fold of what
        // it holds against the empties below it.
        let mut level: Vec<([u8; 32], Digest)> =
            of_the_sibling.iter().map(|(k, held)| (*k, *held)).collect();
        for (at, empty) in empties.iter().enumerate().take(height) {
            let mut above: Vec<([u8; 32], Digest)> = Vec::with_capacity(level.len());
            let mut which = 0;
            while which < level.len() {
                let (k, value) = level[which];
                let pairs = which + 1 < level.len() && {
                    let (next, _) = level[which + 1];
                    same_prefix_above(&k, &next, at)
                };
                let folded = if pairs {
                    let (_, sibling) = level[which + 1];
                    which += 2;
                    if bit_at(&k, at) {
                        node(&sibling, &value)
                    } else {
                        node(&value, &sibling)
                    }
                } else {
                    which += 1;
                    if bit_at(&k, at) {
                        node(empty, &value)
                    } else {
                        node(&value, empty)
                    }
                };
                above.push((k, folded));
            }
            level = above;
        }
        out.push(level[0].1);
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree(entries: &[([u8; 32], Vec<u8>)]) -> BTreeMap<[u8; 32], Vec<u8>> {
        entries.iter().cloned().collect()
    }

    #[test]
    fn the_empty_root_is_the_top_of_this_family_and_not_of_another() {
        assert_ne!(empty_root().bytes(), crate::admitted::empty_root().bytes());
        assert_ne!(empty_leaf(), crate::notes::empty_leaf());
    }

    #[test]
    fn a_record_of_no_bytes_is_the_empty_leaf_and_that_is_what_absence_stands_on() {
        assert_eq!(leaf(&[]), empty_leaf());
        assert_ne!(leaf(&[0u8]), empty_leaf());
    }

    #[test]
    fn the_walk_reads_the_key_from_the_least_significant_end() {
        let mut low = [0u8; 32];
        low[0] = 1;
        let mut high = [0u8; 32];
        high[31] = 0x80;
        let record = vec![0xAAu8; 8];
        assert_ne!(
            root_of(&tree(&[(low, record.clone())])),
            root_of(&tree(&[(high, record)]))
        );
    }

    #[test]
    fn two_records_fold_together_and_not_each_with_an_empty() {
        let mut first = [0u8; 32];
        first[0] = 0b10;
        let mut second = [0u8; 32];
        second[0] = 0b11;
        let both = root_of(&tree(&[(first, vec![1u8]), (second, vec![2u8])]));
        let alone = root_of(&tree(&[(first, vec![1u8])]));
        assert_ne!(both, alone);
        assert_ne!(
            both,
            root_of(&tree(&[(first, vec![2u8]), (second, vec![1u8])]))
        );
    }
}
