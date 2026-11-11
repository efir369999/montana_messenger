// The circuit of a ballot: a machine proves how many votes its standing drew in a window, and
// discloses nothing of the standing itself — neither how many census windows it lived, nor which,
// nor where in their cements it stood.
//
// **What a standing is, and why one machine can prove its own.** A unit of standing is a census
// window whose cement holds the part the machine's secret derives for that window. The part of a
// window names nobody and joins to nothing across windows, so the units of a machine are known to
// that machine alone; their sum over the electorate is not, and needs nobody: it is the sum of the
// counts of the census cements, which every proposal carries. The quorum of hidden weights that no
// prover could witness (WINDOW-RELATION.md, section 1) becomes a quorum of votes each machine
// witnesses for itself: a unit votes in a window when a coin drawn from the machine's spending half,
// the census window and the cemented aggregate of the window two before clears the threshold of the
// committee, and the ballot publishes the count and nothing else.
//
// **The shape.** One block for the part of the window the ballot answers to, then one run per census
// window: the part of that census, the leaf and the walk of its cement, and the coin. After each coin
// stands its comparison against the threshold, laid in rows the next run's blocks leave free in the
// columns of the comparison. Where the machine lived the census, the walk ends at that census's
// root; where it did not, the walk is free and the unit casts nothing. The bit that says which is
// held at the seam the walk ends at and carried in a lane to the comparison, and the borrow out of
// the comparison says whether the coin cleared: the vote of a unit is the product of the two, and
// the votes add in an accumulator whose last value is the public count.
//
// **Why the spending half and not the secret.** The ballot binds itself to the part of its window,
// and that part entered the cement only beside a proof of presence deriving it from the secret of an
// admitted machine. A spending half other than that machine's yielding the same part is a collision
// of the proof hash, so the half the ballot holds is the half the presence held, and the ballot
// reads no secret and walks no tree of admitted machines.

use super::compare::{self, Compared, COMPARED_BYTES};
use super::permutation::ring_column;
use super::sponge::{factor, term};
use super::{capacity, lane, path, permutation, sponge};
use crate::air::{Boundary, BoundaryValue, Constraint, Description, Periodic};
use crate::field::F;
use crate::poseidon::{self, Digest, CAPACITY, RATE, WIDTH};
use mt_codec::domain;

mt_codec::constants! {
    BALLOT:
    /// Where the marks of the votes stand among the periodic columns this layout adds: the seam a
    /// census walk ends at, and the row after a comparison, where its borrow out stands.
    pub const ROOT: usize = 0, code "the periodic column of this layout marking the seam a census walk ends at";
    pub const AFTER: usize = 1, code "the periodic column of this layout marking the row after a comparison, where its borrow out stands";
    pub const PERIODIC_COUNT: usize = 2, code "the count of the periodic columns this layout adds";
}

// The census windows a standing is counted over, read at one door: the Decree's row, and nothing
// for a Decree that names none.
pub fn censuses() -> Option<usize> {
    usize::try_from(mt_genesis::scalar("standing_censuses")?).ok()
}

// The limbs of the aggregate a coin absorbs beside the spending half and the census window.
fn aggregate_limbs() -> usize {
    poseidon::limbs_of(&[0u8; 32]).len()
}

// The elements a coin absorbs: the four cells of the spending half, the census window as one
// element, and the limbs of the aggregate.
fn coin_elements() -> usize {
    CAPACITY + 1 + aggregate_limbs()
}

// The four columns the votes take after the comparison: the bit a census walk ends with, the same
// bit carried to the comparison, the product of that bit and the borrow, and the running count.
#[derive(Clone, Copy, Debug)]
pub struct Votes {
    pub first: usize,
}

impl Votes {
    pub const fn after(width: usize) -> Self {
        Self { first: width }
    }

    pub const fn spike(&self) -> usize {
        self.first
    }

    pub const fn carried(&self) -> usize {
        self.first + 1
    }

    pub const fn product(&self) -> usize {
        self.first + 2
    }

    pub const fn count(&self) -> usize {
        self.first + 3
    }

    pub const fn width(&self) -> usize {
        self.first + 4
    }
}

// The columns of a ballot, in the order they stand: the walk, the lane of the spending half, the
// lane of the coin, the comparison and the votes.
#[derive(Clone, Copy, Debug)]
pub struct Columns {
    pub spending: lane::Places,
    pub coin: lane::Places,
    pub compared: Compared,
    pub votes: Votes,
}

impl Columns {
    pub fn of() -> Self {
        let spending = lane::Places::after(path::TRACE_WIDTH);
        let coin = lane::Places::after(spending.width());
        let compared = Compared::after(coin.width());
        let votes = Votes::after(compared.width());
        Self {
            spending,
            coin,
            compared,
            votes,
        }
    }

    pub fn width(&self) -> usize {
        self.votes.width()
    }
}

// How the blocks of a ballot stand. Block zero is idle so every chain has a seam before it.
#[derive(Clone, Copy, Debug)]
pub struct Places {
    pub censuses: usize,
}

impl Places {
    pub fn of(censuses: usize) -> Self {
        Self { censuses }
    }

    // The part of the window the ballot answers to: the spending half and the window.
    pub fn part(&self) -> usize {
        1
    }

    fn part_blocks(&self) -> usize {
        sponge::blocks_of(CAPACITY + 1)
    }

    fn leaf_blocks(&self) -> usize {
        sponge::blocks_of(CAPACITY)
    }

    pub fn coin_blocks(&self) -> usize {
        sponge::blocks_of(coin_elements())
    }

    pub fn depth(&self) -> usize {
        crate::tree_depth()
    }

    fn per_census(&self) -> usize {
        self.part_blocks() + self.leaf_blocks() + self.depth() + self.coin_blocks()
    }

    // The first block of the run of census `at`: the part of that census.
    pub fn census(&self, at: usize) -> usize {
        self.part() + self.part_blocks() + at * self.per_census()
    }

    pub fn leaf(&self, at: usize) -> usize {
        self.census(at) + self.part_blocks()
    }

    pub fn nodes(&self, at: usize) -> usize {
        self.leaf(at) + self.leaf_blocks()
    }

    pub fn coin(&self, at: usize) -> usize {
        self.nodes(at) + self.depth()
    }

    pub fn blocks(&self) -> usize {
        self.census(self.censuses)
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    // The seam the walk of census `at` ends at: the last row of its last node, where the root stands.
    pub fn root_seam(&self, at: usize) -> usize {
        self.seam_before(self.coin(at))
    }

    // The first row of the comparison of census `at`: the row after its coin, in the columns the
    // next run's blocks leave free.
    pub fn start(&self, at: usize) -> usize {
        (self.coin(at) + self.coin_blocks()) * permutation::period()
    }

    pub fn after(&self, at: usize) -> usize {
        compare::after_of(self.start(at))
    }

    // The row the count of votes is read at: one past the borrow out of the last comparison.
    pub fn counted(&self) -> usize {
        self.after(self.censuses - 1) + 1
    }

    pub fn levels(&self, at: usize) -> Vec<usize> {
        path::level_rows(self.nodes(at), self.depth())
    }

    pub fn carry_rows(&self) -> Vec<usize> {
        (0..self.censuses)
            .flat_map(|at| sponge::carry_rows(self.coin(at), self.coin_blocks()))
            .collect()
    }

    // The seams a part hands its digest to the leaf of its census over.
    pub fn digest_rows(&self) -> Vec<usize> {
        (0..self.censuses)
            .map(|at| self.seam_before(self.leaf(at)))
            .collect()
    }

    pub fn spending_wires(&self) -> Vec<usize> {
        let mut out = vec![self.seam_before(self.part())];
        for at in 0..self.censuses {
            out.push(self.seam_before(self.census(at)));
            out.push(self.seam_before(self.coin(at)));
        }
        out
    }

    pub fn coin_loads(&self) -> Vec<usize> {
        (0..self.censuses).map(|at| self.start(at) - 1).collect()
    }

    pub fn opens(&self) -> Vec<(usize, mt_codec::Domain)> {
        let mut out = vec![(self.seam_before(self.part()), domain::MT_PART_NF)];
        for at in 0..self.censuses {
            out.push((self.seam_before(self.census(at)), domain::MT_PART_NF));
            out.push((self.seam_before(self.leaf(at)), domain::MT_CEMENT_LEAF));
            for level in 0..self.depth() {
                out.push((
                    self.seam_before(self.nodes(at) + level),
                    domain::MT_CEMENT_NODE,
                ));
            }
            out.push((self.seam_before(self.coin(at)), domain::MT_VOTE));
        }
        out
    }
}

// Where each value of the public input stands, in limbs: the part, the window, the census windows,
// their roots, the aggregate, the threshold one byte to a limb, and the count of votes.
#[derive(Clone, Copy, Debug)]
pub struct Public {
    pub censuses: usize,
}

impl Public {
    const fn word() -> usize {
        2
    }

    const fn digest() -> usize {
        2 * CAPACITY
    }

    pub const fn part(&self) -> usize {
        0
    }

    pub const fn window(&self) -> usize {
        self.part() + Self::digest()
    }

    pub const fn census(&self, at: usize) -> usize {
        self.window() + Self::word() + at * Self::word()
    }

    pub const fn root(&self, at: usize) -> usize {
        self.census(self.censuses) + at * Self::digest()
    }

    pub const fn aggregate(&self) -> usize {
        self.root(self.censuses)
    }

    pub fn threshold(&self) -> usize {
        self.aggregate() + aggregate_limbs()
    }

    pub fn votes(&self) -> usize {
        self.threshold() + COMPARED_BYTES
    }
}

fn limb(index: usize) -> u16 {
    index as u16
}

fn boundaries(places: &Places, columns: &Columns) -> Vec<Boundary> {
    let public = Public {
        censuses: places.censuses,
    };
    let mut out = Vec::new();
    // The part of the window, at the seam its block ends at, and the window it absorbed.
    let part_end = places.seam_before(places.part() + places.part_blocks());
    for cell in 0..CAPACITY {
        out.push(Boundary {
            column: ring_column(cell) as u16,
            row: part_end as u64,
            value: BoundaryValue::Word(limb(public.part() + 2 * cell)),
        });
    }
    out.push(Boundary {
        column: ring_column(CAPACITY) as u16,
        row: (places.part() * permutation::period()) as u64,
        value: BoundaryValue::Word(limb(public.window())),
    });
    out.extend(sponge::padding_boundaries(places.part(), CAPACITY + 1));
    for at in 0..places.censuses {
        // The census window, absorbed by the part of that census and by its coin alike.
        for block in [places.census(at), places.coin(at)] {
            out.push(Boundary {
                column: ring_column(CAPACITY) as u16,
                row: (block * permutation::period()) as u64,
                value: BoundaryValue::Word(limb(public.census(at))),
            });
        }
        out.extend(sponge::padding_boundaries(places.census(at), CAPACITY + 1));
        out.extend(sponge::padding_boundaries(places.leaf(at), CAPACITY));
        // The root of that census's cement, in the sibling columns at the seam the walk ends at,
        // where no level reads them: the walk is bound to it exactly where the bit of the unit is.
        for cell in 0..CAPACITY {
            out.push(Boundary {
                column: (path::SIBLING + cell) as u16,
                row: places.root_seam(at) as u64,
                value: BoundaryValue::Word(limb(public.root(at) + 2 * cell)),
            });
        }
        // The limbs of the aggregate enter the coin after the spending half and the census window.
        let first = places.coin(at);
        for held in 0..aggregate_limbs() {
            let element = CAPACITY + 1 + held;
            out.push(Boundary {
                column: ring_column(element % RATE) as u16,
                row: ((first + element / RATE) * permutation::period()) as u64,
                value: BoundaryValue::Public(limb(public.aggregate() + held)),
            });
        }
        out.extend(sponge::padding_boundaries(first, coin_elements()));
        let start = places.start(at);
        out.extend(compare::threshold_boundaries(
            &columns.compared,
            start,
            |row| limb(public.threshold() + row),
        ));
        out.push(compare::borrow_in(&columns.compared, start));
        out.extend(compare::accumulators_open(&columns.compared, start));
    }
    // The count opens at nought and closes at the count the ballot publishes.
    out.push(Boundary {
        column: columns.votes.count() as u16,
        row: 0,
        value: BoundaryValue::Literal(0),
    });
    out.push(Boundary {
        column: columns.votes.count() as u16,
        row: places.counted() as u64,
        value: BoundaryValue::Word(limb(public.votes())),
    });
    out
}

fn mark_column(rows_log2: u8, rows: &[usize]) -> Periodic {
    sponge::carry_column(rows_log2, rows)
}

// The rules of the votes, over the columns and the marks the caller places them at.
fn vote_constraints(periodic_base: usize, votes: &Votes, borrow: usize) -> Vec<Constraint> {
    let root = periodic_base + ROOT;
    let after = periodic_base + AFTER;
    let minus = F::ONE.negated();
    let mut out = Vec::new();
    // The bit a walk ends with is a bit, and it stands nowhere but at the seam a walk ends at.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(votes.spike(), 0, 2)]),
            term(minus, vec![factor(votes.spike(), 0, 1)]),
        ],
    });
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(votes.spike(), 0, 1)]),
            term(minus, vec![factor(root, 0, 1), factor(votes.spike(), 0, 1)]),
        ],
    });
    // Where the bit stands, the root the walk reached is the root of the census: the bit times the
    // difference of the ring and the sibling columns, which hold that root at that seam alone.
    for cell in 0..CAPACITY {
        out.push(Constraint {
            degree: 2,
            terms: vec![
                term(
                    F::ONE,
                    vec![factor(votes.spike(), 0, 1), factor(ring_column(cell), 0, 1)],
                ),
                term(
                    minus,
                    vec![
                        factor(votes.spike(), 0, 1),
                        factor(path::SIBLING + cell, 0, 1),
                    ],
                ),
            ],
        });
    }
    // The bit carried to the comparison: taken at the seam a walk ends at, held everywhere else.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                F::ONE,
                vec![factor(root, 0, 1), factor(votes.carried(), 1, 1)],
            ),
            term(minus, vec![factor(root, 0, 1), factor(votes.spike(), 0, 1)]),
        ],
    });
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(votes.carried(), 1, 1)]),
            term(minus, vec![factor(votes.carried(), 0, 1)]),
            term(
                minus,
                vec![factor(root, 0, 1), factor(votes.carried(), 1, 1)],
            ),
            term(
                F::ONE,
                vec![factor(root, 0, 1), factor(votes.carried(), 0, 1)],
            ),
        ],
    });
    // The product of the carried bit and the borrow, at every row.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(votes.product(), 0, 1)]),
            term(
                minus,
                vec![factor(votes.carried(), 0, 1), factor(borrow, 0, 1)],
            ),
        ],
    });
    // The count: held everywhere, and at the row after a comparison it takes the vote of that unit —
    // the bit less the product, which is the bit where the coin cleared and nought where it did not.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(F::ONE, vec![factor(votes.count(), 1, 1)]),
            term(minus, vec![factor(votes.count(), 0, 1)]),
            term(
                minus,
                vec![factor(after, 0, 1), factor(votes.carried(), 0, 1)],
            ),
            term(
                F::ONE,
                vec![factor(after, 0, 1), factor(votes.product(), 0, 1)],
            ),
        ],
    });
    out
}

// The assembled shape, at the frame's height: the permutation base, the carries, the walks, the
// capacity wiring, the two lanes, the comparisons and the votes.
pub fn description() -> Option<Description> {
    let places = Places::of(censuses()?);
    if places.censuses == 0 {
        return None;
    }
    let columns = Columns::of();
    let rows_log2 = crate::params::ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    crate::circuit::widen(&mut held, columns.width());
    let base = columns.width() + held.periodic.len();
    let carry = base;
    let digest = base + 1;
    let walk = base + 2;
    let opens_at = walk + path::PERIODIC_COUNT;
    let spending_at = opens_at + capacity::PERIODIC_COUNT;
    let coin_at = spending_at + lane::PERIODIC_COUNT;
    let compared_at = coin_at + lane::PERIODIC_COUNT;
    let votes_at = compared_at + compare::PERIODIC_COUNT;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic
        .push(sponge::carry_column(rows_log2, &places.digest_rows()));
    let walks: Vec<Vec<usize>> = (0..places.censuses).map(|at| places.levels(at)).collect();
    held.periodic
        .extend(path::periodic_columns(rows_log2, &walks, &[]));
    held.periodic
        .extend(capacity::periodic_columns(rows_log2, &places.opens()));
    held.periodic.extend(lane::periodic_columns(
        rows_log2,
        &[],
        &places.spending_wires(),
    ));
    held.periodic
        .extend(lane::periodic_columns(rows_log2, &places.coin_loads(), &[]));
    let starts: Vec<usize> = (0..places.censuses).map(|at| places.start(at)).collect();
    held.periodic
        .extend(compare::periodic_columns(rows_log2, &starts));
    let roots: Vec<usize> = (0..places.censuses)
        .map(|at| places.root_seam(at))
        .collect();
    let afters: Vec<usize> = (0..places.censuses).map(|at| places.after(at)).collect();
    held.periodic.push(mark_column(rows_log2, &roots));
    held.periodic.push(mark_column(rows_log2, &afters));

    held.constraints.extend(sponge::capacity_carries(carry));
    held.constraints.extend(sponge::digest_carries(digest));
    held.constraints.extend(path::constraints(walk));
    held.constraints.extend(capacity::constraints(opens_at));
    held.constraints
        .extend(lane::constraints(spending_at, &columns.spending));
    held.constraints
        .extend(lane::constraints(coin_at, &columns.coin));
    held.constraints.extend(compare::constraints(
        compared_at,
        &columns.compared,
        &columns.coin,
    ));
    held.constraints.extend(vote_constraints(
        votes_at,
        &columns.votes,
        columns.compared.borrow(),
    ));
    held.boundaries.extend(boundaries(&places, &columns));
    Some(held)
}

// What a machine holds of one census window: the root of its cement, the window it stands for, and
// — where the machine lived it — the branch its part walks. A census it did not live is a unit that
// casts nothing, and its walk is free.
#[derive(Clone, Debug)]
pub struct Census {
    pub window: u64,
    pub root: Digest,
    pub branch: Option<(Vec<Digest>, u64)>,
}

// The coin a unit draws: the spending half, the census window as one element, and the limbs of the
// aggregate of the window two before.
pub fn coin_of(spending: &Digest, census: u64, aggregate: &[u8; 32]) -> Option<Digest> {
    let mut preimage = Vec::with_capacity(coin_elements());
    preimage.extend_from_slice(spending.elements());
    preimage.push(F::try_from_u64(census)?);
    preimage.extend(poseidon::limbs_of(aggregate));
    Some(poseidon::hash_elements(domain::MT_VOTE, &preimage))
}

// The part of a window a spending half derives: the nullifier of the machine's part.
pub fn part_of(spending: &Digest, window: u64) -> Option<Digest> {
    let mut preimage = Vec::with_capacity(CAPACITY + 1);
    preimage.extend_from_slice(spending.elements());
    preimage.push(F::try_from_u64(window)?);
    Some(poseidon::hash_elements(domain::MT_PART_NF, &preimage))
}

// The votes a standing draws, computed outside the circuit as the circuit computes them: a unit votes
// where the machine lived its census and its coin clears the threshold.
pub fn votes_of(
    spending: &Digest,
    censuses: &[Census],
    aggregate: &[u8; 32],
    threshold: &[u8; 32],
) -> Option<u64> {
    let mut votes = 0u64;
    for census in censuses {
        if census.branch.is_none() {
            continue;
        }
        let coin = coin_of(spending, census.window, aggregate)?;
        if coin.bytes() < *threshold {
            votes += 1;
        }
    }
    Some(votes)
}

// The trace of a ballot. It answers with nothing where a branch it is handed does not reach the
// root of its census: a trace of a false statement is not written.
pub fn trace_of(
    spending: &Digest,
    window: u64,
    censuses: &[Census],
    aggregate: &[u8; 32],
    threshold: &[u8; 32],
) -> Option<(Vec<Vec<F>>, Digest, u64)> {
    let places = Places::of(censuses.len());
    if Some(places.censuses) != self::censuses() {
        return None;
    }
    let columns = Columns::of();
    let rows = 1usize << crate::params::ROWS_LOG2;
    let mut trace = vec![vec![F::ZERO; rows]; columns.width()];
    let period = permutation::period();

    // The part of the window.
    let mut preimage = Vec::with_capacity(CAPACITY + 1);
    preimage.extend_from_slice(spending.elements());
    preimage.push(F::try_from_u64(window)?);
    for (at, state) in sponge::chain(domain::MT_PART_NF, &preimage)
        .iter()
        .enumerate()
    {
        permutation::write_block(&mut trace, places.part() + at, state)?;
    }
    let part = poseidon::hash_elements(domain::MT_PART_NF, &preimage);

    let mut votes = 0u64;
    let mut carried = F::ZERO;
    let mut carried_from = 0usize;
    for (at, census) in censuses.iter().enumerate() {
        // The part of that census, and the walk of its cement under it.
        let mut preimage = Vec::with_capacity(CAPACITY + 1);
        preimage.extend_from_slice(spending.elements());
        preimage.push(F::try_from_u64(census.window)?);
        for (offset, state) in sponge::chain(domain::MT_PART_NF, &preimage)
            .iter()
            .enumerate()
        {
            permutation::write_block(&mut trace, places.census(at) + offset, state)?;
        }
        let of_the_census = poseidon::hash_elements(domain::MT_PART_NF, &preimage);
        let depth = places.depth();
        let empties = crate::cement::empty_internals(depth);
        let (siblings, position, lived) = match &census.branch {
            Some((siblings, position)) => (siblings.clone(), *position, true),
            None => (empties[..depth].to_vec(), 0, false),
        };
        if siblings.len() != depth {
            return None;
        }
        let reached = path::write_walk_under(
            &mut trace,
            places.leaf(at),
            &of_the_census,
            &siblings,
            position,
            domain::MT_CEMENT_LEAF,
            domain::MT_CEMENT_NODE,
        )?;
        if lived && reached != census.root {
            return None;
        }
        let seam = places.root_seam(at);
        for cell in 0..CAPACITY {
            trace[path::SIBLING + cell][seam] = census.root.elements()[cell];
        }
        let bit = if lived { F::ONE } else { F::ZERO };
        trace[columns.votes.spike()][seam] = bit;
        trace[columns.votes.carried()][carried_from..=seam].fill(carried);
        carried = bit;
        carried_from = seam + 1;

        // The coin, and its comparison in the rows after it.
        let coin = coin_of(spending, census.window, aggregate)?;
        let mut preimage = Vec::with_capacity(coin_elements());
        preimage.extend_from_slice(spending.elements());
        preimage.push(F::try_from_u64(census.window)?);
        preimage.extend(poseidon::limbs_of(aggregate));
        for (offset, state) in sponge::chain(domain::MT_VOTE, &preimage).iter().enumerate() {
            permutation::write_block(&mut trace, places.coin(at) + offset, state)?;
        }
        let borrow = compare::write(
            &mut trace,
            &columns.compared,
            places.start(at),
            &coin.bytes(),
            threshold,
        );
        if lived && borrow == 0 {
            votes += 1;
        }
    }
    trace[columns.votes.carried()][carried_from..].fill(carried);

    // The lanes: the spending half constant along the whole trace, and each coin from the row after
    // its chain ends until the next coin is loaded.
    for cell in 0..CAPACITY {
        let value = spending.elements()[cell];
        for slot in trace[columns.spending.cell(cell)].iter_mut() {
            *slot = value;
        }
    }
    // A coin is loaded at the last row of its chain and stands in the lane from the row after it,
    // so the rows up to a load carry the coin before it.
    let mut held = [F::ZERO; CAPACITY];
    let mut from = 0usize;
    for load in places.coin_loads() {
        for (cell, value) in held.iter().enumerate() {
            trace[columns.coin.cell(cell)][from..=load].fill(*value);
        }
        for (cell, slot) in held.iter_mut().enumerate() {
            *slot = trace[ring_column(cell)][load];
        }
        from = load + 1;
    }
    for (cell, value) in held.iter().enumerate() {
        trace[columns.coin.cell(cell)][from..].fill(*value);
    }

    write_votes(&mut trace, &places, &columns);

    // An idle block is not a row of zeros: the permutation's own rules speak at every block.
    let mut written = std::collections::BTreeSet::new();
    written.insert(places.part());
    for at in 0..places.censuses {
        for block in places.census(at)..places.census(at) + places.per_census() {
            written.insert(block);
        }
    }
    for block in 0..rows / period {
        if !written.contains(&block) {
            permutation::write_block(&mut trace, block, &[F::ZERO; WIDTH])?;
        }
    }
    path::write_pairs(&mut trace);
    let walks: Vec<Vec<usize>> = (0..places.censuses).map(|at| places.levels(at)).collect();
    path::write_accumulator(&mut trace, &walks, &[]);
    Some((trace, part, votes))
}

// The product and the count, row by row, as the rules say them, out of the carried bit and the
// borrows the trace already holds.
fn write_votes(trace: &mut [Vec<F>], places: &Places, columns: &Columns) {
    let afters: std::collections::BTreeSet<usize> =
        (0..places.censuses).map(|at| places.after(at)).collect();
    let products: Vec<F> = trace[columns.votes.carried()]
        .iter()
        .zip(&trace[columns.compared.borrow()])
        .map(|(carried, borrow)| carried.times(*borrow))
        .collect();
    let mut count = F::ZERO;
    let counts: Vec<F> = products
        .iter()
        .zip(&trace[columns.votes.carried()])
        .enumerate()
        .map(|(row, (product, carried))| {
            let here = count;
            if afters.contains(&row) {
                count = count.plus(*carried).minus(*product);
            }
            here
        })
        .collect();
    trace[columns.votes.product()] = products;
    trace[columns.votes.count()] = counts;
}

// The public input in the order the set states: the part, the window, the census windows, their
// roots, the aggregate, the threshold one byte to a limb in the order of the rows of a comparison,
// and the count of votes.
pub fn public_of(
    part: &Digest,
    window: u64,
    censuses: &[(u64, Digest)],
    aggregate: &[u8; 32],
    threshold: &[u8; 32],
    votes: u64,
) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&part.bytes());
    out.extend_from_slice(&window.to_le_bytes());
    for (census, _) in censuses {
        out.extend_from_slice(&census.to_le_bytes());
    }
    for (_, root) in censuses {
        out.extend_from_slice(&root.bytes());
    }
    out.extend_from_slice(aggregate);
    for at in 0..COMPARED_BYTES {
        let word = CAPACITY - 1 - at / compare::BYTES_OF_A_WORD;
        let byte = compare::BYTES_OF_A_WORD - 1 - at % compare::BYTES_OF_A_WORD;
        out.extend_from_slice(
            &u32::from(threshold[word * compare::BYTES_OF_A_WORD + byte]).to_le_bytes(),
        );
    }
    out.extend_from_slice(&votes.to_le_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const WINDOW: u64 = 50_000;

    fn spending_of(secret: &[u8; 32]) -> Digest {
        poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &poseidon::limbs_of(secret)).0
    }

    // A standing over the census windows of the window two before: five strangers' parts in every
    // census cement, and the machine's own in every census but one in three. The machine lived seven
    // of ten, so a ballot counting every census rather than those lived is a different count.
    fn a_standing(spending: &Digest) -> Vec<Census> {
        let interval = mt_genesis::scalar("census_interval").expect("the Decree names it");
        let newest = (WINDOW - 2) / interval * interval;
        let depth = crate::tree_depth();
        (0..censuses().expect("the Decree names it"))
            .map(|at| {
                let window = newest - at as u64 * interval;
                let mut parts: Vec<[u8; 32]> = (0..5u8)
                    .map(|i| poseidon::hash_bytes(domain::MT_PART_NF, &[i, at as u8, 7, 7]).bytes())
                    .collect();
                let mine = part_of(spending, window)
                    .expect("a window of the field")
                    .bytes();
                let lived = at % 3 != 1;
                if lived {
                    parts.push(mine);
                }
                parts.sort_unstable();
                let root = crate::cement::root_of(&parts, depth).expect("distinct ascending parts");
                let branch = if lived {
                    crate::cement::branch_of(&parts, &mine, depth)
                } else {
                    None
                };
                Census {
                    window,
                    root,
                    branch,
                }
            })
            .collect()
    }

    fn pairs(censuses: &[Census]) -> Vec<(u64, Digest)> {
        censuses.iter().map(|c| (c.window, c.root)).collect()
    }

    // A threshold that halves the width: a coin clears when its first byte stands below 0x80.
    fn half() -> [u8; 32] {
        let mut out = [0u8; 32];
        out[0] = 0x80;
        out
    }

    // The rules of the votes stand last in the description: the bit, the bit at the seam alone, one
    // rule of the root per cell, the carried bit twice, the product and the count.
    fn root_rules(held: &Description) -> std::ops::Range<usize> {
        let last = held.constraints.len() - 4;
        last - CAPACITY..last
    }

    fn broken_rules(
        held: &Description,
        trace: &[Vec<F>],
        rules: std::ops::Range<usize>,
    ) -> Vec<(usize, u64)> {
        let mut out = Vec::new();
        for at in rules {
            for row in 0..held.live_rows() - 1 {
                if !held.evaluate(trace, at, row).is_zero() {
                    out.push((at, row));
                    break;
                }
            }
        }
        out
    }

    #[test]
    fn the_runs_of_a_ballot_fit_its_height_and_its_bounds() {
        let held = description().expect("the description stands");
        let places = Places::of(censuses().expect("the Decree names it"));
        assert!(usize::from(held.trace_width) <= crate::params::TRACE_WIDTH_BOUND);
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
        assert_eq!(held.rows_log2, crate::params::ROWS_LOG2);
        // The count is read before the free block, so every row a rule or a boundary speaks at is
        // a live row.
        assert!(
            (places.counted() as u64) + 1 < held.live_rows(),
            "the count reaches into the free block"
        );
        held.check().expect("the description passes its own checks");
    }

    // An honest ballot satisfies its description at both thresholds and publishes the count the
    // derivation outside the circuit computes: every lived unit at a threshold of everything, some
    // of them at half. The named wrong implementation counts the censuses it did not live — ten
    // where the machine lived seven.
    #[test]
    fn an_honest_ballot_counts_the_lived_units_whose_coin_clears() {
        let spending = spending_of(&[0x5Au8; 32]);
        let censuses = a_standing(&spending);
        let lived = censuses.iter().filter(|c| c.branch.is_some()).count() as u64;
        assert!(lived < censuses.len() as u64);
        let aggregate = [0x33u8; 32];
        let held = description().expect("the description stands");
        for (threshold, everything) in [([0xFFu8; 32], true), (half(), false)] {
            let (trace, part, votes) =
                trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
                    .expect("an honest ballot");
            assert_eq!(
                part,
                part_of(&spending, WINDOW).expect("a window of the field")
            );
            assert_eq!(
                Some(votes),
                votes_of(&spending, &censuses, &aggregate, &threshold)
            );
            if everything {
                assert_eq!(votes, lived);
            }
            let public = public_of(
                &part,
                WINDOW,
                &pairs(&censuses),
                &aggregate,
                &threshold,
                votes,
            );
            let broken = broken_rules(&held, &trace, 0..held.constraints.len());
            assert!(broken.is_empty(), "rules broken at: {broken:?}");
            assert!(held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
        }
    }

    // What the ballot publishes binds it: one vote more or one less, a census root moved onto
    // another census, a census window moved, another aggregate and another window are statements
    // the trace does not make.
    #[test]
    fn a_ballot_refuses_every_public_value_it_did_not_count() {
        let spending = spending_of(&[0x5Au8; 32]);
        let censuses = a_standing(&spending);
        let aggregate = [0x33u8; 32];
        let threshold = [0xFFu8; 32];
        let held = description().expect("the description stands");
        let (trace, part, votes) = trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
            .expect("an honest ballot");
        assert!(votes > 0);
        let named = pairs(&censuses);
        let refused = |public: Vec<u8>| !held.satisfied_by(&trace, &poseidon::limbs_of(&public));
        assert!(refused(public_of(
            &part,
            WINDOW,
            &named,
            &aggregate,
            &threshold,
            votes + 1
        )));
        assert!(refused(public_of(
            &part,
            WINDOW,
            &named,
            &aggregate,
            &threshold,
            votes - 1
        )));
        let mut moved = named.clone();
        moved[0].1 = moved[1].1;
        assert!(refused(public_of(
            &part, WINDOW, &moved, &aggregate, &threshold, votes
        )));
        let mut shifted = named.clone();
        shifted[0].0 += 1;
        assert!(refused(public_of(
            &part, WINDOW, &shifted, &aggregate, &threshold, votes
        )));
        assert!(refused(public_of(
            &part,
            WINDOW,
            &named,
            &[0x34u8; 32],
            &threshold,
            votes
        )));
        assert!(refused(public_of(
            &part,
            WINDOW + 1,
            &named,
            &aggregate,
            &threshold,
            votes
        )));
    }

    // The comparison is strict: a threshold at a lived unit's coin leaves that unit without a vote,
    // and one above it gives it one. The named wrong implementation compares at or below.
    #[test]
    fn a_coin_votes_below_the_threshold_and_never_at_it() {
        let spending = spending_of(&[0x5Au8; 32]);
        let censuses = a_standing(&spending);
        let aggregate = [0x33u8; 32];
        let lived = censuses
            .iter()
            .find(|c| c.branch.is_some())
            .expect("a lived census");
        let at = coin_of(&spending, lived.window, &aggregate)
            .expect("a window of the field")
            .bytes();
        let mut above = at;
        for byte in above.iter_mut().rev() {
            let (sum, carried) = byte.overflowing_add(1);
            *byte = sum;
            if !carried {
                break;
            }
        }
        let held = description().expect("the description stands");
        let mut counted = Vec::new();
        for threshold in [at, above] {
            let (trace, part, votes) =
                trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
                    .expect("an honest ballot");
            let public = public_of(
                &part,
                WINDOW,
                &pairs(&censuses),
                &aggregate,
                &threshold,
                votes,
            );
            assert!(held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
            counted.push(votes);
        }
        assert_eq!(counted[1], counted[0] + 1);
    }

    // A census the machine did not live casts nothing, whatever the trace says of it. The honest
    // writer refuses a branch that does not reach the root; and a trace forged around the free walk,
    // with the bit raised at its seam and the carried bit, the product and the count rewritten to
    // agree, breaks the rule of the root at that seam and no rule of the votes besides. The named
    // wrong implementation binds the root nowhere and counts the forged vote.
    #[test]
    fn a_census_not_lived_casts_nothing() {
        let spending = spending_of(&[0x5Au8; 32]);
        let censuses = a_standing(&spending);
        let aggregate = [0x33u8; 32];
        let threshold = [0xFFu8; 32];
        let depth = crate::tree_depth();
        let not_lived = censuses
            .iter()
            .position(|c| c.branch.is_none())
            .expect("a census not lived");
        let mut claimed = censuses.clone();
        claimed[not_lived].branch =
            Some((crate::cement::empty_internals(depth)[..depth].to_vec(), 0));
        assert!(trace_of(&spending, WINDOW, &claimed, &aggregate, &threshold).is_none());

        let (mut trace, part, votes) =
            trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
                .expect("an honest ballot");
        let places = Places::of(censuses.len());
        let columns = Columns::of();
        let seam = places.root_seam(not_lived);
        trace[columns.votes.spike()][seam] = F::ONE;
        trace[columns.votes.carried()][seam + 1..=places.root_seam(not_lived + 1)].fill(F::ONE);
        write_votes(&mut trace, &places, &columns);
        let held = description().expect("the description stands");
        let roots = root_rules(&held);
        let broken = broken_rules(&held, &trace, roots.start - 2..held.constraints.len());
        assert!(!broken.is_empty(), "the forged vote stands");
        assert!(
            broken
                .iter()
                .all(|(rule, row)| roots.contains(rule) && *row == seam as u64),
            "the forgery breaks another rule than the root at its seam: {broken:?}"
        );
        let public = public_of(
            &part,
            WINDOW,
            &pairs(&censuses),
            &aggregate,
            &threshold,
            votes + 1,
        );
        assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    }

    #[test]
    fn a_ballot_is_proven_and_verified_end_to_end() {
        let spending = spending_of(&[0x5Au8; 32]);
        let censuses = a_standing(&spending);
        let aggregate = [0x33u8; 32];
        let threshold = half();
        let held = description().expect("the description stands");
        let (trace, part, votes) = trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
            .expect("an honest ballot");
        let named = pairs(&censuses);
        let public = public_of(&part, WINDOW, &named, &aggregate, &threshold, votes);
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true ballot proves");
        assert_eq!(
            bytes.len(),
            crate::params::Shape::of_rows_log2(u32::from(crate::params::ROWS_LOG2))
                .expect("the height stands")
                .proof_bytes()
        );
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));
        let more = public_of(&part, WINDOW, &named, &aggregate, &threshold, votes + 1);
        assert!(crate::scheme::verify(&held, &more, &bytes).is_err());
        let other = public_of(&part, WINDOW, &named, &[0x34u8; 32], &threshold, votes);
        assert!(crate::scheme::verify(&held, &other, &bytes).is_err());
    }
}
