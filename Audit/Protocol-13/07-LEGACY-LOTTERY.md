# 7. Remove the earlier core's lottery; keep what stays deterministic

**Status: closed.** Item 7 is closed on the chairman's verdict of #18 (issue #18, Protocol-13 item 7). The
removal is merged: R1-R4 in PR #71 (`main` `6972826`, 2026-10-27 14:10 UTC), S1-S5 in PR #73 (`main`
`f1a5fada`, 2026-10-27 17:24 UTC, verdict comment 6448755277), this report in PR #77 (`main` `6b0283b6`,
blob `28d7e91a`). The full ring is green on `main` `dd399280` (tree `core/Code` `35d191ce`), ring
a633-codering on Lauterbourg-2, 2026-10-27 20:15-21:51 UTC: `fmt --all -- --check` exit 0,
`clippy --workspace --all-targets -- -D warnings` exit 0, `test --release --workspace --no-fail-fast`
exit 0 (`/srv/montana/a633-codering.out`); CI `audit-tools` SUCCESS on PR #82 (`dd399280`). The earlier
ring a626 on `f1a5fada` (before PR #76) was red by format, clippy and the timing test `mt-mnemonic`
`fast.rs:226` under load and is superseded. Self-verification by the council's sessions, not an
independent external audit.

Historical (marked 2026-10-28 UTC): the status line before this change read "Status: open. The removal is
merged (PR #73, `main` `f1a5fada`, 2026-10-27). The chairman's verdict of #18 is not given; the issue is
open ("#18 stays open until its remaining boxes are checked", comment 6448755277 on PR #73)."

This item concerns `Code`, not the native `Montana-Core` proof system. Paths below are under `core/Code/`
on `f1a5fada`.

## The decision: removed, not repaired

The item first asked to repair the lottery of `Code` (historical thresholds and weights, epoch
boundaries, complete reveals). The author decided otherwise.

- Comment 6396759556 (2026-10-25 10:56 UTC), the author's word of link 7796: "this is old -- now 1 coin
  is 1 second, full stop." With issuance at 1 coin per second of presence (#14), there is no recipient
  of a window's mint to draw. The threshold, the reveals, `lottery_target` and `tau2_reveal_count`, the
  calibration and the "accepted by quorum" path are removed from `Code`, not repaired. What remains of
  the item is the determinism of what stays: the same roots and the same state for every order of
  delivery, and rejection of the incomplete and the contradictory.
- Comment 6444586299, decision 279 of the author, (b), recorded in the constitution chain as 288
  (2026-10-27 14:11 UTC): remove the lottery and carry over the rule of `Montana-Core` (the lowest ticket
  by the aggregate) and 1 second = 1 coin from #14; the fields `target`, `reveals_root` and `winner` of the
  header are zeros, and the wire does not change.

## What was removed (PR #73, S1-S3)

Search of `crates/` on `f1a5fada` finds no occurrence of `apply_emission`, `determine_winner`,
`sorted_candidates_for_fallback`, `winner_history`, `lottery_history`, `validate_winner` or
`validate_included_reveals`. Of the reveals only the wire code remains: `MsgType::SshaReveal`
(`mt-net/src/msg_type.rs:11`), ignored at `montana-node/src/commands/start.rs:1533`, and the help text
`montana-node/src/main.rs:95`.

- **S2, issuance** (`f0b93e4`): `apply_emission`, which credited `EMISSION_moneta` to the operator of
  `winner_id` and panicked on an unknown winner, is replaced by `apply_window_credit`
  (`mt-account/src/lib.rs:575`). The proposal of W credits every living node of W-1, each counted once,
  by `window_credit_moneta` (`:542`) = 60 coins. A node or account missing from the tables is credited
  nothing. `reward_moneta` and `supply_moneta` are removed.
- **S1, the proposer** (`2000a63`): the reveals and their pool, `compute_endpoint`, `validate_reveal`,
  the weights and `ln_q64`, `Candidate`, the cascade over the candidates of W-2 and the winner and
  lottery histories, and their tests, together with `mt-lottery/tests/external_oracle.rs`.
- **S3, the header** (`eb7db86`): `target`, `included_reveals_root`, `winner_endpoint` and `winner_id` stay
  in the signed 3722-byte layout and are written as zeros.

## The rule that decides the proposer now

The rule is carried over from `Montana-Core` (`core/Montana-Core/crates/montana-node/src/pulse.rs`,
`take_the_proposal`; Canon "The threshold of the draw"), not its code.

- `mt-consensus/src/lib.rs:193` `ticket` = SHA-256 of `mt-ticket`, 0x00, the aggregate of W-2 and the
  `node_id`.
- `:199` `proposer_order` sorts the electorate by (ticket, `node_id`), each node once.
- `:211` `proposer_at(W, aggregate, electorate, depth)` gives the depth-th lowest ticket; `NO_PROPOSER`
  (`:191`) before window 2, with no electorate, or past the cascade.
- `:317` `validate_proposer_is_canonical` recomputes it at the depth the signed header declares.
- `:305` `validate_retired_fields` refuses a header where any of the four lottery fields is non-zero.
- The aggregate is `mt-timechain/src/lib.rs:117` `cemented_bundle_aggregate(W-2, set)`, with the set kept
  in `bc_set_history`. `montana-node/src/commands/start.rs:892` `held_aggregate` gives no value for a
  window past 1 whose confirmers the node does not hold; the follower then refuses the envelope
  (`start.rs:1301-1304`). The electorate is the active nodes of the Node Table at W
  (`start.rs:901` `electorate_at`); the proposer and the follower use the same `canonical_proposer_at`
  (`start.rs:918`).
- The follower's checks, in order: `start.rs:1307` canonical proposer, `:1316` retired fields, `:1327`
  a confirmation named twice.
- **S4** (`f7cc088`): an envelope of a window this node already applied (`start.rs:1251-1259`) goes to
  `keep_equivocation` (`start.rs:938`); it is refused and nothing moves. The pair is kept when the second
  envelope names the proposer of the applied one, carries another `proposal_hash` and verifies under that
  proposer's key. This is the chairman's ruling, not the author's (PR #73 comment 6447242904): "reject
  both" would abandon a decision the machine verified; the sources are `core/docs/Montana Consensus.md`
  `:1382` (invariant 13), `:425-428` and `:1239-1243`. `docs/SPEC_DEVIATIONS.md:700` closes DEV-026.
- **S5** (`940bc33`): an envelope whose confirmations of W-1, or whose evidence of W, name one node
  twice is refused whole (`names_a_node_twice`, `start.rs:963`, used at `:1327`).

## Tests

Each test is red on its parent `6972826` or on a mutant, and green on the branch (PR #73 description and
the helper's comment 6447975036). Self-verification, not an independent external audit.

| Requirement | Test | Place on `f1a5fada` |
|---|---|---|
| Every delivery order gives the same window and roots | `order_tests::every_delivery_order_gives_the_same_window_and_roots` (24 orders) | `montana-node/src/commands/start/order_tests.rs:426` |
| A window's proposer is the same on every order | `order_tests::a_window_has_one_proposer_whatever_the_order_of_delivery`; `mt-consensus` `the_proposer_is_the_same_on_every_order_of_the_electorate` | `order_tests.rs:457`; `mt-consensus/src/lib.rs:756` |
| A header with a non-zero lottery field is refused | `order_tests::a_header_with_a_non_zero_lottery_field_is_refused`; `mt-consensus` `a_header_with_a_non_zero_lottery_field_is_refused` | `order_tests.rs:490`; `mt-consensus/src/lib.rs:970` |
| Issuance of a window equals its seconds | `order_tests::a_closed_window_issues_its_seconds_to_every_living_node`; `mt-account` `the_issuance_of_a_window_is_its_seconds_for_every_living_machine` | `order_tests.rs:607`; `mt-account/src/lib.rs:1998` |
| S4: a second envelope of an applied window is refused, the state byte-identical, the pair kept | `order_tests::a_second_envelope_of_an_applied_window_is_refused_and_the_pair_kept` | `order_tests.rs:526` |
| S5: a confirmation named twice refuses the envelope whole | `order_tests::an_envelope_naming_one_confirmation_twice_is_refused_whole` | `order_tests.rs:558` |
| The ticket is the frozen value (Python hashlib oracle `031819bb...1d1e`) | `mt-consensus` `the_ticket_is_the_frozen_value` | `mt-consensus/src/lib.rs:727` |

Red before: on the parent `6972826` with a probe holding the same four tests of S1-S3,
`test --release -p montana-node --lib order_tests` gave exit 101, 0 passed, 4 failed. Red on mutants of
`940bc33`: `mut-s4b` exit 101 ("a second envelope moved the state", `order_tests.rs:537`) and `mut-s5` exit
101 ("an envelope naming a confirmation twice moved the state", `order_tests.rs:580`). The first S4
mutant run, `mut-s4`, returned exit 0 because its snapshot held the restored file, not the mutant; it
was repeated as `mut-s4b`.

Commands (Lauterbourg-3, `run.py`, in `core/Code`). Exit codes as the PR #73 description and the helper's
comment 6447975036 state:

| Run | Tree | Command | Exit |
|---|---|---|---|
| s1-clippy | S1 | `clippy -p mt-codec -p mt-consensus -p mt-lottery -p mt-account -p mt-conformance -p montana-node -p mt-examples -p mt-genesis -p mt-state --all-targets -- -D warnings` | 101 (`NetCtx.identity` never read; `publish_window_artifacts` 8 arguments) |
| s1-clippy2 | `2000a63` | same | 0 |
| s3-clippy | `eb7db86` | `clippy -p mt-consensus -p montana-node --all-targets -- -D warnings` | 0 |
| tip-libtest2 | `c15e8ae` | `test --release -p mt-codec -p mt-consensus -p mt-lottery -p mt-account -p mt-conformance -p montana-node -p mt-genesis -p mt-state --lib` | 0 (an earlier run exited 253, a wrapper fault: ssh closed) |
| tip-itest2 | `c15e8ae` | `test --release -p mt-account -p mt-consensus -p mt-lottery --test determinism_invariants` | 0 (26, 18 and 11 passed; an earlier run exited 253, a wrapper fault) |
| red-parent | `6972826` plus probe | `test --release -p montana-node --lib order_tests` | 101 (0 passed, 4 failed) |
| tip-build | `4054547` | `build --release --workspace` | 0 |
| s4-test | S4 | `test --release -p montana-node --lib order_tests` | 0 (7 passed) |
| s5-clippy | `940bc33` | `clippy -p mt-consensus -p montana-node --all-targets -- -D warnings` | 0 |
| s5-libtest | `940bc33` | `test --release -p montana-node -p mt-consensus --lib` | 0 (montana-node 60, mt-consensus 47 passed) |
| mut-s4b | `940bc33` plus S4 mutant | `test --release -p montana-node --lib order_tests::a_second_envelope` | 101 (required) |
| mut-s5 | `940bc33` plus S5 mutant | `test --release -p montana-node --lib order_tests::an_envelope_naming` | 101 (required) |
| node-itest | `940bc33` | `test --release -p montana-node --tests` | 0 (lib 60, `e2e_init` 6 passed; `three_peer_e2e` 1 ignored in the file) |
| (Mac) | `4054547` | `python3 doc/external-audit/snapshot.py --revision HEAD` | 0 |

`cargo fmt --all --check` gave exit 1 at `s4`, `s5` and `4054547` (75 hunks in 25 files at the tip, the
same count as `main`; none in a line this branch wrote). The chairman's verdict (6448755277, Agent 624,
2026-10-27 17:26 UTC) checked each snapshot against `940bc33` on the host's `core.git` (`git diff --stat`
empty, so no mutant was in the tree) and read the same exit codes: `test --release -p montana-node --tests`
0 (snapshot `f170d69e`); `--lib` montana-node 60 and mt-consensus 47, 0 (`1e8b2c4f`); `clippy -D warnings`
0 (`df2cfa9b`); mutants S4b and S5 101; main is an ancestor, the merged `core` tree is `a236ef2a18ff`
(`RELEASES.md` row), CI `audit-tools` SUCCESS.

## What remains

- **The chairman's verdict of #18.** Issue #18 is open; the verdict on its remaining boxes is not given. Historical (marked 2026-10-28 UTC): the verdict is the one named in the status line above.
- **The full ring** (`test --release --workspace`) is the chairman's; it was not run by the helper. Historical (marked 2026-10-28 UTC): the ring ran on `main` `dd399280` (tree `core/Code` `35d191ce`) as a633-codering on Lauterbourg-2 and is green: `fmt` 0, `clippy` 0, `test --release --workspace --no-fail-fast` 0, 2026-10-27 20:15-21:51 UTC.
- **S4b, recorded and not changed** (comment 6447975036): two proposers of one window at two cascade
  depths. `mt-consensus` `validate_proposer_is_canonical` accepts the depth the signed header declares;
  the proposer's own depth comes from local silence (`start.rs:883` `fallback_depth_at`). Between a depth-1
  and a depth-2 envelope of one window arrival still decides which is applied; after S4 the later one is
  refused and no pair is kept, because the proposers differ. The chairman takes it up after S4 and S5
  (comment 6447242904).
- **DEV-055, open** (`docs/SPEC_DEVIATIONS.md:1130`): the ticket of `Code` is drawn from the `node_id`,
  not from the machine's secret as Canon.md:2094 and `mt-derive/src/aggregate.rs:67` draw it.
- **Format.** `cargo fmt --all --check` exits 1 on files this branch did not write; two files of format
  were left to this branch by PR #76 and go with the main format fix (verdict 6448755277).
- **K5 (#17)** also edits `start.rs` and rebases onto this merge. How a network with no electorate opens
  is the author's decision 280 (#17), not decided by this rule.
- This is self-verification by the council's sessions, not an independent external audit.
