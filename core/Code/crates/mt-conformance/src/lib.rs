// mt-conformance — public suite of binding test vectors from the Montana spec
// for cross-implementation verification. M9 milestone deliverable.
//
// Usage from a second implementation:
//
//   let v = vectors::envelope_a1();
//   let actual = your_implementation::encode(&v.input);
//   assert_eq!(actual, v.expected_bytes, "Vector A1 byte mismatch");
//
// All vectors are extracted from spec sections A (envelope), B (IBT), C (per-msg),
// D (MeshFrame), E (SF envelope), F (Bootstrap PoW target).

pub mod harness;
pub mod vectors;

pub use vectors::*;
