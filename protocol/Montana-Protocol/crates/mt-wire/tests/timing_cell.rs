// PANIC-OK: a test reports by panicking; an unmet expectation here is the finding being raised.
//
// Montana carries no synthetic filler — the set forbids it (Network, "Nothing is made even") — but a
// delivery is padded from inside: the last block of a body is padded with zeros and the last group
// of a delivery is filled with blocks of zeros (`erasure::cut`, `erasure::groups`), and those blocks
// ride cells that must cost exactly what a cell of a letter costs — at the origin that seals them,
// at every hop that carries them, and on a link whose last piece is padding. An observer with a
// clock that told a padding block from a letter block would read, through the clock, the size the
// one width exists to hide.
//
// This file measures, rather than asserts, that a padding block and a letter block cost the same
// on every path of this crate where the two part ways only inside a seal. It uses the instrument of
// `tests/dudect` and, as that instrument requires, ends with the named wrong implementation it is
// shown to catch.

mod dudect;

use dudect::{fill, t_between, SAMPLES, THRESHOLD};
use mt_codec::size;
use mt_wire::cell::{self, Cell, Delivery, Routing};
use mt_wire::{erasure, link, LABEL_BYTES, SEAL_BYTES};

const PIPE_KEY: [u8; 32] = [0x44; 32];
const STEP_KEY: [u8; 32] = [0x11; 32];
const LABEL: [u8; LABEL_BYTES] = [0x22; LABEL_BYTES];
const NONCE: [u8; size::AEAD_NONCE] = [0x66; size::AEAD_NONCE];
const TARGET: [u8; 32] = [0x55; 32];
const OWNER: [u8; 32] = [0xEE; 32];
const NEXT_KEY: [u8; 32] = [0x77; 32];
const NEXT_LABEL: [u8; LABEL_BYTES] = [0x88; LABEL_BYTES];

// The block of zeros `erasure::groups` fills a last group with, and the block a letter rides in.
fn padding_block() -> Vec<u8> {
    vec![0u8; mt_wire::chunk_bytes().expect("the set fixes the width of a block")]
}

fn letter_block(seed: u64) -> Vec<u8> {
    let mut block = padding_block();
    fill(seed, &mut block);
    block
}

fn delivery_of(chunk: Vec<u8>) -> Delivery {
    Delivery {
        delivery_id: [0x33; SEAL_BYTES],
        block_index: 3,
        block_count: 16,
        chunk,
    }
}

// The origin's path for one block, with the nonces stated and the seal array drawn once, so that
// what is timed is the sealing and not the generator.
fn routing_of(delivery: &Delivery, seals: &[[u8; SEAL_BYTES]]) -> Routing {
    let inner = cell::seal_pipe_with_nonce(&PIPE_KEY, &NONCE, delivery).expect("the pipe seals");
    Routing {
        target_commit: TARGET,
        seals: seals.to_vec(),
        inner,
    }
}

fn cell_of(delivery: &Delivery, seals: &[[u8; SEAL_BYTES]]) -> Cell {
    cell::seal_cell_with_nonce(&STEP_KEY, &LABEL, &NONCE, &routing_of(delivery, seals))
        .expect("the cell seals")
}

// A cell that has crossed this many hops, each of another owner, every hop handing it back under
// the one step key so that the measured hop opens it exactly as it opens a cell from the origin.
fn after_hops(mut cell: Cell, hops: u8) -> Cell {
    for owner in 0..hops {
        cell = cell::carry(&STEP_KEY, &cell, &[0xA0 + owner; 32], &STEP_KEY, &LABEL)
            .expect("a hop carries");
    }
    cell
}

// The origin seals a block twice, under the pipe key and under the key of its first step. Both
// seals are ChaCha20-Poly1305 over a fixed width, and this stands over them: a padding block and a
// letter block leave the origin in one time.
#[test]
fn the_origin_seals_a_padding_block_and_a_letter_block_in_one_time() {
    let seals = mt_wire::draw::seals().expect("drawn");
    let padding = delivery_of(padding_block());
    let letter = delivery_of(letter_block(0x5EED_CE11_0000_0001));
    let seal = |delivery: &Delivery| {
        let _ = cell_of(delivery, &seals);
    };
    let t = t_between(SAMPLES, || seal(&padding), || seal(&letter));
    dudect::report("origin seals padding vs letter", SAMPLES, t);
    assert!(
        t < THRESHOLD,
        "the origin seals a padding block and a letter block in different times: t = {t:.2}, \
         above the threshold of {THRESHOLD}. A clock reads the size of a letter."
    );
}

// A hop opens the outer seal, writes its own seal at the slot that seal selects, and seals again
// under the next step. It never opens the pipe, so what the pipe carries must not reach its clock.
#[test]
fn a_hop_carries_a_padding_block_and_a_letter_block_in_one_time() {
    let seals = mt_wire::draw::seals().expect("drawn");
    let padding = cell_of(&delivery_of(padding_block()), &seals);
    let letter = cell_of(&delivery_of(letter_block(0x5EED_CE11_0000_0002)), &seals);
    let carry = |cell: &Cell| {
        let _ =
            cell::carry(&STEP_KEY, cell, &OWNER, &NEXT_KEY, &NEXT_LABEL).expect("the hop carries");
    };
    let t = t_between(SAMPLES, || carry(&padding), || carry(&letter));
    dudect::report("hop carries padding vs letter", SAMPLES, t);
    assert!(
        t < THRESHOLD,
        "a hop carries a padding block and a letter block in different times: t = {t:.2}, above \
         the threshold of {THRESHOLD}. A clock reads what the pipe carries."
    );
}

// The seal array is the one part of a cell that changes along a path, and a hop that cost more
// the further a cell had come would publish, to its own clock, what the drawn slots exist to hide.
// The two classes here are a cell fresh from the origin and one that has crossed six owners.
#[test]
fn a_hop_carries_a_cell_from_the_origin_and_one_that_has_travelled_in_one_time() {
    let seals = mt_wire::draw::seals().expect("drawn");
    let letter = delivery_of(letter_block(0x5EED_CE11_0000_0003));
    let fresh = cell_of(&letter, &seals);
    let travelled = after_hops(cell_of(&letter, &seals), 6);
    let carry = |cell: &Cell| {
        let _ =
            cell::carry(&STEP_KEY, cell, &OWNER, &NEXT_KEY, &NEXT_LABEL).expect("the hop carries");
    };
    let t = t_between(SAMPLES, || carry(&fresh), || carry(&travelled));
    dudect::report("hop carries fresh vs travelled", SAMPLES, t);
    assert!(
        t < THRESHOLD,
        "a hop carries a fresh cell and a travelled one in different times: t = {t:.2}, above \
         the threshold of {THRESHOLD}. A clock reads how far a cell has come."
    );
}

// A unit of a link is sealed exactly as a cell is, and the last piece of a message is padding. A
// unit whose plaintext is all padding and one carrying a full piece seal in one time.
#[test]
fn a_unit_of_padding_and_a_unit_of_a_message_seal_in_one_time() {
    let width = mt_wire::outer_plaintext_bytes().expect("the set fixes the width of a unit");
    let padding = vec![0u8; width];
    let mut message = vec![0u8; width];
    fill(0x5EED_CE11_0000_0004, &mut message);
    let seal = |plain: &[u8]| {
        let _ = link::seal_unit(&STEP_KEY, &LABEL, plain).expect("the unit seals");
    };
    let t = t_between(SAMPLES, || seal(&padding), || seal(&message));
    dudect::report("unit seals padding vs message", SAMPLES, t);
    assert!(
        t < THRESHOLD,
        "a unit of padding and a unit of a message seal in different times: t = {t:.2}, above \
         the threshold of {THRESHOLD}."
    );
}

// Cutting is where padding is born: a body is laid into blocks and the last block is filled with
// zeros, a message into pieces and the last piece likewise. Two bodies of one count of blocks —
// one filling its last block, one leaving it nearly all padding — must cut in one time, or the
// length the padding hides is read off the clock of the machine that cuts.
//
// A cutter is measured at more samples than a seal is. The copy that followed the length (one
// block at most, `src/erasure.rs` 237-239 at the baseline) is some ten nanoseconds of a cut of half
// a microsecond, where sparing a block the seal is two microseconds of two: at two thousand samples
// the first stood at t = 34 and 52 on an Apple M1 and at t = 0.2 to 9.3 on a four-core Linux
// server under a hypervisor, where the cutters of the baseline passed four runs in five. The noise
// of that machine comes in bursts that last longer than a sample, so timing many cuts per sample
// buys nothing — the bursts grow with the sample — and only the count of samples does: at fifty
// thousand the copy of the baseline stands at t near forty there and the cutters below at t near
// one. Four cuts per sample keep the clock's own cost out of the sample. The two power checks of
// the cutters at the end of this file are the proof that these numbers see the copy.
//
// The four stand down in the debug build and say so: a block laid without optimization costs a
// hundred microseconds where the copy they look for costs ten nanoseconds, so the debug build
// measures itself and not the code that ships (the baseline cutters passed it too). The release
// numbers are the ones that count, and the release build is where these four run.
const CUTTER_SAMPLES: usize = 50_000;
const CUTS_PER_SAMPLE: usize = 4;

// The two classes of every measurement of a cutter: a body of three full blocks and one of two
// blocks and a single byte, cutting into one count of blocks.
fn full_and_short(width: usize, seed: u64) -> (Vec<u8>, Vec<u8>) {
    let mut full = vec![0u8; 3 * width];
    fill(seed, &mut full);
    let short = full[..2 * width + 1].to_vec();
    (full, short)
}

#[cfg_attr(
    debug_assertions,
    ignore = "a measurement of a copy of ten nanoseconds is of the optimized build: cargo test --release"
)]
#[test]
fn cutting_a_body_that_fills_its_last_block_and_one_that_barely_does_costs_the_same() {
    let width = mt_wire::chunk_bytes().expect("the set fixes the width of a block");
    let (full, short) = full_and_short(width, 0x5EED_CE11_0000_0005);
    assert_eq!(
        erasure::cut(&full).expect("cuts").len(),
        erasure::cut(&short).expect("cuts").len(),
        "the two bodies must cut into one count of blocks"
    );
    let cuts = |body: &[u8]| {
        for _ in 0..CUTS_PER_SAMPLE {
            std::hint::black_box(erasure::cut(body).expect("cuts"));
        }
    };
    let t = t_between(CUTTER_SAMPLES, || cuts(&full), || cuts(&short));
    dudect::report("erasure::cut full vs short body", CUTTER_SAMPLES, t);
    assert!(
        t < THRESHOLD,
        "a body filling its last block and one barely reaching it cut in different times: \
         t = {t:.2}, above the threshold of {THRESHOLD}. A clock reads the length of a body."
    );
}

#[cfg_attr(
    debug_assertions,
    ignore = "a measurement of a copy of ten nanoseconds is of the optimized build: cargo test --release"
)]
#[test]
fn cutting_a_message_that_fills_its_last_piece_and_one_that_barely_does_costs_the_same() {
    let width = mt_wire::piece_bytes().expect("the set fixes the width of a piece");
    let (full, short) = full_and_short(width, 0x5EED_CE11_0000_0006);
    let kind = 0x01u8;
    assert_eq!(
        link::pieces(kind, &full).expect("cuts").len(),
        link::pieces(kind, &short).expect("cuts").len(),
        "the two messages must cut into one count of pieces"
    );
    let cuts = |message: &[u8]| {
        for _ in 0..CUTS_PER_SAMPLE {
            std::hint::black_box(link::pieces(kind, message).expect("cuts"));
        }
    };
    let t = t_between(CUTTER_SAMPLES, || cuts(&full), || cuts(&short));
    dudect::report("link::pieces full vs short message", CUTTER_SAMPLES, t);
    assert!(
        t < THRESHOLD,
        "a message filling its last piece and one barely reaching it cut in different times: \
         t = {t:.2}, above the threshold of {THRESHOLD}. A clock reads the length of a message."
    );
}

// The named wrong implementation the measurements above stand against: an origin that notices a
// block of zeros and spares it the seal — "padding needs no secrecy" — writing it under a tag of
// zeros and the pipe key untouched. It is the optimization a reader would call harmless, and it
// hands an observer the size of every letter by the time each cell takes. If the instrument could
// not see it, the measurements above would stand for nothing.
fn seal_pipe_that_leaks(delivery: &Delivery) -> Vec<u8> {
    if delivery.chunk.iter().all(|byte| *byte == 0) {
        let mut out = NONCE.to_vec();
        out.extend_from_slice(&delivery.delivery_id);
        out.extend_from_slice(&delivery.block_index.to_le_bytes());
        out.extend_from_slice(&delivery.block_count.to_le_bytes());
        out.extend_from_slice(&delivery.chunk);
        out.extend_from_slice(&[0u8; size::AEAD_TAG]);
        return out;
    }
    cell::seal_pipe_with_nonce(&PIPE_KEY, &NONCE, delivery).expect("the pipe seals")
}

#[test]
fn the_measurement_catches_an_origin_that_spares_a_padding_block_the_seal() {
    let padding = delivery_of(padding_block());
    let letter = delivery_of(letter_block(0x5EED_CE11_0000_0007));
    assert_eq!(
        seal_pipe_that_leaks(&padding).len(),
        seal_pipe_that_leaks(&letter).len(),
        "the wrong implementation keeps the one width, so only the clock tells it"
    );
    let t = t_between(
        SAMPLES,
        || {
            let _ = seal_pipe_that_leaks(&padding);
        },
        || {
            let _ = seal_pipe_that_leaks(&letter);
        },
    );
    dudect::report("power: origin sparing padding the seal", SAMPLES, t);
    assert!(
        t > THRESHOLD,
        "the instrument did not see an origin that spares a padding block the seal: t = {t:.2}. \
         Until it does, the measurements above stand for nothing."
    );
}

// The named wrong implementations the measurements above stand against, and the proof that the
// instrument sees them. Each file of this instrument shows the power of its measurements at every
// scale it measures at: a seal costs microseconds and a copy nanoseconds, and an instrument shown
// to see the one has not been shown to see the other.

// The cutter of the reference core as it stood at the baseline (`src/erasure.rs` 229-243 at
// 2c6951f), word for word: the last block copies `end - at` bytes, so one copy of up to one block
// follows the length of the body. The bytes it writes are the ones `erasure::cut` writes; only the
// time differs, which is what makes it the right wrong implementation for a clock.
fn cut_that_copies(body: &[u8]) -> Vec<Vec<u8>> {
    let width = mt_wire::chunk_bytes().expect("the set fixes the width of a block");
    let count = body.len().div_ceil(width).max(1);
    let mut out = Vec::with_capacity(count);
    for index in 0..count {
        let at = index * width;
        let end = body.len().min(at + width);
        let mut block = vec![0u8; width];
        if at < body.len() {
            block[..end - at].copy_from_slice(&body[at..end]);
        }
        out.push(block);
    }
    out
}

// The same for the link (`src/link.rs` 31-54 at the baseline).
fn pieces_that_copy(kind: u8, message: &[u8]) -> Vec<Vec<u8>> {
    let width = mt_wire::piece_bytes().expect("the set fixes the width of a piece");
    let count = message.len().div_ceil(width).max(1);
    let mut out = Vec::with_capacity(count);
    for index in 0..count {
        let at = index * width;
        let end = message.len().min(at + width);
        let mut piece = vec![0u8; link::FRAMING_BYTES + width];
        piece[..2].copy_from_slice(&(index as u16).to_le_bytes());
        piece[2..4].copy_from_slice(&(count as u16).to_le_bytes());
        piece[4] = kind;
        if at < message.len() {
            piece[link::FRAMING_BYTES..link::FRAMING_BYTES + (end - at)]
                .copy_from_slice(&message[at..end]);
        }
        out.push(piece);
    }
    out
}

#[cfg_attr(
    debug_assertions,
    ignore = "a measurement of a copy of ten nanoseconds is of the optimized build: cargo test --release"
)]
#[test]
fn the_measurement_catches_a_cutter_whose_copy_follows_the_length_of_the_body() {
    let width = mt_wire::chunk_bytes().expect("the set fixes the width of a block");
    let (full, short) = full_and_short(width, 0x5EED_CE11_0000_0008);
    for body in [&full, &short] {
        assert_eq!(
            cut_that_copies(body),
            erasure::cut(body).expect("cuts"),
            "the wrong implementation writes the bytes the right one writes, so only the clock tells it"
        );
    }
    let cuts = |body: &[u8]| {
        for _ in 0..CUTS_PER_SAMPLE {
            std::hint::black_box(cut_that_copies(body));
        }
    };
    let t = t_between(CUTTER_SAMPLES, || cuts(&full), || cuts(&short));
    dudect::report(
        "power: cutter copying what the body reaches",
        CUTTER_SAMPLES,
        t,
    );
    assert!(
        t > THRESHOLD,
        "the instrument did not see a cutter whose copy follows the length of the body: t = {t:.2}. \
         Until it does, the two measurements of the cutters stand for nothing."
    );
}

#[cfg_attr(
    debug_assertions,
    ignore = "a measurement of a copy of ten nanoseconds is of the optimized build: cargo test --release"
)]
#[test]
fn the_measurement_catches_a_link_whose_copy_follows_the_length_of_the_message() {
    let width = mt_wire::piece_bytes().expect("the set fixes the width of a piece");
    let (full, short) = full_and_short(width, 0x5EED_CE11_0000_0009);
    let kind = 0x01u8;
    for message in [&full, &short] {
        assert_eq!(
            pieces_that_copy(kind, message),
            link::pieces(kind, message).expect("cuts"),
            "the wrong implementation writes the bytes the right one writes, so only the clock tells it"
        );
    }
    let cuts = |message: &[u8]| {
        for _ in 0..CUTS_PER_SAMPLE {
            std::hint::black_box(pieces_that_copy(kind, message));
        }
    };
    let t = t_between(CUTTER_SAMPLES, || cuts(&full), || cuts(&short));
    dudect::report(
        "power: link copying what the message reaches",
        CUTTER_SAMPLES,
        t,
    );
    assert!(
        t > THRESHOLD,
        "the instrument did not see a link whose copy follows the length of the message: t = {t:.2}. \
         Until it does, the two measurements of the cutters stand for nothing."
    );
}
