// The tree of credited rights: append-only by position, of the proof hash family, since its paths
// exist only as witnesses of proofs. Its leaf absorbs the four words of a part-nullifier, and the
// proposal of the window after a window appends the parts of that window's cement, ascending — so
// the one leaf a right of a window can walk to is the part its machine's secret derives for that
// window, and only where that window's cement held it.
//
// **Why a tree of parts and not a tree of machines.** A walk to the tree of admitted machines says
// that a machine was admitted, and nothing about which windows it lived: an admitted machine absent
// from a cement walked there as well as one present in it, and took the coin of a window that never
// witnessed it. A part is the window and the machine at once, so a leaf over it is a credit of one
// window to one machine and of nothing else, and it names nobody, as the part does.

use crate::poseidon::{self, Digest};
use mt_codec::domain;

// The leaf absorbs the four words of a part-nullifier and nothing beside it: the part already takes
// the window, so a window written beside it would bind what is bound. This is the one place that
// fold is written, and the circuit of a frame walks the tree through this same door.
pub fn leaf_of(part: &Digest) -> Digest {
    poseidon::hash_elements(domain::MT_CREDIT_LEAF, part.elements())
}

// Bytes that are not a digest of the family never become a leaf, and the refusal stands here.
pub fn leaf(part: &[u8; 32]) -> Option<Digest> {
    Some(leaf_of(&Digest::of_bytes(part)?))
}

pub fn empty_leaf() -> Digest {
    poseidon::hash_elements(domain::MT_CREDIT_LEAF, &[])
}

pub fn node(left: &Digest, right: &Digest) -> Digest {
    poseidon::node(domain::MT_CREDIT_NODE, left, right)
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

pub fn empty_root() -> Digest {
    let depth = crate::tree_depth();
    empty_internals(depth)[depth]
}

// The root over the parts credited so far, in the order they entered, every level above the
// written prefix taking the empty internal of that level — the convention every append-only tree of
// the set takes. A list longer than the tree is refused rather than rooted over its first leaves.
pub fn root_of(parts: &[[u8; 32]], depth: usize) -> Option<Digest> {
    if u32::try_from(depth)
        .ok()
        .and_then(|bits| 1usize.checked_shl(bits))
        .is_some_and(|room| parts.len() > room)
    {
        return None;
    }
    let leaves = parts.iter().map(leaf).collect::<Option<Vec<Digest>>>()?;
    Some(Tree::of_leaves(depth, leaves).ok()?.root())
}

// The tree as a machine holding the state grows it: the parts of a window's cement appended at the
// proposal of the window after it, the root over them, and the path a machine walks to redeem its
// own right. A caller that folded the levels itself would be a second implementation of the fold
// above, and the two would agree only until one of them was edited.
#[derive(Clone)]
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

    // The parts of one cement credited together, ascending as the cement holds them. The whole run
    // is checked before a leaf enters, so a refused run leaves the tree as it stood: a window is
    // credited whole or not at all.
    pub fn credit(&mut self, parts: &[[u8; 32]]) -> Result<(), TreeFull> {
        let end = self.leaves.len().checked_add(parts.len()).ok_or(TreeFull)?;
        if self.depth < 64 && end as u64 > 1u64 << self.depth {
            return Err(TreeFull);
        }
        let leaves: Vec<Digest> = parts
            .iter()
            .map(leaf)
            .collect::<Option<_>>()
            .ok_or(TreeFull)?;
        self.leaves
            .try_reserve(leaves.len())
            .map_err(|_| TreeFull)?;
        self.leaves.extend(leaves);
        Ok(())
    }

    // The leaves this tree stands on, and a tree built back from them: a tree is a function of its
    // leaves in their order and of nothing else.
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
        self.walk(None).0
    }

    // Where the leaf of one part stands, or nothing for a part no cement this tree credited held.
    pub fn position_of(&self, part: &[u8; 32]) -> Option<u64> {
        let held = leaf(part)?;
        self.leaves
            .iter()
            .position(|at| *at == held)
            .map(|at| at as u64)
    }

    // The siblings from the leaf upward at one position, or nothing where nothing stands there.
    pub fn path(&self, position: u64) -> Option<Vec<Digest>> {
        if position >= self.len() {
            return None;
        }
        self.walk(Some(position as usize)).1
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
            for pair in level.chunks(2) {
                let right = pair.get(1).copied().unwrap_or(*empty);
                above.push(node(&pair[0], &right));
            }
            level = above;
            index = index.map(|at| at >> 1);
        }
        (level.first().copied().unwrap_or(empties[self.depth]), path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn part(byte: u8, window: u64) -> [u8; 32] {
        mt_derive::nullifier::part(&[byte; 32], window).expect("a secret of the family")
    }

    // The tree of credited rights is neither the tree of a cement nor the tree of admitted machines:
    // its own domains part every value, so a branch of one never stands in another.
    #[test]
    fn the_tree_of_credited_rights_is_no_other_tree() {
        let held = Digest::of_bytes(&part(1, 1000)).expect("a digest of the family");
        assert_ne!(leaf_of(&held), crate::cement::leaf_of(&held));
        assert_ne!(leaf_of(&held), crate::admitted::leaf_of(&held));
        assert_ne!(empty_leaf(), crate::cement::empty_leaf());
        assert_ne!(node(&held, &held), crate::admitted::node(&held, &held));
    }

    // Every branch the tree hands out walks to its root, and the leaf of one machine's part of one
    // window is not the leaf of its part of another.
    #[test]
    fn every_branch_walks_to_the_root_and_a_window_is_its_own_leaf() {
        let depth = 8;
        let mut tree = Tree::new(depth);
        let first: Vec<[u8; 32]> = (1..=3u8).map(|b| part(b, 1000)).collect();
        assert!(tree.credit(&first).is_ok());
        assert!(tree.credit(&[part(1, 1001)]).is_ok());
        let root = tree.root();
        assert_eq!(
            root_of(&[first[0], first[1], first[2], part(1, 1001)], depth),
            Some(root)
        );
        for held in first.iter().chain(std::iter::once(&part(1, 1001))) {
            let position = tree.position_of(held).expect("a part the tree credited");
            let siblings = tree.path(position).expect("a position the tree holds");
            let mut current = leaf(held).expect("a digest");
            for (level, sibling) in siblings.iter().enumerate() {
                current = if (position >> level) & 1 == 1 {
                    node(sibling, &current)
                } else {
                    node(&current, sibling)
                };
            }
            assert_eq!(current, root);
        }
        assert_ne!(
            tree.position_of(&part(1, 1000)),
            tree.position_of(&part(1, 1001))
        );
        assert!(tree.position_of(&part(1, 1002)).is_none());
        assert!(tree.position_of(&part(4, 1000)).is_none());
    }

    // A run is credited whole or not at all: a value that is no digest of the family, or a run past
    // the room of the tree, leaves the tree as it stood.
    #[test]
    fn a_refused_run_credits_nothing() {
        let mut tree = Tree::new(2);
        assert!(tree.credit(&[part(1, 7)]).is_ok());
        let before = tree.root();
        assert!(tree.credit(&[part(2, 7), [0xFF; 32]]).is_err());
        assert!(tree.credit(&[part(3, 7); 4]).is_err());
        assert_eq!(tree.len(), 1);
        assert_eq!(tree.root(), before);
        assert_eq!(root_of(&[], 2), Some(empty_internals(2)[2]));
        assert!(root_of(&[[0xFF; 32]], 2).is_none());
    }
}
