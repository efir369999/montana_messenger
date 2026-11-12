// A lane of one digest: four columns that pick a value out of the state at one seam and hand it to
// an absorption at another, holding it unchanged across every row between.
//
// The walk\'s level rules carry a squeeze into the block that stands next; a lane exists for the
// value that must reach a block that does not stand next. The frame ferries two digests through the
// lane of a redemption; a circuit that must ferry one needs only this — and a value that is loaded,
// held and wired is asserted equal at both ends by construction, with nothing about it trusted to
// the prover between them.

use super::permutation::ring_column;
use super::sponge::{factor, term};
use crate::air::{Constraint, Periodic};
use crate::field::F;
use crate::poseidon::CAPACITY;

mt_codec::constants! {
    LANE:
    /// Where the marks of a lane stand among the periodic columns this layout adds.
    pub const LOAD: usize = 0, code "the periodic column of this layout marking the seam a lane picks its digest up at";
    pub const WIRE: usize = 1, code "the periodic column of this layout marking the seam a lane hands its digest to an absorption at";
    pub const PERIODIC_COUNT: usize = 2, code "the count of the periodic columns this layout adds";
}

// The four columns of the lane, standing after the layers below.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Places {
    pub first: usize,
}

impl Places {
    pub const fn after(width: usize) -> Self {
        Self { first: width }
    }

    pub const fn cell(&self, cell: usize) -> usize {
        self.first + cell
    }

    pub const fn width(&self) -> usize {
        self.first + CAPACITY
    }
}

// The two columns of the schedule.
pub fn periodic_columns(rows_log2: u8, loads: &[usize], wires: &[usize]) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut load = vec![0u64; rows];
    let mut wire = vec![0u64; rows];
    for at in loads {
        if *at < rows {
            load[*at] = 1;
        }
    }
    for at in wires {
        if *at < rows {
            wire[*at] = 1;
        }
    }
    vec![
        Periodic {
            period_log2: rows_log2,
            values: load,
        },
        Periodic {
            period_log2: rows_log2,
            values: wire,
        },
    ]
}

// Every rule of a lane, per cell: away from a load the lane holds, at a load it takes the digest
// out of the state one row on, and at a wire the rate of the next block takes the lane.
pub fn constraints(periodic_base: usize, places: &Places) -> Vec<Constraint> {
    let load = periodic_base + LOAD;
    let wire = periodic_base + WIRE;
    let minus = F::ONE.negated();
    let mut out = Vec::with_capacity(CAPACITY * 3);
    for cell in 0..CAPACITY {
        let lane = places.cell(cell);
        // The lane holds: lane one row on equals the lane, wherever no load stands.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(lane, 1, 1)]),
                term(minus, vec![factor(lane, 0, 1)]),
                term(minus, vec![factor(load, 0, 1), factor(lane, 1, 1)]),
                term(F::ONE, vec![factor(load, 0, 1), factor(lane, 0, 1)]),
            ],
        });
        // At a load, the lane one row on is the digest cell of the state at the seam.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(load, 0, 1), factor(lane, 1, 1)]),
                term(
                    minus,
                    vec![factor(load, 0, 1), factor(ring_column(cell), 0, 1)],
                ),
            ],
        });
        // At a wire, the rate cell of the block one row on is the lane.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![factor(wire, 0, 1), factor(ring_column(cell), 1, 1)],
                ),
                term(minus, vec![factor(wire, 0, 1), factor(lane, 0, 1)]),
            ],
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_lane_costs_four_columns() {
        let places = Places::after(58);
        assert_eq!(places.cell(0), 58);
        assert_eq!(places.width(), 58 + CAPACITY);
    }

    #[test]
    fn the_schedule_marks_the_two_seams() {
        let columns = periodic_columns(4, &[3], &[9]);
        assert_eq!(columns.len(), PERIODIC_COUNT);
        assert_eq!(columns[LOAD].values[3], 1);
        assert_eq!(columns[WIRE].values[9], 1);
        assert_eq!(columns[LOAD].values[9], 0);
    }

    #[test]
    fn every_rule_stands_within_the_degree_the_scheme_admits() {
        let places = Places::after(58);
        let rules = constraints(90, &places);
        assert_eq!(rules.len(), CAPACITY * 3);
        for rule in rules {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
            for held in &rule.terms {
                let power: u8 = held.factors.iter().map(|f| f.power).sum();
                assert!(power <= crate::params::DEGREE_BOUND);
            }
        }
    }
}
