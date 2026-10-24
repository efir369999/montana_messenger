# Session 35: closure evidence

Source base: `2073d6f916c8de36d36c1bbc5f3ca32ee6caabe2`, branch
`fix/session35-finality-issuance`. This is a work-in-progress candidate, not a release.
The author's thirteen requirements apply separately to legacy `Code` and native `Montana-Core`.
No native protocol deployment, independent external audit or production network closure is established here. The later public website deployment is recorded below.
The author also requested correction of the public website against the same requirements.

## Current status, 2026-10-14

**None of the thirteen acceptance criteria is closed.** The dated observations below are
partial repairs and historical runs, not a claim of complete finality, authorized issuance,
anonymous joining or an independently reviewed release.

All verification after the author's server-only instruction runs on the separate Linux host.
The public repository now contains a separate report for each item under `Audit/Protocol-13`,
published as `beb28addd5b72aff70e55a78bdf9f5cc1c69228a`. These reports are mirrored to the
author's app Audit directory. Public core source remains the earlier snapshot; candidate
repairs below must not be represented as code already present in that snapshot.

The complete-workspace attempt on snapshot v5 was stopped in the three-machine test after
approximately sixteen minutes and 3.5 GiB resident memory. Its diagnostic exposed starvation
of early historical rounds while the current round grew. Freezing each historical sweep's
end fixed that starvation, but a second run exposed early deposits discarded during presence
proof construction and the absence of relay to inbound-only holders. Two delivery tests fail
on unchanged v8. The v9 repair enters the receive round before proving and reconciles retained
cells in both directions, suppressing retries only after a peer returns the exact bytes.

Snapshot v9 archive SHA-256:
`ee6603c5979820c05c575e522bc055de127714c8a27d406fe581e2c4409d5ffb`.
Its 202-file manifest was verified before running. Formatting and whole-workspace Clippy pass;
three historical-read tests and two delivery tests pass. The three-machine count scenario
passes in 19.49 seconds, but prints three different beacon identifiers. That is not canonical
network finality. The full workspace sweep failed later: 143 proof-library tests passed and two
stale width-dependent length expectations failed. The assertions were corrected against Canon;
the subsequent v12 proof-package run passed all 189 tests. The v9 workspace sweep did not pass.

Two complete window-arithmetic counterexamples verify on the candidate: zero challenges
discard the instance, and chosen nonzero challenges cancel a fabricated predecessor. The
separate replay on the public snapshot reproduced both cases in 3977.47 seconds; all 193 source
files matched their manifest afterwards. The excess-issuance-and-onward-spend counterexample also reproduces
on the candidate. These passing tests establish open defects, not security conformance.

Consensus 4.0.2 uses the nonzero challenge space in its conditional bound. The checked arithmetic
step independently derives these challenges and the AIR enforces their inverses. Snapshot v12
passed 189 proof-package tests, 72 conformance tests, whole-workspace Clippy and release; all 205
source files matched their manifest after the run. Two commitment counterexamples and one real
node-verifier test reproduce unresolved weight-authority defects. A complete soundness argument remains
missing. The plan and operational checklist now explicitly distinguish their historical stage
claims from current acceptance. Those documentation edits follow the frozen v9 runtime snapshot.

Work is now restricted to item 1. A further regression demonstrates that the next public part
opens the prior standing commitment. Its HMAC-based private-blinding repair passed the actual-node
regression in 14.44 seconds and all 67 derivation-package tests on snapshot v17. The separate
forged-weight test still reproduces acceptance. Whole-workspace Clippy passed; the conformance
run then caught a stale audit count of 248 frozen lines instead of 249. That ledger correction
is checked separately. Neither repair constitutes a complete window proof.

The legacy decoder repair passed three selected tests and whole-workspace Clippy on its
separate 320-file snapshot. Its complete workspace tests have not run; deletion-based fixtures
were not executed under the author's no-deletion requirement.

| Item | Current result | Remaining closure evidence |
|---|---|---|
| 1. Full window statement | Reproduced conflicting 51-percent certificates with only 2-percent equivocating weight. Fixed-parent quorum and refusal of self-selected restart now specified and implemented; 38 pulse checks passed before subsequent AIR edits. | Complete quorum, weight, transition, ticket and authenticated-history relation; complete certificate verification of durable honest signing choices; valid and adversarial full proofs. |
| 2. Canonical Proposal | Reproduced endorsement of fabricated beacon cement, then bound endorsement and round advancement to a recomputed sum of verified heavy attestations. Durable predecessor choices refuse conflicting restarts and races. Count-based close and beacon identifier substitution still remain; no complete Proposal verifier exists in the running node. | Verified Proposal storage/serving and no issuance or finalized-head advancement on missing/invalid proof. |
| 3. Authorized issuance | Full proof plus node acceptance reproduced an amount above the whole window budget and its onward spend (100.14 seconds). A second AIR counterexample switched only the membership selector to filler and spent against an empty tree. | Branch binding repair passed full honest proofs and two adversarial constraint checks; authenticated entitlement binding recipient, window, amount and one-time redemption still required. |
| 4. Admission common origin | Separate record, admitted naming and operator-secret chains confirmed; empty binding lane. | Complete common-origin constraints and adversarial proofs. |
| 5. Continuity and rejoin | Earlier reserved-bit repair preserved. Recovery arithmetic now preserves the parent electorate. | Shifted gate-specific period and required share inside admission, including missing actions and rejoin. |
| 6. Clocks and test paths | Removed native round-based quorum lowering and restart authorization. Legacy timer-selected fallback remains under review. | All acceptance/bootstrapping paths and explicit isolation of test parameters. |
| 7. Legacy lottery | Prior complete reveal-set and settlement-root repairs preserved. | Historical threshold and weight context, epoch transition, missing-data retrieval and conflicting proposals. |
| 8. Atomic state | Native note append validates the whole batch; State applies notes and spent/rate nullifiers only after checks. The node persists a candidate before publishing it in memory. Checked encoding refuses count/size overflow. Exclusive temporary creation prevents stale-file/symlink reuse; secret publication has one winner under a race. Nested frame shape checks passed. | Crash-atomic proposal/proof/head/state persistence in both generations. |
| 9. First synchronization | Prior anchor/session repairs preserved. | Authenticated initial root and actual clean external synchronization. |
| 10. Observable stalls | Prior legacy local diagnostics preserved; native progress output inspected. | Networked reasons distinguishing missing quorum, data, invalid proof and absent diagnostics; no timeout authority. |
| 11. Infrastructure privacy | Read access and server-observer procedures. No infrastructure mutated. | Transport identity/privacy construction, origin exposure and request/replay resource verification. |
| 12. Audit/spec/publication | Repaired 11 pre-existing tier-one Canon findings; finality rule, AIR identifiers, proof widths, lengths, Genesis and serialization vectors updated. Five changed normative documents pass tier one. Explorer 22186ff deployed and verified against live APIs; website audit report covers the thirteen evidence boundaries. | Reconcile all remaining findings and website claims; persisted-state network binding passes 14 store tests; authenticated migration and remaining required gates; sanitized checked publication. |
| 13. Second-machine network run | On Lauterbourg x86-64 Linux, the frozen 199-file snapshot passed 172 checks: 156 regression, 10 frame, 5 state-decoder and 1 persistence. All five AIR identifiers, parameters digest and Genesis exactly match macOS ARM. This is cross-machine verification, not an independent external audit. | The network-marker follow-up passed its second server run. The later beacon/lock change needs its server run. Full distributed canonical Proposal/proof, partition/restart/rejoin and authenticated first-sync scenarios remain required. |

## Reproducible observations

- Baseline `mt-pulse/tests/finality.rs`: all three negative expectations failed.
  After the fixed-parent change, `cargo test --release -p mt-pulse` passed
  25 library, 3 finality, 1 conformance, 3 partition and 6 window tests.
- `montana-node/tests/issuance_audit.rs` currently reproduces an OPEN exploit.
  Its passing result means the oversized issue and onward spend were accepted;
  it must never be reported as conservation conformance.
- `membership_cannot_be_disabled_at_the_root_seam_alone` failed on the prior AIR:
  the verifier's constraints accepted nonzero inputs under an empty public tree.
- `mt-proof` note-tree checks: four passed, including whole-batch refusal.
- `a_wallet_pays_a_wallet`: passed after atomic append and rate-nullifier tracking.
- Tier-one spec guard: baseline and initial candidate both had the same eleven
  Canon findings; after explicit local layout invariants and named references,
  the four changed documents passed. Later edits require rechecking.

## Migration constraint

The candidate changes consensus semantics and proof constraints. It requires new
parameters, identifiers and Genesis. No fallback to retired vulnerable proofs is
allowed, and existing balances are not certified merely by changing a network ID.
No new server listener or unit has been installed. Server-side proof replay can
run without listeners; any network topology change must obey the existing observer.

## Further verification, 2026-10-14

- 156 checks passed across mt-conformance, mt-pulse, mt-state and mt-store after the AIR
  migration and exclusive-file repair. This count includes gates and does not assert complete
  monetary or consensus security. The checked State encoder passed five decoding checks and the node tests.
- The frame AIR's eight original checks passed; the additional all-seam filler attack is
  refused. All ten frame checks, including malformed witness shape, passed locally and on Linux.
- The failed-persistence regression confirms the live state is unchanged when publication fails.
  A directory-sync error after rename is reported as an uncertain commit, not a rollback.
- A stale-symlink fixture and concurrent secret creation passed. All native test scratch
  directories are now fresh and retained; no test deletes pre-existing data.
- Public Explorer commit 22186ff: 167 browser checks and actual deployed HTTPS verification
  passed, 2026-10-14T10:50:51Z. New protocol code was not deployed.
- First frozen candidate Genesis: 172584adc68b7b729d4efd49e8d8e744c73042556e7488aa2a3114f901f59c85.
  It is not an authorization to open a production network while the listed proof gaps remain.

## Separate Critic pass

Cryptographic perspective: the repaired selector schedules share two constant branch bits for
each complete redemption, and a filler cannot contribute nonzero input value. This prevents
the reproduced membership bypass. It does not authenticate a right's amount or complete the
window/admission statements. Those are blockers, not covered by the passing arithmetic tests.

Storage/operator perspective: writes use exclusive private temporary creation; identity is
published without replacing a concurrent winner. A new value plane is exposed in memory only
after complete-file publication. A directory-sync failure is reported as uncertain, retaining
the complete state already visible on disk. Atomic proposal/proof/state/head commit remains open. The later repair binds a new persisted
directory to its exact Genesis and refuses pre-existing unbound or different-network state;
14 store tests and whole-workspace Clippy pass. Authenticated migration of old balances remains open. Scratch data and backups are retained.

Public-evidence perspective: live browser verification supports the deployed website's limited
claims about signatures and checkpoint reconstruction. It does not establish independent holders,
consensus weight, privacy of public history, authorized issuance or finality. These remain named
in the page and in the thirteen-row ledger. No external independent review is claimed.

Final local checks of this candidate: whole-workspace `cargo clippy --release --workspace
--all-targets -- -D warnings` passed; 14 store tests including both network-marker refusals
passed; 14 node unit tests and 5 state-decoder tests passed before the network-marker addition;
a production-width wallet payment proof passed after it in 50.24 seconds. The three audit
measurement checks pass with 626 declared workspace tests; that declaration count is not a
claim that all 626 tests were run. No native protocol deployment or mainnet-readiness claim.

## Second server snapshot and pulse follow-up

The f858a72 snapshot of 199 files passed 165 checks on the second machine: 158 selected
regressions, five state-decoder checks, one failed-persistence check and one production-width
wallet payment proof. The complete source manifest was verified before and after the run; all
five AIR identifiers, parameter digest and Genesis agree with macOS ARM. Archive SHA-256:
`d985f63523fff9a31014ec977a078bae119dfedbb7811a020a6844456d2c261f`.
This run includes Genesis-bound storage and excludes the subsequent pulse edits.

Two further baseline failures were reproduced: a fabricated cement was signed, and a pulse
could reopen a window under a competing predecessor. Endorsement now requires reconciliation
with the sum of verified heavy attestations. The same requirement guards round advancement,
even if a valid member signs a fabricated sum. Missing leaves remain collectable and cause
an explicit waiting reason rather than authorizing a transition. A validated earlier version
is retained while late leaves extend the sum.

The predecessor choice is persisted before creating the window's signing identity, shared by
all chains and rounds, and never cleared by restart or a clock. Publication is exclusive; the
file and directory durability barriers precede success. Identical retries repeat the barrier.
Sixteen store tests and four round/delivery checks pass, including concurrent conflicting
choices, restart, malformed lock bytes, a signed fabricated beacon and late heavy evidence.
These are prerequisites, not a complete certificate or the missing canonical Proposal path.

The old two-job compiler cap was discovered during verification and removed. Compiler
parallelism now follows available CPUs. Proof tests retain sequential scheduling to bound the
memory of simultaneous full traces; processes run at ordinary priority.

## Filler regression found by the complete workspace run

The first workspace run failed when spending a received note alongside five fillers. The
new zero-filler condition had constrained the shared amount column on every filler row,
including the output decomposition that begins near the end of the preceding redemption.
A smaller honest mixed-input trace reproduced the refusal. The repair ties a reusable boolean
to the persistent branch specifically at each consumed-amount tie. A filler must contribute
zero there, while output decompositions remain valid. The reused path bit is outside tree
levels at those ties; both production and test layouts check that these schedules do not
overlap. Constraints remain quadratic, width and proof length remain unchanged.

All eleven frame checks pass, including a complete proof with one real input and five
fillers and both forged-branch refusals. The all-seam forgery now also changes the auxiliary
bit coherently; the nonzero filler amount itself still causes rejection. Full production
payment and workspace checks are being rerun. The failure and its repair are recorded rather
than presenting the earlier selected checks as a full sweep.

Canon 5.0.1 / Core 0.21.1 changes the frame AIR and therefore the network binding again:
frame `0c2b70014a8aa0834177472226118a5637c991715f54a0518bafc14e8304fa42`;
air_hash `84f6bfa8ece2661ffa8997a3cf0eebc8dddf36133850b0bba2cea918974ebb76`;
parameters `c08c1be157ff119658689a6eaa7917fcd14c93d9890c2b3483f30aef12e31ec3`;
Genesis `ee515d902ae16ad88497ff97cb0579ddcfe19af1b60a46d4598eda68c0760ec7`.
The other four AIR identifiers and object lengths are unchanged. Python independently
reproduced the parameter and Genesis hashes from the encoded bytes and six roots.
No fallback accepts a prior AIR or imports its stored balances.

## Canonical public words and reproducible proof vector

Two additional baseline regressions exposed reduction of noncanonical public hash words:
the prover certified a public word equal to the field modulus against a zero trace cell,
and resolution accepted oversized limbs. Resolution now requires two u32 limbs and a
combined word strictly below the modulus, as Canon's canonical digest encoding requires.
The prover and verifier share this rejection. This is a repair of the existing encoding
rule, not permission to accept the retired frame AIR or a proof from its network.

The scheme fixture's old digest belonged to the earlier trace-width bound. In an isolated
source copy, the original direct quotient evaluator from before commit 0ca92d4 produced
`a1c5a40fc0968ac76ab956539c469aa6aec2b5231360736e61b4304a2b9947ca`
under the current width 64, exactly matching the batched implementation. The frozen vector
is updated to that value. The historical pre-migration digest remains in its dated audit.

Verification limitation: an initial reference comparison mistakenly shared the active
workspace's target directory. It was stopped during compilation and rerun with isolated
build outputs. The final release gate must run after this repair on a frozen source tree;
intermediate workspace output is not evidence of a complete frozen-snapshot pass.

## Author's additional acceptance requirements

After the thirteen protocol requirements, the public montana_messenger repository must
carry matching code, documents and supported claims. Its remote main was read as
6303fa5fbbb5ad93e4d7dd3dcc699693fb10e002; this is a public snapshot repository, separate
from the private protocol history. Publication must preserve concurrent app updates and
use the existing sanitization and source-tree evidence procedures.

An outside operator must be able to build a node and client, authenticate network history,
participate, mint an authorized entitlement, spend it and restart from public sources.
Owner anonymity is a required protocol property across bootstrap, transport, synchronization,
minting and client use. No such complete run or anonymity proof is established here.
Permanent identifiers, source addresses, timing correlation and infrastructure exposure
remain review subjects; removing documentation of an exposure does not remove the exposure.

Every subsequent author turn and agent work step is recorded through the existing
LLM_Agent timechain writer. Earlier session-35 markers were already in that chain.
