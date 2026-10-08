// The circuit of a window: the public carriage of the accumulation, proven so a joining device
// inherits it instead of replaying it.
//
// **What it asserts and what it does not.** Six repetitions of one step: the accumulator taken,
// plus the challenge times the instance, is the accumulator reached — coefficient by coefficient,
// under the modulus of the lattice, with every witness of a reduction held in range. The instance,
// the accumulators in and the accumulators out are public: every cell of them is bound to the
// public input by a boundary, so the proof asserts arithmetic over values the verifier holds and
// nothing rides on trust in the trace. What it does not assert is stated in the set: the openings
// are native — the final accumulator is discharged once by whoever must be convinced — and the
// equalities of a window are carried into the instance publicly, which is carriage and not
// judgement.
//
// **The shape.** One phase, six runs of the instance's coefficients at one lane a row; the
// challenge of a run is bound at its first row and carried across it by the schedule. The width is
// the bound's, the height one power of two above the rows the runs fill.

use super::fold;
use crate::air::{Boundary, BoundaryValue, Description};
use crate::params::TRACE_WIDTH_BOUND;

mt_codec::constants! {
    WINDOW:
    /// The coefficients of an instance: the commitment's polynomials laid end to end.
    pub const INSTANCE_COEFFICIENTS: usize = 1536, code "the coefficients of an instance of the accumulation: the polynomials of a standing commitment laid end to end";
    /// What the runs of this circuit fill, one power of two: the count its own blocks ask for. The
    /// height it is **built** at is the one every description stands at, since a proof is bytes of
    /// one length whatever is proven; this number is what says the runs fit under it.
    pub const ROWS_FILLED_LOG2: usize = 14, code "the rows six runs of the instance fill, one power of two: what the height every description stands at must hold";
}

pub fn places() -> fold::Places {
    fold::Places::after(0, 1)
}

// A limb index rides a u16, and the window's publics stand under twenty thousand of them — a fact
// the tests hold rather than a hope.
fn limb(index: usize) -> BoundaryValue {
    BoundaryValue::Public(index as u16)
}

// The public input, laid as limbs of four bytes: the accumulators taken in, run by run; the
// instance; the accumulators reached, run by run; and the challenge of each run.
pub fn public_of(
    taken: &[[u32; INSTANCE_COEFFICIENTS]],
    instance: &[u32; INSTANCE_COEFFICIENTS],
    reached: &[[u32; INSTANCE_COEFFICIENTS]],
    challenges: &[u32],
) -> Vec<u8> {
    let mut out = Vec::new();
    for run in taken {
        for value in run {
            out.extend_from_slice(&value.to_le_bytes());
        }
    }
    for value in instance {
        out.extend_from_slice(&value.to_le_bytes());
    }
    for run in reached {
        for value in run {
            out.extend_from_slice(&value.to_le_bytes());
        }
    }
    for value in challenges {
        out.extend_from_slice(&value.to_le_bytes());
    }
    out
}

pub fn description() -> Description {
    let held = places();
    let width = TRACE_WIDTH_BOUND as u16;
    let rows_log2 = crate::params::ROWS_LOG2;
    let reps = fold::REPETITIONS;
    let coeffs = INSTANCE_COEFFICIENTS;

    // The schedule: within every run the challenge of a row below is the challenge of this one;
    // across runs and beyond them, nothing is said.
    let carried: Vec<usize> = (0..reps)
        .flat_map(|run| run * coeffs..run * coeffs + coeffs - 1)
        .collect();
    let periodic = fold::periodic_columns(rows_log2, &carried);

    let constraints = fold::constraints(width as usize, &held, fold::MODULUS);

    // Every public cell bound: the coefficient taken, the coefficient folded and the coefficient
    // reached at every row, and the challenge at the first row of every run.
    let mut boundaries = Vec::with_capacity(reps * coeffs * 3 + reps);
    let instance_base = reps * coeffs;
    let reached_base = instance_base + coeffs;
    let challenge_base = reached_base + reps * coeffs;
    for run in 0..reps {
        for coeff in 0..coeffs {
            let row = (run * coeffs + coeff) as u64;
            boundaries.push(Boundary {
                column: held.taken(0) as u16,
                row,
                value: limb(run * coeffs + coeff),
            });
            boundaries.push(Boundary {
                column: held.folded(0) as u16,
                row,
                value: limb(instance_base + coeff),
            });
            boundaries.push(Boundary {
                column: held.reached(0) as u16,
                row,
                value: limb(reached_base + run * coeffs + coeff),
            });
        }
        boundaries.push(Boundary {
            column: held.challenge as u16,
            row: (run * coeffs) as u64,
            value: limb(challenge_base + run),
        });
    }

    Description {
        trace_width: width,
        rows_log2,
        periodic,
        constraints,
        boundaries,
    }
}

// The trace of a window: the lanes filled from the publics, the reduction witnessed as the rule
// reads it. What this writes is what the constraints assert — the arithmetic stands in one place,
// the rule, and this door computes the witnesses the rule holds in range.
pub fn trace_of(
    taken: &[[u32; INSTANCE_COEFFICIENTS]],
    instance: &[u32; INSTANCE_COEFFICIENTS],
    challenges: &[u32],
) -> (Vec<Vec<crate::field::F>>, Vec<[u32; INSTANCE_COEFFICIENTS]>) {
    use crate::field::F;
    let held = places();
    let q = fold::MODULUS;
    let rows = 1usize << crate::params::ROWS_LOG2;
    let mut columns = vec![vec![F::ZERO; rows]; TRACE_WIDTH_BOUND];
    let mut reached_out = Vec::with_capacity(taken.len());
    for (run, (accumulator, challenge)) in taken.iter().zip(challenges).enumerate() {
        let mut reached_run = [0u32; INSTANCE_COEFFICIENTS];
        for (coeff, reached_cell) in reached_run.iter_mut().enumerate() {
            let row = run * INSTANCE_COEFFICIENTS + coeff;
            let sum = accumulator[coeff] as u64 + *challenge as u64 * instance[coeff] as u64;
            let quotient = sum / q;
            let reached = sum % q;
            *reached_cell = reached as u32;
            columns[held.challenge][row] = F::from_u64_reduced(*challenge as u64);
            columns[held.taken(0)][row] = F::from_u64_reduced(accumulator[coeff] as u64);
            columns[held.folded(0)][row] = F::from_u64_reduced(instance[coeff] as u64);
            for bit in 0..fold::QUOTIENT_BITS {
                columns[held.quotient_bit(0, bit)][row] =
                    F::from_u64_reduced((quotient >> bit) & 1);
            }
            for bit in 0..fold::VALUE_BITS {
                columns[held.reached_bit(0, bit)][row] = F::from_u64_reduced((reached >> bit) & 1);
            }
            columns[held.reached(0)][row] = F::from_u64_reduced(reached);
        }
        reached_out.push(reached_run);
    }
    (columns, reached_out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_description_stands_at_the_bound_and_inside_the_degree() {
        let held = description();
        assert_eq!(held.trace_width as usize, TRACE_WIDTH_BOUND);
        assert!(places().width() <= TRACE_WIDTH_BOUND);
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
        assert!(fold::rows_of(INSTANCE_COEFFICIENTS, 1) <= 1 << ROWS_FILLED_LOG2);
        assert!(ROWS_FILLED_LOG2 <= usize::from(crate::params::ROWS_LOG2));
    }

    #[test]
    fn every_public_cell_is_bound_and_counted() {
        let held = description();
        assert_eq!(
            held.boundaries.len(),
            fold::REPETITIONS * INSTANCE_COEFFICIENTS * 3 + fold::REPETITIONS
        );
        let public = public_of(
            &[[0u32; INSTANCE_COEFFICIENTS]; fold::REPETITIONS],
            &[0u32; INSTANCE_COEFFICIENTS],
            &[[0u32; INSTANCE_COEFFICIENTS]; fold::REPETITIONS],
            &[1u32; fold::REPETITIONS],
        );
        assert_eq!(
            public.len(),
            (fold::REPETITIONS * INSTANCE_COEFFICIENTS * 2 + INSTANCE_COEFFICIENTS) * 4
                + fold::REPETITIONS * 4
        );
    }

    // The one proving run of this tree that the sweep does not make. Its description carries a
    // boundary for every coefficient of every accumulator and of the instance, and the composition
    // of those boundaries takes past an hour at the height every description stands at — measured,
    // not estimated. A run that long is a run nobody makes, and a test nobody makes says nothing;
    // so it is named rather than quietly slow, and `AUDIT.md` carries what closes it: a public
    // input bound by a digest rather than cell by cell. Run it by name:
    //
    //   cargo test --jobs 2 -p mt-proof --lib a_window_is_proven -- --ignored
    #[ignore = "past an hour at the one height: AUDIT.md carries what closes it"]
    #[test]
    fn a_window_is_proven_and_verified_end_to_end() {
        let mut taken = [[0u32; INSTANCE_COEFFICIENTS]; fold::REPETITIONS];
        let mut instance = [0u32; INSTANCE_COEFFICIENTS];
        let q = fold::MODULUS as u32;
        // Deterministic values below the modulus, with bits at both ends of the range.
        let mut seed = 0x4D54_2D57_494Eu64;
        let mut next = || {
            seed ^= seed >> 12;
            seed ^= seed << 25;
            seed ^= seed >> 27;
            (seed.wrapping_mul(0x2545_F491_4F6C_DD1D) % q as u64) as u32
        };
        for run in taken.iter_mut() {
            for cell in run.iter_mut() {
                *cell = next();
            }
        }
        for cell in instance.iter_mut() {
            *cell = next();
        }
        let challenges: Vec<u32> = (0..fold::REPETITIONS)
            .map(|_| 1 + next() % (q - 1))
            .collect();
        let (trace, reached) = trace_of(&taken, &instance, &challenges);
        let public = public_of(&taken, &instance, &reached, &challenges);
        let held = description();
        assert!(
            held.satisfied_by(&trace, &crate::poseidon::limbs_of(&public)),
            "an honest window satisfies its own description"
        );
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true window proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));
        // And a moved public is refused: the first accumulator's first coefficient, one up.
        let mut moved = public.clone();
        moved[0] = moved[0].wrapping_add(1);
        assert!(crate::scheme::verify(&held, &moved, &bytes).is_err());
    }

    #[test]
    fn the_identifier_of_the_window_exists_and_is_stable() {
        let one = description().identifier();
        let two = description().identifier();
        assert_eq!(one, two);
        let hex: String = one.iter().map(|b| format!("{b:02x}")).collect();
        println!("air_hash of the window's circuit = {hex}");
    }
}
