// The circuit of a presence: a machine proves that it stands admitted and that the value the draw
// of a round reads is its own, disclosing neither which machine it is nor where in the tree it
// stands.
//
// **Why this circuit exists at all.** A machine attests under a one-time key of the window, and a
// key nobody can join to a machine is a key nobody can refuse either: without a proof, a fabricator
// draws secrets until one of them clears the round threshold. What the proof must bind is therefore
// the value the draw reads — and that is why the draw reads the nullifier of the machine's part
// rather than the key. Both are fixed by the secret and the window and neither is chosen, but a key
// comes of a lattice key generation, and asserting that generation inside a proof costs orders more
// than the whole statement around it. The key signs and chooses nothing; this circuit binds it by
// its digest, so a proof lifted from one attestation onto another fails at the boundary that names
// it.
//
// **The shape.** Four chains laid one after another, rows and not columns, each opening under its
// own domain through the capacity wiring: the halves of the secret — one absorption squeezed twice,
// which is what makes the half that spends and the half that names two values of one reading rather
// than two readings; the leaf and the walk of the tree of admitted machines under the naming half;
// the nullifier of the part over the spending half and the window; and the absorption of the
// one-time key, whose squeeze is the digest the public input carries.

use super::permutation::ring_column;
use super::{capacity, lane, path, permutation, sponge};
use crate::air::{Boundary, BoundaryValue, Description};
use crate::poseidon::CAPACITY;
use mt_codec::domain;

mt_codec::constants! {
    PRESENCE:
    /// The limbs of a one-time key: its bytes in words of four.
    pub const KEY_LIMBS: usize = 488, code "the limbs of a one-time answering key: one thousand nine hundred fifty-two bytes in words of four";
    /// The height of the presence: the least the folding reaches the tail from at or above what
    /// its blocks fill. The description is **built** at it — the set derives it as
    /// `presence_rows_log2` with the length of its proof beside it — because the duty of every
    /// window is priced by its own statement, not by the tallest circuit of the protocol.
    pub const PRESENCE_ROWS_LOG2: u8 = 14, writes "| `presence_rows_log2` | 14 |";
}

// How the blocks of a presence stand. Block zero is idle so every chain has a seam before it.
#[derive(Clone, Copy, Debug)]
pub struct Places;

impl Places {
    pub fn halves(&self) -> usize {
        1
    }

    // The absorption of the secret, and one block more for the second squeeze.
    pub fn halves_blocks(&self) -> usize {
        sponge::blocks_of(crate::poseidon::limbs_of(&[0u8; 32]).len()) + 1
    }

    pub fn admitted_leaf(&self) -> usize {
        self.halves() + self.halves_blocks()
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
        sponge::blocks_of(CAPACITY + 1)
    }

    pub fn key(&self) -> usize {
        self.nullifier() + self.nullifier_blocks()
    }

    pub fn key_blocks(&self) -> usize {
        sponge::blocks_of(KEY_LIMBS)
    }

    pub fn blocks(&self) -> usize {
        self.key() + self.key_blocks()
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    pub fn carry_rows(&self) -> Vec<usize> {
        // The absorption of the secret carries across its own blocks; the extra block of the second
        // squeeze overwrites nothing, and the rule that says so stands with the squeeze itself.
        // The absorption carries across its own blocks, and the seam of the second squeeze carries
        // its capacity as well: what crosses there is the whole state, rate and capacity alike.
        let mut out = sponge::carry_rows(self.halves(), self.halves_blocks());
        out.extend(sponge::carry_rows(
            self.nullifier(),
            self.nullifier_blocks(),
        ));
        out.extend(sponge::carry_rows(self.key(), self.key_blocks()));
        out
    }

    // The seam a squeeze stands at: the last row of the block whose state the second squeeze takes
    // whole. Nothing is overwritten there, so the rate crosses beside the capacity — which is what
    // makes the two halves two values of one reading of the secret rather than two readings of it.
    pub fn squeeze_rows(&self) -> Vec<usize> {
        sponge::squeeze_rows(self.halves(), self.halves_blocks() - 1)
    }

    pub fn admitted_levels(&self) -> Vec<usize> {
        path::level_rows(self.admitted_nodes(), self.admitted_depth())
    }

    // The three digests the public input carries: the root of admitted machines at the walk's end,
    // the nullifier of the part at its chain's end, and the digest of the key at its chain's end.
    pub fn boundaries(&self) -> Vec<Boundary> {
        let ends = [
            self.seam_before(self.nullifier()),
            self.seam_before(self.key()),
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

    // The lane's two seams: the half that spends, picked up at the seam of the first squeeze — the
    // ring holds it there, before the block of the second squeeze turns it into the half that names
    // — and handed to the absorption that yields the nullifier of the part. A load standing where a
    // chain opens would read the state that chain wrote instead.
    pub fn lane_loads(&self) -> Vec<usize> {
        vec![self.seam_before(self.halves() + self.halves_blocks() - 1)]
    }

    pub fn lane_wires(&self) -> Vec<usize> {
        vec![self.seam_before(self.nullifier())]
    }

    pub fn opens(&self) -> Vec<(usize, mt_codec::Domain)> {
        let mut out = vec![
            (self.seam_before(self.halves()), domain::MT_KEY_HALVES),
            (
                self.seam_before(self.admitted_leaf()),
                domain::MT_ADMITTED_LEAF,
            ),
        ];
        for level in 0..self.admitted_depth() {
            out.push((
                self.seam_before(self.admitted_nodes() + level),
                domain::MT_ADMITTED_NODE,
            ));
        }
        out.push((self.seam_before(self.nullifier()), domain::MT_PART_NF));
        out.push((self.seam_before(self.key()), domain::MT_PART_KEY));
        out
    }
}

// The assembled shape: the permutation base at the presence's height, the carries, the walk and the
// capacity wiring — the same machinery the admission assembles from, at the chains this statement
// needs.
pub fn description() -> Option<Description> {
    let places = Places;
    let rows_log2 = PRESENCE_ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let lane_places = lane::Places::after(path::TRACE_WIDTH);
    let width = lane_places.width();
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let squeeze = base + 1;
    let walk = base + 2;
    let opens_at = walk + path::PERIODIC_COUNT;
    let lane_at = opens_at + capacity::PERIODIC_COUNT;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic
        .push(sponge::carry_column(rows_log2, &places.squeeze_rows()));
    held.periodic.extend(path::periodic_columns(
        rows_log2,
        &[places.admitted_levels()],
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
    held.constraints.extend(sponge::rate_carries(squeeze));
    held.constraints.extend(path::constraints(walk));
    held.constraints.extend(capacity::constraints(opens_at));
    held.constraints
        .extend(lane::constraints(lane_at, &lane_places));
    held.boundaries.extend(places.boundaries());
    Some(held)
}

// The trace of a presence: the halves of the secret, the walk of the tree of admitted machines, the
// nullifier of the part, and the absorption of the one-time key.
pub fn trace_of(
    machine_secret: &[u8; 32],
    admitted_siblings: &[crate::poseidon::Digest],
    admitted_position: u64,
    window: u64,
    one_time_key: &[u8],
) -> Option<(Vec<Vec<crate::field::F>>, [crate::poseidon::Digest; 3])> {
    use crate::field::F;
    use crate::poseidon::{self, CAPACITY as CAP, WIDTH};
    let places = Places;
    let rows = 1usize << PRESENCE_ROWS_LOG2;
    let lane_places = lane::Places::after(path::TRACE_WIDTH);
    let width = lane_places.width();
    let mut columns = vec![vec![F::ZERO; rows]; width];

    // The halves: one absorption of the secret, squeezed twice. The half that spends is the first
    // squeeze and the half that names the second, in the order the set states.
    let secret_limbs = poseidon::limbs_of(machine_secret);
    let states = sponge::chain_twice(domain::MT_KEY_HALVES, &secret_limbs);
    for (at, state) in states.iter().enumerate() {
        permutation::write_block(&mut columns, places.halves() + at, state)?;
    }
    let (spending, naming) = poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &secret_limbs);

    // The branch of admitted machines, through the walk writer as it stands.
    let admitted_root = path::write_walk_under(
        &mut columns,
        places.admitted_leaf(),
        &naming,
        admitted_siblings,
        admitted_position,
        domain::MT_ADMITTED_LEAF,
        domain::MT_ADMITTED_NODE,
    )?;

    // The nullifier of the part: the half that spends out of the lane, and the window as one
    // element — one encoding, one nullifier.
    let mut preimage = Vec::with_capacity(CAP + 1);
    preimage.extend_from_slice(spending.elements());
    preimage.push(F::try_from_u64(window)?);
    let nf_states = sponge::chain(domain::MT_PART_NF, &preimage);
    for (at, state) in nf_states.iter().enumerate() {
        permutation::write_block(&mut columns, places.nullifier() + at, state)?;
    }
    let part_nullifier = poseidon::hash_elements(domain::MT_PART_NF, &preimage);

    // The absorption of the one-time key, whose squeeze is the digest the public input carries.
    let key_limbs = poseidon::limbs_of(one_time_key);
    if key_limbs.len() != KEY_LIMBS {
        return None;
    }
    let key_states = sponge::chain(domain::MT_PART_KEY, &key_limbs);
    for (at, state) in key_states.iter().enumerate() {
        permutation::write_block(&mut columns, places.key() + at, state)?;
    }
    let key_digest = poseidon::hash_elements(domain::MT_PART_KEY, &key_limbs);

    // The lane: a cyclic hold with one load is a constant, and the constant is the half that spends.
    for cell in 0..CAP {
        let value = spending.elements()[cell];
        for slot in columns[lane_places.cell(cell)][..rows].iter_mut() {
            *slot = value;
        }
    }

    // An idle block is not a row of zeros: the permutation's own rules speak at every block, and the
    // trace of nothing is the permutation of the zero state, written through the same door.
    let written: std::collections::BTreeSet<usize> = (places.halves()
        ..places.halves() + places.halves_blocks())
        .chain(places.admitted_leaf()..places.blocks())
        .collect();
    let all_blocks = rows / permutation::period();
    for block in 0..all_blocks {
        if !written.contains(&block) {
            permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])?;
        }
    }

    path::write_pairs(&mut columns);
    path::write_accumulator(&mut columns, &[places.admitted_levels()], &[]);
    Some((columns, [admitted_root, part_nullifier, key_digest]))
}

// The public input of a presence: the root of admitted machines, the nullifier of the part and the
// digest of the key, in the order the boundaries bind them. The window enters the nullifier it is
// absorbed into rather than standing beside it, so nothing carries a second encoding of it.
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
    fn the_blocks_of_the_presence_fit_its_height() {
        let places = Places;
        assert_eq!(places.admitted_depth(), 40);
        assert_eq!(places.key_blocks(), 62);
        const { assert!(PRESENCE_ROWS_LOG2 <= crate::params::ROWS_LOG2) };
        assert!(
            places.blocks() * permutation::period() <= 1usize << PRESENCE_ROWS_LOG2,
            "blocks {} at {} rows each stand past the height",
            places.blocks(),
            permutation::period()
        );
        // The least lawful height: one power of two lower does not reach the tail by whole
        // folds, and the one below that does not hold the blocks.
        assert!(crate::params::Shape::of_rows_log2(13).is_err());
        assert!(places.blocks() * permutation::period() > 1usize << 12);
    }

    // A machine of the tree of admitted machines: its secret, the branch its naming half stands on,
    // and the position of that leaf. The siblings are the empties of the construction, which is the
    // branch of a tree holding one machine — the smallest true walk there is.
    fn a_machine() -> ([u8; 32], Vec<crate::poseidon::Digest>, u64) {
        let secret = [0x5Au8; 32];
        let depth = crate::tree_depth();
        let empties = crate::admitted::empty_internals(depth);
        (secret, empties[..depth].to_vec(), 0)
    }

    // What a failure of the honest trace looks like, said by name rather than by a bare refusal: the
    // first rule that does not hold and the first boundary that does not bind.
    #[test]
    fn the_honest_trace_names_what_it_breaks() {
        let (secret, siblings, position) = a_machine();
        let key = vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY];
        let (trace, digests) =
            trace_of(&secret, &siblings, position, 1_000, &key).expect("the presence stands");
        let public = crate::poseidon::limbs_of(&public_of(&digests));
        let held = description().expect("the description stands");
        let mut broken: Vec<String> = Vec::new();
        for at in 0..held.constraints.len() {
            for row in 0..held.rows() {
                if !held.evaluate(&trace, at, row).is_zero() {
                    broken.push(format!("rule {at} at row {row}"));
                    break;
                }
            }
            if broken.len() > 6 {
                break;
            }
        }
        for (which, boundary) in held.boundaries.iter().enumerate() {
            let want = crate::scheme::resolve(boundary.value, &public);
            let got = trace[usize::from(boundary.column)][boundary.row as usize];
            if want != Some(got) {
                broken.push(format!(
                    "boundary {which} at column {} row {}",
                    boundary.column, boundary.row
                ));
                break;
            }
        }
        assert!(broken.is_empty(), "{}", broken.join("; "));
    }

    #[test]
    fn a_presence_is_proven_and_verified_end_to_end() {
        let (secret, siblings, position) = a_machine();
        let window = 1_000u64;
        let key = vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY];
        let (trace, digests) = trace_of(&secret, &siblings, position, window, &key)
            .expect("the presence of a machine of the tree");
        let public = public_of(&digests);
        let held = description().expect("the description stands");
        assert!(
            held.satisfied_by(&trace, &crate::poseidon::limbs_of(&public)),
            "an honest presence satisfies its own description"
        );
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true presence proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));

        // A moved public is refused: the nullifier of the part, one bit over.
        let mut moved = public.clone();
        moved[32] ^= 1;
        assert!(crate::scheme::verify(&held, &moved, &bytes).is_err());
    }

    // What the circuit publishes is what the tree computes outside it: the same root, the same
    // nullifier of the part and the same digest of the key. A circuit answering other values would
    // prove a statement about nothing the network reads.
    #[test]
    fn what_the_presence_publishes_is_what_the_tree_computes_outside_it() {
        let (secret, siblings, position) = a_machine();
        let window = 1_000u64;
        let key = vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY];
        let (_, digests) =
            trace_of(&secret, &siblings, position, window, &key).expect("the presence stands");
        let naming = crate::poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, &secret).1;
        let leaf = crate::admitted::leaf_of(&naming);
        let mut current = leaf;
        for (level, sibling) in siblings.iter().enumerate() {
            let bit = (position >> level) & 1 == 1;
            let (left, right) = if bit {
                (*sibling, current)
            } else {
                (current, *sibling)
            };
            current = crate::admitted::node(&left, &right);
        }
        assert_eq!(digests[0], current, "the root of admitted machines");
        assert_eq!(
            digests[2],
            crate::poseidon::hash_bytes(domain::MT_PART_KEY, &key),
            "the digest of the one-time key"
        );
    }

    #[test]
    fn the_description_stands_under_the_one_bound() {
        let held = description().expect("the description stands");
        assert!(usize::from(held.trace_width) <= crate::params::TRACE_WIDTH_BOUND);
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
    }
}
