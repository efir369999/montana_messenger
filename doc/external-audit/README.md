# Issue #2: external audit commissioning package

This is a contributor proposal for [issue #2](https://github.com/efir369999/montana_messenger/issues/2),
prepared with OpenAI Codex from the public repository. It is not an independent professional audit,
an auditor engagement, or evidence of production GPA resistance. The [source review](REVIEW.md)
checks the proposal's premises against a fixed snapshot and executable characterization probes.

**Recommendation:** commission a bounded source/design assessment now. Do not commission a
production GPA-resilience sign-off until the complete deployed path is supplied. A fixed snapshot
is reviewable even while findings remain open; that does not make the protocol production-ready.
The existing [audit catalogue](../../AUDIT.md) and
[13-item register](../../Audit/Protocol-13/README.md) remain the authorities for security closure.

## Maintainer decisions and issue closure

| Issue #2 action | Deliverable in this proposal | Remaining accountable decision |
|---|---|---|
| Decide whether the code can be audited | Fixed public snapshot, checked source inventory, explicit boundaries and four executable premise probes | Maintainer accepts the snapshot and source-assessment scope; auditor accepts the supplied inputs |
| Establish transparent funding | Funding and procurement record below | Maintainer chooses a real funding vehicle, publishes its verified link, budget and spending authority; or explicitly records a no-fundraising decision and another funding source |
| Provide deployment/topology instructions | Offline reproduction below; isolated lab contract and capture protocol in [LAB.md](LAB.md) | Supply the missing server sources/configuration and exact launch commands before claiming a runnable production-path lab |

**This PR is mergeable preparation, not automatic completion of issue #2.** Use `Refs #2`,
not an automatic closing keyword. Under [CONTRIBUTING.md](../../CONTRIBUTING.md), the chairman
imports an accepted contribution into the project's source of publication and credits its next
published build; a direct merge into this snapshot repository is not the documented intake road.
Keep this directory under `doc/`, outside the generated `Audit/` catalogue.

The maintainer can close #2 **as a planning proposal** only after recording disposition of all
three rows above and linking successor work with named owners for every deferred requirement.
Closing it **as a completed third-party audit** additionally requires the named independent
reviewer's report, scope/commit, methodology, findings, and remediation retest. Do not equate
either administrative closure with universal or absolute anonymity. Until those decisions exist,
leave the issue open. Nothing in this package changes the 13 acceptance statuses.

## Reproduce without access to private infrastructure

Requirements: Git, Python 3.9+, Rust 1.92.0, a C compiler and Perl for the vendored OpenSSL.
All commands below run from the repository root. The snapshot tool reads committed Git objects;
it deliberately excludes local edits and never runs code from the selected revision.

```sh
python3 -m unittest discover -s doc/external-audit/tests -v
python3 doc/external-audit/snapshot.py --revision e558daace1ef32283167867cfa2cf8db883d48fe > /tmp/montana-audit-snapshot.json
rustup run 1.92.0 cargo test --release --locked --manifest-path doc/external-audit/probes/Cargo.toml
python3 doc/external-audit/traffic.py --demo > /tmp/montana-audit-positive-control.json
python3 doc/external-audit/traffic.py /tmp/montana-audit-positive-control.json --max-lag 3
```

After fetching the locked Rust dependencies once, `sh doc/external-audit/check.sh` runs the
Python tests, current committed-source inventory and Rust probes together, offline.

The first dependency fetch requires network access. Add `--offline` to Cargo only when its
locked dependencies are cached. The harness has its own committed lockfile, seeded from the
client core's lockfile to retain its exact dependency versions (including a yanked transitive
`spin 0.9.8`); it does not silently upgrade the code under review. Dependency advisory review is
still part of the professional audit. `publish = false` prevents publishing the harness as a crate.

A successful source inventory means `RELEASES.md` agrees with all three committed folder trees.
It also pins the separate Protocol-13 candidate source and hashes its and both production-core
lockfiles. Missing/duplicate rows, missing objects, or mismatched trees produce exit 2 and no JSON.
Private source labels are recorded as unverified; public tree identity does not establish binary
provenance, source stability, operational behavior or security. Preserve the exact public commit
and the PR commit containing these tools alongside the output.

A successful Rust probe means the described limitation/control was reproduced. These are
**characterization tests, not privacy acceptance gates**: a later protocol improvement can make
them fail and requires reviewing their interpretation. The first test distinguishes successful
authentication from length hiding; the second shows that padding buckets have different widths;
the last two distinguish reusable queue identifiers from consumed fetch nonces. They execute the
real `core/Code` libraries without modifying any published core/application tree.

The traffic demo is synthetic and deliberately easy to correlate. It checks the instrument,
not Montana's network. No traffic is captured, no server is started, and no real user data is used.
A flat-flow negative control must be inconclusive; tests also cover ties, reverse lag, malformed
counts, tiny overlaps and missing candidates. See [LAB.md](LAB.md) before interpreting a real run.

For the complete existing core baseline, follow the repository's build road:

```sh
(cd core/Montana-Core && cargo test --workspace --release --locked)
(cd core/Code && cargo test --workspace --release --locked)
```

Loopback sockets must be allowed. The reference suite's OpenSSL differential test needs an
OpenSSL 3.5+ executable on `PATH`; system LibreSSL is not a substitute. App builds and physical
phone experiments are separate acceptance steps; the commands above do not perform them.
See [RESULTS.md](RESULTS.md) for what was actually run, including failures and exclusions.

## Statement of work to send for quotations

Send the same snapshot manifest and scope to the firms suggested in #2; their mention in that
issue is not an endorsement, acceptance or quote. This contribution does not contact them.
Require the proposal to name reviewers, independence/conflicts, relevant protocol expertise,
estimated person-days by work package, price/currency/tax, prerequisites, schedule, report
publication terms, embargo process and included remediation/retest rounds.

| Work package | Inputs and required output |
|---|---|
| A: design and reachability | Normative spec, both core generations, app call sites, dependency versions; claim-to-code matrix identifying the actual deployed path and unused library constructions |
| B: cryptography and implementation | KEM/signature transcript and peer authentication, key/nonce lifecycle, domain separation, hop binding, state persistence, parser/fuzz/sanitizer and side-channel review; reproducible findings and proposed fixes |
| C: metadata and traffic | All node-service sources plus configurations and [lab contract](LAB.md); passive correlation/intersection results, distinct active-adversary experiments, measured overhead and availability |
| D: remediation and release binding | Exact fixed revisions, regression and adversarial retests, unresolved findings, source-to-binary comparison or an explicit provenance limitation |

Do not substitute a library two-hop test for C, or a primitive known-answer test for B. A timing
microbenchmark of an erasure routine concerns local computation; it does not measure traffic
correlation between network links. Go's Xray VPN engine is a dependency with a separate boundary,
not evidence that the messenger's routing is implemented or protected by Go.

## Funding/procurement record (pending maintainer approval)

Record these facts in the issue or a linked decision before accepting donations or signing work:

- Decision date, accountable maintainer and chosen funding source/vehicle; verified official URL
  and beneficiary/controller. No donation address is supplied by this proposal.
- Comparable written quotations, selected scope and exclusions, selection reason, reviewer
  independence/conflicts, budget/currency, contingency and retest allowance.
- Who can authorize payment; public receipts or redacted invoices and spending ledger; disclosure
  cadence, surplus/refund policy, cancellation and shortfall handling.
- Scope-freeze commit, audit start/delivery dates, report publication and disclosure terms.
- A change-control rule: record subsequent commits, triage security-impacting changes, agree
  incremental review with the auditor, and bind the final report to its actual reviewed revision.

These are decisions for the maintainer and auditor, not fictional completed checkboxes. Track
funding approval, scope freeze, server-source delivery, lab reproduction, external report and
retest as separate owned milestones. A quote or donation is not evidence of a security property.

## Agent attribution

[agent-attribution.json](agent-attribution.json) exports one local agent-chain entry,
record 5538, written in English by the chairman of the Montana council (LLM Agent No. 329).
It names the contributor's own entry, record 4704 of LLM Agent No. 277 (OpenAI Codex), by its
SHA-256 `635b34272607d7cf7c5db3af2bb53248a261f508c211fe42f97144dcca077c39`, and binds it to
review-package commit `9da5572bf918bd30077eae33e5499722674cdee2`, which precedes the commit
adding this export and CI. The entry reports 30 focused checks and 0/13 closed Protocol-13 requirements (historical, the count of 2026-10-23; 4 of 13 are closed on 2026-10-27, `core/Montana-Core/PROTOCOL-13.json`).
Record 4704 carries non-English text and is not exported; its digest is the
reference. The `prev` field links record 5538 to the preceding private chain entry, and its
`time` field is Moscow time (UTC+3).

The record digest is SHA-256 over the UTF-8 encoding of Python
`json.dumps(body, ensure_ascii=False, sort_keys=True)`, with `hash` excluded and default
separators retained. This verifies the exported entry's integrity. It is named attribution
in a hash chain, not an asymmetric digital signature, authenticated proof of the agent's
identity or an independently witnessed timestamp. The full private chain and credentials
are not exported. A verifier can recompute the digest with:

```sh
python3 - <<'PYVERIFY'
import hashlib, json
from pathlib import Path
record = json.loads(Path('doc/external-audit/agent-attribution.json').read_text())
expected = record.pop('hash')
actual = hashlib.sha256(json.dumps(record, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
assert actual == expected, (actual, expected)
print(actual)
PYVERIFY
```
