# Item 4: K0c/K0d and author decision 233, partial specification

Refs #15. Existing PR branch; predecessor `6de0f4b6bb4749909cd566f5f8dd3eeca9e23987`.

Decision sources: [K0c](https://github.com/efir369999/montana_messenger/pull/52#issuecomment-6420072906),
[K0d, records 224/231 and link 8935](https://github.com/efir369999/montana_messenger/pull/52#issuecomment-6420399577),
[record 233 and link 8951](https://github.com/efir369999/montana_messenger/pull/52#issuecomment-6420491388).
Decision 212's self-transfer is superseded. The author's amount, continuity-plus-lock gate
and burning decision are settled. The cryptographic construction and its activation are not.

**Constitution is a separate commit: `4221b83`.** Its I-6, I-12 and monetary-layer amendment
quotes the chairman's translation and cites the author's records. It is proposed wording
for line review, not a declaration that this PR has been accepted or deployed.

## Follow-up to the chairman's line review
+
+[Review of 4221b83](https://github.com/efir369999/montana_messenger/pull/52#issuecomment-6422507154):
+the proposal entries in the iOS build CHANGELOG are removed from the branch diff. I-6 keeps
+"Forbidden without exception" with the one explicit voluntary-lock exception. The monetary
+clause follows the author's [17:08 UTC word](https://github.com/efir369999/montana_messenger/issues/14#issuecomment-6422452584):
+one coin per lived second, not a shared fixed mint. The chairman owns A1/A2 code and amount
+binding; this branch changes documentation only. Canon's node_lock row remains decided;
+tau-2 times the corrected window credit must equal that row. Source line anchors below
+describe 0dcbd81; headings are stable through this follow-up. The Value equation still
+subtracts each distinct slashed lock and includes outstanding locked value.
+
+## Current source map and result

| Task | Source in this revision | Result |
|---|---|---|
| Decided amount | `core/docs/Montana Canon.md:4657` | One decided Decree row; denomination in the candidacy proposal. No runtime clock conversion. |
| Stand-alone continuity/F-1 input | `core/docs/Montana Canon.md:5245-5268` | Explicit offsets, verifier-owned period/root, machine commitment and suite binding; no self-transfer fields. |
| Pressure context | `core/docs/Montana Canon.md:5270-5277` | Verifier-owned K0c input retained; record 233 fixes tau-2 and supersedes the proposed pressure extension for the node gate. |
| Lock candidacy bytes | `core/docs/Montana Canon.md:5279-5314` | Input/change/lock fields and both layouts specified; fixed proof length and lock construction remain uncomputed. |
| Release and slash | `core/docs/Montana Canon.md:5337-5365` | Exact existing challenge boundary, one successor-window close; mutual exclusion, no double burn, anonymous revocation and withdrawal duties named. Release/slash byte layouts await the missing cryptographic relation. |
| Gate and client debt | `core/docs/Montana Consensus.md:936-959` | Continuity plus lock; no additional Global/pi/Fabric node gate. Client is unchanged and owed. |
| Conservation | `core/docs/Montana Value.md:196-208` | Lock/release conserve supply; each distinct slash burns the Decree amount; outstanding locks enter the supply equation. |

The continuity numbers come from base `4c6430a6` Canon:4649,4655-4657: 14 segments of
1 440 windows give tau-2. The public-input four-byte period comes from
`core/Montana-Core/crates/mt-state/src/layout.rs:1011` at that base; integer/digest widths
come from Canon:5197-5206, fixed input/output counts from Canon:4817-4821. The release
boundary is Consensus:772-773 at that base, not a newly chosen waiting constant.

Client facts at that base, `apps/messenger/ios/Code/Montana/MontanaSettings.swift`:
line 277 says Global is the lowest of three levels; line 279 gives level n at 2^n seconds;
the author's chosen amount of seconds therefore reaches level 20. Line 281's pi-prefix
rule gives level 6 because 314 159 <= the decided balance < 3 141 592. Line 283 still
opens one's own node at level 8; line 281 says pi falls with balance, so locking spendable
funds can reduce that display. `apps/messenger/ios/FABRIC-OF-TIME.md:362` supplies the
network-verification limitation. None of these client displays is an additional node gate
under record 233. Removing that client threshold is owed outside this PR, not delivered.

## Concrete unfinished construction

1. **Evidence to lock and anonymous revocation.** Current CNS-10 evidence is a pair under
   a one-window part-nullifier. Neither it nor the existing candidacy proves which persistent
   lock must burn or which future parts must be excluded. Publishing a stable identifier
   across honest windows would defeat the privacy requirement. The lock commitment alone
   cannot prove this relation. A noncooperating offender must not prevent slash/exclusion.
   The missing relation, commitment/domain encoding, lock state commitment, lifecycle card
   and release/slash public inputs remain OPEN. This is why K0d is reported partial.
2. **Continuity construction.** Record 233 fixes the base tau-2 period. Canon, Consensus
   and Identity explicitly distinguish it from the pre-transition pressure rule. The full
   shifted/masked continuity gadget remains unimplemented; a fixed public period alone
   does not prove the record lived it.
3. **Circuit cost and privacy.** SHA-256/HMAC/HKDF and full continuity gadgets remain absent
   from the cited K0b registry. The old self-transfer skeleton is not a lock/exclusion cost
   estimate. Funding ownership, lock release and sanction wiring need a joint artifact
   budget and a linkability analysis. No frozen hash, proof length or proof run is claimed.

## Separate Critic pass: all 21 criteria

This is implementing-session self-review, not an independent external audit.

| Criterion | Result and remaining obligation |
|---|---|
| 1. Accelerate one's own | Lock cannot circulate while outstanding; prove every consumption path excludes ordinary spending. |
| 2. Delay another | F-1 and suite transplant must fail at the proof verifier; native checks alone are insufficient. |
| 3. Punish without evidence | Only proven violation; existing signed contradicting pairs qualify. Silence, timeout and malformed deposits do not. Evidence-to-lock relation OPEN. |
| 4. Subjective seed | No seed change; verifier roots and period need canonical authenticated state. |
| 5. Expiry and slot | Pending expiry does not refund a still-selectable candidate; explicit withdrawal/release prevents trapped value and double use. |
| 6. Hardware/precomputation | Full gadget budget absent; no commodity-device feasibility claim. |
| 7. Field necessity | Note roots/nullifiers fund a lock; commitment associates it with the candidate; period/suite/machine bind the statement. No owner or record identifier added. |
| 8. Cross-section | Constitutional exception, Consensus gate and Value equation aligned; fixed-period override and sanction linkage gap are explicit. |
| 9. Scope | Documentation only, existing branch, constitutional amendment separate. No client or Rust edits. |
| 10. Temporal evolution | Release follows successor-window close, not a timer; canonical evidence precedes refund eligibility; repeated evidence cannot double burn. |
| 11. Concentration | Fixed capital can exclude cash-poor eligible keys; decided policy does not establish decentralization or prevent rented capital. |
| 12. New-class review | Slash association must protect all honest windows, not only hide one funding input. Public lock/candidate association remains a review surface. |
| 13. Invariants | Adjacent candidacy invariants name checks and state effects. Full release/slash statement is OPEN, not hidden behind an opaque digest. |
| 14. Lifecycle | Lock state, root and storage card unresolved; no unbounded registry claimed safe. Existing nullifier set owns spentness. |
| 15. Sabotage | Cheap parsing/spentness checks first; unsolicited junk cannot burn an honest lock. Proof-cost DoS unmeasured. |
| 16. Completeness | Prior decision-212 text retained below as historical evidence; active Canon/Consensus/Registry point to the replacement. Old frozen vectors are pre-transition. |
| 17. Single source | Canon Decree owns the amount; other texts refer to node_lock. Canon owns layout offsets and denomination. |
| 18. Whole class | Required tests cover all funding conflicts, release/slash permutations, repeats, restart and anonymous exclusion after slash. |
| 19. Scarcity | Constitution expressly admits the one monetary exception; it is not relabeled time. |
| 20. Minimality | Existing note slots, change and spent set reused; one lock. New persistent machinery must justify its full lifecycle before acceptance. |
| 21. Equilibrium | Simultaneous locks immobilize value; voluntary exit and challenge delay constrain reuse. Loans, wealth concentration and bootstrap availability remain unproven. Burning supplies no reporter reward. |

Required later tests: honest lock, below/exact/above funding with correct change; forged
amount/filler/ownership; F-1 and suite mutation; spent inputs and duplicate operator right;
release before/at/after last challenge boundary; slash before release and release before
late evidence; repeated evidence, same-window ordering and restart; candidate expiry and
withdrawal; noncooperating offender; exclusion from every later cement without linking
honest windows. Every refusal compares full state. Each mutation must turn its regression
red. None of these tests was executed here.

Validation for this documentation pass: `git diff --check`, exit 0. Byte offsets reviewed
field by field against existing widths. No Cargo, build, test, proof, device or server run.
All source-map paths are in the existing branch. K0 is partial and K1-K4 remain stopped.

GPT agent [01a1792c], model id not visible to the agent

---

## Historical decision-212/K0b report, superseded as the active proposal

The following is retained evidence of the earlier proposal and its source inventory.
Its present-tense status, self-transfer rules, numerical threshold, estimates and review
conclusions refer only to the predecessor. They are not the current K0d specification.

# Item 4: decision-212 self-transfer, K0 review proposal

Base: `4c6430a6feb54527606e3e93023ec71219c2c352`, 2026-10-26 UTC.
Paths and line numbers in the source table refer to this immutable base, not the changed
line numbers of the proposal. Existing PR #52 continues on its original branch.

The [chairman's task](https://github.com/efir369999/montana_messenger/pull/52#issuecomment-6417336650)
records the author's decision: pi is a network-proven transfer to self; Fabric remains a
client gate. This supersedes the choice that the earlier K0 report left open. This report
is an implementing-session specification review, not an independent external audit.

**Status: proposal published; K0 is not closed.** Canon, "The candidacy self-transfer
proposal", is the sole proposed layout and arithmetic definition. Consensus holds the
behavioral limit and observable disclosure. Registry CNS-28 through CNS-30 name the new
checks. AUDIT.md keeps the missing implementation and the review gates open. No Rust,
frozen vector, accepted artifact identifier, release row or deployment changes here.

## Source evidence

| Source at the base | What was read and what it supports |
|---|---|
| `core/docs/Montana Canon.md:5191-5218` | Current candidacy fields, its one-time right, verifier-owned record root, unbound machine commitment and intended continuity. |
| `core/docs/Montana Canon.md:1787-1793,1823-1839` | The master-seed width and independent operator, note and nullifier-key branches. Client derivation from a common seed is not a circuit equality. |
| `core/docs/Montana Canon.md:3033-3062` | Note commitment, amount encoding, two-squeeze ownership/redemption relation, position-dependent nullifier and independent payment-key hash. |
| `core/docs/Montana Canon.md:4817-4821` | Existing fixed input/output counts and note-tree depth reused by the proposal. No new configurable slot count. |
| `core/docs/Montana Canon.md:1418-1432,1484-1522,1580-1628` | The common geometry, proof-length derivation and why changing geometry changes dependent layouts. |
| `core/docs/Montana Value.md:147-173` | Real/filler branch coherence, zero filler value, conservation, membership horizon, current spentness checks and application to existing trees. |
| `core/docs/Montana Identity.md:88-111`; `core/docs/Montana Consensus.md:907-911`; `core/docs/Montana Canon.md:4655-4665` | Network continuity is a shifted segment/share test with pressure-dependent period, not the client's attended seconds. |
| `core/docs/Montana Consensus.md:359-390` | Machine and person secrets are separate. The proposed note/right origin must not equate either to the machine secret. |
| `core/Montana-Core/crates/mt-proof/src/circuit/admission.rs:59-90,137-170,218-326` | Actual placement count; current record/right/naming boundaries and witness; current public input. There is no note witness or pressure-period input in this circuit. |
| `core/Montana-Core/crates/mt-proof/src/circuit/redemption.rs:60-109`; `circuit/frame.rs:155-157,194-207`; `circuit/sponge.rs:38-40` (same proof crate) | Source formulas for the note/redemption and creation skeleton, not a new measured circuit. |
| `core/Montana-Core/crates/mt-proof/src/circuit/value.rs:1-36` | Existing amount-range restriction prevents a field wrap becoming inflation. The proposal must also constrain the threshold difference. |
| `core/Montana-Core/crates/mt-proof/src/params.rs:29-42,62-68` | Row cost, free-row reserve, width bound and common height. Unused rows alone do not establish a fitting circuit. |
| `core/Montana-Core/crates/mt-derive/src/note.rs:48-73` | The actual commitment and nullifier compositions. Knowledge of a note key does not itself prove which operator branch has the same seed. |
| `core/Montana-Core/crates/montana-node/tests/admission_audit.rs:110-133` | The current F-1 test expects a lifted machine commitment to apply. No passing fix is claimed here. |
| `apps/messenger/ios/Code/Montana/MontanaSettings.swift:277-281,320` | Client Global/pi thresholds and the denomination sentence. Canon explicitly marks the new core unit bridge as proposed, rather than treating the client as a previously implemented core constraint. |
| `apps/messenger/ios/FABRIC-OF-TIME.md:362` | Per-correspondence keys cannot verify a balance or identify its public account without violating the separation. Fabric remains a client gate. |
| `core/docs/Montana Constitution.md:82-133,160-179,249-311` | Financial privacy, fungibility and time-only validator scarcity clauses that need reconciliation with the later decision. |

## What the proposed origin binding means

There is an existing formula from a common master seed to both the right branch and the
note branches. There is no such equality in the present admission description. The proposed
binding in Canon uses those formulas under a single hidden master seed and constrains every
use of the resulting branches. A witness struct with fields named as if related is insufficient.
The proposed output key and naming half are constrained to the same origin as the real inputs.

This is a proposed use of existing derivations in a new proof statement, not a claim that the
current arithmetic already supports them. Merely putting two separate proofs beside each
other, or setting the note nullifier key equal to the operator secret, would not implement it.
The machine's own secret remains separate. Neither civil identity nor mnemonic-generation
quality is claimed by that relation. Knowledge of the record's right is also not proof of
its current signing-key preimage; the proposal preserves the admission meaning of that right.

## Open gates for the chairman

1. **Origin gadget and cost.** The proposed relation needs constrained HMAC/SHA-256 branches
   and cross-gadget equality. The existing admission assembles permutation, sponge, path and
   capacity constraints; its current hash chains do not prove HKDF. Canon gives a skeleton-only
   row estimate and an explicitly conditional wire size. A fixed final proof length cannot be
   asserted until the whole replacement fits height, width, degree and free-row rules. No
   latency or RAM estimate is reported as measured.
2. **Adaptive continuity context.** K0b now proposes an exact verifier-owned period input
   and pressure snapshot in Canon, shared with both roots. Difficulty depends on the canonical
   post-snapshot pending population and living count, never announcements or a claimant's
   count. The proposal fixes strict comparison, zero-population behavior, overflow widths,
   expiry boundary and the masked continuity predicate. Authenticated replay of pending
   candidacies remains an implementation dependency: the current proposal roll contains
   frames and cement parts, and current `apply_candidacy` records only a spent right.
   Thus the contract is specified for review, but its runtime input is not established.
3. **Privacy compatibility.** The requested public output commitments stand beside a machine
   commitment in one self-transfer. An observer can group those outputs with that candidacy
   and learns the threshold predicate. This does not reveal an input leaf, exact amount,
   person or network address. It nevertheless adds observable ownership context, which cannot
   be described as zero leakage under the current stronger financial/fungibility wording.
   Canon and Consensus name the disclosure; Constitution is not silently rewritten here.
4. **Scarcity compatibility.** The later decision explicitly chooses a value threshold, while
   Constitution [I-12] says validator-role defenses use time alone. The threshold does not lock
   funds, so it cannot establish a proportional capital barrier for a fleet. Review must state
   how the later decision reconciles the invariant, without relabeling capital as time.
5. **Bootstrap and lifecycle.** The proposal uses the existing spent set, note tree and candidate
   path. Applied nullifiers persist, commitments append, a successful transfer does not depend
   on eventual selection, and refusal is atomic. The existing continuity/selection defenses
   must actually be enforced to supply the storage barrier. Cold-start access to eligible notes
   must be checked against the opening cohort; this proposal neither invents premint nor proves
   bootstrap liveness. It adds no fee, lock, expiry or new tree to hide these obligations.

The author's choice is recorded, not reversed. The chairman's
[K0 review](https://github.com/efir369999/montana_messenger/pull/52#issuecomment-6419157012)
accepted the first proposal for review and assigned K0b; the constitutional questions are
with the author and do not block preparing K0b. K1-K4 remain stopped at the cost gate.

## K0b response to the chairman

| Finding | Proposed correction and evidence |
|---|---|
| F-564-1, denomination | Canon now owns one explicit proposed Values row, shared by the note amount, emission mint and issued share. The client FAQ is context, not a previous core unit anchor; `montana-wallet/src/pay.rs:108-114` at the base copies the share without a denomination conversion. The earlier core gap is stated explicitly. |
| F-564-2, one order | The common object fields have the same order in serialization and public input. Verifier-owned roots and the period are inserted without permuting those fields. Canon owns the offsets. |
| Gate 2, pressure/period | Canon chooses the last proposal of the standing stride, post-application/selection/expiry. It defines the living and canonical pending counts, exact period rule and verifier-owned encoding, plus refusal if the authenticated pending snapshot cannot be reconstructed. That missing canonical-history path is not replaced by local state or a default. |
| F-564-3, cost first | The complete gadget registry and relevant assembled descriptions were read; exact-name searches covered the proof source tree. There is no registered SHA-256/HMAC/HKDF or complete continuity gadget. Canon gives the actual partial column counts and identifies the native helpers that do not supply constraints. Neither a final width nor growth of the common height can be justified yet. K1 remains stopped. |
| Proof-length impact | Canon distinguishes common-height consumers from separate presence/ticket height and explains why shared width changes affect both families. A larger domain also requires rechecking the proof soundness budget; no guessed length is frozen. |

Additional source anchors at the unchanged base:
`mt-proof/src/circuit.rs:11-26`, `mt-codec/src/lib.rs:570-629`,
`mt-proof/src/air.rs:628-648`, `mt-proof/src/circuit/opening.rs:12-19,97-130`,
`mt-proof/src/circuit/compare.rs:1-17,39-94`, `mt-state/src/layout.rs:1009-1023`,
`mt-proof/src/circuit/presence.rs:185-190`, `mt-proof/src/circuit/ticket.rs:222-226`,
`mt-proof/src/params.rs:88-94,135-161` (all crate paths beneath
`core/Montana-Core/crates/`). The missing gadget cost is a finding, not an estimate of zero.

K0b self-check: one denomination row; common-field order compared directly; input offsets
and pressure equality/zero-population arithmetic checked locally. No runtime or proof run.
Pressure manipulation and snapshot delay are explicit policy consequences: a larger pending
set can raise the later stride's period, but local arrival order cannot change it. The
privacy/scarcity findings stay with the author's decision record. No independent review or
completed admission proof is claimed.

## Gate -1: required failing-before / passing-after evidence

Tests below are requirements for later code, not executed tests in this document.
Every refusal must compare the full pre/post state and, for persistent application, restart.

| Attack or control | Required observation |
|---|---|
| No real notes, all filler, invented positive filler amount | Threshold fails; filler cannot contribute value at any seam. |
| Already-spent input under a still-eligible old root | Refused against the current spent set before proof work and without state change. |
| Threshold minus one base unit, exact threshold, threshold plus one | Below fails; the latter two honest self-transfers succeed. Include maximum-range and wrapped-difference forgeries. |
| Two candidacies spending the same notes in one window, under different rights | Only the first in canonical order applies; the second leaves its own operator right unspent. Repeat after restart. |
| A frame and candidacy spending the same note, in both orders | The same current set rejects the later operation; no separate candidacy spent set. |
| Duplicate note nullifiers, including collision with the operator right | Refused before verification, including fillers; no partial note or candidate insertion. |
| Foreign `node_commit` (F-1) | The captured proof fails for changed commitment bytes; the honest original still applies to unchanged state. |
| Relay swaps `suite_id` | Unsupported suite rejected at the reader; altered public-input bytes rejected by proof verification independently of that reader check. |
| A root outside the horizon, a claimant-supplied root, a wrong standing proposal | Rejected; record and note roots come from one authenticated verifier-selected proposal. |
| Note origin A with operator right B; output key C | Common-origin constraint fails, including an adversarial trace with otherwise valid branch computations and memberships. |
| Machine secret substituted for person seed or note key | Refused by the distinct derivation relations, not merely by honest-prover validation. |
| Same root, wrong window; missing first stride | Refused by context; no unanchored bootstrap exception. |
| Easier adaptive period, stale/future continuity, inflated or reserved bits | Fails the same-record, verifier-owned-period and shifted/masked-share checks. |
| Local pending announcement, expiry equality, pressure equality, zero population, period from a different stride | Only the authenticated post-snapshot population determines the period; the exact boundaries and cross-stride binding must be tested. |
| Fragmented balance requiring more positions than the format allows | No variable-length shortcut; ordinary consolidation and horizon wait are required. |
| Conserved self-transfer then ordinary transfer to another holder | Allowed after ordinary root eligibility; documents the threshold's non-locking limit. |
| Crash across operator/nullifier/note/candidate application | Full old or full new state, never a consumed right with missing returned notes. |
| Honest minimum transfer, filler and two real inputs; maximum supported amount | Valid proof and canonical round trip at exactly the artifact-derived size. |

The artifact transition must recompute the admission identifier, aggregate artifact hash,
Genesis State Hash and parameter digest. Compare all dependent lengths and new typical,
boundary and adversarial vectors. No old frozen vector is evidence for the proposed statement.

## Separate Critic pass

This pass is self-review by the implementing session. Findings remain visible rather than
being promoted to an independent audit or to a completed K0.

| Criterion | Result of the pass |
|---|---|
| 1. Accelerate one's own operations | Capital can circulate between applicants; no fleet capital bound claimed. |
| 2. Delay somebody else's | F-1/suite replay fixed only by the proposed binding; spentness races need canonical ordering and tests. |
| 3. Punish without a signature | No new sanction; invalid proof refuses the transition and spends nothing. |
| 4. Subjective seed bit | No new draw seed; verifier roots must come from authenticated canonical state. |
| 5. Expiry plus scarce slot | Existing one-time right is consumed before selection; no invented retry or expiry. Availability remains a separate obligation. |
| 6. Hardware/precomputation | New origin proof cost unknown; no hardware-neutral runtime claim. |
| 7. Field necessity | Public roots, note outputs/nullifiers and machine/suite binding have named checks; amount, account, time and branch selector stay private or absent. |
| 8. Cross-section consistency | Privacy/scarcity conflicts and the missing gadget/canonical-history dependencies are open, explicitly cross-referenced. |
| 9. Scope | Documentation only, existing PR, old vectors retained and labeled pre-transition. |
| 10. Temporal evolution | Spentness is current even when membership root is old; output eligibility follows the ordinary horizon. |
| 11. Threat concentration | One common-origin witness requires proving on the holder's device; no master seed is sent to a node. |
| 12. Re-audit new class | Threshold disclosure and output association were checked against financial privacy/fungibility, not just admission correctness. |
| 13. Invariant enumeration | Canon owns the proposed layout and adjacent refusal/application invariants; unresolved gates are named. |
| 14. State lifecycle | Existing tables grow under the existing operation; runtime continuity/storage barrier and atomic persistence remain unverified. |
| 15. Sabotage | Cheap length, suite, encoding and spentness refusal precede expensive proof work; malformed-input cost must be tested. |
| 16. Post-edit completeness | No entity or data deleted. Searches distinguish old frozen statement, implementation, historical audit evidence and proposed replacement. |
| 17. Single source | Only Canon defines candidate bytes, numeric threshold and cost arithmetic. Other files link to it. |
| 18. Whole class | Test plan covers both transplanted fields, all note-spend conflicts and adversarial mixed-origin traces. |
| 19. Time scarcity | Conflict with the money threshold remains a review gate; no capital-as-time argument. |
| 20. Minimality | Existing input/output forms, note/nullifier storage and branch derivations are reused; one group, no new lock, tree or fee. Extra common-origin constraints are necessary to exclude mixed owners. |
| 21. Equilibrium | A holder can recycle liquidity or lend it between already eligible records; a fleet still needs distinct rights and continuity. No claim that a stake remains bonded, a rental market is excluded or bootstrap is established. |

Constitution checks: existing primitive families and integer arithmetic are preserved as design
requirements ([I-1], [I-7], [I-9]); canonical ordering/context and the established draw remain
requirements ([I-3], [I-8]). [I-2]/[I-6]/[I-12] have the conflicts above. [I-4] bootstrap,
[I-5] proof resources and [I-11] enforced lifecycle remain unverified. [I-10] has the single
proposed numerical source. [I-13]/[I-14] gain no fingerprint or binary-release claim.
[I-15] receives no system clock. [I-16]/[I-17] receive no anonymity or graph-closure claim
from a larger hidden-witness proof; the added public association remains under review.

Validation: `git diff --check` passes. A local integer calculation checked the proposed
byte offsets, conditional size and skeleton-only row sum directly from the cited formulas.
No Cargo, Rust build, proof, device test, server run or frozen-vector computation was run for
this K0. The tests above remain requirements, not results. Review is requested before K1-K4.

-- GPT agent [01a17795], gpt-6, contributor of the Montana council
