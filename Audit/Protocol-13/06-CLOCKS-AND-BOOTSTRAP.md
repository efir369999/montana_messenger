# 6. Remove clock authority and implicit private bootstrap

**Status: closed for `core/Montana-Core`; for `core/Code` with the recorded limit of decision 334 (a).** Item 6 is closed on
the chairman's verdict of #17 (issue #17, Protocol-13 item 6, comment issuecomment-6528920596). It is not closed "across both generations":
- K1 (`core/Montana-Core`): Genesis only under window 0 (`certificate.rs:154`) -- `242dce79`, in main.
- K3 (`core/Montana-Core`): the verdict reads no clock -- one verdict under clocks x1/x3/x1000 and budgets x1/+1/x1000;
  the gate `check_no_clock_in_the_verdict` (`mt-conformance/src/parse.rs:4674`) and the test
  `montana-node/tests/a_verdict_reads_no_clock.rs` -- `e6c1d7bf`, in main.
- K0 (`core/Montana-Core`): a network opens by `--open` on an empty store, never by an implicit `--from` -- PR #69 (`f4cd115`).
- C-3: the waits of conduct may read local clocks and no verifier reads them (`Montana Constitution.md` I-15; Registry
  CNS-19) -- PR #96 (`ac6347c6`).
- K5 (`core/Code`): production values in `mt-genesis`; `--d-test-override` refused in a release build; no start without
  `--genesis-manifest` -- PR #96 (`ac6347c6`).
- The limit (`core/Code`): the clocked cascade moves proposer eligibility (section below); bounded by #21 K6 (`e5cc3bc`) --
  an exhausted cascade appoints nobody and says `STALLED`.
- Citations brought to main -- PR #130 (`94dcb2a`).
- Rings: L3 `k776-m118p` on `66aa47c` (`core/Montana-Core`, the core tree of main after #130): `cargo fmt --all -- --check` 0,
  `cargo clippy --workspace --all-targets -- -D warnings` 0, the test binaries 120 rc 0 (136 suites, 823 passed, 0 failed), doc tests rc 0; L3 `k759-code17` on the
  `core/Code` tree `4b8cff73`: fmt 0, clippy 0, `cargo test --release --workspace --no-fail-fast` 1397 passed, 1 failed
  (`mt-mnemonic` `sources.rs:655`, a flap of the host by decision 404 (a); its tests are their own issue by 404 (c)).

The native candidate removes round-dependent quorum lowering and self-selected
restart authority. Exhausting a polling budget returns an error; it cannot
manufacture a verified answer. Targeted tests exercised that refusal. Polling
delays remain scheduling choices, not evidence permitting a close.

This does not establish clock independence of the earlier `Code` runtime. Its
historical fallback and bootstrap paths require separate verification; earlier
entries in `core/Code/docs/SPEC_DEVIATIONS.md` are dated history, not current
closure evidence. The container's explicit isolated mode must not be presented
as authenticated joining of the public network.

Closure requires replaying the same authenticated protocol state under
different clock values, scheduler delays and machine speeds, with identical
validity and proposer eligibility. The test must exercise the used runtime
paths in both generations and cover initialization. A timer may schedule an
attempt or report a stall; it must not grant consensus authority. Test-only
population, threshold or trust-anchor settings must be explicitly isolated and
unavailable as silent production defaults.

No deployed host's clock was changed during this review.

## The limit for `core/Code` (decision 334 (a))

By the Author's decision 334 (a) (record 339 of the constitution chain,
2026-10-29 09:28 UTC), the clocked cascade of `core/Code` stays a property of
the earlier generation, which answers to its own spec target (decision 330
(a)), and it is recorded in `core/Code/AUDIT.md` ("Known limitations", item 4).

- **The clock.** The silence since the last cement is read on a monotonic clock
  (`core/Code/crates/montana-node/src/commands/start.rs:582`,
  `last_cement_at.elapsed()`).
- **The depth.** `fallback_depth_at` turns it into the depth of the cascade
  (`start.rs:952-955`, `silence / fallback_secs`, with `fallback_secs` taken
  from the measured tick at `:393`).
- **The proposer.** The depth chooses which machine may propose
  (`canonical_proposer_at`, `start.rs:585-586` and `:987-997`).

A follower checks the proposer at the depth the signed header declares and
reads no clock (`core/Code/crates/mt-consensus/src/lib.rs:316-332`). In this
generation, though, a timer still moves proposer eligibility, which the
closure requirement above forbids.

K6 of issue #21 (`e5cc3bc`) bounds it. From window 2 an exhausted cascade
appoints nobody, the node says `STALLED` and does not appoint itself
(`start.rs:582-598` and `:1006-1018`; test
`an_exhausted_cascade_halts_and_never_self_appoints`, `start.rs:2226`), so a
timeout no longer closes a window in a private chain. K6 does not take the
clock out of the depth.

The closing scope of this item is therefore stated, not widened. It closes for
the native core, `core/Montana-Core`, whose verdicts read no clock (the gate
`check_no_clock_in_the_verdict`,
`core/Montana-Core/crates/mt-conformance/src/parse.rs:4674`, and the test
`crates/montana-node/tests/a_verdict_reads_no_clock.rs`). It closes for
`core/Code` only with the recorded limit, and never as "across both
generations". The status line above stands until the chairman's public verdict;
this section states the scope that verdict can take, and does not give it.
