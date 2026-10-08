// The fabric of time: append-only by position, of the proof hash family. A leaf of it is the
// blinded observation of a record commitment in a window, and its path exists only as the witness
// of a proof — one judge, so one family, by the boundary the set draws.
//
// It lived among the two constructions of the state while it folded under SHA-256. The move is not
// a tidying: a walk of a tree this deep under SHA-256 is tens of thousands of rows per level and
// exceeds the whole height a commodity device admits, so a circuit could not walk it at all.

use crate::poseidon::{self, Digest};
use mt_codec::domain;

// The observation is absorbed as limbs, the door every use of this family takes for bytes that are
// not already words of the field. The window is eight bytes little-endian, as everywhere.
pub fn leaf(record_commitment: &[u8; 32], window: u64, blind: &[u8; 32]) -> Digest {
    let mut body = Vec::with_capacity(72);
    body.extend_from_slice(record_commitment);
    body.extend_from_slice(&window.to_le_bytes());
    body.extend_from_slice(blind);
    poseidon::hash_bytes(domain::MT_FABRIC_LEAF, &body)
}

pub fn empty_leaf() -> Digest {
    poseidon::hash_elements(domain::MT_FABRIC_LEAF, &[])
}

pub fn node(left: &Digest, right: &Digest) -> Digest {
    poseidon::node(domain::MT_FABRIC_NODE, left, right)
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

// The root over the observations written so far, every level above the written prefix taking the
// empty internal of that level. A tree of one observation folds it with the empty of every level
// and never with another leaf, which is why the set freezes a root over two: that is the value a
// level assembled right-then-left parts from.
pub fn root_of(leaves: &[Digest], depth: usize) -> Digest {
    let empties = empty_internals(depth);
    let mut level: Vec<Digest> = leaves.to_vec();
    for empty in empties.iter().take(depth) {
        if level.is_empty() {
            return empties[depth];
        }
        let mut above = Vec::with_capacity(level.len().div_ceil(2));
        for pair in level.chunks(2) {
            match pair {
                [left, right, ..] => above.push(node(left, right)),
                [only] => above.push(node(only, empty)),
                [] => {}
            }
        }
        level = above;
    }
    level.first().copied().unwrap_or_else(|| empties[depth])
}

pub struct FabricTree {
    depth: usize,
    leaves: Vec<Digest>,
}

pub struct TreeFull;

impl FabricTree {
    pub fn new(depth: usize) -> Self {
        Self {
            depth,
            leaves: Vec::new(),
        }
    }

    pub fn witness(
        &mut self,
        record_commitment: &[u8; 32],
        window: u64,
        blind: &[u8; 32],
    ) -> Result<u64, TreeFull> {
        if self.depth < 64 && self.leaves.len() as u64 >= 1u64 << self.depth {
            return Err(TreeFull);
        }
        self.leaves.push(leaf(record_commitment, window, blind));
        Ok(self.leaves.len() as u64 - 1)
    }

    pub fn len(&self) -> u64 {
        self.leaves.len() as u64
    }

    pub fn is_empty(&self) -> bool {
        self.leaves.is_empty()
    }

    pub fn root(&self) -> Digest {
        root_of(&self.leaves, self.depth)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_leaf_binds_the_window_it_was_seen_in() {
        let commitment = [0x11u8; 32];
        let blind = [0x22u8; 32];
        assert_ne!(leaf(&commitment, 7, &blind), leaf(&commitment, 8, &blind));
    }

    #[test]
    fn the_fabric_folds_apart_from_the_tree_of_notes() {
        let commitment = [0x11u8; 32];
        let blind = [0x22u8; 32];
        let one = leaf(&commitment, 7, &blind);
        let by_notes = crate::notes::root_of(&[one.bytes()], 40).expect("a tree of one leaf");
        assert_ne!(root_of(&[one], 40).bytes(), by_notes);
        assert_ne!(empty_leaf(), crate::notes::empty_leaf());
    }

    #[test]
    fn a_second_observation_is_what_pins_the_pairing_of_a_level() {
        let one = leaf(&[0x11u8; 32], 7, &[0x22u8; 32]);
        let two = leaf(&[0x33u8; 32], 8, &[0x44u8; 32]);
        assert_ne!(root_of(&[one, two], 40), root_of(&[two, one], 40));
    }
}
