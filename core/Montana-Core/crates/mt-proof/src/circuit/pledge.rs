// The circuit of a pledge: a machine proves that the value its pledge carries is the line of its
// slot at the abscissa of the name it pledges, drawn from the same half of its secret the nullifier
// of its part is drawn from, and discloses neither half, the lock-opening value nor the slope (Canon,
// "The pledge of a part", "What its proof asserts").
//
// **Why a point of a line needs a proof.** Two pledges of one slot on two names give the
// lock-opening value of their machine only if both points stand on its line. A value nobody proves is
// a value anyone writes, and two written values extract a number that opens nothing. So the proof
// binds the point to the half the part is named by: one absorption of the secret, one lane out of it
// into every derivation that takes the half.
//
// **The shape.** Five chains laid one after another, rows and not columns, each opening under its
// own domain through the capacity wiring, as the presence lays its own: the halves of the secret,
// absorbed once and squeezed twice; the nullifier of the part over the spending half and the window;
// the lock-opening value over the spending half alone; the slope over the spending half, the window
// and the slot; and the abscissa over the eight limbs of the name. The lane carries the spending half
// into the first three derivations. What is no chain is twenty held columns: the four coefficients of
// the opening, the slope, the abscissa and the value in the field of the line, and the slot — its
// attempt, its `since`, its kind and the inverse that decides the kind. A column held equal to itself
// one row on is one value across every row a rule reaches; a load ties it to the digest its chain
// leaves, and the rule of the line ties the four elements together.

use super::permutation::{self, ring_column};
use super::presence::PRESENCE_ROWS_LOG2;
use super::sponge::{factor, term};
use super::{capacity, lane, sponge};
use crate::air::{Boundary, BoundaryValue, Constraint, Description};
use crate::field::F;
use crate::line::{self, L};
use crate::poseidon::{self, Digest, CAPACITY, RATE, WIDTH};
use mt_codec::{domain, Domain};

mt_codec::constants! {
    PLEDGE:
    /// Where each field of the public input stands, in limbs of four bytes, in the order the layout
    /// of a pledge carries them: `window`, `attempt`, `name`, `since`, `part_nullifier`,
    /// `line_value`.
    const WINDOW: u16 = 0, code "the first limb of the window in the public input of a pledge";
    const ATTEMPT: u16 = 2, code "the limb of the attempt in the public input of a pledge, after the two of the window";
    const NAME: u16 = 3, code "the first of the eight limbs of the name in the public input of a pledge";
    const SINCE: u16 = 11, code "the limb of `since` in the public input of a pledge, after the eight of the name";
    const PART_NULLIFIER: u16 = 12, code "the first of the eight limbs of the nullifier of the part in the public input of a pledge";
    const LINE_VALUE: u16 = 20, code "the first limb of the value of the line in the public input of a pledge, after the eight of the nullifier";
    /// The held columns: four elements of the line, a digest wide each, and the four cells of the
    /// slot.
    const HELD: usize = 4 * CAPACITY + 4, code "the held columns of a pledge: the opening, the slope, the abscissa and the value of the line, a digest wide each, and the four cells of the slot";
}

// How the blocks of a pledge stand. Block zero is idle so every chain has a seam before it.
#[derive(Clone, Copy, Debug)]
pub struct Places;

impl Places {
    pub fn halves(&self) -> usize {
        1
    }

    // The absorption of the secret, and one block more for the second squeeze, as the presence's.
    pub fn halves_blocks(&self) -> usize {
        sponge::blocks_of(Self::limbs_of_32()) + 1
    }

    pub fn nullifier(&self) -> usize {
        self.halves() + self.halves_blocks()
    }

    pub fn nullifier_blocks(&self) -> usize {
        sponge::blocks_of(CAPACITY + 1)
    }

    pub fn opening(&self) -> usize {
        self.nullifier() + self.nullifier_blocks()
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
        sponge::blocks_of(Self::limbs_of_32())
    }

    pub fn blocks(&self) -> usize {
        self.abscissa() + self.abscissa_blocks()
    }

    // A secret and a name are thirty-two bytes each, eight limbs.
    fn limbs_of_32() -> usize {
        poseidon::limbs_of(&[0u8; 32]).len()
    }

    fn seam_before(&self, block: usize) -> usize {
        block * permutation::period() - 1
    }

    // Each chain as it stands: its first block, its blocks, the domain it opens under and the count
    // of the elements it absorbs. The halves count one block more than they absorb.
    fn chains(&self) -> [(usize, usize, Domain, usize); 5] {
        [
            (
                self.halves(),
                self.halves_blocks(),
                domain::MT_KEY_HALVES,
                Self::limbs_of_32(),
            ),
            (
                self.nullifier(),
                self.nullifier_blocks(),
                domain::MT_PART_NF,
                CAPACITY + 1,
            ),
            (
                self.opening(),
                self.opening_blocks(),
                domain::MT_LINE_OPENING,
                CAPACITY,
            ),
            (
                self.slope(),
                self.slope_blocks(),
                domain::MT_LINE_SLOPE,
                CAPACITY + 2,
            ),
            (
                self.abscissa(),
                self.abscissa_blocks(),
                domain::MT_LINE_ABSCISSA,
                Self::limbs_of_32(),
            ),
        ]
    }

    // Every chain carries across its own blocks; the seam of the second squeeze is one of them, and
    // its rate crosses beside its capacity by the rule that stands with the squeeze.
    pub fn carry_rows(&self) -> Vec<usize> {
        let mut out = Vec::new();
        for (first, blocks, _, _) in self.chains() {
            out.extend(sponge::carry_rows(first, blocks));
        }
        out
    }

    pub fn squeeze_rows(&self) -> Vec<usize> {
        sponge::squeeze_rows(self.halves(), self.halves_blocks() - 1)
    }

    pub fn opens(&self) -> Vec<(usize, Domain)> {
        let mut out = Vec::new();
        for (first, _, domain, _) in self.chains() {
            out.push((self.seam_before(first), domain));
        }
        out
    }

    // The lane picks the spending half up where the absorption of the secret leaves it, before the
    // block of the second squeeze, and hands it to the three derivations that take it.
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
    // chain. The first is the seam before the slope, where the slot enters it as well.
    pub fn loads(&self) -> [usize; 3] {
        [
            self.seam_before(self.slope()),
            self.seam_before(self.abscissa()),
            self.seam_before(self.blocks()),
        ]
    }

    pub fn boundaries(&self, held: &Held) -> Vec<Boundary> {
        let period = permutation::period();
        let mut out = Vec::new();
        // The window is verifier input, one element in the nullifier of the part and in the slope: a
        // private window would draw the slope of one window under the part of another.
        for block in [self.nullifier(), self.slope()] {
            out.push(Boundary {
                column: ring_column(CAPACITY) as u16,
                row: (block * period) as u64,
                value: BoundaryValue::Word(WINDOW),
            });
        }
        out.push(Boundary {
            column: held.attempt() as u16,
            row: 0,
            value: BoundaryValue::Public(ATTEMPT),
        });
        out.push(Boundary {
            column: held.since() as u16,
            row: 0,
            value: BoundaryValue::Public(SINCE),
        });
        // The name, absorbed as its eight limbs.
        for at in 0..Self::limbs_of_32() {
            out.push(Boundary {
                column: ring_column(at % RATE) as u16,
                row: ((self.abscissa() + at / RATE) * period) as u64,
                value: BoundaryValue::Public(NAME + at as u16),
            });
        }
        // The nullifier of the part where its chain leaves it, and the value of the line.
        for cell in 0..CAPACITY {
            out.push(Boundary {
                column: ring_column(cell) as u16,
                row: self.seam_before(self.opening()) as u64,
                value: BoundaryValue::Word(PART_NULLIFIER + 2 * cell as u16),
            });
        }
        for cell in 0..CAPACITY {
            out.push(Boundary {
                column: held.value(cell) as u16,
                row: 0,
                value: BoundaryValue::Word(LINE_VALUE + 2 * cell as u16),
            });
        }
        for (first, _, _, elements) in self.chains() {
            out.extend(sponge::padding_boundaries(first, elements));
        }
        out
    }
}

// The held columns, standing after the lane.
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

    pub const fn attempt(&self) -> usize {
        self.first + 4 * CAPACITY
    }

    pub const fn since(&self) -> usize {
        self.attempt() + 1
    }

    pub const fn kind(&self) -> usize {
        self.attempt() + 2
    }

    pub const fn inverse(&self) -> usize {
        self.attempt() + 3
    }

    pub const fn width(&self) -> usize {
        self.first + HELD
    }
}

// The kind of a pledge from its attempt and its `since`, or nothing where the pledge is refused as it
// is read (Canon, "Invariants of a pledge"): closing where `since` equals the attempt, open where it
// stands below or is `0xFFFFFFFF`; refused where it stands above and is not `0xFFFFFFFF`, where the
// attempt is `0xFFFFFFFF`, and for an open pledge of attempt zero, the heavy attestation being the
// one open object of that attempt. The proof asserts the kind and not these refusals.
pub fn kind_of(attempt: u32, since: u32) -> Option<bool> {
    if attempt == u32::MAX {
        return None;
    }
    if since == attempt {
        return Some(true);
    }
    if since > attempt && since != u32::MAX {
        return None;
    }
    (attempt != 0).then_some(false)
}

// The assembled shape: the permutation base at the presence's height, the carries, the capacity
// wiring, the lane, and the rules of the held columns.
pub fn description() -> Option<Description> {
    assembled(&Places.lane_wires())
}

fn assembled(wires: &[usize]) -> Option<Description> {
    let places = Places;
    let rows_log2 = PRESENCE_ROWS_LOG2;
    let mut held = permutation::description()?;
    held.rows_log2 = rows_log2;
    let lane_places = lane::Places::after(permutation::TRACE_WIDTH);
    let columns = Held::after(lane_places.width());
    let width = columns.width();
    crate::circuit::widen(&mut held, width);
    let base = width + held.periodic.len();
    let carry = base;
    let squeeze = base + 1;
    let opens_at = base + 2;
    let lane_at = opens_at + capacity::PERIODIC_COUNT;
    let loads_at = lane_at + lane::PERIODIC_COUNT;

    held.periodic
        .push(sponge::carry_column(rows_log2, &places.carry_rows()));
    held.periodic
        .push(sponge::carry_column(rows_log2, &places.squeeze_rows()));
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
    held.constraints.extend(capacity::constraints(opens_at));
    held.constraints
        .extend(lane::constraints(lane_at, &lane_places));
    held.constraints.extend(constraints(loads_at, &columns));
    held.boundaries.extend(places.boundaries(&columns));
    Some(held)
}

// The rules of the held columns, in the order they stand: each held column is itself one row on;
// the three loads; the two rules of the slot; the slot entering the slope; and the line.
fn constraints(marks: usize, held: &Held) -> Vec<Constraint> {
    let one = F::ONE;
    let minus = F::ONE.negated();
    let mut out = holds(held.first..held.width());
    out.extend(loads(
        marks,
        [held.opening(0), held.slope(0), held.abscissa(0)],
    ));
    // The kind: `(since − attempt)·kind = 0` and `kind − 1 + (since − attempt)·inverse = 0`. Where
    // `since` is the attempt the second forces the kind to one; anywhere else the first forces it to
    // zero, and the inverse is what lets the second hold.
    let (attempt, since, kind, inverse) =
        (held.attempt(), held.since(), held.kind(), held.inverse());
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(one, vec![factor(since, 0, 1), factor(kind, 0, 1)]),
            term(minus, vec![factor(attempt, 0, 1), factor(kind, 0, 1)]),
        ],
    });
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(one, vec![factor(kind, 0, 1)]),
            term(minus, Vec::new()),
            term(one, vec![factor(since, 0, 1), factor(inverse, 0, 1)]),
            term(minus, vec![factor(attempt, 0, 1), factor(inverse, 0, 1)]),
        ],
    });
    // The slot `2·attempt + kind` is the element the slope absorbs after the window.
    out.push(Constraint {
        degree: 2,
        terms: vec![
            term(
                one,
                vec![factor(marks, 0, 1), factor(ring_column(CAPACITY + 1), 1, 1)],
            ),
            term(
                F::from_u64_reduced(2).negated(),
                vec![factor(marks, 0, 1), factor(attempt, 0, 1)],
            ),
            term(minus, vec![factor(marks, 0, 1), factor(kind, 0, 1)]),
        ],
    });
    out.extend(the_line(
        held.opening(0),
        held.slope(0),
        held.abscissa(0),
        held.value(0),
    ));
    out
}

// Each held column is itself one row on: one value across every row a rule reaches. The presence
// holds its line by the same rule (record 309).
pub(super) fn holds(columns: std::ops::Range<usize>) -> Vec<Constraint> {
    columns
        .map(|column| Constraint {
            degree: 1,
            terms: vec![
                term(F::ONE, vec![factor(column, 1, 1)]),
                term(F::ONE.negated(), vec![factor(column, 0, 1)]),
            ],
        })
        .collect()
}

// At the last row of a chain the ring holds its digest, and the held element is that digest: the
// opening, the slope and the abscissa, each under its own mark — the three periodic columns from
// `marks` on — and each a digest wide from the column given.
pub(super) fn loads(marks: usize, firsts: [usize; 3]) -> Vec<Constraint> {
    let (one, minus) = (F::ONE, F::ONE.negated());
    let mut out = Vec::new();
    for (mark, first) in (marks..).zip(firsts) {
        for cell in 0..CAPACITY {
            out.push(Constraint {
                degree: 2,
                terms: vec![
                    term(one, vec![factor(mark, 0, 1), factor(first + cell, 0, 1)]),
                    term(
                        minus,
                        vec![factor(mark, 0, 1), factor(ring_column(cell), 0, 1)],
                    ),
                ],
            });
        }
    }
    out
}

// The line: `value = opening + slope·abscissa` in `F[X] / (X⁴ − 7)`, coefficient by coefficient,
// the products at or above the fourth degree folded back by the residue. Each argument is the first
// of four held columns.
pub(super) fn the_line(
    opening: usize,
    slope: usize,
    abscissa: usize,
    value: usize,
) -> Vec<Constraint> {
    let (one, minus) = (F::ONE, F::ONE.negated());
    let folded = F::from_u64_reduced(line::RESIDUE).negated();
    let mut out = Vec::new();
    for at in 0..CAPACITY {
        let mut terms = vec![
            term(one, vec![factor(value + at, 0, 1)]),
            term(minus, vec![factor(opening + at, 0, 1)]),
        ];
        for i in 0..CAPACITY {
            for j in 0..CAPACITY {
                let coefficient = if i + j == at {
                    minus
                } else if i + j == at + CAPACITY {
                    folded
                } else {
                    continue;
                };
                terms.push(term(
                    coefficient,
                    vec![factor(slope + i, 0, 1), factor(abscissa + j, 0, 1)],
                ));
            }
        }
        out.push(Constraint { degree: 2, terms });
    }
    out
}

// The trace of a pledge, and the nullifier of the part and the value of the line it publishes. A
// pledge the network refuses where it reads it is written by nobody, and an abscissa of zero is one.
pub fn trace_of(
    machine_secret: &[u8; 32],
    window: u64,
    attempt: u32,
    name: &[u8; 32],
    since: u32,
) -> Option<(Vec<Vec<F>>, Digest, L)> {
    let closing = kind_of(attempt, since)?;
    let slot = line::slot(attempt, closing);
    let places = Places;
    let rows = 1usize << PRESENCE_ROWS_LOG2;
    let lane_places = lane::Places::after(permutation::TRACE_WIDTH);
    let held = Held::after(lane_places.width());
    let mut columns = vec![vec![F::ZERO; rows]; held.width()];

    let secret_limbs = poseidon::limbs_of(machine_secret);
    let (spending, _) = poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &secret_limbs);
    let mut nullified = spending.elements().to_vec();
    nullified.push(F::try_from_u64(window)?);
    let mut sloped = nullified.clone();
    sloped.push(F::try_from_u64(slot)?);
    let name_limbs = poseidon::limbs_of(name);
    for (first, states) in [
        (
            places.halves(),
            sponge::chain_twice(domain::MT_KEY_HALVES, &secret_limbs),
        ),
        (
            places.nullifier(),
            sponge::chain(domain::MT_PART_NF, &nullified),
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
    // An idle block is the permutation of the zero state, written through the same door.
    for block in (0..places.halves()).chain(places.blocks()..rows / permutation::period()) {
        permutation::write_block(&mut columns, block, &[F::ZERO; WIDTH])?;
    }

    let part_nullifier = poseidon::hash_elements(domain::MT_PART_NF, &nullified);
    let opening = line::opening(&spending);
    let slope = line::slope(&spending, window, slot)?;
    let abscissa = line::abscissa(name)?;
    let value = line::line_at(opening, slope, abscissa);

    for cell in 0..CAPACITY {
        columns[lane_places.cell(cell)].fill(spending.elements()[cell]);
        columns[held.opening(cell)].fill(opening.coefficients()[cell]);
        columns[held.slope(cell)].fill(slope.coefficients()[cell]);
        columns[held.abscissa(cell)].fill(abscissa.coefficients()[cell]);
        columns[held.value(cell)].fill(value.coefficients()[cell]);
    }
    let (at, from) = (
        F::from_u64_reduced(u64::from(attempt)),
        F::from_u64_reduced(u64::from(since)),
    );
    columns[held.attempt()].fill(at);
    columns[held.since()].fill(from);
    columns[held.kind()].fill(if closing { F::ONE } else { F::ZERO });
    columns[held.inverse()].fill(from.minus(at).inverse().unwrap_or(F::ZERO));
    Some((columns, part_nullifier, value))
}

// The public input in the order the layout of a pledge carries it.
pub fn public_of(
    window: u64,
    attempt: u32,
    name: &[u8; 32],
    since: u32,
    part_nullifier: &Digest,
    line_value: L,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + 4 + 32 + 4 + 32 + line::ELEMENT_BYTES);
    out.extend_from_slice(&window.to_le_bytes());
    out.extend_from_slice(&attempt.to_le_bytes());
    out.extend_from_slice(name);
    out.extend_from_slice(&since.to_le_bytes());
    out.extend_from_slice(&part_nullifier.bytes());
    out.extend_from_slice(&line_value.to_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::super::trial::{broken, fill};
    use super::*;

    const SECRET: [u8; 32] = [0x5A; 32];
    const AT: u64 = 1_000;
    const FIRST: [u8; 32] = [0x11; 32];
    const SECOND: [u8; 32] = [0x22; 32];

    fn columns() -> Held {
        Held::after(lane::Places::after(permutation::TRACE_WIDTH).width())
    }

    fn spending_of(secret: &[u8; 32]) -> Digest {
        poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, secret).0
    }

    // A pledge of the machine of `SECRET` in window `AT`: its trace, the limbs of its public input,
    // the nullifier of its part and the value of its line.
    fn pledged(attempt: u32, since: u32, name: &[u8; 32]) -> (Vec<Vec<F>>, Vec<F>, Digest, L) {
        let (trace, nullifier, value) =
            trace_of(&SECRET, AT, attempt, name, since).expect("a pledge the network reads");
        let public = limbs(attempt, since, name, &nullifier, value);
        (trace, public, nullifier, value)
    }

    fn limbs(attempt: u32, since: u32, name: &[u8; 32], nullifier: &Digest, value: L) -> Vec<F> {
        poseidon::limbs_of(&public_of(AT, attempt, name, since, nullifier, value))
    }

    // Where the rules of the held columns stand: the holds, the loads, the two rules of the slot,
    // the slot entering the slope, and the four rules of the line, last of all.
    fn slot_rules(held: &Description) -> [usize; 2] {
        let at = held.constraints.len() - CAPACITY - 1 - 2;
        [at, at + 1]
    }

    fn slot_entry(held: &Description) -> usize {
        held.constraints.len() - CAPACITY - 1
    }

    fn line_rules(held: &Description) -> std::ops::Range<usize> {
        held.constraints.len() - CAPACITY..held.constraints.len()
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
        let slope = L::of_digest(&poseidon::hash_elements(domain::MT_LINE_SLOPE, elements));
        let held = columns();
        fill(trace, held.slope(0), slope);
        let opening = line::opening(&spending_of(&SECRET));
        let value = line::line_at(opening, slope, line::abscissa(name).expect("an abscissa"));
        fill(trace, held.value(0), value);
        value
    }

    #[test]
    fn the_blocks_of_the_pledge_fit_the_height_of_the_presence() {
        let places = Places;
        let held = description().expect("the description stands");
        assert_eq!(places.blocks(), 9);
        assert!(places.blocks() * permutation::period() <= held.live_rows() as usize);
        // The slot enters the slope at the row the opening is loaded at, so one mark serves both.
        assert_eq!(places.loads()[0], places.seam_before(places.slope()));
        assert_eq!(usize::from(held.trace_width), columns().width());
        assert_eq!(
            public_of(0, 0, &FIRST, 0, &Digest::ZERO, L::ZERO).len(),
            4 * 28
        );
    }

    #[test]
    fn the_kind_is_read_as_the_set_reads_it() {
        assert_eq!(kind_of(3, 3), Some(true));
        assert_eq!(kind_of(0, 0), Some(true));
        assert_eq!(kind_of(3, 2), Some(false));
        assert_eq!(kind_of(3, u32::MAX), Some(false));
        assert_eq!(kind_of(3, 4), None);
        assert_eq!(kind_of(u32::MAX, u32::MAX), None);
        assert_eq!(kind_of(0, u32::MAX), None);
        assert!(trace_of(&SECRET, AT, 0, &FIRST, u32::MAX).is_none());
    }

    #[test]
    fn the_honest_trace_names_what_it_breaks() {
        let held = description().expect("the description stands");
        for (attempt, since) in [
            (0, 0),
            (3, 3),
            (3, 1),
            (62, u32::MAX),
            (0xFFFF_FFFE, u32::MAX),
        ] {
            let (trace, public, _, _) = pledged(attempt, since, &FIRST);
            assert_eq!(
                broken(&held, &trace, &public),
                (Vec::new(), Vec::new()),
                "attempt {attempt}, since {since}"
            );
        }
    }

    // What the circuit publishes is what the derivations compute outside it: the nullifier the
    // presence of the same part publishes, and a value on the line whose two points give the
    // lock-opening value of the machine.
    #[test]
    fn what_the_pledge_publishes_is_what_the_line_computes_outside_it() {
        let spending = spending_of(&SECRET);
        let depth = crate::tree_depth();
        let siblings = crate::admitted::empty_internals(depth)[..depth].to_vec();
        let key = vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY];
        let (_, presence, _) =
            super::super::presence::trace_of(&SECRET, &siblings, 0, AT, &FIRST, &key)
                .expect("the presence of the same part");
        for (attempt, since) in [(3, 3), (3, u32::MAX)] {
            let (_, _, nullifier, one) = pledged(attempt, since, &FIRST);
            let (_, _, _, two) = pledged(attempt, since, &SECOND);
            assert_eq!(nullifier, presence[1], "the nullifier of the part");
            let slope =
                line::slope(&spending, AT, line::slot(attempt, since == attempt)).expect("a slope");
            let (x1, x2) = (
                line::abscissa(&FIRST).expect("an abscissa"),
                line::abscissa(&SECOND).expect("an abscissa"),
            );
            assert_eq!(one, line::line_at(line::opening(&spending), slope, x1));
            assert_eq!(
                line::opening_of((x1, one), (x2, two)),
                Some(line::opening(&spending))
            );
        }
    }

    #[test]
    fn a_pledge_is_proven_and_verified_end_to_end() {
        let (trace, nullifier, value) =
            trace_of(&SECRET, AT, 3, &FIRST, 3).expect("a closing pledge");
        let public = public_of(AT, 3, &FIRST, 3, &nullifier, value);
        let held = description().expect("the description stands");
        assert!(held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
        let bytes = crate::scheme::prove(&held, &public, &trace).expect("a true pledge proves");
        assert_eq!(bytes.len(), mt_state::PRESENCE_PROOF_LEN);
        assert_eq!(crate::scheme::verify(&held, &public, &bytes), Ok(()));
        // The value of the line, one bit over.
        let mut moved = public.clone();
        moved[80] ^= 1;
        assert!(crate::scheme::verify(&held, &moved, &bytes).is_err());
        // The same point offered as the open pledge of the same attempt.
        let open = public_of(AT, 3, &FIRST, u32::MAX, &nullifier, value);
        assert!(crate::scheme::verify(&held, &open, &bytes).is_err());
    }

    // A closing pledge taking the slot of the open one: the kind set to zero where `since` is the
    // attempt. Everything else is moved to match, and the second rule of the slot refuses it.
    #[test]
    fn a_closing_pledge_cannot_take_the_open_slot() {
        let held = description().expect("the description stands");
        let (mut trace, _, nullifier, _) = pledged(3, 3, &FIRST);
        trace[columns().kind()].fill(F::ZERO);
        let slot = line::slot(3, false);
        let value = reslope(
            &mut trace,
            &slope_elements(&spending_of(&SECRET), slot),
            &FIRST,
        );
        let public = limbs(3, 3, &FIRST, &nullifier, value);
        assert_eq!(
            broken(&held, &trace, &public),
            (vec![slot_rules(&held)[1]], Vec::new())
        );
    }

    // An open pledge taking the closing slot, with the inverse set to zero so the second rule holds:
    // the first refuses it, and so a `since` of `0xFFFFFFFF` is an open pledge.
    #[test]
    fn an_open_pledge_cannot_take_the_closing_slot() {
        let held = description().expect("the description stands");
        let (mut trace, _, nullifier, _) = pledged(3, u32::MAX, &FIRST);
        let held_columns = columns();
        trace[held_columns.kind()].fill(F::ONE);
        trace[held_columns.inverse()].fill(F::ZERO);
        let slot = line::slot(3, true);
        let value = reslope(
            &mut trace,
            &slope_elements(&spending_of(&SECRET), slot),
            &FIRST,
        );
        let public = limbs(3, u32::MAX, &FIRST, &nullifier, value);
        assert_eq!(
            broken(&held, &trace, &public),
            (vec![slot_rules(&held)[0]], Vec::new())
        );
    }

    // The slope of another attempt, its kind kept: the rule that writes the slot into the slope.
    #[test]
    fn a_slope_of_another_attempt_is_refused() {
        let held = description().expect("the description stands");
        let (mut trace, _, nullifier, _) = pledged(3, 3, &FIRST);
        let slot = line::slot(4, true);
        let value = reslope(
            &mut trace,
            &slope_elements(&spending_of(&SECRET), slot),
            &FIRST,
        );
        let public = limbs(3, 3, &FIRST, &nullifier, value);
        assert_eq!(
            broken(&held, &trace, &public),
            (vec![slot_entry(&held)], Vec::new())
        );
    }

    // A value that is the line of another slot, published and held: only the rules of the line fail.
    #[test]
    fn a_value_on_the_line_of_another_slot_is_refused() {
        let held = description().expect("the description stands");
        let (mut trace, _, nullifier, _) = pledged(3, 3, &FIRST);
        let spending = spending_of(&SECRET);
        let other = line::line_at(
            line::opening(&spending),
            line::slope(&spending, AT, line::slot(3, false)).expect("a slope"),
            line::abscissa(&FIRST).expect("an abscissa"),
        );
        fill(&mut trace, columns().value(0), other);
        let public = limbs(3, 3, &FIRST, &nullifier, other);
        let (rules, boundaries) = broken(&held, &trace, &public);
        assert!(!rules.is_empty());
        for rule in &rules {
            assert!(line_rules(&held).contains(rule), "rule {rule}");
        }
        assert!(boundaries.is_empty());
    }

    // The name of one pledge published with the value of another: the boundaries of the name.
    #[test]
    fn a_name_cannot_carry_the_value_of_another() {
        let held = description().expect("the description stands");
        let (trace, _, nullifier, value) = pledged(3, 3, &FIRST);
        let public = limbs(3, 3, &SECOND, &nullifier, value);
        let (rules, boundaries) = broken(&held, &trace, &public);
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

    // The padding of the slope used as one more input: one more slope per slot, and so two lines.
    #[test]
    fn padding_cannot_be_an_extra_input_of_the_slope() {
        let held = description().expect("the description stands");
        let (mut trace, _, nullifier, _) = pledged(3, 3, &FIRST);
        let mut elements = slope_elements(&spending_of(&SECRET), line::slot(3, true));
        elements.push(F::ONE);
        let value = reslope(&mut trace, &elements, &FIRST);
        let public = limbs(3, 3, &FIRST, &nullifier, value);
        let (rules, boundaries) = broken(&held, &trace, &public);
        assert!(rules.is_empty());
        assert_eq!(boundaries.len(), 1);
        let padding = &held.boundaries[boundaries[0]];
        assert_eq!(padding.column as usize, ring_column(RATE - 1));
        assert_eq!(padding.row as usize, Places.slope() * permutation::period());
    }

    // A slope drawn from another half: with the lane wired to the nullifier and the opening only,
    // the forgery stands; wired to the slope as well, the lane refuses it.
    #[test]
    fn the_lane_reaches_every_derivation_of_the_half() {
        let held = description().expect("the description stands");
        let (mut trace, _, nullifier, _) = pledged(3, 3, &FIRST);
        let stranger = spending_of(&[0xB7; 32]);
        let value = reslope(
            &mut trace,
            &slope_elements(&stranger, line::slot(3, true)),
            &FIRST,
        );
        let public = limbs(3, 3, &FIRST, &nullifier, value);
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
        for rule in &held.constraints {
            assert!(rule.degree <= crate::params::DEGREE_BOUND);
        }
        assert_eq!(Description::decode(&held.encode()).ok(), Some(held.clone()));
        let presence = super::super::presence::description().expect("the presence stands");
        assert_ne!(held.identifier(), presence.identifier());
    }
}
