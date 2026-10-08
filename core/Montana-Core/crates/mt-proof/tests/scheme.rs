// A proof of a small set of constraints, written and then checked as bytes — the form a proof
// arrives in — and every mutation of those bytes refused. The set is small on purpose: what is
// exercised is the machinery, not the statement.

use mt_proof::air::{Boundary, Constraint, Description, Factor, Periodic, Term};
use mt_proof::ext::E;
use mt_proof::field::{F, P};
use mt_proof::params::{Shape, TAIL_DEGREE};
use mt_proof::poly;
use mt_proof::scheme::{self, Proof, Tail, VerifyError};

const ROWS_LOG2: u8 = 10;
const INPUT: &[u8] = b"the public input";

// Two columns and two constraints, both true on every row including the one that wraps: a column
// that is a bit, and a column that steps by a root of unity. A constraint that failed where the
// last row meets the first would be a statement about all rows but one, and the composition
// divides by what vanishes on all of them.
fn description() -> Description {
    let step = poly::root_of_unity(u32::from(ROWS_LOG2)).expect("a root of this order stands");
    Description {
        trace_width: 2,
        rows_log2: ROWS_LOG2,
        periodic: Vec::new(),
        constraints: vec![
            Constraint {
                degree: 2,
                terms: vec![
                    Term {
                        coefficient: 1,
                        factors: vec![Factor {
                            column: 0,
                            shift: 0,
                            power: 2,
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
            },
            Constraint {
                degree: 1,
                terms: vec![
                    Term {
                        coefficient: 1,
                        factors: vec![Factor {
                            column: 1,
                            shift: 1,
                            power: 1,
                        }],
                    },
                    Term {
                        coefficient: P - step.as_u64(),
                        factors: vec![Factor {
                            column: 1,
                            shift: 0,
                            power: 1,
                        }],
                    },
                ],
            },
        ],
        boundaries: vec![Boundary {
            column: 1,
            row: 0,
            value: mt_proof::air::BoundaryValue::Literal(1),
        }],
    }
}

fn trace() -> Vec<Vec<F>> {
    let rows = 1usize << ROWS_LOG2;
    let step = poly::root_of_unity(u32::from(ROWS_LOG2)).expect("a root of this order stands");
    let bits: Vec<F> = (0..rows)
        .map(|row| if row % 2 == 0 { F::ZERO } else { F::ONE })
        .collect();
    let mut walk = Vec::with_capacity(rows);
    let mut value = F::ONE;
    for _ in 0..rows {
        walk.push(value);
        value = value.times(step);
    }
    vec![bits, walk]
}

fn shape() -> Shape {
    Shape::of_rows_log2(u32::from(ROWS_LOG2)).expect("the height reaches the tail")
}

fn written() -> (Description, Vec<u8>) {
    let description = description();
    let bytes =
        scheme::prove(&description, INPUT, &trace()).expect("a trace that satisfies proves");
    (description, bytes)
}

fn stands(description: &Description, bytes: &[u8]) -> Result<(), VerifyError> {
    scheme::verify(description, INPUT, bytes)
}

// A mutation is made where a proof lives — in its bytes — by reading it back, changing one thing,
// and writing it again. Nothing here mutates a parsed object the wire never carries.
fn mutated(bytes: &[u8], change: impl FnOnce(&mut Proof, &mut Tail)) -> Vec<u8> {
    let (mut proof, mut tail) = Proof::decode(shape(), bytes).expect("its own bytes read");
    change(&mut proof, &mut tail);
    proof.encode(shape(), &tail).expect("writes back")
}

#[test]
fn a_proof_of_a_true_statement_is_accepted() {
    let (description, bytes) = written();
    assert_eq!(bytes.len(), shape().proof_bytes());
    assert_eq!(stands(&description, &bytes), Ok(()));
}

#[test]
fn a_proof_reads_back_and_writes_back_to_the_same_bytes() {
    let (_, bytes) = written();
    assert_eq!(mutated(&bytes, |_, _| {}), bytes);
}

#[test]
fn a_proof_is_the_same_bytes_where_it_is_written_twice() {
    let (_, first) = written();
    let (_, second) = written();
    assert_eq!(first, second);
}

#[test]
fn a_trace_that_does_not_satisfy_is_not_provable() {
    let description = description();
    let mut trace = trace();
    trace[0][7] = F::from_u64_reduced(2);
    assert_eq!(
        scheme::prove(&description, INPUT, &trace).err(),
        Some(scheme::ProveError::TraceDoesNotSatisfy)
    );
}

#[test]
fn a_flipped_value_of_a_trace_is_refused() {
    let (description, bytes) = written();
    let broken = mutated(&bytes, |proof, _| {
        let value = proof.queries[0].row[0];
        proof.queries[0].row[0] = value.plus(F::ONE);
    });
    assert_eq!(stands(&description, &broken), Err(VerifyError::Opening));
}

#[test]
fn a_reordered_opening_is_refused() {
    let (description, bytes) = written();
    let broken = mutated(&bytes, |proof, _| proof.queries[0].openings[0].swap(1, 2));
    assert_eq!(stands(&description, &broken), Err(VerifyError::Opening));
}

#[test]
fn a_swapped_query_is_refused() {
    let (description, bytes) = written();
    let broken = mutated(&bytes, |proof, _| proof.queries.swap(0, 1));
    assert_eq!(stands(&description, &broken), Err(VerifyError::Opening));
}

#[test]
fn a_changed_composition_outside_the_domain_is_refused() {
    let (description, bytes) = written();
    let broken = mutated(&bytes, |proof, _| {
        let last = proof.ood_values.len() - 1;
        proof.ood_values[last] = proof.ood_values[last].plus(E::ONE);
    });
    assert_eq!(stands(&description, &broken), Err(VerifyError::Composition));
}

#[test]
fn a_changed_value_of_a_column_outside_the_domain_is_refused() {
    let (description, bytes) = written();
    let broken = mutated(&bytes, |proof, _| {
        proof.ood_values[0] = proof.ood_values[0].plus(E::ONE);
    });
    assert_eq!(stands(&description, &broken), Err(VerifyError::Composition));
}

// What the padding covers is not a place to write in. A proof that used it would be a second set
// of bytes for one claim, and an object taking its name over its own bytes would have two names.
#[test]
fn a_value_written_where_the_padding_stands_is_refused() {
    let (description, bytes) = written();
    let width = usize::from(description.trace_width);
    let broken = mutated(&bytes, |proof, _| proof.ood_values[width] = E::ONE);
    assert_eq!(stands(&description, &broken), Err(VerifyError::Length));

    let broken = mutated(&bytes, |proof, _| proof.queries[0].row[width] = F::ONE);
    assert_eq!(stands(&description, &broken), Err(VerifyError::Length));
}

// The one field of a proof that carries no value of the field and therefore no door of its own
// until this stands: a node of a path. It arrives as thirty-two bytes, and thirty-two bytes are a
// digest only where every limb of them is an element. The implementation this refuses is the one
// that took them as they came and handed them to the arithmetic: a proof of the right length, from
// anybody, took down every machine that verified it.
#[test]
fn a_node_of_a_path_that_is_not_a_digest_is_refused_rather_than_consumed() {
    let (description, bytes) = written();
    let (proof, _) = Proof::decode(shape(), &bytes).expect("its own bytes read");
    // Where the first node of the first path stands is found by the doors of the crate rather than
    // by an offset written here: the bytes of the proof are searched for that node.
    let node = proof.queries[0].trace_path[0].bytes();
    let at = bytes
        .windows(node.len())
        .position(|window| window == node)
        .expect("the node of a path stands in the bytes of the proof");
    for limb in [[0xFFu8; 8], mt_proof::field::P.to_le_bytes()] {
        let mut doctored = bytes.clone();
        doctored[at..at + 8].copy_from_slice(&limb);
        assert_eq!(doctored.len(), bytes.len(), "the length has not moved");
        assert_eq!(stands(&description, &doctored), Err(VerifyError::Length));
    }
    // And a node that is a digest but not the one committed to fails the walk rather than the door.
    let mut elsewhere = bytes.clone();
    elsewhere[at] ^= 1;
    assert_eq!(stands(&description, &elsewhere), Err(VerifyError::Opening));
}

#[test]
fn a_changed_tail_is_refused() {
    let (description, bytes) = written();
    let broken = mutated(&bytes, |_, tail| tail.0[3] = tail.0[3].plus(E::ONE));
    assert!(stands(&description, &broken).is_err());
}

#[test]
fn a_tail_of_more_coefficients_than_the_bound_has_no_bytes_to_travel_in() {
    let (description, bytes) = written();
    let (proof, mut tail) = Proof::decode(shape(), &bytes).expect("reads");
    assert_eq!(tail.0.len(), TAIL_DEGREE);
    tail.0.push(E::ONE);
    assert_eq!(proof.encode(shape(), &tail).err(), Some(VerifyError::Tail));
    assert!(stands(&description, &bytes).is_ok());
}

#[test]
fn bytes_of_another_length_are_refused_before_they_are_parsed() {
    let (description, bytes) = written();
    let mut longer = bytes.clone();
    longer.push(0);
    assert_eq!(stands(&description, &longer), Err(VerifyError::Length));
    assert_eq!(
        stands(&description, &bytes[..bytes.len() - 1]),
        Err(VerifyError::Length)
    );
}

#[test]
fn a_proof_of_one_input_does_not_stand_for_another() {
    let (description, bytes) = written();
    assert!(scheme::verify(&description, b"another public input", &bytes).is_err());
}

#[test]
fn a_proof_of_one_description_does_not_stand_for_another() {
    let (_, bytes) = written();
    let mut other = description();
    other.boundaries[0].value = mt_proof::air::BoundaryValue::Literal(2);
    assert!(scheme::verify(&other, INPUT, &bytes).is_err());
}

// The bound on the width the set derives from the memory of a telephone is refused where a
// description becomes a description, not where it becomes bytes.
#[test]
fn a_description_wider_than_the_bound_is_refused() {
    let mut wide = description();
    // One column past the bound, taken from the register the bound stands in rather than written
    // here: a number of its own would be a second place the bound lives.
    wide.trace_width = (mt_proof::params::TRACE_WIDTH_BOUND + 1) as u16;
    assert!(wide.check().is_err());
}

// A factor at a further row than the shape carries. The format writes a shift in one byte, and the
// slot of the out-of-domain evaluations holds a column at the point and at the point one row on and
// nothing beyond — so a description naming a further row names values no proof carries. Under the
// shape before this, such a description was admitted, its trace was judged against the row it
// named, and the machine then proved the row after it: two readings of one artifact, and no proof
// of a satisfying trace could fold at all. It is refused where a description becomes one.
#[test]
fn a_factor_at_a_further_row_than_the_shape_carries_is_refused() {
    let mut further = description();
    further.constraints[1].terms[0].factors[0].shift = 2;
    assert_eq!(
        further.check(),
        Err(mt_proof::air::AirError::RowBeyondTheShape { shift: 2 })
    );
    // And the two rows the shape does carry stand.
    for shift in [0u8, 1] {
        let mut held = description();
        held.constraints[1].terms[0].factors[0].shift = shift;
        held.check().expect("this row and the one after it");
    }
}

// The selector, which is what a trace of many gadgets cannot do without: a constraint that holds
// inside a block and not across the seam between blocks. The trace below counts inside a block of
// four rows and starts over at each seam — a transition that would be false at every fourth row
// if nothing switched it off, and false at the row where the trace wraps, which is the last row of
// the last block and therefore switched off by the same column.
//
// The period is the block and never the trace. A column of the length of the trace would cost the
// description eight megabytes for a frame and would make a verifier evaluate a million
// coefficients; a column of the block costs sixteen kilobytes and two thousand.
fn counting_inside_a_block() -> Description {
    Description {
        trace_width: 1,
        rows_log2: ROWS_LOG2,
        periodic: vec![
            // One except at the last row of a block: the transition of the counter.
            Periodic {
                period_log2: 2,
                values: vec![1, 1, 1, 0],
            },
            // One at the first row of a block: where the counter starts over.
            Periodic {
                period_log2: 2,
                values: vec![1, 0, 0, 0],
            },
        ],
        constraints: vec![
            Constraint {
                degree: 2,
                terms: vec![
                    Term {
                        coefficient: 1,
                        factors: vec![
                            Factor {
                                column: 1,
                                shift: 0,
                                power: 1,
                            },
                            Factor {
                                column: 0,
                                shift: 1,
                                power: 1,
                            },
                        ],
                    },
                    Term {
                        coefficient: P - 1,
                        factors: vec![
                            Factor {
                                column: 1,
                                shift: 0,
                                power: 1,
                            },
                            Factor {
                                column: 0,
                                shift: 0,
                                power: 1,
                            },
                        ],
                    },
                    Term {
                        coefficient: P - 1,
                        factors: vec![Factor {
                            column: 1,
                            shift: 0,
                            power: 1,
                        }],
                    },
                ],
            },
            Constraint {
                degree: 2,
                terms: vec![Term {
                    coefficient: 1,
                    factors: vec![
                        Factor {
                            column: 2,
                            shift: 0,
                            power: 1,
                        },
                        Factor {
                            column: 0,
                            shift: 0,
                            power: 1,
                        },
                    ],
                }],
            },
        ],
        boundaries: Vec::new(),
    }
}

fn counting_trace() -> Vec<Vec<F>> {
    let rows = 1usize << ROWS_LOG2;
    vec![(0..rows)
        .map(|row| F::from_u64_reduced((row % 4) as u64))
        .collect()]
}

#[test]
fn a_selector_switches_a_transition_off_at_the_seam_of_every_block() {
    let description = counting_inside_a_block();
    description.check().expect("the description stands");
    assert!(
        description.satisfied_by(&counting_trace(), &[]),
        "the counter obeys inside a block and the seam is switched off"
    );
    let bytes =
        scheme::prove(&description, INPUT, &counting_trace()).expect("a counting trace proves");
    assert_eq!(bytes.len(), shape().proof_bytes());
    assert_eq!(scheme::verify(&description, INPUT, &bytes), Ok(()));
}

#[test]
fn a_counter_that_does_not_start_over_at_a_seam_is_not_provable() {
    let description = counting_inside_a_block();
    let mut trace = counting_trace();
    trace[0][4] = F::from_u64_reduced(9);
    assert_eq!(
        scheme::prove(&description, INPUT, &trace).err(),
        Some(scheme::ProveError::TraceDoesNotSatisfy)
    );
}

#[test]
fn a_period_beyond_the_trace_is_refused() {
    let mut wide = counting_inside_a_block();
    wide.periodic[0].period_log2 = ROWS_LOG2 + 1;
    wide.periodic[0].values = vec![1; 1 << (ROWS_LOG2 + 1)];
    assert!(wide.check().is_err());
}
