// The circuit of an admission: a claimant proves that the record it walks, the right it spends and
// the half it publishes come of one admissible state — disclosing neither the record, nor the branch
// the right comes of, nor the secret of the machine, nor where the record stands in its tree.
//
// **Why the three must meet in one proof.** Each of them proven alone is a statement about nobody in
// particular: a record standing under some root, a right someone holds, a half of some secret. A
// claimant free to bring them apart walks one person's record, spends another person's right and
// seats a third person's machine, and the one machine a lived continuity buys becomes as many as
// there are records to borrow. What joins them here is two equalities and a public input the
// verifier holds: the right the record carries is the right the chain of the nullifier yields, and
// both are the value the candidacy publishes; the half the candidacy publishes is the second squeeze
// of one absorption of a secret; and the root the walk answers is the root of the one proposal the
// set names for the window, which the verifier takes and the claimant does not state.
//
// **The shape.** One trace of chained permutation blocks, rows and not columns: the record chain —
// the serialized record absorbed limb by limb, whose squeeze is its leaf in the tree of records —
// then a walk of two hundred and fifty-six node blocks under the record domains, keyed by the bits
// of the key; then the halves of the machine's secret, one absorption squeezed twice; then the chain
// of the right, whose squeeze a boundary publishes. Every chain opens under its own domain through
// the capacity wiring, and a chain wired to the wrong domain computes a value of the wrong family
// byte for byte. No walk of the tree of admitted machines stands here: a claimant who could walk it
// would need no candidacy.
//
// **What binds and how.** The root of the walk, the naming half and the right are words of the hash
// state held to the public input. The eight limbs of the record's `operator_nf` are held, where they
// enter the absorption, to the eight limbs of the same right in the public input — the device the
// opening binds the fields of a new record with, and the reason no lane is needed: the two ends meet
// in the public input, not across the trace. The bits of the record walk are witness by design, as a
// note's position is: the statement is membership under a public root, not the key. The window is a
// limb of the public input and enters the transcript of every proof, so a proof of one window stands
// for no other. The machine's commitment and its suite stand there the same way: no cell holds
// them, and the transcript every proof opens with does, so a proof seen under one `node_commit`
// stands under no other and a relay cannot lift a candidacy onto a machine of its own.
// Continuity remains open in AUDIT.md: no field of the record but its right is read.

use super::permutation::ring_column;
use super::{capacity, path, permutation, sponge};
use crate::air::{Boundary, BoundaryValue, Description};
use crate::poseidon::{CAPACITY, RATE};
use mt_codec::domain;

mt_codec::constants! {
    ADMISSION:
    /// The limbs of a serialized record: its bytes in words of four.
    pub const RECORD_LIMBS: usize = 519, code "the limbs of a serialized record: two thousand and seventy-four bytes in words of four";
    /// The first limb of a serialized record carrying the right to raise a machine it carries. It
    /// follows from the order the layout of a record fixes and from nothing else.
    pub const LIMB_OPERATOR_NF: usize = 6, code "the first of the eight limbs of a serialized record carrying the right to raise a machine";
    /// What the chains and the walks of this circuit fill, one power of two. The height it is
    /// **built** at is the one every description stands at.
    pub const ROWS_FILLED_LOG2: usize = 16, code "the rows the chains and the walks of an admission fill, one power of two: what the height every description stands at must hold";
    /// The places of the values of thirty-two bytes in the public input after the window, in the
    /// order `public_of` lays them. The machine's commitment stands at the third and binds no cell.
    pub const SLOT_RECORD_ROOT: usize = 0, code "the place of the root of records among the values of thirty-two bytes of the public input of an admission";
    pub const SLOT_NAMING_HALF: usize = 1, code "the place of the naming half among the values of thirty-two bytes of the public input of an admission";
    pub const SLOT_RIGHT: usize = 3, code "the place of the right among the values of thirty-two bytes of the public input of an admission, after the machine's commitment";
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

    pub fn halves(&self) -> usize {
        self.record_nodes() + self.record_depth()
    }

    // The absorption of the machine's secret, and one block more for the second squeeze.
    pub fn halves_blocks(&self) -> usize {
        sponge::blocks_of(secret_limbs()) + 1
    }

    pub fn nullifier(&self) -> usize {
        self.halves() + self.halves_blocks()
    }

    pub fn nullifier_blocks(&self) -> usize {
        sponge::blocks_of(secret_limbs())
    }

    pub fn blocks(&self) -> usize {
        self.nullifier() + self.nullifier_blocks()
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    // The absorption of the secret carries across its own blocks, and the seam of the second
    // squeeze carries its capacity as well: what crosses there is the whole state.
    pub fn carry_rows(&self) -> Vec<usize> {
        let mut out = sponge::carry_rows(self.record(), self.record_blocks());
        out.extend(sponge::carry_rows(self.halves(), self.halves_blocks()));
        out.extend(sponge::carry_rows(
            self.nullifier(),
            self.nullifier_blocks(),
        ));
        out
    }

    // The seam the second squeeze stands at. Nothing is overwritten there, so the rate crosses
    // beside the capacity — which is what makes the naming half a value of one reading of the
    // secret rather than of a second one.
    pub fn squeeze_rows(&self) -> Vec<usize> {
        sponge::squeeze_rows(self.halves(), self.halves_blocks() - 1)
    }

    pub fn record_levels(&self) -> Vec<usize> {
        path::level_rows(self.record_nodes(), self.record_depth())
    }

    // The public input, in the order the set gives it: the window, then the root of records, the
    // naming half, the machine's commitment and the right, each of thirty-two bytes, then the
    // suite. The window, the commitment and the suite bind no cell: they are limbs the transcript
    // of the proof opens with.
    // The three digests at the ends of their chains, and the eight limbs of the record's right held
    // where they enter the absorption — the first block of the record for the first two of them,
    // the second for the rest — to the limbs of the right the public input carries.
    pub fn boundaries(&self) -> Vec<Boundary> {
        let window = crate::poseidon::limbs_of(&0u64.to_le_bytes()).len();
        // Each end beside the place its digest takes among the values of thirty-two bytes.
        let ends = [
            (self.seam_before(self.halves()), SLOT_RECORD_ROOT),
            (self.seam_before(self.nullifier()), SLOT_NAMING_HALF),
            (self.blocks() * permutation::period() - 1, SLOT_RIGHT),
        ];
        let mut out = Vec::with_capacity(ends.len() * CAPACITY + secret_limbs());
        for (row, slot) in ends {
            for cell in 0..CAPACITY {
                out.push(Boundary {
                    column: ring_column(cell) as u16,
                    row: row as u64,
                    // A word is a pair of adjacent limbs, so a cell's index steps by two limbs.
                    value: BoundaryValue::Word((window + 2 * (slot * CAPACITY + cell)) as u16),
                });
            }
        }
        let right = window + 2 * SLOT_RIGHT * CAPACITY;
        for at in 0..secret_limbs() {
            let limb = LIMB_OPERATOR_NF + at;
            out.push(Boundary {
                column: ring_column(limb % RATE) as u16,
                row: ((self.record() + limb / RATE) * permutation::period()) as u64,
                value: BoundaryValue::Public((right + at) as u16),
            });
        }
        // The length delimiter and zero padding are constraints of the statement.
        out.extend(sponge::padding_boundaries(self.record(), RECORD_LIMBS));
        out.extend(sponge::padding_boundaries(self.halves(), secret_limbs()));
        out.extend(sponge::padding_boundaries(self.nullifier(), secret_limbs()));
        out
    }

    pub fn opens(&self) -> Vec<(usize, mt_codec::Domain)> {
        let mut out = vec![(self.seam_before(self.record()), domain::MT_RECORD_LEAF)];
        for level in 0..self.record_depth() {
            out.push((
                self.seam_before(self.record_nodes() + level),
                domain::MT_RECORD_NODE,
            ));
        }
        out.push((self.seam_before(self.halves()), domain::MT_KEY_HALVES));
        out.push((self.seam_before(self.nullifier()), domain::MT_OPERATOR_NF));
        out
    }
}

// The limbs a secret of thirty-two bytes stands in, and therefore a digest's bytes as well.
fn secret_limbs() -> usize {
    crate::poseidon::limbs_of(&[0u8; 32]).len()
}

// The assembled shape: the permutation base at the admission's height, the carries, the squeeze,
// the walk and the capacity wiring.
pub fn description() -> Option<Description> {
    let places = Places;
    let rows_log2 = crate::params::ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let width = path::TRACE_WIDTH;
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let squeeze = base + 1;
    let walk = base + 2;
    let opens_at = walk + path::PERIODIC_COUNT;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic
        .push(sponge::carry_column(rows_log2, &places.squeeze_rows()));
    held.periodic.extend(path::periodic_columns(
        rows_log2,
        &[places.record_levels()],
        &[],
    ));
    held.periodic
        .extend(capacity::periodic_columns(rows_log2, &places.opens()));

    held.constraints.extend(sponge::capacity_carries(carry));
    held.constraints.extend(sponge::rate_carries(squeeze));
    held.constraints.extend(path::constraints(walk));
    held.constraints.extend(capacity::constraints(opens_at));
    held.boundaries.extend(places.boundaries());
    Some(held)
}

// The trace of an admission: the record and its walk, the halves of the machine's secret, and the
// branch that holds the right. What comes back is the three digests the public input carries beside
// the window — the root the walk answers, the naming half and the right — as this trace computes
// them; a verifier takes the root from the proposal the set names and never from here.
pub fn trace_of(
    record: &[u8],
    key: &[u8; 32],
    record_siblings: &[crate::poseidon::Digest],
    machine_secret: &[u8; 32],
    operator_secret: &[u8; 32],
) -> Option<(Vec<Vec<crate::field::F>>, [crate::poseidon::Digest; 3])> {
    use crate::field::F;
    use crate::poseidon::{self, CAPACITY as CAP, WIDTH};
    let places = Places;
    let rows = 1usize << crate::params::ROWS_LOG2;
    let mut columns = vec![vec![F::ZERO; rows]; path::TRACE_WIDTH];

    // The record chain: the serialized record absorbed limb by limb under the record leaf domain.
    let limbs = poseidon::limbs_of(record);
    if limbs.len() != RECORD_LIMBS {
        return None;
    }
    let states = sponge::chain(domain::MT_RECORD_LEAF, &limbs);
    for (at, state) in states.iter().enumerate() {
        permutation::write_block(&mut columns, places.record() + at, state)?;
    }
    let record_leaf = poseidon::hash_elements(domain::MT_RECORD_LEAF, &limbs);

    // The record walk, by the bits of the key, least significant first — the convention of the
    // sparse tree. This mirrors the walk writer only because a position of sixty-four bits cannot
    // carry a key of two hundred and fifty-six.
    let node_capacity = poseidon::capacity_of(domain::MT_RECORD_NODE);
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
        current = poseidon::node(domain::MT_RECORD_NODE, &left, &right);
    }
    let record_root = current;

    // The halves: one absorption of the machine's secret, squeezed twice. The half that names is
    // the second squeeze, in the order the set states, and it is the one this statement publishes.
    let secret = poseidon::limbs_of(machine_secret);
    for (at, state) in sponge::chain_twice(domain::MT_KEY_HALVES, &secret)
        .iter()
        .enumerate()
    {
        permutation::write_block(&mut columns, places.halves() + at, state)?;
    }
    let naming = poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &secret).1;

    // The chain of the right: the branch of the seed that holds the one-time right to raise a
    // machine, under the domain of that right. **This is the value a candidacy publishes**, and the
    // boundaries hold the record's own field to it: a claimant free to publish anything spends a
    // right it never held, and one free to pair it with any record spends a right that record does
    // not carry.
    let right_limbs = poseidon::limbs_of(operator_secret);
    for (at, state) in sponge::chain(domain::MT_OPERATOR_NF, &right_limbs)
        .iter()
        .enumerate()
    {
        permutation::write_block(&mut columns, places.nullifier() + at, state)?;
    }
    let nullifier = poseidon::hash_elements(domain::MT_OPERATOR_NF, &right_limbs);

    // An idle block is not a row of zeros: the permutation's own rules speak at every block, and
    // the trace of nothing is the permutation of the zero state, written through the same door.
    let all_blocks = rows / permutation::period();
    for block in 0..all_blocks {
        if !(places.record()..places.blocks()).contains(&block) {
            permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])?;
        }
    }

    // The pair and accumulator columns of the walk machinery, at every row they speak.
    path::write_pairs(&mut columns);
    path::write_accumulator(&mut columns, &[places.record_levels()], &[]);
    Some((columns, [record_root, naming, nullifier]))
}

// The public input of an admission, in the order the set gives it: the window the candidacy is
// published in, the root of records of the proposal the set names for that window, the naming
// half, the commitment of the machine, the right, and the suite. A verifier lays it from the
// window it applies, the root it holds and the four fields of the object, and from nothing else.
pub fn public_of(
    window: u64,
    record_root: &crate::poseidon::Digest,
    naming_half: &crate::poseidon::Digest,
    node_commit: &[u8; 32],
    operator_nullifier: &crate::poseidon::Digest,
    suite_id: u16,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + 4 * 32 + 2);
    out.extend_from_slice(&window.to_le_bytes());
    out.extend_from_slice(&record_root.bytes());
    out.extend_from_slice(&naming_half.bytes());
    out.extend_from_slice(node_commit);
    out.extend_from_slice(&operator_nullifier.bytes());
    out.extend_from_slice(&suite_id.to_le_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::poseidon::{self, Digest};

    const WINDOW: u64 = 1_000;

    // A record of the layout the set fixes, carrying the right of `operator_secret`. The bytes are
    // laid here by hand because this crate stands below the one that owns that layout.
    fn a_record(operator_secret: &[u8; 32]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&0b1011u64.to_le_bytes()); // segment_bitmap
        out.extend_from_slice(&7u32.to_le_bytes()); // last_active_segment
        out.extend_from_slice(&990u64.to_le_bytes()); // opened_window
        out.extend_from_slice(&4u32.to_le_bytes()); // own_height
        out.extend_from_slice(
            &poseidon::hash_bytes(domain::MT_OPERATOR_NF, operator_secret).bytes(),
        );
        out.extend_from_slice(&[0x11u8; 32]); // fabric_root
        out.extend_from_slice(&1u16.to_le_bytes()); // suite_id
        out.extend_from_slice(&[0x44u8; mt_codec::size::SIGNING_PUBLIC_KEY]);
        out.extend_from_slice(&[0x33u8; 32]); // blind
        out
    }

    // A tree of records holding this one record at the key its commitment is: the key and the
    // siblings of its walk, and the root a verifier holds of that tree.
    fn the_tree_of(record: &[u8]) -> ([u8; 32], Vec<Digest>, Digest) {
        let leaf = crate::records::leaf(record);
        let leaves: std::collections::BTreeMap<[u8; 32], Digest> =
            std::iter::once((leaf.bytes(), leaf)).collect();
        let path = crate::records::path_of_leaves(&leaves, &leaf.bytes()).expect("it stands");
        (leaf.bytes(), path, crate::records::root_of_leaves(&leaves))
    }

    const MACHINE: [u8; 32] = [0x5A; 32];
    const RIGHT: [u8; 32] = [0x22; 32];
    const NODE_COMMIT: [u8; 32] = [0x66; 32];
    const SUITE: u16 = 1;

    fn public_at(digests: &[Digest; 3], window: u64) -> Vec<u8> {
        public_of(
            window,
            &digests[0],
            &digests[1],
            &NODE_COMMIT,
            &digests[2],
            SUITE,
        )
    }

    fn public_of_the(digests: &[Digest; 3], window: u64) -> Vec<crate::field::F> {
        poseidon::limbs_of(&public_at(digests, window))
    }

    #[test]
    fn the_blocks_of_the_admission_fit_its_height() {
        let places = Places;
        assert_eq!(places.record_blocks(), 65);
        assert_eq!(places.record_depth(), 256);
        assert_eq!(places.halves_blocks(), 3);
        assert!(places.blocks() * permutation::period() <= 1 << ROWS_FILLED_LOG2);
        // The right of a record stands past the four fields an opening binds and inside the first
        // two blocks of its absorption, where the boundaries reach it.
        assert_eq!(
            LIMB_OPERATOR_NF,
            crate::poseidon::limbs_of(&[0u8; 24]).len(),
            "the right does not follow own_height"
        );
    }

    #[test]
    fn every_chain_opens_under_its_own_domain() {
        let places = Places;
        assert_eq!(places.opens().len(), 1 + places.record_depth() + 1 + 1);
    }

    #[test]
    fn the_three_digests_and_the_right_of_the_record_are_bound_inside_the_trace() {
        let held = Places.boundaries();
        let words = held
            .iter()
            .filter(|b| matches!(b.value, BoundaryValue::Word(_)))
            .count();
        let limbs = held
            .iter()
            .filter(|b| matches!(b.value, BoundaryValue::Public(_)))
            .count();
        assert_eq!(words, 3 * CAPACITY);
        assert_eq!(limbs, secret_limbs());
        for boundary in &held {
            assert!((boundary.row as usize) < (1 << crate::params::ROWS_LOG2));
        }
    }

    // The honest admission from one state: the record of the claimant, its walk in the tree that
    // holds it, the claimant's own machine and the right the record carries. It satisfies, proves
    // and verifies; and what it publishes is what the tree and the doors compute outside it. The
    // same proof is then refused for the root of another state and for another window — the named
    // wrong implementations being a verifier that takes the root from the candidacy and a public
    // input that leaves the window out.
    #[test]
    fn an_admission_from_one_state_is_proven_and_verified_end_to_end() {
        let record = a_record(&RIGHT);
        let (key, siblings, root) = the_tree_of(&record);
        let (trace, digests) =
            trace_of(&record, &key, &siblings, &MACHINE, &RIGHT).expect("a written admission");
        assert_eq!(digests[0], root, "the root of records");
        assert_eq!(
            digests[1],
            poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, &MACHINE).1,
            "the naming half"
        );
        assert_eq!(
            digests[2],
            poseidon::hash_bytes(domain::MT_OPERATOR_NF, &RIGHT),
            "the right to raise a machine"
        );
        let held = description().expect("the description stands");
        let public = public_at(&digests, WINDOW);
        if !held.satisfied_by(&trace, &poseidon::limbs_of(&public)) {
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

        // Another state: the same record beside a second one, whose root is not this one.
        let other = a_record(&[0x23; 32]);
        let leaves: std::collections::BTreeMap<[u8; 32], Digest> = [&record, &other]
            .iter()
            .map(|r| {
                let leaf = crate::records::leaf(r);
                (leaf.bytes(), leaf)
            })
            .collect();
        let another_root = crate::records::root_of_leaves(&leaves);
        assert_ne!(another_root, root);
        let elsewhere = public_of(
            WINDOW,
            &another_root,
            &digests[1],
            &NODE_COMMIT,
            &digests[2],
            SUITE,
        );
        assert!(crate::scheme::verify(&held, &elsewhere, &bytes).is_err());
        assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&elsewhere)));

        // Another window: no cell holds it, and the transcript does.
        let later = public_at(&digests, WINDOW + 1);
        assert!(crate::scheme::verify(&held, &later, &bytes).is_err());

        // Another machine's commitment and another suite: no cell holds them either, and the
        // same proof stands under neither. The named wrong implementation: a public input that
        // leaves `node_commit` out, under which a relay lifts the candidacy onto its own machine.
        let mut lifted = [0x99u8; 32];
        lifted[0] = NODE_COMMIT[0];
        for other in [
            public_of(
                WINDOW,
                &digests[0],
                &digests[1],
                &lifted,
                &digests[2],
                SUITE,
            ),
            public_of(
                WINDOW,
                &digests[0],
                &digests[1],
                &NODE_COMMIT,
                &digests[2],
                SUITE + 1,
            ),
        ] {
            assert!(held.satisfied_by(&trace, &poseidon::limbs_of(&other)));
            assert!(crate::scheme::verify(&held, &other, &bytes).is_err());
        }
    }

    // The counterexample of the audit at the relation: a foreign record — one carrying another
    // person's right — walked honestly in its own tree, with the claimant's own secret and the
    // claimant's own right. Every chain is computed truly from what it absorbs, and the statement
    // still refuses, at the limbs of the record's right. The named wrong implementation: the chains
    // of the record and of the right standing side by side with no cell or limb in common, which
    // accepted exactly this trace.
    #[test]
    fn a_foreign_record_does_not_carry_the_claimants_right() {
        let foreign = a_record(&[0x23; 32]);
        let (key, siblings, _) = the_tree_of(&foreign);
        let (trace, digests) =
            trace_of(&foreign, &key, &siblings, &MACHINE, &RIGHT).expect("an attacker writes it");
        let held = description().expect("the description stands");
        assert!(
            !held.satisfied_by(&trace, &public_of_the(&digests, WINDOW)),
            "a record carrying another right satisfied the admission"
        );
        // Nor does it pass by publishing the foreign right instead: the chain of the right is over
        // the claimant's own branch, and its squeeze is held to the same limbs.
        let mut claimed = digests;
        claimed[2] = poseidon::hash_bytes(domain::MT_OPERATOR_NF, &[0x23; 32]);
        assert!(
            !held.satisfied_by(&trace, &public_of_the(&claimed, WINDOW)),
            "a right the claimant does not hold satisfied the admission"
        );
    }

    // The right the public input carries is the one the chain yields and the one the record
    // carries, and no other: an honest trace with the right of another branch in its public input
    // is refused. The named wrong implementation: a right published beside the proof and bound to
    // nothing inside it.
    #[test]
    fn another_right_in_the_public_input_does_not_satisfy() {
        let record = a_record(&RIGHT);
        let (key, siblings, _) = the_tree_of(&record);
        let (trace, mut digests) =
            trace_of(&record, &key, &siblings, &MACHINE, &RIGHT).expect("an honest trace");
        digests[2] = poseidon::hash_bytes(domain::MT_OPERATOR_NF, &[0x24; 32]);
        assert!(!description()
            .expect("the description stands")
            .satisfied_by(&trace, &public_of_the(&digests, WINDOW)));
    }

    // A claimant with a secret of its own cannot publish the naming half of a machine whose secret
    // it does not hold: the half is the second squeeze of the absorption the trace carries, and a
    // half lifted off the tree of admitted machines — where every leaf is public — is another
    // value. The named wrong implementation: the naming half a free parameter of the trace, which
    // let a claimant seat a machine that answers to somebody else.
    #[test]
    fn a_candidacy_cannot_graft_another_machines_naming_half() {
        let record = a_record(&RIGHT);
        let (key, siblings, _) = the_tree_of(&record);
        let stranger = [0xB7u8; 32];
        let (trace, mut digests) =
            trace_of(&record, &key, &siblings, &stranger, &RIGHT).expect("an attacker writes it");
        digests[1] = poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, &MACHINE).1;
        assert!(
            !description()
                .expect("the description stands")
                .satisfied_by(&trace, &public_of_the(&digests, WINDOW)),
            "the naming half must be of the secret the trace absorbs"
        );
    }

    // The naming half is the second squeeze of one absorption and of no second reading: a trace
    // whose block of the second squeeze keeps the capacity the absorption left and enters with a
    // rate of the prover's choosing is refused, even with its own squeeze published. The named
    // wrong implementation: the seam of the squeeze holding the capacity alone, under which the
    // prover writes into the rate whatever reaches the half it wants to publish.
    #[test]
    fn the_naming_half_is_the_second_squeeze_of_one_absorption() {
        let record = a_record(&RIGHT);
        let (key, siblings, _) = the_tree_of(&record);
        let (mut trace, mut digests) =
            trace_of(&record, &key, &siblings, &MACHINE, &RIGHT).expect("an honest trace");
        let places = Places;
        let halves = sponge::chain_twice(domain::MT_KEY_HALVES, &poseidon::limbs_of(&MACHINE));
        let mut chosen = *halves.last().expect("a chain holds a block");
        chosen[0] = chosen[0].plus(crate::field::F::ONE);
        let squeeze = places.halves() + places.halves_blocks() - 1;
        let left = permutation::write_block(&mut trace, squeeze, &chosen).expect("it fits");
        let mut half = [0u8; 32];
        for (at, cell) in left[..CAPACITY].iter().enumerate() {
            half[at * 8..at * 8 + 8].copy_from_slice(&cell.as_u64().to_le_bytes());
        }
        digests[1] = Digest::of_bytes(&half).expect("a digest of the family");
        path::write_pairs(&mut trace);
        assert!(
            !description()
                .expect("the description stands")
                .satisfied_by(&trace, &public_of_the(&digests, WINDOW)),
            "a second reading of a secret stood for the second squeeze of the first"
        );
    }

    #[test]
    fn the_assembled_shape_stands_at_the_bound_and_inside_the_degree() {
        let held = description().expect("the permutation base stands");
        assert!(held.trace_width as usize <= crate::params::TRACE_WIDTH_BOUND);
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
    }

    #[test]
    fn padding_cannot_create_a_second_nullifier_for_one_right() {
        let record = a_record(&RIGHT);
        let (key, siblings, _) = the_tree_of(&record);
        let (mut trace, mut digests) =
            trace_of(&record, &key, &siblings, &MACHINE, &RIGHT).expect("an honest trace");
        let description = description().unwrap();
        assert!(description.satisfied_by(&trace, &public_of_the(&digests, WINDOW)));
        let mut longer = crate::poseidon::limbs_of(&RIGHT);
        longer.push(crate::field::F::ONE);
        for (at, state) in sponge::chain(domain::MT_OPERATOR_NF, &longer)
            .iter()
            .enumerate()
        {
            permutation::write_block(&mut trace, Places.nullifier() + at, state).unwrap();
        }
        digests[2] = crate::poseidon::hash_elements(domain::MT_OPERATOR_NF, &longer);
        path::write_pairs(&mut trace);
        assert!(
            !description.satisfied_by(&trace, &public_of_the(&digests, WINDOW)),
            "padding must not give another nullifier to the same right"
        );
    }
}
