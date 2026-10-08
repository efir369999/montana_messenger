// The root is never taken from a single source. Bitcoin Core is built the same way: the system
// generator is mixed with CPU instructions, time counters and an internal pool;
// a hardware wallet does likewise, adding its own randomness to foreign randomness.
//
// Combining rule: the absence of an optional source does not cancel birth, the absence of
// the system one does. The result is unpredictable as long as at least one source is unpredictable.
//
// SOURCE LIVENESS IS MEASURED, NOT ASSUMED. Previously three of five were counted alive by
// the fact that the code for them had run: the length of what was collected is constant, so the liveness flag was set
// always, so the counter never dropped below three on any machine — and the threshold it
// was introduced for could never fire. Now all seven follow one rule: a source is alive when its
// own measurements DIFFER from each other. A set of identical numbers is the absence of a source,
// named by its name.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use mt_codec::domain;
use zeroize::{Zeroize, Zeroizing};

use crate::sha256_raw;

pub const JITTER_ROUNDS: usize = 256;
pub const MEMORY_ROUNDS: usize = 128;
pub const QUARTZ_SAMPLES: usize = 64;
pub const SCHEDULER_SAMPLES: usize = 32;
pub const TIMER_SAMPLES: usize = 32;

// MEASURE IN CLOCK STEPS, NOT IN UNITS OF WORK (19.09.2026). The Apple clock ticks at 24 MHz — 41.67 ns,
// and the number of distinct values of a measurement of FIXED work falls as the die gets faster: on
// iPhone 17 (A19) 4096 multiplications fit into a handful of steps, "jitter" and "memory" went dead, and
// a live machine got a refusal — eleven failures for two testers in a week across five consecutive
// builds. The threshold "derived by measurement on this machine" was the constant of one machine.
//
// Now the work of each measurement is calibrated BY THE MEASURED QUANTITY ITSELF: it is doubled until
// trial measurements show a mode share of at most a quarter — a twofold margin to the liveness threshold of
// one half — and no fewer than TICKS_PER_SAMPLE steps OF THIS clock. The curve was measured (19.09, Apple M):
// 24 steps per measurement — mode 42 %, 181 — 22 %, 579 — 12 %, 1017 — 8 %, 1645 — 3 %: noise accumulates with
// work, quantisation stays constant, and the mode share falls monotonically. A fast die simply
// does more work until its measurements begin to differ. The liveness rule does not change — it
// begins to measure what it names, and on any die.
pub const TICKS_PER_SAMPLE: u64 = 256;
// Trial measurements per calibration step and the permitted mode share among them (at most a quarter).
const PROBE_SAMPLES: usize = 32;
const PROBE_MODE_NUM: usize = 1;
const PROBE_MODE_DEN: usize = 4;
// "Dead" is a property of the machine, not of an instant: the verdict is set only when the measurements do not differ
// in any of three windows, each four times wider than the previous (256, 1024, 4096 steps).
pub const PROOF_SCALES: [u64; 3] = [1, 4, 16];
// Calibration starts from this number of work units and doubles it until a measurement covers the window.
const CALIBRATION_START: u64 = 1_024;
const CALIBRATION_CAP: u64 = 1 << 28;
// Ceiling of one measurement: on a clock with a coarse step (a millisecond on some virtual machines) a window in
// steps would inflate a gather to minutes; above two milliseconds per measurement a source is honestly measured
// by what there is, and dies if it does not differ.
const MAX_SAMPLE_NS: u64 = 2_000_000;

// The liveness measure is the share of the MOST FREQUENT measurement, a min-entropy estimate by the most common value
// (NIST SP 800-90B, section 6.3.1). A share of at most one half means at least one bit of
// unpredictability per measurement. The threshold is derived by measurement, not assigned: on this machine the most frequent
// value takes two to twelve percent for all time-based sources, whereas for a
// dead source it takes all hundred. The margin is fourfold, and it holds when the machine is busy.
//
// The share of DISTINCT measurements is unsuitable for this role: it floats with machine load —
// seventy-five percent on an idle machine, forty on a busy one — and a threshold on it would refuse
// an honest phone in the middle of work. A false refusal is as bad as a false pass.
const MAX_REPEAT_NUM: usize = 1;
const MAX_REPEAT_DEN: usize = 2;
// Fewer than four distinct values — not a source, but oscillation between two numbers.
const MIN_DISTINCT_CHUNKS: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourceReport {
    pub os_csprng: bool,
    pub jitter: bool,
    pub memory: bool,
    pub quartz: bool,
    pub scheduler: bool,
    pub timer: bool,
    /// In which proof window the report was taken: 1, 4 or 16 (× TICKS_PER_SAMPLE clock steps).
    pub scale: u64,
    /// Clock step of this machine in nanoseconds.
    pub step_ns: u64,
}

impl SourceReport {
    pub const TOTAL: usize = 6;
    pub fn count(&self) -> usize {
        usize::from(self.os_csprng)
            + usize::from(self.jitter)
            + usize::from(self.memory)
            + usize::from(self.quartz)
            + usize::from(self.scheduler)
            + usize::from(self.timer)
    }
}

// One liveness rule for all seven sources: measurements must differ from each other.
// A source that ran and returned the same number is not counted alive.
fn is_alive(bytes: &[u8], samples: usize) -> bool {
    if samples < MIN_DISTINCT_CHUNKS || bytes.len() < samples * 8 {
        return false;
    }
    if distinct_chunks(bytes) < MIN_DISTINCT_CHUNKS {
        return false;
    }
    max_repeat(bytes) * MAX_REPEAT_DEN <= samples * MAX_REPEAT_NUM
}

// How many times the most frequent measurement repeats. The unpredictability estimate per
// measurement comes from it: the share of this value is the probability of guessing a measurement by the best guess.
fn max_repeat(bytes: &[u8]) -> usize {
    let mut v: Vec<&[u8]> = bytes.chunks(8).collect();
    v.sort_unstable();
    let mut best = 0usize;
    let mut run = 0usize;
    let mut prev: Option<&[u8]> = None;
    for c in v {
        if Some(c) == prev {
            run += 1;
        } else {
            run = 1;
            prev = Some(c);
        }
        if run > best {
            best = run;
        }
    }
    best
}

// Clock step of this machine: the smallest nonzero difference of two consecutive reads. A property of the hardware, not
// of an instant, so it is taken once per process. On Apple — 41–42 ns (24 MHz timebase).
pub fn clock_step_ns() -> u64 {
    static STEP: OnceLock<u64> = OnceLock::new();
    *STEP.get_or_init(|| {
        let mut best = u64::MAX;
        for _ in 0..4_096 {
            let a = Instant::now();
            let mut b = Instant::now();
            let mut spins = 0u32;
            while b == a && spins < 100_000 {
                b = Instant::now();
                spins += 1;
            }
            let d = b.duration_since(a).as_nanos() as u64;
            if d != 0 && d < best {
                best = d;
            }
        }
        if best == u64::MAX { 1 } else { best.max(1) }
    })
}

// How many units of work a measurement needs to (a) occupy at least TICKS_PER_SAMPLE × scale
// clock steps and (b) differ on a trial sample: mode at most a quarter. Doubling from
// CALIBRATION_START up to the ceiling; the calibration itself is a warm run, so the first cold
// measurement does not enter the sample. At the ceiling it returns what there is — the source is honestly measured and
// dies if it does not differ.
fn calibrate(scale: u64, mut work: impl FnMut(u64)) -> u64 {
    let need = Duration::from_nanos(
        TICKS_PER_SAMPLE.saturating_mul(scale).saturating_mul(clock_step_ns()).min(MAX_SAMPLE_NS),
    );
    let mut units = CALIBRATION_START;
    loop {
        let mut probe = Vec::with_capacity(PROBE_SAMPLES * 8);
        let mut total = Duration::ZERO;
        for _ in 0..PROBE_SAMPLES {
            let start = Instant::now();
            work(units);
            let took = start.elapsed();
            total += took;
            probe.extend_from_slice(&(took.as_nanos() as u64).to_le_bytes());
        }
        let long_enough = total / PROBE_SAMPLES as u32 >= need;
        let noisy_enough = distinct_chunks(&probe) >= MIN_DISTINCT_CHUNKS
            && max_repeat(&probe) * PROBE_MODE_DEN <= PROBE_SAMPLES * PROBE_MODE_NUM;
        let at_cap = units >= CALIBRATION_CAP || total / PROBE_SAMPLES as u32 >= Duration::from_nanos(MAX_SAMPLE_NS);
        if (long_enough && noisy_enough) || at_cap {
            return units;
        }
        units *= 2;
    }
}

fn lcg_work(units: u64) {
    let mut acc: u64 = 0x9E37_79B9_7F4A_7C15;
    for i in 0..units {
        acc = acc.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(i | 1);
        std::hint::black_box(acc);
    }
}

// Execution jitter: the same short work never takes exactly the same number of
// cycles — the cache, branch predictor, temperature and neighbouring cores interfere. The low bits of
// the measurements are the noise that neither the system kernel nor its generator provides.
fn jitter_bytes(scale: u64) -> Vec<u8> {
    // There must be noticeably more work than the clock resolution, otherwise a measurement returns the same
    // number and "jitter" turns out to be an invention. How much exactly is decided by the clock of this machine.
    let units = calibrate(scale, lcg_work);
    let mut out = Vec::with_capacity(JITTER_ROUNDS * 8);
    for _ in 0..JITTER_ROUNDS {
        let start = Instant::now();
        lcg_work(units);
        out.extend_from_slice(&(start.elapsed().as_nanos() as u64).to_le_bytes());
    }
    out
}

// Memory access: a walk along a chain of references inside a buffer deliberately larger than the near levels of the
// cache. The latency of each step is decided by what is in the cache right now, by the work of neighbouring cores and by the
// memory controller — a mechanism distinct from the jitter of pure computation.
fn memory_bytes(scale: u64) -> Vec<u8> {
    const CELLS: usize = 1 << 16; // 64K cells of 8 bytes = 512 KiB: past the near cache levels
    const STRIDE: usize = 20_011; // coprime with the length: the walk covers all cells
    let mut chain: Vec<usize> = vec![0; CELLS];
    let mut idx = 0usize;
    for slot in chain.iter_mut() {
        idx = (idx + STRIDE) % CELLS;
        *slot = idx;
    }
    // Cache size is a property of foreign hardware (the A19 L2 holds the whole buffer): the liveness of the source
    // rests not on a cache miss but on the walk along the chain taking at least K clock steps.
    let mut pos = 0usize;
    let steps = calibrate(scale, |n| {
        for _ in 0..n {
            pos = chain[pos];
            std::hint::black_box(pos);
        }
    });
    let mut out = Vec::with_capacity(MEMORY_ROUNDS * 8);
    for _ in 0..MEMORY_ROUNDS {
        let start = Instant::now();
        for _ in 0..steps {
            pos = chain[pos];
            std::hint::black_box(pos);
        }
        out.extend_from_slice(&(start.elapsed().as_nanos() as u64).to_le_bytes());
    }
    chain.zeroize();
    out
}


// Quartz. The clock that counts the passage of time inside the machine and the clock that names the calendar
// date are driven by different mechanisms: the first from the crystal, the second is corrected from outside. The divergence
// between them over a short interval is a physical property of THIS crystal: it drifts with
// temperature, supply and age, and no external party reproduces this divergence.
// The low bits are taken, where the noise is, not the high ones, where the progression is.
fn quartz_drift(scale: u64) -> Vec<u8> {
    let units = calibrate(scale, lcg_work);
    let mut out = Vec::with_capacity(QUARTZ_SAMPLES * 8);
    for _ in 0..QUARTZ_SAMPLES {
        let mono = Instant::now();
        let wall = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0);
        // work between two looks at the clock: the divergence accumulates over it, and there is
        // as much of it as needed for the divergence to accumulate to K steps
        lcg_work(units);
        let elapsed_mono = mono.elapsed().as_nanos() as u64;
        let wall_after = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0);
        let elapsed_wall = wall_after.wrapping_sub(wall);
        out.extend_from_slice(&elapsed_mono.wrapping_sub(elapsed_wall).to_le_bytes());
    }
    out
}

// Schedule. A neighbouring thread counts ahead while this one does a short piece of work; how much it
// managed is decided by the scheduler, the number of busy cores and foreign load — what neither the
// system generator nor the die knows. Where a second thread is not allowed at all, the measurements will coincide and the
// source will honestly turn out dead.
fn scheduler_bytes(scale: u64) -> Vec<u8> {
    let counter = Arc::new(AtomicU64::new(0));
    let stop = Arc::new(AtomicU64::new(0));
    let worker = {
        let counter = Arc::clone(&counter);
        let stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("mt-entropy-sched".into())
            .spawn(move || {
                while stop.load(Ordering::Relaxed) == 0 {
                    counter.fetch_add(1, Ordering::Relaxed);
                }
            })
            .ok()
    };
    // The measurement is "how much the neighbour managed while I worked", not "did the neighbour manage to be born at all":
    // in the first second after launch the scheduler does not give the new thread a quantum at once, and without this
    // wait all measurements would be zeros through the fault of the moment, not the machine. Wait no longer than 50 ms.
    let born = Instant::now();
    while counter.load(Ordering::Relaxed) == 0 && born.elapsed() < Duration::from_millis(50) {
        thread::yield_now();
    }
    let units = calibrate(scale, lcg_work);
    let mut out = Vec::with_capacity(SCHEDULER_SAMPLES * 8);
    let mut last = counter.load(Ordering::Relaxed);
    for _ in 0..SCHEDULER_SAMPLES {
        lcg_work(units);
        thread::yield_now();
        let now = counter.load(Ordering::Relaxed);
        out.extend_from_slice(&now.wrapping_sub(last).to_le_bytes());
        last = now;
    }
    stop.store(1, Ordering::Relaxed);
    if let Some(w) = worker {
        let _ = w.join();
    }
    out
}

// Timer. A sleep is asked for the smallest duration and gets more: the overshoot is decided by the ticking of
// interrupts, the sleep state of cores and foreign work. The overshoot is exactly what is taken — by how much the machine
// missed the request — not the duration itself.
fn timer_bytes() -> Vec<u8> {
    const ASKED_NS: u64 = 1_000;
    let mut out = Vec::with_capacity(TIMER_SAMPLES * 8);
    for _ in 0..TIMER_SAMPLES {
        let start = Instant::now();
        thread::sleep(Duration::from_nanos(ASKED_NS));
        let got = start.elapsed().as_nanos() as u64;
        out.extend_from_slice(&got.wrapping_sub(ASKED_NS).to_le_bytes());
    }
    out
}

// A cheap probe of the same die: two looks at clocks of different nature and nothing more.
// It costs nanoseconds, so it can be taken on EVERY output of the fast source — and then
// no output depends only on a seed taken sometime earlier.
pub(crate) fn quartz_tick() -> [u8; 24] {
    let mono = Instant::now();
    let wall = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0);
    let here = &mono as *const _ as u64;
    let mut out = [0u8; 24];
    out[..8].copy_from_slice(&(mono.elapsed().as_nanos() as u64).to_le_bytes());
    out[8..16].copy_from_slice(&wall.to_le_bytes());
    out[16..].copy_from_slice(&here.to_le_bytes());
    out
}

fn distinct_chunks(bytes: &[u8]) -> usize {
    let mut v: Vec<&[u8]> = bytes.chunks(8).collect();
    v.sort_unstable();
    v.dedup();
    v.len()
}

fn absorb(buf: &mut Vec<u8>, tag: u8, part: &[u8]) {
    buf.push(tag);
    buf.extend_from_slice(&(part.len() as u32).to_le_bytes());
    buf.extend_from_slice(part);
}

/// The measure of one source: how many measurements were taken, how many of them are distinct, how often
/// the most frequent repeats and whether the source is deemed alive. There is not a single byte of the source here and
/// there cannot be — only the count, because a person is entitled to see what their identity stands on, while
/// no one is entitled to see the measurements themselves.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourceMeasure {
    pub samples: u16,
    pub distinct: u16,
    pub max_repeat: u16,
    pub alive: bool,
}

impl SourceMeasure {
    fn of(bytes: &[u8], samples: usize) -> Self {
        SourceMeasure {
            samples: samples.min(u16::MAX as usize) as u16,
            distinct: distinct_chunks(bytes).min(u16::MAX as usize) as u16,
            max_repeat: max_repeat(bytes).min(u16::MAX as usize) as u16,
            alive: is_alive(bytes, samples),
        }
    }
}

/// Take the measures of all seven sources on THIS machine. The order is the same as in combining: the system
/// generator, the CPU instruction, execution jitter, memory access, quartz drift,
/// the schedule, the timer overshoot. It costs the same as birth itself and is taken on request.
pub fn measure_sources() -> [SourceMeasure; SourceReport::TOTAL] {
    let mut os = [0u8; 32];
    let os_ok = getrandom::getrandom(&mut os).is_ok();
    let jit = jitter_bytes(1);
    let mem = memory_bytes(1);
    let qz = quartz_drift(1);
    let sched = scheduler_bytes(1);
    let tim = timer_bytes();
    [
        SourceMeasure::of(if os_ok { &os[..] } else { &[] }, if os_ok { 4 } else { 0 }),
        SourceMeasure::of(&jit, JITTER_ROUNDS),
        SourceMeasure::of(&mem, MEMORY_ROUNDS),
        SourceMeasure::of(&qz, QUARTZ_SAMPLES),
        SourceMeasure::of(&sched, SCHEDULER_SAMPLES),
        SourceMeasure::of(&tim, TIMER_SAMPLES),
    ]
}

// ── Viewing window. Exists only under the test-vectors feature: in a production build
// these functions are physically absent from the library, and not a single byte of a source comes out.
// Only MEASURES come out — how many bytes the source gave, how many of them are distinct and
// whether it is deemed alive — because a person is entitled to see what their identity stands on.
#[cfg(any(test, feature = "vectors"))]
pub struct SourceFacts {
    pub name: &'static str,
    pub what: &'static str,
    pub bytes: usize,
    pub samples: usize,
    pub distinct_chunks: usize,
    pub distinct_bytes: usize,
    pub max_repeat: usize,
    pub alive: bool,
    pub alive_rule: &'static str,
}

#[cfg(any(test, feature = "vectors"))]
fn distinct_byte_values(bytes: &[u8]) -> usize {
    let mut seen = [false; 256];
    for b in bytes {
        seen[*b as usize] = true;
    }
    seen.iter().filter(|x| **x).count()
}

#[cfg(any(test, feature = "vectors"))]
fn facts(name: &'static str, what: &'static str, bytes: &[u8], samples: usize) -> SourceFacts {
    SourceFacts {
        name,
        what,
        bytes: bytes.len(),
        samples,
        distinct_chunks: distinct_chunks(bytes),
        distinct_bytes: distinct_byte_values(bytes),
        max_repeat: max_repeat(bytes),
        alive: is_alive(bytes, samples),
        alive_rule: "alive when the most frequent measurement takes no more than half and there are at least four distinct values",
    }
}

/// Calibration viewing window: the mode share and the number of distinct values of a measurement of `units` units of work —
/// the curve "noise versus amount of work" on this machine. Only under the test-vectors feature.
#[cfg(any(test, feature = "vectors"))]
pub fn jitter_probe(units: u64, samples: usize) -> (usize, usize, u64) {
    let mut out = Vec::with_capacity(samples * 8);
    let mut total = 0u64;
    for _ in 0..samples {
        let start = Instant::now();
        lcg_work(units);
        let ns = start.elapsed().as_nanos() as u64;
        total += ns;
        out.extend_from_slice(&ns.to_le_bytes());
    }
    (distinct_chunks(&out), max_repeat(&out) * 100 / samples, total / samples as u64)
}

#[cfg(any(test, feature = "vectors"))]
pub fn survey() -> Vec<SourceFacts> {
    let mut os = [0u8; 32];
    let os_ok = getrandom::getrandom(&mut os).is_ok();
    vec![
        facts(
            "system generator",
            "getrandom of the operating-system kernel; on a phone, the same one that stands behind SecRandomCopyBytes",
            if os_ok { &os[..] } else { &[] },
            if os_ok { 4 } else { 0 },
        ),
        facts(
            "execution jitter",
            "256 measurements of one and the same short piece of work: cache, branch predictor, temperature, neighbouring cores",
            &jitter_bytes(1),
            JITTER_ROUNDS,
        ),
        facts(
            "memory access",
            "128 measurements of a walk along a chain of references past the near cache levels: cache state, neighbouring cores, memory controller",
            &memory_bytes(1),
            MEMORY_ROUNDS,
        ),
        facts(
            "quartz drift",
            "64 divergences between the crystal's monotonic clock and the calendar clock, which is corrected from outside",
            &quartz_drift(1),
            QUARTZ_SAMPLES,
        ),
        facts(
            "schedule",
            "32 measurements of how much a neighbouring thread managed to count: scheduler, number of cores, foreign load",
            &scheduler_bytes(1),
            SCHEDULER_SAMPLES,
        ),
        facts(
            "timer overshoot",
            "32 overshoots above the smallest requested sleep: interrupt ticking, core sleep, foreign work",
            &timer_bytes(),
            TIMER_SAMPLES,
        ),
    ]
}

static LAST_REPORT: Mutex<Option<SourceReport>> = Mutex::new(None);

/// Report of the last gather — so that the log names what this run's randomness stands on
/// and which sources it deemed dead, if it did. There is not a single byte of a source here.
pub fn last_report() -> Option<SourceReport> {
    *LAST_REPORT.lock().unwrap_or_else(|e| e.into_inner())
}

/// A gather with proof: three windows, each four times wider. A live machine answers in the first;
/// "dead" is pronounced only when the measurements do not differ in any of them.
pub fn gather(os_block: &[u8]) -> (Zeroizing<[u8; 32]>, SourceReport) {
    let mut last = None;
    for scale in PROOF_SCALES {
        let (mixed, report) = gather_at(os_block, scale);
        let enough = report.count() >= crate::entropy::MIN_LIVE_SOURCES;
        last = Some((mixed, report));
        if enough {
            break;
        }
    }
    let (mixed, report) = last.expect("at least one proof window");
    *LAST_REPORT.lock().unwrap_or_else(|e| e.into_inner()) = Some(report);
    (mixed, report)
}

fn gather_at(os_block: &[u8], scale: u64) -> (Zeroizing<[u8; 32]>, SourceReport) {
    let jit = jitter_bytes(scale);
    let mem = memory_bytes(scale);
    let qz = quartz_drift(scale);
    let sched = scheduler_bytes(scale);
    let tim = timer_bytes();

    let mut buf: Vec<u8> =
        Vec::with_capacity(512 + jit.len() + mem.len() + qz.len() + sched.len() + tim.len());
    buf.extend_from_slice(domain::ENTROPY_MIX);
    buf.push(0x00);
    absorb(&mut buf, 1, os_block);
    absorb(&mut buf, 2, &jit);
    absorb(&mut buf, 3, &mem);
    absorb(&mut buf, 4, &qz);
    absorb(&mut buf, 5, &sched);
    absorb(&mut buf, 6, &tim);

    let mixed = sha256_raw(&buf);
    buf.zeroize();

    // The liveness of each source is computed from its own measurements — by one rule,
    // the same for all seven. None is declared alive by the fact that the code ran.
    let report = SourceReport {
        os_csprng: is_alive(os_block, os_block.len() / 8),
        jitter: is_alive(&jit, JITTER_ROUNDS),
        memory: is_alive(&mem, MEMORY_ROUNDS),
        quartz: is_alive(&qz, QUARTZ_SAMPLES),
        scheduler: is_alive(&sched, SCHEDULER_SAMPLES),
        timer: is_alive(&tim, TIMER_SAMPLES),
        scale,
        step_ns: clock_step_ns(),
    };
    (Zeroizing::new(mixed), report)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_constant_source_is_not_alive() {
        // Eight identical measurements: the code ran, there is no source.
        let dead = vec![0x11u8; 8 * 8];
        assert!(!is_alive(&dead, 8), "constant measurements must not be counted alive");
    }

    #[test]
    fn a_varying_source_is_alive() {
        let mut live = Vec::new();
        for i in 0..8u64 {
            live.extend_from_slice(&(i * 1_000_003).to_le_bytes());
        }
        assert!(is_alive(&live, 8));
    }

    #[test]
    fn a_dominating_value_is_not_alive() {
        // Eight measurements, five of them the same number: there are enough distinct values, but guessing
        // a measurement by the best guess succeeds more often than in half the cases.
        let mut lopsided = Vec::new();
        for _ in 0..5 {
            lopsided.extend_from_slice(&7u64.to_le_bytes());
        }
        for i in 1..4u64 {
            lopsided.extend_from_slice(&(i * 1_000_003).to_le_bytes());
        }
        assert!(!is_alive(&lopsided, 8), "skew toward one value — the source is dead");
    }

    #[test]
    fn two_values_alternating_is_not_alive() {
        let mut two = Vec::new();
        for i in 0..8u64 {
            two.extend_from_slice(&(i % 2).to_le_bytes());
        }
        assert!(!is_alive(&two, 8), "oscillation between two numbers is not counted as a source");
    }

    #[test]
    fn jitter_is_not_constant() {
        let a = jitter_bytes(1);
        assert!(is_alive(&a, JITTER_ROUNDS), "jitter must differ");
    }

    #[test]
    fn memory_is_not_constant() {
        let m = memory_bytes(1);
        assert!(is_alive(&m, MEMORY_ROUNDS), "memory access must differ");
    }

    #[test]
    fn quartz_is_not_constant() {
        let q = quartz_drift(1);
        assert!(is_alive(&q, QUARTZ_SAMPLES), "quartz must differ");
    }

    #[test]
    fn scheduler_is_not_constant() {
        let s = scheduler_bytes(1);
        assert!(is_alive(&s, SCHEDULER_SAMPLES), "the schedule must differ");
    }

    #[test]
    fn timer_is_not_constant() {
        let t = timer_bytes();
        assert!(is_alive(&t, TIMER_SAMPLES), "timer overshoot must differ");
    }

    // Synthetic measurements quantised by the Apple clock step (42 ns). The vector catches an implementation
    // that measures FIXED work regardless of clock resolution: on a fast die its
    // measurement fits in 900 ns ± 3 % — three distinct values, mode above half, "dead";
    // a measurement stretched to 256 steps (10.7 µs ± 3 %) leaves the same clock alive.
    fn quantised(base_ns: u64, samples: usize) -> Vec<u8> {
        let step = 42u64;
        let mut out = Vec::with_capacity(samples * 8);
        let mut x: u64 = 0x2545_F491_4F6C_DD1D;
        for _ in 0..samples {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let spread = base_ns * 6 / 100 + 1;
            let noise = (x % spread) as i64 - (base_ns * 3 / 100) as i64;
            let v = ((base_ns as i64 + noise) as u64 / step) * step;
            out.extend_from_slice(&v.to_le_bytes());
        }
        out
    }

    #[test]
    fn a_fixed_work_sample_dies_on_a_fast_clock_and_a_calibrated_one_lives() {
        assert!(!is_alive(&quantised(900, JITTER_ROUNDS), JITTER_ROUNDS), "900 ns on a 42 ns step must be dead");
        let long = TICKS_PER_SAMPLE * 42;
        assert!(is_alive(&quantised(long, JITTER_ROUNDS), JITTER_ROUNDS), "256 steps must be alive");
    }

    #[test]
    fn calibration_spans_the_window() {
        let step = clock_step_ns();
        assert!(step >= 1 && step < 1_000_000, "clock step outside the reasonable range: {step}");
        let units = calibrate(1, lcg_work);
        let start = Instant::now();
        lcg_work(units);
        let took = start.elapsed().as_nanos() as u64;
        assert!(took >= TICKS_PER_SAMPLE * step / 2, "calibrated work {units} took {took} ns at step {step}");
    }

    #[test]
    fn a_live_machine_answers_in_the_first_window() {
        let (_, r) = gather(&[0x5Au8; 32]);
        assert_eq!(r.scale, 1, "a live machine must answer in the first window, answers in {}", r.scale);
        assert!(last_report().is_some());
    }

    #[test]
    fn six_sources_are_reported() {
        assert_eq!(SourceReport::TOTAL, 6);
        let (_, report) = gather(&[0u8; 32]);
        assert!(!report.os_csprng, "a block of all zeros is not counted alive");
        assert!(report.count() >= 3, "fewer than three live sources on this machine");
    }

    #[test]
    fn a_dead_system_block_is_survived_by_the_rest() {
        let (a, _) = gather(&[0u8; 32]);
        let (b, _) = gather(&[0u8; 32]);
        assert_ne!(a[..], b[..], "two gathers with one dead block must diverge");
    }
}
