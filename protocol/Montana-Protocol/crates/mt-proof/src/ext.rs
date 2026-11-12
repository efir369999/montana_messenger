// The field every challenge is drawn in, and the one no challenge is ever drawn out of. The set
// derives the degree rather than choosing it: the soundness of the mixing and of the deep
// composition is the degree of the trace over the size of the field a challenge came from, and
// the base field and a quadratic extension both fall short of the target where the cubic does not.
//
// An element is three coefficients over the base field, least significant first, which is also the
// order it stands in on the wire — twenty-four bytes, as the parts of a proof state.

use crate::field::F;

mt_codec::constants! {
    EXTENSION:
    /// The residue the extension closes on: `X³ − 7`, so `X³` folds to this.
    pub const RESIDUE: u64 = 7, writes "`proof_field[X] / (X³ − 7)`";
    /// The width of one element on the wire.
    pub const ELEMENT_BYTES: usize = 24, writes "one element of `proof_challenge_field` each, 24 B";
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct E([F; 3]);

impl E {
    pub const ZERO: E = E([F::ZERO, F::ZERO, F::ZERO]);
    pub const ONE: E = E([F::ONE, F::ZERO, F::ZERO]);

    pub fn of(a: F, b: F, c: F) -> E {
        E([a, b, c])
    }

    // A value of the base field standing in the extension: the field a challenge is drawn in holds
    // the field the trace stands in, and a constraint mixes the two.
    pub fn from_base(value: F) -> E {
        E([value, F::ZERO, F::ZERO])
    }

    pub fn coefficients(self) -> [F; 3] {
        self.0
    }

    pub fn is_zero(self) -> bool {
        self.0.iter().all(|c| c.is_zero())
    }

    pub fn plus(self, other: E) -> E {
        E([
            self.0[0].plus(other.0[0]),
            self.0[1].plus(other.0[1]),
            self.0[2].plus(other.0[2]),
        ])
    }

    pub fn minus(self, other: E) -> E {
        E([
            self.0[0].minus(other.0[0]),
            self.0[1].minus(other.0[1]),
            self.0[2].minus(other.0[2]),
        ])
    }

    pub fn negated(self) -> E {
        E::ZERO.minus(self)
    }

    // The product of two polynomials of degree two, with everything above the second degree folded
    // back by the residue: `X³` is the residue, so `X⁴` is the residue times `X`.
    pub fn times(self, other: E) -> E {
        let (a, b) = (self.0, other.0);
        let residue = F::from_u64_reduced(RESIDUE);
        let m = |x: F, y: F| x.times(y);
        let c0 = m(a[0], b[0]).plus(residue.times(m(a[1], b[2]).plus(m(a[2], b[1]))));
        let c1 = m(a[0], b[1])
            .plus(m(a[1], b[0]))
            .plus(residue.times(m(a[2], b[2])));
        let c2 = m(a[0], b[2]).plus(m(a[1], b[1])).plus(m(a[2], b[0]));
        E([c0, c1, c2])
    }

    pub fn mul_base(self, scalar: F) -> E {
        E([
            self.0[0].times(scalar),
            self.0[1].times(scalar),
            self.0[2].times(scalar),
        ])
    }

    pub fn square(self) -> E {
        self.times(self)
    }

    // The exponent of an inverse is `p³ − 2`, which is wider than a machine word, so it is walked
    // as the three words it is rather than held as one number this machine does not have.
    pub fn pow(self, exponent: [u64; 3]) -> E {
        let mut result = E::ONE;
        let mut base = self;
        for word in exponent {
            let mut bits = word;
            for _ in 0..64 {
                if bits & 1 == 1 {
                    result = result.times(base);
                }
                base = base.square();
                bits >>= 1;
            }
        }
        result
    }

    pub fn inverse(self) -> Option<E> {
        (!self.is_zero()).then(|| self.pow(order_less_two()))
    }

    // Least significant coefficient first, each of eight bytes, which is what the parts of a proof
    // and the openings of a folding layer are written in.
    pub fn to_bytes(self) -> [u8; ELEMENT_BYTES] {
        let mut out = [0u8; ELEMENT_BYTES];
        for (at, coefficient) in self.0.iter().enumerate() {
            out[at * 8..at * 8 + 8].copy_from_slice(&coefficient.as_u64().to_le_bytes());
        }
        out
    }

    // A value carrying a coefficient at or above the modulus is not an element of this field: it
    // is refused rather than folded, exactly as in the base field.
    pub fn from_bytes(bytes: &[u8; ELEMENT_BYTES]) -> Option<E> {
        let mut out = [F::ZERO; 3];
        for (at, slot) in out.iter_mut().enumerate() {
            let mut eight = [0u8; 8];
            eight.copy_from_slice(&bytes[at * 8..at * 8 + 8]);
            *slot = F::try_from_u64(u64::from_le_bytes(eight))?;
        }
        Some(E(out))
    }
}

// `p³ − 2`, in the three words the exponentiation walks, least significant first.
fn order_less_two() -> [u64; 3] {
    let p = u128::from(crate::field::P);
    let square = p * p;
    // `p³` in three words: the square is under `2^128`, so the cube is taken word by word.
    let low = square as u64;
    let high = (square >> 64) as u64;
    let (w0, carry0) = mul_wide(low, crate::field::P);
    let (w1, carry1) = mul_wide(high, crate::field::P);
    let (w1, extra) = w1.overflowing_add(carry0);
    let w2 = carry1 + u64::from(extra);
    let (w0, borrow) = w0.overflowing_sub(2);
    let (w1, borrow) = w1.overflowing_sub(u64::from(borrow));
    let w2 = w2 - u64::from(borrow);
    [w0, w1, w2]
}

fn mul_wide(a: u64, b: u64) -> (u64, u64) {
    let wide = u128::from(a) * u128::from(b);
    (wide as u64, (wide >> 64) as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

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

        fn element(&mut self) -> E {
            E([
                F::from_u64_reduced(self.next() % crate::field::P),
                F::from_u64_reduced(self.next() % crate::field::P),
                F::from_u64_reduced(self.next() % crate::field::P),
            ])
        }
    }

    #[test]
    fn the_extension_holds_its_own_laws() {
        let mut rng = Rng(0x4D54_5F45_5854_0001);
        for _ in 0..2_000 {
            let (a, b, c) = (rng.element(), rng.element(), rng.element());
            assert_eq!(a.plus(b), b.plus(a));
            assert_eq!(a.times(b), b.times(a));
            assert_eq!(a.times(b).times(c), a.times(b.times(c)));
            assert_eq!(a.times(b.plus(c)), a.times(b).plus(a.times(c)));
            assert_eq!(a.minus(a), E::ZERO);
            assert_eq!(a.times(E::ONE), a);
        }
    }

    // The residue is what makes this a field rather than a ring with zero divisors: seven is a
    // non-residue of this prime, so `X³ − 7` has no root and every non-zero element inverts.
    #[test]
    fn every_element_but_zero_inverts() {
        let mut rng = Rng(0x4D54_5F45_5854_0002);
        for _ in 0..200 {
            let a = rng.element();
            if a.is_zero() {
                continue;
            }
            assert_eq!(
                a.times(a.inverse().expect("a non-zero element inverts")),
                E::ONE
            );
        }
        assert_eq!(E::ZERO.inverse(), None);
        // And the residue itself has no cube root in the base field, which is the property the
        // choice rests on: a root would factor the polynomial and the extension would not be one.
        let residue = F::from_u64_reduced(RESIDUE);
        let exponent = (crate::field::P - 1) / 3;
        assert_ne!(residue.pow(exponent), F::ONE);
    }

    #[test]
    fn the_bytes_of_an_element_round_trip_and_refuse_a_value_of_another_field() {
        let mut rng = Rng(0x4D54_5F45_5854_0003);
        for _ in 0..1_000 {
            let a = rng.element();
            assert_eq!(E::from_bytes(&a.to_bytes()), Some(a));
        }
        let mut bytes = [0u8; ELEMENT_BYTES];
        bytes[..8].copy_from_slice(&crate::field::P.to_le_bytes());
        assert_eq!(E::from_bytes(&bytes), None);
    }

    // The exponent an inverse walks is `p³ − 2`, and a wrong one gives a wrong inverse on every
    // element rather than on some, so it is checked as a number before it is used as an exponent.
    #[test]
    fn the_exponent_of_an_inverse_is_the_order_of_the_field_less_two() {
        let words = order_less_two();
        let p = u128::from(crate::field::P);
        let cube_low = (p * p).wrapping_mul(p);
        assert_eq!(words[0], (cube_low as u64).wrapping_sub(2));
    }
}
