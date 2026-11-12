// What degree the shape admits, and why the answer is two.
//
// The composition of a constraint of degree d over a trace of n rows carries degree about
// (d - 1)·n. The folding divides by the fold at every layer, and the count of layers is exactly
// what carries n down to the tail, so it carries the composition down to the tail times (d - 1).
// A tail of its own count of coefficients therefore admits d <= 2, at every height, since n
// cancels.
//
// The trace below is a bit that is no low-degree function of the row, and it has to be: a bit that
// merely alternates interpolates to (1 - x^(n/2))/2, which is half the degree of a general column,
// and a measurement taken on it answers four where the truth is two. That reading was taken here
// once and was wrong; the column that replaced it is what the measurement stands on.

use mt_proof::air::{AirError, Constraint, Description, Factor, Periodic, Term};
use mt_proof::field::{F, P};
use mt_proof::params::DEGREE_BOUND;
use mt_proof::scheme;

const ROWS_LOG2: u8 = 10;

fn bits_of_degree(degree: u8) -> Description {
    Description {
        trace_width: 1,
        rows_log2: ROWS_LOG2,
        periodic: Vec::<Periodic>::new(),
        constraints: vec![Constraint {
            degree,
            terms: vec![
                Term {
                    coefficient: 1,
                    factors: vec![Factor {
                        column: 0,
                        shift: 0,
                        power: degree,
                    }],
                },
                Term {
                    coefficient: P - 1,
                    factors: vec![Factor {
                        column: 0,
                        shift: 0,
                        power: 1,
                    }],
                },
            ],
        }],
        boundaries: Vec::new(),
    }
}

fn bits() -> Vec<Vec<F>> {
    let rows = 1usize << ROWS_LOG2;
    vec![(0..rows)
        .map(|row| {
            let mut x = (row as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
            x ^= x >> 29;
            x = x.wrapping_mul(0xBF58_476D_1CE4_E5B9);
            x ^= x >> 32;
            if x & 1 == 0 {
                F::ZERO
            } else {
                F::ONE
            }
        })
        .collect()]
}

#[test]
fn a_constraint_of_the_degree_the_shape_admits_proves_and_verifies() {
    let description = bits_of_degree(DEGREE_BOUND);
    description.check().expect("the description stands");
    assert!(description.satisfied_by(&bits(), &[]));
    let bytes = scheme::prove(&description, b"degree", &bits()).expect("proves");
    assert_eq!(scheme::verify(&description, b"degree", &bytes), Ok(()));
}

#[test]
fn a_constraint_above_it_is_refused_where_the_description_is_made() {
    for degree in DEGREE_BOUND + 1..=5 {
        let description = bits_of_degree(degree);
        assert!(
            description.satisfied_by(&bits(), &[]),
            "a bit raised to any power is still the bit, so the trace is true at degree {degree}"
        );
        assert_eq!(
            description.check(),
            Err(AirError::DegreeBeyondTheShape {
                constraint: 0,
                degree,
                bound: DEGREE_BOUND,
            }),
            "and the refusal names the shape rather than the tail a proof would fail to fit"
        );
    }
}
