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
| Lottery: weighted_ticket integer form, ln_q64, binding vectors N1–N5 | mt-lottery | vectors pass; live rotation of winners on cohort |
| Target calibration, vectors TA1–TA5 | mt-lottery::calibrate_target (commit baca884) | 5/5 byte-exact; wired at τ₂ in settle; candidacy gate + header.target cross-check |
| Two-window pipeline: BC_W carries W−1 reveal hashes; winner_{W−1} cemented at proposal_W; one-window reward lag | montana-node start.rs (commits 6ea9d12, 3e0e523) | live: window 1 cemented with evidence=3, bundles(W−1)=0 at genesis per design |
| Weighted reveal cementing (Σ chain_length ≥ 67% per hash, not set-union) | start.rs weighted_cemented_hashes | local cohort + live |
| Lookback proposer = winner_{W−2}; fallback cascade by weighted ticket of W−2; bootstrap for W<2 | start.rs expected_proposer + mt_consensus::fallback_proposer | local cohort: all three nodes cement (46/62/44) |
| Proposer signature verified against NodeTable (not bootstrap-pinned) | mt_consensus::validate_header wired in drain | live cross-node application |
| SSHA continuity: finalization concurrent with next-window chain computation | mid-tick drain (ssha_step_chunked on_chunk) | DEV-021b closed; confirmers=3 steady on cohort |
| Quorum on active_chain_length with 2τ₂ active predicate | active_chain_length_at | node-kill ⇒ honest freeze (+1 inertia), node-return ⇒ resume (+62 windows/75 s) |
| apply_proposal steps 1/2/3a/3b/3.5/3.6 incl. checkpoint rotation | mt-account, mt-entry | unit tests; settle_and_bookkeep single transition shared by proposer and followers |
| Canonical cemented_bundle_aggregate fed with real confirmer sets (was empty everywhere) | cba_from + bc_set_history | per-window histories persisted via archive replay |
| Genesis Decree params (d0=325M, τ₂=20160, emission=13e9 nɈ, quorum 67, admission 130, selection 336, pruning 4τ₂) | mt-genesis | constants matched against spec text |
| Envelope archiving on every node; explorer parity from any node | drain cemented arm + mt-store::load_proposal_envelope | live |

## Open, tracked in SPEC_DEVIATIONS.md

- DEV-024: cemented_bundle_aggregate hashes confirmer node_ids; spec text says ML-DSA-65 signatures (grinding-resistance gap). Author decision required: amend spec or regenerate primitive + KATs.
- DEV-026: proposer equivocation handled first-valid-wins (quorum-protected); spec asks reject-both.
- DEV-027 (closed): genesis window 0 carries no settle ⇒ supply(W) = EMISSION × W. Spec v35.26.2 closed-form aligned to × W (supply_moneta(0)=0); code helper/tests/status updated. No residual deviation.
- DEV-010/011/016: acknowledged operator choices (genesis bootstrap detection, hardware D calibration for the genesis node, manifest-seeded cohort).

## Operational notes (spec math, not defects)

- A 3-node equal-weight cohort has zero fault tolerance: 67% of three equals all three; any node going dark pauses the chain until it returns (verified live and on the local cohort). Tolerance appears at N=4 (3/4 = 75%).
- Network pace equals the slowest node inside the quorum boundary; with equal weights this is the slowest of the three.
