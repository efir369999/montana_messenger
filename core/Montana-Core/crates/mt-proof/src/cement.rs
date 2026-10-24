// The tree of a cement: the part-nullifiers a window's cement holds, in ascending order, folded by
// position under domains of their own. It is of the proof hash family because its paths exist only
// as witnesses of proofs — a ballot walks it to say that the part a machine's secret derives for a
// census window stands in that window's cement, and says nothing of which part or where.
//
// **Why a tree over a set the aggregate already binds.** The aggregate of a cement is the seed of a
// draw and is taken under SHA-256, which no circuit of this set carries; membership in it cannot be
// proven without publishing the member. A root of the proof hash over the same ascending run is the
// one value a proof can walk to, and it binds the run exactly as the aggregate does.

use crate::poseidon::{self, Digest};
use mt_codec::domain;

// The leaf absorbs the four words of a part-nullifier. This is the one place that fold is written,
// and the circuit of a ballot walks the tree through this same door.
pub fn leaf_of(part: &Digest) -> Digest {
    poseidon::hash_elements(domain::MT_CEMENT_LEAF, part.elements())
}

pub fn empty_leaf() -> Digest {
    poseidon::hash_elements(domain::MT_CEMENT_LEAF, &[])
}

pub fn node(left: &Digest, right: &Digest) -> Digest {
    poseidon::node(domain::MT_CEMENT_NODE, left, right)
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
    empty_internals(crate::tree_depth())[crate::tree_depth()]
}

// The leaves of a cement in the order the tree takes them: ascending by the bytes of the part, each
// once. A run holding a repeat or a value that is no digest of the family is not a cement.
fn leaves_of(parts: &[[u8; 32]]) -> Option<Vec<Digest>> {
    let mut out = Vec::with_capacity(parts.len());
    let mut last: Option<[u8; 32]> = None;
    for part in parts {
        if last.is_some_and(|held| *part <= held) {
            return None;
        }
        last = Some(*part);
        out.push(leaf_of(&Digest::of_bytes(part)?));
    }
    Some(out)
}

// The root over a cement's parts, ascending, every level above the written prefix taking the empty
// internal of that level — the convention the tree of admitted machines takes, so one rule carries
// both trees.
pub fn root_of(parts: &[[u8; 32]], depth: usize) -> Option<Digest> {
    let empties = empty_internals(depth);
    let mut level = leaves_of(parts)?;
    for empty in empties.iter().take(depth) {
        if level.is_empty() {
            return Some(empties[depth]);
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
    level.first().copied()
}

// The branch one part walks: its siblings level by level and its position, or nothing for a part the
// cement does not hold. A machine takes its own branch once, when the census window closes, and
// keeps it — the tree of a closed window never moves again.
pub fn branch_of(parts: &[[u8; 32]], part: &[u8; 32], depth: usize) -> Option<(Vec<Digest>, u64)> {
    let mut level = leaves_of(parts)?;
    let mut index = parts.binary_search(part).ok()?;
    let position = index as u64;
    let empties = empty_internals(depth);
    let mut siblings = Vec::with_capacity(depth);
    for empty in empties.iter().take(depth) {
        siblings.push(level.get(index ^ 1).copied().unwrap_or(*empty));
        let mut above = Vec::with_capacity(level.len().div_ceil(2));
        for pair in level.chunks(2) {
            let right = pair.get(1).copied().unwrap_or(*empty);
            above.push(node(&pair[0], &right));
        }
        level = above;
        index >>= 1;
    }
    Some((siblings, position))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn part(byte: u8) -> [u8; 32] {
        poseidon::hash_bytes(domain::MT_PART_NF, &[byte; 32]).bytes()
    }

    fn ascending(mut parts: Vec<[u8; 32]>) -> Vec<[u8; 32]> {
        parts.sort_unstable();
        parts
    }

    // The tree of a cement is not the tree of admitted machines: its own domains part every value,
    // so a branch of one never stands in the other.
    #[test]
    fn the_tree_of_a_cement_is_not_the_tree_of_admitted_machines() {
        let held = Digest::of_bytes(&part(1)).expect("a digest of the family");
        assert_ne!(leaf_of(&held), crate::admitted::leaf_of(&held));
        assert_ne!(empty_leaf(), crate::admitted::empty_leaf());
        assert_ne!(node(&held, &held), crate::admitted::node(&held, &held));
    }

    // Every branch the tree hands out walks to its root, and a run out of order is no cement.
    #[test]
    fn every_branch_walks_to_the_root() {
        let parts = ascending((1..=5u8).map(part).collect());
        let depth = 8;
        let root = root_of(&parts, depth).expect("a cement of distinct digests");
        for held in &parts {
            let (siblings, position) = branch_of(&parts, held, depth).expect("a part it holds");
            let mut current = leaf_of(&Digest::of_bytes(held).expect("a digest"));
            for (level, sibling) in siblings.iter().enumerate() {
                current = if (position >> level) & 1 == 1 {
                    node(sibling, &current)
                } else {
                    node(&current, sibling)
                };
            }
            assert_eq!(current, root);
        }
        let mut swapped = parts.clone();
        swapped.swap(0, 1);
        assert!(
            root_of(&swapped, depth).is_none(),
            "a run out of order is no cement"
        );
        assert!(branch_of(&parts, &part(9), depth).is_none());
    }

    // A cement missing one part is another root, an empty cement is the empty root, and a repeat is
    // no cement at all.
    #[test]
    fn the_root_binds_the_run() {
        let parts = ascending((1..=4u8).map(part).collect());
        let depth = 8;
        assert_ne!(root_of(&parts, depth), root_of(&parts[1..], depth));
        assert_eq!(root_of(&[], depth), Some(empty_internals(depth)[depth]));
        let repeated = vec![parts[0], parts[0]];
        assert!(root_of(&repeated, depth).is_none());
    }
}
