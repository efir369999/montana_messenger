# 7. Make the earlier core's lottery deterministic

**Status: open; a historical-state decoding repair passed selected checks.**

This item concerns `Code`, not the native `Montana-Core` proof system. Inspect
`core/Code/crates/montana-node/src/timechain_state.rs`, the lottery runtime and
`core/Code/docs/SPEC_DEVIATIONS.md`.

The unpublished candidate refuses legacy V1 state that lacks its historical
target and reveal count, except for the exact canonical genesis state. It also
rejects nonzero reserved padding. Three selected decoder tests passed on the
separate Linux host; formatting and whole-workspace Clippy passed. The frozen
archive SHA-256 was
`03eb3de9117516322f671fe1dc5796c250d2803b157373f9825be085195bf4a1`.
The complete legacy workspace tests were not run. Existing deletion-based
fixtures require a retained-data test environment before that claim is possible.

This repair does not settle historical weight selection, epoch retarget order,
missing reveals, conflicting proposals or self-bootstrap. Earlier complete
reveal-set and settlement-root repairs must remain intact.

Closure requires adversarial and valid histories delivered in different orders:
all verifiers must select the same eligible winner and resulting roots using
the target and weights of the relevant historical window. Incomplete historical
context must trigger retrieval or refusal, never a permissive default.
