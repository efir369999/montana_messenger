// What a frame says about amounts: that every value it moves stands below the bound this circuit
// holds them to, and that what a spend creates equals what it consumes.
//
// **Why a bound and not four limbs with carries.** A commitment absorbs an amount as four limbs of
// four bytes, and the field is narrower than two of them together — so a sum of limbs weighted by
// powers of two to the thirty-second wraps, and a wrap is a mint. What stands instead is one
// number: the amount read as `limb0 + 2³² · limb1`, with the two limbs above it held at zero, and
// that number decomposed into bits so it stands below two to the sixty-second. Two such numbers sum
// below two to the sixty-third, which is inside the field — so a balance written as a difference of
// field elements is exact, and nothing about it can wrap.
//
// **What that bound costs, named rather than discovered.** An amount above two to the sixty-second
// is unrepresentable in a frame. The whole emission of this protocol reaches that number after more
// than a hundred thousand years of windows, so what the bound removes is a quantity no chain of
// this network can hold — and what it buys is a balance of one subtraction instead of four
// positions with signed carries, which is four columns and six booleans this trace does not spend.
//
// **The bits ride under the blocks.** A decomposition needs one row per bit and no permutation, so
// it stands in columns of its own beneath the blocks that are computing hashes at those same rows.
// It costs no block and no height.

use super::permutation::ring_column;
use super::sponge::{factor, term};
use crate::air::{Constraint, Periodic};
use crate::field::F;

mt_codec::constants! {
    AMOUNTS:
    /// The bits an amount is decomposed into. Two amounts of this width sum below the modulus, which
    /// is what makes a balance written as a difference exact; it is a place of this layout, and the
    /// set holds no such number.
    pub const BITS_OF_AN_AMOUNT: usize = 62, code "the bits an amount stands below, so that two of them sum inside the field";
    /// Where the schedule of an amount stands among the periodic columns this layer adds.
    pub const RANGE: usize = 0, code "the periodic column of this layout marking a row of a decomposition";
    pub const TIE: usize = 1, code "the periodic column of this layout marking where an amount meets its limbs";
    pub const SIGN: usize = 2, code "the periodic column of this layout marking which side of a balance an amount enters";
    pub const CHECK: usize = 3, code "the periodic column of this layout marking where a balance is closed";
    pub const PERIODIC_COUNT: usize = 4, code "the count of the periodic columns this layout adds";
    /// The weight of the higher limb of an amount, which is the width of a limb.
    const LIMB_SCALE: u64 = 1 << 32, code "the weight of the higher limb of an amount, which is the width of a limb";
}

// The columns this layer adds after those of the layers below it: the bit of a decomposition, the
// number it accumulates to, and the balance of a spend.
pub struct Places {
    pub bit: usize,
    pub amount: usize,
    pub balance: usize,
}

impl Places {
    pub const fn after(width: usize) -> Self {
        Self {
            bit: width,
            amount: width + 1,
            balance: width + 2,
        }
    }

    pub const fn width(&self) -> usize {
        self.balance + 1
    }
}

// Which rows a decomposition occupies: the bits stand in the rows before the row the number meets
// the cells it is read against, so the accumulation ends exactly where it is read. How many rows
// is how many bits the number is held below — an amount takes the width of an amount, and a number
// the Decree bounds takes the width of that bound, which is what makes the bound a bound at all.
pub fn range_rows(tie: usize, bits: usize) -> Vec<usize> {
    (tie.saturating_sub(bits)..tie).collect()
}

// The four columns of the schedule this layer adds, in the order the description carries them.
pub fn periodic_columns(
    rows_log2: u8,
    consumed: &[usize],
    created: &[usize],
    counted: &[usize],
    counted_bits: usize,
    closes: &[usize],
) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut range = vec![0u64; rows];
    let mut tie = vec![0u64; rows];
    let mut sign = vec![0u64; rows];
    let mut check = vec![0u64; rows];
    for (ties, entering, bits) in [
        (consumed, Some(F::ONE), BITS_OF_AN_AMOUNT),
        (created, Some(F::ONE.negated()), BITS_OF_AN_AMOUNT),
        (counted, None, counted_bits),
    ] {
        for at in ties {
            if *at >= rows {
                continue;
            }
            // A number that is decomposed but enters no balance — the index of a rate is one — is
            // marked for its rows and left out of the sign, so the bound holds on it while the sum
            // stays a sum of amounts alone. Its rows are the bits of its own bound, which is the
            // whole of what holds it below that bound.
            if let Some(entering) = entering {
                tie[*at] = 1;
                sign[*at] = entering.as_u64();
            }
            for row in range_rows(*at, bits) {
                range[row] = 1;
            }
        }
    }
    for at in closes {
        if *at < rows {
            check[*at] = 1;
        }
    }
    // The closing of the trace closes the last balance too: after the last spend the balance is
    // empty, so what this says there is that it is, and the rows close on themselves without a
    // term of their own.
    check[rows - 1] = 1;
    [range, tie, sign, check]
        .into_iter()
        .map(|values| Periodic {
            period_log2: rows_log2,
            values,
        })
        .collect()
}

// Every rule this layer adds. `wrap` is the column that marks where the trace closes — one event,
// one place — and it arrives by its number rather than as a second column saying the same thing.
pub fn constraints(periodic_base: usize, places: &Places) -> Vec<Constraint> {
    let range = periodic_base + RANGE;
    let tie = periodic_base + TIE;
    let sign = periodic_base + SIGN;
    let check = periodic_base + CHECK;
    let minus = F::ONE.negated();
    let two = F::from_u64_reduced(2);
    let scale = F::from_u64_reduced(LIMB_SCALE);
    vec![
        // A bit is a bit, wherever it stands.
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(places.bit, 0, 2)]),
                term(minus, vec![factor(places.bit, 0, 1)]),
            ],
        },
        // The number a decomposition reaches: it doubles and takes the bit where the rows of a
        // decomposition stand, and is empty everywhere else — so an accumulation opens at zero
        // without a boundary saying so.
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(places.amount, 1, 1)]),
                term(
                    two.negated(),
                    vec![factor(range, 0, 1), factor(places.amount, 0, 1)],
                ),
                term(minus, vec![factor(range, 0, 1), factor(places.bit, 0, 1)]),
            ],
        },
        // Where an amount meets its limbs: the number the bits reached is the pair of limbs the
        // commitment absorbs, read as one.
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(tie, 0, 1), factor(places.amount, 0, 1)]),
                term(minus, vec![factor(tie, 0, 1), factor(ring_column(4), 0, 1)]),
                term(
                    scale.negated(),
                    vec![factor(tie, 0, 1), factor(ring_column(5), 0, 1)],
                ),
            ],
        },
        // And the two limbs above the pair are empty, which is what makes the reading above the
        // whole of the amount rather than a part of it.
        Constraint {
            degree: 2,
            terms: vec![term(
                F::ONE,
                vec![factor(tie, 0, 1), factor(ring_column(6), 0, 1)],
            )],
        },
        Constraint {
            degree: 2,
            terms: vec![term(
                F::ONE,
                vec![factor(tie, 0, 1), factor(ring_column(7), 0, 1)],
            )],
        },
        // The balance: it takes every amount at the side it enters on, is emptied where a spend
        // closes, and is emptied again by the closing of the trace.
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(places.balance, 1, 1)]),
                term(minus, vec![factor(places.balance, 0, 1)]),
                term(
                    F::ONE,
                    vec![factor(check, 0, 1), factor(places.balance, 0, 1)],
                ),
                term(minus, vec![factor(sign, 0, 1), factor(places.amount, 0, 1)]),
            ],
        },
        // What a spend creates equals what it consumes.
        Constraint {
            degree: 2,
            terms: vec![term(
                F::ONE,
                vec![factor(check, 0, 1), factor(places.balance, 0, 1)],
            )],
        },
    ]
}

// The bits of an amount and the number they reach, written where they stand.
pub fn write_amount(
    columns: &mut [Vec<F>],
    places: &Places,
    tie: usize,
    amount: u128,
    bits: usize,
) {
    let rows = range_rows(tie, bits);
    for (at, row) in rows.iter().enumerate() {
        let bit = if bits > at {
            (amount >> (bits - 1 - at)) & 1
        } else {
            0
        };
        columns[places.bit][*row] = F::from_u64_reduced(bit as u64);
    }
}

// The two accumulators written across the whole height, each from the rules above: what the bits
// reach, and what the balance of a spend holds.
pub fn write_accumulators(
    columns: &mut [Vec<F>],
    places: &Places,
    consumed: &[usize],
    created: &[usize],
    counted: &[usize],
    counted_bits: usize,
    closes: &[usize],
) {
    let rows = columns[places.bit].len();
    let mut is_range = vec![false; rows];
    let mut sign = vec![F::ZERO; rows];
    for (ties, entering, bits) in [
        (consumed, Some(F::ONE), BITS_OF_AN_AMOUNT),
        (created, Some(F::ONE.negated()), BITS_OF_AN_AMOUNT),
        (counted, None, counted_bits),
    ] {
        for at in ties {
            if *at >= rows {
                continue;
            }
            if let Some(entering) = entering {
                sign[*at] = entering;
            }
            for row in range_rows(*at, bits) {
                is_range[row] = true;
            }
        }
    }
    let mut closing = vec![false; rows];
    for at in closes {
        if *at < rows {
            closing[*at] = true;
        }
    }
    closing[rows - 1] = true;
    let mut amount = F::ZERO;
    let mut balance = F::ZERO;
    for row in 0..rows {
        columns[places.amount][row] = amount;
        columns[places.balance][row] = balance;
        amount = if is_range[row] {
            amount
                .times(F::from_u64_reduced(2))
                .plus(columns[places.bit][row])
        } else {
            F::ZERO
        };
        balance = if closing[row] {
            F::ZERO
        } else {
            balance.plus(sign[row].times(columns[places.amount][row]))
        };
    }
}
