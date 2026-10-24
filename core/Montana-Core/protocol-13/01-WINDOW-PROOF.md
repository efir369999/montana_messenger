# 1. Complete window statement

**Status: open.** The relation of a window and its verifier are implemented and tested in the small
in the branch this folder is published from. Agreement on what a window decided is specified by the
author's choice and not implemented, and a run on six hosts closed one window on two names. No
closure or production readiness is claimed.

## Requirement

Accept a valid window; reject insufficient quorum, forged weight, incorrect state roots and
another machine's proposer ticket. The proof and its verifying algorithm must bind these
properties to authenticated predecessor state and history under the protocol construction.
Checking witness-generation code alone is insufficient: a prover can replace that code.

## The relation that stands

[`WINDOW-RELATION.md`](source/Montana-Core/WINDOW-RELATION.md) states it. A window closes on the
count of distinct admitted machines against the quorum of the electorate of window `W - 2` and,
where the standing is wide enough to be sampled, on the votes of verified ballots, which prove a
count of votes and disclose no weight (the author's ruling of 2026-10-16 on [I-12], section 2 of
that note). The proposal carries the six roots of state and the proven ticket of its runner; the
certificate of a window is its heavy attestations; history is the walk of certificates from an
anchor. Its acceptance matrix is section 4 of that note.

## What the branch implements, and what holds it

The commits named in row 1 of the table: the window closes through one verifying door, the roots
of state are defined and a device walks from an anchor to the head (`2add1f6`); the ballot proves a
count of votes and hides the standing it was drawn from, a payer's frame applies with its round,
the threshold of the draw is the width and the ticket orders the runners, a right needs the
machine's own part in the cement (`cdcbd7a`, `6ae1a3b`, `9f22057`, `2538b6a`).

The rows of the matrix run through the node's own verifier (`montana-node/src/certificate.rs`) and
through the running node's own close. The tests that hold them, in
`Montana-Core/crates/montana-node/tests/`: `certificate_matrix.rs`, `a_window_closes.rs`,
`window_cement_audit.rs`, `the_roots_of_state.rs`, `a_walk_from_an_anchor.rs`,
`a_device_joins_the_running_chain.rs`, `presence_disclosure_audit.rs` (the observer of the hiding
row, which now fails to extract), `a_ballot_casts_the_standing_a_machine_lived.rs` and
`a_payers_own_frame_applies_with_its_round.rs`.
[`ITEM-1-INTERNAL-AUDIT.md`](source/Montana-Core/ITEM-1-INTERNAL-AUDIT.md) maps each finding of the
review to the test that holds it.

## Runs

Self-verification by the implementing sessions, not an independent external audit. Commits after
`9380a76` up to the one published here change documents only.

| Revision | Machine | Command, in `Montana-Core` | Result |
|---|---|---|---|
| `9380a76` | macOS on arm64 | `taskpolicy -b cargo test --release --jobs 2 --no-fail-fast -p montana-node -p mt-net -p mt-boundary -p mt-conformance -- --test-threads 2` | 44 test groups: 135 passed, 0 failed, 0 ignored; exit 0 after 6872.9 s. Every test file named above ran and passed. |
| `bd1468a` with the test correction committed as `9380a76` | Linux x86-64, rustc 1.92.0, OpenSSL 3.5.4 | `cargo +1.92.0 fmt --all -- --check`; `cargo +1.92.0 clippy --release --workspace --all-targets -- -D warnings`; `cargo +1.92.0 test --release --no-fail-fast -p montana-wallet -p mt-codec -p mt-derive -p mt-genesis -p mt-merkle -p mt-proof -p mt-pulse -p mt-seed -p mt-state -p mt-store -p mt-suite -p mt-wire`; `cargo +1.92.0 build --release --workspace` | format 0; Clippy 0; 54 test groups: 507 passed, 0 failed; release build 0 |

The four crates of the first row hold the tests that open network listeners; the second row holds
the rest of the workspace.

## What is open

1. **Agreement on what a window decided.** Section 6 of
   [`AGREEMENT.md`](source/Montana-Core/AGREEMENT.md) records the construction the author chose on
   2026-10-16: the roll of a proposal is one body whose root stands inside the proposal's name, at
   the window's points for `retained_windows` windows; a machine keeps one agreement record for each
   open window and lets it go at the close. Neither the specification text nor its code is in the
   tree. Acceptance: four machines at a quorum of three under a held part, a late frame and a
   partition that heals, then the run on six hosts repeated.
2. **The run on six hosts, 2026-10-16.** A cohort of six machines on six hosts, a quorum of five, the
   node built from this branch. Read from the machines' own logs:
   - window 0 closed on two names: two machines on proposal `702a4d1d...` over a cement naming five
     machines (after 33 and 65 rounds), two on proposal `9ffa8f44...` over a cement naming six (after
     513 and 4097 rounds); each machine minted to itself under its own name;
   - the two remaining machines stood in round 0 holding cements of six and of five parts that no
     beacon at the quorum carried (`montana-node/src/pulse.rs`, `matches_cement`: the pair must be
     equal);
   - window 1 reached a cement of one or two of six at every machine and no quorum;
   - while window 1 stood, the rounds turned without bound, and the machine at 4097 rounds of
     window 0 was killed by its kernel (exit 137); `AGREEMENT.md`, section 6, records its memory at
     1.25 GB after four minutes. The rule that bounds the memory of a stalled window is part of the
     agreement stage and is not written.
3. **The hosts.** Distributed finality, loss and recovery of quorum, partition and rejoin are item
   13.

Items 2, 3, 9 and 13 depend on this closure. Their finality, issuance and authenticated-joining
claims remain open while this item is.

## Earlier records of this item

The internal review of session 38 continues in
[`ITEM-1-INTERNAL-AUDIT.md`](source/Montana-Core/ITEM-1-INTERNAL-AUDIT.md), under the verdicts of
sessions 41 and 42: each finding W01 to W15 stands there with its state and the test that holds it.
The relation that review audited, a quorum over a sum of hidden weights carried by the fold and the
arithmetic step of a window proof, left the specification and the tree in session 39
([`WINDOW-RELATION.md`](source/Montana-Core/WINDOW-RELATION.md), section 1). The receipts, the
reproducers and the first publication of that review stood in this folder until commit `0434dc6` of
this repository and remain in its history; they reproduce defects of code that is no longer in the
source.
