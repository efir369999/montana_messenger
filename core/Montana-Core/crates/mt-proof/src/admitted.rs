// The tree of admitted machines: append-only by position, of the proof hash family, since its
// paths exist only as witnesses of proofs. Its leaf absorbs the four words of the half that names
// a machine, and its empties are its own — folding it under the domains of the tree of notes
// reproduces nothing of it.
//
// **Why a tree at all.** A right names no machine, by construction, and a value naming no machine
// is a value a network cannot check against anything it holds: it holds no secret of any machine
// and can pre-register nothing. Membership is what closes that, and it closes it the way a note is
// closed — a walk whose leaf and whose position stay inside the proof.

use crate::poseidon::{self, Digest};
use mt_codec::domain;

// The leaf absorbs the four words of the naming half. This is the one place that fold is written,
// and the circuit of a frame walks the tree through this same door.
pub fn leaf_of(naming: &Digest) -> Digest {
    poseidon::hash_elements(domain::MT_ADMITTED_LEAF, naming.elements())
}

pub fn leaf(naming: &[u8; 32]) -> Option<Digest> {
    Some(leaf_of(&Digest::of_bytes(naming)?))
}

pub fn empty_leaf() -> Digest {
    poseidon::hash_elements(domain::MT_ADMITTED_LEAF, &[])
}

pub fn node(left: &Digest, right: &Digest) -> Digest {
    poseidon::node(domain::MT_ADMITTED_NODE, left, right)
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

fn depth() -> usize {
    crate::tree_depth()
}

pub fn empty_root() -> Digest {
    let empties = empty_internals(depth());
    empties[depth()]
}

// The root over the naming halves written so far, every level above the written prefix taking the
// empty internal of that level. What it takes is the contents and never the leaves: the fold of a
// leaf stands in one place, above, and this door applies it — the same shape the tree of notes
// takes, so one convention carries both trees rather than one each.
//
// A root over one half folds that half with the empty of every level and never with another leaf,
// so it says nothing about which of two neighbours of a level is the left one. That is why the set
// freezes a root over two.
pub fn root_of(naming: &[[u8; 32]], depth: usize) -> Option<Digest> {
    let empties = empty_internals(depth);
    let mut level: Vec<Digest> = naming.iter().map(leaf).collect::<Option<Vec<Digest>>>()?;
    for empty in empties.iter().take(depth) {
        if level.is_empty() {
            return Some(empties[depth]);
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
    level.first().copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    // The two trees part on every value, which is what their own domains buy: a machine folded
    // under the domains of the notes stands at another leaf and under another root.
    #[test]
    fn the_tree_of_machines_is_not_the_tree_of_notes() {
        let naming = Digest::of_bytes(&[0x5A; 32]).expect("a digest of the family");
        assert_ne!(leaf_of(&naming), crate::notes::leaf_of(&naming));
        assert_ne!(empty_leaf(), crate::notes::empty_leaf());
        assert_ne!(node(&naming, &naming), crate::notes::node(&naming, &naming));
    }

    // Bytes that are no digest of the family never become a leaf.
    #[test]
    fn a_leaf_takes_a_digest_and_refuses_what_is_not_one() {
        assert!(leaf(&[0xFF; 32]).is_none());
        assert!(leaf(&[0x01; 32]).is_some());
        assert!(root_of(&[[0xFF; 32]], 4).is_none());
    }

    // The pairing of a level, which a root over one half cannot say anything about: the named
    // wrong implementation folds a genuine pair right-then-left and reproduces every root over
    // one leaf there is.
    #[test]
    fn the_pairing_of_a_level_is_what_a_second_leaf_pins() {
        let a = [0x11; 32];
        let b = [0x22; 32];
        assert_ne!(root_of(&[a, b], 4), root_of(&[b, a], 4));
        assert_ne!(root_of(&[a, b], 4), root_of(&[a], 4));
        assert_eq!(
            root_of(&[], 4).map(|d| d.bytes()),
            Some(empty_internals(4)[4].bytes())
        );
    }
}
