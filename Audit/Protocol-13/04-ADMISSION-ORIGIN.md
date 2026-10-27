# 4. Bind admission witnesses to one authenticated state

**Status: open.** Historical (marked 2026-10-27 UTC): item 4 was closed by PR #62, merged with PR #60 as `e612a55` (#15, comment 6437744613).

At public baseline `6303fa5fbbb5ad93e4d7dd3dcc699693fb10e002`, inspect
`core/Montana-Core/crates/mt-proof/src/circuit/admission.rs`.
The circuit contains a record membership walk, an admitted naming walk and an
operator-secret nullifier absorption. `lane_loads` and `lane_wires` return empty
lists. The published digests do not establish the required common origin of
these independently supplied witnesses. Historical (marked 2026-10-27 UTC): this paragraph describes that baseline; on `main` `admission.rs` has no `lane_loads` or `lane_wires`, and the public input carries `node_commit` (`core/Montana-Core/crates/mt-proof/src/circuit/admission.rs:328-336`).

Earlier repairs to canonical padding, record-tree bit order and presence
membership are retained in the candidate. An honest admission proof or a
padding regression passing does not close the common-origin requirement.
No claim is made that the required mixed-witness adversarial proof is rejected.

Closure requires constraints binding the identity record, machine derivation,
operator secret, membership paths and public outputs to one admissible state.
The actual verifying algorithm must reject a foreign record combined with the
claimant's secret and an unrelated membership path. The corresponding honest
admission must still verify. Any changed statement needs new identifiers and
an explicit network transition; accepting the old weak statement as a fallback
would leave this requirement open.
