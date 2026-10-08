// The tree of notes: append-only by position, of the proof hash family, since its paths exist
// only as witnesses of proofs. Its leaf absorbs the limbs of a commitment — the commitment
// itself stays SHA-256, the hiding envelope of a note is not of this family — and its empties
// are its own, so folding it under the Merkle domains or under SHA-256 reproduces nothing of it.

use crate::poseidon::{self, Digest};
use mt_codec::domain;

// The leaf absorbs the four words of the commitment — `cells(cm)` of the set. This is the one
// place that fold is written; the door below takes bytes and refuses those that are not a digest
// of the family, and the circuit of a frame walks the tree through this same door.
pub fn leaf_of(commitment: &Digest) -> Digest {
    poseidon::hash_elements(domain::MT_NOTE_LEAF, commitment.elements())
}

// Bytes that are not a digest of the family never become a leaf, and the refusal stands here.
pub fn leaf(commitment: &[u8; 32]) -> Option<Digest> {
    Some(leaf_of(&Digest::of_bytes(commitment)?))
}

pub fn empty_leaf() -> Digest {
    poseidon::hash_elements(domain::MT_NOTE_LEAF, &[])
}

pub fn node(left: &Digest, right: &Digest) -> Digest {
    poseidon::node(domain::MT_NOTE_NODE, left, right)
}

// The chain of empty internals, level zero being the empty leaf.
pub fn empty_internals(depth: usize) -> Vec<Digest> {
    let mut out = Vec::with_capacity(depth + 1);
    out.push(empty_leaf());
    for level in 0..depth {
        let below = out[level];
        out.push(node(&below, &below));
    }
    out
}

// The root over the leaves written so far, every level above the written prefix taking the
// empty internal of that level — the same walk as every append-only tree of the set.
// The root of this tree holding nothing, at the depth the Decree names. Written here because the
// fold is written here: a caller that assembled the empties itself would be a second implementation
// of it, and the two would agree only until one of them was edited.
pub fn empty_root() -> Digest {
    let depth = crate::tree_depth();
    empty_internals(depth)[depth]
}

// The tree as it grows on a machine that holds the state: commitments appended in the order they
// were seen, the root over them, and the path a spender walks to prove one is in it. A caller that
// folded the levels itself would be a second implementation of the fold above, and the two would
// agree only until one of them was edited.
pub struct Tree {
    depth: usize,
    leaves: Vec<Digest>,
}

pub struct TreeFull;

impl Tree {
    pub fn new(depth: usize) -> Self {
        Self {
            depth,
            leaves: Vec::new(),
        }
    }

    // A commitment appended, answering with the position it took. Bytes that are not a digest of
    // the family never enter, and the refusal is the one the leaf itself gives.
    pub fn push(&mut self, commitment: &[u8; 32]) -> Result<u64, TreeFull> {
        if self.depth < 64 && self.leaves.len() as u64 >= 1u64 << self.depth {
            return Err(TreeFull);
        }
        self.leaves.push(leaf(commitment).ok_or(TreeFull)?);
        Ok(self.leaves.len() as u64 - 1)
    }

    // The leaves this tree stands on, and a tree built back from them. A tree is a function of its
    // leaves in their order and of nothing else, so these two are what lets a machine keep what it
    // holds across a stop without keeping a second construction of the tree beside the first.
    pub fn leaves(&self) -> &[Digest] {
        &self.leaves
    }

    pub fn of_leaves(depth: usize, leaves: Vec<Digest>) -> Result<Self, TreeFull> {
        if depth < 64 && leaves.len() as u64 > 1u64 << depth {
            return Err(TreeFull);
        }
        Ok(Self { depth, leaves })
    }

    pub fn len(&self) -> u64 {
        self.leaves.len() as u64
    }

    pub fn is_empty(&self) -> bool {
        self.leaves.is_empty()
    }

    pub fn root(&self) -> Digest {
        let (root, _) = self.walk(None);
        root
    }

    // The siblings from the leaf upward at one position, or nothing where nothing stands there.
    pub fn path(&self, position: u64) -> Option<Vec<Digest>> {
        if position >= self.len() {
            return None;
        }
        let (_, path) = self.walk(Some(position as usize));
        path
    }

    fn walk(&self, of: Option<usize>) -> (Digest, Option<Vec<Digest>>) {
        let empties = empty_internals(self.depth);
        let mut level = self.leaves.clone();
        let mut index = of;
        let mut path = of.map(|_| Vec::with_capacity(self.depth));
        for empty in empties.iter().take(self.depth) {
            if let (Some(at), Some(held)) = (index, path.as_mut()) {
                held.push(level.get(at ^ 1).copied().unwrap_or(*empty));
            }
            let mut above = Vec::with_capacity(level.len().div_ceil(2));
            let mut which = 0;
            while which < level.len() {
                let left = level[which];
                let right = level.get(which + 1).copied().unwrap_or(*empty);
                above.push(node(&left, &right));
                which += 2;
            }
            level = above;
            index = index.map(|at| at >> 1);
        }
        (level.first().copied().unwrap_or(empties[self.depth]), path)
    }
}

pub fn root_of(commitments: &[[u8; 32]], depth: usize) -> Option<[u8; 32]> {
    let empties = empty_internals(depth);
    let mut level: Vec<Digest> = commitments
        .iter()
        .map(leaf)
        .collect::<Option<Vec<Digest>>>()?;
    for empty in empties.iter().take(depth) {
        if level.is_empty() {
            return Some(empties[depth].bytes());
        }
        let mut above = Vec::with_capacity(level.len().div_ceil(2));
        // A chunk of two holds two, one, or nothing, and every one of the three is answered.
        for pair in level.chunks(2) {
            match pair {
                [left, right, ..] => above.push(node(left, right)),
                [only] => above.push(node(only, empty)),
                [] => {}
            }
        }
        level = above;
    }
    level.first().map(|root| root.bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_tree_is_the_empty_internal_of_its_depth() {
        let empties = empty_internals(4);
        assert_eq!(root_of(&[], 4), Some(empties[4].bytes()));
    }

    #[test]
    fn one_commitment_moves_the_root_and_its_position_matters() {
        let a = [0x11u8; 32];
        let b = [0x22u8; 32];
        let one = root_of(&[a], 4);
        assert!(one.is_some());
        assert_ne!(one, root_of(&[], 4));
        assert_ne!(one, root_of(&[b], 4));
        assert_ne!(root_of(&[a, b], 4), root_of(&[b, a], 4));
    }

    #[test]
    fn bytes_that_are_not_a_digest_never_become_a_leaf() {
        // The named wrong implementation: one absorbing the limbs of the bytes would fold
        // anything; the door of the words refuses what no digest of the family ever is.
        assert!(leaf(&[0xFFu8; 32]).is_none());
        assert_eq!(root_of(&[[0xFFu8; 32]], 4), None);
    }
}
