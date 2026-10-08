// The circuit of a frame, and the gadgets it is assembled from. What stands here so far is the
// ground every gadget of the tree of notes rests on: the permutation of the proof hash read as
// arithmetic a constraint set can assert.
//
// Nothing here transcribes the permutation. The two linear layers are **taken from it** — applied
// to the unit vectors of the state, which is what a linear map is — and the constants of a round
// are read from the row that holds them. A circuit carrying its own copy of either would be the
// second place that parts from the first the day one of them moves, and the whole point of a
// circuit is that it asserts the same function a verifier of the network computes.

pub mod admission;
pub mod branch;
pub mod capacity;
pub mod discharge;
pub mod fold;
pub mod frame;
pub mod lane;
pub mod moment;
pub mod opening;
pub mod path;
pub mod permutation;
pub mod presence;
pub mod redemption;
pub mod reduce;
pub mod sponge;
pub mod value;
pub mod window;

use crate::field::F;
use crate::poseidon::{self, WIDTH};

// A linear map of the state, as the coefficients a constraint multiplies by. Row `i` holds what
// the output cell `i` takes from every input cell.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Linear([[F; WIDTH]; WIDTH]);

impl Linear {
    pub fn coefficient(&self, out: usize, from: usize) -> Option<F> {
        Some(*self.0.get(out)?.get(from)?)
    }

    pub fn apply(&self, state: &[F; WIDTH]) -> [F; WIDTH] {
        let mut out = [F::ZERO; WIDTH];
        for (i, slot) in out.iter_mut().enumerate() {
            let mut sum = F::ZERO;
            for (j, value) in state.iter().enumerate() {
                sum = sum.plus(self.0[i][j].times(*value));
            }
            *slot = sum;
        }
        out
    }
}

// The map a layer is, taken by applying it to the unit vectors. A layer of this permutation is
// linear and has no constant part, so the columns of its matrix are its answers to the units, and
// the test below holds the two against each other over inputs neither of them chose.
fn map_of(layer: fn(&mut [F; WIDTH])) -> Linear {
    let mut columns = [[F::ZERO; WIDTH]; WIDTH];
    for (j, column) in columns.iter_mut().enumerate() {
        let mut unit = [F::ZERO; WIDTH];
        unit[j] = F::ONE;
        layer(&mut unit);
        *column = unit;
    }
    let mut rows = [[F::ZERO; WIDTH]; WIDTH];
    for (i, row) in rows.iter_mut().enumerate() {
        for (j, slot) in row.iter_mut().enumerate() {
            *slot = columns[j][i];
        }
    }
    Linear(rows)
}

pub fn external_map() -> Linear {
    map_of(poseidon::external)
}

pub fn internal_map() -> Linear {
    map_of(poseidon::internal)
}

// The permutation, run again out of the two maps and the constants of the rounds rather than out
// of its own body. It exists for one reason: what a circuit asserts is this shape, so the shape is
// held against the permutation itself before a constraint is written over it. Where the two part,
// the circuit would be asserting a function this network does not compute.
pub fn permute_by_maps(state: &mut [F; WIDTH]) -> Option<()> {
    let external = external_map();
    let internal = internal_map();
    *state = external.apply(state);
    for round in 0..poseidon::ROUNDS_TOTAL {
        if poseidon::round_is_external(round) {
            for (lane, cell) in state.iter_mut().enumerate() {
                *cell = seventh(cell.plus(poseidon::round_constant(round, lane)?));
            }
            *state = external.apply(state);
        } else {
            state[0] = seventh(state[0].plus(poseidon::round_constant(round, 0)?));
            *state = internal.apply(state);
        }
    }
    Some(())
}

// The S-box, in the four multiplications a constraint of degree two admits: nothing raises to the
// seventh in one step here, and the chain below is the one a gadget writes as four cells.
pub fn seventh(x: F) -> F {
    let square = x.times(x);
    let cube = square.times(x);
    let fourth = square.times(square);
    cube.times(fourth)
}

pub fn widen(held: &mut crate::air::Description, trace_width: usize) {
    let held_width = usize::from(held.trace_width);
    if trace_width <= held_width {
        return;
    }
    let shift = (trace_width - held_width) as u16;
    held.trace_width = trace_width as u16;
    for constraint in held.constraints.iter_mut() {
        for term in constraint.terms.iter_mut() {
            for factor in term.factors.iter_mut() {
                if usize::from(factor.column) >= held_width {
                    factor.column += shift;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // xorshift64*, seeded once: the same run on every machine.
    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            let mut x = self.0;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            self.0 = x;
            x.wrapping_mul(0x2545_F491_4F6C_DD1D)
        }

        fn state(&mut self) -> [F; WIDTH] {
            let mut out = [F::ZERO; WIDTH];
            for cell in out.iter_mut() {
                *cell = F::from_u64_reduced(self.next() % crate::field::P);
            }
            out
        }
    }

    // A map taken from the unit vectors is the layer itself only where the layer is linear. It is,
    // and this is what says so: over states neither the map nor the layer had a hand in choosing.
    #[test]
    fn the_maps_are_the_layers_they_were_taken_from() {
        let external = external_map();
        let internal = internal_map();
        let mut rng = Rng(0x4D54_5F43_4952_4331);
        for _ in 0..200 {
            let state = rng.state();
            let mut by_layer = state;
            poseidon::external(&mut by_layer);
            assert_eq!(external.apply(&state), by_layer);

            let mut by_layer = state;
            poseidon::internal(&mut by_layer);
            assert_eq!(internal.apply(&state), by_layer);
        }
    }

    // The chain of four multiplications against the exponent it stands for.
    #[test]
    fn the_chain_of_four_is_the_seventh_power() {
        let mut rng = Rng(0x4D54_5F43_4952_4332);
        for _ in 0..500 {
            let x = rng.state()[0];
            assert_eq!(seventh(x), x.pow(7));
        }
        assert_eq!(seventh(F::ZERO), F::ZERO);
        assert_eq!(seventh(F::ONE), F::ONE);
    }

    // The whole permutation, rebuilt out of the maps and the constants, against the permutation
    // itself — including the known answer of its authors, so the rebuild is held to the same value
    // the primitive is.
    #[test]
    fn the_permutation_rebuilt_from_the_maps_is_the_permutation() {
        let mut rng = Rng(0x4D54_5F43_4952_4333);
        for _ in 0..20 {
            let state = rng.state();
            let mut by_body = state;
            poseidon::permute(&mut by_body);
            let mut by_maps = state;
            permute_by_maps(&mut by_maps).expect("every round names its constants");
            assert_eq!(by_maps, by_body);
        }

        let mut authors = [F::ZERO; WIDTH];
        for (at, cell) in authors.iter_mut().enumerate() {
            *cell = F::from_u64_reduced(at as u64);
        }
        permute_by_maps(&mut authors).expect("every round names its constants");
        assert_eq!(authors[0].as_u64(), 0x01ea_ef96_bdf1_c0c1);
        assert_eq!(authors[11].as_u64(), 0x6a50_450d_df85_a6ed);
    }

    // A round beyond the count of them answers nothing rather than a value of the last one.
    #[test]
    fn a_round_the_permutation_does_not_hold_names_no_constant() {
        assert!(poseidon::round_constant(poseidon::ROUNDS_TOTAL, 0).is_none());
        assert!(poseidon::round_constant(0, WIDTH).is_none());
        assert!(poseidon::round_constant(0, 0).is_some());
    }
}

// A description written over one width, carried to a wider trace. A column at or above the width
// names a periodic column, so widening the trace moves every such reference by exactly what the
// width moved — and this is the one place that arithmetic is written, since every layer above the
// permutation needs it and two copies of it would part at the first column either layer gained.
