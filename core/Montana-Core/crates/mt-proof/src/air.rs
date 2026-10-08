// The canonical description of a constraint set: the bytes whose hash is `air_hash`, and the
// reading of them. The set fixes the format field by field, and this is its one transcription.
//
// What a description means is stated with it and holds here: a constraint holds at every row of
// the trace — the sum of its terms is zero — a term is its coefficient times the product of its
// factors, and a factor is one column at one row offset raised to one power. Row indices are taken
// modulo the length of the trace, so the domain closes on itself. A column index below the width
// names a column of the trace; one at or above it names a periodic column, whose value at a row is
// its own values at the row modulo its period.

use crate::field::{F, P};

#[derive(Debug, PartialEq, Eq)]
pub enum AirError {
    ValueOutsideField {
        value: u64,
    },
    // The memory of a prover is the width times the rows times the blowup times the size of an
    // element, and the weakest device the protocol claims is a telephone. The bound that follows
    // is refused here, where a description becomes a description — not where it becomes bytes,
    // which is after a proof of it has already been built.
    WidthBeyondBound {
        width: u16,
        bound: usize,
    },
    // A period longer than the trace is a column of which the trace sees a part, while the bytes
    // the description is hashed over carry the whole: two descriptions meaning one circuit would
    // then take two identifiers.
    PeriodBeyondTrace {
        period_log2: u8,
        rows_log2: u8,
    },
    // The composition of a constraint of degree d carries degree about (d - 1) times the rows, and
    // the folding carries it down by exactly what carries the rows down to the tail — so a tail of
    // its frozen count of coefficients admits two and no more. A constraint of higher degree is
    // refused here rather than at the end of proving, where it shows as a tail that does not fit.
    DegreeBeyondTheShape {
        constraint: usize,
        degree: u8,
        bound: u8,
    },
    DegreeMisdeclared {
        constraint: usize,
        declared: u8,
        held: u8,
    },
    ColumnOutsideDescription {
        column: u16,
    },
    RowOutsideTrace {
        row: u64,
    },
    // A factor naming a row further on than the shape of a proof carries. It is a refusal of its
    // own and never the one above: that row stands inside the trace, and what it stands outside of
    // is the slot beside the roots, which holds every column at the point outside the domain and at
    // the point one row on and nothing beyond.
    RowBeyondTheShape {
        shift: u8,
    },
    Length {
        needed: usize,
        remaining: usize,
    },
    TrailingBytes {
        remaining: usize,
    },
    CountBeyondBytes {
        declared: usize,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Factor {
    pub column: u16,
    pub shift: u8,
    pub power: u8,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Term {
    pub coefficient: u64,
    pub factors: Vec<Factor>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Constraint {
    pub degree: u8,
    pub terms: Vec<Term>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Periodic {
    pub period_log2: u8,
    pub values: Vec<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Boundary {
    pub column: u16,
    pub row: u64,
    pub value: BoundaryValue,
}

// What a boundary holds a cell to: a literal of the field, or a limb of the public inputs — the
// bytes of the object the proof stands in. The second kind is what binds one frozen description
// to every frame's own roots, nullifiers and commitments: a proof of one frame asserts nothing
// about another, and neither prover nor verifier chooses anything in the resolution.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BoundaryValue {
    Literal(u64),
    Public(u16),
    // The pair of adjacent limbs at this index, low first: a 64-bit word of a hash state, which
    // no single four-byte limb can carry.
    Word(u16),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Description {
    pub trace_width: u16,
    pub rows_log2: u8,
    pub periodic: Vec<Periodic>,
    pub constraints: Vec<Constraint>,
    pub boundaries: Vec<Boundary>,
}

impl Description {
    pub fn rows(&self) -> u64 {
        1u64 << self.rows_log2
    }

    // The columns a factor may name: the trace, then the periodic columns after it.
    pub fn columns(&self) -> usize {
        usize::from(self.trace_width) + self.periodic.len()
    }

    // Every rule the set states of a description, in one place, answered before the bytes are
    // hashed — a description that fails one of them is not an artifact of this protocol.
    pub fn check(&self) -> Result<(), AirError> {
        if usize::from(self.trace_width) > crate::params::TRACE_WIDTH_BOUND {
            return Err(AirError::WidthBeyondBound {
                width: self.trace_width,
                bound: crate::params::TRACE_WIDTH_BOUND,
            });
        }
        let rows = self.rows();
        for periodic in &self.periodic {
            if u32::from(periodic.period_log2) > u32::from(self.rows_log2) {
                return Err(AirError::PeriodBeyondTrace {
                    period_log2: periodic.period_log2,
                    rows_log2: self.rows_log2,
                });
            }
            for value in &periodic.values {
                outside_field(*value)?;
            }
        }
        for (at, constraint) in self.constraints.iter().enumerate() {
            let mut greatest = 0u32;
            for term in &constraint.terms {
                outside_field(term.coefficient)?;
                let mut sum = 0u32;
                for factor in &term.factors {
                    if usize::from(factor.column) >= self.columns() {
                        return Err(AirError::ColumnOutsideDescription {
                            column: factor.column,
                        });
                    }
                    if u64::from(factor.shift) >= rows {
                        return Err(AirError::RowOutsideTrace {
                            row: u64::from(factor.shift),
                        });
                    }
                    // A shift names this row or the one after it, and no other. What decides that
                    // is not taste: the slot beside the roots holds every column at the point
                    // outside the domain and at the point one row on, and nothing further, so a
                    // factor at a further row is a value no proof carries. Refused here rather
                    // than read as one row on — which would judge a trace against the row the
                    // description names and prove the row after it, two readings of one artifact.
                    if u64::from(factor.shift) > 1 {
                        return Err(AirError::RowBeyondTheShape {
                            shift: factor.shift,
                        });
                    }
                    sum += u32::from(factor.power);
                }
                greatest = greatest.max(sum);
            }
            let held = u8::try_from(greatest).unwrap_or(u8::MAX);
            if held != constraint.degree {
                return Err(AirError::DegreeMisdeclared {
                    constraint: at,
                    declared: constraint.degree,
                    held,
                });
            }
            // A degree that is declared truly and still stands above what the shape admits is
            // named by the shape and not by the declaration: the two refusals say different
            // things, and a reader of the second must not be told the first.
            if held > crate::params::DEGREE_BOUND {
                return Err(AirError::DegreeBeyondTheShape {
                    constraint: at,
                    degree: constraint.degree,
                    bound: crate::params::DEGREE_BOUND,
                });
            }
        }
        for boundary in &self.boundaries {
            if let BoundaryValue::Literal(value) = boundary.value {
                outside_field(value)?;
            }
            if usize::from(boundary.column) >= usize::from(self.trace_width) {
                return Err(AirError::ColumnOutsideDescription {
                    column: boundary.column,
                });
            }
            if boundary.row >= rows {
                return Err(AirError::RowOutsideTrace { row: boundary.row });
            }
        }
        Ok(())
    }

    // The bytes the artifact is, in the order the set writes them and in no other: terms stand in
    // the order given and are never sorted, since two orderings are two artifacts with two hashes.
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&self.trace_width.to_le_bytes());
        out.push(self.rows_log2);
        out.extend_from_slice(&(self.periodic.len() as u16).to_le_bytes());
        for periodic in &self.periodic {
            out.push(periodic.period_log2);
            for value in &periodic.values {
                out.extend_from_slice(&value.to_le_bytes());
            }
        }
        out.extend_from_slice(&(self.constraints.len() as u16).to_le_bytes());
        for constraint in &self.constraints {
            out.push(constraint.degree);
            out.extend_from_slice(&(constraint.terms.len() as u16).to_le_bytes());
            for term in &constraint.terms {
                out.extend_from_slice(&term.coefficient.to_le_bytes());
                out.push(term.factors.len() as u8);
                for factor in &term.factors {
                    out.extend_from_slice(&factor.column.to_le_bytes());
                    out.push(factor.shift);
                    out.push(factor.power);
                }
            }
        }
        out.extend_from_slice(&(self.boundaries.len() as u16).to_le_bytes());
        for boundary in &self.boundaries {
            out.extend_from_slice(&boundary.column.to_le_bytes());
            out.extend_from_slice(&boundary.row.to_le_bytes());
            match boundary.value {
                BoundaryValue::Literal(value) => {
                    out.push(0);
                    out.extend_from_slice(&value.to_le_bytes());
                }
                BoundaryValue::Public(index) => {
                    out.push(1);
                    out.extend_from_slice(&u64::from(index).to_le_bytes());
                }
                BoundaryValue::Word(index) => {
                    out.push(2);
                    out.extend_from_slice(&u64::from(index).to_le_bytes());
                }
            }
        }
        out
    }

    // What a proof is written against: the description in its canonical form, under a domain of
    // its own, so a proof of one statement cannot be offered for another.
    pub fn identifier(&self) -> [u8; 32] {
        mt_codec::hash_of_one(mt_codec::domain::MT_PROOF_AIR, &self.encode())
    }

    pub fn decode(bytes: &[u8]) -> Result<Description, AirError> {
        let mut at = 0usize;
        let trace_width = take_u16(bytes, &mut at)?;
        let rows_log2 = take_u8(bytes, &mut at)?;
        let periodic_count = usize::from(take_u16(bytes, &mut at)?);
        let mut periodic = Vec::with_capacity(periodic_count.min(bytes.len()));
        for _ in 0..periodic_count {
            let period_log2 = take_u8(bytes, &mut at)?;
            let count = 1usize << period_log2;
            if bytes.len().saturating_sub(at) < count * 8 {
                return Err(AirError::CountBeyondBytes { declared: count });
            }
            let mut values = Vec::with_capacity(count);
            for _ in 0..count {
                values.push(take_u64(bytes, &mut at)?);
            }
            periodic.push(Periodic {
                period_log2,
                values,
            });
        }
        let constraint_count = usize::from(take_u16(bytes, &mut at)?);
        let mut constraints = Vec::with_capacity(constraint_count.min(bytes.len()));
        for _ in 0..constraint_count {
            let degree = take_u8(bytes, &mut at)?;
            let term_count = usize::from(take_u16(bytes, &mut at)?);
            let mut terms = Vec::with_capacity(term_count.min(bytes.len()));
            for _ in 0..term_count {
                let coefficient = take_u64(bytes, &mut at)?;
                let factor_count = usize::from(take_u8(bytes, &mut at)?);
                let mut factors = Vec::with_capacity(factor_count);
                for _ in 0..factor_count {
                    factors.push(Factor {
                        column: take_u16(bytes, &mut at)?,
                        shift: take_u8(bytes, &mut at)?,
                        power: take_u8(bytes, &mut at)?,
                    });
                }
                terms.push(Term {
                    coefficient,
                    factors,
                });
            }
            constraints.push(Constraint { degree, terms });
        }
        let boundary_count = usize::from(take_u16(bytes, &mut at)?);
        let mut boundaries = Vec::with_capacity(boundary_count.min(bytes.len()));
        for _ in 0..boundary_count {
            let column = take_u16(bytes, &mut at)?;
            let row = take_u64(bytes, &mut at)?;
            let kind = take_u8(bytes, &mut at)?;
            let raw = take_u64(bytes, &mut at)?;
            let value = match kind {
                0 => BoundaryValue::Literal(raw),
                1 => u16::try_from(raw)
                    .map(BoundaryValue::Public)
                    .map_err(|_| AirError::TrailingBytes { remaining: 0 })?,
                2 => u16::try_from(raw)
                    .map(BoundaryValue::Word)
                    .map_err(|_| AirError::TrailingBytes { remaining: 0 })?,
                _ => return Err(AirError::TrailingBytes { remaining: 0 }),
            };
            boundaries.push(Boundary { column, row, value });
        }
        if at != bytes.len() {
            return Err(AirError::TrailingBytes {
                remaining: bytes.len() - at,
            });
        }
        let held = Description {
            trace_width,
            rows_log2,
            periodic,
            constraints,
            boundaries,
        };
        held.check()?;
        Ok(held)
    }

    // The value of a column at a row: the trace where the index names one, and the periodic column
    // at the row modulo its period where it does not.
    fn cell(&self, trace: &[Vec<F>], column: u16, row: u64) -> F {
        let width = usize::from(self.trace_width);
        let rows = self.rows();
        let at = (row % rows) as usize;
        if usize::from(column) < width {
            trace[usize::from(column)][at]
        } else {
            let periodic = &self.periodic[usize::from(column) - width];
            let period = 1usize << periodic.period_log2;
            F::from_u64_reduced(periodic.values[at % period])
        }
    }

    // What a constraint says at one row: the sum of its terms, each the coefficient times the
    // product of its factors.
    pub fn evaluate(&self, trace: &[Vec<F>], constraint: usize, row: u64) -> F {
        let mut sum = F::ZERO;
        for term in &self.constraints[constraint].terms {
            let mut product = F::from_u64_reduced(term.coefficient);
            for factor in &term.factors {
                let value = self.cell(trace, factor.column, row + u64::from(factor.shift));
                for _ in 0..factor.power {
                    product = product.times(value);
                }
            }
            sum = sum.plus(product);
        }
        sum
    }

    // Whether a trace satisfies this description: every constraint at every row, and every
    // boundary where it stands. What a frozen vector of an encoding is worth is that it encodes a
    // description of something rather than of nothing, and this is what says the two agree.
    pub fn satisfied_by(&self, trace: &[Vec<F>], public: &[F]) -> bool {
        if trace.len() != usize::from(self.trace_width) {
            return false;
        }
        let rows = self.rows() as usize;
        if trace.iter().any(|column| column.len() != rows) {
            return false;
        }
        for at in 0..self.constraints.len() {
            for row in 0..self.rows() {
                if !self.evaluate(trace, at, row).is_zero() {
                    return false;
                }
            }
        }
        self.boundaries.iter().all(|boundary| {
            let held = match crate::scheme::resolve(boundary.value, public) {
                Some(value) => value,
                None => return false,
            };
            trace[usize::from(boundary.column)][boundary.row as usize] == held
        })
    }
}

fn outside_field(value: u64) -> Result<(), AirError> {
    if value >= P {
        return Err(AirError::ValueOutsideField { value });
    }
    Ok(())
}

fn take<'a>(bytes: &'a [u8], at: &mut usize, n: usize) -> Result<&'a [u8], AirError> {
    if bytes.len().saturating_sub(*at) < n {
        return Err(AirError::Length {
            needed: n,
            remaining: bytes.len().saturating_sub(*at),
        });
    }
    let out = &bytes[*at..*at + n];
    *at += n;
    Ok(out)
}

fn take_u8(bytes: &[u8], at: &mut usize) -> Result<u8, AirError> {
    Ok(take(bytes, at, 1)?[0])
}

fn take_u16(bytes: &[u8], at: &mut usize) -> Result<u16, AirError> {
    let two = take(bytes, at, 2)?;
    Ok(u16::from_le_bytes([two[0], two[1]]))
}

fn take_u64(bytes: &[u8], at: &mut usize) -> Result<u64, AirError> {
    let eight = take(bytes, at, 8)?;
    let mut buf = [0u8; 8];
    buf.copy_from_slice(eight);
    Ok(u64::from_le_bytes(buf))
}

// The description the set writes to fix its encoder: a boolean column, a multiplication gate, a
// transition gated by a periodic column, and one boundary. It is small enough to read and real
// enough to exercise every part of the format, and it is what the frozen vector stands over.
pub fn the_description_of_the_set() -> Description {
    let minus_one = P - 1;
    Description {
        trace_width: 3,
        rows_log2: 3,
        periodic: vec![Periodic {
            period_log2: 1,
            values: vec![1, 0],
        }],
        constraints: vec![
            // c0 − c0²: the column carries a bit and nothing else.
            Constraint {
                degree: 2,
                terms: vec![
                    Term {
                        coefficient: 1,
                        factors: vec![Factor {
                            column: 0,
                            shift: 0,
                            power: 1,
                        }],
                    },
                    Term {
                        coefficient: minus_one,
                        factors: vec![Factor {
                            column: 0,
                            shift: 0,
                            power: 2,
                        }],
                    },
                ],
            },
            // c2 − c0·c1: the gate that multiplies two cells, which one column per term could not
            // express and which every hash of this protocol needs.
            Constraint {
                degree: 2,
                terms: vec![
                    Term {
                        coefficient: 1,
                        factors: vec![Factor {
                            column: 2,
                            shift: 0,
                            power: 1,
                        }],
                    },
                    Term {
                        coefficient: minus_one,
                        factors: vec![
                            Factor {
                                column: 0,
                                shift: 0,
                                power: 1,
                            },
                            Factor {
                                column: 1,
                                shift: 0,
                                power: 1,
                            },
                        ],
                    },
                ],
            },
            // per·(c1[+1] − c1 − c0): a transition the periodic column turns on over one region of
            // the trace and off over another.
            Constraint {
                degree: 2,
                terms: vec![
                    Term {
                        coefficient: 1,
                        factors: vec![
                            Factor {
                                column: 3,
                                shift: 0,
                                power: 1,
                            },
                            Factor {
                                column: 1,
                                shift: 1,
                                power: 1,
                            },
                        ],
                    },
                    Term {
                        coefficient: minus_one,
                        factors: vec![
                            Factor {
                                column: 3,
                                shift: 0,
                                power: 1,
                            },
                            Factor {
                                column: 1,
                                shift: 0,
                                power: 1,
                            },
                        ],
                    },
                    Term {
                        coefficient: minus_one,
                        factors: vec![
                            Factor {
                                column: 3,
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
                ],
            },
        ],
        boundaries: vec![
            Boundary {
                column: 1,
                row: 0,
                value: BoundaryValue::Literal(1),
            },
            Boundary {
                column: 2,
                row: 2,
                value: BoundaryValue::Public(0),
            },
            Boundary {
                column: 1,
                row: 2,
                value: BoundaryValue::Word(0),
            },
        ],
    }
}

// The trace the set says the description above is satisfied by: eight rows, a bit alternating in
// the first column, a running sum in the second that advances only where the periodic column turns
// the transition on, and their product in the third.
pub fn the_trace_of_the_set() -> Vec<Vec<F>> {
    let column = |values: [u64; 8]| values.iter().map(|v| F::from_u64_reduced(*v)).collect();
    vec![
        column([1, 0, 1, 0, 1, 0, 1, 0]),
        column([1, 2, 5, 6, 9, 10, 13, 14]),
        column([1, 0, 5, 0, 9, 0, 13, 0]),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    // Canon, "The vector of the encoding". The wrong implementation this refuses is the one that
    // sorts the terms of a constraint or writes a factor in another order: the bytes are the
    // artifact, and two orderings are two artifacts with two hashes.
    #[test]
    fn the_frozen_vector_of_the_encoding_reproduces() {
        let held = the_description_of_the_set();
        let bytes = held.encode();
        assert_eq!(bytes.len(), 199);
        assert_eq!(
            hex(&Sha256::digest(&bytes)),
            "703186b6adf3929c84fec81da75ab7353856015318252d8ef1a197a4eb193e24"
        );
        assert_eq!(Description::decode(&bytes), Ok(held));
    }

    // What the frozen vector is worth is that it encodes a description of something: the set says
    // so, and this is where the two meet.
    #[test]
    fn the_description_of_the_set_is_satisfied_by_its_trace() {
        let held = the_description_of_the_set();
        assert!(held.satisfied_by(
            &the_trace_of_the_set(),
            &crate::poseidon::limbs_of(&[0x05, 0, 0, 0, 0, 0, 0, 0])
        ));
    }

    // And a trace that breaks one rule of it is refused by that rule alone, which is what says the
    // evaluation reads the description rather than agreeing with everything.
    #[test]
    fn a_trace_that_breaks_one_rule_is_not_a_satisfying_trace() {
        let held = the_description_of_the_set();
        let mut broken = the_trace_of_the_set();
        broken[0][3] = F::from_u64_reduced(2);
        assert!(!held.satisfied_by(
            &broken,
            &crate::poseidon::limbs_of(&[0x05, 0, 0, 0, 0, 0, 0, 0])
        ));
        let mut broken = the_trace_of_the_set();
        broken[2][2] = F::from_u64_reduced(4);
        assert!(!held.satisfied_by(
            &broken,
            &crate::poseidon::limbs_of(&[0x05, 0, 0, 0, 0, 0, 0, 0])
        ));
        let mut broken = the_trace_of_the_set();
        broken[1][1] = F::from_u64_reduced(3);
        assert!(!held.satisfied_by(
            &broken,
            &crate::poseidon::limbs_of(&[0x05, 0, 0, 0, 0, 0, 0, 0])
        ));
        let mut broken = the_trace_of_the_set();
        broken[1][0] = F::from_u64_reduced(7);
        broken[2][0] = F::from_u64_reduced(7);
        broken[1][1] = F::from_u64_reduced(8);
        assert!(!held.satisfied_by(
            &broken,
            &crate::poseidon::limbs_of(&[0x05, 0, 0, 0, 0, 0, 0, 0])
        ));
    }

    #[test]
    fn a_description_of_another_field_or_another_shape_is_refused() {
        let mut held = the_description_of_the_set();
        held.constraints[0].terms[0].coefficient = P;
        assert_eq!(held.check(), Err(AirError::ValueOutsideField { value: P }));

        let mut held = the_description_of_the_set();
        held.constraints[0].degree = 3;
        assert_eq!(
            held.check(),
            Err(AirError::DegreeMisdeclared {
                constraint: 0,
                declared: 3,
                held: 2
            })
        );

        let mut held = the_description_of_the_set();
        held.constraints[0].terms[0].factors[0].column = 4;
        assert_eq!(
            held.check(),
            Err(AirError::ColumnOutsideDescription { column: 4 })
        );

        let mut held = the_description_of_the_set();
        held.constraints[0].terms[0].factors[0].shift = 8;
        assert_eq!(held.check(), Err(AirError::RowOutsideTrace { row: 8 }));
        let mut held = the_description_of_the_set();
        held.boundaries[0].row = 8;
        assert_eq!(held.check(), Err(AirError::RowOutsideTrace { row: 8 }));
    }

    #[test]
    fn bytes_that_are_not_a_description_are_refused_rather_than_read() {
        let bytes = the_description_of_the_set().encode();
        assert!(matches!(
            Description::decode(&bytes[..bytes.len() - 1]),
            Err(AirError::Length { .. })
        ));
        let mut longer = bytes.clone();
        longer.push(0);
        assert_eq!(
            Description::decode(&longer),
            Err(AirError::TrailingBytes { remaining: 1 })
        );
        let mut doctored = bytes.clone();
        doctored[3] = 9;
        assert!(Description::decode(&doctored).is_err());
    }

    // The rows close on themselves: a shift past the last row reads the first, which is what lets
    // a transition be written once for every row and turned off where it must not hold.
    #[test]
    fn the_rows_close_on_themselves() {
        let held = the_description_of_the_set();
        let trace = the_trace_of_the_set();
        assert!(held.evaluate(&trace, 2, 7).is_zero());
    }
}
