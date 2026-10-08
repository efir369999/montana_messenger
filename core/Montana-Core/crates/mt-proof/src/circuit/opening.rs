// The circuit of an opening: a claimant proves that the record it brings into being is the one its
// commitment stands for, and that the one-time right to open a record is spent — disclosing neither
// the record nor the branch of the seed the right comes of.
//
// **Why this circuit exists at all.** Two bounds hold the opening of a record and both are of the
// identity plane: a one-time right, extinguished by a nullifier that names nobody, and a ceiling of
// openings per window. Neither binds anything unless the nullifier is tied to the seed it came of:
// a claimant free to publish a fresh value each time spends a right it never held, and a ceiling
// counted over such values counts nobody. Lived time is not among the bounds and could not be — the
// segments of a record are earned by its own actions, and a claimant has no record to act with.
//
// **What it asserts about the record itself.** A record opened with a height or a lived segment
// already in it would buy standing it never lived, so the four fields that could carry such a claim
// are bound: the bitmap of lived segments and the height stand at zero, the segment the bitmap is
// written against is the segment of the window being applied, and the window the record was opened
// in is that window. They are the first six limbs of the serialization, which is why one block of
// the absorption carries all four.
//
// **The shape.** Two chains laid one after another, rows and not columns, each opening under its own
// domain through the capacity wiring: the absorption of the branch that holds the right, whose
// squeeze is the nullifier; and the absorption of the serialized record, whose squeeze is the leaf
// of the tree of records — which is the commitment the opening publishes and the key that leaf
// stands at.

use super::permutation::ring_column;
use super::{capacity, permutation, sponge};
use crate::air::{Boundary, BoundaryValue, Description};
use crate::poseidon::CAPACITY;
use mt_codec::domain;

mt_codec::constants! {
    OPENING:
    /// What the two chains of this circuit fill, one power of two. The height it is **built** at is
    /// the one every description stands at, since a proof is bytes of one length whatever is
    /// proven; this number is what says the blocks fit under it.
    pub const ROWS_FILLED_LOG2: usize = 14, code "the rows the two chains of an opening fill, one power of two: what the height every description stands at must hold";
    /// Which limb of a serialized record carries which of the four fields an opening binds. They
    /// follow from the order the layout of a record fixes and from nothing else.
    pub const LIMB_BITMAP_LOW: usize = 0, code "the limb of a serialized record carrying the low half of the bitmap of lived segments";
    pub const LIMB_BITMAP_HIGH: usize = 1, code "the limb carrying the high half of that bitmap";
    pub const LIMB_LAST_SEGMENT: usize = 2, code "the limb carrying the segment the bitmap is written against";
    pub const LIMB_WINDOW_LOW: usize = 3, code "the limb carrying the low half of the window the record was opened in";
    pub const LIMB_WINDOW_HIGH: usize = 4, code "the limb carrying the high half of that window";
    pub const LIMB_HEIGHT: usize = 5, code "the limb carrying the number of the holder's own actions";
}

// How the blocks of an opening stand. Block zero is idle so every chain has a seam before it.
#[derive(Clone, Copy, Debug)]
pub struct Places;

impl Places {
    pub fn right(&self) -> usize {
        1
    }

    pub fn right_blocks(&self) -> usize {
        sponge::blocks_of(crate::poseidon::limbs_of(&[0u8; 32]).len())
    }

    pub fn record(&self) -> usize {
        self.right() + self.right_blocks()
    }

    pub fn record_blocks(&self) -> usize {
        sponge::blocks_of(super::admission::RECORD_LIMBS)
    }

    pub fn blocks(&self) -> usize {
        self.record() + self.record_blocks()
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    pub fn carry_rows(&self) -> Vec<usize> {
        let mut out = sponge::carry_rows(self.right(), self.right_blocks());
        out.extend(sponge::carry_rows(self.record(), self.record_blocks()));
        out
    }

    // The two digests the public input carries: the nullifier of the right at its chain's end, and
    // the commitment of the record at its own.
    pub fn boundaries(&self) -> Vec<Boundary> {
        let ends = [
            self.seam_before(self.record()),
            self.blocks() * permutation::period() - 1,
        ];
        let mut out = Vec::with_capacity(ends.len() * CAPACITY + 6);
        for (which, row) in ends.iter().enumerate() {
            for cell in 0..CAPACITY {
                out.push(Boundary {
                    column: ring_column(cell) as u16,
                    row: *row as u64,
                    // A word is a pair of adjacent limbs, so a cell's index steps by two limbs.
                    value: BoundaryValue::Word((2 * (which * CAPACITY + cell)) as u16),
                });
            }
        }
        // The four fields of the record this opening binds. They stand in the first block of the
        // absorption, where the limbs enter before the permutation reads them, so a boundary
        // reaches them where nothing has yet moved.
        let first = self.record() * permutation::period();
        let public_of_a_limb = 2 * ends.len() * CAPACITY;
        for (limb, value) in [
            (LIMB_BITMAP_LOW, BoundaryValue::Literal(0)),
            (LIMB_BITMAP_HIGH, BoundaryValue::Literal(0)),
            (
                LIMB_LAST_SEGMENT,
                BoundaryValue::Public(public_of_a_limb as u16),
            ),
            (
                LIMB_WINDOW_LOW,
                BoundaryValue::Public((public_of_a_limb + 1) as u16),
            ),
            (
                LIMB_WINDOW_HIGH,
                BoundaryValue::Public((public_of_a_limb + 2) as u16),
            ),
            (LIMB_HEIGHT, BoundaryValue::Literal(0)),
        ] {
            out.push(Boundary {
                column: ring_column(limb) as u16,
                row: first as u64,
                value,
            });
        }
        out
    }

    pub fn opens(&self) -> Vec<(usize, mt_codec::Domain)> {
        vec![
            (self.seam_before(self.right()), domain::MT_OPEN_NF),
            (self.seam_before(self.record()), domain::MT_RECORD_LEAF),
        ]
    }
}

// The assembled shape: the permutation base at the height every description stands at, the carries
// of a sponge and the capacity wiring — the machinery the other circuits assemble from, at the two
// chains this statement needs.
pub fn description() -> Option<Description> {
    let places = Places;
    let rows_log2 = crate::params::ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let width = permutation::TRACE_WIDTH;
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let opens_at = carry + 1;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic
        .extend(capacity::periodic_columns(rows_log2, &places.opens()));

    held.constraints.extend(sponge::capacity_carries(carry));
    held.constraints.extend(capacity::constraints(opens_at));
    held.boundaries.extend(places.boundaries());
    Some(held)
}

// The trace of an opening: the absorption of the branch that holds the right, and the absorption of
// the serialized record.
pub fn trace_of(
    open_secret: &[u8; 32],
    record: &[u8],
) -> Option<(Vec<Vec<crate::field::F>>, [crate::poseidon::Digest; 2])> {
    use crate::field::F;
    use crate::poseidon::{self, WIDTH};
    let places = Places;
    let rows = 1usize << crate::params::ROWS_LOG2;
    let width = permutation::TRACE_WIDTH;
    let mut columns = vec![vec![F::ZERO; rows]; width];

    let right_limbs = poseidon::limbs_of(open_secret);
    for (at, state) in sponge::chain(domain::MT_OPEN_NF, &right_limbs)
        .iter()
        .enumerate()
    {
        permutation::write_block(&mut columns, places.right() + at, state)?;
    }
    let nullifier = poseidon::hash_elements(domain::MT_OPEN_NF, &right_limbs);

    let record_limbs = poseidon::limbs_of(record);
    if record_limbs.len() != super::admission::RECORD_LIMBS {
        return None;
    }
    for (at, state) in sponge::chain(domain::MT_RECORD_LEAF, &record_limbs)
        .iter()
        .enumerate()
    {
        permutation::write_block(&mut columns, places.record() + at, state)?;
    }
    let commitment = poseidon::hash_elements(domain::MT_RECORD_LEAF, &record_limbs);

    // An idle block is not a row of zeros: the permutation's own rules speak at every block, and the
    // trace of nothing is the permutation of the zero state, written through the same door.
    let all_blocks = rows / permutation::period();
    for block in 0..all_blocks {
        if !(places.right()..places.blocks()).contains(&block) {
            permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])?;
        }
    }
    Some((columns, [nullifier, commitment]))
}

// The public input of an opening: the nullifier of the right, the commitment of the record, and the
// three limbs the record's own fields are bound to — the segment the bitmap is written against and
// the two halves of the window it was opened in. A verifier holds both of those from the window it
// is applying, so nothing about them is taken from the object.
pub fn public_of(digests: &[crate::poseidon::Digest; 2], window: u64, segment: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity(2 * 32 + 12);
    for digest in digests {
        out.extend_from_slice(&digest.bytes());
    }
    out.extend_from_slice(&segment.to_le_bytes());
    out.extend_from_slice(&window.to_le_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    // A record as a claimant brings it into being: nothing lived, nothing done, opened in the
    // window being applied. The bytes are the serialization the set fixes, laid here by hand
    // because this crate stands below the one that owns that layout.
    fn a_new_record(window: u64, segment: u32) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&0u64.to_le_bytes()); // segment_bitmap
        out.extend_from_slice(&segment.to_le_bytes()); // last_active_segment
        out.extend_from_slice(&window.to_le_bytes()); // opened_window
        out.extend_from_slice(&0u32.to_le_bytes()); // own_height
        out.extend_from_slice(&[0x11u8; 32]); // fabric_root
        out.extend_from_slice(&1u16.to_le_bytes()); // suite_id
        out.extend_from_slice(&[0x22u8; mt_codec::size::SIGNING_PUBLIC_KEY]);
        out.extend_from_slice(&[0x33u8; 32]); // blind
        out
    }

    #[test]
    fn the_blocks_of_an_opening_fit_its_height() {
        let places = Places;
        let rows = 1usize << ROWS_FILLED_LOG2;
        assert!(
            places.blocks() * permutation::period() <= rows,
            "the two chains do not fit the rows they name"
        );
        assert!(
            places.blocks() * permutation::period() <= 1usize << crate::params::ROWS_LOG2,
            "the two chains do not fit the height every description stands at"
        );
    }

    #[test]
    fn an_opening_is_proven_and_verified_end_to_end() {
        let window = 1_000u64;
        let segment = 7u32;
        let record = a_new_record(window, segment);
        let held = description().expect("the description of an opening stands");
        let (trace, digests) =
            trace_of(&[0x44u8; 32], &record).expect("a claimant writes an opening");
        let public = public_of(&digests, window, segment);
        assert!(
            held.satisfied_by(&trace, &crate::poseidon::limbs_of(&public)),
            "an honest opening does not satisfy its own description"
        );
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true opening proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));
        // The nullifier it publishes is the one the set derives from that branch, and nothing else.
        assert_eq!(
            digests[0].bytes(),
            mt_derive_open(&[0x44u8; 32]),
            "the opening publishes a nullifier of another derivation"
        );
    }

    // The set's own derivation of the right, restated here only because this crate stands below the
    // one that owns it; the gate holds the two against each other.
    fn mt_derive_open(secret: &[u8; 32]) -> [u8; 32] {
        crate::poseidon::hash_bytes(domain::MT_OPEN_NF, secret).bytes()
    }

    // The named wrong implementations these refuse: a claimant opening a record that already
    // carries lived time, or one claiming a window it was not opened in. Both would buy standing
    // the claimant never lived, and both fail at the boundary that binds the field.
    #[test]
    fn a_record_carrying_lived_time_or_another_window_does_not_prove() {
        let window = 1_000u64;
        let segment = 7u32;
        let held = description().expect("stands");
        let public_of_the_honest =
            |digests: &[crate::poseidon::Digest; 2]| public_of(digests, window, segment);

        // A bitmap with a segment already lived in it.
        let mut record = a_new_record(window, segment);
        record[0] = 1;
        let (trace, digests) = trace_of(&[0x44u8; 32], &record).expect("it writes");
        assert!(
            !held.satisfied_by(
                &trace,
                &crate::poseidon::limbs_of(&public_of_the_honest(&digests))
            ),
            "a record opened with a lived segment satisfied the description"
        );

        // A height above zero.
        let mut record = a_new_record(window, segment);
        record[20] = 1;
        let (trace, digests) = trace_of(&[0x44u8; 32], &record).expect("it writes");
        assert!(
            !held.satisfied_by(
                &trace,
                &crate::poseidon::limbs_of(&public_of_the_honest(&digests))
            ),
            "a record opened with a height satisfied the description"
        );

        // A window other than the one being applied.
        let record = a_new_record(window + 1, segment);
        let (trace, digests) = trace_of(&[0x44u8; 32], &record).expect("it writes");
        assert!(
            !held.satisfied_by(
                &trace,
                &crate::poseidon::limbs_of(&public_of_the_honest(&digests))
            ),
            "a record claiming another window satisfied the description"
        );
    }
}
