# L2 run ledger — interim, not a completed gate

Evidence snapshot: 2026-10-26T14:09:47.977364+00:00. Source pin `a835c1c3ff4bc95ea3c75e02391d3d69e2e08833`.

The main runner is still executing. `RUN-RESULTS.json` explicitly records `complete: false`.
Only completed commands appear below. Their unmodified logs are checked against the SHA-256
in that file. No omitted, pending, ignored or timed-out check is counted as a pass.

The toolchain is Rust 1.92.0; native OpenSSL uses its matching libraries. Each test binary runs
with one test thread in its own loopback-only network namespace and fresh source-specific targets.
The current unit policy is CPUWeight=1, MemoryMax=4 GiB, MemorySwapMax=0. The before/after
receipt is in priority-change.json; Protocol-13 item 2/p2-close jobs have priority. Earlier
commands ran before this priority adjustment. A future timeout needs diagnosis, not an
automatic claim of a product defect or of host contention.

| Completed command | Exit | Seconds | Log |
| --- | ---: | ---: | --- |
| git-init | 0 | 0.134 | [log](logs/git-init.log) |
| git-remote | 0 | 0.012 | [log](logs/git-remote.log) |
| git-fetch | 0 | 4.16 | [log](logs/git-fetch.log) |
| git-checkout | 0 | 1.13 | [log](logs/git-checkout.log) |
| rustc | 0 | 0.93 | [log](logs/rustc.log) |
| openssl | 0 | 0.22 | [log](logs/openssl.log) |
| python-tests | 0 | 10.269 | [log](logs/python-tests.log) |
| snapshot | 0 | 0.274 | [log](logs/snapshot.log) |
| reconcile | 0 | 1.741 | [log](logs/reconcile.log) |
| traffic-control | 0 | 0.176 | [log](logs/traffic-control.log) |
| probe-fetch | 0 | 3.255 | [log](logs/probe-fetch.log) |
| probes | 0 | 167.458 | [log](logs/probes.log) |
| Montana-Core-fmt | 0 | 1.425 | [log](logs/Montana-Core-fmt.log) |
| Montana-Core-fetch | 0 | 1.176 | [log](logs/Montana-Core-fetch.log) |
| Montana-Core-clippy | 0 | 77.621 | [log](logs/Montana-Core-clippy.log) |
| Montana-Core-test-build | 0 | 225.343 | [log](logs/Montana-Core-test-build.log) |
| Montana-Core-test-000-a_ballot_casts_the_standing_a_machine_lived | 0 | 214.721 | [log](logs/Montana-Core-test-000-a_ballot_casts_the_standing_a_machine_lived.log) |
| Montana-Core-test-001-a_closed_window_is_never_pledged_again | 0 | 38.844 | [log](logs/Montana-Core-test-001-a_closed_window_is_never_pledged_again.log) |
| Montana-Core-test-002-a_count_at_the_quorum_moves_neither_head_nor_rights | 0 | 18.882 | [log](logs/Montana-Core-test-002-a_count_at_the_quorum_moves_neither_head_nor_rights.log) |
| Montana-Core-test-003-a_device_joins_the_running_chain | 0 | 413.714 | [log](logs/Montana-Core-test-003-a_device_joins_the_running_chain.log) |
| Montana-Core-test-004-a_fuller_cement_closes_on_a_later_beacon | 0 | 95.817 | [log](logs/Montana-Core-test-004-a_fuller_cement_closes_on_a_later_beacon.log) |
| Montana-Core-test-005-a_machine_keeps_what_it_holds | 0 | 0.22 | [log](logs/Montana-Core-test-005-a_machine_keeps_what_it_holds.log) |
| Montana-Core-test-006-a_machine_stopped_lets_its_store_go | 0 | 0.275 | [log](logs/Montana-Core-test-006-a_machine_stopped_lets_its_store_go.log) |
| Montana-Core-test-007-a_payer_is_told_again_where_a_replay_moves_its_frame | 0 | 116.142 | [log](logs/Montana-Core-test-007-a_payer_is_told_again_where_a_replay_moves_its_frame.log) |
| Montana-Core-test-008-a_payers_own_frame_applies_with_its_round | 0 | 115.099 | [log](logs/Montana-Core-test-008-a_payers_own_frame_applies_with_its_round.log) |
| Montana-Core-test-009-a_payment_crosses_the_wire | 0 | 115.948 | [log](logs/Montana-Core-test-009-a_payment_crosses_the_wire.log) |
| Montana-Core-test-010-a_payment_settles_before_a_window | 0 | 232.71 | [log](logs/Montana-Core-test-010-a_payment_settles_before_a_window.log) |
| Montana-Core-test-011-a_record_is_opened | 0 | 192.812 | [log](logs/Montana-Core-test-011-a_record_is_opened.log) |
| Montana-Core-test-012-a_record_raises_one_machine | 0 | 362.179 | [log](logs/Montana-Core-test-012-a_record_raises_one_machine.log) |
| Montana-Core-test-013-a_round_on_two_machines | 0 | 39.876 | [log](logs/Montana-Core-test-013-a_round_on_two_machines.log) |
| Montana-Core-test-014-a_round_over_the_wire | 0 | 37.627 | [log](logs/Montana-Core-test-014-a_round_over_the_wire.log) |
| Montana-Core-test-015-a_round_requires_an_answer | 0 | 57.783 | [log](logs/Montana-Core-test-015-a_round_requires_an_answer.log) |

## Meaning of the results

- Audit instrumentation: 36 Python tests passed. Snapshot and reconciliation succeeded; reconciliation compared 10 quantities across 24 statements.
- Existing premise probes: 4 passed, 0 ignored. Their success confirms the characterized constructions/controls; it does not establish GPA resistance.
- Supplemental published F-1: 2 passed, 0 ignored; two valid channel legs and a rejected bad signature, with scope in channel-probes/README.md.
- Supplemental published F-13: 1 passed, 19,450 malformed/stale cases rejected and two valid controls; native parser boundaries only.
- New core: formatting, strict all-target Clippy and release test compilation succeeded. 16 of 96 compiled test executables had completed at this snapshot. The rest, doctests and final release build are pending; the legacy Code workspace stage is pending.
- The synthetic traffic demonstration checks the instrument only. No production or real-app GPA capture is included.
- A separate dependency/advisory investigation is retained for the author privately under SECURITY.md. This public ledger does not disclose new project-specific security findings.

No application build, installation, released-binary equivalence, complete production service audit,
multi-operator GPA experiment, Protocol-13 acceptance or independent external review is claimed.

-- GPT agent [01a17795], gpt-6, contributor of the Montana council

## Later checkpoint: missing differential dependency

The original `Montana-Core-test-028-differential` exited 101: four tests passed and two
liboqs comparisons failed before comparison because `MT_LIBOQS` named no library. This is
a runner-environment failure, not evidence of a cryptographic mismatch. The unmodified
[log](logs/Montana-Core-test-028-differential.log) and [command/hash receipt](DIFFERENTIAL-FAILURE.json)
are retained. The earlier snapshot above remains historical; the main runner continues and
its gate is not green. A ready liboqs was found on the host; the bounded repeat script
records its hash and reuses the same pinned binary, with private scratch and network namespace.
A repeat result will be separate evidence and will not erase this failure.

The bounded repeat at 2026-10-26T15:02:25Z passed all six tests, exit 0, no ignored tests
and no timeout. [Receipt](DIFFERENTIAL-REPEAT.json), [log](logs/Montana-Core-differential-repeat.log).
The executable and installed library hashes agree before and after. The library reports
liboqs 0.16.0; its installed configuration has OpenSSL disabled and enables ML-KEM-768 and
ML-DSA-65. The retained build recipe names source commit
`5a1a854b0dc9f2141bdc771c555ee60c37950183`, but the old source/build directories are not
present: that recipe is provenance context, not a reproduced library build. The binary
hash in the receipt is the tested artifact identity. No library was installed or rebuilt.

The repeat reused the original executable under a private loopback-only network namespace,
set `MT_LIBOQS` to that existing library, supplied isolated temporary storage and enabled
uncaptured test output. Its separate unit requested CPUWeight=1, MemoryMax=512 MiB, zero
swap and a 120-second unit bound; the script also imposed a 60-second command timeout.
It ran for 1.159 seconds as reported by systemd, with 2.3 MiB peak memory and no swap.
Only this executable was repeated; the original main runner and its retained failure were
not changed. These results resolve the missing dependency for this differential check,
not the still-running full core/legacy gate, and do not apply to newer PR heads.
