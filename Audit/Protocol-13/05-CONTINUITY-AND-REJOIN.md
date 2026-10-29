# 5. Prove continuity and return after partition

**Status: Partial** (the Author's decision 342 (a), record 345 of the constitution chain,
2026-10-29 10:03 UTC). Rules 1 and 2 of the continuity rule are applied in the node, and rules 3 and 4
are functions with tests. The check inside the admission proof is the remainder, and it goes to the
specification of the next generation. No complete partition-and-rejoin acceptance run exists.

The source baseline and normative sources are identified in the [index](README.md).
Read the Identity continuity rule together with the native admission circuit,
not just the bitmap reader. Earlier reserved-bit rejection prevents fabricated
future bits from aging into the valid region; it does not prove the applicable
period, shift or required participation share inside admission.

Replaying other machines' cements does not create an action by this identity.
Recovery cannot silently manufacture participation or replace the parent's
electorate with whichever participants happen to be reachable. Candidate
fixed-parent quorum arithmetic preserves that distinction, but complete
admission and recovery proofs are missing.

Closure requires verified cases for network-wide halt, a minority partition,
long absence, return and exact period boundaries. The proof must reject omitted
actions, invalid shifts, stale periods, reserved bits and insufficient shares.
The positive return case must recover by the stated protocol rule and remain
valid after restart. Correct arithmetic in a helper, or reconnection of a socket,
does not establish that an authenticated returning node was admitted.

## What stands and what remains (issue #16 K5, K7b)

- **Stands, rule 1:** an opening takes its segment from its own window and never from its caller,
  `Value::apply_opening` (`core/Montana-Core/crates/montana-node/src/state.rs:610-615`, PR #106).
- **Stands, rules 3 and 4, as functions:** the segments lived in the shifted period,
  `Record::segments_lived` (`crates/mt-state/src/layout.rs:1028`). The count of segments in force,
  `n_in_force` (`crates/mt-pulse/src/entry.rs:26`), is none while the active set is empty. The share
  required is `required_segments` (`entry.rs:43`). Each has its tests.
- **Stands, rejoin after the walk (K7b):** a machine that took its plane from the network stakes and
  proposes nothing until the standing stride of the horizon changes. Until then it follows the decided
  rolls, so a returning minority cannot replay a rate the others refuse (the Author's decision 332 (b),
  record 339; Consensus, "The join"; test
  `a_machine_on_a_plane_of_the_network_waits_for_the_next_stride`).
- **Remains:** `apply_candidacy` (`state.rs:691-739`) puts neither the segment, nor `n`, nor the
  share into the public input. The admission circuit reads no field of the record but its right
  (`crates/mt-proof/src/circuit/admission.rs:34`). The record is private, so the share can be checked
  only inside the proof. That needs a new admission form in Canon and a new description of the
  circuit for every machine, which decision 342 (a) assigns to the next generation. `n` with an empty
  active set is not defined (the ramp question of link 11280). AUDIT.md row "Admission continuity is
  not enforced end to end" stays open.
