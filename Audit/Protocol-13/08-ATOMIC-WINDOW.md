# 8. Apply and persist a complete window atomically

**Status: open; native value-state and storage prerequisites were repaired.**

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
