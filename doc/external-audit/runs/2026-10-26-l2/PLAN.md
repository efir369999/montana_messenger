# Issue 2: contributor audit on L2

Source pin: `a835c1c3ff4bc95ea3c75e02391d3d69e2e08833`.
The author authorized server checks on 2026-10-26 and then selected L2.
This is the implementing contributor's technical audit, not an independent external audit.

## Work and evidence

1. Reproduce source inventory, consistency and audit-instrument checks at the pin.
2. Run the four source-premise probes; their success characterizes limitations and controls,
   rather than establishing GPA resistance.
3. Run pinned Rust 1.92.0 fmt, strict clippy, release test compilation, each discovered test
   executable in its own network namespace, doctests and release builds for both core trees.
4. Recheck published findings against their owning source paths and callers. Keep a coverage
   ledger, including partial/absent/unmapped areas, and record concrete remedies.
5. Report every command, return code, timeout, ignored test and environmental failure. Retain
   logs and source/toolchain identities. A resource kill is not an assertion failure or pass.

The initial Frankfurt probe was stopped when the author selected L2. That shared production
host has one CPU and about 2 GiB RAM. No deployed service was changed. L2 has 16 CPUs and about
64 GiB RAM, but existing Kani runs occupied most memory at intake. They remain untouched.
Our runner has its own memory cgroup and fresh target directories; compilation uses four jobs
and test binaries run sequentially while that contention exists. Test networking is loopback
inside private namespaces. The OpenSSL differential oracle uses its matching library directory.

## Boundaries

Public source is pinned separately from unmerged PRs; this run does not import #33/#50/#52/#53.
No production traffic capture, service restart, secret access or public listener is required.
The complete deployed application/service route, phone background/lock behavior, binary
provenance, multi-operator GPA experiments, hardware side channels and independent review need
separate evidence. A synthetic correlation control must not be called a Montana GPA experiment.
Existing private service snapshots may be examined locally; their current deployment identity
must be verified before treating them as the deployed implementation. Newly discovered security
weaknesses stay in the private report under SECURITY.md; only already-public findings and safe
verification metadata are proposed publicly. No issue closure or protocol acceptance is claimed.

-- GPT agent [01a17795], gpt-6, contributor of the Montana council

## Resource-priority update

At 2026-10-26 13:43:30 UTC, after the chairman's PR #54 comment, the running audit
unit changed from an unspecified CPUWeight to CPUWeight=1. MemoryMax remains 4 GiB
and MemorySwapMax remains zero. Protocol-13 item 2/p2-close work on L2 has priority.
Earlier commands ran before this update; later timings reflect this shared-host policy.
A timeout is not attributed to contention without supporting observations. No existing
chairman job is stopped or changed. The raw before/after property receipt is retained.
