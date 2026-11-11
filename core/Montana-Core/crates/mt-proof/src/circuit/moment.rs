// The moment a right is taken at, as a constraint set: the second squeeze of the right's own
// nullifier chain is the delay it drew, and the window of the frame equals the right's window
// plus that delay's low word modulo the spread. Nothing here is chosen — a person chooses
// nothing about the moment, so nothing about the choice can be read — and nothing here runs for
// a note: every rule is gated by the right half of the moment's split, and the witnesses of a
// note's rows are zeros.
//
// **The five witnesses, and why five.** The drawn word is the low half of one field element, so
// the element is opened as `high · 2³² + drawn` with both halves ranged — without the range on
// `drawn` the split of the element is not unique, and a prover shifts mass between the halves to
// move the remainder. The division is `drawn = q · spread + r` with `q` ranged and `r` held below
// the spread exactly — by the fifth witness `s` with `r + s = spread − 1`, since a power-of-two
// range on `r` alone would admit remainders the division never yields, and two `(q, r)` readings
// of one word are two moments of one right.

use super::sponge::{factor, term};
use crate::air::{Constraint, Periodic};
use crate::field::F;

mt_codec::constants! {
    MOMENT:
    /// The five ranged witnesses of the moment, in the order their columns stand: the high half
    /// of the drawn element, the drawn word itself, the quotient, the remainder, and the
    /// remainder's complement to the spread.
    pub const HIGH: usize = 0, code "the column of this layout holding the high half of the drawn element";
    pub const DRAWN: usize = 1, code "the column of this layout holding the drawn word";
    pub const QUOTIENT: usize = 2, code "the column of this layout holding the quotient of the division by the spread";
    pub const REMAINDER: usize = 3, code "the column of this layout holding the remainder of that division";
    pub const COMPLEMENT: usize = 4, code "the column of this layout holding the remainder's complement to the spread";
    pub const COLUMN_COUNT: usize = 5, code "the count of the columns this layout adds";
    /// The bits each witness is decomposed into. The element halves are words of four bytes; the
    /// quotient is bounded by the word over the spread; the remainder and its complement stand
    /// below the spread, whose bits these are.
    pub const BITS_OF_A_WORD: usize = 32, code "the bits of a four-byte word, which both halves of an element stand below";
    pub const BITS_OF_A_QUOTIENT: usize = 22, code "the least bits above the word over the spread, which the quotient stands below";
    pub const BITS_OF_A_REMAINDER: usize = 11, code "the least bits above the spread, which the remainder and its complement stand below";
}

pub const BITS: [usize; COLUMN_COUNT] = [
    BITS_OF_A_WORD,
    BITS_OF_A_WORD,
    BITS_OF_A_QUOTIENT,
    BITS_OF_A_REMAINDER,
    BITS_OF_A_REMAINDER,
];

// Where the five columns stand, after the layers below.
pub struct Places {
    pub first: usize,
}

impl Places {
    pub const fn after(width: usize) -> Self {
        Self { first: width }
    }

    pub const fn column(&self, which: usize) -> usize {
        self.first + which
    }

    pub const fn width(&self) -> usize {
        self.first + COLUMN_COUNT
    }
}

// The rows a witness's decomposition occupies inside one redemption: runs laid end to end in the
// last block of the walk, each ending where its accumulator's value is complete and holds.
pub fn range_rows(nullifier_first_row: usize, which: usize) -> Vec<usize> {
    let mut start = nullifier_first_row - BITS.iter().sum::<usize>() - 1;
    for bits in BITS.iter().take(which) {
        start += bits;
    }
    (start..start + BITS[which]).collect()
}

// The schedules of the five decompositions and the clearing of the accumulators, across every
// redemption of a frame: five range columns and one clear column, all of the description.
pub fn periodic_columns(
    rows_log2: u8,
    nullifier_first_rows: &[usize],
    clear_rows: &[usize],
) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut out = Vec::new();
    for which in 0..COLUMN_COUNT {
        let mut values = vec![0u64; rows];
        for first in nullifier_first_rows {
            for row in range_rows(*first, which) {
                if row < rows {
                    values[row] = 1;
                }
            }
        }
        out.push(Periodic {
            period_log2: rows_log2,
            values,
        });
    }
    let mut values = vec![0u64; rows];
    for row in clear_rows {
        if *row < rows {
            values[*row] = 1;
        }
    }
    out.push(Periodic {
        period_log2: rows_log2,
        values,
    });
    out
}

// Every rule of the moment. The accumulators double and take the shared bit on their own rows,
// hold everywhere else, and are cleared where a redemption ends; the three equations stand at the
// last row of the right's nullifier chain, gated by the right half of the moment's split.
#[allow(clippy::too_many_arguments)]
pub fn constraints(
    places: &Places,
    bit: usize,
    ranges_at: usize,
    clear: usize,
    halves: &super::branch::Halves,
    delay_cell: usize,
    spread: u64,
) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let mut out = Vec::new();
    for which in 0..COLUMN_COUNT {
        let acc = places.column(which);
        let range = ranges_at + which;
        // The accumulator: doubles and takes the bit where its range stands, holds elsewhere,
        // and is emptied where a redemption closes — so a value of one right never leaks into
        // the equations of the next.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(acc, 1, 1)]),
                term(minus, vec![factor(acc, 0, 1)]),
                term(F::ONE, vec![factor(clear, 0, 1), factor(acc, 0, 1)]),
                term(minus, vec![factor(range, 0, 1), factor(acc, 0, 1)]),
                term(minus, vec![factor(range, 0, 1), factor(bit, 0, 1)]),
            ],
        });
    }
    let two_to_32 = F::from_u64_reduced(1u64 << BITS_OF_A_WORD);
    // The element the delay stands in is its two ranged halves and nothing else.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(halves.right, 0, 1), factor(delay_cell, 0, 1)],
            ),
            term(
                two_to_32.negated(),
                vec![
                    factor(halves.right, 0, 1),
                    factor(places.column(HIGH), 0, 1),
                ],
            ),
            term(
                minus,
                vec![
                    factor(halves.right, 0, 1),
                    factor(places.column(DRAWN), 0, 1),
                ],
            ),
        ],
    });
    // The drawn word is the quotient times the spread plus the remainder.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![
                    factor(halves.right, 0, 1),
                    factor(places.column(DRAWN), 0, 1),
                ],
            ),
            term(
                F::from_u64_reduced(spread).negated(),
                vec![
                    factor(halves.right, 0, 1),
                    factor(places.column(QUOTIENT), 0, 1),
                ],
            ),
            term(
                minus,
                vec![
                    factor(halves.right, 0, 1),
                    factor(places.column(REMAINDER), 0, 1),
                ],
            ),
        ],
    });
    // And the remainder stands below the spread exactly: with its complement it sums to the
    // spread less one, both ranged, so no second reading of the division exists.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![
                    factor(halves.right, 0, 1),
                    factor(places.column(REMAINDER), 0, 1),
                ],
            ),
            term(
                F::ONE,
                vec![
                    factor(halves.right, 0, 1),
                    factor(places.column(COMPLEMENT), 0, 1),
                ],
            ),
            term(
                F::from_u64_reduced(spread - 1).negated(),
                vec![factor(halves.right, 0, 1)],
            ),
        ],
    });
    out
}

// The witnesses of one right written into the columns: the bits into the shared bit column, the
// accumulators built over them and held to the row the equations read.
pub fn write_moment(
    columns: &mut [Vec<F>],
    places: &Places,
    bit: usize,
    nullifier_first_row: usize,
    hold_until: usize,
    delay_element: u64,
    spread: u64,
) {
    let drawn = delay_element & 0xFFFF_FFFF;
    let values = [
        delay_element >> BITS_OF_A_WORD,
        drawn,
        drawn / spread,
        drawn % spread,
        (spread - 1) - drawn % spread,
    ];
    for which in 0..COLUMN_COUNT {
        let rows = range_rows(nullifier_first_row, which);
        let mut held = 0u64;
        for (at, row) in rows.iter().enumerate() {
            let value_bit = (values[which] >> (BITS[which] - 1 - at)) & 1;
            columns[bit][*row] = F::from_u64_reduced(value_bit);
            held = 2 * held + value_bit;
            columns[places.column(which)][row + 1] = F::from_u64_reduced(held);
        }
        let complete = rows.last().map(|row| row + 1).unwrap_or(0);
        let held_value = F::from_u64_reduced(values[which]);
        for cell in columns[places.column(which)]
            .iter_mut()
            .take(hold_until + 1)
            .skip(complete)
        {
            *cell = held_value;
        }
    }
}
