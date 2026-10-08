// PANIC-OK: a test reports by panicking; an unmet expectation here is the finding being raised.
//
// The field arithmetic of the code walks over the bytes of a body, and a body is a secret. If the
// walk took a different time for a byte of one value than for a byte of another, an observer with
// a clock would read the body through the clock rather than through the key. The construction
// closes this — the multiplication is branch-free and the table lookups are of fixed shape — and
// this file is the standing witness of it: it measures, rather than asserts, that the two classes
// of body cost the same.
//
// The measurement follows the shape Reparaz, Balasch and Verbauwhede published as dudect
// (DATE 2017): two classes drawn once, their samples interleaved so that drift of the machine
// falls on both alike, the slowest tenth dropped because a scheduler interruption is not the code,
// and Welch's t over what remains. A t of ten is the threshold that work uses to call a leak.

use mt_wire::erasure;

const SAMPLES: usize = 2_000;
const CROP: f64 = 0.9;
const THRESHOLD: f64 = 10.0;

fn fill(seed: u64, into: &mut [u8]) {
    let mut x = seed | 1;
    for byte in into.iter_mut() {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        *byte = (x >> 24) as u8;
    }
}

fn blocks(seed: Option<u64>, count: usize, width: usize) -> Vec<Vec<u8>> {
    (0..count)
        .map(|i| {
            let mut block = vec![0u8; width];
            if let Some(s) = seed {
                fill(s.wrapping_add(i as u64 * 0x9E37_79B9), &mut block);
            }
            block
        })
        .collect()
}

fn welch(a: &[f64], b: &[f64]) -> f64 {
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

fn cropped(mut samples: Vec<f64>) -> Vec<f64> {
    samples.sort_by(|x, y| x.partial_cmp(y).expect("a duration is a number"));
    samples.truncate((samples.len() as f64 * CROP) as usize);
    samples
}

// The two classes are the extremes of what a body can be: a body of zeros, where every product is
// the trivial one, and a body of uniform bytes, where none of them is. An implementation that
// short-circuits a zero — the obvious optimization, and the one a compiler is glad to make — is
// what this measurement is here to catch.
#[test]
fn the_parity_of_a_group_costs_the_same_whatever_the_body_holds() {
    let width = mt_wire::chunk_bytes().expect("the set fixes the width of a block");
    let count = erasure::data().expect("the set fixes the blocks of a group");
    let zeros = blocks(None, count, width);
    let drawn = blocks(Some(0x5EED_1234_ABCD_0001), count, width);

    for warm in [&zeros, &drawn] {
        for _ in 0..64 {
            let _ = erasure::parity(warm).expect("parity of a full group");
        }
    }

    let mut of_zeros = Vec::with_capacity(SAMPLES);
    let mut of_drawn = Vec::with_capacity(SAMPLES);
    for _ in 0..SAMPLES {
        let start = std::time::Instant::now();
        let _ = erasure::parity(&zeros).expect("parity of a full group");
        of_zeros.push(start.elapsed().as_nanos() as f64);
        let start = std::time::Instant::now();
        let _ = erasure::parity(&drawn).expect("parity of a full group");
        of_drawn.push(start.elapsed().as_nanos() as f64);
    }

    let t = welch(&cropped(of_zeros), &cropped(of_drawn));
    assert!(
        t < THRESHOLD,
        "the parity of a group of zeros and of a group of drawn bytes differ in time: \
         t = {t:.2}, above the threshold of {THRESHOLD}. A clock reads the body."
    );
}

// Reconstruction inverts a matrix whose rows are chosen by which cells are missing, and which
// cells are missing is public. What must not reach the clock is the content of the cells that
// arrived. The two classes here lose the same cells and differ only in what the survivors carry.
#[test]
fn reconstruction_costs_the_same_whatever_the_survivors_carry() {
    let width = mt_wire::chunk_bytes().expect("the set fixes the width of a block");
    let count = erasure::data().expect("the set fixes the blocks of a group");
    let lost = [0usize, 3, 7, 11];

    let present = |source: &[Vec<u8>]| -> Vec<(usize, Vec<u8>)> {
        erasure::encode(source)
            .expect("a full group encodes")
            .into_iter()
            .enumerate()
            .filter(|(index, _)| !lost.contains(index))
            .collect()
    };
    let of_zeros_input = present(&blocks(None, count, width));
    let of_drawn_input = present(&blocks(Some(0x5EED_1234_ABCD_0002), count, width));

    for warm in [&of_zeros_input, &of_drawn_input] {
        for _ in 0..16 {
            let _ = erasure::reconstruct(warm).expect("a group with four losses reconstructs");
        }
    }

    let mut of_zeros = Vec::with_capacity(SAMPLES / 4);
    let mut of_drawn = Vec::with_capacity(SAMPLES / 4);
    for _ in 0..SAMPLES / 4 {
        let start = std::time::Instant::now();
        let _ = erasure::reconstruct(&of_zeros_input).expect("reconstruction");
        of_zeros.push(start.elapsed().as_nanos() as f64);
        let start = std::time::Instant::now();
        let _ = erasure::reconstruct(&of_drawn_input).expect("reconstruction");
        of_drawn.push(start.elapsed().as_nanos() as f64);
    }

    let t = welch(&cropped(of_zeros), &cropped(of_drawn));
    assert!(
        t < THRESHOLD,
        "reconstruction of a group of zeros and of drawn bytes differ in time: \
         t = {t:.2}, above the threshold of {THRESHOLD}."
    );
}

// The measurement must be shown to have power, or it is a scale that measures nothing. This is the
// named wrong implementation the two tests above stand against: a multiplication that returns
// early on a zero operand, which is the optimization a reader of the code would call harmless and
// a compiler would make unasked. Over a body of zeros it does no work at all. If the instrument
// could not tell that apart from the branch-free form, a real leak would pass it in silence too.
fn multiply_that_leaks(a: u8, b: u8) -> u8 {
    if a == 0 || b == 0 {
        return 0;
    }
    let mut product = 0u8;
    let (mut x, mut y) = (a, b);
    while y != 0 {
        if y & 1 == 1 {
            product ^= x;
        }
        let carried = x & 0x80 != 0;
        x <<= 1;
        if carried {
            x ^= 0x1D;
        }
        y >>= 1;
    }
    product
}

fn parity_that_leaks(blocks: &[Vec<u8>], matrix: &[Vec<u8>]) -> Vec<Vec<u8>> {
    matrix
        .iter()
        .map(|row| {
            let mut out = vec![0u8; blocks[0].len()];
            for (block, coefficient) in blocks.iter().zip(row.iter()) {
                for (o, b) in out.iter_mut().zip(block.iter()) {
                    *o ^= multiply_that_leaks(*coefficient, *b);
                }
            }
            out
        })
        .collect()
}

#[test]
fn the_measurement_catches_a_multiplication_that_returns_early_on_a_zero() {
    let width = mt_wire::chunk_bytes().expect("the set fixes the width of a block");
    let count = erasure::data().expect("the set fixes the blocks of a group");
    let matrix = erasure::cauchy().expect("the set fixes the matrix");
    let zeros = blocks(None, count, width);
    let drawn = blocks(Some(0x5EED_1234_ABCD_0003), count, width);

    for warm in [&zeros, &drawn] {
        for _ in 0..8 {
            let _ = parity_that_leaks(warm, &matrix);
        }
    }

    let rounds = SAMPLES / 8;
    let mut of_zeros = Vec::with_capacity(rounds);
    let mut of_drawn = Vec::with_capacity(rounds);
    for _ in 0..rounds {
        let start = std::time::Instant::now();
        let _ = parity_that_leaks(&zeros, &matrix);
        of_zeros.push(start.elapsed().as_nanos() as f64);
        let start = std::time::Instant::now();
        let _ = parity_that_leaks(&drawn, &matrix);
        of_drawn.push(start.elapsed().as_nanos() as f64);
    }

    let t = welch(&cropped(of_zeros), &cropped(of_drawn));
    assert!(
        t > THRESHOLD,
        "the instrument did not see a multiplication that returns early on a zero: t = {t:.2}. \
         Until it does, the two measurements above stand for nothing."
    );
}
