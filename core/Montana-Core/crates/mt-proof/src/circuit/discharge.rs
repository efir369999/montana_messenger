// The discharge of a fold: a number returned to the size of a digit by its bits, held a row at a
// time rather than a bit at a time.
//
// **Why not the range that already stands here.** That one answers a different question — it carries
// an accumulation alongside its bit and spends a row for every bit, which is right where a frame
// holds three amounts and wrong where a window holds the randomness of a fold. The randomness of a
// fold is tens of thousands of bits; a row apiece is half the height the memory of a device admits,
// and eight parts in a thousand of it is what the count of a step assumed. The difference is not a
// wall — both fit — it is the difference between a step that leaves room for the rest of a circuit
// and one that leaves almost none.
//
// **Why a row of booleans costs a row and not a column each of height.** A boolean is a boolean by a
// rule that touches only the column holding it, so a row may hold as many as the width allows and
// each is held by its own rule at that row. What recomposes them is one rule naming the whole row,
// and a rule may name as many columns as it likes. So the wide shape is writable, and this module is
// where it is written.
//
// **What a row says.** The accumulator of a row is the accumulator of the row above shifted by the
// count of lanes and taking this row's bits, most significant first. Where the schedule marks no
// discharge the accumulator is empty, so a run opens at zero without a boundary saying so — the same
// convention the range beside it takes. Where the schedule marks a tie, the accumulator is the value
// the discharge was of.

use super::sponge::{factor, term};
use crate::air::{Constraint, Periodic};
use crate::field::F;

mt_codec::constants! {
    DISCHARGE:
    /// Where the schedule of a discharge stands among the periodic columns this layout adds.
    pub const RUN: usize = 0, code "the periodic column of this layout marking a row of a discharge";
    pub const TIE: usize = 1, code "the periodic column of this layout marking where a discharge meets the value it is of";
    pub const PERIODIC_COUNT: usize = 2, code "the count of the periodic columns this layout adds";
}

// The columns this layer adds after those below it: the lanes of a row, and the number they reach.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Places {
    pub lane: usize,
    pub lanes: usize,
    pub reached: usize,
}

impl Places {
    pub const fn after(width: usize, lanes: usize) -> Self {
        Self {
            lane: width,
            lanes,
            reached: width + lanes,
        }
    }

    pub const fn at(&self, lane: usize) -> usize {
        self.lane + lane
    }

    pub const fn width(&self) -> usize {
        self.reached + 1
    }
}

// How many rows a value of this many bits takes, at this many lanes to a row. A value whose bits do
// not fill the last row is held by the same rules: the lanes above it are zero, which is a boolean,
// and they add nothing to what the row reaches.
pub fn rows_of(bits: usize, lanes: usize) -> usize {
    if lanes == 0 {
        return 0;
    }
    // The ceiling of a division, in the shape the set names for it, so nothing rests on which way a
    // library rounds.
    bits.div_ceil(lanes)
}

// Which rows a discharge occupies: the rows before the row its value is read at, so a run ends
// exactly where it is read — the convention the range beside it takes, and one convention is what
// keeps a reader from having to hold two.
pub fn run_rows(tie: usize, bits: usize, lanes: usize) -> Vec<usize> {
    let rows = rows_of(bits, lanes);
    (tie.saturating_sub(rows)..tie).collect()
}

// The two columns of the schedule this layer adds, in the order a description carries them.
pub fn periodic_columns(rows_log2: u8, ties: &[usize], bits: usize, lanes: usize) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut run = vec![0u64; rows];
    let mut tie = vec![0u64; rows];
    for at in ties {
        if *at >= rows {
            continue;
        }
        tie[*at] = 1;
        for row in run_rows(*at, bits, lanes) {
            run[row] = 1;
        }
    }
    [run, tie]
        .into_iter()
        .map(|values| Periodic {
            period_log2: rows_log2,
            values,
        })
        .collect()
}

// Every rule this layer adds: one that a lane is a boolean, one that a row carries the number
// forward, and one that a tie reads it. The column a tie reads against arrives by its number, since
// what a discharge is of belongs to the layer that asked for it and not to this one.
pub fn constraints(periodic_base: usize, places: &Places, read_against: usize) -> Vec<Constraint> {
    let run = periodic_base + RUN;
    let tie = periodic_base + TIE;
    let minus = F::ONE.negated();
    let mut out = Vec::with_capacity(places.lanes + 2);

    // A lane is a boolean, wherever it stands. One rule per lane, each touching its own column and
    // nothing else, which is the whole reason a row may be wide.
    for lane in 0..places.lanes {
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(places.at(lane), 0, 2)]),
                term(minus, vec![factor(places.at(lane), 0, 1)]),
            ],
        });
    }

    // The number a run reaches: it shifts by the count of lanes and takes this row's lanes, the
    // first lane weighing most. Where the schedule marks no run it is empty, so a run opens at zero
    // and no boundary is spent saying so.
    let shift = F::from_u64_reduced(1u64 << places.lanes.min(63));
    let mut carry = vec![
        term(F::ONE, vec![factor(places.reached, 1, 1)]),
        term(
            shift.negated(),
            vec![factor(run, 0, 1), factor(places.reached, 0, 1)],
        ),
    ];
    for lane in 0..places.lanes {
        let weight = F::from_u64_reduced(1u64 << (places.lanes - 1 - lane).min(63));
        carry.push(term(
            weight.negated(),
            vec![factor(run, 0, 1), factor(places.at(lane), 0, 1)],
        ));
    }
    out.push(Constraint {
        degree: 2,
        terms: carry,
    });

    // Where a discharge meets the value it is of: what the run reached is that value, and nothing is
    // said of this column anywhere else.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(tie, 0, 1), factor(places.reached, 0, 1)],
            ),
            term(minus, vec![factor(tie, 0, 1), factor(read_against, 0, 1)]),
        ],
    });
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_row_of_lanes_costs_one_column_each_and_one_for_the_number() {
        let places = Places::after(10, 62);
        assert_eq!(places.at(0), 10);
        assert_eq!(places.at(61), 71);
        assert_eq!(places.width(), 73);
    }

    #[test]
    fn the_rows_of_a_discharge_are_its_bits_over_its_lanes() {
        assert_eq!(rows_of(67584, 62), 1091);
        assert_eq!(rows_of(62, 62), 1);
        assert_eq!(rows_of(63, 62), 2);
        assert_eq!(rows_of(0, 62), 0);
        assert_eq!(rows_of(10, 0), 0);
    }

    #[test]
    fn a_run_ends_at_the_row_its_value_is_read_at() {
        let rows = run_rows(100, 62 * 3, 62);
        assert_eq!(rows, vec![97, 98, 99]);
        assert!(run_rows(1, 62 * 3, 62).len() <= 1);
    }

    #[test]
    fn every_lane_is_held_by_a_rule_of_its_own() {
        let places = Places::after(4, 8);
        let rules = constraints(20, &places, 3);
        assert_eq!(rules.len(), 8 + 2);
        for (lane, rule) in rules.iter().enumerate().take(8) {
            assert_eq!(rule.degree, 2);
            assert!(rule.terms.iter().all(|t| t
                .factors
                .iter()
                .all(|f| f.column as usize == places.at(lane))));
        }
    }

    #[test]
    fn the_schedule_marks_the_rows_of_a_run_and_the_row_it_is_read_at() {
        let columns = periodic_columns(4, &[10], 8 * 2, 8);
        assert_eq!(columns.len(), PERIODIC_COUNT);
        let run = &columns[RUN].values;
        let tie = &columns[TIE].values;
        assert_eq!(run[8], 1);
        assert_eq!(run[9], 1);
        assert_eq!(run[10], 0);
        assert_eq!(tie[10], 1);
        assert_eq!(tie[9], 0);
    }
}
