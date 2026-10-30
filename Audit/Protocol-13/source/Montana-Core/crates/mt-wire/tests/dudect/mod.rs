// The one instrument of the timing tests of this crate, so that two files measuring two surfaces
// of the wire cannot drift apart in how they measure.
//
// The measurement follows the shape Reparaz, Balasch and Verbauwhede published as dudect
// (DATE 2017): two classes of input drawn once, their samples interleaved so that drift of the
// machine falls on both alike, the slowest tenth dropped because a scheduler interruption is not the
// code, and Welch's t over what remains. A t of ten is the threshold that work uses to call a leak.
//
// A file using this instrument carries, beside its measurements, a named wrong implementation the
// instrument is shown to catch, at every scale of cost it measures at: a scale that was never seen
// to move measures nothing, and one seen to move by a microsecond has not been seen to move by ten
// nanoseconds.

pub const SAMPLES: usize = 2_000;
pub const CROP: f64 = 0.9;
pub const THRESHOLD: f64 = 10.0;

// Deterministic bytes for a class of input: the same seed gives the same body on every run, so a
// measurement that moved did so because the code moved and not because the input did.
pub fn fill(seed: u64, into: &mut [u8]) {
    let mut x = seed | 1;
    for byte in into.iter_mut() {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        *byte = (x >> 24) as u8;
    }
}

pub fn welch(a: &[f64], b: &[f64]) -> f64 {
    let mean = |v: &[f64]| v.iter().sum::<f64>() / v.len() as f64;
    let (ma, mb) = (mean(a), mean(b));
    let var = |v: &[f64], m: f64| {
        v.iter().map(|x| (x - m) * (x - m)).sum::<f64>() / (v.len() as f64 - 1.0)
    };
    let (va, vb) = (var(a, ma), var(b, mb));
    let denominator = (va / a.len() as f64 + vb / b.len() as f64).sqrt();
    if denominator == 0.0 {
        return 0.0;
    }
    (ma - mb).abs() / denominator
}

pub fn cropped(mut samples: Vec<f64>) -> Vec<f64> {
    samples.sort_by(|x, y| x.partial_cmp(y).expect("a duration is a number"));
    samples.truncate((samples.len() as f64 * CROP) as usize);
    samples
}

// Welch's t between the running times of two closures, each timed `rounds` times, the two
// interleaved sample by sample. Both are run a few times first so that neither pays for a cold
// cache the other does not.
pub fn t_between<A: FnMut(), B: FnMut()>(rounds: usize, mut first: A, mut second: B) -> f64 {
    for _ in 0..16 {
        first();
        second();
    }
    let mut of_first = Vec::with_capacity(rounds);
    let mut of_second = Vec::with_capacity(rounds);
    for _ in 0..rounds {
        let start = std::time::Instant::now();
        first();
        of_first.push(start.elapsed().as_nanos() as f64);
        let start = std::time::Instant::now();
        second();
        of_second.push(start.elapsed().as_nanos() as f64);
    }
    welch(&cropped(of_first), &cropped(of_second))
}

// What a measurement found, said aloud: a test that passes in silence leaves no number behind, and
// a report of this instrument is a number. `cargo test -- --nocapture` shows it.
pub fn report(what: &str, rounds: usize, t: f64) {
    eprintln!("dudect: {what}: t = {t:.2} (threshold {THRESHOLD}, {rounds} samples per class)");
}
