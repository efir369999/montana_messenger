# 4. Bind admission witnesses to one authenticated state

**Status: closed.** Item 4 is closed by PR #62 (`agent-582/issue-15`, merged into the PR #60 branch as
`ce01975` at 2026-10-27 08:54 UTC) and with it into `main` as `e612a55` (author's decision 267; comment
6437725428). The chairman closed #15 at 2026-10-27 09:00 UTC (comment 6437744613): "Closed: merged
into main at e612a55; CI audit-tools pass on main (run 40477250041)."

At the public baseline `6303fa5fbbb5ad93e4d7dd3dcc699693fb10e002` the circuit
`core/Montana-Core/crates/mt-proof/src/circuit/admission.rs` consisted of three chains with no
common cell: the lane was empty, the public input was three digests the prover chose, and no node
checked a candidacy (Gate -1, comment 6390575634). The requirement: the identity record, the machine
key, the operator secret and the membership paths are taken from one admissible state, and an
admission assembled from foreign and own parts is rejected.

## What was decided

- **F-1 is fixed inside this issue** (the author's decision 246, "yes", 2026-10-26 21:21 UTC; comment
  6427650419): `node_commit` and `suite_id` join the public input of an admission, in the order of the
  K0c specification: window, `record_root`, `naming_half`, `node_commit`, `operator_nullifier`,
  `suite_id`. A relay can no longer carry a candidacy's proof onto another `node_commit`.
- **The tau2 collateral and slashing (decision 233) move out of #15** into #61; #15 closes on its own
  five criteria (comment 6427650419).

## What the merge holds

Paths under `core/Montana-Core/crates/` on `main`.

- `montana-node/tests/admission_one_state.rs` (`880b0b0`, `c8bf49d`): the claimant's own record walked
  by the path of another record of the held tree
  (`an_own_record_walked_by_the_path_of_another_record_of_the_tree_is_refused`, `:131`) and a path
  spliced of two states of the tree (`a_path_spliced_of_two_states_of_the_tree_is_refused`, `:163`)
  are each refused by `State::apply_candidacy`; the honest admission of the same record applies.
- `montana-node/tests/admission_audit.rs`: a foreign record with the claimant's secret and an
  unrelated path is refused (`audit_refuses_a_foreign_record_with_the_claimants_secret_and_an_unrelated_path`,
  `:34`); the reproduction of F-1 became a refusal
  (`audit_refuses_a_candidacy_lifted_onto_another_commitment`, `:120`).
- F-1 in the public input of the admission (`f0b071f`, `mt-proof/src/circuit/admission.rs`); R6 for
  it: the admission identifier `df6b61c2..`, `air_hash` `49533d47..`, `published_parameters`
  `e913fb4d..`, Genesis State Hash `3f053286..` (`ff9815d`, from `genesis-values` on Lauterbourg-3);
  the places of the 32-byte values in the register ADMISSION (`a053dfc`).
- The AUDIT ledger of tests of the workspace: 728 (`645cd8c`), then 729 (`347f8a7`).

## Runs

Self-verification by the council's sessions, not an independent external audit.

| Revision | Run | Command | Result |
|---|---|---|---|
| `645cd8c` | a582-p15 (Lauterbourg-2), comment 6427879145, 2026-10-26 21:17-21:29 UTC | `cargo fmt --all -- --check` | rc 0 |
| `645cd8c` | same | `cargo test -p montana-node --test admission_one_state` | 2 passed, 0 failed, 411.54 s |
| `645cd8c` | same | `cargo clippy -p montana-node --all-targets -- -D warnings` | rc 0 |
| `645cd8c` | same | `cargo test -p mt-conformance --test measurements` | 3 passed, ledger at 728; the run ended `END 0 failed: none` |
| `f0b071f` | a583-f1 (Lauterbourg-3): `fmt`, `genesis-values`, `mt-proof circuit::admission`, `admission_audit`, `admission_one_state`, `mt-conformance` and `mt-genesis`, `clippy` on `montana-node` and `mt-proof` | exact commands not recorded | result not quoted in the verdicts (comment 6427879145 says it had not been run yet); the genesis values it printed are the ones of `ff9815d` |
| branch of PR #62, `347f8a7` | ring a594-62 (Lauterbourg-2), comment 6437725428 | not recorded | `admission_one_state`, `admission_audit` and `measurements` (AUDIT 729) green |
| branch of PR #62 | `four_machines_decide_one_name` | not recorded | passed on Lauterbourg-3 (2039 s); cut by the ring's time cap on Lauterbourg-2 (1226 s, rc -15), "a cap, not a verdict" |
| `ce01975` | CI `audit-tools`, run 40476769805 | the workflow | pass |
| `main` after `e612a55` | CI `audit-tools`, run 40477250041 | the workflow | pass |

The merged core tree `4a0e3737` is the core of PR #62 (comment 6437725428). A red control (`public_of`
laying zeros for `node_commit` and `suite_id` must turn `admission_audit` and the end-to-end test red) was
listed as to come in the description of PR #62; its result is not recorded in the verdicts.

## Earlier merge of this item

An earlier branch of item 4 (PR #26, K0-K4 of Agent 491) was merged into `main` as `0089d333` on
2026-10-26 (comment 6406161907) with its finding F-1 open: the proof of a candidacy did not bind
`node_commit` (`admission_audit.rs:107-131` reproduced a lifted candidacy). The decision 246 above
closed it.

## Outside this closure

- The tau2 collateral and slashing (decision 233, the relation named at `Canon:5354-5363`, decision
  238) are #61 (comments 6426103702, 6427650419).
- Continuity belongs to item 5 (#16). The wire intake of candidacies is stage 19 (comment 6406161907).
- This is self-verification by the council's sessions, not an independent external audit.
