# 1. Complete window statement

**Status: closed.** Item 1 closes on the condition section 10 of
[`WINDOW-THEOREM.md`](source/Montana-Core/WINDOW-THEOREM.md) states: the obligations O-1 to O-5
discharged, the Lean file green on the build host, and the ring of the core green on the commit that
carries them. O-6, the bound from above of the ballot, is discharged as well (section 10, O-6).
The relation of a window and its verifier are implemented in the branch this folder is published
from, and the closure of a window is stated as theorems with proofs in that note, checked in part by
machine (`formal/Window.lean`, section 9). Agreement on what a window decided, the
construction the author chose (section 6 of [`AGREEMENT.md`](source/Montana-Core/AGREEMENT.md)), is
implemented and held by the test of four machines. Model checking of the code with Kani is item 2 (Historical (marked 2026-10-27 UTC): item 2 is closed on its own evidence, `02-CANONICAL-PROPOSAL.md` and `PROTOCOL-13.json` row 2; the Kani harnesses are PR #29, still a draft);
the run on several hosts is item 13. No production readiness is claimed.

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
`9380a76` up to the one published here change documents only, except the test file of O-6,
`crates/mt-proof/tests/ballot_and_ticket.rs`, which the row of `033c6b7` runs.

| Revision | Machine | Command, in `Montana-Core` | Result |
|---|---|---|---|
| `4451b21` (the core tree of PR #39 before O-6; the `Montana-Core` tree published here differs from it in `crates/mt-proof/tests/ballot_and_ticket.rs`, `AUDIT.md` and `WINDOW-THEOREM.md` only) | Linux x86-64, rustc 1.92.0, the build host | the ring of the core: `fmt`, `clippy`, `build-tests`, then every test binary of the workspace | fmt 0; Clippy 0; build-tests 0; 92 test binaries, all exit 0 (tests-all): 702 passed, 0 failed, 5 ignored (`agreement::every_book::every_book_of_the_bound_decides_at_most_one_name` of `montana-node`, the whole bound of Theorem 1, run with `--ignored`; four timing measurements of `crates/mt-wire/tests/timing_cell.rs`, of the optimized build only); doctest 0; doc 0; release build 0; 25.10.2026 20:41-22:44 UTC |
| `033c6b7` (O-6, merged here as `0ac84ae`) | Linux x86-64, rustc 1.92.0, the build host | `cargo fmt --all -- --check`; `cargo clippy -p mt-proof --all-targets -- -D warnings`; `cargo test -p mt-proof --release`; `cargo test -p mt-conformance --release` | format 0; Clippy 0; `mt-proof`: 11 test groups, 189 passed (145 unit, 6 in `ballot_and_ticket`), 0 failed, 0 ignored; `mt-conformance`: 5 test groups, 71 passed, 0 failed, 0 ignored; exit 0 each, 25.10.2026 22:13-22:28 UTC |
| `4451b21` | Linux x86-64, Lean 4.35.0 | `lean formal/Window.lean` (blob `a9fd7faa`, 1586 lines) | exit 0, no error, no warning, no `sorry` (`WINDOW-THEOREM.md`, section 9) |
| `9380a76` | macOS on arm64 | `taskpolicy -b cargo test --release --jobs 2 --no-fail-fast -p montana-node -p mt-net -p mt-boundary -p mt-conformance -- --test-threads 2` | 44 test groups: 135 passed, 0 failed, 0 ignored; exit 0 after 6872.9 s. Every test file named above ran and passed. |
| `bd1468a` with the test correction committed as `9380a76` | Linux x86-64, rustc 1.92.0, OpenSSL 3.5.4 | `cargo +1.92.0 fmt --all -- --check`; `cargo +1.92.0 clippy --release --workspace --all-targets -- -D warnings`; `cargo +1.92.0 test --release --no-fail-fast -p montana-wallet -p mt-codec -p mt-derive -p mt-genesis -p mt-merkle -p mt-proof -p mt-pulse -p mt-seed -p mt-state -p mt-store -p mt-suite -p mt-wire`; `cargo +1.92.0 build --release --workspace` | format 0; Clippy 0; 54 test groups: 507 passed, 0 failed; release build 0 |

The four crates of the row of `9380a76` hold the tests that open network listeners; the row of
`bd1468a` holds the rest of the workspace.

## What is open, outside the closure of item 1

1. **The memory of a stalled window.** Inside an open window nothing of a round is let go, and
   without a quorum the rounds keep turning; the rule that bounds what a stalled window holds is part
   of the agreement stage and is not written (`AGREEMENT.md`, section 6, *Found against the pulse*).
2. **The run on six hosts.** The run of 2026-10-16 (six machines, a quorum of five) closed window 0
   on two names, before the agreement stage was in the tree; the acceptance of that stage repeats it
   on six machines (`AGREEMENT.md`, section 6, *Acceptance*). That run, with distributed finality,
   loss and recovery of quorum, partition and rejoin, is item 13.

Items 2, 3, 9 and 13 depend on this closure. Their finality, issuance and authenticated-joining
claims remain open while this item is. Historical (marked 2026-10-27 UTC): items 1, 2 and 3 are closed (`PROTOCOL-13.json`, rows 1-3, closed 2026-10-25, 2026-10-26 and 2026-10-27); items 9 and 13 are open on their own evidence (rows 9 and 13).

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
