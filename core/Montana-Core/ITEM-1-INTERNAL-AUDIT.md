# Internal audit of the complete window proof

Date: 2026-10-14. Session: 38. Reviewer: Codex, acting first as Architect 6.2.8
and then as Critic 5.1.3. This is internal review by the implementing session.

**Verdict of session 42 (2026-10-16): item 1 is closed under the relation of `WINDOW-RELATION.md`
with the author's ruling of 2026-10-16 on [I-12] — the standing weighs in the close through ballots
that prove a count of votes and disclose no weight — through the node's own verifier, in the small.**
The question session 41 left open is answered and built: a window closes on the count of distinct
machines and, where the standing is wide enough to be sampled, on the votes of verified ballots; the
matrix below carries the rows of the votes. Not claimed: agreement on what a window decided where
machines left its rounds holding different things — a stage of its own, whose design gate is
`AGREEMENT.md`; and the hosts, which are item 13.

**Verdict of session 41 (2026-10-15): item 1 is closed under the count relation of
`WINDOW-RELATION.md`, through the node's own verifier and through the running node's own close, in
the small.** Every row of the acceptance matrix of that note runs through
`montana-node/src/certificate.rs`, and the running node closes every window through the same door;
a device that held nothing walks from an anchor to the head two living machines left. Two things
are not claimed. The relation weighs every admitted machine alike: whether standing weighs in the
quorum is the author's ruling on [I-12], and it stays open as a question of semantics rather than of
implementation. And nothing here ran on the hosts: that is item 13. The verdict of session 38, kept
below as written, judged the relation that left the set.

> Session 38: item 1 remains open. The candidate is not a working replacement network.
> The present change adds an adversarial node test; it does not implement a complete
> window prover, a complete window verifier, or a replacement zero-knowledge scheme.
> The author authorized an incompatible redesign and a new network. That authorization
> is not implementation evidence, a new Genesis, or a release approval certificate.

## The relation of 2026-10-15, and what it does to the rows below

Session 39 established that the relation the rows below audit has no prover — the quorum was an
inequality over a sum of hidden commitments whose opening nobody holds — and replaced it under the
author's authorization of an incompatible redesign (`WINDOW-RELATION.md`). The weight, the fold, the
arithmetic step and the proof of a window carried apart left the set and the tree; the cement is the
set of part-nullifiers with its aggregate and count, the close is a count against the count of the
electorate of `W - 2`, the ticket is proven in the proposal by a description of its own, and the
certificate of a window is its heavy attestations. The rows below therefore read in two ways:

- **closed with the weight they were about**, because the quantity no longer exists and nothing
  weighs in the quorum: W03 (signed weight), W04 (the short opening of a sum), W05 (the quorum
  helper now compares counts every verifier holds — `a_window_closes.rs`, `window_cement_audit.rs`),
  W09 (resets and discharge), W10 (the lifetime bound of the accumulation), W12 (the weight mask),
  W13 (the normative descriptions now state one relation, and the gate holds them), W15 (two real
  machines gathering one window in two orders carry one beacon: `window_cement_audit.rs`);
- **transformed into the work of stage four, and closed by it on 2026-10-15** (session 41): W01
  (the ticket description proves the draw, the membership and the key digest, and
  `verify_proposal` and `verify_successor` judge a proposal by it — `certificate_matrix.rs`), W06
  (the six roots of state defined in Canon, "The roots of state", owned by `State::roots`, recomputed
  by every machine before it takes a proposal — `the_roots_of_state.rs` against a real frame, the
  matrix against a moved root and a moved count), W07 (the ticket verified against the electorate
  root and the aggregate of `W - 2` and the threshold from state; a key another machine's ticket
  names and an aggregate of another window refused — the matrix and the walk), W08 (history is the
  walk of certificates from an anchor: `certificate::walk` and `pulse::join`, the electorate of
  `W - 2` and not of `W - 1` accepting, a proposal awaiting its certificate not final, a forged
  anchor refused — `a_walk_from_an_anchor.rs`, `a_device_joins_the_running_chain.rs`), W14 (the
  acceptance matrix of `WINDOW-RELATION.md`, section 4, through that entry point and through the
  running node's close).

W02 closed on 2026-10-15 by the hiding construction of the scheme. The acceptance ledger and the
matrix below are the ones of the retired relation and are kept as the record of what was found;
the matrix of the relation that stands is section 4 of `WINDOW-RELATION.md`, and every row of it is
open until the entry point exists and runs it.

## Scope and source

The target is the new native network in `Montana-Core`. The preceding `Code`
generation and the old running cohort are test work, not the target architecture.
The base revision is `efcc7fca717a57c4b3d42cdd109936d0e9f2d873`, descended from
`3392f6628613c7ce5fec1775a3592c9035c8e4ec`. Earlier changes remain intact.

The source paths and lines below refer to that base; the new test is identified
separately. Read together with [WINDOW-STATEMENT.md](WINDOW-STATEMENT.md),
[AUDIT.md](AUDIT.md), and the recorded session 37 [receipt](SESSION-37.json).
Earlier receipts describe earlier executions. They are not fresh executions by
this session and do not certify every test in the workspace.

## Verified session 38 evidence

The [machine-readable receipt](SESSION-38.json) retains failed attempts and the
final run. The final snapshot is `session38-window-v4`, archive SHA-256
`0a4a31fd973e328c43a733016e5c32553df784420a3f506954d9ed1b73daa38d`.
All 208 supplied source files matched their manifest before and after execution
on Linux x86-64, Rust 1.92.0 and OpenSSL 3.5.4. The final test was run in a separate
network namespace with loopback enabled; existing services were not changed.

| Check | Observed result |
|---|---|
| Workspace formatting | pass |
| Workspace Clippy, all targets, warnings denied | pass |
| Final cement adversarial test | open defect reproduced; 45.52 seconds excluding compilation |
| Conformance package | 74 tests pass |
| Workspace release build | pass |

These checks are not a whole-workspace test sweep. No complete window proof,
canonical finality certificate, new Genesis or deployed replacement network was
produced. The final test is the only implementation-file change made in session
38; the earlier candidate repairs have their own revisions and receipts.

The accompanying public audit fixture reconstructs 206 identical source files
from the published commit and a patch. Two private session reports are excluded
from publication; neither is a compilation input. The new audit and receipt were
written after the test snapshot and do not change its compilation inputs.

## Acceptance ledger

The statuses describe the complete relation, not the existence of a helper with
a similar name. `partial` means a relevant component exists but does not establish
the obligation; `absent` means the integrated required relation is absent in the
reviewed native acceptance path. No required row is left unmapped.

| Obligation | Status | Implementation evidence | Required closure |
|---|---|---|---|
| Authenticated Genesis, suite, parent, height and input roots | full, 2026-10-15: the predecessor is the proposal of the window before or, for the first window, the Genesis State Hash; suite, height, version and roots judged at the one door — superseding: partial | `mt-store` binds a directory to Genesis; `window::verify_step` takes arithmetic bytes, not an authenticated predecessor | A verifier derives context from a checked parent and refuses candidate-selected trust anchors |
| Unique participants and permitted hidden weights | full for participants, 2026-10-15: each part once, a second key under one part refused, the count against the electorate of `W - 2`; the weight left the relation, and whether it returns is the author's ruling — superseding: partial | Presence proves membership and part derivation; `presence::public_of` omits weight and its origin | Prove that each contribution opens the permitted record in the same authenticated parent state |
| Fresh commitment to the exact integer sum | retired with the weight, 2026-10-15: the count of the cement is public and recomputed — superseding: absent | `mt-pulse::fold` adds ring commitments; `FoldNode` has a layout | Prove child authentication, integer carries, fresh openings and bounded randomness at every node |
| Parent quorum and a separate living count | full, 2026-10-15: the final beacon's count against the quorum of the electorate of `W - 2`; the living are its count — superseding: partial | `close::quorum_reached` computes a bounded integer inequality | Bind numerator, denominator and living count to the preceding obligations inside the accepted relation |
| Canonical operations and output roots | full for what the node applies, 2026-10-15: Canon, "The roots of state", and `State::roots`; the payer's own frame applying at once is item 7's — superseding: absent | Proposal serializes six roots; the window AIR binds coefficient arithmetic | Prove every permitted operation and recompute every output root from authenticated input roots |
| Proposer ticket ownership and historical eligibility | full, 2026-10-15: the ticket proven in the proposal and verified against the electorate and the aggregate of `W - 2` — superseding: absent | `runs_the_chain` computes a local ticket; Proposal carries bytes named `ticket_proof` | Prove the admitted secret, the proposal signing key, historical aggregate and threshold in one relation |
| History from Genesis including every reset and terminal check | full under the relation, 2026-10-15: history is the walk of certificates from an anchor, resets and the terminal claim left the set with the fold — superseding: absent | `verify_step` checks one arithmetic step; `discharge` is a bit-decomposition gadget | Authenticate predecessors and every reset, then verify the terminal claim under a complete soundness argument |
| Hidden witnesses in the entire proof transcript | full, 2026-10-15 | The free block, the randomizer and the two-part composition of the scheme; the session 37 observer fails to extract | — |

The actual complete-window verifier has no accepting positive-case artifact in
this candidate. Rejecting every window would not close any of these rows.

## Findings and closure conditions

### W01 The registered window description proves arithmetic

**Open, blocks release.** `mt-proof/src/circuit/window.rs:153` builds the
description entirely from fold arithmetic, an inverse constraint and public
coefficient boundaries. `verify_step` at line 96 validates input shape,
canonical coefficients and transcript-derived challenges. It has no authenticated
state, operations, membership, quorum or ticket arguments.

An accepting arithmetic proof can therefore be genuine while providing no
evidence for a proposed window. The repair belongs in the full proving relation
and its protocol entry point. Renaming the helper or attaching a signature does
not supply the missing predicates. Closure requires the complete acceptance
matrix below through the real node entry point.

### W02 An accepted transcript discloses a permanent secret half

**Closed on 2026-10-15 by the hiding construction of the scheme** — the free block, the
randomizer and the two parts of the composition, stated in Canon, "The proof scheme", and argued in
`WINDOW-RELATION.md`, section 5. The observer below is kept and now fails to extract:
`montana-node/tests/presence_disclosure_audit.rs`. The paragraphs that follow describe the defect
as it stood.

`presence.rs:297` fills four lane columns
with the spending half. `scheme.rs:445` interpolates the columns without a
random mask. A constant polynomial evaluates to its constant at every query.

The session 37 observer receives serialized proof bytes only, after the actual
`verify_heavy` accepted them, and predicts part and credit nullifiers at five
heights. Its recorded test duration is 15.63 seconds. The server's existing
raw log was read again in session 38; the experiment was not rerun merely to
rename its owner. It does not recover a signing key or demonstrate theft.

Closure requires a complete witness-hiding construction, including out-of-domain
and FRI disclosures. Moving the lane, masking a struct field, or making one
extraction test fail does not establish zero knowledge. The relevant caution
about base-field masks and quotient disclosure is described by
[Haboeck and Kindi](https://eprint.iacr.org/2024/1037); that paper is a design
source, not an implemented repair or a theorem for this candidate.

### W03 Signed weight is not authorized weight

**Open, blocks quorum.** `montana-node/src/attest.rs:195` verifies a signature
and presence. Its public vector at line 229 has no `weight_commit`.
`presence.rs:323` encodes admitted root, key digest, part and window only.
`Cohort::branch_of` at `pulse.rs:97` authenticates a naming half and returns
the literal standing one at line 119.

The admitted owner reuses one presence proof, commits zero or `u64::MAX`, and
signs the replacement normally. Both pass the actual verifier. Session 37's
recorded reproduction took 16.65 seconds. The source and existing raw log were
checked again in this review. Closure requires an authenticated private weight
record and a proof tying the fresh commitment to that record. Adding a hash of
the chosen commitment to the transcript alone still lets its owner prove a
fresh unauthorized value.

### W04 A short opening of the running sum is not the integer sum

**Open, blocks sum soundness.** `mt-pulse/src/fold.rs:57` adds commitments in
the ring. The actual commitment admits the aggregate counterexample
`4 * (17 * 1 + 4) = 17 * 5 - 1`: four bounded weight-one inputs sum to the
bytes of a bounded weight-five opening. With parent total seven this changes
the quorum outcome. The individual commitment is not broken: the combined
honest randomness has exceeded its bound.

The separate `255 + 1` counterexample shows why adding encoded coefficients
does not implement integer carries. Both executable examples are in
`mt-suite/tests/window_weight_audit.rs`. Closure requires the fresh tree of
authenticated child-sum proofs described by Canon, including carry bounds and
odd-child rules. A new root with unchecked children does not close this finding.
The protocol must also specify how distributed parties construct those proofs.
A collector holding only public child commitments and proofs does not thereby
obtain their private openings. Collecting every participant's permanent secret
would violate the intended ownership and confidentiality requirements.

### W05 The quorum helper does not authenticate its numbers

**Open, blocks quorum.** `Pulse::closes` at `pulse.rs:484` receives the
cemented and total standings from its caller. `mt-pulse/src/close.rs` correctly
rejects zero totals, oversized subsets and multiplication overflow; its own
comment states that it is an arithmetic predicate. That predicate does not
open a commitment or authenticate its denominator.

Closure requires the fixed parent total and the exact proven participant sum
to feed the inequality inside the accepted statement. An unrelated count of
parts, even if honestly collected, cannot substitute for weighted quorum.

### W06 Output roots have no complete window transition proof

**Open, blocks state validity.** `mt-state/src/layout.rs:455` defines the
Proposal roots. `window.rs:153` never reads those fields or a canonical
operation set. Local operation verification and the presence of root fields
do not prove the entire transition represented by a proposed window.

Closure requires one ordered transition from authenticated input roots, with
all affected roots recomputed and public outputs compared. At least one honest
nonempty operation set must pass; wrong input root, wrong output root, omission,
insertion and reordering must fail where they change canonical state.

### W07 A local draw is not proof of the proposing key's right

**Open, blocks proposer entitlement.** `Pulse::runs_the_chain` at
`pulse.rs:197` computes a ticket from a local secret and aggregate. The Proposal
layout carries `runner_pubkey` and `ticket_proof`, but these fields do not
create a circuit that binds their common origin, membership and historical
threshold. The native circuit registry and the full window description were
read; they supply no such complete ticket relation.

Closure requires a proof that the permitted runner secret authorizes the
signing key and clears the threshold from the authenticated historical state.
Replaying another runner's eligibility must fail even with a valid attacker
signature. A test that only changes a signature is not that counterexample.

### W08 Arithmetic input does not authenticate predecessor history

**Open, blocks history.** `prove_step` and `verify_step` accept the caller's
incoming accumulators. The transcript fixes those bytes before drawing its
challenges, but cannot certify where the bytes came from. The interface does
not receive Genesis, a checked predecessor statement or a proof chain.

Closure requires a verifier-authenticated base and a justified recursive or
accumulated relation for every step. Replacing the incoming accumulator,
Genesis, parent, height or suite must fail without relying on the honest
producer's checks.

### W09 Decomposition does not authenticate resets or discharge

**Open, blocks history.** `mt-proof/src/circuit/discharge.rs:108` constrains
bits and reconstruction. It does not verify that a reset recommitted the
previous claim, that all resets are present, or that the final claim is rooted
in the network's Genesis. The window description does not compose those duties.

Closure requires the explicit relation between old and new commitments at
every reset and a terminal verifier for the authenticated accumulated claim.
Changed resets, omitted resets, truncated history and a forged terminal
opening must be rejected independently.

### W10 The lifetime security argument is incomplete

**Open, blocks a security claim.** Consensus states a conditional bound
`k / (q - 1)^6` and explicitly leaves its premises unproved. Six different
transcript draws alone do not establish independence under adaptive attempts,
authentication of history, or binding across recommitments. The previously
claimed comparison with `2^-138` had the wrong direction.

Closure requires an explicit theorem with the actual challenge space,
history/adversary budget, commitment assumptions, reductions and the target
of Canon. Increasing the repetition count does not establish missing premises.
[LatticeFold](https://eprint.iacr.org/2024/257) supplies its own low-norm
extraction construction; naming it does not import that theorem into this code.

### W11 Zero and claimant-selected challenges were repaired locally

**Closed at the arithmetic component, not at item 1.** Revision `3392f66`
adds the inverse constraint and checked APIs which recompute nonzero challenges
from canonical inputs. Earlier receipt evidence records 189 proof-package
tests, 72 conformance tests, Clippy and release. `mt-proof/tests/window_audit.rs`
still distinguishes the generic AIR interface from the checked step.

The required closure of W08 and W09 remains separate. A valid step over an
invented predecessor is not a valid history.

### W12 The future-public-part weight mask was repaired locally

**Closed for that extraction path, not for overall confidentiality.**
Revision `3392f66` replaces the next window's public part as a blind with an
HMAC-derived private blind over the machine secret and committed tuple.
The existing receipt records the failing baseline and passing actual-node
regression. W02 is a different channel and remains open. Neither repair proves
the origin of the weight in W03.

### W13 The normative descriptions disagree on required relations

**Open, blocks a canonical implementation target.** Canon's Confirmation
invariant requires authorized standing, whereas Consensus's presence public
vector excludes the weight commitment. Canon's fresh fold node verifies
children and recommits their integer sum; parts of Consensus describe simple
outside addition as sufficient. Consensus alternately excludes the ticket
from the window proof and requires it inside, and alternately says history
verifies prior proofs and inherits nonlinear predicates by attestation.

The relevant passages are Canon's Confirmation and fold-node invariants and
Consensus's sections on presence and the proof a window carries. These are
different requirements, not equivalent wording. The authorized redesign must
choose one sound complete relation and synchronize its normative bytes,
circuits, identifiers, parameters and new Genesis. This audit does not silently
rewrite the specification to match the incomplete implementation.

### W14 The complete acceptance matrix has not run

**Open, blocks closure.** No canonical valid complete-window proof was
produced in these receipts. Arithmetic proofs, presence proofs, signatures,
matching roots and successful builds establish their own narrower results.
There is no basis for reporting that the complete verifier rejects a foreign
ticket or accepts an honest weighted window.

Closure requires every row of the following matrix against the same pinned
complete protocol entry point. An honest-prover refusal is insufficient.

### W15 Conflicting signed weights reach different running cements

**Open, reproduced on the final session 38 test source.**
`montana-node/tests/window_cement_audit.rs` uses the real `Machine`, `Pulse`,
presence prover, signatures and `gather` path. Two machines have separate stores
in one test process; their receiving pulses use the same identity, admitted root
and parent. One receives zero then maximum weight; the other
receives maximum then zero, for the same part and same presence proof.
`Cement::add` keeps the first contribution and ignores subsequent ones.

The test confirms that both first contributions enter and the resulting
beacon cement bytes differ. It also checks that repeated participation does
not increase the count and that the quorum helper can answer for caller values
unrelated to that cement. Positive presence and wrong-root controls accompany
it. The changed-key control is correctly re-signed by the substituted key's
owner, and the changed-proof control is correctly re-signed by the original
owner. Both are refused specifically at presence-proof verification. Neither
is a test of the missing complete runner-ticket relation.

The test passed in 45.52 seconds excluding compilation. It calls `gather`
directly, not over the wire, inside an isolated network namespace. This is a
demonstrated path from W03 to disagreement about the running cement,
not a claim that a complete finality verifier accepted conflicting final
Proposals. Such a verifier remains absent. Closing W03 with a canonical weight
relation is necessary; rejecting a second conflicting arrival alone leaves
the two first-arrival choices different.

An earlier draft used two pulses of one machine and unsigned key/proof
corruption controls. Critic review caught both limitations. Its first result
is preserved in the receipt and is not presented as the final experiment.

## The acceptance matrix of the relation, through the one entry point

Section 4 of `WINDOW-RELATION.md`, run on 2026-10-15 through `montana-node/src/certificate.rs`
(`verify_certificate`, `verify_proposal`) with proposals assembled by `montana-node/src/runner.rs`,
in `montana-node/tests/certificate_matrix.rs` (259 s, debug): every attestation is the real node
prover's, every proof is verified by the real verifier, every proposal is signed by the key its
ticket names.

| Case | Required outcome | Evidence |
|---|---|---|
| a window of distinct admitted machines reaching the quorum, honest roots, owned ticket | accept | accepted: three of three, the aggregate the parts fold to, the proposal judged whole |
| count strictly below the quorum of the electorate | refuse | refused: "a cement below the quorum share of the electorate" (two of three) |
| an attestation whose presence proof stands against another electorate root | refuse | refused at the presence proof |
| an attestation whose part-nullifier repeats | counted once | four attestations, three parts, the same closure |
| an attestation signed by a key the presence proof does not name | refuse | refused at the presence proof |
| a proposal whose roots differ from the recomputed ones | refuse | refused by name, for a moved root and for a moved count of the admitted |
| a final beacon below the quorum, naming more parts than its certificate verified, or standing on another predecessor | refuse | refused by name at `decided_of` |
| two runners of one decision | one identifier | two proposals under two runner keys carry one identifier and both are accepted |
| a proposal whose cement is not the one its certificate established | refuse | refused by name |
| a proposal whose predecessor is not the final proposal of W - 1 | refuse | refused by name |
| a proposal signed by a key another machine's ticket proof names | refuse | refused at the ticket proof |
| a ticket drawn against another aggregate | refuse | refused at the ticket proof |
| a machine whose ticket does not clear | assembles nothing | `Runner::of_the_window` answers nothing |
| an observer given the serialized proofs alone | recovers no spending half | `presence_disclosure_audit.rs`; two proofs of one ticket differ byte for byte and both stand |
| the same rows through the running node's own close | accept and refuse as above | accepted, 2026-10-15: `live_doing` judges every proposal it takes with `verify_proposal` against its own roots and final beacon; two machines live four windows, take one identifier in every window and keep a chain linked from the Genesis State Hash, the head on the proposal the last cement finalized (`a_device_joins_the_running_chain.rs`); two and three machines close one window under one identifier (`two_hosts_live_a_window.rs`, `three_machines_live_a_window.rs`) |
| the roots of a real transition | recomputed | a real frame: the note root moved, the set of nullifiers the spent positions and not the rates, the tree of operations the frame of this window and empty for the next, all surviving a stop (`the_roots_of_state.rs`) |
| a proposal whose census is not the one carried from the proposal before | refuse | refused with the roots, for a moved count of a census cement |
| a final beacon carrying more votes than its certificate's ballots cast | refuse | refused by name at `decided_of` |
| an electorate whose standing is sampled, the whole count and no votes | refuse | refused: "votes below the quorum share of the committee" |
| ballots claiming votes their proofs do not carry | cast nothing | every part's ballot claiming every census under a proof of nothing is passed over, and a committee of three stays unreached |
| a ballot of the machine's own standing, through the node's path | the count its lived units drew | `a_ballot_casts_the_standing_a_machine_lived.rs`: the ballot names the part of the machine's heavy attestation, verifies at the count drawn outside the circuit, is refused one vote more and under another aggregate; a census kept under a root the electorate does not name is no unit; an electorate counted whole asks and takes no ballot |
| the circuit of a ballot | counts the lived units whose coin clears, and nothing else | `mt-proof/src/circuit/ballot.rs`, unit tests: an honest count, one vote more or less, a moved root, census window, aggregate or window refused, the comparison strict, a census not lived casting nothing, one ballot proven and verified |
| history from an anchor | the head, and no further | `a_walk_from_an_anchor.rs`: the electorate of `W - 2` accepts where the one of `W - 1` refuses; a proposal awaiting its certificate is not final; a certificate below the quorum, a ticket against the later aggregate, a loose anchor and a forged anchor are refused; a next proposal the window after does not attest is not taken, and a copy of the honest decision re-signed with a final beacon outside the certificate is refused alone and stops nothing beside the honest bytes; over the wire, `a_device_joins_the_running_chain.rs` walks to the head of two living machines and refuses a forged anchor |

The matrix of the retired relation that stood here is the record of what was found and is
superseded by this one; its rows are closed with the weight they were about or transformed as the
section at the head states.

## Critic review

From the cryptographic perspective, W02, W03, W04 and W08-W10 are independent
failures of required premises. No one-row fix, extra signature, higher
repetition count or documentation change closes their composition.

From the distributed-systems perspective, an authenticated parent must supply
one weight context to every verifier. W15 tests the current failure of that
property at the running cement. The operation/Proposal persistence transition
is the downstream responsibility of items 2 and 8; no claim of completing them
is made here.

From the audit perspective, source hashes bind experiments to bytes, not to
the truth of an unimplemented theorem. Successful reproduction of an attack
is evidence of an open defect. This session's review is not independent
external assurance, and its timechain attribution cannot substitute for it.

## Work required before a new network can be called ready

1. Specify and implement a witness-hiding proof backend with its supported
   relation, disclosure budget, degree bound and soundness analysis.
2. Define authenticated private weight state, permitted updates and how
   distributed participants supply witnesses for fresh sums without publishing
   their hidden values or entrusting their long-term secrets to a collector.
3. Implement the complete window and ticket relations and their native verifier.
4. Replace the incomplete history argument with a proved construction and
   implement its base, step, reset and terminal algorithms.
5. Generate the new identifiers and Genesis only from the completed artifacts;
   execute the complete acceptance matrix, then the separate network scenarios.

The reader should not treat this list as an implemented design. This revision
does not ship a new network. Item 1 can be declared closed only after its
implementation and evidence replace every open row above.
