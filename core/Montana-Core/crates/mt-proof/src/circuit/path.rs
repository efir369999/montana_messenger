// The walk of the tree of notes as a constraint set: a leaf absorbed, then one node permutation per
// level, the child and its sibling ordered by the bit of the position at that level, and the bits
// accumulated into the position itself — so that the position a nullifier takes and the position
// the walk was made at are one number rather than two the prover may choose apart.
//
// Nothing here folds a leaf or a node of its own: the walk goes through the doors of `notes`, which
// is where that tree is written, so the circuit asserts the fold every machine computes.
//
// **The order of a pair is held by a column and never by a branch.** A rule that read the bit and
// then placed the two values would multiply the bit into a difference of cells, which is degree
// three where the shape admits two. What stands instead is the left of the pair as a column of its
// own, held to the child when the bit is zero and to the sibling when it is one — two rules of
// degree two — with the right read as their sum less the left, which is linear.
//
// **The wrap of the trace is the initialization of the accumulator.** The rows close on themselves,
// so the row after the last is the first; a term that subtracts the accumulator exactly there makes
// that closing say `acc(0) = 0` — the one thing an accumulator needs said, taken from the shape of
// the trace rather than from a boundary written beside it.

use super::permutation::{self, period, ring_column};
use super::sponge::{self, factor, term};
use crate::air::{Boundary, BoundaryValue, Constraint, Periodic};
use crate::field::F;
use crate::poseidon::{self, Digest, CAPACITY, RATE, WIDTH};
use mt_codec::domain;

// The columns this layer adds after those of the permutation: the sibling of a level, the left of
// the pair, the bit that orders them, and the accumulator that binds the bits to a position.
pub const SIBLING: usize = permutation::TRACE_WIDTH;
pub const LEFT: usize = SIBLING + CAPACITY;
pub const BIT: usize = LEFT + CAPACITY;
pub const ACCUMULATOR: usize = BIT + 1;
pub const TRACE_WIDTH: usize = ACCUMULATOR + 1;

mt_codec::constants! {
    WALK:
    /// Where the schedule of a walk stands among the periodic columns this layer adds: which seam
    /// loads a node, at what weight its bit enters the position, and where the trace wraps. All
    /// four are places of this layout and of nothing else, which is why the set holds none of them.
    pub const LEVEL: usize = 0, code "the periodic column of this layout that marks the seam of a level";
    pub const WEIGHT: usize = 1, code "the periodic column of this layout that carries the weight of a level";
    pub const WRAP: usize = 2, code "the periodic column of this layout that marks where the trace closes";
    pub const PERIODIC_COUNT: usize = 3, code "the count of the periodic columns this layout adds";
    /// The bits a position of the tree of notes stands in. A trace carrying several walks numbers
    /// the levels of each from its own start, so the weight of a level is its place inside its own
    /// walk; the depth the Decree names is what bounds that place.
    const BITS_OF_A_POSITION: usize = 64, code "the bits a position of a leaf stands in, which bounds the place of a level inside its own walk";
}

// Which row carries the seam that loads the node of a level: the last row of the block before it.
pub fn level_rows(first_node_block: usize, depth: usize) -> Vec<usize> {
    (0..depth)
        .map(|level| (first_node_block + level) * period() - 1)
        .collect()
}

// The three columns of the schedule of a walk, in the order the description carries them.
// `clears` are the rows a walk's accumulator is emptied at: one walk holds one position, so a
// trace carrying several empties it between them. The closing of the trace is one of those rows
// always, which is what opens the first accumulator at zero.
pub fn periodic_columns(rows_log2: u8, walks: &[Vec<usize>], clears: &[usize]) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut level = vec![0u64; rows];
    let mut weight = vec![0u64; rows];
    let mut wrap = vec![0u64; rows];
    // A trace carries several walks, and the weight of a level is its place inside its own walk:
    // a flat list of every level of every walk would give the second walk the weights that follow
    // the first, and a position would come out as the sum of two.
    // The mark of a level and the weight of a position are two quantities: every level of a walk
    // is folded, and only the levels inside a position's bits carry weight. A guard that glued the
    // two together dropped the fold rules of a deep walk past the position's width — invisible on
    // the tree of notes, whose depth stands below it, and unsound on a walk keyed by a hash.
    for walk in walks {
        for (at, row) in walk.iter().enumerate() {
            if *row < rows {
                level[*row] = 1;
                if at < BITS_OF_A_POSITION {
                    weight[*row] = 1u64 << at;
                }
            }
        }
    }
    for row in clears {
        if *row < rows {
            wrap[*row] = 1;
        }
    }
    wrap[rows - 1] = 1;
    [level, weight, wrap]
        .into_iter()
        .map(|values| Periodic {
            period_log2: rows_log2,
            values,
        })
        .collect()
}

// Every rule of a walk, over the columns the caller places them at.
pub fn constraints(periodic_base: usize) -> Vec<Constraint> {
    let level = periodic_base + LEVEL;
    let weight = periodic_base + WEIGHT;
    let wrap = periodic_base + WRAP;
    let minus = F::ONE.negated();
    let mut out = Vec::new();

    // The bit is a bit, wherever it stands.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(BIT, 0, 2)]),
            term(minus, vec![factor(BIT, 0, 1)]),
        ],
    });

    for j in 0..CAPACITY {
        let child = ring_column(j);
        let sibling = SIBLING + j;
        let left = LEFT + j;
        // Zero orders the child first: (left − child)(1 − bit) = 0.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(left, 0, 1)]),
                term(minus, vec![factor(left, 0, 1), factor(BIT, 0, 1)]),
                term(minus, vec![factor(child, 0, 1)]),
                term(F::ONE, vec![factor(child, 0, 1), factor(BIT, 0, 1)]),
            ],
        });
        // One orders the sibling first: (left − sibling)·bit = 0.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(left, 0, 1), factor(BIT, 0, 1)]),
                term(minus, vec![factor(sibling, 0, 1), factor(BIT, 0, 1)]),
            ],
        });
        // The node of the level enters with that pair: the left where the left stands, and the
        // right as the sum of the two less the left, which is linear and needs no column.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(level, 0, 1), factor(child, 1, 1)]),
                term(minus, vec![factor(level, 0, 1), factor(left, 0, 1)]),
            ],
        });
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![factor(level, 0, 1), factor(ring_column(CAPACITY + j), 1, 1)],
                ),
                term(minus, vec![factor(level, 0, 1), factor(child, 0, 1)]),
                term(minus, vec![factor(level, 0, 1), factor(sibling, 0, 1)]),
                term(F::ONE, vec![factor(level, 0, 1), factor(left, 0, 1)]),
            ],
        });
    }

    // The accumulator: it holds where no level stands, takes the bit at its own weight where one
    // does, and the wrap of the trace says it opens at zero.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(ACCUMULATOR, 1, 1)]),
            term(minus, vec![factor(ACCUMULATOR, 0, 1)]),
            term(F::ONE, vec![factor(wrap, 0, 1), factor(ACCUMULATOR, 0, 1)]),
            term(minus, vec![factor(weight, 0, 1), factor(BIT, 0, 1)]),
        ],
    });
    out
}

// The blocks a walk of this depth costs: the leaf and one node per level.
pub fn blocks_of(depth: usize) -> usize {
    sponge::blocks_of(CAPACITY) + depth
}

// The walk written into the trace: the leaf absorbed, then the nodes, with the sibling, the pair
// and the bit of every level standing at the seam that loads it. What it answers with is the root.
pub fn write_walk(
    columns: &mut [Vec<F>],
    first_block: usize,
    commitment: &Digest,
    siblings: &[Digest],
    position: u64,
) -> Option<Digest> {
    write_walk_under(
        columns,
        first_block,
        commitment,
        siblings,
        position,
        domain::MT_NOTE_LEAF,
        domain::MT_NOTE_NODE,
    )
}

// The same walk under the domains of its branch: the doors of the fold stay where they are, and
// which tree is walked is the pair of domains the branch names.
pub fn write_walk_under(
    columns: &mut [Vec<F>],
    first_block: usize,
    commitment: &Digest,
    siblings: &[Digest],
    position: u64,
    leaf_domain: mt_codec::Domain,
    node_domain: mt_codec::Domain,
) -> Option<Digest> {
    let leaf_blocks = sponge::blocks_of(CAPACITY);
    let states = sponge::chain(leaf_domain, commitment.elements());
    for (at, state) in states.iter().enumerate() {
        permutation::write_block(columns, first_block + at, state)?;
    }
    let mut current = poseidon::hash_elements(leaf_domain, commitment.elements());
    let capacity = poseidon::capacity_of(node_domain);
    for (level, sibling) in siblings.iter().enumerate() {
        let block = first_block + leaf_blocks + level;
        let seam = block * period() - 1;
        let bit = (position >> level) & 1 == 1;
        let (left, right) = if bit {
            (*sibling, current)
        } else {
            (current, *sibling)
        };
        for j in 0..CAPACITY {
            columns[SIBLING + j][seam] = sibling.elements()[j];
            columns[LEFT + j][seam] = left.elements()[j];
        }
        columns[BIT][seam] = if bit { F::ONE } else { F::ZERO };
        let mut state = [F::ZERO; WIDTH];
        state[..CAPACITY].copy_from_slice(left.elements());
        state[CAPACITY..RATE].copy_from_slice(right.elements());
        state[RATE..].copy_from_slice(&capacity);
        permutation::write_block(columns, block, &state)?;
        current = poseidon::node(node_domain, &left, &right);
    }
    Some(current)
}

// The left of the pair, written at every row and not at the seams alone. The two rules that hold
// it stand under no selector — a selector over them would multiply the bit into a difference of
// cells and carry the degree past what the shape admits — so they speak at every row of the trace,
// and a column left empty where they speak is a column that breaks them. Where no level stands the
// bit is zero, so the left is the ring itself, and the rules say nothing more than that.
pub fn write_pairs(columns: &mut [Vec<F>]) {
    let ordered: Vec<bool> = columns[BIT].iter().map(|bit| *bit == F::ONE).collect();
    for j in 0..CAPACITY {
        let ring = ring_column(j);
        for (row, ordered) in ordered.iter().enumerate() {
            columns[LEFT + j][row] = if *ordered {
                columns[SIBLING + j][row]
            } else {
                columns[ring][row]
            };
        }
    }
}

// The accumulator written across the whole height: it opens at zero and takes the bit of every
// level at its own weight, so what it holds after the last level is the position itself.
pub fn write_accumulator(columns: &mut [Vec<F>], walks: &[Vec<usize>], clears: &[usize]) {
    let rows = columns[ACCUMULATOR].len();
    let mut weights = vec![F::ZERO; rows];
    for walk in walks {
        for (at, row) in walk.iter().enumerate() {
            if *row < rows && at < BITS_OF_A_POSITION {
                weights[*row] = F::from_u64_reduced(1u64 << at);
            }
        }
    }
    let mut emptied = vec![false; rows];
    for row in clears {
        if *row < rows {
            emptied[*row] = true;
        }
    }
    let mut held = F::ZERO;
    for row in 0..rows {
        columns[ACCUMULATOR][row] = held;
        held = if emptied[row] {
            F::ZERO
        } else {
            held.plus(weights[row].times(columns[BIT][row]))
        };
    }
}

// The boundaries a walk needs: the capacity of every node block, which is the literal of its own
// domain, since a node opens a fresh state rather than continuing one.
pub fn boundaries(first_block: usize, depth: usize) -> Vec<Boundary> {
    let capacity = poseidon::capacity_of(domain::MT_NOTE_NODE);
    let leaf_blocks = sponge::blocks_of(CAPACITY);
    let mut out = Vec::new();
    for level in 0..depth {
        let row = ((first_block + leaf_blocks + level) * period()) as u64;
        for (j, value) in capacity.iter().enumerate() {
            out.push(Boundary {
                column: ring_column(RATE + j) as u16,
                row,
                value: BoundaryValue::Literal(value.as_u64()),
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::air::Description;

    // A walk standing alone: the commitment and the root are the public input, the siblings and the
    // position are the witness, and what a proof of it asserts is that some path of this depth
    // carries that commitment to that root at the position the accumulator holds.
    fn description_of_a_walk(depth: usize, rows_log2: u8) -> Option<Description> {
        let mut held = permutation::description()?;
        held.rows_log2 = rows_log2;
        crate::circuit::widen(&mut held, TRACE_WIDTH);
        let base = TRACE_WIDTH + held.periodic.len();
        let leaf_blocks = sponge::blocks_of(CAPACITY);
        let levels = level_rows(leaf_blocks, depth);
        held.periodic.extend(periodic_columns(
            rows_log2,
            std::slice::from_ref(&levels),
            &[],
        ));
        held.constraints.extend(constraints(base));
        held.boundaries.extend(boundaries(0, depth));
        let capacity = poseidon::capacity_of(domain::MT_NOTE_LEAF);
        for (j, value) in capacity.iter().enumerate() {
            held.boundaries.push(Boundary {
                column: ring_column(RATE + j) as u16,
                row: 0,
                value: BoundaryValue::Literal(value.as_u64()),
            });
        }
        for slot in 0..RATE {
            let value = if slot < CAPACITY {
                BoundaryValue::Word((2 * slot) as u16)
            } else if slot == CAPACITY {
                BoundaryValue::Literal(F::ONE.as_u64())
            } else {
                BoundaryValue::Literal(0)
            };
            held.boundaries.push(Boundary {
                column: ring_column(slot) as u16,
                row: 0,
                value,
            });
        }
        let last = ((leaf_blocks + depth) * period() - 1) as u64;
        for j in 0..CAPACITY {
            held.boundaries.push(Boundary {
                column: ring_column(j) as u16,
                row: last,
                value: BoundaryValue::Word((2 * (CAPACITY + j)) as u16),
            });
        }
        held.boundaries.push(Boundary {
            column: ACCUMULATOR as u16,
            row: last,
            value: BoundaryValue::Word((4 * CAPACITY) as u16),
        });
        Some(held)
    }

    fn digest_of(byte: u8) -> Digest {
        poseidon::hash_bytes(domain::MT_NOTE_LEAF, &[byte; 32])
    }

    fn walk(depth: usize, position: u64) -> (Digest, Vec<Digest>, Digest) {
        let commitment = digest_of(0x11);
        let siblings: Vec<Digest> = (0..depth).map(|i| digest_of(0x20 + i as u8)).collect();
        let mut current = crate::notes::leaf_of(&commitment);
        for (level, sibling) in siblings.iter().enumerate() {
            let (left, right) = if (position >> level) & 1 == 1 {
                (*sibling, current)
            } else {
                (current, *sibling)
            };
            current = crate::notes::node(&left, &right);
        }
        (commitment, siblings, current)
    }

    fn public_of(commitment: &Digest, root: &Digest, position: u64) -> Vec<u8> {
        let mut out = Vec::new();
        for cell in commitment.elements() {
            out.extend_from_slice(&cell.as_u64().to_le_bytes());
        }
        for cell in root.elements() {
            out.extend_from_slice(&cell.as_u64().to_le_bytes());
        }
        out.extend_from_slice(&position.to_le_bytes());
        out
    }

    fn trace_of(depth: usize, position: u64, rows_log2: u8) -> (Vec<Vec<F>>, Digest) {
        let (commitment, siblings, _) = walk(depth, position);
        let rows = 1usize << rows_log2;
        let mut columns = vec![vec![F::ZERO; rows]; TRACE_WIDTH];
        let root = write_walk(&mut columns, 0, &commitment, &siblings, position)
            .expect("the walk is written");
        for block in blocks_of(depth)..rows / period() {
            permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])
                .expect("a block of the tail");
        }
        write_pairs(&mut columns);
        write_accumulator(
            &mut columns,
            &[level_rows(sponge::blocks_of(CAPACITY), depth)],
            &[],
        );
        (columns, root)
    }

    #[test]
    fn the_walk_of_the_circuit_is_the_walk_of_the_tree() {
        // The circuit's reading of a path and the tree every machine folds are one walk. The wrong
        // implementation this refuses: one folding the child left where the bit says right, which
        // answers at position zero and parts from the tree at the first position with a bit set.
        for position in [0u64, 1, 2, 5, 11, 15] {
            let (_, _, expected) = walk(4, position);
            let (_, root) = trace_of(4, position, 10);
            assert_eq!(root, expected, "position {position}");
        }
        let (_, _, at_zero) = walk(4, 0);
        let (_, _, at_one) = walk(4, 1);
        assert_ne!(at_zero, at_one, "a bit of the position moves the root");
    }

    #[test]
    fn the_trace_of_a_walk_satisfies_its_description() {
        for position in [0u64, 1, 6, 13] {
            let held = description_of_a_walk(4, 10).expect("a lawful height");
            held.check().expect("the description stands");
            let (commitment, _, _) = walk(4, position);
            let (trace, root) = trace_of(4, position, 10);
            let public = poseidon::limbs_of(&public_of(&commitment, &root, position));
            assert!(held.satisfied_by(&trace, &public), "position {position}");
        }
    }

    #[test]
    fn a_position_the_walk_was_not_made_at_is_not_satisfied() {
        // The accumulator is what binds the two: a walk made at one position and offered at
        // another fails where the bits are summed, not where the root is compared.
        let held = description_of_a_walk(4, 10).expect("a lawful height");
        let (commitment, _, _) = walk(4, 6);
        let (trace, root) = trace_of(4, 6, 10);
        let public = poseidon::limbs_of(&public_of(&commitment, &root, 7));
        assert!(!held.satisfied_by(&trace, &public));
    }

    #[test]
    fn a_root_the_walk_does_not_reach_is_not_satisfied() {
        let held = description_of_a_walk(4, 10).expect("a lawful height");
        let (commitment, _, _) = walk(4, 6);
        let (trace, root) = trace_of(4, 6, 10);
        let mut bytes = public_of(&commitment, &root, 6);
        bytes[CAPACITY * 8] ^= 1;
        assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&bytes)));
    }

    #[test]
    fn a_pair_ordered_against_its_bit_is_not_satisfied() {
        // The two rules of the left, exercised where they bite: a trace that swapped the pair of
        // one level while leaving the bit as it was.
        let held = description_of_a_walk(4, 10).expect("a lawful height");
        let (commitment, _, _) = walk(4, 6);
        let (mut trace, root) = trace_of(4, 6, 10);
        let public = poseidon::limbs_of(&public_of(&commitment, &root, 6));
        assert!(held.satisfied_by(&trace, &public));
        let seam = sponge::blocks_of(CAPACITY) * period() - 1;
        for j in 0..CAPACITY {
            let held_left = trace[LEFT + j][seam];
            trace[LEFT + j][seam] = trace[SIBLING + j][seam];
            trace[SIBLING + j][seam] = held_left;
        }
        assert!(!held.satisfied_by(&trace, &public));
    }

    #[test]
    fn a_walk_is_proven_and_verified_as_bytes() {
        let held = description_of_a_walk(4, 10).expect("a lawful height");
        let (commitment, _, _) = walk(4, 11);
        let (trace, root) = trace_of(4, 11, 10);
        let public = public_of(&commitment, &root, 11);
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true walk proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));
        let other = public_of(&commitment, &root, 10);
        assert!(crate::scheme::verify(&held, &other, &bytes).is_err());
    }
}
