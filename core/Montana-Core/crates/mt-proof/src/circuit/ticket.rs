// The circuit of a ticket: a runner proves that the ticket drawn from its secret and the cemented
// aggregate of the window two before clears the threshold of the draw, that its naming half stands
// in the tree of the electorate, and that the key its proposal answers under is the one this proof
// names — disclosing neither the ticket, nor the secret, nor the machine.
//
// **The shape.** Four chains laid one after another, as the presence lays them: the halves of the
// secret — one absorption squeezed twice; the leaf and the walk of the tree of the electorate under
// the naming half; the ticket over the spending half and the eight limbs of the aggregate; and the
// absorption of the runner's key, whose squeeze is the digest the public input carries. After the
// chains stands the comparison: thirty-two rows, one per byte of the ticket in the order of their
// significance, where the threshold less one less the ticket is written byte by byte with its
// borrows and every byte is held in range — so the whole of "the ticket clears" is one subtraction
// that does not go below nought.
//
// **Why the comparison is written in bytes.** The draw compares thirty-two bytes read big-endian,
// where the bytes are the four words of the digest each written little-endian: the most significant
// byte of the comparison is the least significant byte of the first word. A comparison written in
// words would have to reverse the bytes of each, which is the same decomposition under another name;
// so the circuit decomposes each word into its eight bytes, holds the decomposition canonical — a
// word written as bytes above the modulus is another word — and compares bytes.

use super::compare::{self, Compared, BYTES_OF_A_WORD, COMPARED_BYTES};
use super::permutation::ring_column;
use super::presence::{KEY_LIMBS, PRESENCE_ROWS_LOG2};
use super::{capacity, lane, path, permutation, sponge};
use crate::air::{Boundary, BoundaryValue, Description};
use crate::field::F;
use crate::poseidon::{CAPACITY, RATE};
use mt_codec::domain;

// The limbs of the aggregate the ticket absorbs beside the spending half: a hash in words of four.
fn aggregate_limbs() -> usize {
    crate::poseidon::limbs_of(&[0u8; 32]).len()
}

// How the blocks of a ticket stand. Block zero is idle so every chain has a seam before it.
#[derive(Clone, Copy, Debug)]
pub struct Places;

impl Places {
    pub fn halves(&self) -> usize {
        1
    }

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

    pub fn ticket(&self) -> usize {
        self.admitted_nodes() + self.admitted_depth()
    }

    pub fn ticket_blocks(&self) -> usize {
        sponge::blocks_of(CAPACITY + aggregate_limbs())
    }

    pub fn key(&self) -> usize {
        self.ticket() + self.ticket_blocks()
    }

    pub fn key_blocks(&self) -> usize {
        sponge::blocks_of(KEY_LIMBS)
    }

    pub fn blocks(&self) -> usize {
        self.key() + self.key_blocks()
    }

    // The first row of the comparison: the row after the last block.
    pub fn compared(&self) -> usize {
        self.blocks() * permutation::period()
    }

    // The row after the comparison, where the borrow out of the most significant byte stands.
    pub fn after(&self) -> usize {
        compare::after_of(self.compared())
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    pub fn carry_rows(&self) -> Vec<usize> {
        let mut out = sponge::carry_rows(self.halves(), self.halves_blocks());
        out.extend(sponge::carry_rows(self.ticket(), self.ticket_blocks()));
        out.extend(sponge::carry_rows(self.key(), self.key_blocks()));
        out
    }

    pub fn squeeze_rows(&self) -> Vec<usize> {
        sponge::squeeze_rows(self.halves(), self.halves_blocks() - 1)
    }

    pub fn admitted_levels(&self) -> Vec<usize> {
        path::level_rows(self.admitted_nodes(), self.admitted_depth())
    }

    // The row of the comparison a byte of the digest stands at: the words from the last to the
    // first, and within a word the bytes from the last to the first, so that significance rises with
    // the row and a borrow walks one row on.
    pub fn row_of(&self, word: usize, byte: usize) -> usize {
        compare::row_of(self.compared(), word, byte)
    }

    // The limb of the public input a byte of the threshold stands in: the bytes follow the two
    // digests and the aggregate, one limb each, in the order of the rows of the comparison.
    fn threshold_limb(&self, at: usize) -> u16 {
        (2 * 2 * CAPACITY + aggregate_limbs() + at) as u16
    }

    // The public input: the root of the electorate, the digest of the runner's key, the aggregate
    // and the threshold, in that order. The two digests are bound as words of the hash state at
    // the seams their chains end at; the limbs of the aggregate are bound where the ticket's chain
    // absorbs them; the bytes of the threshold are bound at the rows of the comparison, one limb
    // each.
    pub fn boundaries(&self, compared: &Compared) -> Vec<Boundary> {
        let ends = [
            (self.seam_before(self.ticket()), 0),
            (self.blocks() * permutation::period() - 1, 1),
        ];
        let mut out = Vec::new();
        for (row, which) in ends {
            for cell in 0..CAPACITY {
                out.push(Boundary {
                    column: ring_column(cell) as u16,
                    row: row as u64,
                    value: BoundaryValue::Word((2 * (which * CAPACITY + cell)) as u16),
                });
            }
        }
        // The limbs of the aggregate enter the ticket's chain after the four cells of the spending
        // half the lane wires in: the first fill the rest of the first block's rate, the next open
        // the second block. The aggregate stands third among the digests of the public input.
        let first_block = self.ticket() * permutation::period();
        let second_block = (self.ticket() + 1) * permutation::period();
        for limb in 0..aggregate_limbs() {
            let (row, cell) = if limb < RATE - CAPACITY {
                (first_block, CAPACITY + limb)
            } else {
                (second_block, limb - (RATE - CAPACITY))
            };
            out.push(Boundary {
                column: ring_column(cell) as u16,
                row: row as u64,
                value: BoundaryValue::Public((2 * 2 * CAPACITY + limb) as u16),
            });
        }
        out.extend(compare::threshold_boundaries(
            compared,
            self.compared(),
            |at| self.threshold_limb(at),
        ));
        // The borrow into the least significant byte is one — the subtraction is of the threshold
        // less one — and the borrow out of the most significant byte is nought, which is the whole
        // of what makes the difference non-negative.
        out.push(compare::borrow_in(compared, self.compared()));
        out.push(Boundary {
            column: compared.borrow() as u16,
            row: self.after() as u64,
            value: BoundaryValue::Literal(0),
        });
        out.extend(compare::accumulators_open(compared, self.compared()));
        for (first, elements) in [
            (self.halves(), crate::poseidon::limbs_of(&[0u8; 32]).len()),
            (self.admitted_leaf(), CAPACITY),
            (self.ticket(), CAPACITY + aggregate_limbs()),
            (self.key(), KEY_LIMBS),
        ] {
            out.extend(sponge::padding_boundaries(first, elements));
        }
        out
    }

    // The lane of the spending half: picked up at the seam of the first squeeze and handed to the
    // ticket's absorption. The lane of the digest: picked up at the seam the ticket's chain ends at
    // and read by the comparison, so it is never wired into a block.
    pub fn spending_loads(&self) -> Vec<usize> {
        vec![self.seam_before(self.halves() + self.halves_blocks() - 1)]
    }

    pub fn spending_wires(&self) -> Vec<usize> {
        vec![self.seam_before(self.ticket())]
    }

    pub fn digest_loads(&self) -> Vec<usize> {
        vec![self.seam_before(self.key())]
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
        out.push((self.seam_before(self.ticket()), domain::MT_TICKET));
        out.push((self.seam_before(self.key()), domain::MT_RUNNER_KEY_DIGEST));
        out
    }
}

// The assembled shape: the permutation base at the ticket's height — the presence's — the carries,
// the walk, the capacity wiring, the two lanes and the comparison.
pub fn description() -> Option<Description> {
    let places = Places;
    let rows_log2 = PRESENCE_ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let spending = lane::Places::after(path::TRACE_WIDTH);
    let digest = lane::Places::after(spending.width());
    let compared = Compared::after(digest.width());
    let width = compared.width();
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let squeeze = base + 1;
    let naming = base + 2;
    let walk = base + 3;
    let opens_at = walk + path::PERIODIC_COUNT;
    let spending_at = opens_at + capacity::PERIODIC_COUNT;
    let digest_at = spending_at + lane::PERIODIC_COUNT;
    let compared_at = digest_at + lane::PERIODIC_COUNT;

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
        &places.spending_loads(),
        &places.spending_wires(),
    ));
    held.periodic.extend(lane::periodic_columns(
        rows_log2,
        &places.digest_loads(),
        &[],
    ));
    held.periodic
        .extend(compare::periodic_columns(rows_log2, &[places.compared()]));

    held.constraints.extend(sponge::capacity_carries(carry));
    held.constraints.extend(sponge::rate_carries(squeeze));
    held.constraints.extend(sponge::digest_carries(naming));
    held.constraints.extend(path::constraints(walk));
    held.constraints.extend(capacity::constraints(opens_at));
    held.constraints
        .extend(lane::constraints(spending_at, &spending));
    held.constraints
        .extend(lane::constraints(digest_at, &digest));
    held.constraints
        .extend(compare::constraints(compared_at, &compared, &digest));
    held.boundaries.extend(places.boundaries(&compared));
    Some(held)
}

// The trace of a ticket: the halves of the secret, the walk of the tree of the electorate, the
// ticket over the spending half and the aggregate, the absorption of the runner's key, and the
// comparison of the ticket against the threshold. It answers with nothing where the ticket does not
// clear: a trace of a false statement is not written.
pub fn trace_of(
    machine_secret: &[u8; 32],
    admitted_siblings: &[crate::poseidon::Digest],
    admitted_position: u64,
    aggregate: &[u8; 32],
    threshold: &[u8; 32],
    runner_key: &[u8],
) -> Option<(Vec<Vec<F>>, [crate::poseidon::Digest; 2])> {
    use crate::poseidon::{self, CAPACITY as CAP, WIDTH};
    let places = Places;
    let rows = 1usize << PRESENCE_ROWS_LOG2;
    let spending_lane = lane::Places::after(path::TRACE_WIDTH);
    let digest_lane = lane::Places::after(spending_lane.width());
    let compared = Compared::after(digest_lane.width());
    let width = compared.width();
    let mut columns = vec![vec![F::ZERO; rows]; width];

    // The halves: one absorption of the secret, squeezed twice.
    let secret_limbs = poseidon::limbs_of(machine_secret);
    let states = sponge::chain_twice(domain::MT_KEY_HALVES, &secret_limbs);
    for (at, state) in states.iter().enumerate() {
        permutation::write_block(&mut columns, places.halves() + at, state)?;
    }
    let (spending, naming) = poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &secret_limbs);

    // The branch of the electorate, through the walk writer as it stands.
    let admitted_root = path::write_walk_under(
        &mut columns,
        places.admitted_leaf(),
        &naming,
        admitted_siblings,
        admitted_position,
        domain::MT_ADMITTED_LEAF,
        domain::MT_ADMITTED_NODE,
    )?;

    // The ticket: the half that spends out of the lane, and the limbs of the aggregate.
    let mut preimage = Vec::with_capacity(CAP + aggregate_limbs());
    preimage.extend_from_slice(spending.elements());
    preimage.extend(poseidon::limbs_of(aggregate));
    let ticket_states = sponge::chain(domain::MT_TICKET, &preimage);
    for (at, state) in ticket_states.iter().enumerate() {
        permutation::write_block(&mut columns, places.ticket() + at, state)?;
    }
    let ticket = poseidon::hash_elements(domain::MT_TICKET, &preimage);

    // The absorption of the runner's key, whose squeeze is the digest the public input carries.
    let key_limbs = poseidon::limbs_of(runner_key);
    if key_limbs.len() != KEY_LIMBS {
        return None;
    }
    let key_states = sponge::chain(domain::MT_RUNNER_KEY_DIGEST, &key_limbs);
    for (at, state) in key_states.iter().enumerate() {
        permutation::write_block(&mut columns, places.key() + at, state)?;
    }
    let runner_digest = poseidon::hash_elements(domain::MT_RUNNER_KEY_DIGEST, &key_limbs);

    // The lanes: a cyclic hold with one load is a constant — the spending half along the whole
    // trace, and the ticket along the whole trace. Both are loaded where the rule loads them and
    // hold everywhere, which is what a constant column is.
    for cell in 0..CAP {
        let value = spending.elements()[cell];
        for slot in columns[spending_lane.cell(cell)][..rows].iter_mut() {
            *slot = value;
        }
        let value = ticket.elements()[cell];
        for slot in columns[digest_lane.cell(cell)][..rows].iter_mut() {
            *slot = value;
        }
    }

    // The comparison: the threshold less one less the ticket, byte by byte from the least
    // significant, every difference held in range, and the borrow out of the last nought. A ticket
    // at or above the threshold has no such difference, and the trace is not written.
    if compare::write(
        &mut columns,
        &compared,
        places.compared(),
        &ticket.bytes(),
        threshold,
    ) != 0
    {
        return None;
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
    Some((columns, [admitted_root, runner_digest]))
}

// The public input in the order Canon states: the root of the electorate, the digest of the
// runner's key, the aggregate, and the threshold as thirty-two limbs of one byte each in the order
// of the rows of the comparison.
pub fn public_of(
    digests: &[crate::poseidon::Digest; 2],
    aggregate: &[u8; 32],
    threshold: &[u8; 32],
) -> Vec<u8> {
    let places = Places;
    let mut out = Vec::with_capacity(3 * 32 + COMPARED_BYTES * 4);
    for digest in digests {
        out.extend_from_slice(&digest.bytes());
    }
    out.extend_from_slice(aggregate);
    for at in 0..COMPARED_BYTES {
        let word = CAPACITY - 1 - at / BYTES_OF_A_WORD;
        let byte = BYTES_OF_A_WORD - 1 - at % BYTES_OF_A_WORD;
        debug_assert_eq!(places.row_of(word, byte), places.compared() + at);
        out.extend_from_slice(&u32::from(threshold[word * BYTES_OF_A_WORD + byte]).to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::poseidon;

    // A machine of the tree of the electorate: its secret, the branch its naming half stands on,
    // and the position of that leaf. The siblings are the empties of the construction, which is the
    // branch of a tree holding one machine — the smallest true walk there is.
    fn a_machine() -> ([u8; 32], Vec<poseidon::Digest>, u64) {
        let secret = [0x5Au8; 32];
        let depth = crate::tree_depth();
        let empties = crate::admitted::empty_internals(depth);
        (secret, empties[..depth].to_vec(), 0)
    }

    fn a_key() -> Vec<u8> {
        vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY]
    }

    // The ticket of a machine, computed outside the circuit as the derivation computes it: the
    // spending half as four cells and the aggregate as eight limbs under the ticket domain.
    fn ticket_of(secret: &[u8; 32], aggregate: &[u8; 32]) -> poseidon::Digest {
        let (spending, _) =
            poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &poseidon::limbs_of(secret));
        let mut preimage = spending.elements().to_vec();
        preimage.extend(poseidon::limbs_of(aggregate));
        poseidon::hash_elements(domain::MT_TICKET, &preimage)
    }

    // A threshold one above a value, compared as the draw compares: unsigned and big-endian over
    // the thirty-two bytes.
    fn one_above(value: &[u8; 32]) -> [u8; 32] {
        let mut out = *value;
        for byte in out.iter_mut().rev() {
            let (sum, carried) = byte.overflowing_add(1);
            *byte = sum;
            if !carried {
                break;
            }
        }
        out
    }

    #[test]
    fn the_blocks_and_the_comparison_of_the_ticket_fit_its_height() {
        let places = Places;
        assert_eq!(places.admitted_depth(), 40);
        assert_eq!(places.key_blocks(), 62);
        assert_eq!(places.ticket_blocks(), 2);
        // The comparison stands after the last block and before the free block: every row the
        // rules speak at and every boundary names is a live row.
        let live = (1usize << PRESENCE_ROWS_LOG2) - crate::params::FREE_ROWS;
        assert!(
            places.after() < live - 1,
            "the comparison reaches into the free block"
        );
        let held = description().expect("the description stands");
        assert!(usize::from(held.trace_width) <= crate::params::TRACE_WIDTH_BOUND);
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
        // The same height as the presence, so the proof is of the presence's length.
        assert_eq!(held.rows_log2, PRESENCE_ROWS_LOG2);
    }

    // What a failure of the honest trace looks like, said by name rather than by a bare refusal.
    #[test]
    fn the_honest_trace_names_what_it_breaks() {
        let (secret, siblings, position) = a_machine();
        let aggregate = [0x33u8; 32];
        let threshold = [0xFFu8; 32];
        let (trace, digests) = trace_of(
            &secret,
            &siblings,
            position,
            &aggregate,
            &threshold,
            &a_key(),
        )
        .expect("a ticket below a threshold of everything clears");
        let public = poseidon::limbs_of(&public_of(&digests, &aggregate, &threshold));
        let held = description().expect("the description stands");
        let mut broken: Vec<String> = Vec::new();
        for at in 0..held.constraints.len() {
            for row in 0..held.live_rows() - 1 {
                if !held.evaluate(&trace, at, row).is_zero() {
                    // The rule by its terms, with the value every factor reads, so that a broken
                    // rule names the column and the row it disagrees with.
                    let mut terms = Vec::new();
                    for term in &held.constraints[at].terms {
                        let factors: Vec<String> = term
                            .factors
                            .iter()
                            .map(|f| {
                                let column = usize::from(f.column);
                                let here = usize::try_from(row).expect("a row of the trace")
                                    + usize::from(f.shift);
                                let value = if column < trace.len() {
                                    format!("{:?}", trace[column][here])
                                } else {
                                    let periodic = &held.periodic[column - trace.len()];
                                    format!(
                                        "periodic {}",
                                        periodic.values[here % periodic.values.len()]
                                    )
                                };
                                format!("c{}[+{}]^{}={}", f.column, f.shift, f.power, value)
                            })
                            .collect();
                        terms.push(format!("{} * {}", term.coefficient, factors.join(" * ")));
                    }
                    broken.push(format!("rule {at} at row {row}: {}", terms.join(" + ")));
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
    fn a_ticket_is_proven_and_verified_end_to_end() {
        let (secret, siblings, position) = a_machine();
        let aggregate = [0x33u8; 32];
        let threshold = [0xFFu8; 32];
        let key = a_key();
        let (trace, digests) = trace_of(&secret, &siblings, position, &aggregate, &threshold, &key)
            .expect("the ticket of a machine of the tree");
        let public = public_of(&digests, &aggregate, &threshold);
        let held = description().expect("the description stands");
        assert!(
            held.satisfied_by(&trace, &poseidon::limbs_of(&public)),
            "an honest ticket satisfies its own description"
        );
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true ticket proves");
        assert_eq!(
            bytes.len(),
            crate::params::Shape::of_rows_log2(u32::from(PRESENCE_ROWS_LOG2))
                .expect("the height stands")
                .proof_bytes()
        );
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));

        // Another key is another digest, and the proof does not move onto it.
        let mut other_key = key.clone();
        other_key[0] ^= 1;
        let other_digest = poseidon::hash_bytes(domain::MT_RUNNER_KEY_DIGEST, &other_key);
        let lifted = public_of(&[digests[0], other_digest], &aggregate, &threshold);
        assert!(crate::scheme::verify(&held, &lifted, &bytes).is_err());

        // Another aggregate is another ticket, and the proof says nothing of it.
        let moved = public_of(&digests, &[0x34u8; 32], &threshold);
        assert!(crate::scheme::verify(&held, &moved, &bytes).is_err());

        // A threshold below the ticket is a statement this proof never made.
        let ticket = ticket_of(&secret, &aggregate).bytes();
        let below = public_of(&digests, &aggregate, &ticket);
        assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&below)));
        assert!(crate::scheme::verify(&held, &below, &bytes).is_err());
    }

    // The comparison is strict and reads the bytes big-endian: a threshold at the ticket itself
    // writes no trace, a threshold one above it does, and so the circuit says exactly what the
    // door of the draw says — a value clears when it falls below.
    #[test]
    fn a_ticket_clears_a_threshold_one_above_it_and_never_the_threshold_itself() {
        let (secret, siblings, position) = a_machine();
        let aggregate = [0x33u8; 32];
        let ticket = ticket_of(&secret, &aggregate).bytes();
        assert!(trace_of(&secret, &siblings, position, &aggregate, &ticket, &a_key()).is_none());
        let above = one_above(&ticket);
        let (trace, digests) = trace_of(&secret, &siblings, position, &aggregate, &above, &a_key())
            .expect("a ticket one below the threshold clears");
        let public = public_of(&digests, &aggregate, &above);
        let held = description().expect("the description stands");
        assert!(held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
        // And the named wrong implementation: a comparison reading the bytes the other way round
        // would let a threshold whose reversed value stands above the reversed ticket clear.
        let mut reversed = ticket;
        reversed.reverse();
        let threshold_reversed = one_above(&reversed);
        if threshold_reversed <= ticket {
            assert!(trace_of(
                &secret,
                &siblings,
                position,
                &aggregate,
                &threshold_reversed,
                &a_key()
            )
            .is_none());
        }
    }

    // What the circuit publishes is what the tree computes outside it: the root of the electorate
    // and the digest of the runner's key under its own domain.
    #[test]
    fn what_the_ticket_publishes_is_what_the_tree_computes_outside_it() {
        let (secret, siblings, position) = a_machine();
        let key = a_key();
        let (_, digests) = trace_of(
            &secret,
            &siblings,
            position,
            &[0x33u8; 32],
            &[0xFFu8; 32],
            &key,
        )
        .expect("the ticket stands");
        let naming = poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, &secret).1;
        let mut current = crate::admitted::leaf_of(&naming);
        for (level, sibling) in siblings.iter().enumerate() {
            let bit = (position >> level) & 1 == 1;
            let (left, right) = if bit {
                (*sibling, current)
            } else {
                (current, *sibling)
            };
            current = crate::admitted::node(&left, &right);
        }
        assert_eq!(digests[0], current, "the root of the electorate");
        assert_eq!(
            digests[1],
            poseidon::hash_bytes(domain::MT_RUNNER_KEY_DIGEST, &key),
            "the digest of the runner's key"
        );
        assert_ne!(
            digests[1],
            poseidon::hash_bytes(domain::MT_PART_KEY_DIGEST, &key),
            "the digest of a runner's key is not the digest of a part key"
        );
    }

    // A stranger cannot graft an admitted machine's branch onto its own ticket: the naming half the
    // walk opens under is the second squeeze of the same absorption the ticket's spending half is
    // the first squeeze of.
    #[test]
    fn a_ticket_cannot_graft_another_machines_membership() {
        let (admitted_secret, siblings, position) = a_machine();
        let stranger = [0xB7u8; 32];
        let aggregate = [0x33u8; 32];
        let threshold = [0xFFu8; 32];
        let (mut trace, mut digests) = trace_of(
            &stranger,
            &siblings,
            position,
            &aggregate,
            &threshold,
            &a_key(),
        )
        .expect("a stranger computes its own trace");
        let (_, public_naming_half) = poseidon::hash_elements_twice(
            domain::MT_KEY_HALVES,
            &poseidon::limbs_of(&admitted_secret),
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
            !description().expect("description").satisfied_by(
                &trace,
                &poseidon::limbs_of(&public_of(&digests, &aggregate, &threshold)),
            ),
            "membership must belong to the secret that draws the ticket"
        );
    }
}
