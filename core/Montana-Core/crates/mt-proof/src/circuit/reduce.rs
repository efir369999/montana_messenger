// A public constant times a value, brought back under the modulus of the lattice: the atom every
// product of an opening is built from.
//
// **Why the quotient carries bits of its own.** The equality this row asserts is
// `constant x = q m + z`, over the field of proofs — and over that field the pair `(m, z)` is
// unique only while both are held in range. A remainder held and a quotient free is no reduction at
// all: the prover picks a quotient large enough to wrap the field and the remainder takes any value
// they like. So the quotient is decomposed as the remainder is, and the row spends more columns on
// the quotient than on anything it computes — which is the general shape of circuits: a value costs
// what holding it in range costs, not what its arithmetic costs.
//
// **Why the constant gates the row and no schedule column is spent.** The constant arrives as a
// periodic column of the assembler — the transforms of a public matrix are constants of the
// circuit, not things to compute. Where that column is zero the equality collapses to
// `q m + z = 0`, which over held bits means every bit is zero; so an idle row is idle by the
// constant alone, and gating by a schedule would only raise the degree past what the scheme admits.
//
// **The bounds, stated once.** The value taken in stands below two to the twenty-seventh — the
// widest an input grows across the layers of a transform before its next product renormalizes it —
// and the constant below the modulus, so the product stands below two to the fiftieth and the
// quotient below two to the twenty-seventh. The remainder is held below two to the twenty-third and
// is not held canonical: a lazy remainder is congruent regardless of which representative the
// prover chose, and only the final comparison of an opening is made canonical, once, where it is
// compared.

use super::sponge::{factor, term};
use crate::air::Constraint;
use crate::field::F;

mt_codec::constants! {
    REDUCE:
    /// The bits a quotient of a product is held below.
    pub const QUOTIENT_BITS: usize = 27, code "the bits the quotient of a reduction is held below: a product of a lane below two to the fiftieth over the modulus";
    /// The bits a remainder is held below. One above the modulus, and lazily so: congruent, not canonical.
    pub const REMAINDER_BITS: usize = 23, code "the bits the remainder of a reduction is held below";
    /// The columns one reduction costs: the value, its quotient bits and its remainder bits.
    pub const COLUMNS_OF_A_REDUCTION: usize = 51, code "the columns one reduction costs: the value taken in, the bits of its quotient and the bits of its remainder";
}

// The columns this layer adds after those below it: the value taken in, then the bits.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Places {
    pub value: usize,
}

impl Places {
    pub const fn after(width: usize) -> Self {
        Self { value: width }
    }

    pub const fn quotient_bit(&self, bit: usize) -> usize {
        self.value + 1 + bit
    }

    pub const fn remainder_bit(&self, bit: usize) -> usize {
        self.value + 1 + QUOTIENT_BITS + bit
    }

    pub const fn width(&self) -> usize {
        self.value + COLUMNS_OF_A_REDUCTION
    }
}

// Every rule this layer adds: a bit is a bit, and the one equality of the row. The column the
// constant stands in belongs to the assembler and arrives by its number.
pub fn constraints(places: &Places, constant_column: usize, modulus: u64) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let mut out = Vec::with_capacity(QUOTIENT_BITS + REMAINDER_BITS + 1);
    for bit in 0..QUOTIENT_BITS {
        let column = places.quotient_bit(bit);
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(column, 0, 2)]),
                term(minus, vec![factor(column, 0, 1)]),
            ],
        });
    }
    for bit in 0..REMAINDER_BITS {
        let column = places.remainder_bit(bit);
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(column, 0, 2)]),
                term(minus, vec![factor(column, 0, 1)]),
            ],
        });
    }
    // constant times value, less the modulus times the quotient, less the remainder: empty. The
    // recompositions are linear, so the whole row is one equality of the second degree.
    let mut held = vec![term(
        F::ONE,
        vec![factor(constant_column, 0, 1), factor(places.value, 0, 1)],
    )];
    for bit in 0..QUOTIENT_BITS {
        held.push(term(
            F::from_u64_reduced(modulus << bit).negated(),
            vec![factor(places.quotient_bit(bit), 0, 1)],
        ));
    }
    for bit in 0..REMAINDER_BITS {
        held.push(term(
            F::from_u64_reduced(1u64 << bit).negated(),
            vec![factor(places.remainder_bit(bit), 0, 1)],
        ));
    }
    out.push(Constraint {
        degree: 2,
        terms: held,
    });
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_reduction_costs_its_value_and_the_bits_of_both_halves() {
        let places = Places::after(10);
        assert_eq!(places.value, 10);
        assert_eq!(places.quotient_bit(0), 11);
        assert_eq!(places.remainder_bit(0), 11 + QUOTIENT_BITS);
        assert_eq!(places.width(), 10 + COLUMNS_OF_A_REDUCTION);
        assert_eq!(COLUMNS_OF_A_REDUCTION, 1 + QUOTIENT_BITS + REMAINDER_BITS);
    }

    #[test]
    fn every_rule_stands_within_the_degree_the_scheme_admits() {
        let places = Places::after(4);
        for rule in constraints(&places, 90, 8_380_417) {
            assert!(rule.degree <= crate::params::DEGREE_BOUND, "{rule:?}");
            for held in &rule.terms {
                let power: u8 = held.factors.iter().map(|f| f.power).sum();
                assert!(power <= crate::params::DEGREE_BOUND, "{held:?}");
            }
        }
    }

    #[test]
    fn the_row_carries_one_rule_per_bit_and_one_equality() {
        let places = Places::after(4);
        let rules = constraints(&places, 90, 8_380_417);
        assert_eq!(rules.len(), QUOTIENT_BITS + REMAINDER_BITS + 1);
        // The equality names the constant, the value and every bit, and nothing else.
        let equality = rules.last().expect("the equality stands last");
        assert_eq!(equality.terms.len(), 1 + QUOTIENT_BITS + REMAINDER_BITS);
    }

    #[test]
    fn an_honest_reduction_satisfies_the_equality_and_a_moved_remainder_does_not() {
        // Evaluated by hand against the terms, since the rule is one linear combination after the
        // product: constant x = q m + z, at x = 3, constant = 5 000 000, q the lattice modulus.
        let q: u64 = 8_380_417;
        let x: u64 = 3;
        let constant: u64 = 5_000_000;
        let product = constant * x;
        let quotient = product / q;
        let remainder = product % q;
        assert_eq!(product, q * quotient + remainder);
        assert!(quotient < (1 << QUOTIENT_BITS));
        assert!(remainder < (1 << REMAINDER_BITS));
        assert_ne!(product, q * quotient + remainder + 1);
    }
}
