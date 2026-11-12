// A comparison of a digest against a threshold, as a constraint set: thirty-two rows, one per byte
// of the digest in the order of their significance, where the threshold less one less the digest is
// written byte by byte with its borrows and every byte is held in range. The borrow out of the most
// significant byte says which side of the threshold the digest stands on — nought where it clears.
//
// **Why the comparison is written in bytes.** A draw of this set compares thirty-two bytes read
// big-endian, where the bytes are the four words of the digest each written little-endian: the most
// significant byte of the comparison is the least significant byte of the first word. A comparison
// written in words would have to reverse the bytes of each, which is the same decomposition under
// another name; so the circuit decomposes each word into its eight bytes, holds the decomposition
// canonical — a word written as bytes above the modulus is another word — and compares bytes.
//
// **One gadget for every draw a proof asserts.** The ticket compares once and holds the borrow out
// at nought, since a ticket that does not clear writes no proof; a ballot compares once per unit of
// standing and reads each borrow out as the bit of a vote. The rows, the rules and the canonical
// check are one, so the two circuits say one thing about what clearing a threshold is.

use super::lane;
use super::sponge::{factor, term};
use crate::air::{Boundary, BoundaryValue, Constraint, Periodic};
use crate::field::F;
use crate::poseidon::CAPACITY;

// The bytes one word of the proof field is written in, read off the type rather than written.
pub const BYTES_OF_A_WORD: usize = (u64::BITS / u8::BITS) as usize;

// The bytes the comparison runs over: the four words of a digest, written byte by byte.
pub const COMPARED_BYTES: usize = CAPACITY * BYTES_OF_A_WORD;

// The largest value the high half of a canonical word may hold: a word below the modulus has its
// high thirty-two bits below two to the thirty-second less one, or exactly that with a low half of
// nought.
const HIGH_CEILING: u64 = (1u64 << u32::BITS) - 1;

// The columns of the comparison: the byte of the digest and its eight bits, the byte of the
// threshold, the byte of the difference and its eight bits, the borrow, the two accumulators that
// rebuild a word from its bytes, and the three cells of the canonical check.
#[derive(Clone, Copy, Debug)]
pub struct Compared {
    pub first: usize,
}

impl Compared {
    pub const fn after(width: usize) -> Self {
        Self { first: width }
    }

    pub const fn byte(&self) -> usize {
        self.first
    }

    pub const fn byte_bit(&self, bit: usize) -> usize {
        self.first + 1 + bit
    }

    pub const fn threshold(&self) -> usize {
        self.first + 1 + BYTES_OF_A_WORD
    }

    pub const fn difference(&self) -> usize {
        self.threshold() + 1
    }

    pub const fn difference_bit(&self, bit: usize) -> usize {
        self.difference() + 1 + bit
    }

    pub const fn borrow(&self) -> usize {
        self.difference() + 1 + BYTES_OF_A_WORD
    }

    pub const fn word(&self) -> usize {
        self.borrow() + 1
    }

    pub const fn high(&self) -> usize {
        self.word() + 1
    }

    pub const fn saturated(&self) -> usize {
        self.high() + 1
    }

    pub const fn inverse(&self) -> usize {
        self.saturated() + 1
    }

    pub const fn witness(&self) -> usize {
        self.inverse() + 1
    }

    pub const fn width(&self) -> usize {
        self.witness() + 1
    }
}

// Where the marks of the comparison stand among the periodic columns this layout adds: the rows of
// the comparison, the rows whose byte stands in the high half of its word, and the last row of each
// word — one mark per word, since the rule at that row reads the cell of the digest of that word.
mt_codec::constants! {
    COMPARISON:
    pub const INSIDE: usize = 0, code "the periodic column of this layout marking a row of the comparison";
    pub const HIGH: usize = 1, code "the periodic column of this layout marking a row whose byte stands in the high half of its word";
    pub const END_OF_WORD: usize = 2, code "the first of the periodic columns of this layout each marking the last row of one word of the digest";
}

pub const PERIODIC_COUNT: usize = END_OF_WORD + CAPACITY;

// The row of a comparison opening at `start` that a byte of the digest stands at: the words from the
// last to the first, and within a word the bytes from the last to the first, so that significance
// rises with the row and a borrow walks one row on.
pub const fn row_of(start: usize, word: usize, byte: usize) -> usize {
    start + (CAPACITY - 1 - word) * BYTES_OF_A_WORD + (BYTES_OF_A_WORD - 1 - byte)
}

// The row after a comparison, where the borrow out of its most significant byte stands.
pub const fn after_of(start: usize) -> usize {
    start + COMPARED_BYTES
}

// The periodic columns of every comparison a trace holds, one opening at each of `starts`.
pub fn periodic_columns(rows_log2: u8, starts: &[usize]) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mut inside = vec![0u64; rows];
    let mut high = vec![0u64; rows];
    let mut ends = vec![vec![0u64; rows]; CAPACITY];
    for start in starts {
        for (word, end) in ends.iter_mut().enumerate() {
            for byte in 0..BYTES_OF_A_WORD {
                let row = row_of(*start, word, byte);
                if row >= rows {
                    continue;
                }
                inside[row] = 1;
                if byte >= BYTES_OF_A_WORD / 2 {
                    high[row] = 1;
                }
                if byte == 0 {
                    end[row] = 1;
                }
            }
        }
    }
    let mut out = vec![
        Periodic {
            period_log2: rows_log2,
            values: inside,
        },
        Periodic {
            period_log2: rows_log2,
            values: high,
        },
    ];
    for values in ends {
        out.push(Periodic {
            period_log2: rows_log2,
            values,
        });
    }
    out
}

fn bit_rule(column: usize) -> Constraint {
    Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(column, 0, 2)]),
            term(F::ONE.negated(), vec![factor(column, 0, 1)]),
        ],
    }
}

// The rules of every comparison, over the columns the caller places them at. `digest` is the lane
// that holds the digest a comparison reads while it runs.
pub fn constraints(
    periodic_base: usize,
    compared: &Compared,
    digest: &lane::Places,
) -> Vec<Constraint> {
    let inside = periodic_base + INSIDE;
    let high = periodic_base + HIGH;
    let ends: Vec<usize> = (0..CAPACITY)
        .map(|word| periodic_base + END_OF_WORD + word)
        .collect();
    let minus = F::ONE.negated();
    let base = F::from_u64_reduced(1 << u8::BITS);
    let mut out = Vec::new();

    // Every bit is a bit, and the borrow and the saturation are one, wherever they stand.
    for bit in 0..BYTES_OF_A_WORD {
        out.push(bit_rule(compared.byte_bit(bit)));
        out.push(bit_rule(compared.difference_bit(bit)));
    }
    out.push(bit_rule(compared.borrow()));
    out.push(bit_rule(compared.saturated()));

    // Inside the comparison a byte is its bits and a difference is its bits, which holds each in
    // range.
    for (value, bits) in [
        (
            compared.byte(),
            (0..BYTES_OF_A_WORD)
                .map(|bit| compared.byte_bit(bit))
                .collect::<Vec<_>>(),
        ),
        (
            compared.difference(),
            (0..BYTES_OF_A_WORD)
                .map(|bit| compared.difference_bit(bit))
                .collect::<Vec<_>>(),
        ),
    ] {
        let mut terms = vec![term(
            F::ONE,
            vec![factor(inside, 0, 1), factor(value, 0, 1)],
        )];
        for (bit, column) in bits.into_iter().enumerate() {
            terms.push(term(
                F::from_u64_reduced(1u64 << bit).negated(),
                vec![factor(inside, 0, 1), factor(column, 0, 1)],
            ));
        }
        out.push(Constraint { degree: 2, terms });
    }

    // The subtraction, byte by byte: the threshold less the byte less the borrow in, less the
    // difference, plus the base times the borrow out — which stands one row on — is nought.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(inside, 0, 1), factor(compared.threshold(), 0, 1)],
            ),
            term(
                minus,
                vec![factor(inside, 0, 1), factor(compared.byte(), 0, 1)],
            ),
            term(
                minus,
                vec![factor(inside, 0, 1), factor(compared.borrow(), 0, 1)],
            ),
            term(
                minus,
                vec![factor(inside, 0, 1), factor(compared.difference(), 0, 1)],
            ),
            term(
                base,
                vec![factor(inside, 0, 1), factor(compared.borrow(), 1, 1)],
            ),
        ],
    });

    // The word rebuilt from its bytes, most significant first: inside the comparison and off the
    // last byte of a word, the word one row on is the base times the word plus the byte. At the last
    // byte of a word the terms are taken back by the end column, and the word one row on opens at
    // nought by a boundary.
    let mut rebuild = vec![
        term(
            F::ONE,
            vec![factor(inside, 0, 1), factor(compared.word(), 1, 1)],
        ),
        term(
            base.negated(),
            vec![factor(inside, 0, 1), factor(compared.word(), 0, 1)],
        ),
        term(
            minus,
            vec![factor(inside, 0, 1), factor(compared.byte(), 0, 1)],
        ),
    ];
    for end in &ends {
        rebuild.push(term(
            minus,
            vec![factor(*end, 0, 1), factor(compared.word(), 1, 1)],
        ));
        rebuild.push(term(
            base,
            vec![factor(*end, 0, 1), factor(compared.word(), 0, 1)],
        ));
        rebuild.push(term(
            F::ONE,
            vec![factor(*end, 0, 1), factor(compared.byte(), 0, 1)],
        ));
    }
    out.push(Constraint {
        degree: 2,
        terms: rebuild,
    });
    // The high half: rebuilt over the bytes of the high half, held over the rest, and opened at
    // nought one row on from the last byte of a word by a boundary — the rule of the hold is taken
    // back there as well.
    let mut high_rule = vec![
        term(
            F::ONE,
            vec![factor(inside, 0, 1), factor(compared.high(), 1, 1)],
        ),
        term(
            minus,
            vec![factor(inside, 0, 1), factor(compared.high(), 0, 1)],
        ),
        term(
            F::from_u64_reduced((1 << u8::BITS) - 1).negated(),
            vec![factor(high, 0, 1), factor(compared.high(), 0, 1)],
        ),
        term(
            minus,
            vec![factor(high, 0, 1), factor(compared.byte(), 0, 1)],
        ),
    ];
    for end in &ends {
        high_rule.push(term(
            minus,
            vec![factor(*end, 0, 1), factor(compared.high(), 1, 1)],
        ));
        high_rule.push(term(
            F::ONE,
            vec![factor(*end, 0, 1), factor(compared.high(), 0, 1)],
        ));
    }
    out.push(Constraint {
        degree: 2,
        terms: high_rule,
    });

    // At the last byte of a word the word is complete: the base times the word plus the byte is the
    // cell of the digest the lane carries.
    for (word, end) in ends.iter().enumerate() {
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    base,
                    vec![factor(*end, 0, 1), factor(compared.word(), 0, 1)],
                ),
                term(
                    F::ONE,
                    vec![factor(*end, 0, 1), factor(compared.byte(), 0, 1)],
                ),
                term(
                    minus,
                    vec![factor(*end, 0, 1), factor(digest.cell(word), 0, 1)],
                ),
            ],
        });
    }

    // Canonical: the high half stands below its ceiling, or at it with a low half of nought. The
    // saturated bit says which: it is nought off the last byte of a word; where it stands, the high
    // half is the ceiling and the low half nought; where it does not, the ceiling less the high half
    // has an inverse, witnessed as a product.
    let mut off_ends = vec![term(F::ONE, vec![factor(compared.saturated(), 0, 1)])];
    for end in &ends {
        off_ends.push(term(
            minus,
            vec![factor(*end, 0, 1), factor(compared.saturated(), 0, 1)],
        ));
    }
    out.push(Constraint {
        degree: 2,
        terms: off_ends,
    });
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![
                    factor(compared.saturated(), 0, 1),
                    factor(compared.high(), 0, 1),
                ],
            ),
            term(
                F::from_u64_reduced(HIGH_CEILING).negated(),
                vec![factor(compared.saturated(), 0, 1)],
            ),
        ],
    });
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                base,
                vec![
                    factor(compared.saturated(), 0, 1),
                    factor(compared.word(), 0, 1),
                ],
            ),
            term(
                F::ONE,
                vec![
                    factor(compared.saturated(), 0, 1),
                    factor(compared.byte(), 0, 1),
                ],
            ),
            term(
                F::from_u64_reduced(1u64 << u32::BITS).negated(),
                vec![
                    factor(compared.saturated(), 0, 1),
                    factor(compared.high(), 0, 1),
                ],
            ),
        ],
    });
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(compared.witness(), 0, 1)]),
            term(
                F::from_u64_reduced(HIGH_CEILING).negated(),
                vec![factor(compared.inverse(), 0, 1)],
            ),
            term(
                F::ONE,
                vec![
                    factor(compared.high(), 0, 1),
                    factor(compared.inverse(), 0, 1),
                ],
            ),
        ],
    });
    for end in &ends {
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![factor(*end, 0, 1), factor(compared.witness(), 0, 1)],
                ),
                term(minus, vec![factor(*end, 0, 1)]),
                term(
                    F::ONE,
                    vec![factor(*end, 0, 1), factor(compared.saturated(), 0, 1)],
                ),
            ],
        });
    }
    out
}

// The bytes of the threshold a comparison opening at `start` reads, one public limb each in the
// order of its rows: `limb(at)` names the limb of the public input the row `start + at` reads.
pub fn threshold_boundaries(
    compared: &Compared,
    start: usize,
    limb: impl Fn(usize) -> u16,
) -> Vec<Boundary> {
    let mut out = Vec::with_capacity(COMPARED_BYTES);
    for word in 0..CAPACITY {
        for byte in 0..BYTES_OF_A_WORD {
            let row = row_of(start, word, byte);
            out.push(Boundary {
                column: compared.threshold() as u16,
                row: row as u64,
                value: BoundaryValue::Public(limb(row - start)),
            });
        }
    }
    out
}

// The borrow into the least significant byte is one: the subtraction is of the threshold less one,
// which is what makes a digest at the threshold itself fail to clear.
pub fn borrow_in(compared: &Compared, start: usize) -> Boundary {
    Boundary {
        column: compared.borrow() as u16,
        row: start as u64,
        value: BoundaryValue::Literal(1),
    }
}

// Each word's accumulators open at nought at the first row of its bytes.
pub fn accumulators_open(compared: &Compared, start: usize) -> Vec<Boundary> {
    let mut out = Vec::with_capacity(2 * CAPACITY);
    for word in 0..CAPACITY {
        let row = row_of(start, word, BYTES_OF_A_WORD - 1) as u64;
        out.push(Boundary {
            column: compared.word() as u16,
            row,
            value: BoundaryValue::Literal(0),
        });
        out.push(Boundary {
            column: compared.high() as u16,
            row,
            value: BoundaryValue::Literal(0),
        });
    }
    out
}

// The trace of one comparison: the threshold less one less the digest, byte by byte from the least
// significant, every byte and every difference written by its bits, the accumulators and the
// canonical check beside them. What it answers with is the borrow out of the most significant byte,
// written at the row after the comparison — nought exactly where the digest clears the threshold.
pub fn write(
    columns: &mut [Vec<F>],
    compared: &Compared,
    start: usize,
    digest: &[u8; 32],
    threshold: &[u8; 32],
) -> u16 {
    let mut borrow = 1u16;
    for word in (0..CAPACITY).rev() {
        let mut rebuilt = 0u64;
        let mut high = 0u64;
        for byte in (0..BYTES_OF_A_WORD).rev() {
            let row = row_of(start, word, byte);
            let s = u16::from(digest[word * BYTES_OF_A_WORD + byte]);
            let t = u16::from(threshold[word * BYTES_OF_A_WORD + byte]);
            let (difference, borrow_out) = if t >= s + borrow {
                (t - s - borrow, 0u16)
            } else {
                (t + (1 << u8::BITS) - s - borrow, 1u16)
            };
            columns[compared.byte()][row] = F::from_u64_reduced(u64::from(s));
            for bit in 0..BYTES_OF_A_WORD {
                columns[compared.byte_bit(bit)][row] =
                    F::from_u64_reduced(u64::from((s >> bit) & 1));
                columns[compared.difference_bit(bit)][row] =
                    F::from_u64_reduced(u64::from((difference >> bit) & 1));
            }
            columns[compared.threshold()][row] = F::from_u64_reduced(u64::from(t));
            columns[compared.difference()][row] = F::from_u64_reduced(u64::from(difference));
            columns[compared.borrow()][row] = F::from_u64_reduced(u64::from(borrow));
            columns[compared.word()][row] = F::from_u64_reduced(rebuilt);
            columns[compared.high()][row] = F::from_u64_reduced(high);
            // The inverse and its witness read the high half as the row holds it — before this
            // byte enters it — because the rule that defines them holds at every row over the cell
            // of that row. At the last byte of a word the half is complete there, which is where
            // the canonical check reads it.
            let ceiling_less_high =
                F::from_u64_reduced(HIGH_CEILING).minus(F::from_u64_reduced(high));
            let inverse = ceiling_less_high.inverse().unwrap_or(F::ZERO);
            columns[compared.inverse()][row] = inverse;
            columns[compared.witness()][row] = ceiling_less_high.times(inverse);
            if byte == 0 {
                let saturated = high == HIGH_CEILING;
                columns[compared.saturated()][row] = if saturated { F::ONE } else { F::ZERO };
            }
            rebuilt = (rebuilt << u8::BITS) + u64::from(s);
            if byte >= BYTES_OF_A_WORD / 2 {
                high = (high << u8::BITS) + u64::from(s);
            }
            borrow = borrow_out;
        }
    }
    columns[compared.borrow()][after_of(start)] = F::from_u64_reduced(u64::from(borrow));
    borrow
}
