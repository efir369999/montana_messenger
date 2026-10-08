// The commitment that carries standing. Parameters, the lift, the expansion, the commitment and
// its serialization, exactly as the set states them; nothing here chooses a number.
//
// The lift is the whole of what makes this a commitment rather than the shape of one. A value added
// at the size of the randomness is a value the randomness can move: lower one coefficient of `r2`
// by one and the same bytes open to a value one greater. Multiplying every digit by `4 eta + 1`
// puts a difference of values out of the range a difference of randomness can reach, which is what
// closes the case where the matrix does not enter the difference at all.

use mt_codec::{domain, hash, Part};
use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::Shake128;
use std::sync::OnceLock;
use zeroize::Zeroizing;

// The parameter set of ML-DSA-65 (FIPS 204), taken whole: the lattice and its dimensions are the
// ones the whole set already stands on.
mt_codec::constants! {
    LATTICE:
    /// The parameter set of ML-DSA-65, taken whole: the ring, the modulus, and the two dimensions.
    pub const D: usize = 256, writes "d = 256";
    pub const Q: u32 = 8_380_417, writes "q = 8 380 417";
    pub const N: usize = 6, writes "n = 6,";
    pub const K: usize = 5, writes "k = 5,";
    pub const ETA: i8 = 4, writes "eta = 4";
    /// The shape of what a commitment carries: three values of eight digits each, base 256.
    pub const VALUE_DIGITS: usize = 8, writes "value_digits = 8";
    pub const VALUES: usize = 3, writes "value_digits = 8, values = 3";
    /// The scale a value enters at, which the set derives beside the parameters it stands on.
    pub const LIFT: u32 = 4 * (ETA as u32) + 1, writes "lift = 4 eta + 1 = 17";
}

pub const SERIALIZED_LEN: usize = N * D * 4;

// The scale that puts a value out of reach of the randomness. A difference of two openings carries
// randomness coefficients in [-2 eta, 2 eta]; a difference of values enters as a non-zero multiple
// of this, and 4 eta + 1 is the least scale that cannot be reached from either end.

// The eight base-256 digits of a value, and the three values one commitment carries.

// The count of commitments whose sum still opens to the sum of their values. A digit is at most
// 255 and enters at the lift, so a coefficient holds this many of them before it wraps. Past it a
// sum is an indicator of reach and never a quantity, which is exactly the role the set gives it.
pub const MAX_OPENABLE_SUMMANDS: u64 = ((Q as u64) - 1) / (LIFT as u64 * 255);

#[derive(Debug, PartialEq, Eq)]
pub enum CommitError {
    RandomnessOutOfBound { value: i8 },
}

type Poly = [u32; D];

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Commitment([Poly; N]);

pub fn matrix_seed() -> [u8; 32] {
    hash(
        domain::MT_STANDING_MATRIX,
        &[
            Part::of(&u64::from(Q).to_le_bytes()),
            Part::of(&(D as u16).to_le_bytes()),
            Part::of(&[N as u8]),
            Part::of(&[K as u8]),
        ],
    )
}

// One polynomial of the public matrix: coefficients from SHAKE-128 over the seed, the column
// and the row, three bytes at a time masked to twenty-three bits, values of q and above
// rejected.
fn sample_poly(seed: &[u8; 32], column: u8, row: u8) -> Poly {
    let mut xof = Shake128::default();
    xof.update(seed);
    xof.update(&[column, row]);
    let mut reader = xof.finalize_xof();
    let mut out = [0u32; D];
    let mut filled = 0;
    let mut chunk = [0u8; 3];
    while filled < D {
        reader.read(&mut chunk);
        let z =
            u32::from(chunk[0]) | (u32::from(chunk[1]) << 8) | (u32::from(chunk[2] & 0x7F) << 16);
        if z < Q {
            out[filled] = z;
            filled += 1;
        }
    }
    out
}

// The matrix is a public value drawn once from its seed and read for every commitment.
fn matrix() -> &'static [[Poly; K]; N] {
    static MATRIX: OnceLock<[[Poly; K]; N]> = OnceLock::new();
    MATRIX.get_or_init(|| {
        let seed = matrix_seed();
        core::array::from_fn(|i| core::array::from_fn(|j| sample_poly(&seed, j as u8, i as u8)))
    })
}

pub fn matrix_coefficients(row: usize, column: usize) -> &'static Poly {
    &matrix()[row][column]
}

// The randomness of one commitment, expanded from the blinding factor a machine draws: the
// coefficients of r1 and then those of r2, four bits at a time, the low nibble of a byte first, a
// nibble of nine or above rejected. It is the rule FIPS 204 applies to its own eta of four, and it
// is why a blinding factor of thirty-two bytes is the whole of what a machine holds beside its
// quantities.
pub fn expand(blind: &[u8; 32]) -> ([[i8; D]; K], [[i8; D]; N]) {
    let mut xof = Shake128::default();
    xof.update(domain::MT_WEIGHT.as_str().as_bytes());
    xof.update(&[0u8]);
    xof.update(blind);
    let mut reader = xof.finalize_xof();
    let mut byte = [0u8; 1];
    let mut half: Option<u8> = None;
    let mut next = || -> i8 {
        loop {
            let nibble = match half.take() {
                Some(high) => high,
                None => {
                    reader.read(&mut byte);
                    half = Some(byte[0] >> 4);
                    byte[0] & 0x0F
                }
            };
            if nibble < 9 {
                return ETA - nibble as i8;
            }
        }
    };
    let mut r1 = [[0i8; D]; K];
    for poly in r1.iter_mut() {
        for slot in poly.iter_mut() {
            *slot = next();
        }
    }
    let mut r2 = [[0i8; D]; N];
    for poly in r2.iter_mut() {
        for slot in poly.iter_mut() {
            *slot = next();
        }
    }
    (r1, r2)
}

// Multiplication in R_q = Z_q[X] / (X^256 + 1): the wrapped half is subtracted, because
// X^256 = -1. Every product is below q squared, and a row of 256 of them stays within a u64.
fn mul_into(acc: &mut [u64; 2 * D], a: &Poly, b: &[u32; D]) {
    for (x, av) in a.iter().enumerate() {
        if *av == 0 {
            continue;
        }
        let av = u64::from(*av);
        for (y, bv) in b.iter().enumerate() {
            let cell = &mut acc[x + y];
            *cell = (*cell + av * u64::from(*bv)) % u64::from(Q);
        }
    }
}

fn centered(value: i8) -> Result<u32, CommitError> {
    if !(-ETA..=ETA).contains(&value) {
        return Err(CommitError::RandomnessOutOfBound { value });
    }
    Ok(if value < 0 {
        Q - value.unsigned_abs() as u32
    } else {
        value as u32
    })
}

// The commitment: A x r1 + r2 + encode(values), n polynomials of the ring. The randomness is
// bounded by eta, and a draw outside the bound is refused rather than reduced — a reduced
// coefficient is a different randomness, and the binding argument counts only bounded ones.
pub fn commit(
    values: [u64; VALUES],
    r1: &[[i8; D]; K],
    r2: &[[i8; D]; N],
) -> Result<Commitment, CommitError> {
    let mut r1_q = [[0u32; D]; K];
    for (row, source) in r1_q.iter_mut().zip(r1.iter()) {
        for (slot, v) in row.iter_mut().zip(source.iter()) {
            *slot = centered(*v)?;
        }
    }
    let a = matrix();
    let mut out = [[0u32; D]; N];
    for i in 0..N {
        let mut acc = [0u64; 2 * D];
        for j in 0..K {
            mul_into(&mut acc, &a[i][j], &r1_q[j]);
        }
        for t in 0..D {
            let folded = (acc[t] + u64::from(Q) - acc[t + D] % u64::from(Q)) % u64::from(Q);
            let with_r2 = (folded + u64::from(centered(r2[i][t])?)) % u64::from(Q);
            out[i][t] = with_r2 as u32;
        }
    }
    // The values, each as its eight base-256 digits at the lift, laid in the first polynomial in
    // the order the values are given.
    for (which, value) in values.iter().enumerate() {
        for t in 0..VALUE_DIGITS {
            let digit = u64::from((value >> (8 * t)) as u8) * u64::from(LIFT);
            let slot = &mut out[0][which * VALUE_DIGITS + t];
            *slot = ((u64::from(*slot) + digit) % u64::from(Q)) as u32;
        }
    }
    Ok(Commitment(out))
}

// The blinding factor of one commitment. It carries the window it was drawn for and the door takes
// it by value, so it cannot stand behind two commitments: two commitments under one factor differ
// only in the coefficients that carry the values, and their difference would disclose the standing,
// the grant and the window in the clear without touching the lattice at all. What the type holds is
// what a rule would otherwise ask a caller to remember.
pub struct Blind {
    bytes: Zeroizing<[u8; 32]>,
    window: u64,
}

impl Blind {
    pub fn of(bytes: [u8; 32], window: u64) -> Self {
        Self {
            bytes: Zeroizing::new(bytes),
            window,
        }
    }

    pub fn window(&self) -> u64 {
        self.window
    }
}

// A factor is a secret of one machine: it shows nothing and carries no comparison, since two
// factors are equal only by accident and comparing them would run in a time that depends on where
// they part.
impl core::fmt::Debug for Blind {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("Blind(<wiped on drop, never shown>)")
    }
}

// The commitment a machine keeps about itself: its accumulated presence and the two windows that
// tell a term from its lapse, under one commitment and one blinding factor, which this door
// consumes.
pub fn weight_commit(
    standing: u64,
    granted: u64,
    last: u64,
    blind: Blind,
) -> Result<Commitment, CommitError> {
    let (r1, r2) = expand(&blind.bytes);
    commit([standing, granted, last], &r1, &r2)
}

impl Commitment {
    // Every coefficient as an unsigned four-byte little-endian integer, polynomial by
    // polynomial.
    pub fn serialize(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(SERIALIZED_LEN);
        for poly in &self.0 {
            for coefficient in poly {
                out.extend_from_slice(&coefficient.to_le_bytes());
            }
        }
        out
    }

    // What a commitment read off the wire is. Every coefficient stands below the modulus, and a
    // value at or above it is refused rather than reduced: a reduced coefficient is a different
    // commitment, and the binding argument counts only the ones the ring holds.
    pub fn deserialize(bytes: &[u8]) -> Option<Commitment> {
        if bytes.len() != SERIALIZED_LEN {
            return None;
        }
        let mut out = [[0u32; D]; N];
        for (i, poly) in out.iter_mut().enumerate() {
            for (t, slot) in poly.iter_mut().enumerate() {
                let at = (i * D + t) * 4;
                let value =
                    u32::from_le_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]);
                if value >= Q {
                    return None;
                }
                *slot = value;
            }
        }
        Some(Commitment(out))
    }

    // The addition of the ring: the commitment of a sum is the sum of the commitments, and the
    // randomness of a sum is the sum of the randomnesses. What the fold carries instead is a
    // fresh commitment, precisely so this sum never travels.
    pub fn add(&self, other: &Commitment) -> Commitment {
        let mut out = [[0u32; D]; N];
        for (row, (a, b)) in out.iter_mut().zip(self.0.iter().zip(other.0.iter())) {
            for (slot, (x, y)) in row.iter_mut().zip(a.iter().zip(b.iter())) {
                *slot = ((u64::from(*x) + u64::from(*y)) % u64::from(Q)) as u32;
            }
        }
        Commitment(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn r1_of(a: i64, b: i64) -> [[i8; D]; K] {
        core::array::from_fn(|j| {
            core::array::from_fn(|t| (((a * t as i64 + j as i64 + b) % 9) - 4) as i8)
        })
    }

    fn r2_of(a: i64, b: i64) -> [[i8; D]; N] {
        core::array::from_fn(|i| {
            core::array::from_fn(|t| (((a * t as i64 + i as i64 + b) % 9) - 4) as i8)
        })
    }

    #[test]
    fn the_seed_and_the_first_coefficients_of_the_matrix_are_the_frozen_values() {
        // Canon, "The vectors of the commitment".
        assert_eq!(
            hex(&matrix_seed()),
            "df12a35944b076cefda23c9a13ede48bf5b528642328b515d72308a719d4befb"
        );
        assert_eq!(
            &matrix_coefficients(0, 0)[..4],
            &[4_174_348, 7_389_464, 1_488_444, 1_764_261]
        );
    }

    #[test]
    fn the_frozen_commitments_reproduce() {
        // Canon, "The vectors of the commitment": two children, the node that folds them, and the
        // commitment a machine keeps about itself.
        let first = commit([1_000_000, 3_000, 7], &r1_of(1, 0), &r2_of(1, 3)).expect("bounded");
        assert_eq!(
            hex(&Sha256::digest(first.serialize())),
            "a8e766bd9b03e3d192bc82f511046c6e46644141368e115c60389eae84f04c5d"
        );
        let second = commit([2_500_000, 4_000, 9], &r1_of(3, 1), &r2_of(5, 2)).expect("bounded");
        assert_eq!(
            hex(&Sha256::digest(second.serialize())),
            "0f26269904ebb1c4709b3da76e14c2e0927d3ab62265e319458396476fed0a64"
        );
        let node = commit([3_500_000, 0, 0], &r1_of(7, 5), &r2_of(11, 6)).expect("bounded");
        assert_eq!(
            hex(&Sha256::digest(node.serialize())),
            "635addc6d980ffc7e666cc57c05fe8f182a52e37535f9e0a4da6d0494bccbff3"
        );
        let kept = weight_commit(1_000_000, 3_000, 7, Blind::of([0xC7u8; 32], 7)).expect("bounded");
        assert_eq!(
            hex(&Sha256::digest(kept.serialize())),
            "c5a74307a0394f893dd0bbaec4bd1c81635d5311a9dbc85fa97d25587900a35b"
        );
        // The named wrong implementation: a fold that adds its children's commitments. It
        // accumulates randomness, and it produces a different value from the frozen node.
        let added = first.add(&second);
        assert_ne!(
            hex(&Sha256::digest(added.serialize())),
            hex(&Sha256::digest(node.serialize()))
        );
    }

    #[test]
    fn a_second_opening_of_one_commitment_does_not_exist() {
        // The named wrong implementation, and the reason the lift stands: an implementation that
        // adds a digit at the size of the randomness answers the same bytes for two values one
        // apart, because one coefficient of `r2` absorbs the difference. Under the lift the two
        // stand apart, and this vector is what tells the two implementations apart.
        let mut r2_held = r2_of(1, 3);
        r2_held[0][0] = 0;
        let mut r2_lowered = r2_of(1, 3);
        r2_lowered[0][0] = -1;
        let held = commit([1_000_000, 0, 0], &r1_of(1, 0), &r2_held).expect("bounded");
        let moved = commit([1_000_001, 0, 0], &r1_of(1, 0), &r2_lowered).expect("bounded");
        assert_ne!(held.serialize(), moved.serialize());
        // Without the lift the two are one value: the difference of the digits is one, the
        // difference of the randomness is one, and they cancel.
        let base = commit([0, 0, 0], &r1_of(1, 0), &r2_held)
            .expect("bounded")
            .0[0][0];
        let lowered = commit([0, 0, 0], &r1_of(1, 0), &r2_lowered)
            .expect("bounded")
            .0[0][0];
        let unlifted = |first_digit: u64, cell: u32| -> u32 {
            ((u64::from(cell) + first_digit) % u64::from(Q)) as u32
        };
        assert_eq!(unlifted(64, base), unlifted(65, lowered));
        // Every difference the randomness can reach is smaller than the lift, which is the whole
        // of the argument for the case where the matrix does not enter.
        assert!(u32::from((2 * ETA) as u8) < LIFT);
    }

    #[test]
    fn the_three_values_stand_in_three_places_and_the_order_is_the_only_one() {
        let straight = commit([7, 11, 13], &r1_of(1, 0), &r2_of(1, 3)).expect("bounded");
        let swapped = commit([11, 7, 13], &r1_of(1, 0), &r2_of(1, 3)).expect("bounded");
        assert_ne!(straight, swapped);
        // Each value moves its own eight coefficients and no others.
        let empty = commit([0, 0, 0], &r1_of(1, 0), &r2_of(1, 3)).expect("bounded");
        for (which, values) in [[1u64, 0, 0], [0, 1, 0], [0, 0, 1]].into_iter().enumerate() {
            let one = commit(values, &r1_of(1, 0), &r2_of(1, 3)).expect("bounded");
            let moved: Vec<usize> = (0..D).filter(|t| one.0[0][*t] != empty.0[0][*t]).collect();
            assert_eq!(moved, vec![which * VALUE_DIGITS]);
        }
    }

    #[test]
    fn the_commitment_of_a_sum_is_the_sum_of_the_commitments() {
        // The homomorphism the quorum sums by: randomness drawn small enough that its sum stays
        // within the bound, so both sides of the identity pass the same door. The values are
        // chosen so no digit of the sum carries, which is the range the identity holds in.
        let half_r1 = |b0: i64| -> [[i8; D]; K] {
            core::array::from_fn(|j| {
                core::array::from_fn(|t| (((t as i64 + j as i64 + b0) % 5) - 2) as i8)
            })
        };
        let half_r2 = |b0: i64| -> [[i8; D]; N] {
            core::array::from_fn(|i| {
                core::array::from_fn(|t| (((2 * t as i64 + i as i64 + b0) % 5) - 2) as i8)
            })
        };
        let a = commit([7, 1, 2], &half_r1(0), &half_r2(1)).expect("bounded");
        let b = commit([11, 3, 4], &half_r1(2), &half_r2(3)).expect("bounded");
        let summed_r1: [[i8; D]; K] =
            core::array::from_fn(|j| core::array::from_fn(|t| half_r1(0)[j][t] + half_r1(2)[j][t]));
        let summed_r2: [[i8; D]; N] =
            core::array::from_fn(|i| core::array::from_fn(|t| half_r2(1)[i][t] + half_r2(3)[i][t]));
        let of_sum =
            commit([18, 4, 6], &summed_r1, &summed_r2).expect("the sums stay within the bound");
        assert_eq!(a.add(&b), of_sum);
    }

    #[test]
    fn the_count_of_summands_a_sum_still_opens_for_is_the_one_the_set_derives() {
        assert_eq!(LIFT, 17);
        assert_eq!(MAX_OPENABLE_SUMMANDS, 1_933);
        // One digit at the lift, taken that many times, still stands below the modulus; one more
        // wraps, and a wrapped sum is an indicator rather than a quantity.
        assert!(u64::from(LIFT) * 255 * MAX_OPENABLE_SUMMANDS < u64::from(Q));
        assert!(u64::from(LIFT) * 255 * (MAX_OPENABLE_SUMMANDS + 1) >= u64::from(Q));
    }

    #[test]
    fn a_randomness_outside_the_bound_is_refused_rather_than_reduced() {
        let mut r1 = r1_of(1, 0);
        r1[0][0] = 5;
        assert_eq!(
            commit([1, 0, 0], &r1, &r2_of(1, 3)),
            Err(CommitError::RandomnessOutOfBound { value: 5 })
        );
        let mut r2 = r2_of(1, 3);
        r2[0][0] = -5;
        assert_eq!(
            commit([1, 0, 0], &r1_of(1, 0), &r2),
            Err(CommitError::RandomnessOutOfBound { value: -5 })
        );
    }

    #[test]
    fn the_serialization_is_the_width_the_set_states() {
        let c = commit([1, 0, 0], &r1_of(1, 0), &r2_of(1, 3)).expect("bounded");
        assert_eq!(c.serialize().len(), SERIALIZED_LEN);
        assert_eq!(SERIALIZED_LEN, mt_state::WEIGHT_COMMIT_BYTES);
    }

    #[test]
    fn the_randomness_a_blind_expands_to_is_bounded_and_is_its_own() {
        let (r1, r2) = expand(&[0xC7u8; 32]);
        assert!(r1
            .iter()
            .all(|p| p.iter().all(|v| (-ETA..=ETA).contains(v))));
        assert!(r2
            .iter()
            .all(|p| p.iter().all(|v| (-ETA..=ETA).contains(v))));
        // One blinding factor expands to itself and two expand apart.
        let (again, _) = expand(&[0xC7u8; 32]);
        assert_eq!(r1[0][..8], again[0][..8]);
        let (other, _) = expand(&[0xC8u8; 32]);
        assert_ne!(r1[0][..8], other[0][..8]);
        // The commitment a machine keeps about itself stands on that expansion and on nothing a
        // caller may choose.
        let held = weight_commit(1_000_000, 3_000, 7, Blind::of([0xC7u8; 32], 7)).expect("bounded");
        assert_eq!(
            held,
            commit([1_000_000, 3_000, 7], &r1, &r2).expect("bounded")
        );
    }

    #[test]
    fn a_commitment_reads_back_and_one_outside_the_ring_does_not() {
        let held = commit([7, 11, 13], &r1_of(1, 0), &r2_of(1, 3)).expect("bounded");
        let bytes = held.serialize();
        assert_eq!(Commitment::deserialize(&bytes), Some(held));
        // The named wrong implementation: one reducing a coefficient at or above the modulus
        // instead of refusing it. A reduced coefficient is a different commitment, and the binding
        // argument counts only the ones the ring holds.
        let mut past = bytes.clone();
        past[..4].copy_from_slice(&Q.to_le_bytes());
        assert_eq!(Commitment::deserialize(&past), None);
        assert_eq!(Commitment::deserialize(&bytes[..bytes.len() - 1]), None);
    }

    #[test]
    fn two_machines_of_equal_quantities_present_two_commitments() {
        let a = weight_commit(500, 10, 20, Blind::of([0x01u8; 32], 20)).expect("bounded");
        let b = weight_commit(500, 10, 20, Blind::of([0x02u8; 32], 20)).expect("bounded");
        assert_ne!(a, b);
    }
}
