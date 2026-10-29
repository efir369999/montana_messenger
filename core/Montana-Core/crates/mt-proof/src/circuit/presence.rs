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
// **The shape.** Seven chains laid one after another, rows and not columns, each opening under its
// own domain through the capacity wiring: the halves of the secret — one absorption squeezed twice,
// which is what makes the half that spends and the half that names two values of one reading rather
// than two readings; the leaf and the walk of the tree of admitted machines under the naming half;
// the nullifier of the part over the spending half and the window; the absorption of the one-time
// key, whose squeeze is the digest the public input carries; and, since the author's record 309, the
// three derivations of the line the pledge's proof draws — the lock-opening value over the spending
// half, the slope of the open slot of attempt zero over that half, the window and the slot, and the
// abscissa of the name attested.
//
// **Why the presence asserts a point of a line.** The heavy attestation is the open pledge of
// attempt zero. Two of them under one part naming two names are the first of the contradicting
// pairs, and the evidence that moves a lock is the lock-opening value their two points give. A value
// no proof binds is a value anyone writes, so the presence binds `line_value` to the half its part
// is named by, through the same lane and the same rules the pledge uses (Canon, "The confirmation of
// a window", "What its proof asserts").

use super::permutation::ring_column;
use super::{capacity, lane, path, permutation, pledge, sponge};
use crate::air::{Boundary, BoundaryValue, Description};
use crate::field::F;
use crate::line::{self, L};
use crate::poseidon::{CAPACITY, RATE};
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
    /// Where the fields after the three digests stand in the public input, in limbs of four bytes:
    /// the window, the name attested and the value of the line, in the order Consensus states.
    const WINDOW: u16 = 24, code "the first limb of the window in the public input of a presence, after the root, the digest of the key and the nullifier of the part";
    const NAME: u16 = 26, code "the first of the eight limbs of the name attested in the public input of a presence, after the two of the window";
    const LINE_VALUE: u16 = 34, code "the first limb of the value of the line in the public input of a presence, after the eight of the name";
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

    // The three derivations of the line (record 309): the lock-opening value over the spending
    // half, the slope over that half, the window and the slot, and the abscissa over the eight limbs
    // of the name — the pledge's three, after the key.
    pub fn opening(&self) -> usize {
        self.key() + self.key_blocks()
    }

    pub fn opening_blocks(&self) -> usize {
        sponge::blocks_of(CAPACITY)
    }

    pub fn slope(&self) -> usize {
        self.opening() + self.opening_blocks()
    }

    pub fn slope_blocks(&self) -> usize {
        sponge::blocks_of(CAPACITY + 2)
    }

    pub fn abscissa(&self) -> usize {
        self.slope() + self.slope_blocks()
    }

    pub fn abscissa_blocks(&self) -> usize {
        sponge::blocks_of(crate::poseidon::limbs_of(&[0u8; 32]).len())
    }

    pub fn blocks(&self) -> usize {
        self.abscissa() + self.abscissa_blocks()
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    pub fn carry_rows(&self) -> Vec<usize> {
        // The absorption of the secret carries across its own blocks, and the seam of the second
        // squeeze carries its capacity as well: what crosses there is the whole state, rate and
        // capacity alike. Every other chain carries across its own blocks.
        let mut out = sponge::carry_rows(self.halves(), self.halves_blocks());
        for (first, blocks) in [
            (self.nullifier(), self.nullifier_blocks()),
            (self.key(), self.key_blocks()),
            (self.opening(), self.opening_blocks()),
            (self.slope(), self.slope_blocks()),
            (self.abscissa(), self.abscissa_blocks()),
        ] {
            out.extend(sponge::carry_rows(first, blocks));
        }
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

    // Consensus orders the public input as admitted root, key digest, part nullifier, window, name
    // attested, value of the line. Trace order differs: the nullifier is absorbed before the key, so
    // each seam names its public position explicitly.
    pub fn boundaries(&self, held: &Held) -> Vec<Boundary> {
        let period = permutation::period();
        let ends = [
            (self.seam_before(self.nullifier()), 0),
            (self.seam_before(self.key()), 2),
            (self.seam_before(self.opening()), 1),
        ];
        let mut out = Vec::new();
        for (row, which) in ends {
            for cell in 0..CAPACITY {
                out.push(Boundary {
                    column: ring_column(cell) as u16,
                    row: row as u64,
                    // A word is a pair of adjacent limbs, so a cell's index steps by two limbs.
                    value: BoundaryValue::Word((2 * (which * CAPACITY + cell)) as u16),
                });
            }
        }
        // The window is verifier input, one element in the nullifier of the part and in the slope.
        // A private window would let one admitted machine derive arbitrarily many parts of this
        // window, or draw the slope of one window under the part of another.
        for block in [self.nullifier(), self.slope()] {
            out.push(Boundary {
                column: ring_column(CAPACITY) as u16,
                row: (block * period) as u64,
                value: BoundaryValue::Word(WINDOW),
            });
        }
        // The slot is the open slot of attempt zero and no other: the heavy attestation is that
        // pledge, so its slot is a literal of the statement and not a choice of the prover.
        out.push(Boundary {
            column: ring_column(CAPACITY + 1) as u16,
            row: (self.slope() * period) as u64,
            value: BoundaryValue::Literal(line::slot(0, false)),
        });
        // The name attested, absorbed as its eight limbs.
        for at in 0..crate::poseidon::limbs_of(&[0u8; 32]).len() {
            out.push(Boundary {
                column: ring_column(at % RATE) as u16,
                row: ((self.abscissa() + at / RATE) * period) as u64,
                value: BoundaryValue::Public(NAME + at as u16),
            });
        }
        for cell in 0..CAPACITY {
            out.push(Boundary {
                column: held.value(cell) as u16,
                row: 0,
                value: BoundaryValue::Word(LINE_VALUE + 2 * cell as u16),
            });
        }
        for (first, elements) in [
            (self.halves(), crate::poseidon::limbs_of(&[0u8; 32]).len()),
            (self.admitted_leaf(), CAPACITY),
            (self.nullifier(), CAPACITY + 1),
            (self.key(), KEY_LIMBS),
            (self.opening(), CAPACITY),
            (self.slope(), CAPACITY + 2),
            (
                self.abscissa(),
                crate::poseidon::limbs_of(&[0u8; 32]).len(),
            ),
        ] {
            out.extend(sponge::padding_boundaries(first, elements));
        }
        out
    }

    // The lane's seams: the half that spends, picked up at the seam of the first squeeze — the ring
    // holds it there, before the block of the second squeeze turns it into the half that names — and
    // handed to the three absorptions that take it: the nullifier of the part, the lock-opening value
    // and the slope. A load standing where a chain opens would read the state that chain wrote
    // instead.
    pub fn lane_loads(&self) -> Vec<usize> {
        vec![self.seam_before(self.halves() + self.halves_blocks() - 1)]
    }

    pub fn lane_wires(&self) -> Vec<usize> {
        vec![
            self.seam_before(self.nullifier()),
            self.seam_before(self.opening()),
            self.seam_before(self.slope()),
        ]
    }

    // The rows the digests of the opening, the slope and the abscissa stand at: the last row of each
    // chain.
    pub fn loads(&self) -> [usize; 3] {
        [
            self.seam_before(self.slope()),
            self.seam_before(self.abscissa()),
            self.seam_before(self.blocks()),
        ]
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
        out.push((self.seam_before(self.key()), domain::MT_PART_KEY_DIGEST));
        out.push((self.seam_before(self.opening()), domain::MT_LINE_OPENING));
        out.push((self.seam_before(self.slope()), domain::MT_LINE_SLOPE));
        out.push((self.seam_before(self.abscissa()), domain::MT_LINE_ABSCISSA));
        out
    }
}

// The held columns of the line, standing after the lane: the opening, the slope, the abscissa and
// the value, a digest wide each. The slot needs none: it is a literal of the statement.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Held {
    pub first: usize,
}

impl Held {
    pub const fn after(width: usize) -> Self {
        Self { first: width }
    }

    pub const fn opening(&self, cell: usize) -> usize {
        self.first + cell
    }

    pub const fn slope(&self, cell: usize) -> usize {
        self.first + CAPACITY + cell
    }

    pub const fn abscissa(&self, cell: usize) -> usize {
        self.first + 2 * CAPACITY + cell
    }

    pub const fn value(&self, cell: usize) -> usize {
        self.first + 3 * CAPACITY + cell
    }

    pub const fn width(&self) -> usize {
        self.first + 4 * CAPACITY
    }
}

fn columns() -> (lane::Places, Held) {
    let lane_places = lane::Places::after(path::TRACE_WIDTH);
    (lane_places, Held::after(lane_places.width()))
}

// The assembled shape: the permutation base at the presence's height, the carries, the walk, the
// capacity wiring, the lane, and the rules of the line — the same machinery the admission and the
// pledge assemble from, at the chains this statement needs.
pub fn description() -> Option<Description> {
    assembled(&Places.lane_wires())
}

fn assembled(wires: &[usize]) -> Option<Description> {
    let places = Places;
    let rows_log2 = PRESENCE_ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let (lane_places, columns) = columns();
    let width = columns.width();
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let squeeze = base + 1;
    let naming = base + 2;
    let walk = base + 3;
    let opens_at = walk + path::PERIODIC_COUNT;
    let lane_at = opens_at + capacity::PERIODIC_COUNT;
    let loads_at = lane_at + lane::PERIODIC_COUNT;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic
        .push(sponge::carry_column(rows_log2, &places.squeeze_rows()));
    held.periodic.push(sponge::carry_column(
        rows_log2,
        &[places.seam_before(places.admitted_leaf())],
    ));
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
        wires,
    ));
    for row in places.loads() {
        held.periodic.push(sponge::carry_column(rows_log2, &[row]));
    }

    held.constraints.extend(sponge::capacity_carries(carry));
    held.constraints.extend(sponge::rate_carries(squeeze));
    held.constraints.extend(sponge::digest_carries(naming));
    held.constraints.extend(path::constraints(walk));
    held.constraints.extend(capacity::constraints(opens_at));
    held.constraints
        .extend(lane::constraints(lane_at, &lane_places));
    held.constraints
        .extend(pledge::holds(columns.first..columns.width()));
    held.constraints.extend(pledge::loads(
        loads_at,
        [columns.opening(0), columns.slope(0), columns.abscissa(0)],
    ));
    held.constraints.extend(pledge::the_line(
        columns.opening(0),
        columns.slope(0),
        columns.abscissa(0),
        columns.value(0),
    ));
    held.boundaries.extend(places.boundaries(&columns));
    Some(held)
}

// The trace of a presence: the halves of the secret, the walk of the tree of admitted machines, the
// nullifier of the part, the absorption of the one-time key, and the line of the open slot of
// attempt zero at the name attested. Beside the trace it gives the three digests the public input
// carries and the value of the line. A name whose abscissa is zero is attested by nobody: the line
// there is the lock-opening value itself.
pub fn trace_of(
    machine_secret: &[u8; 32],
    admitted_siblings: &[crate::poseidon::Digest],
    admitted_position: u64,
    window: u64,
    name: &[u8; 32],
    one_time_key: &[u8],
) -> Option<(Vec<Vec<F>>, [crate::poseidon::Digest; 3], L)> {
    use crate::poseidon::{self, CAPACITY as CAP, WIDTH};
    let places = Places;
    let rows = 1usize << PRESENCE_ROWS_LOG2;
    let (lane_places, held) = columns();
    let mut columns = vec![vec![F::ZERO; rows]; held.width()];

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
    let part_nullifier = poseidon::hash_elements(domain::MT_PART_NF, &preimage);

    // The absorption of the one-time key, whose squeeze is the digest the public input carries.
    let key_limbs = poseidon::limbs_of(one_time_key);
    if key_limbs.len() != KEY_LIMBS {
        return None;
    }
    let key_digest = poseidon::hash_elements(domain::MT_PART_KEY_DIGEST, &key_limbs);

    // The line of the open slot of attempt zero: the slope absorbs the nullifier's preimage and the
    // slot after it, as the pledge's does.
    let slot = line::slot(0, false);
    let mut sloped = preimage.clone();
    sloped.push(F::try_from_u64(slot)?);
    let name_limbs = poseidon::limbs_of(name);
    for (first, states) in [
        (
            places.nullifier(),
            sponge::chain(domain::MT_PART_NF, &preimage),
        ),
        (
            places.key(),
            sponge::chain(domain::MT_PART_KEY_DIGEST, &key_limbs),
        ),
        (
            places.opening(),
            sponge::chain(domain::MT_LINE_OPENING, spending.elements()),
        ),
        (
            places.slope(),
            sponge::chain(domain::MT_LINE_SLOPE, &sloped),
        ),
        (
            places.abscissa(),
            sponge::chain(domain::MT_LINE_ABSCISSA, &name_limbs),
        ),
    ] {
        for (at, state) in states.iter().enumerate() {
            permutation::write_block(&mut columns, first + at, state)?;
        }
    }
    let opening = line::opening(&spending);
    let slope = line::slope(&spending, window, slot)?;
    let abscissa = line::abscissa(name)?;
    let value = line::line_at(opening, slope, abscissa);

    // The lane: a cyclic hold with one load is a constant, and the constant is the half that spends.
    // The held elements of the line are constants the same way.
    for cell in 0..CAP {
        columns[lane_places.cell(cell)].fill(spending.elements()[cell]);
        columns[held.opening(cell)].fill(opening.coefficients()[cell]);
        columns[held.slope(cell)].fill(slope.coefficients()[cell]);
        columns[held.abscissa(cell)].fill(abscissa.coefficients()[cell]);
        columns[held.value(cell)].fill(value.coefficients()[cell]);
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
    Some((columns, [admitted_root, part_nullifier, key_digest], value))
}

// The public input in the order Consensus states: admitted root, key digest, part nullifier, the
// window the verifier is checking, the name attested and the value of the line. The window and the
// name already belong to the attestation and the value is its `line_value`; these bytes add no
// field to its wire layout.
pub fn public_of(
    digests: &[crate::poseidon::Digest; 3],
    window: u64,
    name: &[u8; 32],
    line_value: L,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(3 * 32 + 8 + 32 + line::ELEMENT_BYTES);
    for digest in [&digests[0], &digests[2], &digests[1]] {
        out.extend_from_slice(&digest.bytes());
    }
    out.extend_from_slice(&window.to_le_bytes());
    out.extend_from_slice(name);
    out.extend_from_slice(&line_value.to_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::super::trial::{broken, fill};
    use super::*;
    use crate::poseidon::Digest;

    const AT: u64 = 1_000;
    const FIRST: [u8; 32] = [0x11; 32];
    const SECOND: [u8; 32] = [0x22; 32];

    #[test]
    fn the_blocks_of_the_presence_fit_its_height() {
        let places = Places;
        assert_eq!(places.admitted_depth(), 40);
        assert_eq!(places.key_blocks(), 62);
        // The three derivations of the line add four blocks to the 108 (Canon, "What its proof
        // asserts").
        assert_eq!(places.blocks(), 112);
        const { assert!(PRESENCE_ROWS_LOG2 <= crate::params::ROWS_LOG2) };
        let held = description().expect("the description stands");
        assert!(
            (places.blocks() * permutation::period()) as u64 <= held.live_rows(),
            "blocks {} at {} rows each stand past the live rows",
            places.blocks(),
            permutation::period()
        );
        // The least lawful height: one power of two lower does not reach the tail by whole
        // folds, and the one below that does not hold the blocks.
        assert!(crate::params::Shape::of_rows_log2(13).is_err());
        assert!(places.blocks() * permutation::period() > 1usize << 12);
        assert_eq!(
            public_of(&[Digest::ZERO; 3], 0, &FIRST, L::ZERO).len(),
            4 * usize::from(LINE_VALUE) + line::ELEMENT_BYTES
        );
    }

    // A machine of the tree of admitted machines: its secret, the branch its naming half stands on,
    // and the position of that leaf. The siblings are the empties of the construction, which is the
    // branch of a tree holding one machine — the smallest true walk there is.
    fn a_machine() -> ([u8; 32], Vec<Digest>, u64) {
        let secret = [0x5Au8; 32];
        let depth = crate::tree_depth();
        let empties = crate::admitted::empty_internals(depth);
        (secret, empties[..depth].to_vec(), 0)
    }

    fn key() -> Vec<u8> {
        vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY]
    }

    fn limbs(digests: &[Digest; 3], name: &[u8; 32], value: L) -> Vec<F> {
        crate::poseidon::limbs_of(&public_of(digests, AT, name, value))
    }

    // The presence of the machine of `a_machine` in window `AT` attesting `name`: its trace, the
    // limbs of its public input, its digests and the value of its line.
    fn present(name: &[u8; 32]) -> (Vec<Vec<F>>, Vec<F>, [Digest; 3], L) {
        let (secret, siblings, position) = a_machine();
        let (trace, digests, value) = trace_of(&secret, &siblings, position, AT, name, &key())
            .expect("the presence of a machine of the tree");
        let public = limbs(&digests, name, value);
        (trace, public, digests, value)
    }

    fn spending_of(secret: &[u8; 32]) -> Digest {
        crate::poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, secret).0
    }

    fn slope_elements(spending: &Digest, slot: u64) -> Vec<F> {
        let mut out = spending.elements().to_vec();
        out.push(F::try_from_u64(AT).expect("the window is an element"));
        out.push(F::try_from_u64(slot).expect("the slot is an element"));
        out
    }

    // The slope chain written over other elements, with the held slope and the held value moved to
    // match it: a forger who keeps every rule it can keep, so what fails is the one it cannot.
    fn reslope(trace: &mut [Vec<F>], elements: &[F], name: &[u8; 32]) -> L {
        for (at, state) in sponge::chain(domain::MT_LINE_SLOPE, elements)
            .iter()
            .enumerate()
        {
            permutation::write_block(trace, Places.slope() + at, state).expect("fits");
        }
        let slope = L::of_digest(&crate::poseidon::hash_elements(
            domain::MT_LINE_SLOPE,
            elements,
        ));
        let (_, held) = columns();
        fill(trace, held.slope(0), slope);
        let opening = line::opening(&spending_of(&a_machine().0));
        let value = line::line_at(opening, slope, line::abscissa(name).expect("an abscissa"));
        fill(trace, held.value(0), value);
        value
    }

    #[test]
    fn a_presence_cannot_graft_another_machines_public_membership_path() {
        let (admitted_secret, siblings, position) = a_machine();
        let stranger = [0xB7; 32];
        let (mut trace, mut digests, value) =
            trace_of(&stranger, &siblings, position, AT, &FIRST, &key())
                .expect("an attacker can compute its own trace");
        let (_, public_naming_half) = crate::poseidon::hash_elements_twice(
            domain::MT_KEY_HALVES,
            &crate::poseidon::limbs_of(&admitted_secret),
        );
        let places = Places;
        digests[0] = path::write_walk_under(
            &mut trace,
            places.admitted_leaf(),
            &public_naming_half,
            &siblings,
            position,
            domain::MT_ADMITTED_LEAF,
            domain::MT_ADMITTED_NODE,
        )
        .expect("the membership branch contains no secret");
        path::write_pairs(&mut trace);
        path::write_accumulator(&mut trace, &[places.admitted_levels()], &[]);
        assert!(
            !description()
                .expect("description")
                .satisfied_by(&trace, &limbs(&digests, &FIRST, value)),
            "membership must belong to the secret that derives the part nullifier"
        );
    }

    #[test]
    fn a_part_cannot_choose_extra_nullifiers_through_sponge_padding() {
        let (mut trace, _, mut digests, value) = present(&FIRST);
        let mut forged_preimage = spending_of(&a_machine().0).elements().to_vec();
        forged_preimage.push(F::try_from_u64(AT).expect("window fits"));
        forged_preimage.push(F::ONE);
        let places = Places;
        for (at, state) in sponge::chain(domain::MT_PART_NF, &forged_preimage)
            .iter()
            .enumerate()
        {
            permutation::write_block(&mut trace, places.nullifier() + at, state).expect("fits");
        }
        digests[1] = crate::poseidon::hash_elements(domain::MT_PART_NF, &forged_preimage);
        path::write_pairs(&mut trace);
        assert!(
            !description()
                .expect("description")
                .satisfied_by(&trace, &limbs(&digests, &FIRST, value)),
            "one admitted secret must have only one part nullifier per window"
        );
    }

    // What a failure of the honest trace looks like, said by name rather than by a bare refusal:
    // every rule that does not hold and every boundary that does not bind.
    #[test]
    fn the_honest_trace_names_what_it_breaks() {
        let held = description().expect("the description stands");
        for name in [FIRST, SECOND] {
            let (trace, public, _, _) = present(&name);
            assert_eq!(broken(&held, &trace, &public), (Vec::new(), Vec::new()));
        }
    }

    #[test]
    fn a_presence_is_proven_and_verified_end_to_end() {
        let (secret, siblings, position) = a_machine();
        let (trace, digests, value) = trace_of(&secret, &siblings, position, AT, &FIRST, &key())
            .expect("the presence of a machine of the tree");
        let public = public_of(&digests, AT, &FIRST, value);
        let held = description().expect("the description stands");
        assert!(
            held.satisfied_by(&trace, &crate::poseidon::limbs_of(&public)),
            "an honest presence satisfies its own description"
        );
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true presence proves");
        assert_eq!(bytes.len(), mt_state::PRESENCE_PROOF_LEN);
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));

        // A moved public is refused: the nullifier of the part, the name attested and the value
        // of the line, one bit over each.
        for at in [64, 4 * usize::from(NAME), 4 * usize::from(LINE_VALUE)] {
            let mut moved = public.clone();
            moved[at] ^= 1;
            assert!(crate::scheme::verify(&held, &moved, &bytes).is_err(), "byte {at}");
        }

        // Re-signing the same part at another height cannot re-use its proof.
        let later = public_of(&digests, AT + 1, &FIRST, value);
        assert!(!held.satisfied_by(&trace, &crate::poseidon::limbs_of(&later)));
        assert!(crate::scheme::verify(&held, &later, &bytes).is_err());
    }

    // What the circuit publishes is what the tree and the line compute outside it: the same root,
    // the same nullifier of the part, the same digest of the key and the same point of the line. A
    // circuit answering other values would prove a statement about nothing the network reads.
    #[test]
    fn what_the_presence_publishes_is_what_the_tree_computes_outside_it() {
        let (secret, siblings, position) = a_machine();
        let (_, _, digests, value) = present(&FIRST);
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
            crate::poseidon::hash_bytes(domain::MT_PART_KEY_DIGEST, &key()),
            "the digest of the one-time key"
        );
        let spending = spending_of(&secret);
        let slope = line::slope(&spending, AT, line::slot(0, false)).expect("a slope");
        assert_eq!(
            value,
            line::line_at(
                line::opening(&spending),
                slope,
                line::abscissa(&FIRST).expect("an abscissa")
            ),
            "the line of the open slot of attempt zero at the name attested"
        );
    }

    // Two heavy attestations of one part naming two names carry two points of one line, and that
    // pair gives the lock-opening value (record 309). The closing pledge of attempt zero stands on
    // another slot, so its point is of another line, and the presence and the pledge publish one
    // nullifier of the part.
    #[test]
    fn two_presences_naming_two_names_give_the_lock_opening_value() {
        let spending = spending_of(&a_machine().0);
        let (_, _, digests, one) = present(&FIRST);
        let (_, _, _, two) = present(&SECOND);
        let (x1, x2) = (
            line::abscissa(&FIRST).expect("an abscissa"),
            line::abscissa(&SECOND).expect("an abscissa"),
        );
        assert_eq!(
            line::opening_of((x1, one), (x2, two)),
            Some(line::opening(&spending))
        );
        let (_, nullifier, closing) =
            pledge::trace_of(&a_machine().0, AT, 0, &FIRST, 0).expect("the closing pledge");
        assert_eq!(nullifier, digests[1], "the nullifier of the part");
        assert_ne!(closing, one, "the closing slot of attempt zero is another line");
    }

    // The name of one presence published with the value of another: the boundaries of the name.
    #[test]
    fn a_name_cannot_carry_the_value_of_another() {
        let held = description().expect("the description stands");
        let (trace, _, digests, value) = present(&FIRST);
        let (rules, boundaries) = broken(&held, &trace, &limbs(&digests, &SECOND, value));
        assert!(rules.is_empty());
        assert_eq!(boundaries.len(), 8);
        for at in boundaries {
            let named = match held.boundaries[at].value {
                BoundaryValue::Public(limb) => (NAME..NAME + 8).contains(&limb),
                _ => false,
            };
            assert!(named, "boundary {at}");
        }
    }

    // The line of the closing slot of attempt zero, every rule it can keep kept: only the literal of
    // the slot refuses it, so a presence asserts the open slot and no other.
    #[test]
    fn a_presence_cannot_take_the_closing_slot_of_attempt_zero() {
        let held = description().expect("the description stands");
        let (mut trace, _, digests, _) = present(&FIRST);
        let slot = line::slot(0, true);
        let value = reslope(
            &mut trace,
            &slope_elements(&spending_of(&a_machine().0), slot),
            &FIRST,
        );
        let (rules, boundaries) = broken(&held, &trace, &limbs(&digests, &FIRST, value));
        assert!(rules.is_empty());
        assert_eq!(boundaries.len(), 1);
        let literal = &held.boundaries[boundaries[0]];
        assert_eq!(literal.column as usize, ring_column(CAPACITY + 1));
        assert_eq!(literal.row as usize, Places.slope() * permutation::period());
        assert_eq!(literal.value, BoundaryValue::Literal(line::slot(0, false)));
    }

    // A value off the line, published and held: only the rules of the line fail.
    #[test]
    fn a_value_off_the_line_is_refused() {
        let held = description().expect("the description stands");
        let (mut trace, _, digests, _) = present(&FIRST);
        let (_, _, _, other) = present(&SECOND);
        fill(&mut trace, columns().1.value(0), other);
        let (rules, boundaries) = broken(&held, &trace, &limbs(&digests, &FIRST, other));
        assert!(!rules.is_empty());
        let lines = held.constraints.len() - CAPACITY..held.constraints.len();
        for rule in &rules {
            assert!(lines.contains(rule), "rule {rule}");
        }
        assert!(boundaries.is_empty());
    }

    // A slope drawn from another half: with the lane wired to the nullifier and the opening only,
    // the forgery stands; wired to the slope as well, the lane refuses it.
    #[test]
    fn the_lane_reaches_every_derivation_of_the_half() {
        let held = description().expect("the description stands");
        let (mut trace, _, digests, _) = present(&FIRST);
        let stranger = spending_of(&[0xB7; 32]);
        let value = reslope(
            &mut trace,
            &slope_elements(&stranger, line::slot(0, false)),
            &FIRST,
        );
        let public = limbs(&digests, &FIRST, value);
        let mutant = assembled(&Places.lane_wires()[..2]).expect("the mutant stands");
        assert_eq!(broken(&mutant, &trace, &public), (Vec::new(), Vec::new()));
        let (rules, boundaries) = broken(&held, &trace, &public);
        assert!(!rules.is_empty());
        assert!(boundaries.is_empty());
    }

    #[test]
    fn the_description_stands_under_the_one_bound() {
        let held = description().expect("the description stands");
        assert!(held.check().is_ok());
        assert!(usize::from(held.trace_width) <= crate::params::TRACE_WIDTH_BOUND);
        assert_eq!(usize::from(held.trace_width), columns().1.width());
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
        assert_eq!(Description::decode(&held.encode()).ok(), Some(held.clone()));
        let of_the_pledge = pledge::description().expect("the pledge stands");
        assert_ne!(held.identifier(), of_the_pledge.identifier());
    }
}
