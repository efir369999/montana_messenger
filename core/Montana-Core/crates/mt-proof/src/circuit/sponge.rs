// The sponge of the proof hash as a constraint set: a chain of permutation blocks with the rule of
// absorption written at the seams between them. The permutation itself is the layer below and is
// not restated here — what this adds is the one thing a chain is: the capacity of a block enters
// the block after it, and the rate is overwritten by what follows.
//
// **Why a seam and never a wire across the trace.** A factor names this row or the one after it,
// so two rows that must agree have to stand beside each other. The state a block leaves stands at
// its last row and the state the next block enters with stands at the row after — one row apart,
// exactly what a shift reaches. A chain is therefore blocks laid in the order the data flows, and
// every wire of it costs one selector and no column.
//
// **What decides which seams carry.** A column of the description standing at the length of the
// trace: a seam inside a chain carries, a seam between two chains does not, and the row where the
// trace wraps carries nothing. It varies by block and by nothing shorter, so a column of a shorter
// period would say one thing about every block — and a chain is precisely where blocks differ.

use super::permutation::{self, period, ring_column};
use crate::air::{Boundary, BoundaryValue, Constraint, Description, Factor, Periodic, Term};
use crate::field::F;
use crate::poseidon::{self, CAPACITY, RATE, WIDTH};
use mt_codec::Domain;

// The elements of an absorption as the blocks take them: the padding rule of the set, applied here
// so that the circuit and the door of the family divide one input the same way. A second reading of
// that rule is a circuit proving a hash nobody computes.
pub fn padded(elements: &[F]) -> Vec<F> {
    let mut out = elements.to_vec();
    out.push(F::ONE);
    while !out.len().is_multiple_of(RATE) {
        out.push(F::ZERO);
    }
    out
}

// The blocks an absorption of this many elements costs, which is the count the set derives the
// shape of a frame from. Ceiling division written as the set writes one: the elements, the pad
// element after them, and the rate less one, over the rate.
pub fn blocks_of(elements: usize) -> usize {
    (elements + 1).div_ceil(RATE)
}

// The states the blocks of a chain enter with: the first carrying the capacity of its domain, each
// later one the capacity the block before it left, its rate overwritten by what follows.
pub fn chain(domain: Domain, elements: &[F]) -> Vec<[F; WIDTH]> {
    let padded = padded(elements);
    let mut states = Vec::with_capacity(padded.len() / RATE);
    let mut capacity = poseidon::capacity_of(domain);
    for block in padded.chunks(RATE) {
        let mut state = [F::ZERO; WIDTH];
        state[..RATE].copy_from_slice(block);
        state[RATE..].copy_from_slice(&capacity);
        states.push(state);
        let mut left = state;
        poseidon::permute(&mut left);
        capacity.copy_from_slice(&left[RATE..]);
    }
    states
}

// A chain absorbed once and squeezed twice: the blocks of the absorption, and one block more whose
// state is the state the last of them left, untouched. The first four cells after the absorption
// are the first half and the first four after the extra block are the second, which is the whole
// of why an absorption is not repeated: one place the input enters, two values out of it.
pub fn chain_twice(domain: Domain, elements: &[F]) -> Vec<[F; WIDTH]> {
    let mut states = chain(domain, elements);
    let mut left = match states.last() {
        Some(state) => *state,
        None => return states,
    };
    poseidon::permute(&mut left);
    states.push(left);
    states
}

// The seam a squeeze stands at: the last row of the block whose state the squeeze takes whole.
pub fn squeeze_rows(first_block: usize, absorbed: usize) -> Vec<usize> {
    vec![(first_block + absorbed) * period() - 1]
}

// The rule of a squeeze: nothing is overwritten, so the rate crosses the seam beside the capacity
// the rule above already carries. Together they say the state after the seam is the state before
// it, which is what a squeeze of a sponge is.
pub fn rate_carries(carry_column: usize) -> Vec<Constraint> {
    (0..RATE)
        .map(|j| {
            let cell = ring_column(j);
            Constraint {
                degree: 2,
                terms: vec![
                    term(F::ONE, vec![factor(carry_column, 0, 1), factor(cell, 1, 1)]),
                    term(
                        F::ONE.negated(),
                        vec![factor(carry_column, 0, 1), factor(cell, 0, 1)],
                    ),
                ],
            }
        })
        .collect()
}

// The rows at which a chain of this many blocks, standing at this block of the trace, holds a seam
// that carries: the last row of every block of it but the last.
pub fn carry_rows(first_block: usize, blocks: usize) -> Vec<usize> {
    (0..blocks.saturating_sub(1))
        .map(|at| (first_block + at) * period() + period() - 1)
        .collect()
}

// The column of the description that says which seams carry.
pub fn carry_column(rows_log2: u8, carries: &[usize]) -> Periodic {
    let rows = 1usize << rows_log2;
    let mut values = vec![0u64; rows];
    for row in carries {
        if *row < rows {
            values[*row] = 1;
        }
    }
    Periodic {
        period_log2: rows_log2,
        values,
    }
}

pub(super) fn factor(column: usize, shift: u8, power: u8) -> Factor {
    Factor {
        column: column as u16,
        shift,
        power,
    }
}

pub(super) fn term(coefficient: F, factors: Vec<Factor>) -> Term {
    Term {
        coefficient: coefficient.as_u64(),
        factors,
    }
}

// The rule of a seam that carries: the capacity of the state a block leaves is the capacity the
// block after it enters with. The selector costs the one degree the bound has left, and the body is
// a difference of two cells, which is linear.
pub fn capacity_carries(carry_column: usize) -> Vec<Constraint> {
    (0..CAPACITY)
        .map(|j| {
            let cell = ring_column(RATE + j);
            Constraint {
                degree: 2,
                terms: vec![
                    term(F::ONE, vec![factor(carry_column, 0, 1), factor(cell, 1, 1)]),
                    term(
                        F::ONE.negated(),
                        vec![factor(carry_column, 0, 1), factor(cell, 0, 1)],
                    ),
                ],
            }
        })
        .collect()
}

// One absorption, as a description a proof stands over. The elements are the public input and the
// digest is read from the state the last block leaves, so what a proof of this asserts is that the
// digest of the family over those elements is that value — and nothing of how it was computed is
// left to the prover: the padding is held by literals, the capacity of the first block by the
// literal of its domain, and every seam inside the chain by the rule above.
pub fn description_of_one(domain: Domain, elements: usize, rows_log2: u8) -> Option<Description> {
    let blocks = blocks_of(elements);
    let rows = 1usize << rows_log2;
    if blocks * period() > rows {
        return None;
    }
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let carry = held.trace_width as usize + held.periodic.len();
    held.periodic
        .push(carry_column(rows_log2, &carry_rows(0, blocks)));
    held.constraints.extend(capacity_carries(carry));

    let capacity = poseidon::capacity_of(domain);
    for (j, value) in capacity.iter().enumerate() {
        held.boundaries.push(Boundary {
            column: ring_column(RATE + j) as u16,
            row: 0,
            value: BoundaryValue::Literal(value.as_u64()),
        });
    }
    for at in 0..blocks * RATE {
        let (block, slot) = (at / RATE, at % RATE);
        let value = if at < elements {
            BoundaryValue::Word((2 * at) as u16)
        } else if at == elements {
            BoundaryValue::Literal(F::ONE.as_u64())
        } else {
            BoundaryValue::Literal(0)
        };
        held.boundaries.push(Boundary {
            column: ring_column(slot) as u16,
            row: (block * period()) as u64,
            value,
        });
    }
    for j in 0..CAPACITY {
        held.boundaries.push(Boundary {
            column: ring_column(j) as u16,
            row: (blocks * period() - 1) as u64,
            value: BoundaryValue::Word((2 * (elements + j)) as u16),
        });
    }
    Some(held)
}

// The trace of one absorption: the chain written block by block, and the rest of the height filled
// with blocks no seam of the chain reaches.
pub fn trace_of_one(domain: Domain, elements: &[F], rows_log2: u8) -> Option<Vec<Vec<F>>> {
    let rows = 1usize << rows_log2;
    if !rows.is_multiple_of(period()) {
        return None;
    }
    let states = chain(domain, elements);
    if states.len() * period() > rows {
        return None;
    }
    let mut columns = vec![vec![F::ZERO; rows]; permutation::TRACE_WIDTH];
    for (block, state) in states.iter().enumerate() {
        permutation::write_block(&mut columns, block, state)?;
    }
    for block in states.len()..rows / period() {
        permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])?;
    }
    Some(columns)
}

// The public input of one absorption: the elements it takes and the digest it answers with, each as
// the two limbs a word of the field stands in.
pub fn public_of_one(domain: Domain, elements: &[F]) -> Vec<u8> {
    let mut out = Vec::with_capacity((elements.len() + CAPACITY) * 8);
    for element in elements {
        out.extend_from_slice(&element.as_u64().to_le_bytes());
    }
    let digest = poseidon::hash_elements(domain, elements);
    for cell in digest.elements() {
        out.extend_from_slice(&cell.as_u64().to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_codec::domain;

    fn elements(n: usize) -> Vec<F> {
        (0..n).map(|i| F::from_u64_reduced(i as u64 + 7)).collect()
    }

    #[test]
    fn the_chain_answers_what_the_door_of_the_family_answers() {
        // The circuit's reading of the sponge and the door every machine computes it with are one
        // function, and this is where the two meet. The wrong implementation it refuses: one
        // carrying the rate of a block instead of its capacity, which answers on a single block
        // and parts from the door on the second.
        for n in [1usize, 4, 7, 8, 9, 14, 15, 24] {
            let input = elements(n);
            let states = chain(domain::MT_NOTE_CM, &input);
            assert_eq!(states.len(), blocks_of(n), "{n} elements");
            let mut last = *states.last().expect("a chain holds a block");
            poseidon::permute(&mut last);
            assert_eq!(
                &last[..CAPACITY],
                poseidon::hash_elements(domain::MT_NOTE_CM, &input).elements(),
                "{n} elements"
            );
        }
    }

    #[test]
    fn the_trace_of_an_absorption_satisfies_its_description() {
        for n in [4usize, 7, 14] {
            let input = elements(n);
            let held = description_of_one(domain::MT_NOTE_NF, n, 10).expect("a lawful height");
            held.check().expect("the description stands");
            let trace = trace_of_one(domain::MT_NOTE_NF, &input, 10).expect("a lawful height");
            let public = poseidon::limbs_of(&public_of_one(domain::MT_NOTE_NF, &input));
            assert!(held.satisfied_by(&trace, &public), "{n} elements");
        }
    }

    #[test]
    fn a_digest_the_absorption_does_not_give_is_not_satisfied() {
        let input = elements(14);
        let held = description_of_one(domain::MT_NOTE_NF, 14, 10).expect("a lawful height");
        let trace = trace_of_one(domain::MT_NOTE_NF, &input, 10).expect("a lawful height");
        let mut public = public_of_one(domain::MT_NOTE_NF, &input);
        public[14 * 8] ^= 1;
        assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    }

    #[test]
    fn a_chain_that_breaks_its_seam_is_not_satisfied() {
        // The one rule this layer adds, refused where it is broken: a trace whose second block
        // enters with a capacity the first did not leave.
        let input = elements(14);
        let held = description_of_one(domain::MT_NOTE_NF, 14, 10).expect("a lawful height");
        let mut trace = trace_of_one(domain::MT_NOTE_NF, &input, 10).expect("a lawful height");
        let public = poseidon::limbs_of(&public_of_one(domain::MT_NOTE_NF, &input));
        assert!(held.satisfied_by(&trace, &public));
        let cell = ring_column(RATE);
        trace[cell][period()] = trace[cell][period()].plus(F::ONE);
        assert!(!held.satisfied_by(&trace, &public));
    }

    #[test]
    fn two_domains_of_one_input_are_two_descriptions() {
        // The capacity of the first block is a literal of its domain, so a proof of an absorption
        // under one domain does not stand for the same elements under another.
        let one = description_of_one(domain::MT_NOTE_CM, 4, 10).expect("a lawful height");
        let two = description_of_one(domain::MT_NOTE_NF, 4, 10).expect("a lawful height");
        assert_ne!(one.identifier(), two.identifier());
    }

    #[test]
    fn an_absorption_is_proven_and_verified_as_bytes() {
        // The whole of it through the machine a proof actually travels: the shape of the chain
        // folds to the tail, its width stands inside the slot, and the digest is held to the
        // public input by a boundary rather than by the prover's word.
        let input = elements(14);
        let held = description_of_one(domain::MT_NOTE_NF, 14, 10).expect("a lawful height");
        let trace = trace_of_one(domain::MT_NOTE_NF, &input, 10).expect("a lawful height");
        let public = public_of_one(domain::MT_NOTE_NF, &input);
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true trace proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));

        // And it does not stand for another input: the elements are the public input, and the
        // digest of another absorption is another value.
        let other: Vec<F> = elements(14).iter().map(|e| e.plus(F::ONE)).collect();
        let public_of_other = public_of_one(domain::MT_NOTE_NF, &other);
        assert!(crate::scheme::verify(&held, &public_of_other, &bytes).is_err());
    }
}
