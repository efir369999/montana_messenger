// The disjunction of a note, a right and a filler: a redemption proves one of the three, and which
// of them is not readable from anything a frame publishes.
//
// **Why the third branch costs no column.** A spend carrying no transfer holds filler in every
// position, drawn by its emitter from its own randomness — the set says so, and it is what lets a
// runner prove a frame it cannot read and what lets a machine holding one right and nothing else
// build a frame at all. The filler asserts nothing, so it needs no half to stand under: it **is**
// what remains of the selector when neither of the two is standing, `selector - note - right`.
// Two more rules hold that remainder apart from each of them, and every rule keeps the degree it
// carried. A third column would have widened the trace past the bound the Decree fixes, and with
// it the length of every proof this protocol has — for a branch whose whole content is that
// nothing is asserted.
//
// **Why a bit cannot be multiplied into a rule.** Every wire of a redemption stands under a
// periodic selector, and a rule that took the branch as one more factor would carry degree three
// where the shape admits two. What stands instead is the selector itself, split: two columns of
// the trace whose sum is the periodic selector and whose product is nothing, so at every row one
// of them is the selector and the other is empty. A rule then takes the half that belongs to its
// branch, and the degree it carries is the degree it carried before.
//
// **Why the two branches occupy the same blocks.** A note's redemption walks a tree; a right's
// spends a nullifier and a moment. The blocks are the note's — the longer of the two — and the
// right's rules speak on the same rows, so the count of blocks a frame holds says nothing about
// what it redeemed. What the right leaves unconstrained the note constrains, and the reverse; no
// row is idle in one branch and absent in the other.

use super::sponge::{factor, term};
use crate::air::{Constraint, Periodic};
use crate::field::F;

mt_codec::constants! {
    BRANCH:
    /// The two halves a selector is split into, and the count of columns one split takes.
    pub const NOTE: usize = 0, code "the column of a split carrying the half of a selector the note branch takes";
    pub const RIGHT: usize = 1, code "the column of a split carrying the half the right branch takes";
    pub const COLUMN_COUNT: usize = 2, code "the count of the columns one split adds";
}

// Where the halves stand, after the columns of the layers below. A seam whose rule differs between
// the branches takes a split of its own: a split is two columns against one schedule, and a rule
// gated by a half of it carries the degree it carried before. Two seams cannot share a split, since
// a half is nonzero wherever its schedule is and a rule gated by it fires at every one of those
// rows — which is why the count of splits is the count of seams that differ and not a choice.
pub struct Places {
    pub first: usize,
    pub splits: usize,
}

impl Places {
    pub const fn after(width: usize, splits: usize) -> Self {
        Self {
            first: width,
            splits,
        }
    }

    pub const fn note(&self, at: usize) -> usize {
        self.first + at * COLUMN_COUNT + NOTE
    }

    pub const fn right(&self, at: usize) -> usize {
        self.first + at * COLUMN_COUNT + RIGHT
    }

    pub const fn width(&self) -> usize {
        self.first + self.splits * COLUMN_COUNT
    }
}

// The rules that make the three halves of one split a split of its selector and of nothing else.
pub fn constraints(selector: usize, note: usize, right: usize) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let places = Halves { note, right };
    // The remainder of the selector: what neither of the two halves took, which is the filler.
    let remainder = |with: usize| Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(with, 0, 1), factor(selector, 0, 1)]),
            term(minus, vec![factor(with, 0, 1), factor(places.note, 0, 1)]),
            term(minus, vec![factor(with, 0, 1), factor(places.right, 0, 1)]),
        ],
    };
    vec![
        // Neither half exceeds the selector, and where no selector stands both are empty: the two
        // of them and the remainder are three shares of it, and the rules below leave exactly one
        // of the three standing.
        Constraint {
            degree: 2,
            terms: vec![term(
                F::ONE,
                vec![factor(places.note, 0, 1), factor(places.right, 0, 1)],
            )],
        },
        // The note against the remainder, and the right against it: with the rule above, one of
        // the three is the whole selector and the other two are empty — never a share of it,
        // which is what would let a prover stand in two branches at once.
        remainder(places.note),
        remainder(places.right),
        // And where no selector stands, neither half stands either: without this a prover could
        // write a half at a row no rule reaches and carry it into one that does.
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(places.note, 0, 1)]),
                term(F::ONE, vec![factor(places.right, 0, 1)]),
                term(
                    minus,
                    vec![factor(places.note, 0, 1), factor(selector, 0, 1)],
                ),
                term(
                    minus,
                    vec![factor(places.right, 0, 1), factor(selector, 0, 1)],
                ),
            ],
        },
    ]
}

// The capacity a branch opens its chain with. A boundary is unconditional and therefore cannot tell
// the two branches apart, so what would have been a boundary becomes a rule: where the half of the
// selector belonging to a branch stands, the capacity of that block is the literal of that branch's
// domain. Both halves speak at the same row, and only one of them is standing.
pub fn capacity_of_a_branch(half: usize, capacity_cell: usize, value: F) -> Constraint {
    Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(half, 0, 1), factor(capacity_cell, 1, 1)],
            ),
            term(value.negated(), vec![factor(half, 0, 1)]),
        ],
    }
}

// The same rule where one split serves several rows whose values differ: the value arrives by a
// periodic column instead of a coefficient, so one pair of halves covers the capacity of the leaf,
// of every node of the walk and of the nullifier's chain, at the cost of columns of the
// description and none of the trace.
pub fn capacity_from_a_column(
    half: usize,
    capacity_cell: usize,
    value_column: usize,
) -> Constraint {
    Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(half, 0, 1), factor(capacity_cell, 1, 1)],
            ),
            term(
                F::ONE.negated(),
                vec![factor(half, 0, 1), factor(value_column, 0, 1)],
            ),
        ],
    }
}

// What a branch publishes stands at one place whatever the branch is, so the two of them write
// their digest into the same block — and the rule that ties that digest to the public value is one
// boundary, standing under no branch at all.
// One split, named where a rule takes its halves.
pub struct Halves {
    pub note: usize,
    pub right: usize,
}

// The halves written across the height: the branch of every row that carries a selector, and
// nothing where none does.
pub fn write_halves(
    columns: &mut [Vec<F>],
    places: &Halves,
    selector_rows: &[usize],
    right_rows: &[usize],
    filler_rows: &[usize],
) {
    let rows = columns[places.note].len();
    let mut of_the_right = vec![false; rows];
    for row in right_rows {
        if *row < rows {
            of_the_right[*row] = true;
        }
    }
    let mut of_the_filler = vec![false; rows];
    for row in filler_rows {
        if *row < rows {
            of_the_filler[*row] = true;
        }
    }
    for row in selector_rows {
        if *row < rows {
            // A filler takes neither half: what it stands under is the remainder, and a remainder
            // is written by writing nothing.
            if of_the_filler[*row] {
                continue;
            }
            let column = if of_the_right[*row] {
                places.right
            } else {
                places.note
            };
            columns[column][*row] = F::ONE;
        }
    }
}

// The column of the description the halves are held against: one at every row a rule of a branch
// stands at, and nothing elsewhere.
pub fn selector_column(rows_log2: u8, rows: &[usize]) -> Periodic {
    let count = 1usize << rows_log2;
    let mut values = vec![0u64; count];
    for row in rows {
        if *row < count {
            values[*row] = 1;
        }
    }
    Periodic {
        period_log2: rows_log2,
        values,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::air::{BoundaryValue, Description};

    fn description(rows_log2: u8, selector_rows: &[usize]) -> Description {
        let width = 2usize;
        let places = Halves {
            note: NOTE,
            right: RIGHT,
        };
        let mut held = Description {
            trace_width: width as u16,
            rows_log2,
            periodic: vec![selector_column(rows_log2, selector_rows)],
            constraints: Vec::new(),
            boundaries: Vec::new(),
        };
        held.constraints
            .extend(constraints(width, places.note, places.right));
        held
    }

    fn trace(rows_log2: u8, selector_rows: &[usize], right_rows: &[usize]) -> Vec<Vec<F>> {
        let rows = 1usize << rows_log2;
        let mut columns = vec![vec![F::ZERO; rows]; 2];
        write_halves(
            &mut columns,
            &Halves {
                note: NOTE,
                right: RIGHT,
            },
            selector_rows,
            right_rows,
            &[],
        );
        columns
    }

    #[test]
    fn one_branch_takes_the_whole_selector_and_the_other_is_empty() {
        let selectors = vec![3usize, 9, 20];
        let held = description(8, &selectors);
        held.check().expect("the description stands");
        for right in [vec![], vec![9usize], vec![3usize, 9, 20]] {
            let columns = trace(8, &selectors, &right);
            assert!(held.satisfied_by(&columns, &[]), "{right:?}");
        }
    }

    #[test]
    fn a_prover_standing_in_both_branches_is_refused() {
        // The one thing the product refuses: a row where both halves carry something, which is a
        // redemption claiming a note and a right at once.
        let selectors = vec![3usize];
        let held = description(8, &selectors);
        let mut columns = trace(8, &selectors, &[]);
        // Two shares of a selector, which is exactly what the product refuses.
        let half = F::from_u64_reduced(2).inverse().unwrap_or(F::ZERO);
        columns[NOTE][3] = half;
        columns[RIGHT][3] = half;
        assert!(!held.satisfied_by(&columns, &[]));
    }

    #[test]
    fn a_branch_standing_where_no_selector_does_is_refused() {
        let selectors = vec![3usize];
        let held = description(8, &selectors);
        let mut columns = trace(8, &selectors, &[]);
        columns[NOTE][4] = F::ONE;
        assert!(!held.satisfied_by(&columns, &[]));
        let _ = BoundaryValue::Literal(0);
    }
}
