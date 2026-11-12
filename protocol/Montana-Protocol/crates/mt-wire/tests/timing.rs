// PANIC-OK: a test reports by panicking; an unmet expectation here is the finding being raised.
//
// The field arithmetic of the code walks over the bytes of a body, and a body is a secret. If the
// walk took a different time for a byte of one value than for a byte of another, an observer with
// a clock would read the body through the clock rather than through the key. The construction
// closes this — the multiplication is branch-free and the table lookups are of fixed shape — and
// this file is the standing witness of it: it measures, rather than asserts, that the two classes
// of body cost the same.
//
// The instrument is the one of `tests/dudect`, shared with the measurements of the cell and the
// link in `tests/timing_cell.rs`, so that two surfaces of the wire are measured one way.

mod dudect;

use dudect::{fill, t_between, SAMPLES, THRESHOLD};
use mt_wire::erasure;

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

    let t = t_between(
        SAMPLES,
        || {
            let _ = erasure::parity(&zeros).expect("parity of a full group");
        },
        || {
            let _ = erasure::parity(&drawn).expect("parity of a full group");
        },
    );
    dudect::report("erasure::parity zeros vs drawn", SAMPLES, t);
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

    let t = t_between(
        SAMPLES / 4,
        || {
            let _ = erasure::reconstruct(&of_zeros_input).expect("reconstruction");
        },
        || {
            let _ = erasure::reconstruct(&of_drawn_input).expect("reconstruction");
        },
    );
    dudect::report("erasure::reconstruct zeros vs drawn", SAMPLES / 4, t);
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

    let t = t_between(
        SAMPLES / 8,
        || {
            let _ = parity_that_leaks(&zeros, &matrix);
        },
        || {
            let _ = parity_that_leaks(&drawn, &matrix);
        },
    );
    dudect::report(
        "power: multiplication returning early on a zero",
        SAMPLES / 8,
        t,
    );
    assert!(
        t > THRESHOLD,
        "the instrument did not see a multiplication that returns early on a zero: t = {t:.2}. \
         Until it does, the two measurements above stand for nothing."
    );
}
