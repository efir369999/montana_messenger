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
