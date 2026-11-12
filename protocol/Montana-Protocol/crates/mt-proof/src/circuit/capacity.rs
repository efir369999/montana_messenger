// Where a chain opens under its domain: the wiring that sets the capacity cells of the state at a
// seam to the capacity of the domain the chain opens under.
//
// A sponge of this family is its domain before it is anything else — the capacity cells start at
// the first four limbs of the domain\'s empty hash, and a chain wired to the wrong domain computes
// a value of the wrong family byte for byte. The frame wires its capacities through the branch
// machinery of a redemption, because its chains fork two ways; a circuit whose chains do not fork
// needs only this: a mark at every seam a chain opens at, four periodic columns carrying the limbs
// the domain answers, and four rules holding the state\'s capacity cells to them one row on.

use super::permutation::ring_column;
use super::sponge::{factor, term};
use crate::air::{Constraint, Periodic};
use crate::field::F;
use crate::poseidon::{self, CAPACITY, RATE};
use mt_codec::Domain;

mt_codec::constants! {
    CAPACITIES:
    /// Where the mark of an opening stands among the periodic columns this layout adds.
    pub const MARK: usize = 0, code "the periodic column of this layout marking a seam a chain opens at";
    /// The value columns follow the mark, one per capacity cell.
    pub const PERIODIC_COUNT: usize = 5, code "the count of the periodic columns this layout adds: the mark, and one value column per capacity cell";
}

// The five columns of the schedule, from the seams and the domain each opens under.
pub fn periodic_columns(rows_log2: u8, opens: &[(usize, Domain)]) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut mark = vec![0u64; rows];
    let mut values = vec![vec![0u64; rows]; CAPACITY];
    for (seam, domain) in opens {
        if *seam >= rows {
            continue;
        }
        mark[*seam] = 1;
        let limbs = poseidon::capacity_of(*domain);
        for (cell, limb) in limbs.iter().enumerate() {
            values[cell][*seam] = limb.as_u64();
        }
    }
    let mut out = Vec::with_capacity(PERIODIC_COUNT);
    out.push(Periodic {
        period_log2: rows_log2,
        values: mark,
    });
    for column in values {
        out.push(Periodic {
            period_log2: rows_log2,
            values: column,
        });
    }
    out
}

// The four rules: at a marked seam, each capacity cell of the state one row on equals the value
// column\'s limb. Everywhere unmarked the rule is empty, so nothing is spent gating it further.
pub fn constraints(periodic_base: usize) -> Vec<Constraint> {
    let mark = periodic_base + MARK;
    let minus = F::ONE.negated();
    (0..CAPACITY)
        .map(|cell| Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![factor(mark, 0, 1), factor(ring_column(RATE + cell), 1, 1)],
                ),
                term(
                    minus,
                    vec![factor(mark, 0, 1), factor(periodic_base + 1 + cell, 0, 1)],
                ),
            ],
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_codec::domain;

    #[test]
    fn the_schedule_carries_the_domain_a_chain_opens_under() {
        let columns = periodic_columns(4, &[(3, domain::MT_RECORD_LEAF)]);
        assert_eq!(columns.len(), PERIODIC_COUNT);
        assert_eq!(columns[MARK].values[3], 1);
        let limbs = poseidon::capacity_of(domain::MT_RECORD_LEAF);
        for cell in 0..CAPACITY {
            assert_eq!(columns[1 + cell].values[3], limbs[cell].as_u64());
            assert_eq!(columns[1 + cell].values[4], 0);
        }
    }

    #[test]
    fn two_domains_at_two_seams_stand_apart() {
        let columns = periodic_columns(
            4,
            &[(1, domain::MT_RECORD_NODE), (5, domain::MT_ADMITTED_NODE)],
        );
        let one = poseidon::capacity_of(domain::MT_RECORD_NODE);
        let two = poseidon::capacity_of(domain::MT_ADMITTED_NODE);
        assert_ne!(one, two);
        for cell in 0..CAPACITY {
            assert_eq!(columns[1 + cell].values[1], one[cell].as_u64());
            assert_eq!(columns[1 + cell].values[5], two[cell].as_u64());
        }
    }

    #[test]
    fn every_rule_stands_within_the_degree_the_scheme_admits() {
        for rule in constraints(90) {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
            for held in &rule.terms {
                let power: u8 = held.factors.iter().map(|f| f.power).sum();
                assert!(power <= crate::params::DEGREE_BOUND);
            }
        }
        assert_eq!(constraints(90).len(), CAPACITY);
    }
}
