// The circuit of an admission: a candidacy proves its continuity out of the record that holds it,
// and its right out of the tree of admitted machines, disclosing neither.
//
// **The shape.** One trace of chained permutation blocks, rows and not columns: the record chain —
// the serialized record absorbed limb by limb, whose squeeze is the leaf of the tree of records —
// then a walk of two hundred and fifty-six node blocks under the record domains, keyed by the bits
// of the key; then the admitted branch, one leaf block and forty node blocks under the admitted
// domains; then the chain of the redemption\'s nullifier, whose squeeze a boundary publishes. Every
// chain opens under its own domain through the capacity wiring, and a chain wired to the wrong
// domain computes a value of the wrong family byte for byte.
//
// **What is assembled and what remains.** The layers assembled here are the ones already proven by
// the frame\'s own use: the permutation base, the carries of a sponge, the walk of a path, and the
// capacity wiring — and the loads between adjacent chains are the walk\'s own level rules, which
// take each block\'s squeeze out of the state\'s cells and order it against the sibling by the bit.
// The roots the two walks answer and the nullifier the chain yields are bound to the public input
// as words of the hash state. The bits of the record walk are witness by design, as a
// note's position is: the statement is membership under a public root, not the key. The
// nullifier's absorption takes the very commitment the record walk proved, through a lane of one
// digest loaded at the record chain's last seam and wired at the nullifier's first. **The proving
// run stands**: the witness-side filling is written and one admission is proven and verified end to
// end below, which is what let this identifier be offered at all — an identifier frozen before the
// thing it names has run is a number that measures nothing, and this one is not that.

use super::permutation::ring_column;
use super::{capacity, lane, path, permutation, sponge};
use crate::air::{Boundary, BoundaryValue, Description};
use crate::poseidon::CAPACITY;
use mt_codec::domain;

mt_codec::constants! {
    ADMISSION:
    /// The limbs of a serialized record: its bytes in words of four.
    pub const RECORD_LIMBS: usize = 511, code "the limbs of a serialized record: two thousand and forty-two bytes in words of four";
    /// What the chains and the walks of this circuit fill, one power of two. The height it is
    /// **built** at is the one every description stands at.
    pub const ROWS_FILLED_LOG2: usize = 16, code "the rows the chains and the walks of an admission fill, one power of two: what the height every description stands at must hold";
}

// How the blocks of the admission stand. Block zero is idle so every chain has a seam before it.
#[derive(Clone, Copy, Debug)]
pub struct Places;

impl Places {
    pub fn record(&self) -> usize {
        1
    }

    pub fn record_blocks(&self) -> usize {
        sponge::blocks_of(RECORD_LIMBS)
    }

    pub fn record_nodes(&self) -> usize {
        self.record() + self.record_blocks()
    }

    pub fn record_depth(&self) -> usize {
        mt_merkle::KEY_BITS
    }

    pub fn admitted_leaf(&self) -> usize {
        self.record_nodes() + self.record_depth()
    }

    pub fn admitted_nodes(&self) -> usize {
        self.admitted_leaf() + sponge::blocks_of(CAPACITY)
    }

    pub fn admitted_depth(&self) -> usize {
        crate::tree_depth()
    }

    pub fn nullifier(&self) -> usize {
        self.admitted_nodes() + self.admitted_depth()
    }

    pub fn nullifier_blocks(&self) -> usize {
        sponge::blocks_of(crate::poseidon::limbs_of(&[0u8; 32]).len())
    }

    pub fn blocks(&self) -> usize {
        self.nullifier() + self.nullifier_blocks()
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    pub fn carry_rows(&self) -> Vec<usize> {
        let mut out = sponge::carry_rows(self.record(), self.record_blocks());
        out.extend(sponge::carry_rows(
            self.nullifier(),
            self.nullifier_blocks(),
        ));
        out
    }

    pub fn record_levels(&self) -> Vec<usize> {
        path::level_rows(self.record_nodes(), self.record_depth())
    }

    pub fn admitted_levels(&self) -> Vec<usize> {
        path::level_rows(self.admitted_nodes(), self.admitted_depth())
    }

    // Every seam a chain opens at, with the domain it opens under.
    // The three digests the public input carries, each four words of the hash state: the root of
    // records at the record walk\'s end, the root of admitted machines at the admitted walk\'s end,
    // and the nullifier at its chain\'s end.
    pub fn boundaries(&self) -> Vec<Boundary> {
        let ends = [
            self.seam_before(self.admitted_leaf()),
            self.seam_before(self.nullifier()),
            self.blocks() * permutation::period() - 1,
        ];
        let mut out = Vec::with_capacity(ends.len() * CAPACITY);
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
        out
    }

    // The lane stood to carry the leaf of the record into the chain that followed it; that chain
    // now absorbs the branch of the seed holding the right, and takes nothing from the walk before
    // it. What remains is two empty lists: a lane nothing loads and nothing wires is a lane that is
    // not there, and leaving it wired would leave a rule speaking about a value nobody reads.
    // The old seams:
    // record chain's last seam, and handed to the nullifier's first absorption.
    pub fn lane_loads(&self) -> Vec<usize> {
        Vec::new()
    }

    pub fn lane_wires(&self) -> Vec<usize> {
        Vec::new()
    }

    pub fn opens(&self) -> Vec<(usize, mt_codec::Domain)> {
        let mut out = vec![(self.seam_before(self.record()), domain::MT_RECORD_LEAF)];
        for level in 0..self.record_depth() {
            out.push((
                self.seam_before(self.record_nodes() + level),
                domain::MT_RECORD_NODE,
            ));
        }
        out.push((
            self.seam_before(self.admitted_leaf()),
            domain::MT_ADMITTED_LEAF,
        ));
        for level in 0..self.admitted_depth() {
            out.push((
                self.seam_before(self.admitted_nodes() + level),
                domain::MT_ADMITTED_NODE,
            ));
        }
        out.push((self.seam_before(self.nullifier()), domain::MT_OPERATOR_NF));
        out
    }
}

// The assembled shape: the permutation base at the admission\'s height, the carries, the walks and
// the capacity wiring. The loads are the seam that remains, named above.
pub fn description() -> Option<Description> {
    let places = Places;
    let rows_log2 = crate::params::ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let lane_places = lane::Places::after(path::TRACE_WIDTH);
    let width = lane_places.width();
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let walk = base + 1;
    let opens_at = walk + path::PERIODIC_COUNT;
    let lane_at = opens_at + capacity::PERIODIC_COUNT;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic.extend(path::periodic_columns(
        rows_log2,
        &[places.record_levels(), places.admitted_levels()],
        &[],
    ));
    held.periodic
        .extend(capacity::periodic_columns(rows_log2, &places.opens()));
    held.periodic.extend(lane::periodic_columns(
        rows_log2,
        &places.lane_loads(),
        &places.lane_wires(),
    ));

    held.constraints.extend(sponge::capacity_carries(carry));
    held.constraints.extend(path::constraints(walk));
    held.constraints.extend(capacity::constraints(opens_at));
    held.constraints
        .extend(lane::constraints(lane_at, &lane_places));
    held.boundaries.extend(places.boundaries());
    Some(held)
}

// The trace of an admission: every chain written through the doors that exist, the record walk by
// the bits of its key, the lane holding the record\'s commitment at every row — a cyclic hold with
// one load is a constant lane, and the constant is the digest.
pub fn trace_of(
    record: &[u8],
    key: &[u8; 32],
    record_siblings: &[crate::poseidon::Digest],
    naming: &crate::poseidon::Digest,
    admitted_siblings: &[crate::poseidon::Digest],
    admitted_position: u64,
    operator_secret: &[u8; 32],
) -> Option<(Vec<Vec<crate::field::F>>, [crate::poseidon::Digest; 3])> {
    use crate::field::F;
    use crate::poseidon::{self, CAPACITY as CAP, RATE, WIDTH};
    let places = Places;
    let rows = 1usize << crate::params::ROWS_LOG2;
    let lane_places = lane::Places::after(path::TRACE_WIDTH);
    let width = lane_places.width();
    let mut columns = vec![vec![F::ZERO; rows]; width];

    // The record chain: the serialized record absorbed limb by limb under the record leaf domain.
    let limbs = poseidon::limbs_of(record);
    let states = sponge::chain(mt_codec::domain::MT_RECORD_LEAF, &limbs);
    for (at, state) in states.iter().enumerate() {
        permutation::write_block(&mut columns, places.record() + at, state)?;
    }
    let record_leaf = poseidon::hash_bytes(mt_codec::domain::MT_RECORD_LEAF, record);

    // The record walk, by the bits of the key, least significant first — the convention of the
    // sparse tree. This mirrors the walk writer only because a position of sixty-four bits cannot
    // carry a key of two hundred and fifty-six.
    let node_capacity = poseidon::capacity_of(mt_codec::domain::MT_RECORD_NODE);
    let mut current = record_leaf;
    for (level, sibling) in record_siblings.iter().enumerate() {
        let block = places.record_nodes() + level;
        let seam = block * permutation::period() - 1;
        let bit = (key[level >> 3] >> (level & 7)) & 1 == 1;
        let (left, right) = if bit {
            (*sibling, current)
        } else {
            (current, *sibling)
        };
        for j in 0..CAP {
            columns[path::SIBLING + j][seam] = sibling.elements()[j];
            columns[path::LEFT + j][seam] = left.elements()[j];
        }
        columns[path::BIT][seam] = if bit { F::ONE } else { F::ZERO };
        let mut state = [F::ZERO; WIDTH];
        state[..CAP].copy_from_slice(left.elements());
        state[CAP..RATE].copy_from_slice(right.elements());
        state[RATE..].copy_from_slice(&node_capacity);
        permutation::write_block(&mut columns, block, &state)?;
        current = poseidon::node(mt_codec::domain::MT_RECORD_NODE, &left, &right);
    }
    let record_root = current;

    // The admitted branch, through the walk writer as it stands.
    let admitted_root_digest = path::write_walk_under(
        &mut columns,
        places.admitted_leaf(),
        naming,
        admitted_siblings,
        admitted_position,
        mt_codec::domain::MT_ADMITTED_LEAF,
        mt_codec::domain::MT_ADMITTED_NODE,
    )?;

    // The nullifier's chain: the branch of the seed that holds the one-time right to raise a
    // machine, under the domain of that right. **This is the value a candidacy publishes**, and
    // asserting it is the whole of what makes the right a right: a claimant free to publish
    // anything spends a right it never held, and a bound counted over such values counts nobody.
    // The record and the branch stand in one seed, and neither leaves the proof.
    let right_limbs = poseidon::limbs_of(operator_secret);
    let nf_states = sponge::chain(mt_codec::domain::MT_OPERATOR_NF, &right_limbs);
    for (at, state) in nf_states.iter().enumerate() {
        permutation::write_block(&mut columns, places.nullifier() + at, state)?;
    }
    let nullifier = poseidon::hash_elements(mt_codec::domain::MT_OPERATOR_NF, &right_limbs);

    // An idle block is not a row of zeros: the permutation's own rules speak at every block, and
    // the trace of nothing is the permutation of the zero state, written through the same door.
    let written: std::collections::BTreeSet<usize> = (places.record()
        ..places.record() + places.record_blocks())
        .chain(places.record_nodes()..places.record_nodes() + places.record_depth())
        .chain(places.admitted_leaf()..places.nullifier() + places.nullifier_blocks())
        .collect();
    let all_blocks = rows / permutation::period();
    for block in 0..all_blocks {
        if !written.contains(&block) {
            permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])?;
        }
    }

    // The pair and accumulator columns of the walk machinery, at every row they speak.
    path::write_pairs(&mut columns);
    path::write_accumulator(
        &mut columns,
        &[places.record_levels(), places.admitted_levels()],
        &[],
    );
    Some((columns, [record_root, admitted_root_digest, nullifier]))
}

// The public input of an admission: its three digests, in the order the boundaries bind them.
pub fn public_of(digests: &[crate::poseidon::Digest; 3]) -> Vec<u8> {
    let mut out = Vec::with_capacity(3 * 32);
    for digest in digests {
        out.extend_from_slice(&digest.bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_blocks_of_the_admission_fit_its_height() {
        let places = Places;
        assert_eq!(places.record_blocks(), 64);
        assert_eq!(places.record_depth(), 256);
        assert_eq!(places.admitted_depth(), 40);
        assert!(places.blocks() * permutation::period() <= 1 << ROWS_FILLED_LOG2);
    }

    #[test]
    fn every_chain_opens_under_its_own_domain() {
        let places = Places;
        let opens = places.opens();
        assert_eq!(
            opens.len(),
            1 + places.record_depth() + 1 + places.admitted_depth() + 1
        );
    }

    #[test]
    fn the_three_digests_are_bound_as_words_inside_the_trace() {
        let places = Places;
        let held = places.boundaries();
        assert_eq!(held.len(), 3 * CAPACITY);
        for boundary in &held {
            assert!((boundary.row as usize) < (1 << crate::params::ROWS_LOG2));
        }
    }

    #[test]
    fn an_admission_is_proven_and_verified_end_to_end() {
        use crate::poseidon::{self, Digest};
        let places = Places;
        let record = vec![0xA7u8; 2042];
        let mut key = [0u8; 32];
        key[0] = 0b1010_0110;
        key[31] = 0b0100_1001;
        // A tree holding this one record: every sibling is the empty internal of its level, and
        // the root follows the bits of the key.
        let record_empties = crate::records::empty_internals(places.record_depth());
        let record_siblings: Vec<Digest> = record_empties[..places.record_depth()].to_vec();
        let naming = Digest::of_bytes(&[0x5Cu8; 32]).expect("a digest of the family");
        let admitted_empties = crate::admitted::empty_internals(places.admitted_depth());
        let admitted_siblings: Vec<Digest> = admitted_empties[..places.admitted_depth()].to_vec();
        let (trace, digests) = trace_of(
            &record,
            &key,
            &record_siblings,
            &naming,
            &admitted_siblings,
            0,
            &[0x6Du8; 32],
        )
        .expect("a written admission");
        // The natively computed roots agree with what the trace reached.
        let mut current = poseidon::hash_bytes(mt_codec::domain::MT_RECORD_LEAF, &record);
        for (level, sibling) in record_siblings.iter().enumerate() {
            let bit = (key[level >> 3] >> (level & 7)) & 1 == 1;
            current = if bit {
                poseidon::node(mt_codec::domain::MT_RECORD_NODE, sibling, &current)
            } else {
                poseidon::node(mt_codec::domain::MT_RECORD_NODE, &current, sibling)
            };
        }
        assert_eq!(current.bytes(), digests[0].bytes(), "the record root");
        // And the value it publishes is the one-time right of the set, under its own derivation:
        // a candidacy publishing anything else publishes a right nobody issued.
        assert_eq!(
            digests[2].bytes(),
            poseidon::hash_bytes(mt_codec::domain::MT_OPERATOR_NF, &[0x6Du8; 32]).bytes(),
            "the right to raise a machine"
        );
        let held = description().expect("the description stands");
        let public = public_of(&digests);
        if !held.satisfied_by(&trace, &crate::poseidon::limbs_of(&public)) {
            for at in 0..held.constraints.len() {
                for row in 0..held.rows() {
                    if !held.evaluate(&trace, at, row).is_zero() {
                        panic!(
                            "constraint {at} of {} violated first at row {row} (block {}, offset {})",
                            held.constraints.len(),
                            row / permutation::period() as u64,
                            row % permutation::period() as u64,
                        );
                    }
                }
            }
            panic!("a boundary is violated rather than a constraint");
        }
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true admission proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));
        let mut moved = public.clone();
        moved[0] = moved[0].wrapping_add(1);
        assert!(crate::scheme::verify(&held, &moved, &bytes).is_err());
    }

    #[test]
    fn the_assembled_shape_stands_at_the_bound_and_inside_the_degree() {
        let held = description().expect("the permutation base stands");
        assert!(held.trace_width as usize <= crate::params::TRACE_WIDTH_BOUND);
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
    }
}
