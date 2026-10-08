// The six sources a seed is drawn from, and the one rule that decides whether each is alive.
// The set states them in `docs/Montana Canon.md`, "The birth of a seed": six sources of four
// natures, summed under the mixing domain, each preceded by its own length; a source that is
// not alive contributes neither a length nor bytes.
//
// Aliveness is measured and never assumed. The measure is the most-common-value estimate of
// min-entropy of NIST SP 800-90B §6.3.1 taken as that standard takes it: the **upper bound** of
// the share of the most frequent sample, not the share a short run happened to show. A length that
// is constant by construction says nothing about a source, so no source here is called alive
// because its code ran.
//
// The generator of the operating system is judged by another rule, and for the reason the set
// states: it is a full-entropy source by construction rather than a physical process whose
// unpredictability is being estimated, so what can go wrong with it is that it stops, and what
// catches that is the four health tests of its own block.

use mt_codec::{domain, Preimage};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use zeroize::{Zeroize, Zeroizing};

mt_codec::constants! {
    OF_THIS_TREE:
    /// The stride of the walk of the memory source and the shortest sleep asked of the timer:
    /// both enter no object and the set states no value for either. They stand in a register
    /// rather than loose, since a numeral in no register is a numeral no reading of this tree
    /// ever reaches.
    const STRIDE_OF_THE_WALK: usize = 20_011, code "the stride of the walk of the memory source, which enters no object";
    const ASKED_OF_THE_TIMER: u64 = 1_000, code "the shortest sleep this tree asks the timer for";
    const CELLS_OF_THE_WALK: usize = 1 << 16, code "the length of the chain of references the memory source walks";
}

mt_codec::constants! {
    SAMPLING:
    /// The width of one sample and the count taken from each source are of this tree: the set
    /// states which sources are drawn and how a source is judged alive, and leaves to an
    /// implementation how much of each it takes — a count that moved would change no byte of any
    /// object, only how much of a machine's own noise enters one birth.
    const SAMPLE: usize = 8, code "the width of one sample of a source of this tree";
    pub const JITTER_SAMPLES: usize = 256, code "the count of samples this tree draws from the jitter";
    pub const MEMORY_SAMPLES: usize = 128, code "the count of samples this tree draws from the latency of memory";
    pub const QUARTZ_SAMPLES: usize = 64, code "the count of samples this tree draws from the drift of the quartz";
    pub const SCHEDULER_SAMPLES: usize = 128, code "the count of samples this tree draws from the scheduler";
    pub const TIMER_SAMPLES: usize = 128, code "the count of samples this tree draws from the overshoot of the timer";
}

// Four times the square of the point of the normal law the standard names for ninety-nine per
// cent, written as a fraction: z is 2.576, z squared is 6.635776, and four times it is exactly
// this pair. They are the whole of what the bound adds to the share, and they are the set's.
mt_codec::constants! {
    BOUND:
    pub const CONFIDENCE_NUM: u128 = 414_736, writes "414736 *";
    pub const CONFIDENCE_DEN: u128 = 15_625, writes "<= 15625 *";
    /// Fewer than four distinct samples is an oscillation between two numbers, not a source.
    const MIN_DISTINCT: usize = 4, spells "at least four\ndistinct values were produced";
}

// The order is the order of the table of the set, and it is what the mixing consumes.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Source {
    OperatingSystem,
    Jitter,
    Memory,
    Quartz,
    Scheduler,
    Timer,
}

impl Source {
    // The place of a source in the table of the set, counted from zero: it stands in the preimage
    // of the mixing, so the identity of every summand is bound and not merely its length.
    pub fn place(self) -> u8 {
        match self {
            Source::OperatingSystem => 0,
            Source::Jitter => 1,
            Source::Memory => 2,
            Source::Quartz => 3,
            Source::Scheduler => 4,
            Source::Timer => 5,
        }
    }

    pub const ALL: [Source; 6] = [
        Source::OperatingSystem,
        Source::Jitter,
        Source::Memory,
        Source::Quartz,
        Source::Scheduler,
        Source::Timer,
    ];

    pub fn required(self) -> bool {
        matches!(self, Source::OperatingSystem)
    }
}

// What a person is shown about the source their identity stands on: counts and a verdict, and
// not one byte of what was measured.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Measure {
    pub source: Source,
    pub samples: usize,
    pub distinct: usize,
    pub most_frequent: usize,
    pub alive: bool,
}

pub struct Draw {
    pub measures: Vec<Measure>,
    contributions: Vec<(Source, Zeroizing<Vec<u8>>)>,
}

impl Draw {
    pub fn alive(&self) -> usize {
        self.measures.iter().filter(|m| m.alive).count()
    }

    pub fn is_alive(&self, source: Source) -> bool {
        self.measures.iter().any(|m| m.source == source && m.alive)
    }

    // The mixing of the set: the domain, then every living source ascending by its place in the
    // table, each preceded by that place and by its own length. A source that is not alive
    // contributes none of the three, so no two different sets of sources collapse into one input.
    //
    // The door is of the crate and not of the world: an entropy that passed neither the floor of
    // the living nor the tests of health is not a thing a caller may hold, and the one way to a
    // person is `birth`.
    pub(crate) fn mix(&self) -> Option<Zeroizing<[u8; 32]>> {
        let parts: Vec<(u8, &[u8])> = self
            .contributions
            .iter()
            .map(|(source, bytes)| (source.place(), bytes.as_slice()))
            .collect();
        mix_of_stated_sources(&parts).map(Zeroizing::new)
    }

    // The one place a draw is assembled from samples, whether they were taken from this machine
    // or handed in by a test that needs a source to be dead.
    pub(crate) fn of(drawn: Vec<(Source, Zeroizing<Vec<u8>>)>) -> Draw {
        let mut measures = Vec::with_capacity(drawn.len());
        let mut contributions = Vec::new();
        for (source, samples) in drawn {
            let m = measure(source, &samples);
            measures.push(m);
            if m.alive {
                contributions.push((source, samples));
            }
        }
        Draw {
            measures,
            contributions,
        }
    }
}

pub fn measure(source: Source, samples: &[u8]) -> Measure {
    let count = samples.len() / SAMPLE;
    let alive = if source.required() {
        generator_is_alive(samples)
    } else {
        alive(samples)
    };
    Measure {
        source,
        samples: count,
        distinct: distinct(samples),
        most_frequent: most_frequent(samples),
        alive,
    }
}

// The rule for a source whose unpredictability is being estimated: at least four distinct samples,
// and the upper bound of the share of the most frequent standing at or below one half. Written as
// a comparison of products, so no square root is taken and no division truncates a verdict.
pub fn alive(samples: &[u8]) -> bool {
    let count = samples.len() / SAMPLE;
    if count < MIN_DISTINCT || !samples.len().is_multiple_of(SAMPLE) {
        return false;
    }
    if distinct(samples) < MIN_DISTINCT {
        return false;
    }
    bound_holds(count, most_frequent(samples))
}

// n > 2 m and 414736 * m * (n - m) <= 15625 * (n - 2 m)^2 * (n - 1). The first condition is what
// makes the second sound: squaring both sides of the estimate is faithful only where the side
// being squared is non-negative, and that is exactly where the slack is positive. Every count here
// is bounded by the samples a source draws, so nothing approaches the width it is computed in.
pub fn bound_holds(count: usize, most_frequent: usize) -> bool {
    // A count no draw of this protocol produces is not a measurement, and admitting one would
    // put the products below past the width they are computed in. Four thousand million samples
    // is a source of thirty-two gigabytes; the largest this set draws is two hundred and
    // fifty-six.
    if count > u32::MAX as usize {
        return false;
    }
    if count <= 2 * most_frequent || count < 2 {
        return false;
    }
    let n = count as u128;
    let m = most_frequent as u128;
    let slack = n - 2 * m;
    CONFIDENCE_NUM * m * (n - m) <= CONFIDENCE_DEN * slack * slack * (n - 1)
}

// The rule for the generator of the operating system: it answered with a whole block, and that
// block passes the four health tests. A generator returning one repeated value is caught by the
// repetition count and by the distinctness test at once.
fn generator_is_alive(block: &[u8]) -> bool {
    crate::health(block, None).is_ok()
}

fn sorted(samples: &[u8]) -> Vec<&[u8]> {
    let mut v: Vec<&[u8]> = samples.chunks_exact(SAMPLE).collect();
    v.sort_unstable();
    v
}

fn distinct(samples: &[u8]) -> usize {
    let mut v = sorted(samples);
    v.dedup();
    v.len()
}

fn most_frequent(samples: &[u8]) -> usize {
    let v = sorted(samples);
    let mut best = 0usize;
    let mut run = 0usize;
    let mut previous: Option<&[u8]> = None;
    for sample in v {
        if Some(sample) == previous {
            run += 1;
        } else {
            run = 1;
            previous = Some(sample);
        }
        best = best.max(run);
    }
    best
}

// The cryptographic source of the operating system: the one source the set requires. An error
// from it yields no samples, and the draw refuses rather than proceeding without it.
fn operating_system() -> Zeroizing<Vec<u8>> {
    let mut block = Zeroizing::new(vec![0u8; 32]);
    if getrandom::getrandom(&mut block[..]).is_err() {
        return Zeroizing::new(Vec::new());
    }
    block
}

// The jitter of execution: one short arithmetic work timed many times. The low bits of the
// timings are what the operating system and its generator do not produce.
fn jitter() -> Zeroizing<Vec<u8>> {
    let mut out = Zeroizing::new(Vec::with_capacity(JITTER_SAMPLES * SAMPLE));
    let mut accumulator: u64 = 0x9E37_79B9_7F4A_7C15;
    for _ in 0..JITTER_SAMPLES {
        let start = Instant::now();
        // The work must stand well above the resolution of the clock, or every sample reads
        // the same number and the aliveness rule refuses the source — as it should.
        for i in 0..4_096u64 {
            accumulator = accumulator
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(i | 1);
            std::hint::black_box(accumulator);
        }
        out.extend_from_slice(&(start.elapsed().as_nanos() as u64).to_le_bytes());
    }
    out
}

// The latency of memory: a walk along a chain of references past the near levels of cache.
// What decides each step is what stands in cache now, the work of neighbouring cores and the
// memory controller — a mechanism other than the timing of pure arithmetic.
fn memory() -> Zeroizing<Vec<u8>> {
    const CELLS: usize = CELLS_OF_THE_WALK;
    const STRIDE: usize = STRIDE_OF_THE_WALK;
    let mut chain = vec![0usize; CELLS];
    let mut index = 0usize;
    for slot in chain.iter_mut() {
        index = (index + STRIDE) % CELLS;
        *slot = index;
    }
    let mut out = Zeroizing::new(Vec::with_capacity(MEMORY_SAMPLES * SAMPLE));
    let mut position = 0usize;
    for _ in 0..MEMORY_SAMPLES {
        let start = Instant::now();
        for _ in 0..1_024 {
            position = chain[position];
            std::hint::black_box(position);
        }
        out.extend_from_slice(&(start.elapsed().as_nanos() as u64).to_le_bytes());
    }
    chain.zeroize();
    out
}

// The drift of the quartz: the clock that counts against the clock that names the date. The low
// bits of their disagreement are a physical property of this crystal, which no outside party
// reproduces; the high bits, which merely say how much time passed, are dropped by the
// subtraction.
fn quartz() -> Zeroizing<Vec<u8>> {
    let mut out = Zeroizing::new(Vec::with_capacity(QUARTZ_SAMPLES * SAMPLE));
    for _ in 0..QUARTZ_SAMPLES {
        let monotonic = Instant::now();
        let wall_before = wall_nanos();
        let mut accumulator: u64 = wall_before;
        for i in 0..1_024u64 {
            accumulator = accumulator
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(i | 1);
            std::hint::black_box(accumulator);
        }
        let by_crystal = monotonic.elapsed().as_nanos() as u64;
        let by_calendar = wall_nanos().wrapping_sub(wall_before);
        out.extend_from_slice(&by_crystal.wrapping_sub(by_calendar).to_le_bytes());
    }
    out
}

fn wall_nanos() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
}

// The scheduling: how far a neighbouring thread advances while this one works. Where a second
// thread is not admitted at all the samples agree and the source is honestly dead.
fn scheduler() -> Zeroizing<Vec<u8>> {
    let counter = Arc::new(AtomicU64::new(0));
    let stop = Arc::new(AtomicU64::new(0));
    let worker = {
        let counter = Arc::clone(&counter);
        let stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("montana-scheduler-probe".into())
            .spawn(move || {
                while stop.load(Ordering::Relaxed) == 0 {
                    counter.fetch_add(1, Ordering::Relaxed);
                }
            })
            .ok()
    };
    // A source that could not start its probe is absent, not still. Were the samples taken anyway,
    // the counter would never move and this source would hand back its full count of identical
    // readings — an array that claims to be a measurement of something that never ran. Absence is
    // told apart from a machine that gave the probe no time, and both are told apart from a
    // reading: the first returns nothing, the second returns samples the bound refuses, the third
    // returns samples the bound accepts.
    let Some(worker) = worker else {
        return Zeroizing::new(Vec::new());
    };
    let mut out = Zeroizing::new(Vec::with_capacity(SCHEDULER_SAMPLES * SAMPLE));
    let mut last = counter.load(Ordering::Relaxed);
    for _ in 0..SCHEDULER_SAMPLES {
        let mut accumulator: u64 = 0x2545_F491_4F6C_DD1D;
        for i in 0..8_192u64 {
            accumulator = accumulator
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(i | 1);
            std::hint::black_box(accumulator);
        }
        thread::yield_now();
        let now = counter.load(Ordering::Relaxed);
        out.extend_from_slice(&now.wrapping_sub(last).to_le_bytes());
        last = now;
    }
    stop.store(1, Ordering::Relaxed);
    let _ = worker.join();
    out
}

// The overshoot of the timer: the shortest sleep asked for against the sleep received. What is
// taken is the overshoot and never the interval.
fn timer() -> Zeroizing<Vec<u8>> {
    const ASKED_NANOS: u64 = ASKED_OF_THE_TIMER;
    let mut out = Zeroizing::new(Vec::with_capacity(TIMER_SAMPLES * SAMPLE));
    for _ in 0..TIMER_SAMPLES {
        let start = Instant::now();
        thread::sleep(Duration::from_nanos(ASKED_NANOS));
        let received = start.elapsed().as_nanos() as u64;
        out.extend_from_slice(&received.wrapping_sub(ASKED_NANOS).to_le_bytes());
    }
    out
}

// Draws every source once, measures each on its own samples, and keeps the contributions of
// the living alone. Of the crate, for the same reason `mix` is.
pub(crate) fn draw() -> Draw {
    let drawn: Vec<(Source, Zeroizing<Vec<u8>>)> = vec![
        (Source::OperatingSystem, operating_system()),
        (Source::Jitter, jitter()),
        (Source::Memory, memory()),
        (Source::Quartz, quartz()),
        (Source::Scheduler, scheduler()),
        (Source::Timer, timer()),
    ];
    Draw::of(drawn)
}

// The five sources of the machine alone, without the generator of the operating system: the
// self-test holds one system block fixed and asks whether these differ between two draws.
pub(crate) fn draw_machine_sources() -> Vec<(Source, Zeroizing<Vec<u8>>)> {
    vec![
        (Source::Jitter, jitter()),
        (Source::Memory, memory()),
        (Source::Quartz, quartz()),
        (Source::Scheduler, scheduler()),
        (Source::Timer, timer()),
    ]
}

// The mixing over parts a caller states, each with the place of the source it stands for: the
// frozen vector of the set writes its sources as literals at named places, so the check needs a
// door that takes them. A birth mixes what it drew and measured and never what a caller hands it.
pub fn mix_of_stated_sources(parts: &[(u8, &[u8])]) -> Option<[u8; 32]> {
    // The place of a source is of one byte and the block that follows it is of no fixed width, so
    // the block stands after the count of its bytes. The builder writes that count; a block longer
    // than the count can hold is refused rather than written truncated, because a truncated length
    // is two different sets of sources sharing one preimage.
    let mut preimage = Preimage::under(domain::MT_ENTROPY_MIX);
    for (place, part) in parts {
        preimage = preimage.fixed(&[*place]).counted(part).ok()?;
    }
    Some(preimage.finish())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn samples_of(values: &[u64]) -> Vec<u8> {
        values.iter().flat_map(|v| v.to_le_bytes()).collect()
    }

    #[test]
    fn a_source_that_repeats_one_sample_is_not_alive() {
        assert!(!alive(&samples_of(&[7, 7, 7, 7, 7, 7, 7, 7])));
    }

    #[test]
    fn two_values_alternating_are_not_a_source() {
        assert!(!alive(&samples_of(&[0, 1, 0, 1, 0, 1, 0, 1])));
    }

    #[test]
    fn a_majority_of_one_value_is_not_alive() {
        // Five of eight samples equal: four distinct values stand, and still the best guess
        // wins more often than half the time.
        assert!(!alive(&samples_of(&[7, 7, 7, 7, 7, 1, 2, 3])));
    }

    #[test]
    fn a_share_a_short_run_does_not_support_is_refused() {
        // Half of eight samples: the share alone would call this alive at exactly the bound, and
        // the bound of the standard refuses it, because eight samples support no such claim.
        assert!(!alive(&samples_of(&[7, 7, 7, 7, 1, 2, 3, 4])));
        // What the bound admits at that count is a source that repeats nothing.
        assert!(alive(&samples_of(&[1, 2, 3, 4, 5, 6, 7, 8])));
    }

    #[test]
    fn the_bound_is_the_one_the_standard_gives_and_it_loosens_as_the_run_grows() {
        // The same observed share is refused on a short run and admitted on a long one, which is
        // the whole difference between the share and its upper bound.
        assert!(!bound_holds(32, 9 + 1));
        assert!(bound_holds(32, 9));
        assert!(bound_holds(128, 40));
        assert!(!bound_holds(128, 50));
        // A share at or above one half is refused at every count.
        for count in [8usize, 32, 128, 256] {
            assert!(!bound_holds(count, count / 2), "{count}");
        }
        // And the two integers are four times the square of the point of the normal law, exactly:
        // z squared is 6.635776, and four times it is 26.543104.
        assert_eq!(CONFIDENCE_NUM * 1_000_000, CONFIDENCE_DEN * 26_543_104);
    }

    #[test]
    fn the_generator_is_judged_by_the_health_of_its_block_and_not_by_a_share() {
        // A block of thirty-two bytes drawn from a healthy generator passes; one repeated value
        // fails the health tests, which is the failure that rule exists to catch.
        let mut block = [0u8; 32];
        for (i, byte) in block.iter_mut().enumerate() {
            *byte = i as u8;
        }
        assert!(measure(Source::OperatingSystem, &block).alive);
        assert!(!measure(Source::OperatingSystem, &[7u8; 32]).alive);
        assert!(!measure(Source::OperatingSystem, &[]).alive);
    }

    #[test]
    fn too_few_samples_are_not_a_source_whatever_they_hold() {
        assert!(!alive(&samples_of(&[1, 2, 3])));
        assert!(!alive(&[]));
    }

    #[test]
    fn no_source_of_the_machine_is_constant_and_its_measures_are_its_own() {
        // What a test may assert is a property of the code: every source produces the count of
        // samples it claims, its measures agree with each other, and none of them stands still.
        // Whether a source is alive is a property of the machine at that second — a busy one puts
        // a timing source past the bound, which is what the floor of living sources is for — and
        // asserting it here would make the suite fail for a reason that is not a defect.
        for (source, samples, expected) in [
            (Source::Jitter, jitter(), JITTER_SAMPLES),
            (Source::Memory, memory(), MEMORY_SAMPLES),
            (Source::Quartz, quartz(), QUARTZ_SAMPLES),
            (Source::Scheduler, scheduler(), SCHEDULER_SAMPLES),
            (Source::Timer, timer(), TIMER_SAMPLES),
        ] {
            let m = measure(source, &samples);
            assert!(
                m.samples == expected || m.samples == 0,
                "{source:?} claims {} samples, where the count is {expected} or none at all",
                m.samples
            );
            assert!(m.distinct <= m.samples, "{source:?}");
            assert!(m.most_frequent <= m.samples, "{source:?}");
            // Standing still is a property of the machine at that second, not of the code, and the
            // comment above says so. What is a property of the code, and what is asserted here, is
            // that a source standing still is reported dead rather than counted. A second machine
            // found this: on a quiet server the probe of the scheduler stood still once in thirty
            // draws, and the assertion that stood here failed for a reason that was not a defect.
            if m.distinct < MIN_DISTINCT {
                assert!(
                    !m.alive,
                    "{source:?} stands nearly still at {} distinct of {} samples and is counted \
                     alive",
                    m.distinct, m.samples
                );
            }
        }
    }

    #[test]
    fn a_draw_of_this_machine_clears_the_floor_of_living_sources() {
        let drawn = draw();
        assert!(
            drawn.alive() >= 3,
            "living sources: {} — measures {:?}",
            drawn.alive(),
            drawn.measures
        );
    }

    #[test]
    fn a_dead_source_leaves_none_of_the_three() {
        // The mixing of two parts differs from the mixing of the same two with an empty third,
        // which is what a place and a length for a dead source would produce.
        let a = mix_of_stated_sources(&[(0, &[1u8; 32]), (1, &[2u8; 32])]);
        let b = mix_of_stated_sources(&[(0, &[1u8; 32]), (1, &[2u8; 32]), (2, &[])]);
        assert!(a.is_some() && b.is_some());
        assert_ne!(a, b);
    }

    #[test]
    fn no_two_different_sets_collapse_into_one_input() {
        // Without the length these two would share a preimage.
        assert_ne!(
            mix_of_stated_sources(&[(0, b"ab"), (1, b"cd")]),
            mix_of_stated_sources(&[(0, b"abc"), (1, b"d")])
        );
        // Without the place these two would: the same bytes surviving at another place is a
        // different set of sources, and the preimage says so.
        assert_ne!(
            mix_of_stated_sources(&[(0, &[1u8; 32]), (1, &[2u8; 32])]),
            mix_of_stated_sources(&[(0, &[1u8; 32]), (2, &[2u8; 32])])
        );
    }

    #[test]
    fn the_place_of_every_source_is_its_row_of_the_table() {
        for (row, source) in Source::ALL.iter().enumerate() {
            assert_eq!(usize::from(source.place()), row);
        }
    }

    #[test]
    fn a_draw_reports_every_source_and_mixes_only_the_living() {
        let first = draw();
        assert_eq!(first.measures.len(), Source::ALL.len());
        for (m, source) in first.measures.iter().zip(Source::ALL.iter()) {
            assert_eq!(m.source, *source);
        }
        assert!(first.alive() >= 3, "living sources: {}", first.alive());
        let second = draw();
        assert_ne!(
            first.mix().expect("the samples fit the field")[..],
            second.mix().expect("the samples fit the field")[..]
        );
    }
}

#[cfg(test)]
mod width_tests {
    use super::*;

    #[test]
    fn a_part_longer_than_its_length_field_is_refused_rather_than_truncated() {
        let long = vec![0u8; usize::from(u16::MAX) + 1];
        assert_eq!(mix_of_stated_sources(&[(0, &long)]), None);
        let fits = vec![0u8; usize::from(u16::MAX)];
        assert!(mix_of_stated_sources(&[(0, &fits)]).is_some());
    }

    #[test]
    fn a_count_no_draw_produces_is_not_a_measurement() {
        assert!(!bound_holds(usize::MAX, 1));
        assert!(!bound_holds((u32::MAX as usize) + 1, 1));
        assert!(bound_holds(u32::MAX as usize, 1));
    }
}
