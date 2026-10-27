# 2. Close only a verified canonical Proposal

**Status: open.** No canonical live-window closure has been demonstrated. Historical (marked 2026-10-27 UTC): item 2 was closed by PR #58, merged as `084273c1` (#10, comment 6420198473); the closure report it read is `3c418a4:Audit/Protocol-13/02-CANONICAL-PROPOSAL.md`.

The public baseline is `6303fa5fbbb5ad93e4d7dd3dcc699693fb10e002`. Historical (marked 2026-10-27 UTC): the text below describes that baseline; on `main` `live_doing` takes `take_the_proposal` (`core/Montana-Core/crates/montana-node/src/pulse.rs:1804`) before `machine.close` (`:1824`).
In `core/Montana-Core/crates/montana-node/src/pulse.rs`, `live_doing` treats
`attempts_the_close` as the close and carries a beacon identifier into the next
window. Its own comment identifies the missing Proposal construction.

The unpublished candidate recomputes beacon cement from verified heavy answers
before signing or advancing. It also persists a predecessor choice before
creating the window signing identity. The same choice survives restart and
conflicting concurrent attempts. Targeted server checks passed. Neither repair
supplies authenticated predecessor state or the missing Proposal verifier.

A later complete-workspace attempt did not finish the three-machine scenario.
A bounded diagnostic showed advancing rounds with only one or two of three
heavy participants. Historical reads chased the growing tip and failed to
revisit early points. Three historical-read regressions and two delivery regressions now pass.
The later three-machine count scenario completed in 19.49 seconds and produced three different
beacon identifiers. This confirms progress in delivery, not canonical finality. The subsequent
whole-workspace attempt failed two stale proof-size expectations; those were repaired and
checked separately. No passing full workspace sweep is claimed.

Closure requires a positive canonical Proposal case and rejection of absent,
invalid or substituted proofs before any closed-head or issuance change. The
verified Proposal, proof and actual identifier must be persisted and served.
A participant count can authorize only an attempt. This depends on item 1.
