# 3. Bind redemption to authorized issuance

**Status: closed.** Item 3 is closed by PR #60, merged into `main` as `e612a55` (author's decision 267,
2026-10-27 08:40 UTC; merge comment 6437724909). The chairman closed #14 at 2026-10-27 09:00 UTC
(comment 6437743716): "Closed: merged into main at e612a55; CI audit-tools pass on main (run
40477250041)." The branch of PR #60 is `agent-575/issue-14-main` at `ce01975`, which carries PR #62
(item 4).

Before this closure the public baseline `6303fa5fbbb5ad93e4d7dd3dcc699693fb10e002` reproduced a
full-path excess issuance: membership in the admitted tree did not authenticate a claimant-supplied
`HeldRight.value` as an amount issued by a finalized window (`montana-node/tests/issuance_audit.rs`
redeemed `worth + 1`, and the verifier accepted it and its onward spend).

## What was decided

- **One rate** (the author, Gate 0, comment 6396750772): every machine earns 1 coin for every second
  of presence it lived; the redeemable right is a right to its own seconds, bound to the recipient,
  the amount and one use.
- **Construction** (chairman's ruling for step K3, comment 6406280814): a tree of credited rights in
  the proof-hash family; the proposal of W+1 appends one leaf for every part of the cement of W; a
  redemption proves its part under `credited_root`.
- **The worth of a right** (chairman's comment 6422452584, with the author's word of 17:08 UTC on
  2026-10-26): a window is 60 seconds, so the right of a window is worth 60 coins, `window_credit`
  derived as 86 400 / `segment_windows`; the proof did not bind the amount at all
  (`crates/mt-proof/src/circuit/redemption.rs:705-716` at that time). Boxes A1 (`window_credit` = 60,
  derived) and A2 (an AIR rule at the consumed tie of a right: amount = `window_credit`) were added.

## What the merge holds

Paths under `core/Montana-Core/crates/` on `main`.

- **A1** `window_credit` derived from the Decree (`c1095eb`, `55ce085`).
- **A2** the frame binds a right's worth to `window_credit`: `bind_the_worth_of_a_right`
  (`mt-proof/src/circuit/frame.rs:829`); commits `a3d2207` to `bc4475d`. The test
  `a_right_worth_anything_but_the_credit_satisfies_no_description`
  (`mt-proof/tests/frame.rs:244`).
- **T4** `montana-node/tests/issuance_audit.rs` (`f7458e2`) refuses, in `State::apply` and before
  the tree of notes or a balance moves:
  - an oversized right, and the right stays redeemable at its credit
    (`an_oversized_right_is_refused_and_the_right_stays_redeemable_at_its_credit`, `:93`);
  - a right no window credited (`a_right_no_window_credited_is_refused`, `:168`);
  - a right redeemed to another recipient than its proof names
    (`a_right_redeemed_to_another_recipient_than_its_proof_names_is_refused`, `:182`);
  - a second redemption, also after a restart of `State` (`a_right_redeemed_twice_is_refused_and_so_after_a_restart`, `:207`).
  The machine that lived the window still redeems its own right (commit message of `f7458e2`).
- **R6** the identifiers that changed with A2 (comment 6424642591, commits `dc841a7` and `5d76ec9`):
  the frame identifier `01f51109..` (it was `4621cdac..`), `air_hash` `386737ff..` (it was
  `4933ad20..`), `published_parameters` `ae6e346f..`, `genesis_state_hash` `bd3dcf02..`, taken from
  `cargo run -p mt-state --bin genesis-values` (units a573-gv1, a573-gv2) and recomputed by the chairman
  with SHA-256 by the formula of the Canon, "The Genesis State Hash". PR #62 changed
  `air_hash`, `published_parameters` and `genesis_state_hash` again for item 4; the values in force
  are those of `Montana Canon.md` and `mt-genesis/src/lib.rs` on `main`.

## Runs

Self-verification by the council's sessions, not an independent external audit.

| Revision | Run | Command | Result |
|---|---|---|---|
| `5d76ec9` | a573-a2 (Lauterbourg-3), chairman's comment 6424642591 | `cargo fmt --check`; the harness | fmt 0; harness 60/60 |
| `5d76ec9` | a573-gv1, a573-gv2 | `cargo run -p mt-state --bin genesis-values` | the values above; exact arguments not recorded |
| branch of PR #60, `d5465b4` | ring a594-60 (Lauterbourg-3), comment 6437724909 | not recorded | measurements green after the AUDIT row 727 (`d5465b4`) |
| branch of PR #62, `347f8a7` | ring a594-62 (Lauterbourg-2), comment 6437724909 | not recorded | green after the AUDIT row 729 (`347f8a7`); the attempt patch (a machine behind is drawn into the later attempt before it pledges) is identical on both branches |
| `ce01975` | CI `audit-tools`, run 40476769805 | the workflow | pass |
| `main` after `e612a55` | CI `audit-tools`, run 40477250041 | the workflow | pass |

The merged core tree `4a0e3737` equals the core of PR #62 to the byte; the `core` row of `RELEASES.md`
names it at `52a07d2`. The commands of the two rings and their exit codes are not quoted in the
verdicts; the closing comments name them as green.

## Outside this closure

- The sanction itself (CNS-10, stage 19) is not built: the ruling for step K3 (comment 6406280814)
  says that until then the code credits the whole cement of W. Not recorded whether it changed
  since.
- Admission and candidacy were not touched by this item (the author's questions 196 and 198); item 4
  carries them (04-ADMISSION-ORIGIN.md).
- The process restart of a refused close is held by `a_refused_close_credits_nothing.rs` (F-562-1);
  the restart in T4 is a `State` encode and decode round trip (PR #60 description).
- Kani (PR #29) is a separate formal check.
- This is self-verification by the council's sessions, not an independent external audit.
