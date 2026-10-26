# Item 4 after decision 207: K0 source map and stopping condition

Base: `3314074397b3efa333ae317bfb21ae570eee3094`, 2026-10-26 UTC.
This is a source review, not a changed specification or an implemented gate.
Paths below are relative to the repository and line numbers refer to that base.

**K0 stops at step 2 of the assignment.** There is no committed per-person
balance in the record or in the admission witness/public input. There are
committed note amounts in the value plane; those must not be described as absent.
The missing part is a specified proof relating enough unspent owned value to the
same claimant and admissible state, without disclosing it. A local wallet sum
cannot stand in for that network proof. No new balance field is invented here.

## Reading and findings

The complete issue #15, including the Gate -1 report and the decision-207
assignment, and `Audit/Protocol-13/04-ADMISSION-ORIGIN.md:1-23` were read.
The audit describes its explicit old baseline `6303fa5`; its absent-common-origin
finding must not be silently applied to this base after merged PR #26.

| Source at the base | Finding |
|---|---|
| `core/docs/Montana Canon.md:4830-4862`; `core/Montana-Core/crates/mt-state/src/layout.rs:989-1005` | The record commits to `segment_bitmap`, `last_active_segment`, `opened_window`, `own_height`, `operator_nf`, `fabric_root`, suite, key and blind. There is no balance. The opened window is invariant across successors. |
| `core/docs/Montana Identity.md:65-80,88-111` | The record explicitly holds no balance. Continuity counts lived segments after shifting against the current segment and compares the required share. This is not itself a definition of two seconds of online time. |
| `core/Montana-Core/crates/mt-state/src/layout.rs:1009-1023` | `segments_lived` rejects malformed/future segment state, shifts and counts bits. This helper is not an admission constraint proving level 1. |
| `core/docs/Montana Canon.md:5191-5218`; `core/docs/Montana Consensus.md:893-943`; `core/docs/Montana Registry.md:67` | CNS-15 owns the one-time right. The candidacy takes the record root from the standing stride's last proposal. Its statement binds the record right and naming half, but explicitly asserts nothing of `node_commit`. |
| `core/Montana-Core/crates/mt-proof/src/circuit/admission.rs:218-268,310-326` | The witness walks one record; the public input is exactly `window` (8 little-endian bytes), `record_root` (32), `naming_half` (32), `operator_nullifier` (32): 104 bytes. No note root, amount, nullifier-set root, node commitment or suite is a public input. |
| `core/Montana-Core/crates/montana-node/src/state.rs:20-36,288-305,444-482` | State keeps note commitments and spent nullifiers separately from records. A proposal has both note and record roots and a nullifier root. `apply_candidacy` reads only the supplied record root into its proof input and spends the right after successful verification. |
| `core/Montana-Core/crates/mt-derive/src/note.rs:48-61,67-73` | A note commitment includes a hidden `u128` amount, payment key, nullifier naming half and blind. A nullifier depends on the note commitment, spending half and position. A note membership proof alone would not establish that the note remains unspent. |
| `core/Montana-Core/crates/montana-wallet/src/lib.rs:381-383` | `balance()` sums values from the wallet's local held-note ledger. It is not a balance commitment under the record root and is not an admission proof. |
| `core/docs/Montana Value.md:173` | Applying a frame inserts commitments and nullifiers; no account balance exists. |
| `core/Montana-Core/crates/montana-node/tests/a_record_raises_one_machine.rs:1-146` | Existing source exercises another root/window, repeated right, a second machine under one right, restart and the standing-stride root rule. These tests do not establish Global level 1. |
| `core/Montana-Core/crates/montana-node/tests/admission_audit.rs:31-104,110-133` | The mixed-witness case is refused; the second test still expects a lifted `node_commit` to apply. This is F-1, not a successful binding. Tests were read, not run in this K0. |
| `apps/messenger/ios/Code/Montana/MontanaSettings.swift:277-281`; `apps/messenger/ios/FABRIC-OF-TIME.md:362` | The client describes Global as the minimum of chain, pi and Fabric levels (2 seconds and 3 coins for level 1). A per-correspondence key cannot be tied to the balance by the Fabric verifier. Decision 207 keeps Fabric a client gate. |

## What needs a specification before K0 can continue

1. Define the network witness for the pi threshold using the existing note/value
   plane (or an explicitly authorized different construction), its relation to
   the claimant, the root/stride and unspentness rule. Neither a record-only
   range check nor a note-membership check supplies all of these facts.
2. Keep the network's lived-continuity gate (`Canon:5217`) distinct from the
   client's two seconds of attended time, which are not in state. The chairman's
   review confirms this distinction; no new time field is inferred or invented.
3. Then specify the complete new public input, including `node_commit` and
   `suite_id`, the client-only Fabric gate, and the new admission identifier,
   `air_hash` and Genesis State Hash. Appending 32+2 bytes to the current input
   would be 138 bytes but would still carry no value-plane root: that arithmetic
   alone is not a complete K0 statement and is not adopted as the new format.

Canon, Consensus and Registry are unchanged. No circuit, verifier, transition,
client, release row or old core is changed. F-1 remains open. No K1-K4 work may
start until the chairman accepts a completed K0. The requested stop is reported
with source evidence rather than replaced by an invented state quantity.

The chairman accepted this stop on 2026-10-26 in
[PR #52](https://github.com/efir369999/montana_messenger/pull/52#issuecomment-6414349902).
The value-plane choice is the author's question 212: a candidacy carrying a
self-transfer of at least 3 coins, or pi remaining a client gate. Neither option
is adopted here. K1-K4 wait; the chairman will issue the K0 specification task
after that answer. The public input must bind `node_commit` and `suite_id` either
way, as the review states.

Validation: pinned source reading, separate Critic self-review of the note-plane
counterexample to "there is no committed value", and `git diff --check` (0).
Cargo fmt, clippy and all tests: not run (source-review document only).
This is a check by the implementing session, not an independent external audit.

-- GPT agent [01a17795], gpt-6, contributor of the Montana council
