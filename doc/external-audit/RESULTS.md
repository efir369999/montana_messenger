# Reproduction record

Date: 2026-10-22. Source reviewed:
`e558daace1ef32283167867cfa2cf8db883d48fe`. This is implementer/contributor verification,
not an independent audit. No deployed server or physical phone was tested.

Environment: macOS/Darwin arm64, Python 3.12.2, Rust 1.92.0
(`ded5c06cf 2025-12-08`), host OpenSSL 3.6.2. The client core/harness builds its own
OpenSSL 3.5.5 from the committed lockfile. Commands ran from the repository root
except the two full baseline workspaces indicated below.

## Completed checks

| Exact command | Observed result | What it establishes |
|---|---|---|
| `python3 -m unittest discover -s doc/external-audit/tests -v` | 26 tests passed | Inventory mismatch/missing/duplicate handling and attack-instrument positive/negative controls |
| `python3 doc/external-audit/snapshot.py --revision e558daace1ef32283167867cfa2cf8db883d48fe` | Exit 0; output in [snapshot.json](snapshot.json) | The three RELEASES folder trees match this public commit; all three lockfiles and the separate Protocol-13 source are pinned |
| `rustup run 1.92.0 cargo test --release --locked --offline --manifest-path doc/external-audit/probes/Cargo.toml` | 4 tests passed, 0 failed | Characterization of the actual libraries: variable sealed length, multiple padding buckets, reusable queue ID, one-time fetch nonce |
| `rustup run 1.92.0 cargo fmt --manifest-path doc/external-audit/probes/Cargo.toml -- --check` | Exit 0 | Harness formatting |
| `git diff --check` | Exit 0 | Patch whitespace |

All registry dependencies in the harness lockfile were also compared with `core/Code/Cargo.lock`
by `(name, version, source, checksum)`: no dependency version or checksum changed. The lock was
seeded from the existing client lock because fresh offline resolution refused the yanked
transitive `spin 0.9.8`. The locked build above succeeded without replacing that dependency.

Synthetic positive control:

```sh
python3 doc/external-audit/traffic.py --demo > /tmp/montana-audit-positive-control.json
python3 doc/external-audit/traffic.py /tmp/montana-audit-positive-control.json --max-lag 3
```

Observed: 8 candidates; true flow `flow-3` rank interval `[1, 1]`, correlation `1.0`,
lag `3`, overlap `125` bins, top-1 credit `1.0`, uniform-random reference `0.125`.
Input SHA-256: `9dbeba6dcd12073331f852c5c4da34bb3e064319fb223c9c4927586e778ce9aa`.
This is an intentionally correlated synthetic trace, **not measured Montana traffic**.
Constant traces produce `inconclusive`; equal candidates receive fractional credit.
No statistical significance, production attack success or security acceptance is claimed.

## Existing workspace baseline (separate from this PR's checks)

The following commands were started on the unchanged published source trees:

```sh
(cd core/Montana-Core && cargo test --workspace --release --locked --offline)
(cd core/Code && cargo test --workspace --release --locked --offline)
```

The initial reference-core run stopped with six `montana-node` unit-test failures at
socket creation: `Operation not permitted (os error 1)`. That is an execution-environment
restriction, not evidence of a protocol defect. A repeat with loopback sockets permitted
passed that unit-test target and proceeded to the longer integration proofs.

The two partial runs above were repeated in full on the project's isolated core test server
(2026-10-23, Linux x86_64, 4 cores, Rust 1.92.0, OpenSSL 3.5 under `/opt/ossl35`), on the core folder of
public `main` `f2c2b6fdcce50e4fe27e2a2ebbf22368f627e4a1`, folder tree `4ce3d6705224c8c99db0db1710a70bbde3d04361`
(the `core` row of `RELEASES.md` at that commit; historical, marked 2026-10-27 UTC: the row names another tree since). Each workspace ran as
`cargo test --workspace --release --locked --jobs 4 --no-fail-fast` inside its own network namespace
(`unshare -n`, loopback up), so no test socket was reachable from outside.

| Workspace | Test targets completed | Passed | Failed | Ignored | Exit |
|---|---|---|---|---|---|
| `core/Code` | 117 | 1422 | 0 | 1 | 0 |
| `core/Montana-Core` | 80 | 601 | 0 | 1 | 101 |

The exit 101 of `core/Montana-Core` comes from two integration targets that did not finish:
`montana-node --test two_hosts_live_a_window` and `montana-node --test three_machines_live_a_window`.
Both were stopped by SIGTERM; for `two_hosts_live_a_window` the operator's log records about twenty minutes
elapsed with its CPU time no longer growing (waiting on a futex). Neither reported a failed assertion. Every other target of both workspaces completed
with zero failures. These two live-window proofs are therefore **not** passed by this record; their hang is an
open finding of the reference core, not of this contribution. Historical (marked 2026-10-27 UTC): the ring of the core on `4451b21`, whose tree holds both tests, ran every test binary of the workspace, all exit 0 (`Audit/Protocol-13/01-WINDOW-PROOF.md:57`); both tests changed since (`3e8b6e5`, `c1095eb`), and a run on several hosts is still item 13.

The `Audit readiness tools` GitHub workflow is included after the repository owner's
OAuth authorization was refreshed with `workflow` scope. It runs the Python checks,
committed inventory and four Rust probes. Its hosted outcome must be read from the
workflow run for the exact PR revision; inclusion alone is not a passing result.

Application builds, binary reproduction, actual node services, real capture collection,
side-channel certification, engagement/funding and independent remediation review were not
performed by this contribution.
