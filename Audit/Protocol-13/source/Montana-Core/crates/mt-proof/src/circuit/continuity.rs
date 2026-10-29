// The continuity a record carries, read inside the proof that spends it: the segments the record
// lived in the period in force, counted against the share the gate of entry demands — disclosing
// neither the bitmap, nor the segment it was written against, nor how many segments it lived.
//
// **Why inside the proof.** A record is private and only its commitment stands in a tree, so no
// verifier can read its bitmap; a gate held outside the proof is a gate nobody holds. What the
// verifier holds is the segment of the window it applies, the count in force and the share of it,
// and those three are what the public input carries (Canon, "The rules of continuity", rules 1 to 3;
// "The candidacy of a machine"; constitution records 297, 300 and 370).
//
// **What is counted.** Bit `i` of the bitmap stands for the segment `last - i`, the newest in bit 0.
// At the current segment `c` it is shifted left by `d = c - last`, and the low `n` bits are counted:
// so bit `i` counts exactly when `i < n - d`, and none counts where `d` reaches `n`. A bit at or above
// `max_entry_segments` is reserved, and a record carrying one counts nothing (`Record::segments_lived`,
// the reader this layer is held against).
//
// **The shape: two masks and a sum, rows and not columns.** The sixty-four bits stand one to a row,
// the most significant first, in the first rows of the idle block before the record's absorption;
// the halves and the sums hold through the rest of that block and meet the three limbs of the record
// on the first row of the absorption, where it has written them and nothing has yet moved. Beside
// each bit stand two masks: `period`, set on the bits below
// `n`, and `lived`, set on the bits below `n - d`. Each is a suffix of the rows — once set it stays
// set — so a mask is fixed by its count alone. The count of `period` is the public `n`; the count of
// `lived` is held to `n + last - c`. The second mask lies inside the first, so that count is at least
// nought and at most `n`: `last` stands at or before `c`, and `d` at or below `n`. What the masked
// bits sum to is the public share plus a sum of slack bits, so it is at least the share.
//
// **Why the bitmap is read as two halves.** The field is narrower than sixty-four bits, so one sum of
// sixty-four weighted bits wraps: a pattern above the modulus reads as a smaller bitmap. Each half
// sums below two to the thirty-second and meets its own limb, which is exact.
//
// **The bits ride under the blocks.** The decomposition needs one row per bit and no permutation,
// as an amount's does (`value.rs`): it costs twelve columns and no block and no height.

use super::opening::{LIMB_BITMAP_HIGH, LIMB_BITMAP_LOW, LIMB_LAST_SEGMENT};
use super::permutation::ring_column;
use super::sponge::{factor, term};
use crate::air::{Boundary, BoundaryValue, Constraint, Periodic};
use crate::field::F;

mt_codec::constants! {
    CONTINUITY:
    /// The bits of the bitmap a record carries, one to a row: the width the layout of a record
    /// gives that field, and the row the decomposition meets the record at.
    pub const BITMAP_BITS: usize = 64, code "the bits of a record's bitmap the decomposition of an admission reads, one to a row";
    /// Where the schedule stands among the periodic columns this layer adds.
    pub const RANGE: usize = 0, code "the periodic column of this layout marking a row of the decomposition of the bitmap";
    pub const HIGH_HALF: usize = 1, code "the periodic column of this layout marking a row of the high half of the bitmap";
    pub const RESERVED: usize = 2, code "the periodic column of this layout marking a row of a reserved bit of the bitmap";
    pub const TIE: usize = 3, code "the periodic column of this layout marking where the decomposition meets the record";
    pub const PERIODIC_COUNT: usize = 4, code "the count of the periodic columns this layout adds";
    /// The values of the public input this layer reads, in order, from the place it is given.
    pub const PUBLIC_SEGMENT: usize = 0, code "the place of the current segment among the values of the public input the continuity of an admission reads";
    pub const PUBLIC_IN_FORCE: usize = 1, code "the place of the count in force among them";
    pub const PUBLIC_REQUIRED: usize = 2, code "the place of the share of the count in force among them";
    pub const PUBLIC_COUNT: usize = 3, code "the count of the values of the public input the continuity of an admission reads";
}

// The row the decomposition meets the record at: the first row of the record's absorption, the
// block after the idle one (`admission::Places::record`). The bits stand in the first sixty-four
// rows of the idle block and the halves and sums hold through the rest of it to this row.
pub fn tie() -> usize {
    super::permutation::period()
}

// Whether a row is one of the bits.
fn is_bit(row: usize) -> bool {
    row < BITMAP_BITS
}

// What a verifier holds of the gate: the segment of the window it applies, the count of segments in
// force and the share of that count a record must have lived. It computes all three and takes none
// of them from the candidacy.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Gate {
    pub segment: u32,
    pub in_force: u32,
    pub required: u32,
}

impl Gate {
    // The three values as the public input lays them, after the digests and before the suite.
    pub fn bytes(&self) -> [u8; 4 * PUBLIC_COUNT] {
        let mut out = [0u8; 4 * PUBLIC_COUNT];
        for (at, value) in [self.segment, self.in_force, self.required]
            .iter()
            .enumerate()
        {
            out[at * 4..at * 4 + 4].copy_from_slice(&value.to_le_bytes());
        }
        out
    }
}

// The twelve columns this layer adds after the layers below.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Places {
    pub bit: usize,
    pub lived: usize,
    pub period: usize,
    pub slack: usize,
    pub counted: usize,
    pub lived_held: usize,
    pub period_held: usize,
    pub high: usize,
    pub low: usize,
    pub lived_sum: usize,
    pub period_sum: usize,
    pub count: usize,
}

impl Places {
    pub const fn after(width: usize) -> Self {
        Self {
            bit: width,
            lived: width + 1,
            period: width + 2,
            slack: width + 3,
            counted: width + 4,
            lived_held: width + 5,
            period_held: width + 6,
            high: width + 7,
            low: width + 8,
            lived_sum: width + 9,
            period_sum: width + 10,
            count: width + 11,
        }
    }

    pub const fn width(&self) -> usize {
        self.count + 1
    }
}

// The bits a record may carry: `max_entry_segments`, the widest period any gate demands — the width
// the record's own rule holds its bitmap to, and nothing where the Decree does not give it.
fn carried_bits() -> Option<usize> {
    mt_genesis::scalar("max_entry_segments")
        .and_then(|n| usize::try_from(n).ok())
        .filter(|&n| n != 0 && n <= BITMAP_BITS)
}

// The four columns of the schedule. The bits stand in the rows before the tie, the most significant
// first, so the first half of them is the high limb and the first rows above the carried width are
// the reserved bits.
pub fn periodic_columns(rows_log2: u8) -> Option<Vec<Periodic>> {
    let rows = 1usize << rows_log2;
    if rows <= tie() {
        return None;
    }
    let reserved = BITMAP_BITS - carried_bits()?;
    let mut columns = vec![vec![0u64; rows]; PERIODIC_COUNT];
    columns[RANGE][..BITMAP_BITS].fill(1);
    columns[HIGH_HALF][..BITMAP_BITS / 2].fill(1);
    columns[RESERVED][..reserved].fill(1);
    columns[TIE][tie()] = 1;
    Some(
        columns
            .into_iter()
            .map(|values| Periodic {
                period_log2: rows_log2,
                values,
            })
            .collect(),
    )
}

fn rule(terms: Vec<crate::air::Term>) -> Constraint {
    Constraint { degree: 2, terms }
}

// Every rule this layer adds, each of degree two.
pub fn constraints(periodic_base: usize, places: &Places) -> Vec<Constraint> {
    let range = periodic_base + RANGE;
    let high_half = periodic_base + HIGH_HALF;
    let reserved = periodic_base + RESERVED;
    let tie = periodic_base + TIE;
    let one = F::ONE;
    let minus = F::ONE.negated();
    let two = F::from_u64_reduced(2);
    let mut out = Vec::new();
    // A bit, a mask and a slack are each a bit, wherever they stand.
    for column in [places.bit, places.lived, places.period, places.slack] {
        out.push(rule(vec![
            term(one, vec![factor(column, 0, 2)]),
            term(minus, vec![factor(column, 0, 1)]),
        ]));
    }
    // A bit is counted where the mask of the lived period is set on it.
    out.push(rule(vec![
        term(one, vec![factor(places.counted, 0, 1)]),
        term(
            minus,
            vec![factor(places.bit, 0, 1), factor(places.lived, 0, 1)],
        ),
    ]));
    // A mask is a suffix of the rows of the bits: set on a row whose next row is still a bit, it is
    // set on that next row. The product is held in a column of its own, which keeps the rule at two.
    for (mask, held) in [
        (places.lived, places.lived_held),
        (places.period, places.period_held),
    ] {
        out.push(rule(vec![
            term(one, vec![factor(held, 0, 1)]),
            term(minus, vec![factor(range, 1, 1), factor(mask, 0, 1)]),
        ]));
        out.push(rule(vec![
            term(one, vec![factor(held, 0, 1)]),
            term(minus, vec![factor(held, 0, 1), factor(mask, 1, 1)]),
        ]));
    }
    // The lived period lies inside the period in force.
    out.push(rule(vec![
        term(one, vec![factor(places.lived, 0, 1)]),
        term(
            minus,
            vec![factor(places.lived, 0, 1), factor(places.period, 0, 1)],
        ),
    ]));
    // A reserved bit is empty.
    out.push(rule(vec![term(
        one,
        vec![factor(reserved, 0, 1), factor(places.bit, 0, 1)],
    )]));
    // The high half doubles and takes the bit on its rows and holds everywhere else.
    out.push(rule(vec![
        term(one, vec![factor(places.high, 1, 1)]),
        term(minus, vec![factor(places.high, 0, 1)]),
        term(
            minus,
            vec![factor(high_half, 0, 1), factor(places.high, 0, 1)],
        ),
        term(
            minus,
            vec![factor(high_half, 0, 1), factor(places.bit, 0, 1)],
        ),
    ]));
    // The low half is empty after the rows of the high half, doubles and takes the bit on the rows
    // of the bits below it, and holds after the bits — so it opens at nought where the low half
    // begins and stands whole at the tie.
    out.push(rule(vec![
        term(one, vec![factor(places.low, 1, 1)]),
        term(minus, vec![factor(places.low, 0, 1)]),
        term(minus, vec![factor(range, 0, 1), factor(places.low, 0, 1)]),
        term(minus, vec![factor(range, 0, 1), factor(places.bit, 0, 1)]),
        term(two, vec![factor(high_half, 0, 1), factor(places.low, 0, 1)]),
        term(one, vec![factor(high_half, 0, 1), factor(places.bit, 0, 1)]),
    ]));
    // The three sums take their column on the rows of the bits and hold on every other row; the
    // count gives back a slack bit wherever one is set.
    for (sum, taken) in [
        (places.lived_sum, places.lived),
        (places.period_sum, places.period),
    ] {
        out.push(rule(vec![
            term(one, vec![factor(sum, 1, 1)]),
            term(minus, vec![factor(sum, 0, 1)]),
            term(minus, vec![factor(range, 0, 1), factor(taken, 0, 1)]),
        ]));
    }
    out.push(rule(vec![
        term(one, vec![factor(places.count, 1, 1)]),
        term(minus, vec![factor(places.count, 0, 1)]),
        term(
            minus,
            vec![factor(range, 0, 1), factor(places.counted, 0, 1)],
        ),
        term(one, vec![factor(range, 0, 1), factor(places.slack, 0, 1)]),
    ]));
    // Where the bits meet the record: the two halves are its two limbs of the bitmap, and the count
    // of the lived mask, opened at the current segment, is the count in force and the record's own
    // segment — the lived sum less the period's is `last`.
    for (half, limb) in [
        (places.high, LIMB_BITMAP_HIGH),
        (places.low, LIMB_BITMAP_LOW),
    ] {
        out.push(rule(vec![
            term(one, vec![factor(tie, 0, 1), factor(half, 0, 1)]),
            term(
                minus,
                vec![factor(tie, 0, 1), factor(ring_column(limb), 0, 1)],
            ),
        ]));
    }
    out.push(rule(vec![
        term(one, vec![factor(tie, 0, 1), factor(places.lived_sum, 0, 1)]),
        term(
            minus,
            vec![factor(tie, 0, 1), factor(places.period_sum, 0, 1)],
        ),
        term(
            minus,
            vec![
                factor(tie, 0, 1),
                factor(ring_column(LIMB_LAST_SEGMENT), 0, 1),
            ],
        ),
    ]));
    out
}

// Where the sums open and close: the high half and the two counts open at nought and the lived sum
// at the current segment, and at the tie the count in force and the share close them. `public` is
// the place of the first value this layer reads among the limbs of the public input.
pub fn boundaries(places: &Places, public: usize) -> Vec<Boundary> {
    let at = |column: usize, row: usize, value| Boundary {
        column: column as u16,
        row: row as u64,
        value,
    };
    let limb = |slot: usize| BoundaryValue::Public((public + slot) as u16);
    vec![
        at(places.high, 0, BoundaryValue::Literal(0)),
        at(places.period_sum, 0, BoundaryValue::Literal(0)),
        at(places.count, 0, BoundaryValue::Literal(0)),
        at(places.lived_sum, 0, limb(PUBLIC_SEGMENT)),
        at(places.period_sum, tie(), limb(PUBLIC_IN_FORCE)),
        at(places.count, tie(), limb(PUBLIC_REQUIRED)),
    ]
}

// The columns of this layer, written from the record's bitmap and segment and from the gate, by the
// rules above and by nothing else: a record the gate refuses is written all the same, and it is the
// statement that refuses it.
pub fn write(columns: &mut [Vec<F>], places: &Places, bitmap: u64, last: u32, gate: &Gate) {
    let lived_below = i64::from(gate.in_force) + i64::from(last) - i64::from(gate.segment);
    let flag = |set: bool| F::from_u64_reduced(u64::from(set));
    let mut counted = 0u32;
    for (row, i) in (0..BITMAP_BITS).rev().enumerate() {
        let bit = (bitmap >> i) & 1 == 1;
        let lived = (i as i64) < lived_below;
        columns[places.bit][row] = flag(bit);
        columns[places.lived][row] = flag(lived);
        columns[places.period][row] = flag((i as u64) < u64::from(gate.in_force));
        columns[places.slack][row] = F::ZERO;
        counted += u32::from(bit && lived);
    }
    // What the masked bits hold beyond the share stands in as many slack bits; short of it, none
    // stands, and the count does not close.
    columns[places.slack][..counted.saturating_sub(gate.required) as usize].fill(F::ONE);
    accumulate(columns, places, gate.segment);
}

// Every column of this layer that the bits, the two masks and the slack fix, written by the rules
// above across the whole height: the counted bits, the held masks, the halves and the three sums.
pub fn accumulate(columns: &mut [Vec<F>], places: &Places, segment: u32) {
    let rows = columns[places.bit].len();
    let range = is_bit;
    let high_half = |row: usize| row < BITMAP_BITS / 2;
    let counted: Vec<F> = (0..rows)
        .map(|row| columns[places.bit][row].times(columns[places.lived][row]))
        .collect();
    columns[places.counted][..rows].copy_from_slice(&counted);
    for (mask, held) in [
        (places.lived, places.lived_held),
        (places.period, places.period_held),
    ] {
        let kept: Vec<F> = (0..rows)
            .map(|row| {
                if range((row + 1) % rows) {
                    columns[mask][row]
                } else {
                    F::ZERO
                }
            })
            .collect();
        columns[held][..rows].copy_from_slice(&kept);
    }
    let two = F::from_u64_reduced(2);
    for column in [places.high, places.low, places.period_sum, places.count] {
        columns[column][0] = F::ZERO;
    }
    columns[places.lived_sum][0] = F::from_u64_reduced(u64::from(segment));
    for row in 0..rows - 1 {
        let bit = columns[places.bit][row];
        let high = columns[places.high][row];
        let low = columns[places.low][row];
        columns[places.high][row + 1] = if high_half(row) {
            high.times(two).plus(bit)
        } else {
            high
        };
        columns[places.low][row + 1] = if !range(row) {
            low
        } else if high_half(row) {
            F::ZERO
        } else {
            low.times(two).plus(bit)
        };
        for (sum, taken) in [
            (places.lived_sum, places.lived),
            (places.period_sum, places.period),
        ] {
            columns[sum][row + 1] = if range(row) {
                columns[sum][row].plus(columns[taken][row])
            } else {
                columns[sum][row]
            };
        }
        columns[places.count][row + 1] = if range(row) {
            columns[places.count][row]
                .plus(columns[places.counted][row])
                .minus(columns[places.slack][row])
        } else {
            columns[places.count][row]
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_layer_costs_twelve_columns_and_four_schedules() {
        let places = Places::after(34);
        assert_eq!(places.width(), 34 + 12);
        let columns = periodic_columns(8).expect("the Decree names the width");
        assert_eq!(columns.len(), PERIODIC_COUNT);
        let ones = |at: usize| columns[at].values.iter().sum::<u64>();
        assert_eq!(ones(RANGE), BITMAP_BITS as u64);
        assert_eq!(ones(HIGH_HALF), BITMAP_BITS as u64 / 2);
        assert_eq!(
            ones(RESERVED),
            (BITMAP_BITS - carried_bits().expect("it stands")) as u64
        );
        assert_eq!(ones(TIE), 1);
        assert_eq!(columns[TIE].values[tie()], 1);
        assert!(
            periodic_columns(7).is_none(),
            "the tie stands past the rows of the bits"
        );
    }

    #[test]
    fn every_rule_stands_within_the_degree_the_scheme_admits() {
        for rule in constraints(90, &Places::after(34)) {
            assert_eq!(rule.degree, crate::params::DEGREE_BOUND);
            for held in &rule.terms {
                let power: u8 = held.factors.iter().map(|f| f.power).sum();
                assert!(power <= crate::params::DEGREE_BOUND);
            }
        }
    }

    use crate::air::Description;
    use mt_state::layout::Record;

    // A height every row of which is live, so a trace of this layer alone is judged at every row.
    const LOG: u8 = 8;
    const LAST: u32 = 100;

    fn places() -> Places {
        Places::after(super::super::permutation::TRACE_WIDTH)
    }

    // The layer alone: its columns after those of a permutation, whose three cells at the tie carry
    // the limbs of the record as its absorption would.
    fn held() -> Description {
        let places = places();
        let width = places.width();
        Description {
            trace_width: width as u16,
            rows_log2: LOG,
            periodic: periodic_columns(LOG).expect("the Decree names the width"),
            constraints: constraints(width, &places),
            boundaries: boundaries(&places, 0),
        }
    }

    fn with_record(bitmap: u64, last: u32) -> Vec<Vec<F>> {
        let mut columns = vec![vec![F::ZERO; 1 << LOG]; places().width()];
        for (limb, value) in [
            (LIMB_BITMAP_LOW, bitmap & 0xFFFF_FFFF),
            (LIMB_BITMAP_HIGH, bitmap >> 32),
            (LIMB_LAST_SEGMENT, u64::from(last)),
        ] {
            columns[ring_column(limb)][tie()] = F::from_u64_reduced(value);
        }
        columns
    }

    fn trace(bitmap: u64, last: u32, gate: &Gate) -> Vec<Vec<F>> {
        let mut columns = with_record(bitmap, last);
        write(&mut columns, &places(), bitmap, last, gate);
        columns
    }

    fn public(gate: &Gate) -> Vec<F> {
        crate::poseidon::limbs_of(&gate.bytes())
    }

    fn required(in_force: u32) -> u32 {
        let (num, den) = mt_genesis::ratio("continuity_required").expect("the Decree names it");
        u32::try_from((u64::from(in_force) * num).div_ceil(den)).expect("a share of a count")
    }

    fn record(bitmap: u64, last: u32) -> Record {
        Record {
            segment_bitmap: bitmap,
            last_active_segment: last,
            opened_window: 0,
            own_height: 0,
            operator_nf: [0; 32],
            fabric_root: [0; 32],
            suite_id: 1,
            current_pubkey: vec![0; mt_codec::size::SIGNING_PUBLIC_KEY],
            blind: [0; 32],
        }
    }

    // The statement admits a record exactly where the reader of the record counts the share: across
    // bitmaps full, sparse, old, new and reserved, distances before, inside and past the period, and
    // the floor, the middle and the ceiling of the ramp. The named wrong implementations: a mask that
    // is not shifted (the old bits counted), one that is not cut at `n` (the bits before the period
    // counted), and a record written against a later segment read as a nearer one.
    #[test]
    fn the_layer_admits_exactly_what_the_reader_counts() {
        let width = carried_bits().expect("it stands") as u32;
        let floor = mt_genesis::scalar("continuity_segments").expect("the Decree names it") as u32;
        let carried = (1u64 << width) - 1;
        let bitmaps = [
            0,
            1,
            0b1011,
            0x3FF,
            0x3FFF,
            0x3FFF << 4,
            0x3FFF << 20,
            carried,
            0xAAAA_AAAA_AAAA_AAAA & carried,
            1 << (width - 1),
            (1 << width) | 0x3FFF,
            1 << 63,
        ];
        let description = held();
        let (mut admitted, mut refused) = (0, 0);
        for bitmap in bitmaps {
            for offset in [-5i64, -1, 0, 1, 2, 4, 13, 14, 20, 42, 55, 56, 57, 70] {
                for in_force in [floor, 2 * floor, width] {
                    let segment = u32::try_from(i64::from(LAST) + offset).expect("a segment");
                    let gate = Gate {
                        segment,
                        in_force,
                        required: required(in_force),
                    };
                    let lawful =
                        record(bitmap, LAST).segments_lived(segment, in_force) >= gate.required;
                    let held =
                        description.satisfied_by(&trace(bitmap, LAST, &gate), &public(&gate));
                    assert_eq!(
                        held, lawful,
                        "bitmap {bitmap:#x}, segment {segment}, n {in_force}"
                    );
                    if lawful {
                        admitted += 1;
                    } else {
                        refused += 1;
                    }
                }
            }
        }
        assert!(
            admitted > 0 && refused > 0,
            "{admitted} admitted, {refused} refused"
        );
    }

    // Old segments do not count by lifting the masks onto them: a record whose lived bits all stand
    // before the period in force, with both masks set on those bits instead of on the newest ones —
    // the counts the public input names, the share reached. The suffix rules alone refuse it. The
    // named wrong implementation: masks held only by their counts.
    #[test]
    fn a_mask_lifted_onto_older_segments_is_refused() {
        let (in_force, bitmap) = (14u32, 0x3FFFu64 << 14);
        let gate = Gate {
            segment: LAST,
            in_force,
            required: required(in_force),
        };
        assert_eq!(record(bitmap, LAST).segments_lived(LAST, in_force), 0);
        let places = places();
        let mut columns = with_record(bitmap, LAST);
        let mut lifted = 0u32;
        for row in 0..BITMAP_BITS {
            let i = BITMAP_BITS - 1 - row;
            let set = (bitmap >> i) & 1 == 1;
            let flag = F::from_u64_reduced(u64::from(set));
            columns[places.bit][row] = flag;
            columns[places.lived][row] = flag;
            columns[places.period][row] = flag;
            lifted += u32::from(set);
        }
        assert_eq!(lifted, in_force);
        for row in 0..(lifted - gate.required) as usize {
            columns[places.slack][row] = F::ONE;
        }
        accumulate(&mut columns, &places, gate.segment);
        let description = held();
        assert!(!description.satisfied_by(&columns, &public(&gate)));
        // And the rules that refuse it are the suffixes: without them the lifted masks stand.
        let suffix = |rule: &Constraint| {
            rule.terms.iter().any(|t| {
                t.factors.iter().any(|f| {
                    f.shift == 1 && [places.lived, places.period].contains(&(f.column as usize))
                })
            })
        };
        let mut weak = description.clone();
        weak.constraints.retain(|rule| !suffix(rule));
        assert_eq!(weak.constraints.len() + 2, description.constraints.len());
        assert!(weak.satisfied_by(&columns, &public(&gate)));
    }

    // A bitmap is not read across the modulus: the bits of the record's bitmap plus the modulus,
    // which one weighted sum of sixty-four bits reads as the record's own and which lives the share
    // in its low bits, meet neither half. Held with the reserved rule taken out, so the halves alone
    // refuse it. The named wrong implementation: one sum of the sixty-four bits against the two
    // limbs read as one.
    #[test]
    fn a_bitmap_read_across_the_modulus_is_refused() {
        let in_force = 14u32;
        let gate = Gate {
            segment: LAST,
            in_force,
            required: required(in_force),
        };
        let bitmap = 0x3FFEu64;
        let description = held();
        assert!(description.satisfied_by(&trace(bitmap, LAST, &gate), &public(&gate)));
        let aliased = bitmap + crate::field::P;
        assert_eq!(aliased & 0xFFFF_FFFF, bitmap + 1);
        let mut columns = with_record(bitmap, LAST);
        write(&mut columns, &places(), aliased, LAST, &gate);
        let mut weak = description.clone();
        weak.constraints.retain(|rule| rule.terms.len() != 1);
        assert_eq!(weak.constraints.len() + 1, description.constraints.len());
        assert!(!weak.satisfied_by(&columns, &public(&gate)));
    }

    #[test]
    fn the_gate_lays_three_values_of_four_bytes() {
        let gate = Gate {
            segment: 0x0102_0304,
            in_force: 14,
            required: 10,
        };
        assert_eq!(gate.bytes(), [4, 3, 2, 1, 14, 0, 0, 0, 10, 0, 0, 0]);
    }
}
