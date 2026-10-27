# 2. Close only a verified canonical Proposal

**Status: closed.** Item 2 is closed by PR #58, merged into `main` as `084273c1` (2026-10-26
15:38:50 UTC). The chairman's closing comment on #10 is 6420198473 ("Boxes 1-7: all hold"); his
verdict on the PR is
<https://github.com/efir369999/montana_messenger/pull/58#issuecomment-6420183989>. The issuance
right on the redemption path (`pay.rs:78`) is out of scope here. It belongs to item 3 (#14), which is
closed separately (03-AUTHORIZED-ISSUANCE.md).

This page used to describe the public baseline `6303fa5`. There, `live_doing` treated
`attempts_the_close` as the close. That is no longer the code. Every line below is read on
`cb4283c` (tree `729a7123`), under `core/Montana-Core/crates/`. The merge `084273c1` takes the
branch head `3c418a4`, which adds this report's runs to `cb4283c`.

## Where the head, the closed window and the right move

- **The close of a lived window.** `live_doing` calls `take_the_proposal(...)?`
  (`montana-node/src/pulse.rs:1794-1803`) and then `machine.close(...)?` (`pulse.rs:1814-1820`).
  `Machine::close` (`montana-node/src/lib.rs:1063`) keeps the proposals and writes the head and
  the closed window in one record, through `Store::commit_window` (`lib.rs:1116`). The record goes
  through `shows` first (`mt-store/src/lib.rs:418-430`), which refuses a head or a closed window
  whose proposal the store does not hold.
- **`take_the_proposal` returns one of two things** (`pulse.rs:2320-2387`):
  - a proposal standing at the window's points under the identifier this machine recomputed
    (`pulse.rs:2331`), judged whole by `verify_proposal` (`pulse.rs:2411-2421`);
  - its own proof, verified at `pulse.rs:2359`.

  Otherwise, after `patience` askings, it returns `Err("a window no proposal of its decision ever
  stood at")` (`pulse.rs:2380-2384`), and `live_doing` leaves before the close.
- **The count only selects the final beacon.** `carries_the_quorum` (`pulse.rs:2260`) picks the
  beacon. That authorizes the attempt to take a Proposal, not the close.
- **The right.** It is issued at `pulse.rs:1833-1873`, only after `close` has succeeded, and only
  for the window this close made final (`before.id()`, `pulse.rs:1839`). It is computed from the
  decided roll. The window just closed carries `right: None` (`pulse.rs:1882`).
- **The walk of a joining device.** `certificate::walk` (`pulse.rs:2572`) judges each
  certificate and Proposal first. Only then do `finalize` (`pulse.rs:2575`) and `let_go_of`
  (`pulse.rs:2580`) move the head and the closed window, through the same `commit_window` and
  `shows`.

No path in `src` moves the head, the closed window or a right of the pulse without a verified
Proposal.

## The test seam

`pulse::withhold` (`pulse.rs:2270-2307`) holds back the Proposal a machine proved of its own, so a
test can reach "quorum and beacon, but no verified Proposal" on the live path.

- It sits behind the cargo feature `withhold` (`montana-node/Cargo.toml:34-35`). Only the crate's
  own dev-dependency turns it on (`Cargo.toml:41-42`).
- Without the feature, `withholds` is the constant `false` (`pulse.rs:2301-2307`).
- It is reached only after `verify_proposal(&own, ...)` (`pulse.rs:2359-2360`).

It changes no rule. The chairman's review of 2026-10-26 (comment 6417725558) confirmed the code of
`cce95b2` (box 4) and `bd62ded` (box 3), and that in the normal build `cargo tree -e normal` shows
`default` alone.

## Acceptance boxes of #10

| # | Box | Evidence | Verdict |
|---|-----|----------|---------|
| 1 | Gate -1: file and line for every move of the head, the closed window and the right | the section above | holds (by reading) |
| 2 | A positive case closes, the head moves onto the identifier, and the right is issued | `tests/a_device_joins_the_running_chain.rs:89-113`; `tests/two_hosts_live_a_window.rs:109-137` | holds (by run) |
| 3 | Absent, invalid and substituted proofs are refused before any change | `tests/certificate_matrix.rs` (at the door); `tests/a_device_joins_the_running_chain.rs:149-179` (at the walk); `a_substituted_or_unproven_proposal_at_the_points_closes_nothing` in `tests/a_quorum_without_a_verified_proposal_closes_nothing.rs` (on the live path, six substitutes) | holds for the head, the closed window and the right of the pulse; the right on redemption is item 3 |
| 4 | A count at the quorum without a verified Proposal moves nothing, and the test fails on code that closes on the count | `tests/a_quorum_without_a_verified_proposal_closes_nothing.rs`, through `pulse::live` and across a restart | holds (by run, and by mutation M1) |
| 5 | The Proposal, its proof and its identifier persist, survive a restart, are served and are verified by a joining machine | `tests/a_device_joins_the_running_chain.rs:182-204`; `tests/a_window_outlives_the_restart_of_every_holder.rs:79-121` | holds (by run) |
| 6 | Commands, exit codes and commits kept; one network namespace per test binary on the core test host | the runs below | holds |
| 7 | Self-verification, then the chairman's review | #10 | closed: comment 6420198473 |

## Mutations

Both mutants were run on detached commits that are on no branch.

- **M1** (`4c5bb01`): `live_doing` closes on a proposal assembled from the decided cement.
  - The box 4 test: rc 101, 0 passed, 1 failed, 335.75 s.
  - The mutant closed window 2 and issued the right of window 1.
- **M2** (`bb6085c`): `standing_proposal` takes a proposal under the expected identifier without
  `verify_proposal`.
  - The box 3 live test: rc 101, 0 passed, 1 failed, 265.46 s.

## Runs

Self-verification by the council's sessions, not an independent external audit.

- **`2556c4b`** (box 6; the same core tree as `cb4283c` except for one test comment; the commit is
  not in this repository).
  - Run `a554-p2lock` on the core test host: `cargo test --locked`.
  - All 45 test binaries of `montana-node` and `mt-store` ran, each under `unshare -n`.
  - 0 binaries failed.
  - It also found F-560-1: the line `"montana-node"` that the self dev-dependency adds to `Cargo.lock`,
    without which `cargo metadata --locked` on `a8c9cab` exits 101 ("lock file needs to be updated").
    `cb4283c` carries the line (comment 6417725558).
- **`a8c9cab`** (`bd62ded` plus four comment lines in a test header; the same code as `cb4283c` except the `Cargo.lock` line of `2556c4b`).
  - Runs 16-19 of the helper p2-close of Agent 552 on Lauterbourg-2: `cargo test -p montana-node --no-fail-fast` in four batches, together the lib, 2 bins and 40 test files.
  - rc 0 in each batch: 100 passed, 1 ignored (in the lib), 0 failed; `four_machines_decide_one_name` 2240.63 s, boxes 3 and 4 2 of 2 in 643.21 s.
  - Not `--locked`, under `systemd-run`, without a network namespace per binary; checked by the chairman against the log (link 8899).
- **`cb4283c`**, the head that merges, on Lauterbourg-3 (snapshots of tree `729a7123`):

| Name | Command | rc | Result |
| --- | --- | --- | --- |
| c1 | `cargo metadata --locked --format-version 1 --no-deps` | 0 |  |
| c2 | `cargo fmt --all --check` | 0 |  |
| c3 | `cargo clippy --locked --workspace --all-targets -- -D warnings` | 0 |  |
| c4 | `cargo test --locked -p mt-store` | 0 | 3 binaries, 25 passed, 0 failed |
| s1 | `cargo test --locked -p montana-node --no-fail-fast --test four_machines_decide_one_name` | 0 | 1 binary, 1 passed, 0 failed (3486.86s) |
| s2 | the same, `--test` a_round_over_the_wire, a_window_outlives_the_restart_of_every_holder, certificate_matrix, a_ballot_casts_the_standing_a_machine_lived | 0 | 4 binaries, 11 passed, 0 failed |
| s3 | the same, `--test` a_quorum_without_a_verified_proposal_closes_nothing, a_device_joins_the_running_chain, three_machines_live_a_window, a_walk_from_an_anchor | 0 | 4 binaries, 5 passed, 0 failed |
| s4 | the same, `--test` two_hosts_live_a_window, a_payment_settles_before_a_window, issuance_audit, value_enters_the_network, a_verdict_reads_no_clock, a_record_is_opened, a_wallet_pays_a_wallet, genesis_stands_under_window_zero_alone | 0 | 8 binaries, 12 passed, 0 failed |
| s5 | the same, `--lib --bins` and the other 23 test binaries | 0 | 26 binaries, 71 passed, 1 ignored (in the lib), 0 failed |

Each run is a systemd unit with `PrivateNetwork=yes`, `MemoryMax=12G` and `CARGO_NET_OFFLINE=true`. Logs are kept on the host in `/srv/montana/a562-logs/`.

Together the shards s1-s5 ran the 43 test binaries of `montana-node` (the lib, 2 bins and 40 test files): 100 passed, 1 ignored (in the lib), 0 failed -- the same counts as runs 16-19 on Lauterbourg-2.

The closing comment 6420198473 states the same result ("on Lauterbourg-3 at `cb4283c`, the 43 test
binaries of `montana-node` gave rc 0: 100 passed, 1 ignored, 0 failed"; "`mt-store`, `fmt`, `clippy
-D warnings` and `metadata --locked` are rc 0"; "the mutations M1 and M2 make the box 4 and box 3
tests fail") and adds: "CI `audit-tools` passed on `3c418a4`."

## Outside this closure

- The issuance right on redemption: `pay.rs:78` took the count of the living from the operator,
  not from a kept final Proposal. That is item 3 (#14), reproduced by `tests/issuance_audit.rs`;
  the closing comment of #10 carries it to #14.
- Whether a machine's local reading of the cement is the agreed decision. The closing comment
  carries it to local finality (#4), which is item 1.
- Kani (PR #29) is a separate formal check; the closing comment carries it there, by the author's
  decision 208 (comment 6420527482).
- Finding R-1 of the Gate -1 reading (comment 6373805263: the right of W is printed and shown as a
  share before W is final): the closing comment does not name it. Not recorded.
- This is self-verification by the council's sessions, not an independent external audit.
