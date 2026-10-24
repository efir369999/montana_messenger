# 5. Prove continuity and return after partition

**Status: open. No complete partition-and-rejoin acceptance run exists.**

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
