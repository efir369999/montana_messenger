# 3. Bind redemption to authorized issuance

**Status: open. A full-path excess-issuance counterexample was reproduced.**

The public baseline is `6303fa5fbbb5ad93e4d7dd3dcc699693fb10e002`.
Inspect `core/Montana-Core/crates/mt-proof/src/circuit/redemption.rs`,
`circuit/frame.rs`, and `crates/montana-node/src/state.rs`.
Membership in the admitted tree does not authenticate a claimant-supplied
`HeldRight.value` as an amount actually issued by a finalized window.

The candidate's `montana-node/tests/issuance_audit.rs` creates a complete proof
for a right larger than the entire window mint, applies it through `State::apply`,
then proves and applies an onward payment. The separate Linux-host run accepted
both. Its passing test result reproduces the defect; it does not establish a
supply bound. The run's frozen archive SHA-256 is
`1d5fd71e2c8f81192b25517228830a71ecc3dcc59d8993d9d5ada190c71992ef`.

Candidate branch-selector and zero-filler repairs prevent other reproduced
value-creation paths. They do not authenticate this entitlement. Likewise,
tracking spent nullifiers prevents some replays but cannot authorize a first
redemption of an invented amount.

Closure must bind finalized window, eligible recipient, exact amount and
one-time redemption inside the verified relation. An actual node must reject
an oversized amount, invented right, substituted recipient and replay, while
accepting the legitimate right. Website sums remain observations of recorded
amounts, not evidence of this monetary invariant.
