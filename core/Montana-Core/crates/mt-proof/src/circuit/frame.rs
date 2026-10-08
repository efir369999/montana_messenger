// The circuit of a frame: three spends, each consuming two notes and creating two, each bounded by
// a nullifier of its rate. Nothing of the arithmetic stands here — the layers below hold it — and
// what this adds is where the blocks stand, which is the whole of the wiring.
//
// **One table of places, read by both sides.** The description and the trace take every block
// number from the same table, so a block that moved would move in both at once and there is no
// second place for a layout to drift in.
//
// **What stands outside.** The nullifiers a frame spends, the commitments it creates and the
// nullifiers of its rates — the bytes of the frame itself — and beside them two values no field of
// a frame carries: the canonical root the redemptions prove against and the window the rates belong
// to. A verifier computes both from the state it already holds, so a frame publishes neither.

use super::moment;
use super::path;
use super::permutation::{self, period};
use super::redemption::{self, Held, HeldRight};
use super::sponge;
use super::value;
use crate::air::{Boundary, BoundaryValue, Description};
use crate::field::F;
use crate::poseidon::{self, Digest, CAPACITY, RATE, WIDTH};
use mt_codec::domain;

mt_codec::constants! {
    FRAME:
    /// The height of a frame's trace.
    pub const ROWS_LOG2: usize = 14, code "the height of a frame's circuit: what its blocks fill, one power of two";
    /// The splits of this layout, one per seam where the two branches of a redemption part, and
    /// where each of them stands among them. A seam whose rule differs takes a split of its own,
    /// since a half is nonzero wherever its schedule is.
    pub const SPLIT_ROOT: usize = 0, code "the split of this layout at the row a walk ends on: which root it answers against";
    pub const SPLIT_CAPACITY: usize = 1, code "the split of this layout at the seams where a chain opens: under which domains";
    pub const SPLIT_LEAF: usize = 2, code "the split of this layout at the seam of a leaf's input: wired from the block beside it, or taken from the lane";
    pub const SPLIT_NF_FIRST: usize = 3, code "the split of this layout at the seam of the nullifier chain's first block: which slots of the lane it absorbs";
    pub const SPLIT_NF_SECOND: usize = 4, code "the split of this layout at the seam of its second block: a position absorbed, or a squeeze crossing";
    pub const SPLIT_MOMENT: usize = 5, code "the split of this layout at the row a nullifier chain ends on: where the moment's equations stand";
    pub const SPLITS: usize = 6, code "the count of the splits this layout adds";
    /// Where the index of a rate stands among the cells of the block that absorbs it, and the
    /// bits it is held below. Both are places of this layout: the first follows from the preimage
    /// of a rate nullifier, the second from the bound the Decree names.
    const INDEX_CELL: usize = 2, code "the cell of a block the index of a rate stands at, which follows from its preimage";
    pub const INDEX_TIE: usize = 0, code "the periodic column of this layout marking where the index of a rate is read";
    pub const PERIODIC_COUNT: usize = 1, code "the count of the periodic columns this layout adds";
}

// What a spend creates: a note for somebody, bound to the half of their nullifier key.
#[derive(Clone, Debug)]
pub struct Created {
    pub half: [u8; 32],
    pub value: u128,
    pub note_pk: [u8; 32],
    pub rcm: [u8; 32],
}

// What bounds the payments of one person in one window.
#[derive(Clone, Debug)]
pub struct Rate {
    pub secret: [u8; 32],
    pub index: u8,
}

// What one redemption position consumes: a note, or a right to a window's share. The two are one
// kind — the positions are typeless, and nothing of a frame says which branch filled one.
// What one redemption position consumes: a note, a right to a window's share, or filler. The three
// are one kind — the positions are typeless, and nothing of a frame says which branch filled one.
//
// **Filler is drawn and asserts nothing.** A spend carrying no transfer holds it in every position,
// and a spend that redeems less than its positions allow holds it in the rest; its values come of
// its emitter's own randomness and of no public formula, and under its half neither branch's rules
// fire. It carries no value into the balance, so calling a real note filler forfeits that note —
// which is why nothing has to guard the choice. It is what lets a machine holding one right and
// nothing else build a frame, and what lets a runner make up a window's shortfall with frames it
// cannot read.
#[derive(Clone, Debug)]
pub enum Consumed {
    Note(Held),
    Right(HeldRight),
    Filler(Held),
}

impl Consumed {
    pub fn value(&self) -> u128 {
        match self {
            Consumed::Note(held) => held.value,
            Consumed::Right(held) => held.value,
            // Filler carries nothing into the balance whatever its drawn values say.
            Consumed::Filler(_) => 0,
        }
    }

    // The filler of one position, drawn from a value the emitter holds and an index within the
    // frame. Two positions of one frame therefore differ, and two frames of one emitter differ,
    // without either being a public function of anything.
    pub fn filler(drawn: &[u8; 32], at: usize, depth: usize) -> Self {
        let of = |what: u8| {
            poseidon::hash_bytes(
                domain::MT_NOTE_KEY,
                &[drawn.as_slice(), &(at as u64).to_le_bytes(), &[what]].concat(),
            )
            .bytes()
        };
        Consumed::Filler(Held {
            nf_key: of(0),
            value: 0,
            note_pk: of(1),
            rcm: of(2),
            siblings: (0..depth)
                .map(|level| {
                    poseidon::hash_bytes(
                        domain::MT_NOTE_NODE,
                        &[drawn.as_slice(), &(level as u64).to_le_bytes()].concat(),
                    )
                })
                .collect(),
            position: 0,
        })
    }
}

#[derive(Clone, Debug)]
pub struct Spend {
    pub consumed: Vec<Consumed>,
    pub created: Vec<Created>,
    pub rate: Rate,
}

#[derive(Clone, Debug)]
pub struct Frame {
    pub spends: Vec<Spend>,
    pub window: u64,
}

// The elements of an output commitment and of a rate nullifier, taken the way the derivations of a
// note and of a rate take them.
fn created_elements(created: &Created) -> Option<Vec<F>> {
    let half = poseidon::Digest::of_bytes(&created.half)?;
    let mut out = Vec::new();
    out.extend_from_slice(half.elements());
    out.extend_from_slice(&poseidon::limbs_of(&created.value.to_le_bytes()));
    out.extend_from_slice(&poseidon::limbs_of(&created.note_pk));
    out.extend_from_slice(&poseidon::limbs_of(&created.rcm));
    Some(out)
}

fn rate_elements(rate: &Rate, window: u64) -> Vec<F> {
    let mut out = Vec::new();
    out.extend_from_slice(&poseidon::limbs_of(&rate.secret));
    out.extend_from_slice(&poseidon::limbs_of(&window.to_le_bytes()));
    out.extend_from_slice(&poseidon::limbs_of(&[rate.index]));
    out
}

fn created_element_count() -> usize {
    CAPACITY + 4 + 2 * CAPACITY + 2 * CAPACITY
}

fn rate_element_count() -> usize {
    2 * CAPACITY + 2 + 1
}

// Where every block of a frame stands. One table, read by the description and by the trace alike.
#[derive(Clone, Debug)]
pub struct Places {
    pub depth: usize,
    pub spends: usize,
    pub consumed: usize,
    pub created: usize,
    // The bits the index of a rate is held below, which is the bits of the bound the Decree names:
    // a number decomposed into more bits than its bound has is a bound that bounds nothing.
    pub index_bits: usize,
}

impl Places {
    pub fn of(depth: usize) -> Option<Self> {
        let per_window = mt_genesis::scalar("spends_per_window")?;
        let mut index_bits = 0usize;
        while (1u64 << index_bits) < per_window {
            index_bits += 1;
        }
        Some(Self {
            depth,
            spends: mt_genesis::scalar("spends_per_frame")? as usize,
            consumed: mt_genesis::scalar("spend_inputs")? as usize,
            created: mt_genesis::scalar("spend_outputs")? as usize,
            index_bits,
        })
    }

    pub fn redemption_blocks(&self) -> usize {
        redemption::Places::of(0, self.depth).blocks()
    }

    pub fn created_blocks(&self) -> usize {
        sponge::blocks_of(created_element_count())
    }

    pub fn rate_blocks(&self) -> usize {
        sponge::blocks_of(rate_element_count())
    }

    pub fn spend_blocks(&self) -> usize {
        self.consumed * self.redemption_blocks()
            + self.created * self.created_blocks()
            + self.rate_blocks()
    }

    pub fn blocks(&self) -> usize {
        self.spends * self.spend_blocks()
    }

    pub fn spend_at(&self, spend: usize) -> usize {
        spend * self.spend_blocks()
    }

    pub fn redemption_at(&self, spend: usize, at: usize) -> redemption::Places {
        redemption::Places::of(
            self.spend_at(spend) + at * self.redemption_blocks(),
            self.depth,
        )
    }

    pub fn created_at(&self, spend: usize, at: usize) -> usize {
        self.spend_at(spend) + self.consumed * self.redemption_blocks() + at * self.created_blocks()
    }

    pub fn rate_at(&self, spend: usize) -> usize {
        self.created_at(spend, self.created)
    }

    // The row a spend closes its balance at: the last row of its last block.
    pub fn close_at(&self, spend: usize) -> usize {
        (self.rate_at(spend) + self.rate_blocks()) * period() - 1
    }

    // The rows the amounts of a frame meet their limbs at, on each side of a balance.
    pub fn consumed_ties(&self) -> Vec<usize> {
        (0..self.spends)
            .flat_map(|spend| {
                (0..self.consumed)
                    .map(move |at| self.redemption_at(spend, at).commitment() * period())
            })
            .collect()
    }

    pub fn created_ties(&self) -> Vec<usize> {
        (0..self.spends)
            .flat_map(|spend| {
                (0..self.created).map(move |at| self.created_at(spend, at) * period())
            })
            .collect()
    }

    pub fn closes(&self) -> Vec<usize> {
        (0..self.spends).map(|spend| self.close_at(spend)).collect()
    }

    // The seam at which the index of a rate is read: the one before the block that absorbs it.
    pub fn index_ties(&self) -> Vec<usize> {
        (0..self.spends)
            .map(|spend| (self.rate_at(spend) + 1) * period() - 1)
            .collect()
    }

    // The seams the squeezes of the keys stand at, gathered from every redemption.
    pub fn squeeze_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .flat_map(|r| r.squeeze_rows())
            .collect()
    }

    // The seams where a chain opens under the domain of its branch, gathered from every redemption.
    pub fn capacity_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .flat_map(|r| r.capacity_rows())
            .collect()
    }

    // The seams of the leaf inputs, of the nullifier chains' two blocks, and the rows those
    // chains end on, gathered from every redemption: the schedules of the splits.
    pub fn leaf_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .flat_map(|r| r.leaf_rows())
            .collect()
    }

    pub fn read_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .flat_map(|r| r.read_rows())
            .collect()
    }

    pub fn position_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .flat_map(|r| r.position_rows())
            .collect()
    }

    // The first rows of the nullifier chains, which the moment's decompositions end before.
    pub fn nullifier_first_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .map(|r| r.nullifier() * period())
            .collect()
    }

    // The rows the nullifier chains end on: where a right's moment stands, and where the
    // accumulators of the moment are cleared for the redemption after.
    pub fn nullifier_final_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .map(|r| (r.nullifier() + r.nullifier_blocks()) * period() - 1)
            .collect()
    }

    // The rows a walk ends on, where the accumulator meets the root it answers against.
    pub fn root_rows(&self) -> Vec<usize> {
        self.each_redemption()
            .iter()
            .map(|r| (r.nodes() + r.depth) * period() - 1)
            .collect()
    }

    pub fn carry_rows(&self) -> Vec<usize> {
        let mut out = Vec::new();
        for spend in 0..self.spends {
            for at in 0..self.consumed {
                out.extend(self.redemption_at(spend, at).carry_rows());
            }
            for at in 0..self.created {
                out.extend(sponge::carry_rows(
                    self.created_at(spend, at),
                    self.created_blocks(),
                ));
            }
            out.extend(sponge::carry_rows(self.rate_at(spend), self.rate_blocks()));
        }
        out
    }

    fn each_redemption(&self) -> Vec<redemption::Places> {
        (0..self.spends)
            .flat_map(|spend| (0..self.consumed).map(move |at| self.redemption_at(spend, at)))
            .collect()
    }
}

// The columns of a frame: the layers below, and the three an amount and a balance take.
pub fn amounts() -> value::Places {
    value::Places::after(redemption::TRACE_WIDTH)
}

// The columns holding the two roots a walk may answer against. They carry a root at the row a walk
// ends on, pinned by a boundary, and nothing is asked of them elsewhere: a public value reaches a
// trace only at a boundary, and a boundary stands at one row.
pub fn roots_at() -> usize {
    amounts().width()
}

pub fn halves() -> super::branch::Places {
    super::branch::Places::after(roots_at() + 2 * CAPACITY, SPLITS)
}

// The five witnesses of the moment, after the halves of the splits.
pub fn moments() -> moment::Places {
    moment::Places::after(halves().width())
}

pub fn split(at: usize) -> super::branch::Halves {
    let places = halves();
    super::branch::Halves {
        note: places.note(at),
        right: places.right(at),
    }
}

pub fn trace_width() -> usize {
    moments().width()
}

// Where the public input of a frame holds each of its values, in limbs of four bytes.
fn word(at: usize) -> u16 {
    (2 * at) as u16
}

// The public input: the bytes of the frame, then the two values no field of it carries.
// What a frame publishes of one spend: the nullifiers it consumes, the commitments it creates and
// the nullifier of its rate. These are the fields of the object that crosses the wire, and they are
// what a verifier holds — it never sees a note, a key or a blinding factor.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Published {
    pub nullifiers: Vec<[u8; 32]>,
    pub commitments: Vec<[u8; 32]>,
    pub rate_nullifier: [u8; 32],
}

// The public input of a frame, laid from what the frame publishes and the two values no field of it
// carries: the canonical root its redemptions prove against and the window its rates belong to. A
// verifier computes both from the state it already holds, so a frame publishes neither.
//
// **One order of bytes, read from both sides.** A spender lays it from the secrets it holds and a
// verifier from the object that crossed the wire; both arrive here, so there is no second place for
// the order to drift in and no way for the two to lay it differently.
pub fn public_of_published(
    spends: &[Published],
    root: &Digest,
    admitted: &Digest,
    window: u64,
) -> Vec<u8> {
    let mut out = Vec::new();
    for held in spends {
        for nullifier in &held.nullifiers {
            out.extend_from_slice(nullifier);
        }
        for commitment in &held.commitments {
            out.extend_from_slice(commitment);
        }
        out.extend_from_slice(&held.rate_nullifier);
    }
    for cell in root.elements().iter().chain(admitted.elements().iter()) {
        out.extend_from_slice(&cell.as_u64().to_le_bytes());
    }
    out.extend_from_slice(&window.to_le_bytes());
    out
}

// The nullifiers, the commitments and the rate one spend of a frame publishes, computed from what
// the spender holds. This is the door that turns secrets into the fields of the object, and the
// object is what the door above lays the public input from.
pub fn published_of(spend: &Spend, window: u64) -> Option<Published> {
    let mut nullifiers = Vec::with_capacity(spend.consumed.len());
    for consumed in &spend.consumed {
        let nullifier = match consumed {
            // A filler publishes a nullifier like every other position, drawn rather than derived:
            // a position publishing nothing would be a position an observer counts.
            Consumed::Filler(drawn) => {
                let half = mt_derive_half(&drawn.nf_key);
                let commitment = commitment_of(drawn, &half)?;
                nullifier_of(drawn, &commitment)?
            }
            Consumed::Note(note) => {
                let half = mt_derive_half(&note.nf_key);
                let commitment = commitment_of(note, &half)?;
                nullifier_of(note, &commitment)?
            }
            Consumed::Right(right) => {
                let spending =
                    poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, &right.machine_secret).0;
                let mut elements = Vec::new();
                elements.extend_from_slice(spending.elements());
                elements.push(F::try_from_u64(right.window)?);
                poseidon::hash_elements_twice(domain::MT_CREDIT_NF, &elements).0
            }
        };
        nullifiers.push(nullifier.bytes());
    }
    let commitments = spend
        .created
        .iter()
        .map(|created| {
            Some(poseidon::hash_elements(domain::MT_NOTE_CM, &created_elements(created)?).bytes())
        })
        .collect::<Option<Vec<[u8; 32]>>>()?;
    let rate = poseidon::hash_elements(domain::MT_RATE_NF, &rate_elements(&spend.rate, window));
    Some(Published {
        nullifiers,
        commitments,
        rate_nullifier: rate.bytes(),
    })
}

pub fn public_of(
    frame: &Frame,
    places: &Places,
    root: &Digest,
    admitted: &Digest,
) -> Option<Vec<u8>> {
    let _ = places;
    let published = frame
        .spends
        .iter()
        .map(|spend| published_of(spend, frame.window))
        .collect::<Option<Vec<_>>>()?;
    Some(public_of_published(
        &published,
        root,
        admitted,
        frame.window,
    ))
}

// The half a commitment names: the second of the two the key's sponge yields.
fn mt_derive_half(nf_key: &[u8; 32]) -> Digest {
    poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, nf_key).1
}

fn commitment_of(held: &Held, half: &Digest) -> Option<Digest> {
    let mut elements = Vec::new();
    elements.extend_from_slice(half.elements());
    elements.extend_from_slice(&poseidon::limbs_of(&held.value.to_le_bytes()));
    elements.extend_from_slice(&poseidon::limbs_of(&held.note_pk));
    elements.extend_from_slice(&poseidon::limbs_of(&held.rcm));
    Some(poseidon::hash_elements(domain::MT_NOTE_CM, &elements))
}

fn nullifier_of(held: &Held, commitment: &Digest) -> Option<Digest> {
    let mut elements = Vec::new();
    elements.extend_from_slice(commitment.elements());
    elements.extend_from_slice(
        poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, &held.nf_key)
            .0
            .elements(),
    );
    elements.push(F::try_from_u64(held.position)?);
    Some(poseidon::hash_elements(domain::MT_NOTE_NF, &elements))
}

// Where each value of the public input stands, counted in words.
fn places_of_public(places: &Places) -> (Vec<usize>, Vec<usize>, Vec<usize>, usize, usize, usize) {
    let per_spend = places.consumed + places.created + 1;
    let mut nullifiers = Vec::new();
    let mut commitments = Vec::new();
    let mut rates = Vec::new();
    for spend in 0..places.spends {
        let base = spend * per_spend * CAPACITY;
        for at in 0..places.consumed {
            nullifiers.push(base + at * CAPACITY);
        }
        for at in 0..places.created {
            commitments.push(base + (places.consumed + at) * CAPACITY);
        }
        rates.push(base + (places.consumed + places.created) * CAPACITY);
    }
    let root = places.spends * per_spend * CAPACITY;
    let admitted = root + CAPACITY;
    let window = admitted + CAPACITY;
    (nullifiers, commitments, rates, root, admitted, window)
}

// The description of a frame at a stated depth and height.
pub fn description(places: &Places, rows_log2: u8) -> Option<Description> {
    let width = trace_width();
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let squeeze = base + 1;
    let walk = base + 2;
    let wires = walk + path::PERIODIC_COUNT;
    let amounts_at = wires + redemption::PERIODIC_COUNT;
    let mine = amounts_at + value::PERIODIC_COUNT;
    let of_the_root = mine + 1;
    let of_the_capacities = of_the_root + 1;
    let capacity_values_at = of_the_capacities + 1;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic
        .push(sponge::carry_column(rows_log2, &places.squeeze_rows()));
    let walks: Vec<Vec<usize>> = places
        .each_redemption()
        .iter()
        .map(|r| r.level_rows())
        .collect();
    let clears: Vec<usize> = places
        .each_redemption()
        .iter()
        .flat_map(|r| r.position_rows())
        .collect();
    held.periodic
        .extend(path::periodic_columns(rows_log2, &walks, &clears));
    held.periodic.extend(wire_columns(rows_log2, places));
    let counted: Vec<usize> = places.index_ties().iter().map(|at| at + 1).collect();
    held.periodic.extend(value::periodic_columns(
        rows_log2,
        &places.consumed_ties(),
        &places.created_ties(),
        &counted,
        places.index_bits,
        &places.closes(),
    ));
    held.periodic.push(mark(rows_log2, &places.index_ties()));
    held.periodic.push(mark(rows_log2, &places.root_rows()));
    held.periodic.push(mark(rows_log2, &places.capacity_rows()));
    held.periodic.extend(redemption::capacity_value_columns(
        rows_log2,
        &places.each_redemption(),
    ));
    let of_the_leaf = capacity_values_at + 2 * CAPACITY;
    let of_the_nf_first = of_the_leaf + 1;
    let of_the_nf_second = of_the_nf_first + 1;
    let of_the_moment = of_the_nf_second + 1;
    let moment_ranges_at = of_the_moment + 1;
    let moment_clear = moment_ranges_at + moment::COLUMN_COUNT;
    held.periodic.push(mark(rows_log2, &places.leaf_rows()));
    held.periodic.push(mark(rows_log2, &places.read_rows()));
    held.periodic.push(mark(rows_log2, &places.position_rows()));
    held.periodic
        .push(mark(rows_log2, &places.nullifier_final_rows()));
    held.periodic.extend(moment::periodic_columns(
        rows_log2,
        &places.nullifier_first_rows(),
        &places.nullifier_final_rows(),
    ));

    held.constraints.extend(sponge::capacity_carries(carry));
    held.constraints.extend(sponge::rate_carries(squeeze));
    held.constraints.extend(path::constraints(walk));
    let of_the_root_split = split(SPLIT_ROOT);
    held.constraints.extend(super::branch::constraints(
        of_the_root,
        of_the_root_split.note,
        of_the_root_split.right,
    ));
    held.constraints
        .extend(redemption::root_of_a_branch(&of_the_root_split, roots_at()));
    let of_the_capacity_split = split(SPLIT_CAPACITY);
    held.constraints.extend(super::branch::constraints(
        of_the_capacities,
        of_the_capacity_split.note,
        of_the_capacity_split.right,
    ));
    held.constraints.extend(redemption::capacity_constraints(
        &of_the_capacity_split,
        capacity_values_at,
    ));
    for (schedule, which) in [
        (of_the_leaf, SPLIT_LEAF),
        (of_the_nf_first, SPLIT_NF_FIRST),
        (of_the_nf_second, SPLIT_NF_SECOND),
        (of_the_moment, SPLIT_MOMENT),
    ] {
        let of_it = split(which);
        held.constraints.extend(super::branch::constraints(
            schedule,
            of_it.note,
            of_it.right,
        ));
    }
    held.constraints
        .extend(redemption::leaf_input_constraints(&split(SPLIT_LEAF)));
    held.constraints.extend(redemption::nf_first_constraints(
        &split(SPLIT_NF_FIRST),
        roots_at(),
        moments().column(moment::REMAINDER),
    ));
    held.constraints
        .extend(redemption::nf_second_constraints(&split(SPLIT_NF_SECOND)));
    let spread = mt_genesis::divisor("claim_spread")?;
    held.constraints
        .extend(redemption::published_nullifier_constraints(
            &split(SPLIT_MOMENT),
            &split(SPLIT_NF_SECOND),
            roots_at(),
        ));
    held.constraints.extend(moment::constraints(
        &moments(),
        amounts().bit,
        moment_ranges_at,
        moment_clear,
        &split(SPLIT_MOMENT),
        permutation::ring_column(0),
        spread,
    ));
    let sample = redemption::Places::of(0, places.depth);
    held.constraints
        .extend(redemption::constraints(wires, walk + path::WRAP, &sample));
    let amounts = amounts();
    held.constraints
        .extend(value::constraints(amounts_at, &amounts));
    held.constraints
        .extend(index_constraints(mine, amounts_at, &amounts));
    held.boundaries.extend(boundaries(places));
    Some(held)
}

fn mark(rows_log2: u8, rows: &[usize]) -> crate::air::Periodic {
    let count = 1usize << rows_log2;
    let mut values = vec![0u64; count];
    for row in rows {
        if *row < count {
            values[*row] = 1;
        }
    }
    crate::air::Periodic {
        period_log2: rows_log2,
        values,
    }
}

// The four columns of the wiring of every redemption of a frame, gathered from each of them.
fn wire_columns(rows_log2: u8, places: &Places) -> Vec<crate::air::Periodic> {
    let all = places.each_redemption();
    let gather = |f: fn(&redemption::Places) -> Vec<usize>| -> Vec<usize> {
        all.iter().flat_map(f).collect()
    };
    vec![
        mark(rows_log2, &gather(|r| r.wire_rows())),
        mark(rows_log2, &gather(|r| r.load_rows())),
        mark(rows_log2, &gather(|r| r.spending_rows())),
    ]
}

// The index of a rate stands below the bound the Decree names: its bits are taken by the same
// decomposition an amount uses, and what they reach is the limb the block absorbs.
fn index_constraints(
    mine: usize,
    amounts_at: usize,
    amounts: &value::Places,
) -> Vec<crate::air::Constraint> {
    let _ = amounts_at;
    vec![crate::air::Constraint {
        degree: 2,
        terms: vec![
            sponge::term(
                F::ONE,
                vec![
                    sponge::factor(mine + INDEX_TIE, 0, 1),
                    sponge::factor(amounts.amount, 1, 1),
                ],
            ),
            sponge::term(
                F::ONE.negated(),
                vec![
                    sponge::factor(mine + INDEX_TIE, 0, 1),
                    sponge::factor(permutation::ring_column(INDEX_CELL), 1, 1),
                ],
            ),
        ],
    }]
}

// Every boundary of a frame: what each chain opens with, what it pads with, and the values that
// stand outside it.
pub fn boundaries(places: &Places) -> Vec<Boundary> {
    let (nullifiers, commitments, rates, root, admitted, window) = places_of_public(places);
    let mut out = Vec::new();
    let mut at_nullifier = 0usize;
    for spend in 0..places.spends {
        for at in 0..places.consumed {
            let redemption_places = places.redemption_at(spend, at);
            out.extend(redemption::boundaries(
                &redemption_places,
                word(nullifiers[at_nullifier]),
            ));
            out.extend(redemption::nullifier_pin_boundaries(
                &redemption_places,
                roots_at(),
                word(nullifiers[at_nullifier]),
            ));
            out.extend(redemption::root_boundaries(
                &redemption_places,
                roots_at(),
                word(root),
                word(admitted),
            ));
            // The window the frame stands in, pinned where the rule of a right's window reads it:
            // the first row of the nullifier chain. The column is the note root's lane, free at
            // this row in both branches; a boundary knows no branch and both carry the pin.
            out.push(Boundary {
                column: roots_at() as u16,
                row: (redemption_places.nullifier() * period()) as u64,
                value: BoundaryValue::Word(word(window)),
            });
            at_nullifier += 1;
        }
        for at in 0..places.created {
            let first = places.created_at(spend, at);
            out.extend(chain_boundaries(
                domain::MT_NOTE_CM,
                first,
                created_element_count(),
                0,
            ));
            let last = ((first + places.created_blocks()) * period() - 1) as u64;
            for j in 0..CAPACITY {
                out.push(Boundary {
                    column: permutation::ring_column(j) as u16,
                    row: last,
                    value: BoundaryValue::Word(word(commitments[spend * places.created + at] + j)),
                });
            }
        }
        let first = places.rate_at(spend);
        out.extend(chain_boundaries(
            domain::MT_RATE_NF,
            first,
            rate_element_count(),
            0,
        ));
        // The window a rate belongs to is the one the verifier computes, and it enters the chain
        // where the preimage puts it: the two limbs after the eight of the secret.
        for j in 0..2 {
            out.push(Boundary {
                column: permutation::ring_column(j) as u16,
                row: ((first + 1) * period()) as u64,
                value: BoundaryValue::Public(word(window) + j as u16),
            });
        }
        let last = ((first + places.rate_blocks()) * period() - 1) as u64;
        for j in 0..CAPACITY {
            out.push(Boundary {
                column: permutation::ring_column(j) as u16,
                row: last,
                value: BoundaryValue::Word(word(rates[spend] + j)),
            });
        }
    }
    out
}

// The capacity a chain opens with and the padding it closes with.
fn chain_boundaries(
    domain: mt_codec::Domain,
    first: usize,
    elements: usize,
    wired: usize,
) -> Vec<Boundary> {
    let mut out = Vec::new();
    let capacity = poseidon::capacity_of(domain);
    for (j, value) in capacity.iter().enumerate() {
        out.push(Boundary {
            column: permutation::ring_column(RATE + j) as u16,
            row: (first * period()) as u64,
            value: BoundaryValue::Literal(value.as_u64()),
        });
    }
    let blocks = sponge::blocks_of(elements);
    for at in elements..blocks * RATE {
        if at < wired {
            continue;
        }
        let (block, slot) = (at / RATE, at % RATE);
        out.push(Boundary {
            column: permutation::ring_column(slot) as u16,
            row: ((first + block) * period()) as u64,
            value: if at == elements {
                BoundaryValue::Literal(F::ONE.as_u64())
            } else {
                BoundaryValue::Literal(0)
            },
        });
    }
    out
}

// The whole of a frame written into the trace, answering with the root its redemptions prove
// against — every one of them against the same one, which is what the set fixes.
pub fn write_frame(
    columns: &mut [Vec<F>],
    places: &Places,
    frame: &Frame,
    admitted: &Digest,
) -> Option<Digest> {
    let mut root = None;
    let spread = mt_genesis::divisor("claim_spread")?;
    for (spend, held) in frame.spends.iter().enumerate() {
        for (at, consumed) in held.consumed.iter().enumerate() {
            let redemption_places = places.redemption_at(spend, at);
            match consumed {
                // What a filler writes is what a note writes, over values its emitter drew: the
                // blocks are full, the sponge is lawful, and the root it reaches answers to
                // nothing, because under its half the rule that ties a walk to a root does not
                // fire.
                Consumed::Filler(drawn) => {
                    let (_, nullifier) =
                        redemption::write_redemption(columns, &redemption_places, drawn)?;
                    write_nullifier_pins(columns, &redemption_places, &nullifier);
                }
                Consumed::Note(note) => {
                    let (reached, nullifier) =
                        redemption::write_redemption(columns, &redemption_places, note)?;
                    write_nullifier_pins(columns, &redemption_places, &nullifier);
                    match root {
                        None => root = Some(reached),
                        Some(held_root) if held_root == reached => {}
                        Some(_) => return None,
                    }
                }
                Consumed::Right(right) => {
                    let (reached, nullifier, delay) =
                        redemption::write_right_redemption(columns, &redemption_places, right)?;
                    write_nullifier_pins(columns, &redemption_places, &nullifier);
                    // A right proves against the tree of admitted machines and against nothing
                    // else: a walk ending elsewhere is a frame no verifier accepts, refused here
                    // where it is written.
                    if reached != *admitted {
                        return None;
                    }
                    moment::write_moment(
                        columns,
                        &moments(),
                        amounts().bit,
                        redemption_places.nullifier() * period(),
                        (redemption_places.nullifier() + redemption_places.nullifier_blocks())
                            * period()
                            - 1,
                        delay,
                        spread,
                    );
                }
            }
        }
        for (at, created) in held.created.iter().enumerate() {
            let first = places.created_at(spend, at);
            let elements = created_elements(created)?;
            for (block, state) in sponge::chain(domain::MT_NOTE_CM, &elements)
                .iter()
                .enumerate()
            {
                permutation::write_block(columns, first + block, state)?;
            }
        }
        let first = places.rate_at(spend);
        let elements = rate_elements(&held.rate, frame.window);
        for (block, state) in sponge::chain(domain::MT_RATE_NF, &elements)
            .iter()
            .enumerate()
        {
            permutation::write_block(columns, first + block, state)?;
        }
    }
    // A frame that redeems no note reaches no root of the tree of notes, and that is lawful: the
    // first value of the network is a right beside filler, and neither walks that tree. What comes
    // back then is the root of the tree holding nothing — the value such a frame proves against —
    // and the rule tying a walk to a root does not fire in either position, because both stand
    // under halves this frame did not take.
    Some(root.unwrap_or_else(crate::notes::empty_root))
}

// The published nullifier of one redemption, standing in the pinned lanes at both rows its
// branches read it from.
fn write_nullifier_pins(columns: &mut [Vec<F>], places: &redemption::Places, value: &Digest) {
    let of_the_right = (places.nullifier() + 1) * period();
    let of_the_note = (places.nullifier() + places.nullifier_blocks()) * period() - 1;
    for j in 0..CAPACITY {
        for row in [of_the_right, of_the_note] {
            columns[roots_at() + CAPACITY + j][row] = value.elements()[j];
        }
    }
}

// The bits every amount of a frame is decomposed into, and the index of every rate beside them.
pub fn write_amounts(columns: &mut [Vec<F>], places: &Places, frame: &Frame) {
    let amounts = amounts();
    let consumed = places.consumed_ties();
    let created = places.created_ties();
    let mut at = 0usize;
    for held in frame.spends.iter() {
        for value in held.consumed.iter() {
            value::write_amount(
                columns,
                &amounts,
                consumed[at],
                value.value(),
                value::BITS_OF_AN_AMOUNT,
            );
            at += 1;
        }
    }
    let mut at = 0usize;
    for held in frame.spends.iter() {
        for created_note in held.created.iter() {
            value::write_amount(
                columns,
                &amounts,
                created[at],
                created_note.value,
                value::BITS_OF_AN_AMOUNT,
            );
            at += 1;
        }
    }
    for (spend, held) in frame.spends.iter().enumerate() {
        let tie = places.index_ties()[spend] + 1;
        value::write_amount(
            columns,
            &amounts,
            tie,
            u128::from(held.rate.index),
            places.index_bits,
        );
    }
}

// The trace of a whole frame.
pub fn trace_of(
    places: &Places,
    frame: &Frame,
    admitted: &Digest,
    rows_log2: u8,
) -> Option<(Vec<Vec<F>>, Digest)> {
    let rows = 1usize << rows_log2;
    if places.blocks() * period() > rows {
        return None;
    }
    let mut columns = vec![vec![F::ZERO; rows]; trace_width()];
    let root = write_frame(&mut columns, places, frame, admitted)?;
    for block in places.blocks()..rows / period() {
        permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])?;
    }
    path::write_pairs(&mut columns);
    let walks: Vec<Vec<usize>> = places
        .each_redemption()
        .iter()
        .map(|r| r.level_rows())
        .collect();
    let clears: Vec<usize> = places
        .each_redemption()
        .iter()
        .flat_map(|r| r.position_rows())
        .collect();
    path::write_accumulator(&mut columns, &walks, &clears);
    // The two roots stand where a walk ends, and the half of the split says which of them the
    // redemption answered against. Every redemption of this frame answers against the tree of
    // notes; a redemption of a right answers against the other, and nothing of the difference
    // reaches the length of a frame or the shape of its trace.
    let root_rows = places.root_rows();
    for (at, row) in root_rows.iter().enumerate() {
        let _ = at;
        for j in 0..CAPACITY {
            columns[roots_at() + j][*row] = root.elements()[j];
            columns[roots_at() + CAPACITY + j][*row] = admitted.elements()[j];
        }
    }
    // The window of the frame, standing where its pin reads it: the first row of every
    // nullifier chain, in the note root's lane, which is free there in both branches.
    for row in places.nullifier_first_rows() {
        columns[roots_at()][row] = F::try_from_u64(frame.window)?;
    }
    // Which redemptions were rights, and therefore which rows of every schedule carry the right
    // half of its split. The description knows none of this: the halves are the witness.
    let rights: Vec<usize> = {
        let mut out = Vec::new();
        let mut which = 0usize;
        for held in frame.spends.iter() {
            for consumed in held.consumed.iter() {
                if matches!(consumed, Consumed::Right(_)) {
                    out.push(which);
                }
                which += 1;
            }
        }
        out
    };
    // And which were filler: positions whose values their emitter drew and which assert nothing.
    // Under this half neither branch's rules fire, so a walk ending anywhere and a chain over
    // anything are lawful — and the shape of a spend says nothing about how many of its positions
    // carried a transfer.
    let fillers: Vec<usize> = {
        let mut out = Vec::new();
        let mut which = 0usize;
        for held in frame.spends.iter() {
            for consumed in held.consumed.iter() {
                if matches!(consumed, Consumed::Filler(_)) {
                    out.push(which);
                }
                which += 1;
            }
        }
        out
    };
    let of_rights = |rows_of: &dyn Fn(&redemption::Places) -> Vec<usize>| -> Vec<usize> {
        let all = places.each_redemption();
        rights.iter().flat_map(|at| rows_of(&all[*at])).collect()
    };
    let of_fillers = |rows_of: &dyn Fn(&redemption::Places) -> Vec<usize>| -> Vec<usize> {
        let all = places.each_redemption();
        fillers.iter().flat_map(|at| rows_of(&all[*at])).collect()
    };
    super::branch::write_halves(
        &mut columns,
        &split(SPLIT_ROOT),
        &root_rows,
        &of_rights(&|r| vec![(r.nodes() + r.depth) * period() - 1]),
        &of_fillers(&|r| vec![(r.nodes() + r.depth) * period() - 1]),
    );
    super::branch::write_halves(
        &mut columns,
        &split(SPLIT_CAPACITY),
        &places.capacity_rows(),
        &of_rights(&|r| r.capacity_rows()),
        &of_fillers(&|r| r.capacity_rows()),
    );
    super::branch::write_halves(
        &mut columns,
        &split(SPLIT_LEAF),
        &places.leaf_rows(),
        &of_rights(&|r| r.leaf_rows()),
        &of_fillers(&|r| r.leaf_rows()),
    );
    super::branch::write_halves(
        &mut columns,
        &split(SPLIT_NF_FIRST),
        &places.read_rows(),
        &of_rights(&|r| r.read_rows()),
        &of_fillers(&|r| r.read_rows()),
    );
    super::branch::write_halves(
        &mut columns,
        &split(SPLIT_NF_SECOND),
        &places.position_rows(),
        &of_rights(&|r| r.position_rows()),
        &of_fillers(&|r| r.position_rows()),
    );
    super::branch::write_halves(
        &mut columns,
        &split(SPLIT_MOMENT),
        &places.nullifier_final_rows(),
        &of_rights(&|r| vec![(r.nullifier() + r.nullifier_blocks()) * period() - 1]),
        &of_fillers(&|r| vec![(r.nullifier() + r.nullifier_blocks()) * period() - 1]),
    );
    let loads: Vec<usize> = places
        .each_redemption()
        .iter()
        .flat_map(|r| r.load_rows())
        .collect();
    let spending: Vec<usize> = places
        .each_redemption()
        .iter()
        .flat_map(|r| r.spending_rows())
        .collect();
    redemption::write_lane(&mut columns, &loads, &spending, &clears);
    write_amounts(&mut columns, places, frame);
    let counted: Vec<usize> = places.index_ties().iter().map(|at| at + 1).collect();
    value::write_accumulators(
        &mut columns,
        &amounts(),
        &places.consumed_ties(),
        &places.created_ties(),
        &counted,
        places.index_bits,
        &places.closes(),
    );
    Some((columns, root))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::notes;

    const DEPTH: usize = 4;
    const ROWS_LOG2: u8 = 14;

    // A tree holding the notes a frame consumes, and the path of each of them. Every redemption of
    // a frame proves against one root, which is what the set fixes, so the tree is built once and
    // the paths are read out of it.
    // The tree the state holds, asked of the door that owns the fold. A second walk written here
    // would be a second implementation of it, and the two would agree only until one was edited.
    fn tree(commitments: &[Digest], depth: usize) -> (Digest, Vec<Vec<Digest>>) {
        let mut held = notes::Tree::new(depth);
        for commitment in commitments {
            // PANIC-OK: a test appending digests of the family into a tree of this depth.
            held.push(&commitment.bytes())
                .ok()
                .expect("a leaf of the family");
        }
        let paths = (0..commitments.len() as u64)
            .map(|at| held.path(at).expect("a position that was written"))
            .collect();
        (held.root(), paths)
    }

    fn consumed_note(which: usize, value: u128) -> Consumed {
        Consumed::Note(note_of(which, value))
    }

    fn note_of(which: usize, value: u128) -> Held {
        Held {
            nf_key: [0x30 + which as u8; 32],
            value,
            note_pk: [0x20 + which as u8; 32],
            rcm: [0x80 + which as u8; 32],
            siblings: Vec::new(),
            position: which as u64,
        }
    }

    fn created_note(which: usize, value: u128) -> Created {
        Created {
            half: mt_derive_half(&[0x50 + which as u8; 32]).bytes(),
            value,
            note_pk: [0x60 + which as u8; 32],
            rcm: [0x90 + which as u8; 32],
        }
    }

    // A frame of three spends, each consuming two notes and creating two of the same total.
    fn frame_of(amounts: [[u128; 4]; 3]) -> (Frame, Places, Digest) {
        let places = Places::of(DEPTH).expect("the Decree names the shape of a frame");
        let mut consumed = Vec::new();
        for (spend, values) in amounts.iter().enumerate() {
            for (at, value) in values.iter().take(2).enumerate() {
                consumed.push(consumed_note(spend * 2 + at, *value));
            }
        }
        let commitments: Vec<Digest> = consumed
            .iter()
            .map(|held| match held {
                Consumed::Note(note) => {
                    // PANIC-OK: a test folding the note this same test built above.
                    commitment_of(note, &mt_derive_half(&note.nf_key)).expect("a commitment")
                }
                Consumed::Right(_) | Consumed::Filler(_) => {
                    unreachable!("the balanced frame consumes notes")
                }
            })
            .collect();
        let (root, paths) = tree(&commitments, DEPTH);
        for (held, path) in consumed.iter_mut().zip(paths) {
            if let Consumed::Note(note) = held {
                note.siblings = path;
            }
        }
        let spends: Vec<Spend> = (0..3)
            .map(|spend| Spend {
                consumed: consumed[spend * 2..spend * 2 + 2].to_vec(),
                created: (0..2)
                    .map(|at| created_note(spend * 2 + at, amounts[spend][2 + at]))
                    .collect(),
                rate: Rate {
                    secret: [0x55; 32],
                    index: spend as u8,
                },
            })
            .collect();
        (
            Frame {
                spends,
                window: 1000,
            },
            places,
            root,
        )
    }

    // The root of the tree of admitted machines this frame stands beside. No redemption of these
    // tests answers against it; what it is here for is that the shape of a frame does not depend on
    // which branch was taken, and a frame of notes therefore carries it exactly as a frame of
    // rights would.
    fn admitted() -> Digest {
        crate::admitted::empty_root()
    }

    fn balanced() -> [[u128; 4]; 3] {
        [
            [5_000_000_000, 3_000_000_000, 6_000_000_000, 2_000_000_000],
            [1, 2, 2, 1],
            [1 << 40, 7, 7, 1 << 40],
        ]
    }

    #[test]
    fn the_frame_of_the_set_is_the_shape_this_circuit_holds() {
        let places = Places::of(DEPTH).expect("the Decree names the shape of a frame");
        assert_eq!(places.spends, 3);
        assert_eq!(places.consumed, 2);
        assert_eq!(places.created, 2);
        // And at the depth the Decree names, the blocks of a frame are the count the set derives.
        let deep = Places::of(mt_genesis::scalar("note_tree_depth").expect("named") as usize)
            .expect("the Decree names the shape of a frame");
        assert_eq!(deep.redemption_blocks(), 50);
        assert_eq!(deep.spend_blocks(), 110);
        assert_eq!(deep.blocks(), 330);
    }

    #[test]
    fn a_balanced_frame_satisfies_its_description() {
        let (frame, places, root) = frame_of(balanced());
        let held = description(&places, ROWS_LOG2).expect("a lawful height");
        held.check().expect("the description stands");
        let (trace, reached) =
            trace_of(&places, &frame, &admitted(), ROWS_LOG2).expect("a written frame");
        assert_eq!(reached, root);
        let public =
            poseidon::limbs_of(&public_of(&frame, &places, &root, &admitted()).expect("a public"));
        assert!(held.satisfied_by(&trace, &public));
    }

    #[test]
    fn a_frame_that_creates_more_than_it_consumes_has_no_trace() {
        // The one rule that makes a frame a payment rather than a mint, refused where it is
        // broken: a spend whose outputs exceed its inputs by one.
        let mut amounts = balanced();
        amounts[1][2] += 1;
        let (frame, places, root) = frame_of(amounts);
        let held = description(&places, ROWS_LOG2).expect("a lawful height");
        let (trace, _) =
            trace_of(&places, &frame, &admitted(), ROWS_LOG2).expect("a written frame");
        let public = public_of(&frame, &places, &root, &admitted()).expect("a public input");
        assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    }

    #[test]
    fn an_index_of_a_rate_beyond_the_bound_has_no_trace() {
        // The bound the Decree names, held by the bits the index is read from: an index of four
        // does not stand in two of them.
        let (mut frame, places, root) = frame_of(balanced());
        frame.spends[0].rate.index = mt_genesis::scalar("spends_per_window").expect("named") as u8;
        let held = description(&places, ROWS_LOG2).expect("a lawful height");
        let (trace, _) =
            trace_of(&places, &frame, &admitted(), ROWS_LOG2).expect("a written frame");
        let public = public_of(&frame, &places, &root, &admitted()).expect("a public input");
        assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    }

    #[test]
    fn a_note_yields_one_nullifier_and_not_one_for_every_key_drawn() {
        // The rule that makes a note spendable once: the half the nullifier is taken under comes
        // of the same absorption of the key the commitment names. Here the spender leaves the
        // commitment, the leaf and the walk exactly as they stand and writes the half of another
        // key where the nullifier chain takes one — which is every step a holder of a note can
        // take on their own, and the whole of what a lane carrying that half refuses.
        let (frame, places, root) = frame_of(balanced());
        let held = description(&places, ROWS_LOG2).expect("a lawful height");
        let (mut trace, _) =
            trace_of(&places, &frame, &admitted(), ROWS_LOG2).expect("a written frame");
        let public = public_of(&frame, &places, &root, &admitted()).expect("a public input");
        assert!(held.satisfied_by(&trace, &poseidon::limbs_of(&public)));

        let Consumed::Note(note) = &frame.spends[0].consumed[0] else {
            unreachable!("the balanced frame consumes notes")
        };
        // PANIC-OK: a test folding the note this same test built above.
        let commitment = commitment_of(note, &mt_derive_half(&note.nf_key)).expect("a commitment");
        let first = places.redemption_at(0, 0).nullifier();
        let rewritten = |trace: &mut Vec<Vec<F>>, key: &[u8; 32]| -> Digest {
            let spending = poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, key).0;
            let mut elements = Vec::new();
            elements.extend_from_slice(commitment.elements());
            elements.extend_from_slice(spending.elements());
            // PANIC-OK: a test reading the position this same test assigned two lines above.
            elements.push(F::try_from_u64(note.position).expect("a position of the tree"));
            // PANIC-OK: a test writing into a trace it built two lines above, at blocks the
            // shape of that trace holds by construction.
            for (at, state) in sponge::chain(domain::MT_NOTE_NF, &elements)
                .iter()
                .enumerate()
            {
                permutation::write_block(trace, first + at, state).expect("a block");
            }
            // The pair of a walk is read off the ring at every row, so a hand that rewrites the
            // ring rewrites it too. Leaving it stale would refuse this trace for the rewriting
            // and not for the key, which is a refusal that answers a question nobody asked.
            path::write_pairs(trace);
            poseidon::hash_elements(domain::MT_NOTE_NF, &elements)
        };
        // The control the refusal below is worth nothing without: the same hand, rewriting the
        // same two blocks under the key the commitment does name, leaves the frame standing. A
        // refusal that fires here would be a refusal of the rewriting and not of the key.
        let honest = rewritten(&mut trace, &note.nf_key);
        let mut published = public.clone();
        published[..32].copy_from_slice(&honest.bytes());
        assert!(
            held.satisfied_by(&trace, &poseidon::limbs_of(&published)),
            "the chain rewritten under the true key is the chain that stood"
        );

        let drawn = rewritten(&mut trace, &[0xAB; 32]);
        published[..32].copy_from_slice(&drawn.bytes());
        assert!(
            !held.satisfied_by(&trace, &poseidon::limbs_of(&published)),
            "a note spent under a key its commitment does not name is a note spent twice"
        );
    }

    // The admitted tree of these tests: one machine at position zero, at the depth the test
    // frames use, folded by the doors of the tree of admitted machines.
    fn admitted_of_one(machine_secret: &[u8; 32]) -> (Digest, Vec<Digest>) {
        let naming = poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, machine_secret).1;
        let leaf = crate::admitted::leaf_of(&naming);
        let mut empties = vec![crate::admitted::empty_leaf()];
        for level in 0..DEPTH {
            let below = empties[level];
            empties.push(crate::admitted::node(&below, &below));
        }
        let mut current = leaf;
        let mut siblings = Vec::new();
        for empty in empties.iter().take(DEPTH) {
            siblings.push(*empty);
            current = crate::admitted::node(&current, empty);
        }
        (current, siblings)
    }

    // The window whose computed moment of extinguishing is the stated one: found by walking the
    // spread back, exactly as a machine finds which of its rights is due. Not every window has
    // one — the moments of a machine's rights spread rather than cover — so the caller who needs
    // one picks the frame's window from a machine's moment, never the reverse.
    fn a_right_due_at(machine_secret: &[u8; 32], at: u64) -> Option<u64> {
        let spread = mt_genesis::divisor("claim_spread")?;
        (at.saturating_sub(spread)..=at)
            .find(|w| mt_derive::nullifier::claim_window(machine_secret, *w) == Some(at))
    }

    #[test]
    fn a_frame_redeeming_a_right_is_proven_and_a_wrong_moment_or_tree_is_not() {
        // The disjunction driven from one trace: the first redemption of the frame consumes a
        // right — the machine's membership walked in the tree of admitted machines, its nullifier
        // squeezed for the moment, the moment's division ranged — and the other five consume
        // notes. The frame's fields and length say nothing of which.
        let machine_secret = [0x77u8; 32];
        let (admitted_root, admitted_siblings) = admitted_of_one(&machine_secret);
        // The frame stands in the window the machine's right of window 1000 is due at.
        let due = 1000u64;
        // PANIC-OK: a test reading a moment the Decree's spread bounds.
        let window = mt_derive::nullifier::claim_window(&machine_secret, due)
            .expect("the Decree names the spread");
        let amounts = balanced();
        // The right stands where note 0 stood, worth what that note was worth.
        let (frame_of_notes, places, root) = frame_of(amounts);
        let mut frame = frame_of_notes;
        frame.window = window;
        frame.spends[0].consumed[0] = Consumed::Right(HeldRight {
            machine_secret,
            window: due,
            value: amounts[0][0],
            siblings: admitted_siblings.clone(),
            position: 0,
        });
        let held = description(&places, ROWS_LOG2).expect("a lawful height");
        held.check().expect("the description stands");
        let (trace, reached) =
            trace_of(&places, &frame, &admitted_root, ROWS_LOG2).expect("a written frame");
        assert_eq!(reached, root, "the notes still prove against their root");
        let public = public_of(&frame, &places, &root, &admitted_root).expect("a public input");
        assert!(
            held.satisfied_by(&trace, &poseidon::limbs_of(&public)),
            "a frame redeeming a right stands"
        );
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true frame proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));

        // A right of a window whose moment is not this one: the same machine, one window on.
        let mut wrong_moment = frame.clone();
        if let Consumed::Right(right) = &mut wrong_moment.spends[0].consumed[0] {
            right.window = due + 1;
        }
        if let Some((trace, _)) = trace_of(&places, &wrong_moment, &admitted_root, ROWS_LOG2) {
            let public =
                public_of(&wrong_moment, &places, &root, &admitted_root).expect("a public input");
            assert!(
                !held.satisfied_by(&trace, &poseidon::limbs_of(&public)),
                "a right taken at a moment its delay does not name is refused"
            );
        }

        // A membership in a tree the frame does not publish: the walk of a fresh secret reaches
        // some root, and against the published one the frame does not stand. This is the mint the
        // set closed: a fresh secret yields a fresh nullifier, and membership is what refuses it.
        // A stranger whose own moment lands in this same window, found by searching secrets: the
        // refusal below must be membership's alone, not the moment's.
        // PANIC-OK: a test walking secrets until one of two hundred f56 moments lands.
        let stranger = (0..=u8::MAX)
            .map(|k| {
                let mut secret = [0x5Eu8; 32];
                secret[31] = k;
                secret
            })
            .find(|secret| a_right_due_at(secret, window).is_some())
            .expect("one of the secrets has a right due here");
        let (strangers_root, strangers_siblings) = admitted_of_one(&stranger);
        let mut fresh = frame.clone();
        if let Consumed::Right(right) = &mut fresh.spends[0].consumed[0] {
            right.machine_secret = stranger;
            // PANIC-OK: found one line above.
            right.window = a_right_due_at(&stranger, window).expect("found above");
            right.siblings = strangers_siblings;
        }
        let (trace, _) = trace_of(&places, &fresh, &strangers_root, ROWS_LOG2)
            .expect("the stranger writes a trace against its own tree");
        let public = public_of(&fresh, &places, &root, &admitted_root).expect("a public input");
        assert!(
            !held.satisfied_by(&trace, &poseidon::limbs_of(&public)),
            "a share claimed by an invented secret is refused by membership"
        );
    }

    #[test]
    fn a_frame_is_proven_and_verified_as_bytes() {
        // The whole of it through the machine a proof travels: three spends, six redemptions
        // against one root, the balances closed and the rates bounded — written as bytes, read
        // back and accepted, and refused for a frame that published one nullifier differently.
        let (frame, places, root) = frame_of(balanced());
        let held = description(&places, ROWS_LOG2).expect("a lawful height");
        let (trace, _) =
            trace_of(&places, &frame, &admitted(), ROWS_LOG2).expect("a written frame");
        let public = public_of(&frame, &places, &root, &admitted()).expect("a public input");
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true frame proves");
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));
        let mut other = public.clone();
        other[0] ^= 1;
        assert!(crate::scheme::verify(&held, &other, &bytes).is_err());
    }
}
