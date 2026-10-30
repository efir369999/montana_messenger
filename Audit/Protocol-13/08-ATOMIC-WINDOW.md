# 8. Apply and persist a complete window atomically

**Status: closed.** Item 8 is closed on the chairman's verdict of #19 (issue #19, Protocol-13 item 8). Both
generations apply a window as one record, recover the previous or the complete next window after a death at any file
operation, issue nothing on a repeat, bind the record to its network, and only the core mints:
- K1-K2 (`core/Montana-Core`): one record `window` written by one `commit_window`; the close is one commit; a death at
  every file operation of the close leaves the old or the new record -- PR #27 carried by PR #48, `main` `88b9f486`
  (verdict comment 6412323345).
- K3-K4 (`core/Montana-Core`): a machine starts only on a plane its kept Proposal carries
  (`montana-node/src/lib.rs:774`, `:880-886`); a window applied again issues nothing; the minting door `State::witness`
  stands under `cfg(feature = "witness")` -- PR #70, `main` `3707747` (comment 6443999367).
- K5 (`core/Code`): the commit point `mt-store/src/window.rs` `commit_window`, its one caller
  `montana-node/src/window_record.rs`; settle, follow and fast sync dying at every file operation leave the old or the new
  window, each window issued once -- PR #87, `main` `e459a19`.
- Gate 0: the proof kept with the tables and the head is the Proposal with its `ticket_proof`; the start rule is a norm of
  `core/docs/Montana Consensus.md`, "The way back" -- PR #82, `main` `dd399280` (comment 6452413150).
- K6 (`core/Code`): the window record names its network by the Genesis State Hash; a record of another network and an
  unnamed store above window 0 are refused -- PR #113, `main` `4a3cc25`.
- Only the core mints (the Author's words 11580, 11639): `mt-coin` of `core/Code` takes no MINT from `TX_MINT_STOP`
  (30.10.2026 12:00 UTC), refusal 18 "minting stopped", test `v16_minting_stops_and_only_the_core_mints`, the rule in
  `Audit/App/COIN-TX-V3.md` (fold-9) -- PR #116, `main` `b6f159d`.
Rings: L3 `both-test` on the tree `core/Code` `861dbb53` of `main` `4a3cc25`: `cargo test --release --workspace --no-fail-fast` END 0, 125 suites, 1398 passed, 0 failed (2026-10-29 18:38-18:56 UTC); L2 `both-lint` on the same tree: `cargo fmt --all -- --check` 0, `cargo clippy --workspace --all-targets -- -D warnings` 0; CI audit-tools SUCCESS on PR #113. Outside this closure: the timing tests of `mt-mnemonic` (`sources.rs:649`), red in the debug rings
on Lauterbourg-3 on `main` as well (green in the release run above), the deployment of the new `mt-coin` to the running
coin-chain nodes, and the form of GENESIS 0 (the Author's question 365).

The text below is the report as it stood before the closure.

In the unpublished candidate, note append validates the entire batch before
mutation. `State::apply` reserves and validates fallible operations before
publishing notes and spent/rate nullifiers. The node persists a candidate value
state before exposing it in memory. Checked encoding rejects invalid counts
and overflow; decoding rejects duplicate and noncanonical stored sets.

The store uses exclusive private temporary files, durable publication and
exclusive identity creation. A directory-sync failure after rename is reported
as an uncertain commit, with the complete newly visible state retained; it is
not falsely described as rollback. Selected server tests cover malformed state,
failed persistence, symlink refusal and concurrent identity/signing choices.
Test data was retained.

These repairs do not form a complete window transaction. Proposal, proof,
transition tables and closed head still need one authenticated, crash-consistent
commit in both generations. The native live path has no canonical Proposal to
include in that transaction yet. Historical (marked 2026-10-27 UTC): on `main` the live path takes a verified Proposal before the close (`core/Montana-Core/crates/montana-node/src/pulse.rs:1804`), and the window closes in one writing (`pulse.rs:1814`); item 2, #10, comment 6420198473.

Gate 0 of the plan in #19, asked of the Author, is decided (27.10.2026 19:48 UTC): the proof
written in one record with the tables and the head is the bytes of the Proposal with its
`ticket_proof`, not the window certificate, which needs the attestations of the next window and
cannot enter the same record (`core/docs/Montana Canon.md`, "The certificate of a window"). The
start rule of K3, that a machine starts only if the plane roots of its record equal the roots of its
kept Proposal, is a norm in `core/docs/Montana Consensus.md`, "The way back". The decision closes
no criterion below.

Closure requires deliberate failure at each persistence boundary followed by
restart: recover exactly the previous or complete next window, never mixed
tables/head/archive. Reapplying the same window must not issue twice. Historical
state migration must itself be authenticated and may not import balances simply
because their bytes decode under a new network identifier.
