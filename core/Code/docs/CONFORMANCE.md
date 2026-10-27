# Montana Protocol v35.26.1 — Code Conformance Report

Date: 2026-06-12. Scope: full specification (4435 lines) against the workspace (23 crates).
Method: consensus-critical sections verified line-by-line first-hand; remaining sections swept
by a read-only survey and re-verified at every flagged point. Verification artifacts: unit and
binding-vector tests (`cargo test`), a 3-node local cohort (150+ windows: proposer rotation
46/62/44, confirmers=3, node-kill freeze, node-return resume), and the live 3-node genesis
network.

## Verified conformant (first-hand)

| Spec section | Implementation | Evidence |
|---|---|---|
| R1/R2 signing rules, domain separators | mt-codec, all object codecs | domain tests; cross-checked against production ids (node_id = SHA-256("mt-node"‖0x00‖pk), account_id = SHA-256("mt-account"‖0x00‖suite_le‖pk)) |
| `SshaReveal` 3381 B, BundledConfirmation 3385 B+, ProposalHeader 3722 B | mt-lottery, mt-consensus | byte offsets re-derived and matched (sig scope 0..413; target u128 LE at 396..412; fallback_depth at 412) |
| Lottery: weighted_ticket integer form, ln_q64, binding vectors N1–N5 | **removed** (issue #18, the author's decision 279): tickets, reveals, weights and the winner are gone | the proposer of a window is the lowest ticket by the aggregate (row below); see DEV-054 |
| Target calibration, vectors TA1–TA5 | **removed** (issue #18): `calibrate_target`, its vectors, the τ₂ ticket counter and the candidacy gate are gone | the header fields `target`, `included_reveals_root`, `winner_endpoint` and `winner_id` stay in the 3722-byte layout and carry zeros, and a follower refuses any other value (mt_consensus::validate_retired_fields, issue #18 S3) |
| Two-window pipeline: proposal_W includes the confirmations of W−1 and credits the living of W−1 | montana-node start.rs; mt-account apply_window_credit (issue #18) | BC_W carries no reveal hashes since issue #18 (the list stays, empty, in the wire layout) |
| Proposer of W = the lowest ticket by the aggregate of W−2 among the active nodes, ticket = SHA-256("mt-ticket"‖0x00‖aggregate(W−2)‖node_id); fallback cascade over the same order; NO_PROPOSER for W<2 | mt_consensus::proposer_at; start.rs canonical_proposer_at / held_aggregate / electorate_at (issue #18) | order_tests: one proposer in every delivery order; oracle vector `the_ticket_is_the_frozen_value` |
| One second, one coin: every living node of W−1 is credited `window_credit` = 86 400 / (τ₂ / 14) = 60 coins | mt-account window_credit_moneta, apply_window_credit (issue #18) | `the_issuance_of_a_window_is_its_seconds_for_every_living_machine`; conformance row monetary.window_credit_one_coin_per_second |
| Proposer signature verified against NodeTable (not bootstrap-pinned) | mt_consensus::validate_header wired in drain | live cross-node application |
| SSHA continuity: finalization concurrent with next-window chain computation | mid-tick drain (ssha_step_chunked on_chunk) | DEV-021b closed; confirmers=3 steady on cohort |
| Quorum on active_chain_length with 2τ₂ active predicate | active_chain_length_at | node-kill ⇒ honest freeze (+1 inertia), node-return ⇒ resume (+62 windows/75 s) |
| apply_proposal steps 1/2/3a/3b/3.5/3.6 incl. checkpoint rotation | mt-account, mt-entry | unit tests; settle_and_bookkeep single transition shared by proposer and followers |
| Canonical cemented_bundle_aggregate fed with real confirmer sets (was empty everywhere) | cba_from + bc_set_history | per-window histories persisted via archive replay |
| Genesis Decree params (d0=325M, τ₂=20160, emission=13e9 nɈ, quorum 67, admission 130, selection 336, pruning 4τ₂) | mt-genesis | constants matched against spec text |
| Envelope archiving on every node; explorer parity from any node | drain cemented arm + mt-store::load_proposal_envelope | live |

## Open, tracked in SPEC_DEVIATIONS.md

- DEV-024: cemented_bundle_aggregate hashes confirmer node_ids; spec text says ML-DSA-65 signatures (grinding-resistance gap). Author decision required: amend spec or regenerate primitive + KATs.
- DEV-026 (closed, issue #18 S4): a second envelope of an applied window is refused and nothing moves (core/docs Consensus:1382, a verified decision is never abandoned); a pair from one proposer is kept as equivocation evidence.
- DEV-027 (closed, superseded by DEV-054): genesis window 0 carries no settle ⇒ supply(W) = EMISSION × W. Since issue #18 a window issues the credit times the count of its living, and supply_moneta is removed.
- DEV-010/011/016: acknowledged operator choices (genesis bootstrap detection, hardware D calibration for the genesis node, manifest-seeded cohort).

## Operational notes (spec math, not defects)

- A 3-node equal-weight cohort has zero fault tolerance: 67% of three equals all three; any node going dark pauses the chain until it returns (verified live and on the local cohort). Tolerance appears at N=4 (3/4 = 75%).
- Network pace equals the slowest node inside the quorum boundary; with equal weights this is the slowest of the three.
