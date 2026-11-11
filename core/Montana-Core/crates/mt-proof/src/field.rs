// The field of the proof scheme: the prime the set names, and nothing of a width. Two
// implementations over two sixty-four-bit primes compute two different proofs, so what is
// transcribed here is the modulus itself.
//
// The reduction is the one the set gives its reason from: a product of two elements is folded by
// shifts and additions and never by a division, which is what the choice of the prime buys. It is
// held against the plain arithmetic over a wider integer by a test, because a reduction that is
// faster and wrong is the worst of the three possibilities.

use core::fmt;

mt_codec::constants! {
    FIELD:
    /// The modulus. The set writes it as an expression rather than as digits, so what holds the
    /// number to the set is the expression itself, evaluated below where it cannot drift: a
    /// comparison of text would say the words agree and never that the number does.
    pub const P: u64 = 0xFFFF_FFFF_0000_0001, code "the modulus the set writes as 2^64 - 2^32 + 1";
}

// The number against the expression, in a constant: a modulus that is not the one the set writes
// fails the build rather than a test, and two primes of one width are two protocols.
const _: () = {
    assert!(
        P as u128 == (1u128 << 64) - (1u128 << 32) + 1,
        "the modulus is not the one the set writes"
    );
};

mt_codec::constants! {
    FOLD_OF_THE_PRIME:
    /// What the reduction folds by: the prime is `2^64` less this, so a carry out of the low word
    /// costs exactly this much. It is the modulus read another way rather than a number of its
    /// own, and it enters no object.
    const FOLD: u64 = 0xFFFF_FFFF, code "the complement of the prime, by which its reduction folds";
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct F(u64);

impl fmt::Debug for F {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl F {
    pub const ZERO: F = F(0);
    pub const ONE: F = F(1);

    // A value at or above the modulus is not an element of this field: it is refused rather than
    // reduced, since a description or a proof carrying one is over another field.
    pub fn try_from_u64(value: u64) -> Option<F> {
        (value < P).then_some(F(value))
    }

    pub fn from_u64_reduced(value: u64) -> F {
        F(if value >= P { value - P } else { value })
    }

    pub fn as_u64(self) -> u64 {
        self.0
    }

    pub fn is_zero(self) -> bool {
        self.0 == 0
    }

    pub fn plus(self, other: F) -> F {
        let (sum, carry) = self.0.overflowing_add(other.0);
        let sum = if carry { sum.wrapping_add(FOLD) } else { sum };
        F(if sum >= P { sum - P } else { sum })
    }

    pub fn minus(self, other: F) -> F {
        let (difference, borrow) = self.0.overflowing_sub(other.0);
        F(if borrow {
            difference.wrapping_sub(FOLD)
        } else {
            difference
        })
    }

    pub fn negated(self) -> F {
        F::ZERO.minus(self)
    }

    pub fn times(self, other: F) -> F {
        F(reduce(u128::from(self.0) * u128::from(other.0)))
    }

    pub fn square(self) -> F {
        self.times(self)
    }

    pub fn pow(self, exponent: u64) -> F {
        let mut result = F::ONE;
        let mut base = self;
        let mut left = exponent;
        while left > 0 {
            if left & 1 == 1 {
                result = result.times(base);
            }
            base = base.square();
            left >>= 1;
        }
        result
    }

    // The inverse by the little theorem. Zero has none, which is answered rather than assumed.
    pub fn inverse(self) -> Option<F> {
        (!self.is_zero()).then(|| self.pow(P - 2))
    }
}

// The fold of a product into the field, by shifts and additions. What it rests on is the shape of
// the prime, so the two high words fold down without a division anywhere.
fn reduce(wide: u128) -> u64 {
    let low = wide as u64;
    let high = (wide >> 64) as u64;
    let high_high = high >> 32;
    let high_low = high & FOLD;

    let (partial, borrow) = low.overflowing_sub(high_high);
    let partial = if borrow {
        partial.wrapping_sub(FOLD)
    } else {
        partial
    };

    let folded = high_low * FOLD;
    let (result, carry) = partial.overflowing_add(folded);
    let result = if carry {
        result.wrapping_add(FOLD)
    } else {
        result
    };
    if result >= P {
        result - P
    } else {
        result
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

        fn element(&mut self) -> F {
            F::from_u64_reduced(self.next() % P)
        }
    }

    // The fold by shifts against the fold by a division, over values chosen to sit at every
    // boundary it has. The named wrong implementation this catches is the one that drops the
    // borrow of the high word: it agrees on small values and parts on large ones.
    #[test]
    fn the_fold_agrees_with_the_arithmetic_it_replaces() {
        let wide = |a: u64, b: u64| ((u128::from(a) * u128::from(b)) % u128::from(P)) as u64;
        let mut rng = Rng(0x4D54_5F50_524F_4F46);
        for _ in 0..20_000 {
            let (a, b) = (rng.element(), rng.element());
            assert_eq!(
                a.times(b).as_u64(),
                wide(a.as_u64(), b.as_u64()),
                "{a:?} {b:?}"
            );
        }
        for a in [
            0u64,
            1,
            2,
            P - 1,
            P - 2,
            FOLD,
            FOLD + 1,
            1 << 63,
            u64::MAX % P,
        ] {
            for b in [
                0u64,
                1,
                2,
                P - 1,
                P - 2,
                FOLD,
                FOLD + 1,
                1 << 63,
                u64::MAX % P,
            ] {
                let (x, y) = (F::from_u64_reduced(a), F::from_u64_reduced(b));
                assert_eq!(x.times(y).as_u64(), wide(a, b), "{a} {b}");
            }
        }
    }

    #[test]
    fn the_field_holds_its_own_laws() {
        let mut rng = Rng(0x4D54_5F50_524F_4F47);
        for _ in 0..5_000 {
            let (a, b, c) = (rng.element(), rng.element(), rng.element());
            assert_eq!(a.plus(b), b.plus(a));
            assert_eq!(a.times(b), b.times(a));
            assert_eq!(a.plus(b).plus(c), a.plus(b.plus(c)));
            assert_eq!(a.times(b).times(c), a.times(b.times(c)));
            assert_eq!(a.times(b.plus(c)), a.times(b).plus(a.times(c)));
            assert_eq!(a.minus(a), F::ZERO);
            assert_eq!(a.plus(a.negated()), F::ZERO);
            assert_eq!(a.times(F::ONE), a);
            if !a.is_zero() {
                assert_eq!(
                    a.times(a.inverse().expect("a non-zero element inverts")),
                    F::ONE
                );
            }
        }
        assert_eq!(F::ZERO.inverse(), None);
    }

    // A value at the modulus is not an element: a description or a proof carrying one is over
    // another field, and the door says so rather than folding it into range.
    #[test]
    fn a_value_at_or_above_the_modulus_is_refused_rather_than_folded() {
        assert_eq!(F::try_from_u64(P), None);
        assert_eq!(F::try_from_u64(P + 1), None);
        assert_eq!(F::try_from_u64(u64::MAX), None);
        assert_eq!(F::try_from_u64(P - 1).map(F::as_u64), Some(P - 1));
    }

    // The subgroup the set derives from the prime: an element of order `2^32` stands, and the
    // domains of this scheme sit nine doublings below it.
    #[test]
    fn the_prime_carries_the_subgroup_the_set_derives_from_it() {
        assert_eq!(P - 1, (1u64 << 32) * FOLD);
    }
}
