// The field a line of a slot is taken over, and the line itself. A pledge carries the value of the
// line of its slot at the abscissa of the name it pledges, and two pledges of one slot on two names
// give the line at abscissa zero, which is the value that opens the lock of their machine ("The
// forfeit of a node lock, and the evidence that moves it").
//
// **Why four.** A proposer who grinds two names to one abscissa makes their pair extract nothing,
// and the birthday cost of that is the square root of the field the abscissa is drawn in: 2³² in
// the base field and 2⁹⁶ in the field of the challenges, both below the security target. So an
// abscissa is 256 bits wide, and four is the least degree over the base field that reaches that
// width. An element is four words of eight bytes, least significant first — the width of a digest
// of the proof hash, so a digest reads as an element of this field with no conversion, and the width
// of `line_value` on the wire.
//
// **Why seven.** `X⁴ − a` has no factor over a field of a prime one more than a multiple of four
// exactly when `a` is not a square there, and seven is not a square of this prime — the same seven
// the field of the challenges closes on, where it is no cube.

use crate::field::F;
use crate::poseidon::{self, Digest};
use mt_codec::domain;

mt_codec::constants! {
    LINE:
    /// The residue the field of the line closes on: `X⁴ − 7`, so `X⁴` folds to this.
    pub const RESIDUE: u64 = 7, writes "`proof_field[X] / (X⁴ − 7)`";
    /// The width of one element: four words of the base field, the width of a digest.
    pub const ELEMENT_BYTES: usize = 32, writes "four elements of `proof_field`, 32 B";
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct L([F; 4]);

impl L {
    pub const ZERO: L = L([F::ZERO; 4]);
    pub const ONE: L = L([F::ONE, F::ZERO, F::ZERO, F::ZERO]);

    pub fn of(coefficients: [F; 4]) -> L {
        L(coefficients)
    }

    // A digest of the proof hash is four elements of the base field, and so one element of this
    // field: the lock-opening value, a slope and an abscissa are each a squeeze, read as it stands.
    pub fn of_digest(digest: &Digest) -> L {
        L(*digest.elements())
    }

    pub fn coefficients(self) -> [F; 4] {
        self.0
    }

    pub fn is_zero(self) -> bool {
        self.0.iter().all(|c| c.is_zero())
    }

    pub fn plus(self, other: L) -> L {
        L(std::array::from_fn(|at| self.0[at].plus(other.0[at])))
    }

    pub fn minus(self, other: L) -> L {
        L(std::array::from_fn(|at| self.0[at].minus(other.0[at])))
    }

    // The product of two polynomials of degree three, everything at or above the fourth degree
    // folded back by the residue: `X⁴` is the residue, so `X⁴⁺ᵏ` is the residue times `Xᵏ`.
    pub fn times(self, other: L) -> L {
        let (a, b) = (self.0, other.0);
        let residue = F::from_u64_reduced(RESIDUE);
        let mut low = [F::ZERO; 4];
        let mut high = [F::ZERO; 3];
        for i in 0..4 {
            for j in 0..4 {
                let term = a[i].times(b[j]);
                if i + j < 4 {
                    low[i + j] = low[i + j].plus(term);
                } else {
                    high[i + j - 4] = high[i + j - 4].plus(term);
                }
            }
        }
        for (at, folded) in high.iter().enumerate() {
            low[at] = low[at].plus(residue.times(*folded));
        }
        L(low)
    }

    pub fn square(self) -> L {
        self.times(self)
    }

    // The exponent of an inverse is `p⁴ − 2`, four machine words, walked as the words it is.
    pub fn pow(self, exponent: [u64; 4]) -> L {
        let mut result = L::ONE;
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

    pub fn inverse(self) -> Option<L> {
        (!self.is_zero()).then(|| self.pow(order_less(2)))
    }

    // Least significant coefficient first, each of eight bytes little-endian: the layout of
    // `line_value` and of a digest alike.
    pub fn to_bytes(self) -> [u8; ELEMENT_BYTES] {
        let mut out = [0u8; ELEMENT_BYTES];
        for (at, coefficient) in self.0.iter().enumerate() {
            out[at * 8..at * 8 + 8].copy_from_slice(&coefficient.as_u64().to_le_bytes());
        }
        out
    }

    // Bytes carrying a word at or above the modulus are no element of this field and are refused,
    // not folded: a value read two ways is two values, and the second would verify against a line
    // nobody drew (Canon, "The pledge of a part": refused before the proof is verified).
    pub fn from_bytes(bytes: &[u8; ELEMENT_BYTES]) -> Option<L> {
        let mut out = [F::ZERO; 4];
        for (at, slot) in out.iter_mut().enumerate() {
            let mut eight = [0u8; 8];
            eight.copy_from_slice(&bytes[at * 8..at * 8 + 8]);
            *slot = F::try_from_u64(u64::from_le_bytes(eight))?;
        }
        Some(L(out))
    }
}

// The value a pledge carries: the line of its slot at the abscissa of its name, the lock-opening
// value plus the slope times the abscissa.
pub fn line_at(opening: L, slope: L, abscissa: L) -> L {
    opening.plus(slope.times(abscissa))
}

// The lock-opening value out of two points of one line, which is the line at abscissa zero:
// `(x₂·y₁ − x₁·y₂) / (x₂ − x₁)`. Two points at one abscissa are one point twice, a repetition on one
// name, and give nothing.
pub fn opening_of(first: (L, L), second: (L, L)) -> Option<L> {
    let ((x1, y1), (x2, y2)) = (first, second);
    let run = x2.minus(x1).inverse()?;
    Some(x2.times(y1).minus(x1.times(y2)).times(run))
}

// The slot of an object of a part in its window, as the one element the slope is drawn over:
// `2·attempt + kind`, the kind one for a closing pledge. The open slot of attempt zero, the heavy
// attestation, is slot zero, and every other slot is one more than the position of its pledge in
// its band (Canon, "Past attempt 62"), which an open pledge of attempt zero would make negative.
pub fn slot(attempt: u32, closing: bool) -> u64 {
    2 * u64::from(attempt) + u64::from(closing)
}

// The lock-opening value of a machine, from the spending half of its secret alone: one value across
// every window it lives (Canon, "The construction").
pub fn opening(spending: &Digest) -> L {
    let digest = poseidon::hash_elements(domain::MT_LINE_OPENING, spending.elements());
    L::of_digest(&digest)
}

// The slope of one slot of one window, over the spending half, the window as one element and the
// slot as one: every slot of every window has its own. A window or a slot at or above the modulus
// is no element and draws nothing, as it draws no nullifier of a part.
pub fn slope(spending: &Digest, window: u64, slot: u64) -> Option<L> {
    let mut elements = Vec::with_capacity(spending.elements().len() + 2);
    elements.extend_from_slice(spending.elements());
    elements.push(F::try_from_u64(window)?);
    elements.push(F::try_from_u64(slot)?);
    let digest = poseidon::hash_elements(domain::MT_LINE_SLOPE, &elements);
    Some(L::of_digest(&digest))
}

// The abscissa of a name, from the name alone, over its eight limbs. An abscissa of zero is refused:
// the line there is the lock-opening value itself, so a pledge on such a name would publish it.
pub fn abscissa(name: &[u8; 32]) -> Option<L> {
    let at = L::of_digest(&poseidon::hash_bytes(domain::MT_LINE_ABSCISSA, name));
    (!at.is_zero()).then_some(at)
}

// `p⁴ − k` in four words, least significant first. `p²` stands under `2¹²⁸`, so its square is taken
// limb by limb in the schoolbook way, and `k` is borrowed off the low word.
fn order_less(k: u64) -> [u64; 4] {
    let p = u128::from(crate::field::P);
    let square = p * p;
    let limbs = [square as u64, (square >> 64) as u64];
    let mut out = [0u64; 4];
    for (i, a) in limbs.iter().enumerate() {
        let mut carry = 0u128;
        for (j, b) in limbs.iter().enumerate() {
            let at = i + j;
            let wide = u128::from(*a) * u128::from(*b) + u128::from(out[at]) + carry;
            out[at] = wide as u64;
            carry = wide >> 64;
        }
        out[i + 2] = carry as u64;
    }
    let mut borrow = k;
    for word in out.iter_mut() {
        let (next, under) = word.overflowing_sub(borrow);
        *word = next;
        borrow = u64::from(under);
    }
    out
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

        fn element(&mut self) -> L {
            L(std::array::from_fn(|_| {
                F::from_u64_reduced(self.next() % crate::field::P)
            }))
        }
    }

    #[test]
    fn the_field_of_the_line_holds_its_own_laws() {
        let mut rng = Rng(0x4D54_5F4C_494E_0001);
        for _ in 0..2_000 {
            let (a, b, c) = (rng.element(), rng.element(), rng.element());
            assert_eq!(a.plus(b), b.plus(a));
            assert_eq!(a.times(b), b.times(a));
            assert_eq!(a.times(b).times(c), a.times(b.times(c)));
            assert_eq!(a.times(b.plus(c)), a.times(b).plus(a.times(c)));
            assert_eq!(a.minus(a), L::ZERO);
            assert_eq!(a.times(L::ONE), a);
        }
    }

    // `X` to the fourth is the residue, which is the polynomial the set names and nothing else.
    #[test]
    fn x_to_the_fourth_is_seven() {
        let x = L([F::ZERO, F::ONE, F::ZERO, F::ZERO]);
        let fourth = x.square().square();
        assert_eq!(
            fourth,
            L([F::from_u64_reduced(RESIDUE), F::ZERO, F::ZERO, F::ZERO])
        );
    }

    // The choice rests on two facts of the prime: it is one more than a multiple of four, and seven
    // is no square of it. A square seven would factor `X⁴ − 7` into two quadratics, and the line
    // would be taken over a ring whose zero divisors open no lock.
    #[test]
    fn x_to_the_fourth_less_seven_has_no_factor() {
        assert_eq!(crate::field::P % 4, 1);
        let residue = F::from_u64_reduced(RESIDUE);
        assert_eq!(
            residue.pow((crate::field::P - 1) / 2),
            F::ONE.negated(),
            "seven is a non-residue of the prime"
        );
    }

    #[test]
    fn every_element_but_zero_inverts() {
        let mut rng = Rng(0x4D54_5F4C_494E_0002);
        for _ in 0..200 {
            let a = rng.element();
            if a.is_zero() {
                continue;
            }
            assert_eq!(
                a.times(a.inverse().expect("a non-zero element inverts")),
                L::ONE
            );
        }
        assert_eq!(L::ZERO.inverse(), None);
    }

    // The order is checked as a number from the other side: `p⁴ − 1` is the order of the group of
    // units, so every element but zero raised to it is one.
    #[test]
    fn the_exponent_of_an_inverse_is_the_order_of_the_field_less_two() {
        let less_one = order_less(1);
        let less_two = order_less(2);
        assert_eq!(less_one[0].wrapping_sub(1), less_two[0]);
        let mut rng = Rng(0x4D54_5F4C_494E_0003);
        for _ in 0..50 {
            let a = rng.element();
            if !a.is_zero() {
                assert_eq!(a.pow(less_one), L::ONE);
            }
        }
        // The top word of `p⁴` is not zero, so a carry lost on the way up shows here.
        assert_ne!(less_one[3], 0);
    }

    #[test]
    fn two_points_of_one_line_give_its_opening_and_one_point_twice_gives_nothing() {
        let mut rng = Rng(0x4D54_5F4C_494E_0004);
        for _ in 0..500 {
            let (opening, slope) = (rng.element(), rng.element());
            let (x1, x2) = (rng.element(), rng.element());
            if x1 == x2 {
                continue;
            }
            let (y1, y2) = (line_at(opening, slope, x1), line_at(opening, slope, x2));
            assert_eq!(opening_of((x1, y1), (x2, y2)), Some(opening));
            assert_eq!(opening_of((x2, y2), (x1, y1)), Some(opening));
            assert_eq!(opening_of((x1, y1), (x1, y1)), None);
        }
    }

    // A point of a line on a slope nobody holds opens nothing: a point of another slot beside it
    // extracts a value that is not the opening.
    #[test]
    fn points_of_two_slots_give_no_opening() {
        let mut rng = Rng(0x4D54_5F4C_494E_0005);
        for _ in 0..200 {
            let opening = rng.element();
            let (slope_one, slope_two) = (rng.element(), rng.element());
            let (x1, x2) = (rng.element(), rng.element());
            if x1 == x2 || slope_one == slope_two {
                continue;
            }
            let first = (x1, line_at(opening, slope_one, x1));
            let second = (x2, line_at(opening, slope_two, x2));
            assert_ne!(opening_of(first, second), Some(opening));
        }
    }

    // The spending half of a secret, as the nullifier of a part takes it.
    fn spending_of(secret: &[u8; 32]) -> Digest {
        poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, secret).0
    }

    fn pledged(secret: &[u8; 32], window: u64, slot: u64, name: &[u8; 32]) -> (L, L) {
        let spending = spending_of(secret);
        let x = abscissa(name).expect("an abscissa of a name");
        let y = line_at(
            opening(&spending),
            slope(&spending, window, slot).expect("a slope of a slot"),
            x,
        );
        (x, y)
    }

    // The derivations end to end: two objects of one part in one slot on two names give the
    // lock-opening value of that machine, and the value is the machine's in every window.
    #[test]
    fn two_names_in_one_slot_give_the_opening_of_their_machine() {
        let secret = [0x5Au8; 32];
        let other = [0xA5u8; 32];
        let (first, second) = ([0x11u8; 32], [0x22u8; 32]);
        let mine = opening(&spending_of(&secret));
        assert_ne!(mine, opening(&spending_of(&other)));
        for (window, at) in [
            (0, slot(0, false)),
            (7, slot(3, true)),
            (1_000, slot(62, false)),
        ] {
            let one = pledged(&secret, window, at, &first);
            let two = pledged(&secret, window, at, &second);
            assert_eq!(opening_of(one, two), Some(mine));
            // A repetition on one name is one point twice and reveals nothing.
            assert_eq!(opening_of(one, one), None);
        }
    }

    // Two slots are two lines: the open and the closing pledge of one attempt, two attempts, or one
    // slot of two windows give a value that is not the opening.
    #[test]
    fn two_slots_of_one_machine_give_no_opening() {
        let secret = [0x5Au8; 32];
        let mine = opening(&spending_of(&secret));
        let (first, second) = ([0x11u8; 32], [0x22u8; 32]);
        for ((w1, s1), (w2, s2)) in [
            ((5, slot(1, false)), (5, slot(1, true))),
            ((5, slot(1, true)), (5, slot(2, true))),
            ((5, slot(0, false)), (6, slot(0, false))),
        ] {
            let one = pledged(&secret, w1, s1, &first);
            let two = pledged(&secret, w2, s2, &second);
            assert_ne!(opening_of(one, two), Some(mine));
        }
    }

    // The slot is the position of its pledge in the band plus one, the heavy attestation zero, and
    // no two objects of a window share one.
    #[test]
    fn every_slot_of_a_window_is_its_own_and_the_heavy_attestation_is_zero() {
        assert_eq!(slot(0, false), 0);
        assert_eq!(slot(0, true), 1);
        for attempt in [1u32, 2, 61, 62, 63, 0xFFFF_FFFE] {
            let a = u64::from(attempt);
            // Closing: position 2u, plus one. Open: position 2t - 1, plus one.
            assert_eq!(slot(attempt, true), 2 * a + 1);
            assert_eq!(slot(attempt, false), 2 * a);
        }
        assert!(slot(0xFFFF_FFFE, true) < crate::field::P);
        let spending = spending_of(&[0x5Au8; 32]);
        assert_ne!(
            slope(&spending, 5, slot(1, false)),
            slope(&spending, 5, slot(1, true))
        );
        assert_ne!(slope(&spending, 5, 1), slope(&spending, 6, 1));
        // A window or a slot that is no element draws no slope.
        assert_eq!(slope(&spending, crate::field::P, 0), None);
        assert_eq!(slope(&spending, 0, crate::field::P), None);
    }

    // Each derivation is its own domain: the same cells under the nullifier of a part, or under the
    // domain of the slope, are other values, and so is a name under the domain of the opening.
    #[test]
    fn the_three_derivations_stand_under_three_domains() {
        let spending = spending_of(&[0x5Au8; 32]);
        let name = spending.bytes();
        let under = |d| L::of_digest(&poseidon::hash_elements(d, spending.elements()));
        assert_eq!(opening(&spending), under(domain::MT_LINE_OPENING));
        assert_ne!(opening(&spending), under(domain::MT_PART_NF));
        assert_ne!(opening(&spending), under(domain::MT_LINE_SLOPE));
        let named = poseidon::hash_bytes(domain::MT_LINE_OPENING, &name);
        assert_ne!(abscissa(&name), Some(L::of_digest(&named)));
        assert!(abscissa(&name).is_some());
    }

    #[test]
    fn the_bytes_of_an_element_round_trip_and_a_word_past_the_modulus_is_refused() {
        let mut rng = Rng(0x4D54_5F4C_494E_0006);
        for _ in 0..1_000 {
            let a = rng.element();
            assert_eq!(L::from_bytes(&a.to_bytes()), Some(a));
        }
        for word in 0..4 {
            for bad in [crate::field::P, u64::MAX] {
                let mut bytes = L::ONE.to_bytes();
                bytes[word * 8..word * 8 + 8].copy_from_slice(&bad.to_le_bytes());
                assert_eq!(L::from_bytes(&bytes), None, "word {word} at {bad:#x}");
            }
        }
        // A digest reads as the element its bytes are.
        let digest = crate::poseidon::hash_bytes(mt_codec::domain::MT_KEY_HALVES, &[7u8; 32]);
        assert_eq!(L::from_bytes(&digest.bytes()), Some(L::of_digest(&digest)));
    }
}
