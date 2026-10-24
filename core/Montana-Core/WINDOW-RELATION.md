# The relation of a window, and the construction that carries it

Date: 2026-10-15. Session: 39. Author of this note: the Architect (Claude), acting under the
author's words of 2026-10-14 recorded in the chain of the council: an incompatible redesign of
the proof on an isolated branch is approved, the running cohort is test work, and the target
is a working new network whose closure of item 1 an external auditor can replay.

This note is the design gate for item 1 of the audit list. It replaces the statement of the
required relation in [WINDOW-STATEMENT.md](WINDOW-STATEMENT.md) with a relation that is
provable, and it names the one decision of protocol semantics the relation rests on so that the
author can rule on it.

## 1. The finding that forces the redesign

Consensus, "The proof a window carries", states the quorum of a window as an inequality over
committed standing: the runner adds the standing commitments of the signers in the ring and the
circuit "asserts one inequality between two committed scalars: the summed standing against the
share of the total the quorum demands". Canon, "The commitment that carries standing", gives the
commitment as a lattice commitment with private randomness per machine, and Consensus, "The pulse
and the close of a window", says of the summed commitment that "no machine but the owners of what
entered can open either -- and a runner is not among them".

Both sentences are true of the construction, and together they are the finding: an inequality
over a committed scalar is proven by whoever holds its opening, the opening of a sum is the sum
of the openings, and the openings are the private randomness of distinct machines. No single
prover holds the opening of the cement. The fresh tree of Canon, "The node of the fold", moves
the same obligation to the producer of a node, who holds its own leaf's opening and never its
sibling's. The statement that the quorum "is never added up in the open" is therefore a statement
nobody can prove, under any parameters and at any population. Sessions 35--38 established the
narrower defects (W01--W15); this note establishes that the relation as specified has no prover.

What would restore a prover is exactly what the set forbids: a collector learning every signer's
standing, or a multi-party computation among signers inside one window.

## 2. The decision, and the question it leaves to the author

The relation below weighs every admitted machine alike. The quorum of a window is a count of
distinct admitted machines that attested it, against the count of machines the parent state
admits. Standing as a hidden per-machine weight leaves the quorum; the barrier of time stands
where the set already prices it -- at admission, through the continuity gate and the bounded
rate of selection events -- and the draw and the share were unweighted already (Constitution,
"[I-12]": "The draw itself is unweighted"; Consensus, "The runner's draw": "The ticket carries
no standing").

This is a change of protocol semantics at the constitutional level: the sentence of [I-12]
"what a machine accumulates weighs in the quorum, and it weighs under a commitment" ceases to
hold. The author rules on it. The alternative that keeps a hidden weight provable is a
cryptographic sortition in the manner of Algorand (Gilad et al., 2017): each machine proves in
zero knowledge how many of a window's votes its hidden standing drew, publishes that count, and
the quorum is over published vote counts. It publishes a coarse function of standing per window,
makes finality probabilistic with a stated tail, and costs a binomial sampling gadget in the
circuit. It is implementable on top of the relation below as a later change of the presence
statement and the quorum rule, so nothing built here forecloses it.

**The author's ruling, 2026-10-16, and what stands on it (session 42).** The author ruled for the
second path, in words recorded in the chain of the council: finish the work whole, including that
a machine's weight is not disclosed. Standing returns to the close as votes, and the count of
distinct machines stays beside it:

- a unit of standing is a census window — one window in every `census_interval` — whose cement
  holds the machine's part of that window; a proposal carries the root and the count of the last
  `standing_censuses` census cements (Canon 8.0.0, "The standing of an electorate, and the votes it
  draws"), so the standing of the electorate is a public sum and nobody's share of it is published;
- a unit votes in a window when a coin drawn from the machine's spending half, the census window
  and the cemented aggregate of the window two before falls below the threshold of the committee,
  `width x standing_committee / standing`; below `standing_censuses x standing_committee` units the
  threshold is nought and the electorate is counted whole, because a sample of everything would
  publish every weight;
- a ballot proves the count of votes in zero knowledge (`mt-proof/src/circuit/ballot.rs`, 63
  columns at the frame's height): the part of its window, and for every census the part, the walk of
  that census cement to its root where the machine lived it and a free walk where it did not, the
  coin and its comparison; it publishes the count and nothing else of the standing;
- a window closes on the count of distinct machines to the quorum share of the electorate and,
  where the committee is not nought, on the votes of the verified ballots of the cement's parts to
  the quorum share of the committee; the votes stand on the final beacon as evidence and in no field
  of the proposal's name, so two runners who verified ballots at different moments write one name.

What a ballot discloses is one number per machine per window: how many of its units the coins of
that window drew, a binomial sample of its standing at the rate the committee sets, under a
threshold every reader computes. Which census windows the machine lived, how many, and where it
stood in their cements, the proof hides.

## 3. The relation

**Electorate.** The electorate of window W is the set of admitted machines committed by the
proposal of window W - 2: its `admitted_root` and its `admitted_count`. For W below 2 it is the
opening cohort an operator handed the machine, which the proposal of window 0 must carry.
Membership changes take effect only through a final proposal and never move the electorate of an
open window (Consensus, "The way back").

**Attestation.** A heavy attestation of window W carries the part-nullifier of the machine for W,
its one-time answering key, a presence proof under the description of the presence whose public
input is (electorate root, key digest, part-nullifier, W), and a signature under that key over the
object including `attested` = {identifier of the beacon of its round, identifier of the proposal of
W - 1} ascending. It carries no weight.

**Cement.** The cement of window W is the set of distinct part-nullifiers whose heavy attestations
verified. Its state in a beacon is `aggregate(cement, W)` of Canon, "The draw, and the two
canonical orders" -- the sorted run of part-nullifiers under `mt-bc-aggregate` with W as context
-- beside the count of them. Every verifier recomputes both from the attestations it holds and
refuses a beacon whose state is not that pair. The cement is the value the draw of W + 2 consumes.

**Close.** Proposal W - 1 is final when `count x confirmation_quorum_den >= confirmation_quorum_num
x admitted_count(electorate of W)`, the integer form of Canon, "The close of a window, and the
slots an event offers". A machine closes the window on a beacon whose carried count reaches that
share, which it reconciled against the heavy attestations it held and which a verified attestation
answered — the final beacon (Consensus, "The beacon a window closes on", added 2026-10-15). The
final beacon's pair is the cement of W; the count of the living of W is its count and is public;
the share of W's mint is the mint divided by it.

**Proposal.** The proposal of window W carries, beside what it carries today, `admitted_count`
of the state it closes on, and `cement_aggregate` and `cement_count` of its final beacon. Its six
roots are recomputed by every machine of the window from the state the window's frames left, by
the rule of Canon, "The roots of state" (added 2026-10-15: the set of nullifiers, the table of
machines and the tree of operations were named and not defined before it); a proposal whose roots
differ is refused. Its `previous` is the identifier of the proposal of W - 1, and the first window
of a network stands on the Genesis State Hash, so round zero of every window stands on bytes that
are final. **Its identifier is taken over what the window decided** — `window` through `suite_id`,
286 bytes, with `final_beacon` moved after them — and not over the beacon a runner closed on or the
runner's key: two runners that closed on one cement publish one identifier whichever branch of the
versions of a round each closed on, so the machines of the window after attest one name without
waiting for, comparing or choosing among runners, and no runner's absence or withholding moves the
chain (Canon, "The proposal that closes a window", 7.1.0). The first live run of four windows found
the need: two machines closed window 3001 on two branches, one after nine rounds and one after one,
on one cement, and a name over the beacon parted the next window's cement between two identifiers.

**Ticket.** The runner proves in the proposal, under the description of the ticket at the height
of the presence, that: its secret's naming half stands in the electorate tree of the window;
`ticket = sponge("mt-ticket", spending half || aggregate(W - 2))` compared unsigned and
big-endian clears the draw threshold the verifier supplies from state; and the digest of
`runner_pubkey` under `mt-runner-key` is the key the proposal is signed under. Knowing another
machine's clearing ticket authorizes no key: the key digest is a public input of the proof.

**Certificate.** The certificate of proposal W - 1 is the set of heavy attestations of window W
that made it final, retained at their round points for `retained_windows` windows. A device that
was not present verifies a window exactly as the living did: every presence proof against the
electorate root it already holds, every signature, distinctness, the count against the electorate
count, and the proposal's own ticket proof and signature. No separate fixed-size proof of a window
exists in this relation; the construction that would have produced one has no prover (section 1),
and an aggregation of presence proofs by recursion is refused by the set's own measurement
(Consensus, "What the window asserts of the window before it is an accumulation...").

**History and the join.** A machine of the network verifies every window as it lives. A device
that holds nothing enters by an anchor it trusts -- the proposals of two consecutive windows
handed to it as an operator hands an acquaintance -- and walks the retained certificates from the
anchor to the head, verifying each. Trust in the anchor is explicit and is the trust a device places
in the operator who starts it; it is the same kind of trust the opening cohort already rests on.
A device away longer than `retained_windows` windows takes a fresh anchor. The claim of a join
in constant work from Genesis with no trust leaves the set with this note; what replaces it is
stated rather than implied. Each step verifies the certificate of the later proposal of the pair
against the electorate and the aggregate the earlier one carries, and judges the next proposal
whole but for its roots — its link, rules, signature, ticket and the cement of its final beacon, a
beacon of the certificate linked by hash to round zero and from there to the predecessor. The roots
of a proposal are attested by the certificate that makes it final, whose every member recomputed
them. **The head is the newest proposal whose certificate verified**; a proposal awaiting its
certificate is not final, and nothing is taken against its roots. The set said before 2026-10-15
that the next proposal is final once its ticket clears, which would have let a device take state
against roots no quorum attested; Consensus 5.1.0 corrects it.

**Hiding.** The proof scheme hides its witness: constraints are enforced on the live rows of a
trace and the last `proof_free_rows` rows of every column are drawn uniformly at random by the
prover; a randomizer column of uniform values enters the batch of the deep composition; the
composition polynomial is carried in two parts because its degree exceeds the height by the free
rows. The construction is the one of ethSTARK (StarkWare, 2021) with the batch randomizer of
Haboeck and Kindi (ePrint 2024/1037). Section 5 states the argument.

## 4. The acceptance matrix, through the node's own verifier

- a window of distinct admitted machines reaching the quorum, honest roots, owned ticket: accepted
- count strictly below the quorum of the electorate: refused
- an attestation whose presence proof stands against another electorate root: refused
- an attestation whose part-nullifier repeats: counted once
- an attestation signed by a key the presence proof does not name: refused
- a proposal whose roots differ from the recomputed ones: refused
- a proposal signed by a key another machine's ticket proof names: refused
- a proposal whose predecessor is not the final proposal of W - 1: refused
- an observer given the serialized proofs alone: recovers no spending half
- a final beacon below the quorum, naming more parts than its certificate verified, or not linked to
  round zero and the predecessor: refused
- two runners, or two branches of the versions of a round, of one decision: one identifier
- the same rows through the running node's own close: accepted and refused as above
- a device walking from an anchor: the head is the newest proposal whose certificate verified; a
  forged anchor, a certificate below the quorum and a proposal the window after does not attest are
  refused

## 5. The hiding argument, in brief

Let every column be a polynomial of degree below n over the trace domain H of size n, with the
values at the last f rows drawn uniformly and independently by the prover, f = `proof_free_rows`.
Constraints hold on the live rows but the last of them, and boundaries name live rows. A transcript
reveals, per column, at most q row values at the query positions, q row values one row on through
the composition, and two evaluations out of the domain: 2q + 2 evaluations outside the live rows.
The map from the f free values to any 2q + 2 such evaluations is a Cauchy matrix scaled by
nonzero constants and is of full rank when 2q + 2 is at most f, so those evaluations are uniform
and independent of the witness. The randomizer column is a uniform polynomial of degree below n
with its own weight in the deep batch, so every value a folding layer opens is uniform. The
verifier recomputes the composition out of the domain from the revealed values and learns nothing
beyond them. With q = 48 and f = 128 the inequality holds with room.

## 6. The order of the work

1. This note; the hiding construction in the scheme, with the lengths it moves, and the
   disclosure test turned from a reproduction into a refusal. — Done, commit 0390e40.
2. The cement as the aggregate of part-nullifiers; the confirmation and the beacon without a
   weight; the standing commitment, the fold, the arithmetic step and the proof of a window
   carried apart leave the set and the tree. — Done, with the description of the ticket of stage
   three, in the commit that follows this note's second revision.
3. The description of the ticket — done with stage two; the proposal assembled and signed
   (`montana-node/src/runner.rs`) — done; stored and served by the running machine, with the
   electorate of W - 2 read from the proposal of that window — done in session 41.
4. The verifier of a window's closure as one entry point (`montana-node/src/certificate.rs`) and
   the acceptance matrix above as tests through it (`montana-node/tests/certificate_matrix.rs`) —
   done; the running node closing through that door, the retention of `retained_windows`, and the
   join from an anchor — done in session 41, with the roots of state, the final beacon and the
   identifier of what the window decided stated in Canon 7.1.0 and Consensus 5.1.0
   (`montana-node/tests/a_walk_from_an_anchor.rs`, `the_roots_of_state.rs`,
   `a_device_joins_the_running_chain.rs`).
5. The ledgers: AUDIT.md, ITEM-1-INTERNAL-AUDIT.md, the receipt of this session. — Carried with
   each commit.

Nothing in this note is a claim that any of it stands until the commit that carries it names the
test that shows it.
