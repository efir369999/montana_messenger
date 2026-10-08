// The permutation of the proof hash, as a constraint set and as the trace that satisfies it. It is
// the gadget the tree of notes is walked with, and two hundred and forty-six of the two hundred and
// sixty-one units of a frame are this one.
//
// **The shape is derived and not chosen.** Three bounds decide it and nothing else does: a
// constraint carries degree two, a factor names this row or the one after it, and a trace is at
// most the bound on the width. From them the layout follows. A chain of multiplications inside one
// row is free — every factor stands at the same row — so the whole S-box of a lane costs four cells
// and no row of its own. What costs rows is width: twelve lanes at four cells each ask for
// forty-eight columns where there are twenty-four, so the lanes are taken three at a time and the
// state turns under them like a ring. Four turns bring every lane through the S-box and leave the
// ring in its own order, and a fifth row applies the linear layer.
//
// **Why a ring rather than a schedule.** A row that named which lanes it works on would carry that
// naming into every constraint, and a name that varies by row is a periodic factor — which costs a
// degree the bound does not have where it multiplies a product. Turning the ring makes every row
// identical: the lanes worked on are always the first three, the chain is the same at every row of
// the trace, and nothing of the schedule enters the arithmetic of the S-box at all. What remains
// row-dependent is the linear layer alone, which is linear, and a linear rule bears the selector
// that switches it without leaving the degree.

use crate::air::{Boundary, BoundaryValue, Constraint, Description, Factor, Periodic, Term};
use crate::field::{F, P};
use crate::poseidon::{self, WIDTH};

mt_codec::constants! {
    LAYOUT:
    /// The lanes one row takes through the S-box: the width of a trace over the cells one lane
    /// costs, which is what decides it.
    pub const LANES_PER_ROW: usize = 1, code "the lanes one row of this layout takes: one, so that the frame the permutation serves keeps sixteen columns of the bound for its own wiring";
    /// The cells one lane costs: the square, the cube, the fourth and the seventh.
    pub const CELLS_PER_LANE: usize = 4, code "the multiplications the seventh power costs at degree two";
    /// Where the ring of the state stands among the columns, and where the constant of the first
    /// lane stands among the periodic columns. Both are places of this layout and of nothing else.
    const RING: usize = 0, code "the first column the ring of the state stands at";
    const RC: usize = 0, code "the first periodic column the constant of a lane stands at";
}

// The width this layout takes stands inside the bound the memory of a telephone fixes, and it is
// answered where the layout is written rather than where a test runs: a layout wider than the bound
// fails to compile.
const _: () = {
    assert!(
        TRACE_WIDTH <= crate::params::TRACE_WIDTH_BOUND,
        "the layout of the permutation is wider than the bound on a trace"
    );
};

/// The turns of the ring that bring every lane through the S-box and leave it in its own order.
pub const TURNS: usize = WIDTH / LANES_PER_ROW;
/// The rows one round of the full kind costs: its turns and the row of its linear layer.
pub const ROWS_PER_FULL_ROUND: usize = TURNS + 1;
/// The rows the whole permutation costs, from the opening linear layer to the row its answer
/// stands at. It is counted rather than chosen, and the count closes on a power of two of its own
/// accord — which is what a periodic column of the schedule demands and what leaves this layout
/// without one idle row.
pub const ROWS_PER_PERMUTATION: usize =
    1 + poseidon::ROUNDS_EXTERNAL * ROWS_PER_FULL_ROUND + poseidon::ROUNDS_PARTIAL + 1;

// The columns of the trace. The ring stands first and the workspace of the three lanes after it.
const WORK: usize = WIDTH;
pub const TRACE_WIDTH: usize = WIDTH + LANES_PER_ROW * CELLS_PER_LANE;

// The periodic columns, in the order the description carries them: the constant of each lane a row
// works on, then the three rules a row may stand under.
const SEL_TURN: usize = LANES_PER_ROW;
const SEL_LINEAR: usize = SEL_TURN + 1;
const SEL_PARTIAL: usize = SEL_LINEAR + 1;
const PERIODIC_COUNT: usize = SEL_PARTIAL + 1;

// What a row of the schedule does. A row stands under exactly one of them.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Rule {
    // The opening linear layer, and the linear layer that closes a round of the full kind.
    Linear,
    // One turn of the ring: three lanes through the S-box, the rest of the ring moving under them.
    Turn,
    // A round of the partial kind: one lane through the S-box and the linear layer in one row.
    Partial,
    // The row the answer of the permutation stands at, which carries no rule onward.
    Answer,
}

// The schedule, read off the permutation rather than written beside it: the rounds it runs, in the
// order it runs them, each costing what this layout costs it.
fn schedule() -> Vec<(Rule, usize, usize)> {
    let mut out = Vec::with_capacity(ROWS_PER_PERMUTATION);
    out.push((Rule::Linear, usize::MAX, 0));
    for round in 0..poseidon::ROUNDS_TOTAL {
        if poseidon::round_is_external(round) {
            for turn in 0..TURNS {
                out.push((Rule::Turn, round, turn));
            }
            out.push((Rule::Linear, usize::MAX, 0));
        } else {
            out.push((Rule::Partial, round, 0));
        }
    }
    out.push((Rule::Answer, usize::MAX, 0));
    out
}

/// The rows one block of the schedule occupies: the rows it costs, closed to a power of two, which
/// is what a periodic column of the schedule demands.
pub fn period() -> usize {
    ROWS_PER_PERMUTATION.next_power_of_two()
}

fn periodic_columns() -> Vec<Periodic> {
    let rows = schedule();
    let period_log2 = period().trailing_zeros() as u8;
    let mut values = vec![vec![0u64; period()]; PERIODIC_COUNT];
    for (at, (rule, round, turn)) in rows.iter().enumerate() {
        match rule {
            Rule::Turn => {
                values[SEL_TURN][at] = 1;
                for lane in 0..LANES_PER_ROW {
                    if let Some(constant) =
                        poseidon::round_constant(*round, turn * LANES_PER_ROW + lane)
                    {
                        values[RC + lane][at] = constant.as_u64();
                    }
                }
            }
            Rule::Partial => {
                values[SEL_PARTIAL][at] = 1;
                if let Some(constant) = poseidon::round_constant(*round, 0) {
                    values[RC][at] = constant.as_u64();
                }
            }
            Rule::Linear => values[SEL_LINEAR][at] = 1,
            Rule::Answer => {}
        }
    }
    values
        .into_iter()
        .map(|values| Periodic {
            period_log2,
            values,
        })
        .collect()
}

fn periodic_column(index: usize) -> usize {
    TRACE_WIDTH + index
}

/// Where a cell of the ring stands among the columns. The layer above builds its wiring out of
/// these, and a second statement of the place would be the place standing twice.
pub const fn ring_column(cell: usize) -> usize {
    RING + cell
}

/// How many periodic columns this layout holds. A layer above appends its own after them, so it
/// reads the count rather than restating it.
pub const fn periodic_count() -> usize {
    PERIODIC_COUNT
}

fn factor(column: usize, shift: u8, power: u8) -> Factor {
    Factor {
        column: column as u16,
        shift,
        power,
    }
}

fn term(coefficient: F, factors: Vec<Factor>) -> Term {
    Term {
        coefficient: coefficient.as_u64(),
        factors,
    }
}

// The four multiplications of one lane's S-box, at the row they all stand at: the square of what
// the lane carries with its constant added, the cube, the fourth, and the seventh as the product of
// the last two. Every factor is of this row, so the chain costs no row of its own.
fn sbox_of_slot(slot: usize) -> Vec<Constraint> {
    let ring = RING + slot;
    let rc = periodic_column(RC + slot);
    let work = WORK + slot * CELLS_PER_LANE;
    let (square, cube, fourth, seventh) = (work, work + 1, work + 2, work + 3);
    let minus_one = F::ONE.negated();
    let minus_two = F::from_u64_reduced(2).negated();
    vec![
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(square, 0, 1)]),
                term(minus_one, vec![factor(ring, 0, 2)]),
                term(minus_two, vec![factor(rc, 0, 1), factor(ring, 0, 1)]),
                term(minus_one, vec![factor(rc, 0, 2)]),
            ],
        },
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(cube, 0, 1)]),
                term(minus_one, vec![factor(square, 0, 1), factor(ring, 0, 1)]),
                term(minus_one, vec![factor(square, 0, 1), factor(rc, 0, 1)]),
            ],
        },
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(fourth, 0, 1)]),
                term(minus_one, vec![factor(square, 0, 2)]),
            ],
        },
        Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(seventh, 0, 1)]),
                term(minus_one, vec![factor(cube, 0, 1), factor(fourth, 0, 1)]),
            ],
        },
    ]
}

// A rule that holds where its selector stands and says nothing where it does not. The body is
// linear, so the selector costs the one degree the bound has left.
fn under(selector: usize, body: Vec<(F, usize, u8)>) -> Constraint {
    let selector = periodic_column(selector);
    Constraint {
        degree: 2,
        terms: body
            .into_iter()
            .map(|(coefficient, column, shift)| {
                term(
                    coefficient,
                    vec![factor(selector, 0, 1), factor(column, shift, 1)],
                )
            })
            .collect(),
    }
}

// The set of constraints, built out of the maps. A map that did not hold a cell would be a map of
// another width than this permutation has, and the answer to that is nothing rather than a circuit.
pub fn description() -> Option<Description> {
    let external = super::external_map();
    let internal = super::internal_map();
    let mut constraints = Vec::new();
    for slot in 0..LANES_PER_ROW {
        constraints.extend(sbox_of_slot(slot));
    }

    // The turn of the ring: what stood three places on stands here, and the three lanes that went
    // through the S-box enter at the end.
    for cell in 0..WIDTH {
        let body = if cell + LANES_PER_ROW < WIDTH {
            vec![
                (F::ONE, RING + cell, 1),
                (F::ONE.negated(), RING + cell + LANES_PER_ROW, 0),
            ]
        } else {
            let slot = cell + LANES_PER_ROW - WIDTH;
            vec![
                (F::ONE, RING + cell, 1),
                (
                    F::ONE.negated(),
                    WORK + slot * CELLS_PER_LANE + CELLS_PER_LANE - 1,
                    0,
                ),
            ]
        };
        constraints.push(under(SEL_TURN, body));
    }

    // The linear layer of a round of the full kind, and the opening one: the ring stands in its own
    // order by then, so the map applies to it as it is.
    for out in 0..WIDTH {
        let mut body = vec![(F::ONE, RING + out, 1)];
        for from in 0..WIDTH {
            let coefficient = external.coefficient(out, from)?;
            if !coefficient.is_zero() {
                body.push((coefficient.negated(), RING + from, 0));
            }
        }
        constraints.push(under(SEL_LINEAR, body));
    }

    // A round of the partial kind: the first lane through the S-box, every other lane as it stands,
    // and the map of the partial rounds over the two — all of it in one row.
    for out in 0..WIDTH {
        let mut body = vec![(F::ONE, RING + out, 1)];
        let first = internal.coefficient(out, 0)?;
        if !first.is_zero() {
            body.push((first.negated(), WORK + CELLS_PER_LANE - 1, 0));
        }
        for from in 1..WIDTH {
            let coefficient = internal.coefficient(out, from)?;
            if !coefficient.is_zero() {
                body.push((coefficient.negated(), RING + from, 0));
            }
        }
        constraints.push(under(SEL_PARTIAL, body));
    }

    Some(Description {
        trace_width: TRACE_WIDTH as u16,
        rows_log2: 0,
        periodic: periodic_columns(),
        constraints,
        boundaries: Vec::new(),
    })
}

// The description at a stated height, with the state entering and the state leaving the first
// permutation of the trace held to the public input it is offered against.
pub fn description_at(rows_log2: u8) -> Option<Description> {
    let rows = 1usize << rows_log2;
    if !rows.is_multiple_of(period()) {
        return None;
    }
    let mut held = description()?;
    held.rows_log2 = rows_log2;
    for cell in 0..WIDTH {
        held.boundaries.push(Boundary {
            column: (RING + cell) as u16,
            row: 0,
            value: BoundaryValue::Word((cell * 2) as u16),
        });
        held.boundaries.push(Boundary {
            column: (RING + cell) as u16,
            row: (ROWS_PER_PERMUTATION - 1) as u64,
            value: BoundaryValue::Word(((WIDTH + cell) * 2) as u16),
        });
    }
    Some(held)
}

// The trace the description is satisfied by: the permutation run once per block of the schedule,
// writing what every row of it stands for. Nothing here decides anything — the values are the
// permutation's own, and the layout is the one above.
pub fn trace_of(input: &[F; WIDTH], rows_log2: u8) -> Option<Vec<Vec<F>>> {
    let rows = 1usize << rows_log2;
    if !rows.is_multiple_of(period()) {
        return None;
    }
    let mut columns = vec![vec![F::ZERO; rows]; TRACE_WIDTH];
    for block in 0..rows / period() {
        write_block(&mut columns, block, input)?;
    }
    Some(columns)
}

// One block of the schedule, written where it stands: the state entering it at the first row, the
// workspace of every row beside it, and the state the permutation leaves at the last. What it
// answers with is that state, so a chain of blocks is this function called along a chain of
// states — and the layer above wires the chain rather than restating the permutation.
pub fn write_block(columns: &mut [Vec<F>], block: usize, input: &[F; WIDTH]) -> Option<[F; WIDTH]> {
    let external = super::external_map();
    let internal = super::internal_map();
    let base = block * period();
    if columns.len() < TRACE_WIDTH || columns[0].len() < base + period() {
        return None;
    }
    let mut state = *input;
    for (at, (rule, round, turn)) in schedule().iter().enumerate() {
        let row = base + at;
        for (cell, value) in state.iter().enumerate() {
            columns[RING + cell][row] = *value;
        }
        // The workspace of a row is the S-box of what the ring carries in its first places,
        // whether or not the rule of the row consumes it: a chain standing at every row is what
        // keeps the chain out of the schedule.
        let mut seventh = [F::ZERO; LANES_PER_ROW];
        for (slot, held) in seventh.iter_mut().enumerate() {
            let constant = match rule {
                Rule::Turn => {
                    poseidon::round_constant(*round, turn * LANES_PER_ROW + slot).unwrap_or(F::ZERO)
                }
                Rule::Partial if slot == 0 => {
                    poseidon::round_constant(*round, 0).unwrap_or(F::ZERO)
                }
                _ => F::ZERO,
            };
            let y = state[slot].plus(constant);
            let square = y.times(y);
            let cube = square.times(y);
            let fourth = square.times(square);
            *held = cube.times(fourth);
            let work = WORK + slot * CELLS_PER_LANE;
            columns[work][row] = square;
            columns[work + 1][row] = cube;
            columns[work + 2][row] = fourth;
            columns[work + 3][row] = *held;
        }
        match rule {
            Rule::Turn => {
                let mut next = [F::ZERO; WIDTH];
                for (cell, slot) in next.iter_mut().enumerate() {
                    *slot = if cell + LANES_PER_ROW < WIDTH {
                        state[cell + LANES_PER_ROW]
                    } else {
                        seventh[cell + LANES_PER_ROW - WIDTH]
                    };
                }
                state = next;
            }
            Rule::Linear => state = external.apply(&state),
            Rule::Partial => {
                let mut held = state;
                held[0] = seventh[0];
                state = internal.apply(&held);
            }
            Rule::Answer => {}
        }
    }
    Some(state)
}

// The public input the boundaries of this description are read against: the state entering the
// first permutation and the state leaving it, each cell as the two limbs a word stands in.
pub fn public_of(input: &[F; WIDTH]) -> Vec<u8> {
    let mut out = Vec::with_capacity(WIDTH * 2 * 8);
    let mut held = *input;
    for cell in held.iter() {
        out.extend_from_slice(&cell.as_u64().to_le_bytes());
    }
    poseidon::permute(&mut held);
    for cell in held.iter() {
        out.extend_from_slice(&cell.as_u64().to_le_bytes());
    }
    out
}

// A cell of this permutation is a word of the field and a word of the public input is two limbs, so
// the two agree exactly where the field stands below two to the sixty-fourth. It does.
pub fn a_cell_is_a_word() -> bool {
    P < u64::MAX
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input() -> [F; WIDTH] {
        let mut out = [F::ZERO; WIDTH];
        for (at, cell) in out.iter_mut().enumerate() {
            *cell = F::from_u64_reduced(at as u64);
        }
        out
    }

    // The layout, counted: what the rows come to and what the block closes on. A block that did not
    // close on a power of two would have no periodic column to carry its schedule.
    #[test]
    fn the_layout_costs_what_the_bounds_leave_it() {
        assert_eq!(TRACE_WIDTH, 16);
        assert_eq!(TURNS, 12);
        assert_eq!(ROWS_PER_FULL_ROUND, 13);
        assert_eq!(ROWS_PER_PERMUTATION, 128);
        assert_eq!(period(), 128);
        assert_eq!(ROWS_PER_PERMUTATION, crate::params::ROWS_PER_PERMUTATION);
        assert!(a_cell_is_a_word());
    }

    // Every constraint of this circuit stands inside the shape: the width, the degree, the rows a
    // factor may name. What refuses each of them is the door a description passes through.
    #[test]
    fn the_description_stands_inside_the_shape() {
        let held = description_at(8).expect("a height of four blocks");
        held.check().expect("the description stands");
        for constraint in &held.constraints {
            assert!(constraint.degree <= crate::params::DEGREE_BOUND);
            for term in &constraint.terms {
                for factor in &term.factors {
                    assert!(factor.shift <= 1, "a factor names a further row");
                }
            }
        }
    }

    // The trace of the permutation satisfies the constraints, and the answer it leaves is the
    // permutation's own. Two blocks stand in one trace, so the schedule is exercised where it
    // repeats rather than only where it starts.
    #[test]
    fn the_trace_of_the_permutation_satisfies_the_circuit() {
        // Four blocks in one trace, so the schedule is exercised where it repeats rather than only
        // where it starts, and the wrap of the last row onto the first is exercised with it.
        let held = description_at(8).expect("a height of four blocks");
        let trace = trace_of(&input(), 8).expect("a height of four blocks");
        let public = crate::poseidon::limbs_of(&public_of(&input()));
        assert!(
            held.satisfied_by(&trace, &public),
            "the trace does not satisfy"
        );

        // And what the circuit says the answer is, is what the permutation says it is.
        let mut expected = input();
        crate::poseidon::permute(&mut expected);
        for (cell, value) in expected.iter().enumerate() {
            assert_eq!(
                trace[RING + cell][ROWS_PER_PERMUTATION - 1],
                *value,
                "cell {cell}"
            );
        }
    }

    // A trace that moved one cell of the answer no longer satisfies the circuit: the boundary is
    // what holds the answer to the public input, and it is checked here where it is cheap.
    #[test]
    fn a_moved_answer_no_longer_satisfies() {
        let held = description_at(8).expect("a height of four blocks");
        let mut trace = trace_of(&input(), 8).expect("a height of four blocks");
        let public = crate::poseidon::limbs_of(&public_of(&input()));
        trace[RING][ROWS_PER_PERMUTATION - 1] = trace[RING][ROWS_PER_PERMUTATION - 1].plus(F::ONE);
        assert!(!held.satisfied_by(&trace, &public));
    }

    // The whole of it, through the machine a proof actually travels: a permutation proven and
    // verified as bytes. What this says that a satisfied trace does not is that the circuit stands
    // inside the shape of a proof — its degree folds to the tail, its width fits the slot, and the
    // answer it carries is held to the public input by a boundary rather than by the prover's word.
    #[test]
    fn a_permutation_is_proven_and_verified_as_bytes() {
        let held = description_at(8).expect("a height of four blocks");
        let trace = trace_of(&input(), 8).expect("a height of four blocks");
        let public = public_of(&input());
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true trace proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));

        // A proof of this permutation does not stand for another input: the answer of the one is
        // not the answer of the other, and the boundary is what refuses it.
        let mut other = input();
        other[0] = other[0].plus(F::ONE);
        assert!(crate::scheme::verify(&held, &public_of(&other), &bytes).is_err());
    }

    // A trace that claims an answer the permutation does not give has no proof at all: the prover
    // refuses it where the trace fails the description, rather than writing bytes nobody accepts.
    #[test]
    fn a_claimed_answer_the_permutation_does_not_give_has_no_proof() {
        let held = description_at(8).expect("a height of four blocks");
        let mut trace = trace_of(&input(), 8).expect("a height of four blocks");
        let public = public_of(&input());
        trace[RING][ROWS_PER_PERMUTATION - 1] = trace[RING][ROWS_PER_PERMUTATION - 1].plus(F::ONE);
        assert_eq!(
            crate::scheme::prove(&held, &public, &trace).err(),
            Some(crate::scheme::ProveError::TraceDoesNotSatisfy)
        );
    }

    // A height that carries a part of a block carries no permutation at all, and the answer is
    // nothing rather than a trace whose schedule runs off its end.
    #[test]
    fn a_height_that_carries_a_part_of_a_block_is_refused() {
        assert!(description_at(4).is_none());
        assert!(trace_of(&input(), 4).is_none());
    }
}
