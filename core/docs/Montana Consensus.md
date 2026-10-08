# Montana — Consensus

**Version:** 3.9.0

Consensus holds the TimeChain and its movement: how a window advances, who runs it, how it is cemented,
how a machine enters the set that runs windows, and how the right to a window's share is
issued. It holds no number — Canon holds those — and no note, no record of a person and no pipe.

## Scope

**In scope.** The TimeChain itself — what it is, what identifies it, what one link is, what
advances it and what it rests on; the canonical order and its properties; the layers of time; the round of a
chain and the beacon it turns on; the parallel chains of a window; the chain of cemented
windows and the presence of a machine; the runner's draw, its threshold and the
recomputation of that threshold; the committee and the quorum; the closing of a window and
its finality; the cascade of the beacon; the admission of machines; the issue of the right
to a window's share; the cold start.

**Not in scope.** Values, layouts and vectors — Canon. Notes, proofs and transfers — Value.
Records of people, keys and identity operations — Identity. Delivery — Network. The invariants
themselves — Constitution.

## The TimeChain

**The TimeChain is the sequence of cemented windows.** That is the whole of the definition, and
every other name for it in these documents is this one: the clock of Montana, the canonical order
of events and the chain a device joins are the TimeChain seen from three sides, not three objects.
It is a sequence because each window names its predecessor; it is of cemented windows because a
window enters it by the cement of the population that ran it and by nothing else.

**What identifies it.** The TimeChain is identified by its head, and its head is the identifier of
the newest cemented proposal — the value Canon derives for a signed object of that class, over the
scope that proposal states. Its coordinate is the height that proposal carries. Nothing further is
derived for it and nothing needs to be: a chain whose links are identified needs no identifier of
its own, and a second value standing for the whole would be a second place for what the head
already says.

**One link.** A window is a run of consecutive rounds on each of its chains, and what it leaves
behind is one proposal: the height, the identifier of the proposal of the window before, the roots
of state, and the proof that all of it holds. The link from one window to the next is that
identifier and nothing else — no timestamp, no sequence number of anyone's making, no signature of
an authority, no number a machine could choose. A proposal naming anything else is not of this
chain.

**What advances it.** The rounds of a window accumulate the cement of its predecessor. The moment
that cement reaches the quorum share, the predecessor is final, the window stops admitting traffic
and its runner assembles the proposal, and the next window opens — the three at once, by the rule
the section on the pulse states. Nothing else closes a window: no count of rounds, no measure of
duration, no clock.

**What it is not.** It is not a chain of iterations of a function: no work, no delay and no count
of hashes stands between one window and the next, and nothing in the set fixes how long a window
takes. It is not a ledger ordered by time: no quantity taken from any clock outside the protocol
enters any object of it, and a machine that has not seen the network does not know the current
window. It is not the opinion of a majority: two proposals of one height are separated by which
proof verifies, never by which is longer or which is held by more machines, and length decides
nothing within one set of rules.

**What its pace rests on.** The length of a window is a theorem rather than a number — the count of
rounds at which the standing no round has touched falls to the complement of the quorum — and the
floor under a round is the echo of the population across the geography it lives in. No processor,
no fleet and no width of silicon shortens it. Both are stated where they are derived, in the
section on the pulse and in Canon.

**When it cannot advance, it waits.** A quorum that cannot be reached closes no window. Rounds go
on, the cement accumulates and stops short of the share, and nothing else happens — there is no
timeout to expire and no reduced quorum to fall back to, because either would be a clock or a
majority and this document admits neither. A network parted therefore does not become two chains:
a part holding the quorum share carries the chain alone, and a part holding less carries nothing,
publishes nothing and waits. When the parts meet, the machines that closed nothing verify the
cements they missed and are of the chain again — a cement is verified rather than voted on, so
rejoining asks nobody's permission and revises nothing. What is traded away here is stated rather
than hidden: the protocol will stop before it will fork, and a wait is what a network under a
partition gets in place of a false answer.

**What a stranger holds of it.** A device that holds nothing verifies the proof of the newest
proven window offered to it, recomputes every root that window's proposal carries, and walks the
retained cements from there to the head — at most the depth the Decree bounds — and is then of this
chain: the work of entering does not grow with the age of the chain, because a window's proof
asserts the verification of the window before it. The join states the procedure and the cold start
states the first window.

**Invariants of the TimeChain:**

- Every window but the first names its predecessor by the identifier of that predecessor's proposal; a proposal naming anything else belongs to another chain.
- The coordinate of a window is its height, and one height carries one meaning for every participant.
- A window closes only on the cement of its predecessor reaching the quorum share of the committed total, by the rule of the pulse; no length, no count and no measure closes it.
- No quantity from outside the protocol — a clock, a date, a duration — enters any object of the chain, and none of its rules reads one.
- A machine that verified a cement never leaves it, and no longer chain within one set of rules overrides it.
- A quorum that cannot be reached closes no window: the chain waits, and a part of a parted network holding less than the quorum share carries no chain of its own.
- The chain depends on nothing downstream of it: the presence of machines and the records of people rest on the chain, and a failure of either stops nothing in it.
- What is recomputed is recomputed from the chain alone: no participant asks another what a coordinate means.

## The canonical order

The primary product of the protocol is a canonical order of events. Every window is a run of
consecutive rounds on each of its chains, and it closes on the cement of its predecessor: no
count of rounds is fixed anywhere, because the length of a window is a consequence of
coverage, and Canon derives its expectation rather than choosing it. A cemented window
registers one coordinate of that order.

Four properties hold of it and are what the rest rests on: it advances in one direction only;
one coordinate has one meaning for everyone; any participant recomputes it from the chain
without asking anyone; and it depends on no clock outside the protocol.

Time in Montana is counted in rounds, in windows and in multiples of the period of
adaptation, never in seconds. A machine that has not seen the network does not know the
current window, and that is correct: it has nothing to send until it has.

## The round

A round is one confirmed turn of one-to-many-to-one on one chain of a window: a beacon goes
out, attestations come back, the next beacon closes the turn.

**The beacon** of a round is five fields: the window, the chain index, the round index, the
identifier of the preceding beacon of that chain — or, for round zero, of the proposal of
the window before, the very proposal whose cement these rounds accumulate — and the running
cement state: an additively homomorphic
accumulation over the standing of every distinct machine that has attested this window on
this chain so far. Its identifier is the hash of its serialization under the beacon domain
Canon names. It carries no aggregate of its own round, no list and no count: the beacon is
the pulse and the ledger of the cement, and nothing else.

**Eligibility to attest is drawn, and drawn from what already exists.** A machine is eligible
for a round when the hash, under the round-attestation domain Canon names, of the nullifier of its
part in that window together with the cemented aggregate of the window two before and
the pair of chain and round clears the round threshold. **That threshold is not held by anybody's
observation: it is computed** from the count of machines the tree of admitted machines carries and
the count of chains in force, by the rule Canon states, so that the crowd of a round never falls
below the floor Canon derives — a round no machine is drawn for would not be a slow round but a
chain that stands, and without a clock nothing tells that apart from an answer still in flight. Three properties
follow, each from a part the set already fixes. It is grindless: the part-nullifier is
deterministic from the machine's secret and the window, and the aggregate is cemented —
nothing in the preimage is anyone's to choose. It is self-known and other-unknown: each
machine computes its own eligibility for every round of a window the moment that aggregate
cements, while nobody else can, because the key is unpublished until first used. And it is
natively verifiable: an attestation carries the part-nullifier its eligibility is drawn from, so
any verifier hashes it against the threshold with no proof and no counting — while the
attestation's own proof binds that nullifier to the secret of a machine that stands admitted,
which is what stops a fabricator from drawing secrets until one of them clears. That proof is the
**attestation of presence**, and it is a description the network accepts proofs under exactly as
the frame, the window and the admission are; what it asserts, what it publishes and why no other
description can stand in its place are stated in the section that owes them.

**Why the draw reads the nullifier and not the key.** Eligibility must be drawn from a value that
is fixed by the machine's secret and the window rather than chosen, or a machine draws candidates
until one clears. A one-time key is fixed that way, but no circuit can say so: the key comes of a
lattice key generation, and asserting that generation inside a proof costs orders more than the
whole statement around it. The part-nullifier is fixed the same way and is a value of the family
the circuits speak, so the proof asserts it in the arithmetic it already has. The key then chooses
nothing — it signs, and the proof binds it by its digest so that no one lifts a proof from one
attestation onto another.

**The attestation is the confirmation, extended by one field — and heavy exactly once.** It
attests exactly two identifiers, ascending: the beacon of its round and the proposal of the
window before. It carries the machine's part-nullifier of the window and one round
nullifier, derived from the machine's secret and the attested beacon's identifier. A
machine's first attestation of a window carries the full confirmation — the proof that binds
the answering key to a living machine's secret, and the freshly blinded standing — and it is
what enters the cement. Every later attestation of the same machine in the same window is
light: the same object without the proof and without the standing, valid because its key
already stood proven in the heavy one every verifier holds. Canon holds both layouts and the
one length of the light form. One signature therefore serves two duties — the pulse of its round and, once, the cement of
the previous window — and the heavy duty falls on a machine about once per window, whatever
the count of chains: exactly the confirmation duty it already bears.

**Closure, and the canonical fold.** The runner of a chain closes a round on the first valid
attestation it holds — validity is the native eligibility check, the signature under the
asserted suite, and for a heavy attestation its proof, for a light one the presence of its
key's proven heavy — and publishes the next beacon. The cement state moves only by the
canonical fold: the heavy attestations of the window are its leaves, ascending by
part-nullifier and each part-nullifier once in the life of the window, and every node above them
carries a fresh commitment to the sum of its two children with the proof that says so, up to the
root the beacon carries. A verifier recomputes every node from the attestations and the nodes it
holds and refuses a beacon whose state is not that root. Nothing in the tree accumulates: the
population enters its depth and enters no machine's work, so a network that grows folds no harder
than one that does not. The one freedom left to a runner is when to include, never what to
invent. A round cannot close before an eligible machine has heard the beacon and its answer
has returned: the turn is made of waiting, and the waiting is the clock. Nothing measures it;
the protocol learns that the echo returned, never how long it flew.

**The nullifiers, and what each bounds.** The round nullifier bounds a machine to one
attestation per beacon: a second presentation of the same value is refused in silence, a
deduplication and not a sanction. The part-nullifier bounds a machine's standing to one entry
in the cement of a window: its first appearance adds the machine's freshly blinded standing
to the cement state, and every later appearance — the machine attesting further rounds — adds
nothing and is lawful. What a sanction rests on is one part-nullifier attesting two different
proposal identifiers of one height, and the sanction's own section states it.

**Invariants of the round:**

- A beacon carries the window, the chain index, the round index, the identifier of its predecessor — the proposal of the window before for round zero — and the cement state, and nothing else; its identifier is taken under the beacon domain Canon names.
- Eligibility is computed from the part-nullifier of the window, the cemented aggregate of the window two before and the pair of chain and round, under the domain Canon names, compared unsigned and big-endian over the full width; nothing in the preimage is anyone's to choose, and every atom of it is one a proof of presence asserts or a cemented value every verifier holds.
- An attestation attests exactly two identifiers, ascending: the beacon of its round and the proposal of the window before.
- A machine's first attestation of a window is heavy and enters the cement; every later one is light and enters only the pulse; a light attestation is valid only where a heavy one under the same answering key stands published for the same window.
- The cement state of a beacon is the root of the fold of the published heavy attestations, each part-nullifier at most once, the leaves ascending by part-nullifier and every node carrying a fresh commitment to the sum of its children with the proof that says so; a beacon whose state is not that root is refused.
- A round advances only on a valid attestation; no count, no measure and no clock closes it.
- A beacon and the attestations answering it stand at the points of their round, and a proposal at the points of its window, so an attester reaches a runner it cannot name and a proposal reaches everyone; Network holds how they travel and Canon derives the points.
- A repeated round nullifier under one beacon is refused in silence and is never evidence.

## The pulse and the close of a window

The window has no length parameter. The rounds of a window do two things at once: their
beacons pin the slots that carry the traffic of the window, and their attestations accumulate
the cement of its predecessor. The moment that cement opens to a sum of distinct standing
meeting the quorum share of the committed total, one event does three things: the predecessor
is final, by the rule the Finality section states; the window stops admitting traffic and its
runner assembles the proposal from what the slots carried; the next window opens, its rounds
now accruing the cement of this one.

**A runner does not read the cement; it attempts the close, and the circuit answers.** The cement
is a sum of commitments and the total it is measured against is a committed scalar, so no machine
but the owners of what entered can open either — and a runner is not among them. What a runner does
instead is attempt: it builds the proof of the window over what it has gathered, and the circuit
asserts the cement against the quorum share of the committed total. A window that has not reached
the share yields no proof, because the assertion is false and a false statement does not prove; a
window that has reached it yields one, and that proof **is** the close. So the decision is never an
observation and never a judgement of a runner — it is the same artifact the network verifies, and
two runners of one chain reach the same answer because they attempt the same statement.

**What a runner reads to know when to attempt.** The count of attestations the cement holds is
public — it is a count of part-nullifiers and it names nobody — and the count of admitted machines
is a fact of the tree every machine walks. A runner attempts the close each time a new
part-nullifier enters the cement and the count of them has reached the quorum share of the count of
the admitted; below that the attempt is certain to fail and is not made, above it the attempt is
made and the circuit decides. Counting is not the rule and never becomes it: what closes a window is
the standing the circuit opens, and the count is only what keeps a runner from attempting a proof it
knows cannot stand.

**A residue the window never reached costs a window of latency and nothing else.** A window may
close before every residue of its chain has come round, and the senders holding the residues above
the close simply did not emit — nothing of theirs was published, so nothing of theirs repeats. In
the next window each derives a fresh ephemeral identity and a fresh slot by the ordinary rule and
sends there. No rule of re-placement is needed and none exists: what was never published cannot be
published twice, and the case that would need a rule — a frame that did travel and did not arrive —
is answered by the erasure code and never by a repeat.

**The length of a window is a theorem, not a number.** Eligibility is an expected share per
machine per round, drawn independently, so the expected share of standing that no round has
yet touched falls geometrically with the count of rounds. The smallest count at which it
falls to the complement of the quorum is `target_rounds`, a derived number of Canon, frozen
there with its boundary check and with the tail bound on what the variance touches. Where the crowd
of a round is the admitted through the divisor the expectation is exactly that count and depends on
nothing but the two frozen numbers behind it; where the floor of the crowd binds instead, the
expectation falls with the count of the **admitted** and a window closes sooner. Neither reading
touches the count of the **living**, which is what keeps that count closed while the count of rounds
is public.

**The realized length concentrates with the population, and the set says so rather than promising
otherwise.** Each round is a sum of independent draws over the living, so the spread of one window
narrows as their number grows: at a thousand machines a window sits within a tenth of its
expectation, while at a handful every machine is drawn every round and a window closes in its
first ones — at a single machine in the round it answers. Nothing downstream rests
on the concentration of a single window: the tail bound above holds at every population including
one, and every constant denominated in windows spans at least `selection_interval` of them, where
the averaging lemma bounds the deviation of the sum. What the young network gets is windows of
uneven length, which costs it nothing it can observe; what it does not get is a promise of evenness
the mathematics does not make. Under standing concentrated in few hands a window runs longer than
its expectation, because the cement waits on the few who carry the share — the tail bound covers it,
nothing adapts to it, and the set states that rather than implying a correction it does not make.

**Pace is pinned to the speed of light.** A round's duration is one echo across a sample scattered
like the population; a window is `target_rounds` echoes wherever the crowd of a round is the
admitted through the divisor, and fewer where the floor of the crowd binds; the floor under both is
the speed of
light over the geography of the living. No processor, no width of silicon and no fleet
shortens a return from another continent. The remaining headroom — routes straightening
toward geodesics, propagation approaching the speed of light — is a small constant factor
with a hard floor. And the pace is the population's, not any machine's: a runner that spins
beacons without honest attestations advances nothing, because every round waits for an
eligible machine's echo, and the cement waits for the quorum of everyone.

**Invariants of the pulse and the close:**

- A window closes only on the cement of its predecessor meeting the quorum share of the committed total; no count of rounds, no measure and no clock closes it.
- The quorum is asserted over the final cement state by the window's proof; no machine's standing is published on the way.
- No commitment of the fold accumulates randomness: every node commits afresh and proves the sum of its children, so binding holds unconditionally at every node, the count of machines enters nothing but the depth of the tree, and the window's proof opens the root and verifies one proof whatever the population.
- Verification of the fold is the duty of the round: an attester endorses a beacon only after recomputing its transition from the published heavy attestations, so the draw of the verifiers is the draw of the round itself — keyed to each machine's own secret, a sample no fabricator can aim away from — and no separate audit, no sampling and no ranking stands between a verified cement and finality.
- The count of rounds a window took is public and names nobody; it is a function of the count of the **admitted**, which the tree of admitted machines carries in the open, and never of the count of the living.
- The round threshold is read out of the count of admitted machines and the count of chains in force, by the rule of Canon; no observation, no count of rounds and no history enters it, and a chain of one machine and a chain of a million each compute theirs from state alone.
- A machine opens no window while more than `unproven_depth` closed windows stand without their proofs; the bound is read from held state, and the wait it imposes is the wait of a quorum shortfall, not a sanction and not a clock.

## Parallel chains

At every height the schedule of Canon fixes the count of chains: independent beacon chains
run concurrently in every window, each with its own rounds, its own eligibility draws, its
own slot space and its own quota of frames, all accruing the one cement of the previous
window, deduplicated across chains by the same part-nullifier. A sender's slot is a pair —
the chain and the residue, both derived from its ephemeral identity by the derivations Canon
fixes — and it emits at the first round of its chain whose index matches its residue, which
falls within the first `slot_modulus` rounds of the chain. A window therefore admits the
product of the chain count and the frames each chain carries, and the batch of mixing —
everything one window accumulates — grows by the same factor.

What the count of chains buys is stated exactly: it scales capacity and the anonymity batch
together — more payments per window, every one of them hidden among proportionally more —
while the pace of every chain stays the echo of the geography. The rings of the tree are
rings of capacity: the network ages into room, never into speed. Canon holds the cap, the
step of the schedule, and the volume arithmetic every step is checked against.

**Invariants of parallel chains:**

- Every chain of a window accrues the one cement of the predecessor; a part-nullifier enters it at most once whatever chain carried the heavy attestation.
- A sender's chain and residue derive from its ephemeral identity by the derivations Canon fixes; no sender chooses either, and no sender is moved by anyone's idea of the time.
- A chain is added only by the schedule of Canon, never by a runner, a vote or a measure of load.
- A step of the schedule adds no duty to any machine: eligibility spreads across the chains, the strikes of a window stay one family of numbers, the heavy attestation stays about one per window, and what grows is the shared stream of frames, capped by the envelope of Canon.

## The secret of a machine

A machine holds one secret, and everything it does derives from it: the ticket it draws at
home, its part in a window, its right to raise itself, its share, and the moment that share is
taken. The secret never leaves the machine and enters no object it publishes — what leaves is
always a value derived from it in one direction, under the domain Canon names for that use.

**One secret of its own, and one value its owner places there.** Everything the machine
produces derives from its own secret. The owner branch is not of that kind and is stated apart
for exactly that reason: a person copies it onto every machine they run so that the seal of a
step collapses to one value per owner, it derives from the person's seed and from nothing of the
machine, and no value the machine publishes about itself derives from it. The two never mix —
Canon names the machine's secret where a machine acts and the owner's branch where an owner is
being counted, and a derivation taking one in place of the other is a defect.

**Every device that speaks on the network holds a secret of this kind**, whether or not it is a
machine: it is drawn the same way, it never leaves the device, and every published value derives
from it in one direction under the domain Canon names for that use. A device that is not a
machine draws no ticket and takes no share, and it still places itself in a window by a value
derived from this secret — which is why the derivation Canon fixes for that placement names the
sender's secret rather than a machine's.

It is the counterpart of the seed a person holds, and it is separate from it: a machine is
accountable and a person is not, so the two must not be one secret. Where one machine and one
person share a device, they still hold two secrets, and no published value of either derives
from the other.

**Invariants of the secret:**

- It is generated on the machine and is never transmitted, escrowed or reconstructed elsewhere.
- Every published value derives from it in one direction and under a distinct domain; no two uses share a domain.
- Losing it loses the machine's standing and nothing else: the value a person holds lives under their own secret and is untouched.

## The runner's draw

The draw answers one service question — **who runs this window** — and it answers nothing
about money. The share of a window is divided equally
among the living, and the machine on duty receives the same share as any other.

**A threshold, not a comparison.** Every living machine computes its own ticket at home from
its own secret and the cemented aggregate of the window two before the one being drawn, and
checks it against the threshold of the draw held in state. It is that aggregate and no other: the aggregate
of the preceding window is still being cemented when the draw must happen and is therefore not
canonically available to everyone, whereas the aggregate two before is fixed in the preceding
proposal and cemented in time. A ticket drawn from any other window is not a variant — it is
a different network. Comparing tickets would require collecting them, and collecting them
would require naming the participants. Nothing is applied for and nothing is announced: the
one that cleared the threshold is revealed by the fact of publishing a window, and its proof
asserts that it cleared without disclosing the ticket, the secret or the machine.

**The ticket carries no standing.** The standing of a machine rests under a commitment and does
not enter the draw, so every living machine has the same chance and the expectation of income
equals the share of a window — without the network ever holding the quantity "how many of us
there are".

**Two tickets clearing one window.** The draw is a threshold and not a comparison, so nothing
stops two machines from clearing it in one window, and each publishes. The proposals are separated
by their identifiers: the smaller, read as an unsigned big-endian integer, is the one the window
closes on, and the other is a neutral duplicate whose runner keeps its share and loses only duty.
The rule needs no collection and no naming — every machine holding both proposals reaches the same
answer from the two identifiers alone — and it is the same shape as the rule for two versions of
one round, where seniority decides.

**Why a draw and not a queue.** A queue in a circle is known years ahead, and every future
runner can be attacked before its turn, in sequence, until the network stops. The aggregate
the ticket is drawn from is cemented by the signatures of honest participants: it is not
computable offline and not enumerable, so the runner becomes known one window before duty
and there is no time to aim. Eligibility to attest a round is drawn the same way at a
faster pulse — from the one-time key
of the window and the same cemented aggregate — so a machine knows its own rounds the moment
the aggregate cements, and nobody else knows them at all.

**What the aggregate is bound to.** The aggregation Canon defines takes a context, and for the
draw that context is the height of the window being drawn, as an unsigned eight-byte
little-endian integer — not the height of the window the set came from, and not an empty value.
The distinction matters twice over: it makes the seed of each window distinct even where two
windows cemented the identical set of signers, and it leaves no choice to an implementer, so two
implementations cannot compute two seeds and elect two runners from one cemented state.

**The lookback.** The aggregate that fixes the draw is that of the window two before the one
being run: its cemented set is fixed in the preceding proposal and canonically cemented by
the end of the current one, so every participant uses one and the same value and verifies the
endpoint with a single hash.

**Grinding.** Choosing a favourable keypair does not help: by the time the aggregate is
public, the keys of everyone who could be in the committee are already fixed, and the
aggregate is built by the rule Canon states for aggregation into a seed, which admits nothing
an author of an object may choose. Canon holds that rule; it is not restated here, because a
restatement is exactly how the two would come to prohibit different things.

### The threshold of the draw, and its recomputation

The threshold is recomputed over a period so that a window is passable exactly as often as
the protocol intends: where fewer windows were cleared than the period holds, the threshold
rises; where every window was cleared, it holds. The recomputation is integer, it moves by a
fraction of the divergence rather than the whole of it so that it does not oscillate, and one
step is bounded by a factor of four so that a brief collapse of connectivity cannot run it
away. The damping factor, the period, the bound and the vectors that fix the arithmetic are all
Canon's. The shape of the rule is what this document states: the threshold rises when windows
go unclaimed, holds when every window is claimed, moves by no more than the bound in one step,
and never reaches a value at which no ticket can clear.

**Invariants of the draw:**

- A ticket is derived from the machine's secret and the cemented aggregate, and from nothing else; it is never published.
- The comparison is unsigned and big-endian over the full width of both quantities.
- The aggregate is that of the window two before; a proposal drawn from any other window is rejected.
- The threshold enters state and changes only by the recomputation above.
- A machine whose proposal the quorum rejected takes no part in the draw of that window; its ticket is disregarded for that window and for no longer.
- Clearing the threshold is asserted by the window's proof; a proposal that discloses a ticket is malformed.

## Closing a window

**The confirmation of a window.** A machine that has verified a window attests it by publishing
a confirmation: an object carrying the identifiers of what it attests, in the canonical order
Canon fixes for them, and the nullifier of its own part in that window. It is signed, and the
suite it is signed under is one the window's proof asserts. It names no machine and no owner:
what a reader learns is that a distinct participant attested these operations, never which one. A
part-nullifier appearing again for one window adds nothing to the cement and is lawful; one part-nullifier
attesting two different proposal identifiers of one height is the equivocation the sanction
of this document states.

A window is closed when confirmations whose combined standing reaches the quorum sign the
proposal. The quorum is a share of the standing of the active set, and the divisor that sizes
a committee is a number of Canon. The standing of signers is asserted by the window's proof; it
is never added up in the open.

The runner assembles the proposal from what the slots carried, commits the roots of
state, proves its ticket in the proposal itself, and publishes; the proof of the window follows as
its own object, and the section of the proof states who builds it and how far it may lag. Verification is independent and complete: every attestation verified
natively as it arrived, every beacon linked by hash to its predecessor and, at
round zero, to the proposal it stands on and cements, the roots recomputed, the quorum asserted, and the **control set** matched against its rule. The
control set of a window is the objects that change who runs windows, and it is exactly three: the
candidacies redeemed at a selection event of that window, the expiry of candidacies that no event
admitted, and the pruning of machines whose membership term ran out. Each is admitted canonically —
by the rule of this document and the order of Canon — and never at a runner's discretion, and a
proposal whose control set differs by one object from the one every verifier recomputes is
refused. Nothing in a proposal is taken on trust.

**When two clear the threshold**, the window goes to the one whose proposal identifier — taken
over the deterministic fields alone, so no runner grinds a name through the randomness of a proof —
is lexicographically smaller; the other is rejected as a neutral duplicate. It gains nothing by
running and loses nothing by being rejected: its share is the one it already holds as a living
machine, and duty adds no part of a mint to anyone.

**The cascade of the beacon.** A stalled runner is replaced without a timeout, because a
timeout is a clock. The standby order of a window is the one Canon derives — the ascending order
of the cascade key over the commitments of the active set, taken under a domain of its own and
over the same cemented aggregate the draw uses, so that no participant computes it early or grinds
a commitment toward an earlier place. The machines standing first in it, to the count
`cascade_width`, are the entitled of that window, senior first, and they run their versions of
every chain in parallel from the window's first round. An eligible machine attests every valid version it sees: versions of
one round are distinct beacons, so the round nullifier — bound to the beacon identifier —
yields distinct values, and attesting them all is duty, not equivocation. The window closes
on whichever entitled version completes the cement first; among versions completing in one
round, the senior's; a losing version is a neutral duplicate, its runner keeping its share
and losing nothing but duty. The share of the window is divided among the living regardless
of who ran.

**Withholding buys nothing.** Every path from a runner's one freedom — when to include — to a
gain ends in one of three walls. A recomputation that rejects: frames arrive in canonical
slots and every verifier holds them independently, so a proposal whose roots omit or add
anything dies, and censorship is self-rejection, while the cement moves only by the canonical
fold every verifier recomputes. An objective that cannot be read: the one quantity inclusion
timing could tune is the cemented aggregate, and its consumers are tickets and eligibilities
keyed by other machines' secrets, which the runner cannot evaluate. And a duty that pays
nothing: delaying the crossing delays only the runner's own version while junior versions
complete and take the window — the slots are canonical, so the contents are identical either
way, and duty adds no share.

**Skin in the game.** A machine whose proposal the quorum rejects loses the duty of that
window and takes no part in its draw. Its share as a living machine is untouched — the share
is equal and does not depend on duty.

## Finality

The cement quorum exceeds two thirds of the standing of the active set, so two cements of one
height carry quorums intersecting in at least a third of all standing — and every machine of
the intersection has attested two different proposals of one height under one part-nullifier:
self-evident pairs, nameless, the sanction's own evidence. Finality is therefore accountable:
impossible below a third of standing willing to convict itself, self-evidencing above.

**What prices that third, and what does not.** The sanction is not what makes a reversal
expensive: an equivocating right loses the share of its window and nothing else, so a third of
standing willing to convict itself pays a third of one window's mint between them. What makes it
expensive is what standing is. Standing is lived time under the rules of this document — it is not
bought, not delegated and not transferred, and a third of it is a third of everything the network
has lived. A protocol whose weight were purchased would need the sanction to carry the price,
because the weight itself would be for sale; here the weight is the price, and the sanction is what
makes a reversal **evident** rather than what makes it dear. Safety at this boundary is structural
and accountable, and the set says so instead of implying an economic guarantee it does not give.

A machine that verified a cement never leaves it. Within one set of rules length decides
nothing; the length rule of the Constitution survives for the divergence of rules alone, and
it counts cemented windows. The challenge of a window opens at its proposal and closes at its
cement, and a pair presented after that close is refused. The attestations themselves outlive the
challenge only as the bridge the join walks — retained until the window's proof stands — and their
longer life extends no challenge and names nobody.

**Invariants of finality:**

- A cemented window is never abandoned by a machine that verified its cement, and no longer chain within one set of rules overrides it.
- Two cements of one height imply at least a third of all standing equivocating, and the pairs of attestations under one part-nullifier are the whole evidence.
- The challenge of a window runs from its proposal to its cement; a pair presented after the close is refused, the attestations retained for the join extend no challenge, and nothing of it enters persistent state.

## The sanction of a double answer

One part-nullifier attesting two different proposal identifiers of one height is proof that
one right equivocated between two closings, and it is the only proof this protocol accepts
against a machine — a timeout, a silence or a neighbour's
account of what it saw are not evidence and change nothing.

**The sanction names nobody, because nothing here can.** The second appearance is refused in
silence and the right it would have spent is extinguished without issue: the share of that window
is not paid, and nothing beyond that right is touched. There is no confiscation, no exclusion by
name and no list of offenders, because a machine is accountable through its rights and not
through an identity — the construction that hides it is the one that catches it.

**Who applies it.** Everyone, and identically: the pair of objects carrying one nullifier is
self-evident to any machine holding both, so the refusal is a local rule with a global result and
needs neither a court nor a report. Whoever holds the evidence keeps it while the window remains
open to challenge, and discards it with the window.

**Invariants of the sanction:**

- Only one part-nullifier under two different proposal identifiers of one height is evidence, and
  the weight of the attestations carrying it is nothing to the rule: a light attestation carries
  the pair exactly as a heavy one does, its signature being the machine's own and its key already
  proven by the heavy it inherits. A rule admitting only heavy attestations would leave every
  equivocation unprovable, a machine publishing one heavy in a window and every later attestation
  of it being light. Its repetition under one proposal is the lawful deduplication of the cement,
  and a repeated round nullifier under one beacon is refused as a duplicate, never held as
  evidence; nothing observed about timing, presence or reachability is.
- The refusal falls on the right and not on a party, so no implementation needs a name to apply it.
- The first appearance stands and the second is refused, by the canonical order of the window and never by the order of arrival at a machine.
- A pair is admitted no longer than the window's challenge and enters no persistent state; the attestations retained for the join extend no challenge and name nobody, so nothing accumulates about anyone.

## The proof a window carries

A window carries one proof, and it asserts four things without disclosing any of them: that the
signers reached the quorum by accumulated standing, that the count of the living was the divisor
the shares were computed by, that the proof of the window before it verified, and the suite the
window and its confirmations were signed under. The clearing of the runner's ticket is not among
them: it is proven in the proposal itself, by the ticket proof that object carries, because the
chain reads the runner's right at the close and cannot wait for a proof that follows.

**The proof is carried apart, and the chain does not stand on it.** The living verified the window
themselves — every attestation natively, every beacon by hash, every root recomputed — so the proof
adds nothing to a machine that was there; its reader is the device that was not. Its witness is
public but for nothing: the heavy attestations and fold nodes of the window, the canonical slots,
and the proof of the window before — so any machine builds it, the runner first and the standby
order of the window where the runner falls silent. The proofs are sequential, each asserting its
predecessor verified, and the chain opens no window while more than `unproven_depth` closed windows
stand unproven — a bound read from held state, never from a clock, under which a chain whose prover
is slower than its rounds degrades to the pace of the prover instead of failing anybody.

**The difficulty, named before the answer.** Two of those five run over the set of signers, and
that set grows with the network. A proof whose trace follows the size of what it proves would
publish the count of the living in its own length — the very quantity it exists to hide — so the
statement must be of fixed width whatever the set.

**The answer: the sum is taken outside, and only the result is proven.** Standing rests under an
**additively homomorphic** commitment, so the commitment of a sum is the sum of the commitments.
The runner adds the standing commitments of the signers with no proof at all — addition needs
none — and the circuit then asserts one inequality between two committed scalars: the summed
standing against the share of the total the quorum demands. A hundred signers and a hundred
thousand produce one addition of one width and one statement of one size. Nothing about the count
enters the length, because the count never enters the circuit.

The count of the living is handled the same way: it lives as a committed scalar of state, changed
by admission and by pruning, and the circuit reads it as one opening rather than by walking a
table.

**The honest price.** Every linear claim of the whole history rests on the correctness of this proof
scheme, and everything the division leaves out rests on the quorums that signed. The set states both
rather than leaving either to be discovered. A device joining verifies one proof and
inherits every window behind it, so a scheme that fails does not fail loudly: a forged past would
cost its author nothing and announce itself to nobody, where a protocol paying for its past in
accumulated work makes the same forgery cost that work again. From that follow obligations rather
than wishes, the same ones the value layer states for issuance: two independent implementations of
this verifier accept and reject identically, a divergence between them is a release blocker, and
the retirement of a scheme is a procedure of the boundary between eras rather than a hope that no
retirement comes. What a boundary owes the era it closes — whether the recursion alone carries the
history across it, or the boundary anchors that history by a value the retired scheme cannot
forge — is named in the register of what the set does not yet fix, and is not answered here by
silence.

**Why this and not a bound on the committee.** A bound would cap the network at the size where
the committee reaches it, and a network that stops admitting is not a network. Why not a tree
carrying sums: that is a third tree construction, and the protocol keeps two — the surface of
primitives is a cost paid forever, while homomorphic addition is a property of a commitment the
constitution already permits.

**What the circuit asserts.** That the runner's window ticket cleared; that the final cement
state opens to a sum of distinct standing meeting the quorum share of the committed total;
that the count of the living, read as one opening, was the divisor of the shares — the committed
total the quorum opens and the count of the living the shares divide by being two distinct
committed scalars of state, one a sum of standing and the other a count of machines, each opened
once, so an implementation folding them into one commitment is wrong; that the proof
the previous window carried verified, or — at the first window — that its roots were the empty
roots the Genesis State Hash binds; and the suite. That last assertion is what lets a device hold
no history: verifying the newest proof verifies every window behind it, which the join states as
the property it is. Rounds do not enter the circuit: every attestation was verified natively as it
arrived — eligibility by one hash, the signature by the suite, the machine by the
attestation's own proof — and the beacon chain, whose closing identifier the proposal
carries, binds the rounds into the cemented history. Nothing of a round enters persistent
state at any machine: beacons are discarded with the window — the rate set lives for one standing
period of the horizon of proving and empties when its stride moves — and the heavy
attestations and fold nodes outlive it only as the retained bridge of the join, held at their
points until the window's proof stands and gone with it — so rounds add not one row to what a
machine keeps.

**What the window asserts of the window before it is an accumulation and not a verification, and
the count is what decides that.** A verification in circuit walks what a proof carries: every
query opening its paths against the trace, the composition and each folding layer, and the
transcript replayed to draw what it drew. Counted in permutations of the proof hash — the unit a
circuit is counted in — that is nineteen times a frame and not a fraction of one, a height four
powers of two above the one a frame stands at, and an extended trace several times the memory the
weakest device this protocol claims can hold. A circuit of that shape does not fail slowly on a
telephone; it does not run on one at all, and the parameters of the scheme were derived from that
device rather than measured against it afterwards.

What stands instead is the construction the scheme already carries for the fold of a window: a step
of accumulation takes the claim of the window before and yields one claim, in field operations and
one commitment — it verifies no proof, opens no path and answers none of the queries. The
accumulated claim is discharged once, natively, by whoever must be convinced of it. A joining
device already verifies one proof natively; it discharges one accumulator beside it, and its work
stays a constant of the protocol rather than growing with the age of the chain. The property this
document states of the join is therefore untouched: the newest proven window convinces a device of
every window behind it, and no device holds a history.

**Why accumulation is forced and not preferred.** A verification in circuit is refused at every
choice of parameters and not merely at the ones this document froze, and the reason is that its two
costs trade against each other. Raising the rate of the inner proof buys fewer queries and pays for
them in longer paths, since a path is as deep as the extended domain; lowering it does the reverse.
Swept across every rate from two to sixteen million and every height the folding admits, the
cheapest verification anywhere costs more than twice what the device leaves after a frame, and its
cheapest point is a rate whose prover would extend a trace to 2³⁶. There is no floor below it,
because the product of the count of queries and the depth of a path is bounded below by the
security target itself. Accumulation is therefore the only remaining shape, and this document says
so as a derivation rather than as a preference.

**What an accumulation must rest on, derived the same way.** A step folds the claim of the window
before into one claim and must bind both, at the cost of field operations rather than of hashing.
Where a commitment is a tree of hashes, binding the folded claim means committing to it again — the
very cost the step exists to avoid — so a step is cheap exactly where the commitment is **additively
homomorphic** and the folded commitment is a combination of the two rather than a new tree. Of the
commitments a post-quantum protocol may stand on, the minimal-surface rule admits one here without
adding an assumption: the lattice this set already carries, whose parameters are the signature
scheme's and whose homomorphism the quorum of a window already uses to sum standing outside any
circuit.

**What a step costs, counted in the same unit as the verification it replaces.** The accumulator
carries the randomness of the commitment and the commitment itself — two thousand eight hundred and
sixteen coefficients and one thousand five hundred and thirty-six. What a circuit folds is the instance and never the
witness — the runner folds the randomness natively, where it costs nothing — so a step is one
multiply-add per coefficient of the commitment: two hundred and eighteen rows at the width the
bound fixes. An element of the ring in that place would be a convolution per polynomial and cost
nineteen thousand six hundred and sixty-one, ninety times as much, so the question is never whether
to spend the ring's price but which cheap challenge is admissible — and **cost alone does not
decide it, because what makes a fold mean anything is that two accepting answers to two challenges
yield the folded claims apart.**

**The algebra of the challenge is fixed by the extractor and not by the count.** Taking two
transcripts apart divides by the difference of their challenges, and what the difference divides is
a witness whose shortness is the whole of the commitment's binding — a commitment binds only what is
short, so an extracted witness that is long says nothing. A challenge drawn from the modulus of the
lattice fails there and fails badly: every difference but one has an inverse of about half the
modulus, so the extracted witness is longer than the bound by six orders and the binding it was to
rest on is vacuous. **And that is a fact about the extraction route, which the argument below does not take.** The
argument that carries this accumulation counts instead of extracting, and a count asks nothing of an
inverse. What it asks of the challenge is two things only. It is never zero, because a fold
weighs the window it takes in by the challenge, and a challenge of zero does not fold that window
but drops it — the accumulator standing at the end would assert nothing whatever about it, and a
prover holding a false window would need no forgery, only the luck of a zero. And it is **drawn from
the transcript after the instances are committed**, so a falseness is fixed before it learns the
weight that will multiply it.

Under those two demands the challenge is a **scalar of the modulus** — drawn from the transcript and
redrawn while it is zero or at or above the modulus — and it carries the twenty-three bits of that
modulus rather than one. A fixed falseness is cancelled only if the ratio of two weights hits one
particular value of the modulus, which is one chance in it; **six folds in parallel therefore stand
past the security target**, six times twenty-three being a hundred and thirty-eight, where
challenges of one bit would need a hundred and twenty-eight of them. The six shrink everything
downstream: the rows of the fold, the randomness discharged, and above all the accumulators a
window publishes and a proof must bind — six commitments rather than a hundred and twenty-eight.

A lane of a scalar fold carries the witnessed reduction of its product — the quotient held in range
as the remainder is, since a remainder held and a quotient free is no reduction at all — so a lane
is wide and a row holds one; six repetitions over the coefficients of an instance stand near nine
thousand rows. The randomness is then reset by decomposing the folded value into digits whose count
follows the width of the challenge, near eighty-two thousand booleans at a boolean to a column, some
thirteen hundred rows; and every reset is a recommitment, so each opening the argument ever speaks
of is an opening of digits and stays inside the bound the binding covers. **The whole step counts
near a tenth of the height the memory of the device admits, where the verification it replaces asked
six times the whole of it** — counted on the written atoms, and measured only when the circuit is
assembled, since a step counted twice is worth less than a step counted once against the assembled
thing.

**And the one thing that remains, stated precisely because it is the whole of what is left.** The
shape is fixed and it fits: a scalar of the modulus for a challenge, six folds in parallel, a
decomposition that resets the norm and recommits what it decomposed.

**And what remains is a division before it is a proof.** Two arguments can carry an accumulator, and
they ask different things of the shape. One extracts: from two accepting answers it builds the
witnesses of both folded claims, which one step of this fold admits since a bit subtracts and
nothing divides — but a chain composes extractors and the composition costs two to its depth, and a
chain of windows has no bound on its length. The other counts: a false claim survives a scalar
challenge with one chance in the modulus, so six of them let it survive one fold with probability
below two to the minus hundred and thirty-eight, and a chain costs a factor of its length and no
more. **The second asks one thing in return — that what is folded be linear over the
commitment** — because only then does the falseness of a part reach the combination by the algebra
alone.

A window's assertions are not all linear: a threshold is an inequality and a range is a
decomposition into bits, which is quadratic. So the statement a window carries divides in two — the
linear part, which the fold carries and the count answers, and the rest, which is answered where it
stands and never folded. **Writing that division is what the accumulation owes, and it comes before
any proof**, since a proof can only be about a shape that has been drawn. It is drawn here.

**What accumulates, because it is linear over the commitment.** That the summed standing of a window
equals the sum of the standing of the machines its cement names. That the count of the living the
window used as its divisor equals the count its commitment holds. That the issuance of the window
equals the share of a window times that count, the share being a number of the Decree and not a
committed value. And that the roots this window opens on are the roots the window before it closed
on. Each is an equality between committed values and numbers of the Decree, so a false one carries
its falseness into any combination by the algebra alone, and the count above answers a chain of any
length at a factor of that length.

**What does not accumulate, and what carries it instead.** The ticket and its threshold: a rule of
turn-taking, which decides **who** closes a window and never **what** the window does — a runner who
took a turn not theirs still had to close a window every machine accepted, and the machines of that
window are what refuse a turn taken wrongly. The margin by which a quorum was met: an inequality,
whose range is a decomposition into bits and therefore quadratic, and which the cemented signatures
of that window assert by existing. The paths and the hashes of the window's own operations: each
verified by the machines of the window and summarized in the roots the accumulation does carry.

**The price of the division, stated rather than discovered.** What does not accumulate is inherited
by **attestation** — the signatures of the quorum that was alive — and not by proof. A device
joining verifies one proof and inherits by it every linear claim of every window behind it; the rest
it inherits by the assumption the consensus makes everywhere else, that a quorum of a window was not
wholly dishonest. The two are different strengths, and the set names which is which rather than
letting one word cover both. Folding the quadratic parts as well is possible and buys nothing here:
no chain without a bound on its length can extract from them, so it would cost more and guarantee
less.

**The argument for the part that accumulates, in three legs.** With the division drawn it is short,
and it is written here rather than promised.

*The first leg is the algebra.* Everything folded is an equality between committed values and
numbers of the Decree, so an accumulator after any run of windows is one linear combination of those
equalities, weighted by the challenges along the way. If the equality of some window is false by a
non-zero amount, that amount enters the combination multiplied by its weights and by nothing else —
there is no term in which it can hide, because a linear combination has no cross terms. This is the
whole reason the division was necessary: a quadratic part would produce them.

*The second leg is the weights.* A challenge is a non-zero scalar of the modulus, drawn from the
transcript after both instances are committed, so a prover fixes its window before learning how the
window will be weighed. A falseness of a fixed non-zero amount is cancelled by the fold only if the
challenge — or, across two windows, the ratio of two challenges — hits one particular value of the
modulus, which is one chance in it; six repetitions drawn together leave the modulus to the minus
sixth, below two to the minus hundred and thirty-eight. A union bound over the chain multiplies that
by its length and by nothing worse, since the challenges of different windows are drawn from
different transcripts.

*The third leg is the binding.* The two legs above show the accumulator carries a non-zero value
when any folded equality is false; the verifier's check is that the accumulator opens to zero. A
prover could try to open it to something other than what was folded, and that is exactly what the
commitment forbids — two openings of one commitment, both short, are a short solution of the lattice
problem the parameters of the signature scheme are chosen against. Shortness is what the
decomposition maintains: the norm grows by three at each fold and is taken back to a digit before
the next, so the openings the argument speaks of are always inside the range the binding covers.

**The same argument, written symbol by symbol**, so that a reader outside this tree can check it
without reconstructing what the words above mean.

Let `Com` be the commitment of this set, binding for openings of norm below `beta` under the lattice
problem the parameters of the signature scheme are chosen against. Let window `W` present an
instance `I_W = (C_W, L_W)`, where `C_W` are the commitments the window publishes and `L_W` is a
linear form whose coefficients are numbers of the Decree, such that an honest window satisfies
`L_W(v_W) = 0` for the values `v_W` inside `C_W`. Write `delta_W = L_W(v_W)`, the amount by which
that window is false, zero for an honest one.

The accumulator starts at zero and folds one window at a time:

```
Acc_0 = 0
Acc_W = Acc_(W-1) + c_W * I_W          c_W a non-zero scalar of the modulus, drawn from the transcript
                                       after C_W and Acc_(W-1) are committed
e_W   = e_(W-1) + c_W * delta_W        the amount the accumulator is false by
e_k   = sum over W of c_W * delta_W    by induction, and there are no products
```

**Claim.** If `delta_W' != 0` for some `W' <= k`, a verifier accepting `Acc_k` does so with
probability at most `k` times the modulus to the minus sixth — below `k * 2^-138` — plus the
advantage of breaking the commitment.

*Why a false window cannot be cancelled.* A prover wanting `e_k = 0` while `delta_W' != 0` must make
some later window false in compensation: `c_W' * delta_W' + c_W'' * delta_W'' = 0`. The values inside
`C_W''` are committed before `c_W''` is drawn, so `delta_W''` is fixed while the weight that will
multiply it is not; cancellation therefore requires the ratio `c_W' / c_W''` to take one particular
value of the modulus, and a ratio of two scalars drawn after the falseness is fixed hits it with
probability `1/q`. The fold is run in six independent repetitions which share the window's values
and differ only in their challenges, so cancellation must hold in every one of them at once: at most
`q^-6`, below `2^-138`. A union bound over a chain of `k` windows gives `k * q^-6`, which for a
period of this set is below `2^-123` and for a billion windows below `2^-108`.

*Why the accumulator cannot be opened to something else.* The verifier's check is that `Acc_k` opens
to a short witness satisfying the accumulated form at zero. Two short openings of one commitment are
two solutions differing by a short non-zero vector in the kernel, which is a solution of the lattice
problem — so a prover who folds one witness and opens another breaks the commitment.

*Why every opening in the argument is short enough for that binding to apply.* A fold multiplies
the randomness by a scalar of the modulus, so the folded value itself grows far past any bound — and
no opening of it is ever claimed. The decomposition that follows every fold recommits what it
decomposed, so what stands after every step is a commitment to digits, and the only openings the
argument speaks of — the instances at commitment time, and the final accumulator at its native
discharge — are openings of digits and stay below `beta`.

**What this argument does not reach**, said plainly so the legs are not read as more: it carries the
linear part alone, which is what the division isolated; it assumes the commitment binds at the
stated parameters, which is a citation and not a result of ours; and it assumes the transcript the
challenges are drawn from is the one the set already specifies, so a second implementation drawing
them otherwise proves a different statement. What is not fixed is the argument that binds them — that an accumulator standing at the
end implies every claim folded into it held, at the security target and under the binding of this
lattice after a decomposition. That is a proof and not an engineering choice, and until it is
written this document asserts no soundness for the construction: a scheme named in a document and
never proven is the defect this passage exists to have avoided.

**What an opening costs, and why it is taken through the transform of the ring.** The circuit
opens two committed scalars — the total the quorum is measured against and the count of the living
the shares divide by — and an opening recomputes the commitment from its randomness, which means
the product of the public matrix by that randomness. Taken as a convolution that product is near
two million multiplications for each opening, and two of them are more than the whole height the
memory of the device admits: ninety-six parts in a hundred of a circuit that does not fit. Taken
through the negacyclic transform the ring already carries — the one the signature scheme uses, the
modulus admitting it because its predecessor is divisible by twice the degree — the same product is
ninety-six times fewer, and **the matrix being public its transform is a constant of the circuit
and costs nothing at all**. An implementation that convolves computes the same value and does not
fit the device; the set therefore states the transform rather than leaving it to be discovered by
whoever measures afterwards.

With it the whole circuit of a window — the ticket, the two openings, the share the way back gives
at the round the proposal names, the comparison of the quorum, and one step of the accumulation —
stands at a tenth of the height admitted, at the same power of two a frame stands at and a quarter
of the memory. The claim this document made of it, that it is a small circuit, holds of everything
it asserts of itself; it was the recursion alone that did not, and the recursion is an accumulation
now.

**Its length is the length of a frame, and deliberately so.** The trace is padded to the size a
frame uses, so both proofs run under one parameter set, verify through one verifier, and carry
one length: `PROOF_LEN`. The padding costs the runner proving time once a window and buys the
protocol one number instead of two, one verifier instead of two, and a proposal whose length does
not depend on which kind of proof it carries. A second length would have to be derived,
frozen, checked and defended for no gain that anyone could name.

**Invariants of the proof a window carries:**

- Its length is `PROOF_LEN`, identical to a frame's; a proposal carrying a proof of any other length is refused before it is parsed.
- No quantity of the signer set enters the trace, so the length says nothing about how many signed or how many live.
- The summed standing is obtained by adding commitments outside the circuit; a circuit that walked the signers one by one would make its own length a counter.
- The ticket is recomputed inside and never published, and the assertion that it cleared is all that leaves.
- The count of the living is read as one opening of a committed scalar and is never published.
- The circuit accumulates the claim of the previous window rather than verifying it, so every window's assertions stand behind the newest one at the cost of one step and one commitment; the recursion terminates at the first window against the empty roots the Genesis State Hash binds, the accumulated claim is discharged once and natively by whoever must be convinced, and a device therefore joins in work that does not grow with the age of the network.

**What the commitment owes and what it costs.** The commitment carrying standing is additively
homomorphic and its parameters are those of the signature scheme the set already carries, so its
hiding stands where the signatures stand and its binding stands at a smaller bound of the same
lattice — Canon holds the construction, the two vectors and the arithmetic. Nothing about the fold caps a
population: every node commits afresh and proves the sum of its children, so randomness never
accumulates and the count of machines enters only the depth of the tree — Canon states its shape
and how the work of it spreads. Everything here is fixed — what is asserted, how the
sum is taken, why the length is constant, and what that length is.

## What a machine commits about itself

Three quantities of a machine are held under one commitment and never in the open, and each is
proven when a rule needs it.

**Standing** is what a quorum adds up: the accumulated presence a machine earned by carrying
and answering. It grows with cemented windows in which the machine took part, no decision of
anyone lowers it, and it is compared only inside a proof — so a quorum is asserted as reached
without anyone learning whose standing composed it.

**The temporal quantities** are what tell a term from its lapse: the window a membership was
granted in and the window last answered for. They are proven when a term is renewed, and no
timeline of a machine is public.

All three rest under one commitment, under the domain Canon names for it and behind a blinding
factor drawn afresh, and each is opened only by a rule that needs it — so two machines with equal
quantities do not present equal commitments, and a rule reading one of them learns nothing of the
others.

## Presence and admission

A machine is living when it carried and answered for a window; presence is proven, never
declared. Its place in the active set is granted **for a term** and lapses at the end of it
unless the machine renews it by an act of its own. Nothing observes absence, and nothing needs
to: where participation names nobody, no one can tell which machine fell silent — so
membership is not taken away for silence, it simply runs out. Renewal carries the same proof of
presence any window carries, and a machine that stopped working renews nothing and is gone when
its term ends.

This is the choice the identity plane makes and for the same reason: pruning by observed
inactivity requires seeing who is inactive, and seeing that is the graph both planes refuse to
create. What accumulates is carried inside the machine's commitment and proven when needed,
so that the network holds no public timeline of any machine.

Admission runs by selection events at a fixed interval, each admitting a bounded number of
candidates; the interval and the divisor that bounds an event are numbers of Canon. A
candidate is admitted only after a lived continuity period, which Identity defines and which
cannot be bought or parallelized. Where the pressure of pending candidates exceeds a threshold
of the active set, the required continuity rises by the multiplier Canon fixes, to a bounded
maximum — so that a rush of applicants raises the price in time rather than in money.

**The commitment that stands for a machine.** A machine is represented in every consensus
structure by a commitment derived, under the domain Canon names for it, from the public key it
answers with, the suite that key belongs to, and a blinding factor of its own. That commitment
is what a cemented set aggregates over and what a table holds; the key itself is published
nowhere, and the blinding factor keeps two machines from being compared through their key
material.

**One machine per right, and the right names nobody.** Before a candidacy is admitted, its
claimant extinguishes a one-time right to raise a machine, under the domain Canon names for
it. The right is proven by possession and its nullifier names no one, so what the network
learns is that some claimant spent theirs — never whose it was, nor how many machines answer
to one person, because the answer is one and the rule needs no counting to hold it. Without
this a lived continuity period would buy an unbounded fleet: the gate would cost time once
and yield machines forever.

**Invariants of admission:**

- A candidate is admitted only through a selection event; no other path into the active set exists.
- A confirmation carries the identifiers it attests in canonical order and exactly one
  part-nullifier; its first appearance in a window enters the cement, every later one adds
  nothing, and what is held against a machine is only the equivocation the sanction states.
- A candidacy carries the extinguished one-time right to raise a machine; a second candidacy under the same right is refused, and the refusal names nobody.
- The order of candidates within an event follows the canonical sort key derived from the cemented aggregate; no participant chooses it.
- The number admitted by one event never exceeds the bound Canon fixes.
- A candidacy that is not admitted expires after the period Canon fixes and leaves no record.

## The attestation of presence

A machine attests under a key nobody can join to it: the one-time answering key of the window,
derived from the machine's own secret under the domain Canon names, unpublished until first used.
That is what keeps the pulse of a window from being a roll call. It is also what would let a
fabricator draw keypairs until one of them clears the round threshold, since a key nobody can join
to a machine is a key nobody can refuse either. The attestation of presence is what closes that,
and it is the fourth description the network accepts proofs under.

**What it asserts.** That the key the attestation carries is derived from the secret of a machine
whose naming half stands in the tree of admitted machines, and that the part-nullifier the
attestation carries is derived from that same secret and that window — one absorption of the secret
and no second, for the reason every derivation of this set gives: a circuit reading a secret twice
is a circuit where the two readings may differ. It asserts nothing about which machine, nothing
about where in the tree, and nothing about any other window.

**What it publishes.** The root of the tree of admitted machines it answers against, the digest of
the answering key under the domain Canon names, the part-nullifier, and the window. The position of the leaf, the secret, the naming half and
the path stay inside. Two attestations of one machine in two windows share no published value but
the root, and the root is common to every machine — so nothing joins a machine to itself across
windows, which is the property the one-time key exists to hold and which a description publishing
the leaf would destroy.

**Why no description already frozen stands in its place.** The admission binds no answering key, and
its public input carries the nullifier of a redemption rather than a key that signs; a machine
reusing its admission proof would publish identical bytes in every window, and identical bytes are
the join that the one-time key is drawn to prevent. The frame proves value and knows no machine.
The window proves the fold of an accumulation and knows no key. A description that asserts a
different statement is a different artifact, and the network accepts proofs under the descriptions
`air_hash` binds and under no others.

**What it costs, and why the cost is the one already paid.** The statement is one walk of the tree
of admitted machines and one absorption of a secret squeezed twice — the same walk the admission
performs and the same two-squeeze derivation a note's key takes. It carries no arithmetic beyond a
window and a position, both of the widths the Decree fixes, and it stands under the bound on the
width the whole scheme is derived from. A machine makes one per window, whatever the count of
chains, which is the duty the confirmation already bore — and the description stands at a height
of its own, below the frame's, which Canon derives with the length of its proof beside it: the
duty of every window is priced by its own statement, not by the tallest circuit of the protocol.

**Its identifier, and where it stands.** `air_hash` binds the descriptions of this network in the
order the planes stand, the presence among them, and Canon freezes their identifiers, their order
and their heights. An identifier frozen before the
thing it names has run would be a number that measures nothing, so this one was offered only after
one presence was proven and verified end to end — and what this document states is the statement it
asserts, so that two implementations write one circuit rather than two that agree in prose.

**Invariants of the attestation of presence:**

- A heavy attestation carries a proof under the description of the presence, and an attestation carrying any other proof is refused.
- The public input of that proof is the root of the tree of admitted machines, the digest of the answering key, the part-nullifier and the window, in that order, and nothing else; a verifier computes that digest from the key the attestation carries and refuses a proof standing against any other.
- The root it answers against is the root of admitted machines the cemented state of the window before carries; a proof against any other root is refused.
- The part-nullifier comes of the half of the machine's secret that spends, taken with the window under the domain Canon names; that half and the half that names the machine in the tree of admitted machines come of one absorption of the secret, squeezed twice, so a circuit reads the secret once.
- A light attestation carries no proof and is valid only where a heavy one under the same answering key stands published for the same window, whose proof it inherits.

## Presence is witnessed and never self-declared

Presence in a window is counted when, and only when, the network has witnessed it: a machine whose
attestation did not enter the cement of that window is not living in it, whatever work it performed
locally. Self-declared presence weighs nothing, and the rule takes no exception — not for the
opening cohort, which witnesses itself by the same quorum, and not for a part of a split, which
witnesses itself by the rule the way back states.

**The witness is the quorum of the window, and never a count of witnesses.** What stands as
testimony is the cement opening to a sum of distinct standing that meets the quorum share of the
committed total. There is no separate tally of who saw whom and no threshold over such a tally, and
the reason is that a tally of that kind is subjective: how many machines happened to receive one
machine's attestation before a window closed depends on the order of delivery, and two honest
verifiers would count differently. A quorum is one collective act — it is either gathered or it is
not, and every verifier reads the same bytes of it.

**The set of the living is therefore derived and never observed.** It is read off the cement: the
part-nullifiers that entered it, each once, are the machines that lived in that window. From that
the count of the living follows deterministically, and with it the divisor of the shares — which is
why the count is a quantity the window's proof computes rather than a quantity anyone publishes or
polls. Nothing observes absence and nothing needs to: a machine that did not enter the cement takes
no share of that window, and its term runs out in its own time by the rule of presence and
admission.

**What this refuses, named rather than implied.** A rule that counted a machine as living because it
answered on the wire, because a neighbour saw it, or because it was reachable at the moment a window
closed. Each of those is an observation and not a testimony: reachability is bought with sockets and
bytes rather than with anything that cannot be multiplied, so a thousand processes on one machine
would answer as a thousand living machines and take a thousand shares. What cannot be multiplied is
a place in the tree of admitted machines, which costs a lived continuity period and a one-time right
to raise a machine, and admission to which runs at the bounded rate a selection event fixes.

**The honest boundary, stated rather than claimed away.** Common ownership of several machines is
not detected by this protocol and this protocol does not undertake to detect it. What bounds it is
price and not detection, and the price is time: every claimant passes the continuity gate before a
candidacy stands, every admission spends a one-time right that names nobody, and the rate of
admission is bounded per event. A barrier of time rather than of money is the choice this set makes
everywhere, and it is the choice here.

**Invariants of witnessed presence:**

- A machine is living in a window when its part-nullifier entered the cement of that window, and by no other condition.
- The count of the living is derived from the cement and is computed inside the window's proof; it is never published, polled or observed.
- No count of witnesses, no threshold over such a count, and no measure of reachability enters the definition of the living.
- The opening cohort and a resuming part of a split witness themselves by the same quorum; the rule states no exception for either.

## The right to a window's share

Minting creates no note. A window mints a fixed quantity and issues, to each living machine,
a **right to a share** of it. The count of the living is computed inside the window's
proof and never leaves it.

Each living machine holds exactly one right to a share per window, and each such right is extinguished by
exactly one nullifier — so no machine takes its share twice, and no machine takes another's.

Consensus issues the right and states what it is worth: one equal part to every living machine,
with the remainder that does not divide carried forward rather than appropriated. How a right
is proven and consumed is Value's, and is not described here — a second description of one
construction is how two documents come to disagree about it.

## The join

A device that holds nothing joins a network of any age in constant work, and that is a property
of the protocol rather than of anybody's generosity.

**What makes it constant.** Every window has a proof, and that proof asserts — among the
statements the proof section lists — that the proof of the window before it verified. The chain of
transitions therefore collapses into the last proven one: a device that verifies the newest window
proof has verified every window back to Genesis, without holding one of them. Nothing here rests on
the number of windows that passed, so a network a decade old is joined by the same work as one a
day old, and a device that was away for a year catches up by the same act as one that was never
here. What stands between the last proven window and the head is at most `unproven_depth` windows,
and their cement material is retained for exactly this walk: the device verifies each retained
cement as the living did — presence proofs against the admitted root the proven chain gave it, the
fold recomputed — and each step hands it the next proposal's roots on the strength of accountable
finality rather than trust.

**The order of the join.** A joining device holds one thing before it starts: the Genesis State
Hash, which is a number of Canon and is recomputed rather than received.

1. It asks any machine it can reach for the newest **proven** proposal and the proof of its
   window, and it may ask several; both are self-carrying objects, so what is answered is judged
   and never trusted.
2. It verifies that proposal — the length, the signature, the version rule, the ticket proof —
   and the window proof standing for it, which asserts the transition, the quorum and the
   verification of the predecessor's proof, back to the window whose predecessor is Genesis
   itself, where the assertion is that the roots equal the empty roots the Genesis State Hash
   binds; then it walks the retained cements from that window to the head, verifying each as the
   living did.
3. It takes the state it needs against the roots of the head the walk delivered it to — the whole of it, or the
   single leaf a person's own record occupies — by the inclusion proofs Canon lays out, and it
   recomputes every root it takes rather than accepting one.
4. It then follows the beacons of the open window as any machine does, and it is a machine of the
   network from that moment, its own standing beginning where Identity says it begins.

**Two proposals, and no vote.** A device offered two proposals of one height takes the one whose
proof verifies; where both verify, the two are an equivocation and the pair is the evidence the
sanction of this document consumes, so the fork resolves by the rule this document already states
and never by asking who is more numerous.

**Invariants of the join:**

- A joining device verifies one proof and holds no history; what it walks past the proven height is at most `unproven_depth` retained cements, so the work of joining is a constant of the protocol and does not grow with the age of the network.
- The proof of a window asserts that the proof of the window before it verified, and at the first window that assertion is the equality of the roots with the empty roots the Genesis State Hash binds — so the recursion terminates at a number every device computes for itself.
- Every leaf of state a joining device takes is checked against a root the verified proposal carries, by recomputation; a leaf accepted on the word of whoever answered is a defect.
- A device asks several machines and judges every answer alone; nothing in the join is decided by how many answers agree.
- Joining publishes nothing about the joiner but the fact that some device asked, which the ledger of the wire already holds.

## The way back

A chain of this protocol halts rather than parting when more than the complement of the quorum
dies: the survivors hold less standing than the quorum demands of a total that still counts the
dead, so no window closes. Nothing about that is a defect — parting would be worse — but a network
that halts and does not resume is a network that ended, and the rule by which it comes back stands
here.

**What the dead take with them, and what they cannot.** Membership lapses by a term counted in
windows, and windows stop with the chain, so the weight that died stays in the denominator and the
clock that would clear it is the one the dead stopped. What keeps moving is the round: a round
advances on a valid attestation and on no count, no measure and no clock, so a surviving part can
still count. The rule is therefore counted in rounds and in nothing else, and it takes no timeout,
no wall clock and no observation of who fell silent — the three things this document refuses
everywhere else.

**The denominator falls, and nothing is taken from anyone.** After the open window has run
`recovery_onset_multiple` times the derived count of rounds, the share of the committed total a
cement must reach begins to fall, by equal steps over one further count of that size, from the
quorum the Decree names to the floor below. No machine loses standing, no membership is revoked
and no silence is judged: what moves is the bar, and it moves because the window itself has
manifested that the population it was measured against is not there. **This is not a sanction and
carries none of a sanction's requirements** — there is nothing to prove against anybody, because
nothing is being done to anybody.

**The floor is strictly more than half, and it is the whole of the anti-fork guarantee.** The share
never falls below one more part than half of the committed total. Two disjoint parts cannot each
hold more than half of one total, so at most one part of any split ever resumes, whatever order the
parts are driven in and whether or not they can see each other. The floor is applied last and by
name: at exactly half, two parts of an even split would both qualify and the halt would have become
a fork, which is the one outcome this rule exists to make impossible.

**Where no part qualifies, the restart is canonical rather than negotiated.** A network that has
lost more than half of its standing has no part entitled to resume, and the chain does not come
back by agreement among whoever is left. After a further count of that size with no cement, a
restart is admitted: its first window binds the identifier and the roots of the head that closed,
and takes as its denominator the standing that window itself manifests rather than the total the
dead were counted in. Recovery is then a verification — anyone checks the old head's proof, that
the restart names it, and that the restart met its own quorum over its own manifested total — and
never a negotiation among survivors. The entitled runners of a restart are the entitled of the
halted window, by the standby order every machine already computes, so nobody appoints anybody.

**The two prices, stated here rather than discovered.** Both are real and neither is hidden.

*Finality does not reach across a fall.* Two quorums taken at two different shares of the total
need not intersect in a third of standing, so the self-evidencing sanction of a double answer — the
whole of what makes finality accountable — has no evidence to work on across that boundary. Below
the quorum the Decree names, a cement is a cement of a smaller share and the set says so instead of
implying the guarantee it no longer gives. A machine that verified a cement still never abandons
it; what weakens is the proof that two cements of one height imply a third of standing convicting
itself.

*A part between half and the quorum gains what it did not have.* A part holding more than half but
less than the quorum cannot close a window today and can close one after the fall. That is the
whole of what resumability costs: the rule cannot tell a majority that survived from a majority
that excluded the rest, because telling them apart requires seeing who is absent, which is the
observation this protocol does not make anywhere. What bounds it is the price of the wait — ten
derived counts of rounds is a window running an order longer than any the tail bound admits — and
the floor, which keeps a minority out entirely.

**The integer form.**

```
onset(target_rounds, recovery_onset_multiple) = recovery_onset_multiple x target_rounds
floor_num(confirmation_quorum_den)            = confirmation_quorum_den / 2 + 1

resume_share_num(r):
  r <= onset                     ->  confirmation_quorum_num
  r >= onset + target_rounds     ->  floor_num
  otherwise                      ->  confirmation_quorum_num
                                     - (confirmation_quorum_num - floor_num)
                                       x (r - onset) / target_rounds
                                     # unsigned, division toward zero

closes(cemented, total, r) = cemented x confirmation_quorum_den
                             >= resume_share_num(r) x total
restart_admitted(r)        = r >= onset + 2 x target_rounds
```

`r` is the count of rounds the open window has run, summed over its chains, which every machine
holds from the beacon chain it already verifies. Every operand is unsigned, the multiplication
precedes the division, the division truncates toward zero, and the floor is applied by name and
last — so two implementations agree bit for bit and neither reaches a share at which a split
resumes twice.

**Invariants of the way back:**

- The share is a function of the count of rounds and of rows of the Decree alone; no clock, no
  measurement and no observation of absence enters it, and a machine that merely fell silent is
  neither named nor charged.
- The share never falls below one more part than half of the committed total, and the floor is
  applied last: two parts of one split never both close, whatever order they are driven in.
- The fall takes nothing from anyone: no standing is lowered, no membership revoked, no right
  extinguished. What moves is the bar a cement is measured against.
- A restart binds the identifier and the roots of the head that closed and re-bases its denominator
  on the standing it manifests; a chain that opens without naming the head it follows is not a
  restart of this chain but another chain.
- Across a fall of the share, two cements of one height no longer imply a third of standing
  equivocating, and the sanction has no evidence there; the set states this rather than carrying
  the guarantee past the boundary where it holds.
- The circuit of a window asserts the cement against the share this rule gives at the round the
  proposal names, so the rule is bound by the artifact and not by the good behaviour of a runner.

## The cold start

The first window is an empty literal with no operators. The first candidate is admitted by a
selection event while the set of machines is empty and the continuity gate therefore does not
apply, and it finalizes its own chain while the committee consists of itself alone.

## Observability ledger

| Quantity | Status |
|---|---|
| the coordinate of a window | closed by construction: it is the point of the whole layer, it names no one, and it is one number for the network |
| who ran a window | closed: the runner is nameless under a one-time key, and the ticket proof of its proposal asserts clearing without the ticket, the secret or the machine |
| the moment the proof of a window arrives | **deliberately observable**: it is what the depth bound reads, it is a property of the network's proving capacity as a whole, the object is unsigned and carried as every object is, and it names nobody |
| the depth of windows standing without their proofs | **deliberately observable**: it is the observable of the bound the Decree names, a number about the network and about no machine |
| how many machines are living | closed: the count is computed inside the window's proof and never leaves it |
| the standing of a machine | closed: standing rests under a commitment and takes no part in the draw |
| the presence of a machine over time | closed: presence is carried inside a commitment and proven, so no public timeline of a machine exists |
| an equivocation between two closings of one height | **deliberately observable**: the pair of attestations under one part-nullifier and two proposal identifiers is exactly the evidence a sanction requires, and it names no one |
| that a machine was admitted in a selection event | **deliberately observable**: admission adds a commitment about a machine and names no owner, no address and no person; it is what the bound per event is enforced against |
| the thresholds of the draw and of the round | **deliberately observable**: each is a quantity about the network and about no machine |
| the count of rounds in a window | **deliberately observable**: it is the coverage theorem's check, it stands at the derived target wherever the crowd of a round is the admitted through the divisor and falls below it where the floor of the crowd binds, so what it carries is the count of the **admitted** — already in the open at every admission — and never the count of the living, and it names nobody |
| the lived duration of a window | **observable**: it is the echo of committees drawn like the population — a property of the geography of the living as a whole, from which no machine is derivable |
| the count of published attestations | **observable, and named so the leak has a denominator**: it is a noisy bound on the scale of the living; the exact count never leaves the window's proof |
| the eligibility of a machine for the remaining rounds of a window, after its first attestation | **observable to whoever links its key, and closed by two walls, of which the second is the load-bearing one**: the key names no address and [I-16] closes the link; the exposure then lasts to the cement, which is hundreds of rounds, so brevity is not a defence and is not claimed as one. What defends is redundancy — a round needs any one echo of a rolling fresh draw of one in `committee_divisor`, so silencing the pulse means silencing a fresh random share of a hidden population every round on every chain, a share no attacker can aim at |
| that some machine answered at some address | **a named physical prohibition**: answering is observable at the wire; Network holds what bounds it |

## Conformance set

An implementation conforms to this document when all of the following hold.

1. It advances a round only on a valid attestation — eligibility checked natively against the round threshold over the part-nullifier the attestation carries, the signature under the asserted suite, the proof of presence verified for a heavy attestation against the digest of the key that signed it, and its key's published heavy held for a light one — links every beacon to its predecessor by hash, folds each part-nullifier's standing into the cement state at first appearance only, and closes a window only on the cement of its predecessor, never on a count, a measure or a clock.
2. It computes eligibility from the nullifier of its part in that window, the cemented aggregate of the window two before and the pair of chain and round, under the domain Canon names, compared unsigned and big-endian; it attests every valid version of a round it sees, and presents one round nullifier per beacon.
3. It computes the round threshold from the count of admitted machines and the count of chains in force by the rule of Canon — the crowd floored, then the width divided by the admitted, the floor of the crowd applied before the division and the width after it — and reproduces the frozen vectors.
4. It takes the identifier of a proposal over the deterministic fields alone, verifies a ticket proof in the proposal and a window proof apart from it, retains the cement material of a window until that window's proof stands, and opens no window past the unproven depth the Decree bounds.
5. It finalizes a window only on confirmations reaching the quorum, verifying the roots and the control set — the canonically admitted objects that change who runs windows — by independent recomputation rather than by trust.
6. It resolves two clearings by the smaller proposal identifier, read unsigned and big-endian, and walks the cascade in the standby order Canon derives — the ascending order of the cascade key over the commitments of the active set — running the entitled parallel versions from the window's first round and closing on the senior completed cement.
7. It admits a candidate only through a selection event, in the canonical order, within the bound, and only after the lived continuity period Identity defines.
8. It issues one equal right per living machine per window, carries the indivisible remainder forward, and never derives the count of the living from anything the window publishes.
9. It publishes of an admission the commitment that stands for the machine — derived under the domain Canon names from the answering key, its suite and a blinding factor — and nothing that names an owner, an address or a person.
10. It refuses a candidacy whose one-time right to raise a machine is already extinguished, and it derives that right under the domain Canon names.
11. It disregards, for the window in which a proposal was rejected, the ticket of the machine that published it — and restores it for the next window, because the loss is of duty and never of standing.
12. It refuses a repeated round nullifier under one beacon in silence, holds as evidence against a machine only one part-nullifier under two different proposal identifiers of one height, extinguishes that right without issuing its share, applies the refusal by the canonical order of the window, and accepts no other evidence.
13. It treats a cemented window as final: it never abandons a cement it verified, it resolves nothing by chain length within one set of rules, and it discards beacons, attestations and the evidence of an equivocation with the cement that closes the challenge.
14. It derives a ticket from its own secret and the aggregate of the window two before, compares unsigned and big-endian against the threshold of the draw from state, and publishes no ticket.
15. It recomputes the threshold of the draw by the integer rule of Canon over the windows of the period cleared, with the damping and the bound of one step, and reproduces the frozen vectors.
16. It joins by verifying the proof of one proposal — whose assertions reach Genesis through the verification of each predecessor's proof — takes every leaf of state against the roots that proposal carries by recomputation, holds no history to do it, and resolves two proposals of one height by which proof verifies rather than by how many machines say so.
