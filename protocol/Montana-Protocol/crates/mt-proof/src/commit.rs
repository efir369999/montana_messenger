// The trees of a proof: a commitment to a list of positions, and the path that opens one of them.
// They stand under the two domains the set gives them, so a tree of a proof is never a tree of
// anything else, and an odd position rises unchanged, as in the append-only construction of the
// state — no position ever holds a blank child.

use crate::ext::E;
use crate::field::F;
use crate::poseidon::Digest;
use mt_codec::domain;

#[derive(Debug, PartialEq, Eq)]
pub enum OpenError {
    // A position past the leaves the tree was built over.
    PositionBeyondTree { position: usize, leaves: usize },
    // A path of another height than the tree the root came from.
    PathHeight { expected: usize, found: usize },
    // The path recomputes a root that is not the one it was offered against.
    RootMismatch,
}

// A leaf is the values one position carries, in order, absorbed as the field elements they are —
// a row of the extended trace, one value of the composition, or the values a folding layer folds.
pub fn leaf(values: &[F]) -> Digest {
    crate::poseidon::hash_elements(domain::MT_PROOF_LEAF, values)
}

// A leaf of the field the challenges stand in: an element is its three coefficients, so a leaf of
// them is the same rule read over three times the words.
pub fn leaf_of_elements(values: &[E]) -> Digest {
    let mut flat = Vec::with_capacity(values.len() * 3);
    for value in values {
        flat.extend_from_slice(&value.coefficients());
    }
    leaf(&flat)
}

fn node(left: &Digest, right: &Digest) -> Digest {
    crate::poseidon::node(domain::MT_PROOF_NODE, left, right)
}

// The tree over a list of leaves, kept level by level so a path is read rather than recomputed.
pub struct Tree {
    levels: Vec<Vec<Digest>>,
}

impl Tree {
    pub fn of(leaves: Vec<Digest>) -> Tree {
        let mut levels = vec![leaves];
        while let Some(below) = levels.last().filter(|level| level.len() > 1) {
            let mut above = Vec::with_capacity(below.len().div_ceil(2));
            // A chunk of two holds two, one, or nothing, and every one of the three is answered:
            // there is no arm left over to stand for a case that cannot happen, and therefore no
            // place where this fold can fall over.
            for pair in below.chunks(2) {
                match pair {
                    [left, right, ..] => above.push(node(left, right)),
                    // An odd position rises unchanged rather than folding with a blank child.
                    [only] => above.push(*only),
                    [] => {}
                }
            }
            levels.push(above);
        }
        Tree { levels }
    }

    pub fn leaves(&self) -> usize {
        self.levels.first().map(Vec::len).unwrap_or(0)
    }

    pub fn root(&self) -> Digest {
        self.levels
            .last()
            .and_then(|level| level.first().copied())
            .unwrap_or(Digest::ZERO)
    }

    // The siblings a position needs, from the leaf upward. A level whose position has no sibling
    // contributes none, since the position rose unchanged.
    pub fn path(&self, position: usize) -> Result<Vec<Digest>, OpenError> {
        if position >= self.leaves() {
            return Err(OpenError::PositionBeyondTree {
                position,
                leaves: self.leaves(),
            });
        }
        let mut out = Vec::with_capacity(self.levels.len());
        let mut at = position;
        for level in &self.levels[..self.levels.len() - 1] {
            let sibling = at ^ 1;
            if sibling < level.len() {
                out.push(level[sibling]);
            }
            at /= 2;
        }
        Ok(out)
    }
}

// The walk a verifier makes: the leaf and its siblings recompute a root, and the root is compared
// with the one already held. A path is never trusted for a root, and it carries none.
pub fn verify(
    leaf: &Digest,
    position: usize,
    leaves: usize,
    path: &[Digest],
    root: &Digest,
) -> Result<(), OpenError> {
    if position >= leaves {
        return Err(OpenError::PositionBeyondTree { position, leaves });
    }
    let mut current = *leaf;
    let mut at = position;
    let mut width = leaves;
    let mut used = 0usize;
    while width > 1 {
        let sibling = at ^ 1;
        if sibling < width {
            let held = path.get(used).ok_or(OpenError::PathHeight {
                expected: used + 1,
                found: path.len(),
            })?;
            current = if at.is_multiple_of(2) {
                node(&current, held)
            } else {
                node(held, &current)
            };
            used += 1;
        }
        at /= 2;
        width = width.div_ceil(2);
    }
    if used != path.len() {
        return Err(OpenError::PathHeight {
            expected: used,
            found: path.len(),
        });
    }
    if current == *root {
        Ok(())
    } else {
        Err(OpenError::RootMismatch)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn values(seed: u64, count: usize) -> Vec<F> {
        (0..count)
            .map(|i| F::from_u64_reduced(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ i as u64))
            .collect()
    }

    fn tree_of(count: usize, width: usize) -> (Tree, Vec<Digest>) {
        let leaves: Vec<Digest> = (0..count)
            .map(|i| leaf(&values(i as u64 + 1, width)))
            .collect();
        (Tree::of(leaves.clone()), leaves)
    }

    #[test]
    fn every_position_opens_against_the_root_and_no_other() {
        for count in [1usize, 2, 3, 5, 8, 17, 64] {
            let (tree, leaves) = tree_of(count, 3);
            for (position, held) in leaves.iter().enumerate() {
                let path = tree.path(position).expect("a position of the tree");
                assert_eq!(verify(held, position, count, &path, &tree.root()), Ok(()));
                // The same path at another position recomputes another root, so a path proves the
                // place as well as the value.
                if count > 1 {
                    let elsewhere = (position + 1) % count;
                    assert_ne!(verify(held, elsewhere, count, &path, &tree.root()), Ok(()));
                }
            }
        }
    }

    // The named wrong implementation this refuses: one that takes the root the proof carries. A
    // path recomputes a root and is compared with the one already held, so a leaf nobody committed
    // to fails wherever it is put.
    #[test]
    fn a_leaf_the_tree_does_not_hold_fails_the_walk() {
        let (tree, _) = tree_of(16, 3);
        let path = tree.path(5).expect("a position of the tree");
        let stranger = leaf(&values(999, 3));
        assert_eq!(
            verify(&stranger, 5, 16, &path, &tree.root()),
            Err(OpenError::RootMismatch)
        );
    }

    #[test]
    fn a_path_of_another_height_is_refused_rather_than_walked() {
        let (tree, leaves) = tree_of(16, 3);
        let mut path = tree.path(5).expect("a position of the tree");
        path.pop();
        assert!(matches!(
            verify(&leaves[5], 5, 16, &path, &tree.root()),
            Err(OpenError::PathHeight { .. })
        ));
        let mut path = tree.path(5).expect("a position of the tree");
        path.push(leaf(&[F::ZERO]));
        assert!(matches!(
            verify(&leaves[5], 5, 16, &path, &tree.root()),
            Err(OpenError::PathHeight { .. })
        ));
    }

    #[test]
    fn a_position_past_the_tree_is_refused_by_both_doors() {
        let (tree, leaves) = tree_of(8, 2);
        assert_eq!(
            tree.path(8),
            Err(OpenError::PositionBeyondTree {
                position: 8,
                leaves: 8
            })
        );
        assert_eq!(
            verify(&leaves[0], 8, 8, &[], &tree.root()),
            Err(OpenError::PositionBeyondTree {
                position: 8,
                leaves: 8
            })
        );
    }

    // A leaf takes the domain of a leaf and a node the domain of a node, so no value of one is
    // ever read as a value of the other — the property every tree of this protocol rests on.
    #[test]
    fn a_leaf_and_a_node_of_one_pair_of_values_are_two_values() {
        let a = leaf(&[F::from_u64_reduced(0x11)]);
        let b = leaf(&[F::from_u64_reduced(0x22)]);
        let as_leaf = leaf(&[F::from_u64_reduced(1), F::from_u64_reduced(2)]);
        let as_node = node(&a, &b);
        assert_ne!(as_leaf, as_node);
        // And a tree of one leaf is that leaf: nothing is folded where there is nothing to fold.
        let one = leaf(&[F::ONE]);
        assert_eq!(Tree::of(vec![one]).root(), one);
    }

    // The implementation this refuses: one that takes a node of a path as thirty-two bytes and
    // hands them to the arithmetic. A wire carries bytes, and bytes at or above the modulus are not
    // elements; under the old shape the walk consumed them and the machine fell over, which is a
    // proof of one sending taking down every machine that verifies it.
    #[test]
    fn bytes_that_are_not_a_digest_do_not_become_one() {
        assert!(crate::poseidon::Digest::of_bytes(&[0xFFu8; 32]).is_none());
        let mut at_the_edge = [0u8; 32];
        at_the_edge[..8].copy_from_slice(&crate::field::P.to_le_bytes());
        assert!(crate::poseidon::Digest::of_bytes(&at_the_edge).is_none());
        let below = crate::field::P - 1;
        let mut stands = [0u8; 32];
        for at in 0..4 {
            stands[at * 8..at * 8 + 8].copy_from_slice(&below.to_le_bytes());
        }
        let held = crate::poseidon::Digest::of_bytes(&stands).expect("four elements are a digest");
        assert_eq!(held.bytes(), stands);
    }

    #[test]
    fn a_leaf_of_elements_is_the_leaf_of_their_coefficients() {
        let element = E::of(F::ONE, F::from_u64_reduced(2), F::from_u64_reduced(3));
        assert_eq!(
            leaf_of_elements(&[element]),
            leaf(&[F::ONE, F::from_u64_reduced(2), F::from_u64_reduced(3)])
        );
    }
}
