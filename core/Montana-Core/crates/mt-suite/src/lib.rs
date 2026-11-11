// The cryptographic suite of Montana. The set states every part of it in
// `docs/Montana Canon.md`, "Primitives": ML-DSA-65 in its deterministic form, ML-KEM-768 and
// ChaCha20-Poly1305.
//
// All three are standards, and this crate is their one transcription into the shapes the protocol
// names — nothing here reimplements a primitive, and every one of them is held to the published
// known-answer values of its own standard, in `tests/fixtures` beside this code.
//
// Every secret this crate holds wipes itself when dropped and prints nothing of itself.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod aead;
pub mod kem;
pub mod sign;
pub mod suite;

#[cfg(test)]
mod vectors;
