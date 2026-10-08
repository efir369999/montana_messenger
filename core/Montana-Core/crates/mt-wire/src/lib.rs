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
    "proof_query",
    "proof_answer",
    "state_query",
    "state_answer",
    "slot_query",
    "slot_answer",
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
}
