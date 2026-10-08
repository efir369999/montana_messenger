// A redemption as a constraint set: the half of a nullifier key derived, the commitment of the note
// derived over it, the leaf absorbed, the path walked, and the nullifier derived at the end — all of
// it in the arithmetic of the proof hash, and all of it wired by seams rather than by trust.
//
// **The order of the blocks is the wiring.** A factor names this row or the one after it, so a value
// one derivation answers with reaches the next only if the two stand beside each other. The order
// below is therefore not a taste: the half feeds the commitment, the commitment feeds the leaf, the
// walk carries the leaf to a root, and the nullifier closes over the commitment and the position the
// walk was made at. One value alone is needed twice far apart — the commitment, by the leaf and by
// the nullifier — and that one travels a lane of four columns with a rule of its own.
//
// **What a proof of this says.** There is a note in the tree of this root whose nullifier is this
// value, and whoever wrote the proof holds the key that spends it. The commitment, the amount, the
// blinding factor, the path and the position stay inside; the root and the nullifier stand outside.

use super::path;
use super::permutation::{self, period, ring_column};
use super::sponge::{self, factor, term};
use crate::air::{Boundary, BoundaryValue, Constraint, Periodic};
use crate::field::F;
use crate::poseidon::{self, Digest, CAPACITY, RATE};
use mt_codec::domain;

// The lane a value travels when the place that needs it is not the place beside it. Two values
// travel it: the commitment, from the block that computes it to the nullifier that names it, and
// the spending half of the key, from the squeeze that yields it to the same place. Both cross the
// walk, and a walk is forty blocks wide.
pub const LANE: usize = path::TRACE_WIDTH;
pub const TRACE_WIDTH: usize = LANE + LANE_WIDTH;

mt_codec::constants! {
    REDEMPTION:
    /// Where the wiring of a redemption stands among the periodic columns this layer adds: the seam
    /// at which a digest enters the block beside it, the seam at which it enters the lane, the seam
    /// at which the lane enters a block, and the seam at which the accumulator says which position
    /// the nullifier is taken at. All are places of this layout and of nothing else.
    pub const WIRE: usize = 0, code "the periodic column of this layout marking a digest wired to the block beside it";
    pub const LOAD: usize = 1, code "the periodic column of this layout marking a digest entering the lane";
    pub const SPENDING: usize = 2, code "the periodic column of this layout marking the squeeze of the spending half entering the lane";
    /// The columns the lane carries: two digests of the family, since two values of a redemption
    /// are needed where the blocks that yield them do not stand.
    pub const LANE_WIDTH: usize = 2 * CAPACITY, code "the columns of the lane, being the two digests it carries";
    pub const PERIODIC_COUNT: usize = 3, code "the count of the periodic columns this layout adds";
}

// How the blocks of one redemption stand, counted from the block it opens at.
#[derive(Clone, Copy, Debug)]
pub struct Places {
    pub first: usize,
    pub depth: usize,
}

impl Places {
    pub fn of(first: usize, depth: usize) -> Self {
        Self { first, depth }
    }

    // The key: absorbed once and squeezed twice. The first squeeze is the half that spends and
    // travels the lane; the second is the half that names and enters the commitment beside it.
    pub fn half(&self) -> usize {
        self.first
    }

    pub fn absorbed_blocks(&self) -> usize {
        sponge::blocks_of(2 * CAPACITY)
    }

    pub fn half_blocks(&self) -> usize {
        self.absorbed_blocks() + 1
    }

    // The seam the second squeeze stands at, where the whole state crosses and the lane takes the
    // half that spends.
    pub fn squeeze_rows(&self) -> Vec<usize> {
        sponge::squeeze_rows(self.half(), self.absorbed_blocks())
    }

    // The commitment, which absorbs that half and the note beside it.
    pub fn commitment(&self) -> usize {
        self.half() + self.half_blocks()
    }

    pub fn commitment_blocks(&self) -> usize {
        sponge::blocks_of(CAPACITY + 4 + 2 * CAPACITY + 2 * CAPACITY)
    }

    // The leaf of the tree, which absorbs the commitment.
    pub fn leaf(&self) -> usize {
        self.commitment() + self.commitment_blocks()
    }

    // The nodes of the walk.
    pub fn nodes(&self) -> usize {
        self.leaf() + sponge::blocks_of(CAPACITY)
    }

    // The nullifier, which absorbs the commitment out of the lane, the key, and the position.
    pub fn nullifier(&self) -> usize {
        self.nodes() + self.depth
    }

    pub fn nullifier_blocks(&self) -> usize {
        sponge::blocks_of(2 * CAPACITY + 1)
    }

    pub fn blocks(&self) -> usize {
        self.nullifier() + self.nullifier_blocks() - self.first
    }

    fn seam_before(&self, block: usize) -> usize {
        block * period() - 1
    }

    // Every seam of the chains inside this redemption: the ones that carry a capacity onward.
    pub fn carry_rows(&self) -> Vec<usize> {
        let mut out = sponge::carry_rows(self.half(), self.half_blocks());
        out.extend(sponge::carry_rows(
            self.commitment(),
            self.commitment_blocks(),
        ));
        out.extend(sponge::carry_rows(
            self.nullifier(),
            self.nullifier_blocks(),
        ));
        out
    }

    // The one seam at which a digest is wired to the block beside it in both branches: the naming
    // half into the commitment chain. The seam of the leaf is a split — a note wires the
    // commitment in, a right takes the naming half out of the lane.
    pub fn wire_rows(&self) -> Vec<usize> {
        vec![self.seam_before(self.commitment())]
    }

    // Where the first slot of the lane takes the ring: at the seam of the commitment it picks up
    // the naming half — which is what the leaf of a right absorbs — and at the seam of the leaf
    // the commitment, which is what the nullifier of a note reads. A load lands one row on, so at
    // the leaf's own seam the first pickup still stands.
    pub fn load_rows(&self) -> Vec<usize> {
        vec![
            self.seam_before(self.commitment()),
            self.seam_before(self.leaf()),
        ]
    }

    // Where the half that spends enters the lane: the seam of the squeeze that yields it.
    pub fn spending_rows(&self) -> Vec<usize> {
        self.squeeze_rows()
    }

    // The seam of the leaf's input, which the two branches fill differently.
    pub fn leaf_rows(&self) -> Vec<usize> {
        vec![self.seam_before(self.leaf())]
    }

    pub fn read_rows(&self) -> Vec<usize> {
        vec![self.seam_before(self.nullifier())]
    }

    // The position stands in the second block of the nullifier's chain, after the commitment and
    // the key have filled the first.
    pub fn position_rows(&self) -> Vec<usize> {
        vec![self.seam_before(self.nullifier() + 1)]
    }

    pub fn level_rows(&self) -> Vec<usize> {
        path::level_rows(self.nodes(), self.depth)
    }

    // The rows where the two branches open chains under different domains: the seam before the
    // leaf, before every node of the walk, and before the chain of the nullifier. One split
    // covers all of them; which value the capacity takes at each row is a periodic column's to
    // say, and a column of the description costs no width.
    pub fn capacity_rows(&self) -> Vec<usize> {
        let mut out = vec![self.seam_before(self.leaf())];
        for level in 0..self.depth {
            out.push(self.seam_before(self.nodes() + level));
        }
        out.push(self.seam_before(self.nullifier()));
        out
    }
}

// The four columns of the schedule this layer adds, in the order the description carries them.
pub fn periodic_columns(rows_log2: u8, places: &Places) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let mark = |marked: Vec<usize>| {
        let mut values = vec![0u64; rows];
        for row in marked {
            if row < rows {
                values[row] = 1;
            }
        }
        Periodic {
            period_log2: rows_log2,
            values,
        }
    };
    vec![
        mark(places.wire_rows()),
        mark(places.load_rows()),
        mark(places.spending_rows()),
    ]
}

// The capacity values of the two branches, one periodic column per cell per branch: at the seam
// of a leaf the leaf domain, at a node the node domain, at the nullifier its own. What this pins
// is exactly what an unconditional boundary pinned before the second tree existed — the fold a
// chain opens under — said once for both branches instead of once for the only one.
pub fn capacity_value_columns(rows_log2: u8, places_list: &[Places]) -> Vec<Periodic> {
    let rows = 1usize << rows_log2;
    let note = [
        poseidon::capacity_of(domain::MT_NOTE_LEAF),
        poseidon::capacity_of(domain::MT_NOTE_NODE),
        poseidon::capacity_of(domain::MT_NOTE_NF),
    ];
    let right = [
        poseidon::capacity_of(domain::MT_ADMITTED_LEAF),
        poseidon::capacity_of(domain::MT_ADMITTED_NODE),
        poseidon::capacity_of(domain::MT_CREDIT_NF),
    ];
    let mut out = Vec::new();
    for [of_leaf, of_node, of_nf] in [note, right] {
        for ((leaf_value, node_value), nf_value) in
            of_leaf.iter().zip(of_node.iter()).zip(of_nf.iter())
        {
            let mut column = vec![0u64; rows];
            for places in places_list {
                let mut write = |row: usize, value: &F| {
                    if row < rows {
                        column[row] = value.as_u64();
                    }
                };
                write(places.seam_before(places.leaf()), leaf_value);
                for level in 0..places.depth {
                    write(places.seam_before(places.nodes() + level), node_value);
                }
                write(places.seam_before(places.nullifier()), nf_value);
            }
            out.push(Periodic {
                period_log2: rows_log2,
                values: column,
            });
        }
    }
    out
}

// The rules of that split: per cell of the capacity, each branch holds the block it opens to the
// value its column carries.
pub fn capacity_constraints(halves: &super::branch::Halves, values_at: usize) -> Vec<Constraint> {
    let mut out = Vec::new();
    for j in 0..CAPACITY {
        let cell = ring_column(RATE + j);
        out.push(super::branch::capacity_from_a_column(
            halves.note,
            cell,
            values_at + j,
        ));
        out.push(super::branch::capacity_from_a_column(
            halves.right,
            cell,
            values_at + CAPACITY + j,
        ));
    }
    out
}

// Every rule this layer adds, over the columns the caller places them at.
// The column that marks where the trace closes is the walk's own — one event, one place — so it
// arrives here by its number rather than by a second column saying the same thing.
pub fn constraints(periodic_base: usize, wrap: usize, places: &Places) -> Vec<Constraint> {
    let wire = periodic_base + WIRE;
    let load = periodic_base + LOAD;
    let spending = periodic_base + SPENDING;
    let _ = places;
    let minus = F::ONE.negated();
    let mut out = Vec::new();

    for j in 0..CAPACITY {
        let cell = ring_column(j);
        // A digest enters the block beside it: what the block leaves in its first cells is what
        // the next block absorbs in its first cells.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(wire, 0, 1), factor(cell, 1, 1)]),
                term(minus, vec![factor(wire, 0, 1), factor(cell, 0, 1)]),
            ],
        });
    }

    // The lane, in two halves of four columns. Both obey one rule and differ only in the seam that
    // fills them: the first takes the commitment where the load stands, the second the half that
    // spends where the squeeze stands. Both are read into one block at one seam, since the
    // nullifier absorbs the two of them side by side.
    for j in 0..LANE_WIDTH {
        let cell = ring_column(j);
        let lane = LANE + j;
        let fills = if j < CAPACITY { load } else { spending };
        let from = if j < CAPACITY {
            cell
        } else {
            ring_column(j - CAPACITY)
        };
        // The lane holds what it holds, and takes the digest where its seam stands. Written as one
        // rule rather than two, so no column has to say where the lane is idle — and the closing of
        // the trace empties it, exactly as that closing opens the accumulator at zero.
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(lane, 1, 1)]),
                term(minus, vec![factor(lane, 0, 1)]),
                term(F::ONE, vec![factor(wrap, 0, 1), factor(lane, 0, 1)]),
                term(minus, vec![factor(fills, 0, 1), factor(from, 0, 1)]),
                term(F::ONE, vec![factor(fills, 0, 1), factor(lane, 0, 1)]),
            ],
        });
    }
    out
}

// The seam of the leaf's input, split: a note wires the commitment out of the block beside it,
// a right takes the naming half of its machine out of the lane's first slot — where it has stood
// since the seam of the commitment picked it up, a load landing one row on.
pub fn leaf_input_constraints(halves: &super::branch::Halves) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let mut out = Vec::new();
    for j in 0..CAPACITY {
        let cell = ring_column(j);
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(halves.note, 0, 1), factor(cell, 1, 1)]),
                term(minus, vec![factor(halves.note, 0, 1), factor(cell, 0, 1)]),
            ],
        });
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(halves.right, 0, 1), factor(cell, 1, 1)]),
                term(
                    minus,
                    vec![factor(halves.right, 0, 1), factor(LANE + j, 0, 1)],
                ),
            ],
        });
    }
    out
}

// The seam of the nullifier chain's first block, split. A note reads the whole lane — the
// commitment and the half that spends, side by side. A right reads the half that spends into the
// first four cells, takes its window as the one element after them — pinned to the window the
// frame stands in less the remainder the moment drew — and closes the block with its own padding.
pub fn nf_first_constraints(
    halves: &super::branch::Halves,
    window_pin: usize,
    remainder: usize,
) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let mut out = Vec::new();
    for (j, lane) in (0..LANE_WIDTH).map(|j| (j, LANE + j)) {
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![factor(halves.note, 0, 1), factor(ring_column(j), 1, 1)],
                ),
                term(minus, vec![factor(halves.note, 0, 1), factor(lane, 0, 1)]),
            ],
        });
    }
    for j in 0..CAPACITY {
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![factor(halves.right, 0, 1), factor(ring_column(j), 1, 1)],
                ),
                term(
                    minus,
                    vec![
                        factor(halves.right, 0, 1),
                        factor(LANE + CAPACITY + j, 0, 1),
                    ],
                ),
            ],
        });
    }
    // The window of the right: one element, equal to the window the frame publishes less the
    // remainder of the moment's division — which is the whole of "accepted only in the window
    // the moment computes", read backwards.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![
                    factor(halves.right, 0, 1),
                    factor(ring_column(CAPACITY), 1, 1),
                ],
            ),
            term(
                minus,
                vec![factor(halves.right, 0, 1), factor(window_pin, 1, 1)],
            ),
            term(
                F::ONE,
                vec![factor(halves.right, 0, 1), factor(remainder, 1, 1)],
            ),
        ],
    });
    // The padding of the right's block: the one element after the window, and the zeros.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![
                    factor(halves.right, 0, 1),
                    factor(ring_column(CAPACITY + 1), 1, 1),
                ],
            ),
            term(minus, vec![factor(halves.right, 0, 1)]),
        ],
    });
    for j in CAPACITY + 2..RATE {
        out.push(Constraint {
            degree: 2,
            terms: vec![term(
                F::ONE,
                vec![factor(halves.right, 0, 1), factor(ring_column(j), 1, 1)],
            )],
        });
    }
    out
}

// The seam of the nullifier chain's second block, split. A note's second block absorbs the one
// element of its position — which is what the walk's accumulator holds — and pads; a right's
// second block is the squeeze of the moment, and the whole state crosses untouched.
pub fn nf_second_constraints(halves: &super::branch::Halves) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let mut out = Vec::new();
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(halves.note, 0, 1), factor(ring_column(0), 1, 1)],
            ),
            term(
                minus,
                vec![factor(halves.note, 0, 1), factor(path::ACCUMULATOR, 0, 1)],
            ),
        ],
    });
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(halves.note, 0, 1), factor(ring_column(1), 1, 1)],
            ),
            term(minus, vec![factor(halves.note, 0, 1)]),
        ],
    });
    for j in 2..RATE {
        out.push(Constraint {
            degree: 2,
            terms: vec![term(
                F::ONE,
                vec![factor(halves.note, 0, 1), factor(ring_column(j), 1, 1)],
            )],
        });
    }
    for j in 0..crate::poseidon::WIDTH {
        let cell = ring_column(j);
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(F::ONE, vec![factor(halves.right, 0, 1), factor(cell, 1, 1)]),
                term(minus, vec![factor(halves.right, 0, 1), factor(cell, 0, 1)]),
            ],
        });
    }
    out
}

// What a redemption holds inside it. Nothing of this leaves a device; what leaves is the root the
// walk answers against and the nullifier it spends.
#[derive(Clone, Debug)]
pub struct Held {
    pub nf_key: [u8; 32],
    pub value: u128,
    pub note_pk: [u8; 32],
    pub rcm: [u8; 32],
    pub siblings: Vec<Digest>,
    pub position: u64,
}

// The elements of each preimage, taken the way the derivations of a note take them. The order is
// the set's own and stands in one place: `mt_derive::note` computes it, and a test of this module
// holds the two against each other.
fn half_elements(held: &Held) -> Vec<F> {
    poseidon::limbs_of(&held.nf_key)
}

fn commitment_elements(held: &Held, half: &Digest) -> Vec<F> {
    let mut out = Vec::new();
    out.extend_from_slice(half.elements());
    out.extend_from_slice(&poseidon::limbs_of(&held.value.to_le_bytes()));
    out.extend_from_slice(&poseidon::limbs_of(&held.note_pk));
    out.extend_from_slice(&poseidon::limbs_of(&held.rcm));
    out
}

fn nullifier_elements(held: &Held, commitment: &Digest, spending: &Digest) -> Option<Vec<F>> {
    let mut out = Vec::new();
    out.extend_from_slice(commitment.elements());
    out.extend_from_slice(spending.elements());
    out.push(F::try_from_u64(held.position)?);
    Some(out)
}

// The key written where it stands: one absorption and two squeezes, answering with the half that
// spends and the half that names, in that order.
fn write_key(
    columns: &mut [Vec<F>],
    first_block: usize,
    elements: &[F],
) -> Option<(Digest, Digest)> {
    for (at, state) in sponge::chain_twice(domain::MT_KEY_HALVES, elements)
        .iter()
        .enumerate()
    {
        permutation::write_block(columns, first_block + at, state)?;
    }
    let (spending, naming) = poseidon::hash_elements_twice(domain::MT_KEY_HALVES, elements);
    Some((spending, naming))
}

// One chain written where it stands, answering with the digest it leaves.
fn write_chain(
    columns: &mut [Vec<F>],
    first_block: usize,
    domain: mt_codec::Domain,
    elements: &[F],
) -> Option<Digest> {
    for (at, state) in sponge::chain(domain, elements).iter().enumerate() {
        permutation::write_block(columns, first_block + at, state)?;
    }
    Some(poseidon::hash_elements(domain, elements))
}

// The whole of a redemption written into the trace, answering with the root it reaches and the
// nullifier it spends.
pub fn write_redemption(
    columns: &mut [Vec<F>],
    places: &Places,
    held: &Held,
) -> Option<(Digest, Digest)> {
    let (spending, half) = write_key(columns, places.half(), &half_elements(held))?;
    let commitment = write_chain(
        columns,
        places.commitment(),
        domain::MT_NOTE_CM,
        &commitment_elements(held, &half),
    )?;
    let root = path::write_walk(
        columns,
        places.leaf(),
        &commitment,
        &held.siblings,
        held.position,
    )?;
    let nullifier = write_chain(
        columns,
        places.nullifier(),
        domain::MT_NOTE_NF,
        &nullifier_elements(held, &commitment, &spending)?,
    )?;
    Some((root, nullifier))
}

// The lane, written once for the whole height and never per redemption. It holds what the last
// load put in it and is empty before the first — which is exactly what its rule says, and writing
// it per redemption is writing it six times over, where the last one wins and the rest are lost.
pub fn write_lane(columns: &mut [Vec<F>], loads: &[usize], spending: &[usize], clears: &[usize]) {
    let rows = columns[LANE].len();
    let mut loaded = vec![false; rows];
    for row in loads {
        if *row < rows {
            loaded[*row] = true;
        }
    }
    let mut squeezed = vec![false; rows];
    for row in spending {
        if *row < rows {
            squeezed[*row] = true;
        }
    }
    let mut emptied = vec![false; rows];
    for row in clears {
        if *row < rows {
            emptied[*row] = true;
        }
    }
    let mut held = [F::ZERO; LANE_WIDTH];
    for row in 0..rows {
        for j in 0..LANE_WIDTH {
            columns[LANE + j][row] = held[j];
        }
        if emptied[row] {
            held = [F::ZERO; LANE_WIDTH];
        }
        if loaded[row] {
            for j in 0..CAPACITY {
                held[j] = columns[ring_column(j)][row];
            }
        }
        if squeezed[row] {
            for j in 0..CAPACITY {
                held[CAPACITY + j] = columns[ring_column(j)][row];
            }
        }
    }
}

// What a redemption of a right holds instead of a note: a machine's secret, the window the right
// belongs to, the share it is worth, and the walk to the machine's own leaf in the tree of
// admitted machines. It spends its own nullifier and stands at its own moment, and the blocks it
// occupies are the note branch's exactly, so a frame says nothing by its size.
#[derive(Clone, Debug)]
pub struct HeldRight {
    pub machine_secret: [u8; 32],
    pub window: u64,
    pub value: u128,
    pub siblings: Vec<Digest>,
    pub position: u64,
}

// The whole of a right's redemption written into the trace: the key absorbed once and squeezed
// twice, the unread note of the commitment blocks, the leaf of the naming half, the walk of the
// tree of admitted machines, and the chain of the nullifier squeezed for its moment. It answers
// with the root it reaches, the nullifier it spends, and the element the delay was drawn from.
pub fn write_right_redemption(
    columns: &mut [Vec<F>],
    places: &Places,
    held: &HeldRight,
) -> Option<(Digest, Digest, u64)> {
    let elements = poseidon::limbs_of(&held.machine_secret);
    for (at, state) in sponge::chain_twice(domain::MT_KEY_HALVES, &elements)
        .iter()
        .enumerate()
    {
        permutation::write_block(columns, places.half() + at, state)?;
    }
    let (spending, naming) = poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &elements);

    // The unread note: the commitment blocks run under their own domain over the naming half, the
    // share the right is worth, and nothing else — a chain whose digest no rule of this branch
    // consumes, standing so the count of blocks says nothing about the branch. The share rides in
    // the cells an amount rides in, so the balance of the spend takes it by the same tie it takes
    // a note's; what binds that share to the share the window issued is the circuit of a window,
    // where the count of the living is computed.
    let mut unread = Vec::new();
    unread.extend_from_slice(naming.elements());
    unread.extend_from_slice(&poseidon::limbs_of(&held.value.to_le_bytes()));
    unread.resize(CAPACITY + 4 + 2 * CAPACITY + 2 * CAPACITY, F::ZERO);
    write_chain(columns, places.commitment(), domain::MT_NOTE_CM, &unread)?;

    let reached = path::write_walk_under(
        columns,
        places.leaf(),
        &naming,
        &held.siblings,
        held.position,
        domain::MT_ADMITTED_LEAF,
        domain::MT_ADMITTED_NODE,
    )?;

    let mut nf_elements = Vec::new();
    nf_elements.extend_from_slice(spending.elements());
    nf_elements.push(F::try_from_u64(held.window)?);
    for (at, state) in sponge::chain_twice(domain::MT_CREDIT_NF, &nf_elements)
        .iter()
        .enumerate()
    {
        permutation::write_block(columns, places.nullifier() + at, state)?;
    }
    let (nullifier, delay) = poseidon::hash_elements_twice(domain::MT_CREDIT_NF, &nf_elements);
    Some((reached, nullifier, delay.elements()[0].as_u64()))
}

// Where the two branches meet: the block whose digest is published. A note leaves its nullifier
// there and a right leaves its own, so one boundary ties that block to the public value and knows
// nothing of which branch wrote it — which is the whole of what "not readable from the length"
// means for a frame.
pub fn branch_capacities(halves: &super::branch::Halves) -> Vec<Constraint> {
    let note = poseidon::capacity_of(domain::MT_NOTE_NF);
    let right = poseidon::capacity_of(domain::MT_CREDIT_NF);
    let mut out = Vec::new();
    for j in 0..CAPACITY {
        let cell = ring_column(RATE + j);
        out.push(super::branch::capacity_of_a_branch(
            halves.note,
            cell,
            note[j],
        ));
        out.push(super::branch::capacity_of_a_branch(
            halves.right,
            cell,
            right[j],
        ));
    }
    out
}

// The root a walk answers against, where two trees stand. A public value reaches a trace only at a
// boundary, and a boundary knows no branch — so both roots are pinned into columns of their own at
// the row a walk ends on, and the rule takes the half of the split belonging to the branch. Written
// per cell without a split it would admit a value agreeing with one root in some cells and the
// other in the rest, which is why the split stands here and not a product of two differences.
pub fn root_of_a_branch(halves: &super::branch::Halves, roots: usize) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let mut out = Vec::new();
    for j in 0..CAPACITY {
        let reached = ring_column(j);
        for (half, lane) in [
            (halves.note, roots + j),
            (halves.right, roots + CAPACITY + j),
        ] {
            out.push(Constraint {
                degree: 2,
                terms: vec![
                    term(F::ONE, vec![factor(half, 0, 1), factor(reached, 0, 1)]),
                    term(minus, vec![factor(half, 0, 1), factor(lane, 0, 1)]),
                ],
            });
        }
    }
    out
}

// The two roots pinned where a walk ends: one boundary per cell per root per redemption, so the
// column carries the root at the row the rule reads it and nothing is asked of it elsewhere.
pub fn root_boundaries(
    places: &Places,
    roots: usize,
    public_note_root: u16,
    public_admitted_root: u16,
) -> Vec<Boundary> {
    let row = ((places.nodes() + places.depth) * period() - 1) as u64;
    let mut out = Vec::new();
    for j in 0..CAPACITY {
        out.push(Boundary {
            column: (roots + j) as u16,
            row,
            value: BoundaryValue::Word(public_note_root + 2 * j as u16),
        });
        out.push(Boundary {
            column: (roots + CAPACITY + j) as u16,
            row,
            value: BoundaryValue::Word(public_admitted_root + 2 * j as u16),
        });
    }
    out
}

// The boundaries of a redemption: the capacity every chain opens with, the padding of every chain,
// and the two values that stand outside — the root and the nullifier.
pub fn boundaries(places: &Places, public_nullifier: u16) -> Vec<Boundary> {
    let mut out = Vec::new();
    // The chains whose capacity is one value in both branches keep it as a boundary; the leaf, the
    // nodes of the walk and the chain of the nullifier open under the domain of their branch, and
    // their capacities are the rules of the capacity split rather than boundaries — a boundary
    // knows no branch. The paddings stay unconditional where the two branches absorb alike.
    let chains: [(Option<mt_codec::Domain>, usize, usize, usize); 3] = [
        (Some(domain::MT_KEY_HALVES), places.half(), 2 * CAPACITY, 0),
        (
            Some(domain::MT_NOTE_CM),
            places.commitment(),
            CAPACITY + 4 + 2 * CAPACITY + 2 * CAPACITY,
            CAPACITY,
        ),
        (None, places.leaf(), CAPACITY, CAPACITY),
    ];
    for (domain, first, elements, wired) in chains {
        if let Some(domain) = domain {
            let capacity = poseidon::capacity_of(domain);
            for (j, value) in capacity.iter().enumerate() {
                out.push(Boundary {
                    column: ring_column(RATE + j) as u16,
                    row: (first * period()) as u64,
                    value: BoundaryValue::Literal(value.as_u64()),
                });
            }
        }
        // The padding of the chain: the one element and the zeros after it. What stands before it
        // is either wired from a seam or held by nobody, since it is the secret of a person.
        let blocks = sponge::blocks_of(elements);
        for at in elements..blocks * RATE {
            if at < wired {
                continue;
            }
            let (block, slot) = (at / RATE, at % RATE);
            out.push(Boundary {
                column: ring_column(slot) as u16,
                row: ((first + block) * period()) as u64,
                value: if at == elements {
                    BoundaryValue::Literal(F::ONE.as_u64())
                } else {
                    BoundaryValue::Literal(0)
                },
            });
        }
    }
    // The nullifier the chain leaves is a rule of its branch and not a boundary of the ring: a
    // note's stands at the chain's last row and a right's at the end of its first block, and a
    // boundary knows no branch. What is pinned instead is the published value itself, into the
    // admitted root's lanes at both rows — see `nullifier_pin_boundaries`.
    let _ = public_nullifier;
    out
}

// The published nullifier of this redemption, pinned where the rules of the two branches read
// it: the row the right's first block ends on, and the row the whole chain ends on. Both pins
// stand in every frame whatever the branch, so nothing about a redemption says which row spoke.
pub fn nullifier_pin_boundaries(
    places: &Places,
    roots: usize,
    public_nullifier: u16,
) -> Vec<Boundary> {
    let of_the_right = ((places.nullifier() + 1) * period()) as u64;
    let of_the_note = ((places.nullifier() + places.nullifier_blocks()) * period() - 1) as u64;
    let mut out = Vec::new();
    for j in 0..CAPACITY {
        for row in [of_the_right, of_the_note] {
            out.push(Boundary {
                column: (roots + CAPACITY + j) as u16,
                row,
                value: BoundaryValue::Word(public_nullifier + 2 * j as u16),
            });
        }
    }
    out
}

// The rules that tie the published value to the trace, one per branch: a note's chain leaves it
// in the ring at its last row, a right's first squeeze leaves it at the seam before its second
// block. Each rule takes the half of the split whose schedule stands at its row.
pub fn published_nullifier_constraints(
    of_the_moment: &super::branch::Halves,
    of_the_second: &super::branch::Halves,
    roots: usize,
) -> Vec<Constraint> {
    let minus = F::ONE.negated();
    let mut out = Vec::new();
    for j in 0..CAPACITY {
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![
                        factor(of_the_moment.note, 0, 1),
                        factor(ring_column(j), 0, 1),
                    ],
                ),
                term(
                    minus,
                    vec![
                        factor(of_the_moment.note, 0, 1),
                        factor(roots + CAPACITY + j, 0, 1),
                    ],
                ),
            ],
        });
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![
                        factor(of_the_second.right, 0, 1),
                        factor(ring_column(j), 1, 1),
                    ],
                ),
                term(
                    minus,
                    vec![
                        factor(of_the_second.right, 0, 1),
                        factor(roots + CAPACITY + j, 1, 1),
                    ],
                ),
            ],
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::air::Description;
    use crate::notes;

    const DEPTH: usize = 4;
    const ROWS_LOG2: u8 = 12;

    fn held() -> Held {
        Held {
            nf_key: [0x33; 32],
            value: 5_000_000_000,
            note_pk: [0x22; 32],
            rcm: [0x88; 32],
            siblings: (0..DEPTH)
                .map(|i| poseidon::hash_bytes(domain::MT_NOTE_LEAF, &[0x40 + i as u8; 32]))
                .collect(),
            position: 11,
        }
    }

    fn places() -> Places {
        Places::of(0, DEPTH)
    }

    fn description() -> Description {
        let places = places();
        let mut held_description = permutation::description().expect("the permutation stands");
        held_description.rows_log2 = ROWS_LOG2;
        crate::circuit::widen(&mut held_description, TRACE_WIDTH);
        let base = TRACE_WIDTH + held_description.periodic.len();
        held_description
            .periodic
            .push(sponge::carry_column(ROWS_LOG2, &places.carry_rows()));
        held_description.periodic.extend(path::periodic_columns(
            ROWS_LOG2,
            &[places.level_rows()],
            &places.position_rows(),
        ));
        held_description
            .periodic
            .extend(periodic_columns(ROWS_LOG2, &places));
        held_description
            .constraints
            .extend(sponge::capacity_carries(base));
        held_description
            .constraints
            .extend(path::constraints(base + 1));
        held_description.constraints.extend(constraints(
            base + 1 + path::PERIODIC_COUNT,
            base + 1 + path::WRAP,
            &places,
        ));
        // The root a walk answers against is a rule of the frame and not a boundary of a
        // redemption — two trees stand and a boundary knows no branch — so what a redemption of
        // its own holds to the public input here is its nullifier alone. The root it reaches is
        // held by the test above, against the fold every machine computes. The capacities of the
        // branch-parted chains are the frame's split; a redemption standing alone is a note, and
        // holds them as the boundaries of its own branch.
        held_description.boundaries.extend(boundaries(&places, 0));
        for (domain, first) in [
            (domain::MT_NOTE_LEAF, places.leaf()),
            (domain::MT_NOTE_NF, places.nullifier()),
        ] {
            let capacity = poseidon::capacity_of(domain);
            for (j, value) in capacity.iter().enumerate() {
                held_description.boundaries.push(crate::air::Boundary {
                    column: ring_column(RATE + j) as u16,
                    row: (first * period()) as u64,
                    value: BoundaryValue::Literal(value.as_u64()),
                });
            }
        }
        held_description
            .boundaries
            .extend(path::boundaries(places.leaf(), places.depth));
        // A redemption standing alone is a note, and its published nullifier stands where the
        // note branch leaves it: the last row of its chain, held to the public input directly.
        let nullifier_row =
            ((places.nullifier() + places.nullifier_blocks()) * period() - 1) as u64;
        for j in 0..CAPACITY {
            held_description.boundaries.push(crate::air::Boundary {
                column: ring_column(j) as u16,
                row: nullifier_row,
                value: BoundaryValue::Word(2 * j as u16),
            });
        }
        held_description
    }

    fn trace() -> (Vec<Vec<F>>, Digest, Digest) {
        let places = places();
        let rows = 1usize << ROWS_LOG2;
        let mut columns = vec![vec![F::ZERO; rows]; TRACE_WIDTH];
        let (root, nullifier) =
            write_redemption(&mut columns, &places, &held()).expect("the redemption is written");
        for block in places.blocks()..rows / period() {
            permutation::write_block(&mut columns, block, &[F::ZERO; crate::poseidon::WIDTH])
                .expect("a block of the tail");
        }
        path::write_pairs(&mut columns);
        path::write_accumulator(
            &mut columns,
            &[places.level_rows()],
            &places.position_rows(),
        );
        write_lane(
            &mut columns,
            &places.load_rows(),
            &places.spending_rows(),
            &places.position_rows(),
        );
        (columns, root, nullifier)
    }

    fn public_of(nullifier: &Digest) -> Vec<u8> {
        let mut out = Vec::new();
        for cell in nullifier.elements() {
            out.extend_from_slice(&cell.as_u64().to_le_bytes());
        }
        out
    }

    #[test]
    fn the_derivations_of_the_circuit_are_the_derivations_of_a_note() {
        // The values the circuit reaches and the values every machine computes are one set. The
        // wrong implementation this refuses: one absorbing the limbs of a digest where the set
        // absorbs its words, which answers at no input at all and is invisible without this.
        let held = held();
        let (_, root, nullifier) = trace();
        let half = mt_derive::note::nf_pk(&held.nf_key);
        let commitment = mt_derive::note::commitment(held.value, &held.note_pk, &half, &held.rcm)
            .expect("a real half");
        let expected = mt_derive::note::nullifier(&held.nf_key, &commitment, held.position)
            .expect("a real commitment");
        assert_eq!(nullifier.bytes(), expected);
        // And the root is the walk of that commitment, folded by the doors of the tree.
        let mut current = notes::leaf_of(&Digest::of_bytes(&commitment).expect("a digest"));
        for (level, sibling) in held.siblings.iter().enumerate() {
            let (left, right) = if (held.position >> level) & 1 == 1 {
                (*sibling, current)
            } else {
                (current, *sibling)
            };
            current = notes::node(&left, &right);
        }
        assert_eq!(root, current);
    }

    #[test]
    fn the_trace_of_a_redemption_satisfies_its_description() {
        let held_description = description();
        held_description.check().expect("the description stands");
        let (trace, _root, nullifier) = trace();
        let public = poseidon::limbs_of(&public_of(&nullifier));
        assert!(held_description.satisfied_by(&trace, &public));
    }

    #[test]
    fn a_nullifier_of_another_note_is_not_satisfied() {
        let held_description = description();
        let (trace, _root, nullifier) = trace();
        let mut bytes = public_of(&nullifier);
        bytes[0] ^= 1;
        assert!(!held_description.satisfied_by(&trace, &poseidon::limbs_of(&bytes)));
    }

    #[test]
    fn a_lane_that_carries_another_commitment_is_not_satisfied() {
        // The one rule that carries a value across the walk, refused where it is broken: a lane
        // holding at the seam the nullifier reads from something the commitment never left.
        let held_description = description();
        let (mut trace, _root, nullifier) = trace();
        let public = poseidon::limbs_of(&public_of(&nullifier));
        assert!(held_description.satisfied_by(&trace, &public));
        let places = places();
        let seam = places.read_rows()[0];
        trace[LANE][seam] = trace[LANE][seam].plus(F::ONE);
        assert!(!held_description.satisfied_by(&trace, &public));
    }

    #[test]
    fn a_redemption_is_proven_and_verified_as_bytes() {
        let held_description = description();
        let (trace, _root, nullifier) = trace();
        let public = public_of(&nullifier);
        let bytes =
            crate::scheme::prove(&held_description, &public, &trace).expect("a true redemption");
        assert_eq!(
            crate::scheme::verify(&held_description, &public, &bytes),
            Ok(())
        );
        let mut other = public.clone();
        other[0] ^= 1;
        assert!(crate::scheme::verify(&held_description, &other, &bytes).is_err());
    }
}
