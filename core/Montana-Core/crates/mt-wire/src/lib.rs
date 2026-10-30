// The wire. Everything that crosses between two machines is one object of one length, sealed
// twice, and its three visible parts say nothing: a label that names one step, a nonce, and bytes
// indistinguishable from noise. The set states all of it in `docs/Montana Canon.md` — "The cell,
// and the two seals it carries", "The messages of the wire", "How a message crosses a link" and
// "The erasure code of a delivery" — and this is their one transcription.
//
// No width here is written twice: every one of them comes from the Decree through `mt-genesis` or
// from the sizes of `mt-codec`, and the arithmetic that turns those into the widths of a cell
// stands in this file alone.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod cell;
pub mod draw;
pub mod erasure;
pub mod handshake;
pub mod link;
pub mod links;
pub mod message;
pub mod publish;

use mt_codec::size;

#[derive(Debug, PartialEq, Eq)]
pub enum WireError {
    // A unit of the wrong length is discarded in silence, and the discard names nobody; what this
    // carries is what the caller needs to know, never what it would tell anyone else.
    WrongLength { expected: usize, found: usize },
    Sealing,
    Opening,
    // The Decree names every width this crate reads; a tree without it is not this protocol.
    DecreeIncomplete,
    // A value this wire requires to be drawn could not be drawn. Nothing proceeds without it: a
    // nonce that repeats under one key destroys the confidentiality of both units sealed under it,
    // and a slot of the seal array left at a value nobody drew says how far a cell has come.
    Undrawn,
    // A group of a delivery is reconstructed from exactly the count of cells the code needs, and
    // from no fewer.
    TooFewCells { needed: usize, held: usize },
    Singular,
}

fn scalar(name: &str) -> Result<usize, WireError> {
    let value = mt_genesis::scalar(name).ok_or(WireError::DecreeIncomplete)?;
    usize::try_from(value).map_err(|_| WireError::DecreeIncomplete)
}

// The one length of everything that crosses this wire.
pub fn cell_bytes() -> Result<usize, WireError> {
    scalar("cell_bytes")
}

// The slots of the seal array: one per possible step, full from the origin.
pub fn path_max() -> Result<usize, WireError> {
    scalar("path_max")
}

// What a seal of a step and a label of a step take: the same width, which the set fixes once.
// The register of the serializations this crate holds, written once and compared with the set by
// the gate: a layout of the wire the set lays out and this tree does not hold is named as awaiting
// its stage rather than passing in silence.
// The layouts of the wire this crate holds, named as the set names them. The gate compares this
// list with the layouts the set lays out, so a layout of the wire the set states and this tree does
// not hold is caught from the side that can be counted rather than remembered.
pub const NAMES: &[&str] = &[
    "cell",
    "link_unit",
    "collect",
    "collect_public",
    "collect_answer",
    "wake_inline",
    "wake_handle",
    "head_query",
    "head_answer",
    "state_query",
    "state_answer",
    "slot_query",
    "slot_answer",
    "table_query",
    "table_answer",
    "renew_offer",
    "renew_answer",
    "renew_finish",
];

pub const SEAL_BYTES: usize = size::STEP_SEAL;
pub const LABEL_BYTES: usize = size::TAG;

// The bytes under the outer seal: the cell without its label, its nonce and the tag of that seal.
pub fn outer_plaintext_bytes() -> Result<usize, WireError> {
    Ok(cell_bytes()? - LABEL_BYTES - size::AEAD_NONCE - size::AEAD_TAG)
}

// The pipe layer, opaque to every hop: what is left of the outer plaintext after the commitment of
// the machine the cell is for and the array of seals.
pub fn inner_bytes() -> Result<usize, WireError> {
    Ok(outer_plaintext_bytes()? - 32 - path_max()? * SEAL_BYTES)
}

pub fn inner_plaintext_bytes() -> Result<usize, WireError> {
    Ok(inner_bytes()? - size::AEAD_NONCE - size::AEAD_TAG)
}

// The bytes of a body one cell carries: the delivery layer without its identifier and the two
// counts that place a block inside its delivery.
pub fn chunk_bytes() -> Result<usize, WireError> {
    Ok(inner_plaintext_bytes()? - SEAL_BYTES - 2 - 2)
}

// The piece of a message one link unit carries: the outer plaintext without the two counts that
// place it inside its message and the byte that says which message of the set the pieces carry.
pub fn piece_bytes() -> Result<usize, WireError> {
    Ok(outer_plaintext_bytes()? - link::FRAMING_BYTES)
}

// A body laid into a block of one width, in a time that follows the width and never the length of
// the body. Every byte of the block is written: the body's byte where the body reaches that position,
// zero where it does not, chosen by a mask on the position rather than by a branch on it. A block
// that copied what was there and zeroed the rest took one time for a body filling its last block
// and another for a body barely reaching it (Welch's t of 34 and 52 over two thousand samples, in
// `tests/timing_cell.rs`), so the length the one width hides on the wire stood on the clock of the
// machine that cuts. The bytes written are the same either way; only the time is not.
//
// The byte is read at the position clamped to the last byte of the body, so that every position
// reads one byte and the mask alone decides what is kept. A body of nothing is read as one byte of
// zero under a mask of zero, by the same loop, so it costs what a body of one byte costs. Indexing
// the clamped position directly, with the body known to hold a byte, lets the compiler drop the
// check on every byte; the position is formed by a wrapping add because the release profile checks
// overflow, and a check that can panic inside the loop is a branch inside the loop. The first form
// of this function, which looked each byte up with `get` and a fallback and added with a check,
// cost seven times the copy it replaced (4.3 against 0.6 microseconds for three blocks, on the
// machine of the check); this form costs four times, the loop still reading one byte at a time
// through the clamped index, which is the price of a time that follows the width alone. No
// position of a block overflows: a body is bounded by the count of pieces a link declares and the
// count of cells a delivery declares, both of them sixteen bits.
pub(crate) fn lay(body: &[u8], at: usize, block: &mut [u8]) {
    let length = body.len();
    let source: &[u8] = if body.is_empty() { &[0u8] } else { body };
    let last = source.len() - 1;
    for (offset, slot) in block.iter_mut().enumerate() {
        let position = at.wrapping_add(offset);
        let mask = u8::from(position < length).wrapping_neg();
        *slot = source[position.min(last)] & mask;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_width_of_the_wire_follows_from_the_decree_and_the_sizes() {
        // Canon, "The cell, and the two seals it carries": the arithmetic of the set, recomputed
        // here from the Decree rather than restated.
        assert_eq!(cell_bytes(), Ok(1_232));
        assert_eq!(outer_plaintext_bytes(), Ok(1_188));
        assert_eq!(inner_bytes(), Ok(916));
        assert_eq!(inner_plaintext_bytes(), Ok(888));
        assert_eq!(chunk_bytes(), Ok(868));
        assert_eq!(piece_bytes(), Ok(1_183));
    }

    // What `lay` writes is exactly what a copy and a zero fill wrote: the body where it reaches, zeros
    // where it does not, an empty body all zeros. The time is the subject of `tests/timing_cell.rs`;
    // the bytes are the subject here.
    #[test]
    fn a_block_is_laid_as_a_copy_and_a_zero_fill_would_lay_it() {
        let body: Vec<u8> = (1..=10u8).collect();
        let mut block = [0xAAu8; 4];
        lay(&body, 0, &mut block);
        assert_eq!(block, [1, 2, 3, 4]);
        lay(&body, 8, &mut block);
        assert_eq!(block, [9, 10, 0, 0]);
        lay(&body, 12, &mut block);
        assert_eq!(block, [0, 0, 0, 0]);
        lay(&[], 0, &mut block);
        assert_eq!(block, [0, 0, 0, 0]);
    }
}
