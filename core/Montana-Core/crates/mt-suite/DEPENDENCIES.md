# Why these implementations, and what was required of them

Three of the four primitives of the suite are standards, and this tree does not reimplement a
standard. What follows is what each implementation was required to have before it was admitted,
and what is accepted about it — so that a reader asking "why this one" reads an answer rather
than a version number.

## What was required of any candidate

1. **A deterministic entry point taking a seed.** A person's keys are generated from branches of
   their own seed, so an implementation exposing only generation from the operating system's
   randomness cannot serve, however good it is. This requirement has cost the project before:
   a library was admitted without it and the gap surfaced only when recovery was implemented.
2. **The exact sizes of the set** — 4 032 / 1 952 / 3 309 and 2 400 / 1 184 — answered as the
   standard states them.
3. **A basis for its correctness that is not our own testing**: formal verification, an
   independent audit, a FIPS validation, or years of deployment at scale.
4. **A licence permitting distribution**, and a dependency tree small enough to read.

## ML-DSA-65 and ML-KEM-768 — `libcrux-ml-dsa`, `libcrux-ml-kem`

Accepted on requirement 3 as **formally verified**: both are extracted from F\* proofs by the
hax toolchain, which is the strongest of the four bases the requirement admits — a machine-
checked argument rather than an absence of found defects. Both expose generation from a seed
(requirement 1) and answer the sizes of the set (requirement 2).

**What is accepted, and stated rather than implied.** The published versions are below 1.0. A
version number below one usually says an interface may move, and here it says exactly that and
nothing about the proofs: what is verified is verified at that version. The pin is exact, the
lock file travels with the tree, and the risk carried is the cost of an interface change at an
upgrade — not a risk to what the code computes today, which the published vectors and a second
implementation both hold to account.

**Migration.** A suite enters through a row of the suite table and a protocol version upgrade;
the table is transcribed in `src/suite.rs` and read by the gate. Replacing an implementation
without changing the suite is a change behind `src/sign.rs` and `src/kem.rs` alone, and the
published vectors are what would catch a replacement that computes anything else.

## ChaCha20-Poly1305 — `chacha20poly1305`

Accepted on requirement 3 as an audited implementation of the RustCrypto family, the same
family this tree already stands on for SHA-2 and SHA-3. It carries the RFC 8439 vectors and a
second implementation agrees with it.

## SHA-2 and SHA-3 — `sha2`, `sha3`

The hash primitive of the whole protocol and the expansion the standing commitment's matrix is
drawn from. Both are of the RustCrypto family, both carry the vectors of their own standards,
and both are held to those vectors by the tests of the crates that use them.

## What is not taken

Implementations of the post-quantum standards that expose no generation from a seed, whatever
else they offer: the property a person's recovery rests on is not one this project trades.
