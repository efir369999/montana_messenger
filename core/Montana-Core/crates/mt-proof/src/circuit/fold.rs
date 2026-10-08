// One step of the accumulation, as arithmetic a constraint set can assert: a lane takes the
// accumulator's coefficient, folds the instance's under a scalar challenge, and reaches the
// coefficient of the next accumulator, the reduction witnessed with both halves held in range.
//
// **Why the challenge is a scalar of the modulus and not a bit.** The argument that carries the
// accumulation counts instead of extracting, and a count asks nothing of a short inverse — what it
// asks is that the challenge is never zero (a zero drops the window it weighs) and that it is drawn
// after the instances are committed. A scalar carries the twenty-three bits of the modulus, so six
// folds in parallel stand past the security target where bits would need a hundred and twenty-eight
// — and six accumulators are what a window publishes and a proof binds, not a hundred and
// twenty-eight. The never-zero is the transcript's rule, not a rule here: the challenge is drawn
// and redrawn natively by prover and verifier alike, and arrives bound as a public value.
//
// **The bounds of a lane.** The values live lazily below two to the twenty-third — congruent, not
// canonical — and the challenge below the modulus, so `taken + c folded` stands below two to the
// forty-seventh, the quotient below two to the twenty-fourth, and nothing wraps the field. The
// reached coefficient is held below two to the twenty-third by its own bits, which is what lets the
// next fold take it.

use super::sponge::{factor, term};
use crate::air::{Constraint, Periodic};
use crate::field::F;

mt_codec::constants! {
    FOLD:
    /// Where the schedule of this layout stands among the periodic columns it adds.
    pub const COPY: usize = 0, code "the periodic column of this layout marking the rows a challenge is carried across";
    pub const PERIODIC_COUNT: usize = 1, code "the count of the periodic columns this layout adds";
    /// The modulus of the lattice the accumulation folds over: the ring of the commitment that
    /// carries standing, and the number the two bit-counts below are derived from. It stands in a
    /// register rather than as a literal at the caller because a number the gate does not compare
    /// is a number that can drift from the one the commitment actually lives in — and a fold
    /// asserted over the wrong ring proves nothing about the accumulator it claims to fold.
    pub const MODULUS: u64 = 8_380_417, writes "q = 8 380 417";
    /// The bits the quotient of a lane is held below: a sum below two to the forty-seventh, over the modulus.
    pub const QUOTIENT_BITS: usize = 24, code "the bits the quotient of a lane of a fold is held below";
    /// The bits a reached coefficient is held below, lazily: congruent, not canonical.
    pub const VALUE_BITS: usize = 23, code "the bits a coefficient of the accumulator is held below";
    /// The columns one lane costs: taken, folded, the quotient's bits, the reached value's bits and
    /// the reached value itself, recomposed so a boundary can bind one cell of it.
    pub const COLUMNS_OF_A_LANE: usize = 50, code "the columns one lane of a fold costs: the coefficient taken, the coefficient folded, the bits of the quotient, the bits of the coefficient reached and the reached coefficient recomposed";
    /// The repetitions of the fold a window runs in parallel.
    pub const REPETITIONS: usize = 6, code "the parallel repetitions of the fold: six times the bits of the modulus stands past the security target";
}

// The columns this layer adds after those below it: the challenge the phase reads, and the lanes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Places {
    pub challenge: usize,
    pub lane: usize,
    pub lanes: usize,
}

impl Places {
    pub const fn after(width: usize, lanes: usize) -> Self {
        Self {
            challenge: width,
            lane: width + 1,
            lanes,
        }
    }

    pub const fn taken(&self, lane: usize) -> usize {
        self.lane + lane * COLUMNS_OF_A_LANE
    }

    pub const fn folded(&self, lane: usize) -> usize {
        self.taken(lane) + 1
    }

    pub const fn quotient_bit(&self, lane: usize, bit: usize) -> usize {
        self.taken(lane) + 2 + bit
    }

    pub const fn reached_bit(&self, lane: usize, bit: usize) -> usize {
        self.taken(lane) + 2 + QUOTIENT_BITS + bit
    }

    pub const fn reached(&self, lane: usize) -> usize {
        self.taken(lane) + 2 + QUOTIENT_BITS + VALUE_BITS
    }

    pub const fn width(&self) -> usize {
        self.lane + self.lanes * COLUMNS_OF_A_LANE
    }
}

// How many lanes a row of a given width holds after the layers below have taken theirs: one column
// of what is left goes to the challenge and the rest divide by what a lane costs.
pub fn lanes_in(width: usize, taken: usize) -> usize {
    width.saturating_sub(taken).saturating_sub(1) / COLUMNS_OF_A_LANE
}

// How many rows the folds of a window take: the repetitions ride one after another, each over the
// coefficients of the instance, at this many lanes to a row. The ceiling of a division stands in
// the shape the set names for it.
pub fn rows_of(coefficients: usize, lanes: usize) -> usize {
    if lanes == 0 || coefficients == 0 {
        return 0;
    }
    REPETITIONS * coefficients.div_ceil(lanes)
}

// The one column of the schedule this layer adds: the rows a challenge is carried across, which is
// every row of a repetition but its last.
pub fn periodic_columns(rows_log2: u8, carried: &[usize]) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut copy = vec![0u64; rows];
    for at in carried {
        if *at < rows {
            copy[*at] = 1;
        }
    }
    vec![Periodic {
        period_log2: rows_log2,
        values: copy,
    }]
}

// Every rule this layer adds: the challenge is carried across the rows the schedule marks, each bit
// is a bit, and a lane's one equality — reached = taken + challenge times folded, less the modulus
// as many times as the quotient says. An all-zero row satisfies every rule, so idle rows are idle
// with no gate spent on them.
pub fn constraints(periodic_base: usize, places: &Places, modulus: u64) -> Vec<Constraint> {
    let copy = periodic_base + COPY;
    let minus = F::ONE.negated();
    let mut out = Vec::with_capacity(1 + places.lanes * (QUOTIENT_BITS + VALUE_BITS + 1));

    // The challenge of the row below is the challenge of this one, where the schedule carries it.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(copy, 0, 1), factor(places.challenge, 1, 1)],
            ),
            term(
                minus,
                vec![factor(copy, 0, 1), factor(places.challenge, 0, 1)],
            ),
        ],
    });

    for lane in 0..places.lanes {
        for bit in 0..QUOTIENT_BITS {
            let column = places.quotient_bit(lane, bit);
            out.push(Constraint {
                degree: 2,
                terms: vec![
                    term(F::ONE, vec![factor(column, 0, 2)]),
                    term(minus, vec![factor(column, 0, 1)]),
                ],
            });
        }
        for bit in 0..VALUE_BITS {
            let column = places.reached_bit(lane, bit);
            out.push(Constraint {
                degree: 2,
                terms: vec![
                    term(F::ONE, vec![factor(column, 0, 2)]),
                    term(minus, vec![factor(column, 0, 1)]),
                ],
            });
        }
        // taken + challenge times folded, less the modulus times the quotient, less the reached
        // value: empty. The recompositions are linear, so the row is one equality of degree two.
        let mut held = vec![
            term(F::ONE, vec![factor(places.taken(lane), 0, 1)]),
            term(
                F::ONE,
                vec![
                    factor(places.challenge, 0, 1),
                    factor(places.folded(lane), 0, 1),
                ],
            ),
        ];
        for bit in 0..QUOTIENT_BITS {
            held.push(term(
                F::from_u64_reduced(modulus << bit).negated(),
                vec![factor(places.quotient_bit(lane, bit), 0, 1)],
            ));
        }
        for bit in 0..VALUE_BITS {
            held.push(term(
                F::from_u64_reduced(1u64 << bit).negated(),
                vec![factor(places.reached_bit(lane, bit), 0, 1)],
            ));
        }
        out.push(Constraint {
            degree: 2,
            terms: held,
        });
        // And the reached value, recomposed from its bits into one cell a boundary can bind.
        let mut tie = vec![term(F::ONE, vec![factor(places.reached(lane), 0, 1)])];
        for bit in 0..VALUE_BITS {
            tie.push(term(
                F::from_u64_reduced(1u64 << bit).negated(),
                vec![factor(places.reached_bit(lane, bit), 0, 1)],
            ));
        }
        out.push(Constraint {
            degree: 1,
            terms: tie,
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_lane_costs_its_two_values_and_the_bits_of_both_halves() {
        let places = Places::after(10, 1);
        assert_eq!(places.challenge, 10);
        assert_eq!(places.taken(0), 11);
        assert_eq!(places.folded(0), 12);
        assert_eq!(places.quotient_bit(0, 0), 13);
        assert_eq!(places.reached_bit(0, 0), 13 + QUOTIENT_BITS);
        assert_eq!(places.reached(0), 13 + QUOTIENT_BITS + VALUE_BITS);
        assert_eq!(places.width(), 11 + COLUMNS_OF_A_LANE);
        assert_eq!(COLUMNS_OF_A_LANE, 3 + QUOTIENT_BITS + VALUE_BITS);
    }

    #[test]
    fn a_width_holds_what_is_left_of_it_after_the_challenge() {
        assert_eq!(lanes_in(62, 0), 1);
        assert_eq!(lanes_in(62, 11), 1);
        assert_eq!(lanes_in(62, 12), 0);
        assert_eq!(lanes_in(51, 0), 1);
        assert_eq!(lanes_in(50, 0), 0);
    }

    #[test]
    fn the_rows_of_the_folds_are_six_runs_over_the_coefficients() {
        assert_eq!(rows_of(1536, 1), 6 * 1536);
        assert_eq!(rows_of(0, 1), 0);
        assert_eq!(rows_of(12, 0), 0);
    }

    #[test]
    fn every_rule_stands_within_the_degree_the_scheme_admits() {
        let places = Places::after(4, 1);
        for rule in constraints(20, &places, 8_380_417) {
            assert!(rule.degree <= crate::params::DEGREE_BOUND, "{rule:?}");
            for held in &rule.terms {
                let power: u8 = held.factors.iter().map(|f| f.power).sum();
                assert!(power <= crate::params::DEGREE_BOUND, "{held:?}");
            }
        }
    }

    #[test]
    fn a_lane_carries_a_rule_per_bit_and_one_equality_and_the_challenge_its_carry() {
        let places = Places::after(4, 1);
        let rules = constraints(20, &places, 8_380_417);
        assert_eq!(rules.len(), 1 + QUOTIENT_BITS + VALUE_BITS + 2);
    }

    #[test]
    fn an_honest_lane_satisfies_the_equality_by_hand() {
        let q: u64 = 8_380_417;
        let taken: u64 = 7_000_000;
        let folded: u64 = 6_500_000;
        let challenge: u64 = 5_000_003;
        let sum = taken as u128 + challenge as u128 * folded as u128;
        let quotient = sum / q as u128;
        let reached = sum % q as u128;
        assert!(quotient < 1 << QUOTIENT_BITS);
        assert!(reached < 1 << VALUE_BITS);
        assert_eq!(sum, q as u128 * quotient + reached);
    }
}
