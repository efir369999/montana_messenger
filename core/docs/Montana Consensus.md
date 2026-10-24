# Montana — Consensus

**Version:** 7.0.0

Consensus holds the TimeChain and its movement: how a window advances, who runs it, how it is cemented,
how a machine enters the set that runs windows, and how the right to a window's share is
issued. It holds no number — Canon holds those — and no note, no record of a person and no pipe.

## Scope

**In scope.** The TimeChain itself — what it is, what identifies it, what one link is, what
advances it and what it rests on; the canonical order and its properties; the layers of time; the round of a
chain and the beacon it turns on; the parallel chains of a window; the chain of cemented
windows and the presence of a machine; the runner's draw, its threshold and the
recomputation of that threshold; the committee and the quorum; the closing of a window, the agreement on what it decided
and its finality; the cascade of the beacon; the admission of machines; the issue of the right
to a window's share; the cold start.

**Not in scope.** Values, layouts and vectors — Canon. Notes, proofs and transfers — Value.
Records of people, keys and identity operations — Identity. Delivery — Network. The invariants
themselves — Constitution.

## The TimeChain

**The TimeChain is the sequence of decided windows.** That is the whole of the definition, and
every other name for it in these documents is this one: the clock of Montana, the canonical order
of events and the chain a device joins are the TimeChain seen from three sides, not three objects.
It is a sequence because each window names its predecessor; it is of decided windows because a
window enters it by the decision of the population that ran the window after it, and by nothing
else.

**What identifies it.** The TimeChain is identified by its head, and its head is the identifier of
the newest decided proposal — the value Canon derives for a signed object of that class, over the
scope that proposal states. Its coordinate is the height that proposal carries. Nothing further is
derived for it and nothing needs to be: a chain whose links are identified needs no identifier of
its own, and a second value standing for the whole would be a second place for what the head
already says.

**One link.** A window is a run of consecutive rounds on each of its chains, and what it leaves
behind is one proposal: the height, the identifier of the proposal of the window before, the roots
of state, the roll of what it applied, the count of the admitted, the cement of its living — among
whom its predecessor was decided — the census the standing of the electorate is counted over, and
the proof that its runner's ticket cleared. The link from one window to the next is that
identifier and nothing else — no timestamp, no sequence number of anyone's making, no signature of
an authority, no number a machine could choose. A proposal naming anything else is not of this
chain.

**What advances it.** The rounds of a window gather its living machines into its cement and carry
what each of them pledges of the name of its predecessor. The moment the agreement of the window
decides that name — closing pledges of distinct machines of the electorate on it reaching the quorum
share, of their count and of the votes their standing draws where that standing is wide enough to be
sampled — beside a cement reaching the same share, the predecessor is final, the window stops
admitting traffic and its runner assembles the proposal, and the next window opens — the three at
once, by the rule the section on the pulse states. Nothing else closes a window: no count of rounds, no measure of
duration, no clock.

**What it is not.** It is not a chain of iterations of a function: no work, no delay and no count
of hashes stands between one window and the next, and nothing in the set fixes how long a window
takes. It is not a ledger ordered by time: no quantity taken from any clock outside the protocol
enters any object of it, and a machine that has not seen the network does not know the current
window. It is not the opinion of a majority: two proposals of one height are separated by which
certificate verifies, never by which is longer or which is held by more machines, and length
decides nothing within one set of rules.

**What its pace rests on.** The length of a window is a theorem rather than a number — the count of
rounds at which the share of the electorate no round has touched falls to the complement of the
quorum — and the
floor under a round is the echo of the population across the geography it lives in. No processor,
no fleet and no width of silicon shortens it. Both are stated where they are derived, in the
section on the pulse and in Canon.

**When it cannot advance, it waits.** A quorum that cannot be reached closes no window. Rounds go
on, the cement accumulates and stops short of the share, and nothing else happens — no timeout
lowers the quorum and no reduced quorum stands to fall back to, because either would be a clock or a
majority and this document admits neither. Machines that took two names for one window are not that
case: the share is there, divided between the names, and their agreement runs a further attempt,
whose waits are conduct and move no rule of acceptance. A network parted therefore does not become two chains:
a part holding the quorum share carries the chain alone, and a part holding less carries nothing,
publishes nothing and waits. When the parts meet, the machines that closed nothing verify the
decisions they missed and are of the chain again — a decision is verified rather than voted on a
second time, so rejoining asks nobody's permission and revises nothing. What is traded away here is stated rather
than hidden: the protocol will stop before it will fork, and a wait is what a network under a
partition gets in place of a false answer.

**What a stranger holds of it.** A device that holds nothing starts from an anchor its operator
handed it — the proposals of two consecutive final windows — and walks the retained certificates
from there to the head, verifying each as the living did; it is then of this chain. The trust in the
anchor is explicit and is the trust a device places in the operator who starts it, the same trust
the opening cohort rests on. The join states the procedure and the cold start states the first
window.

**Invariants of the TimeChain:**

- Every window but the first names its predecessor by the identifier of that predecessor's proposal, and the first names the Genesis State Hash; a proposal naming anything else belongs to another chain.
- The coordinate of a window is its height, and one height carries one meaning for every participant.
- A window closes only on the decision of its agreement — closing pledges of distinct machines of the electorate on one name of its predecessor, to the quorum share of its count and carrying the votes of their standing to the quorum share of the committee that standing draws — beside a cement reaching the same share, by the rules of the pulse and of the agreement; no length, no measure and no clock closes it.
- No quantity from outside the protocol — a clock, a date, a duration — enters any object of the chain, and none of its rules reads one.
- A machine that verified a cement never leaves it, and no longer chain within one set of rules overrides it.
- A quorum that cannot be reached closes no window: the chain waits, and a part of a parted network holding less than the quorum share carries no chain of its own.
- The chain depends on nothing downstream of it: the presence of machines and the records of people rest on the chain, and a failure of either stops nothing in it.
- What is recomputed is recomputed from the chain alone: no participant asks another what a coordinate means.

## The canonical order

The primary product of the protocol is a canonical order of events. Every window is a run of
consecutive rounds on each of its chains, and it closes on the decision of its predecessor: no
count of rounds is fixed anywhere, because the length of a window is a consequence of
coverage, and Canon derives its expectation rather than choosing it. A decided window
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

**The beacon** of a round is seven fields: the window, the chain index, the round index, the
identifier of the preceding beacon of that chain — or, for round zero, of the proposal of
the window two before, the proposal that fixed the electorate of this window and is final when it
opens — and the running cement: the aggregate, under the domain Canon names for a cemented set,
over the part-nullifiers of every distinct machine that has attested this window on this chain so
far, whatever name its attestation pledges, beside their count and beside the votes the ballots of
those parts cast. Its identifier is the hash of its
serialization under the beacon domain Canon names. It carries no list of members and no key: the
beacon is the pulse and the ledger of the cement, and nothing else.

**Why round zero stands on the proposal two before.** The rounds of a window are the pulse of
everyone in it, and what every machine of the window holds alike when it opens is the proposal that
fixed its electorate: the proposal of the window before is what this window decides, and two
machines may have taken two names for it. A pulse standing on that name would part with the names —
two pulses, each gathering the living of its half — and the cement the next proposal carries would
part with them. Standing on the proposal two before, the pulse is one whatever the window decides,
and the decision is carried by what the attestations pledge, which the agreement counts.

**Eligibility to attest is drawn, and drawn from what already exists.** A machine is eligible
for a round when the hash, under the round-attestation domain Canon names, of the nullifier of its
part in that window together with the cemented aggregate of the window two before and
the pair of chain and round clears the round threshold. **That threshold is not held by anybody's
observation: it is computed** from the count of machines the electorate of the window carries and
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
the frame, the ticket and the admission are; what it asserts, what it publishes and why no other
description can stand in its place are stated in the section that owes them.

**Why the draw reads the nullifier and not the key.** Eligibility must be drawn from a value that
is fixed by the machine's secret and the window rather than chosen, or a machine draws candidates
until one clears. A one-time key is fixed that way, but no circuit can say so: the key comes of a
lattice key generation, and asserting that generation inside a proof costs orders more than the
whole statement around it. The part-nullifier is fixed the same way and is a value of the family
the circuits speak, so the proof asserts it in the arithmetic it already has. The key then chooses
nothing — it signs, and the proof binds it by its digest so that no one lifts a proof from one
attestation onto another.

**The attestation is the confirmation, and heavy exactly once.** It attests exactly two
identifiers, ascending: the beacon of its round and the name its machine took of the proposal of
the window before — its pledge of attempt zero, which the agreement counts. It carries
the machine's part-nullifier of the window and one round nullifier, derived from the machine's
secret and the attested beacon's identifier. A machine's first attestation of a window carries the
full confirmation — the proof that binds the answering key to the secret of a machine the
electorate admits — and it is what enters the cement. Every later attestation of the same machine
in the same window is light: the same object without the proof, valid because its key already stood
proven in the heavy one every verifier holds, and carrying the name that heavy pledged: it moves the
pulse and pledges nothing. Canon holds both layouts and the one length of each.
One signature therefore serves two duties — the pulse of its round and, once, the cement of the
window with the pledge of its predecessor — and the heavy duty falls on a machine about once per window, whatever the count
of chains: exactly the confirmation duty it already bears. Where the standing of the electorate is
sampled and a machine's own standing drew a vote, its ballot stands at the points of the round of
its heavy attestation beside it; the section on the standing states what a ballot is.

**Closure, and the canonical cement.** The runner of a chain closes a round on the first valid
attestation it holds — validity is the native eligibility check, the signature under the asserted
suite, and for a heavy attestation its proof against the root of the electorate, for a light one
the presence of its key's proven heavy — and publishes the next beacon. The cement moves only by
the canonical rule: the heavy attestations of the window are its members, whatever name they
pledge, each part-nullifier once in the life of the window, and the state a beacon carries is the aggregate over the members held so
far beside their count. A verifier recomputes both from the attestations it holds and refuses a
beacon whose state is not that pair; two verifiers holding one set of attestations in two arrival
orders reach one aggregate, because the aggregate sorts what it folds. The one freedom left to a
runner is when to include, never what to invent. A round cannot close before an eligible machine
has heard the beacon and its answer has returned: the turn is made of waiting, and the waiting is
the clock. Nothing measures it; the protocol learns that the echo returned, never how long it flew.

**The nullifiers, and what each bounds.** The round nullifier bounds a machine to one
attestation per beacon: a second presentation of the same value is refused in silence, a
deduplication and not a sanction. The part-nullifier bounds a machine to one entry in the cement
of a window: its first appearance enters the machine into the cement, and every later appearance —
the machine attesting further rounds — adds nothing and is lawful. What a sanction rests on is one
part-nullifier under two pledges the agreement states as contradicting, and the sanction's own
section states them.

**Invariants of the round:**

- A beacon carries the window, the chain index, the round index, the identifier of its predecessor — the proposal of the window two before for round zero — the cement aggregate, the cement count and the cement votes, and nothing else; its identifier is taken under the beacon domain Canon names.
- Eligibility is computed from the part-nullifier of the window, the cemented aggregate of the window two before and the pair of chain and round, under the domain Canon names, compared unsigned and big-endian over the full width; nothing in the preimage is anyone's to choose, and every atom of it is one a proof of presence asserts or a cemented value every verifier holds.
- An attestation attests exactly two identifiers, ascending: the beacon of its round and the name its machine took of the proposal of the window before, which is its pledge of attempt zero; a light attestation carries the name its heavy pledged and pledges nothing.
- A machine's first attestation of a window is heavy and enters the cement; every later one is light and enters only the pulse; a light attestation is valid only where a heavy one under the same answering key stands published for the same window.
- The cement state of a beacon is the aggregate over the part-nullifiers of the published heavy attestations, whatever name they pledge, each at most once, with the window as its context, beside their count; a beacon whose state is not that pair is refused. Its votes are refused where they exceed what the verified ballots of those parts cast, and taken where they fall short of it, which only delays the close of the version carrying them.
- A round advances only on a valid attestation; no count, no measure and no clock closes it.
- A beacon, the attestations answering it and the ballots beside them stand at the points of their round, a proposal and its roll at the points of its window, and a pledge at the points of the window it is made in, so an attester reaches a runner it cannot name and a proposal reaches everyone; Network holds how they travel and Canon derives the points.
- A repeated round nullifier under one beacon is refused in silence and is never evidence.

## The pulse and the close of a window

The window has no length parameter. The rounds of a window do two things at once: their
beacons pin the slots that carry the traffic of the window, and their attestations gather the
living machines of the window into its cement and pledge the name of its predecessor. The moment
the agreement decides that name and a beacon's cement names distinct machines of the electorate to
the quorum share of their count with the votes their standing drew at the quorum share of the
committee, one event does three things: the predecessor is final, by the rules the agreement and
the Finality section state; the window stops admitting traffic and its runner assembles the
proposal from what the slots carried; the next window opens, its rounds now gathering its own
cement and pledging the name of this one.

**The electorate of a window is fixed before the window opens.** It is the set of admitted
machines the proposal of the window two before carries — the root of their tree and their count,
and the census their standing is counted over — because that proposal is final when the window
opens, whereas the proposal of the window before is what the window's own rounds are deciding. For the first two windows of a network it is the
opening cohort an operator handed the machine, which the proposal of window zero must carry.
Membership changes take effect only through a final proposal and move no electorate of an open
window, which is the rule the way back states.

**The close is a count every verifier makes.** A heavy attestation is
verified natively as it arrives — its eligibility against the round threshold, its signature under
the key it carries, its proof of presence against the root of the electorate — and a part-nullifier
that verified enters the cement once, whatever name it pledges. The cement names the distinct
machines of the electorate that attested; it reaches the quorum when their count, multiplied by the
denominator of the quorum, reaches the count of the electorate multiplied by its numerator — the
integer form of Canon — and the votes their ballots cast reach the same share of the committee the
electorate's standing draws. The same two counts, taken over the closing pledges of one attempt on
one name, are the decision of the agreement, and it is the decision that makes the predecessor
final. Every machine of the window makes all of them from what it holds, and a runner is one of
them: it assembles the proposal when the decision and the cement both stand and not before, and a
proposal assembled below either is refused by every machine that counts. **The count is the half that makes finality safe, and the votes the half
that makes it weigh time.** A sum of hidden weights proven in one proof needs a witness nobody holds,
which the certificate section derives; what stands in its place is a sum of public counts each
machine proves for itself — the votes its own standing drew — and the count of machines beside it,
so the safety of a close rests on the count exactly as before, and the votes can only refuse a close
the count would admit.

**The beacon a window closes on.** The cement a machine closes on is the one a beacon carries, so that
the machines closing a window close it on one value wherever they can. A machine closes the window,
once its agreement has decided, on a beacon of its chain whose carried count reaches the quorum share
of the electorate and whose carried votes reach the quorum share of the committee, which it
reconciled — the pair it recomputed from the heavy
attestations it held was that beacon's pair, and the votes stand within what the ballots it verified
of those parts cast — and which a verified attestation answered. That beacon is the final beacon of the window, and its pair is the cement of
the window: the proposal carries it, the share of every living machine divides the mint by its
count, and the draw of the window two on reads its aggregate. An attestation a machine gathered after
the final beacon was published enters no proposal and no share of this window; the window after it
cements its own. The cement is the living of the window whatever names they pledged, so the share
of a window does not part with the names, and a machine that pledged a name the agreement did not
decide lived the window as fully as one that pledged the decided one. Every machine runs a version of the chain where every one of them clears the draw,
and a machine advances on the versions it holds, so two machines may close one window on two beacons
of two branches carrying one pair: what they decided is the pair, and the beacon is the evidence of
where it was decided, which the identifier of the proposal leaves outside the name. The votes are
evidence of the same kind: two runners holding one cement may have verified its ballots at
different moments and carry two tallies, so the tally stands in the beacon and in no field of the
proposal, and the decision is the pair whichever tally reached the committee.

**What this leaves in the open, said rather than implied.** The count of the living of a window is
the count of its cement, and it is public, as the cement is; the share of the window's mint is the
mint divided by it. What stays closed is **which** machines lived and **what** any of them weighs: a
part-nullifier names nobody and joins to nothing across windows, the proof of presence discloses
nothing of the secret it derives from — the section on the certificate states what hides it — and a
ballot discloses a count of votes and nothing of the standing that drew them.

**A residue the window never reached costs a window of latency and nothing else.** A window may
close before every residue of its chain has come round, and the senders holding the residues above
the close simply did not emit — nothing of theirs was published, so nothing of theirs repeats. In
the next window each derives a fresh ephemeral identity and a fresh slot by the ordinary rule and
sends there. No rule of re-placement is needed and none exists: what was never published cannot be
published twice, and the case that would need a rule — a frame that did travel and did not arrive —
is answered by the erasure code and never by a repeat.

**The length of a window is a theorem, not a number.** Eligibility is an expected share per
machine per round, drawn independently, so the expected share of the electorate that no round has
yet touched falls geometrically with the count of rounds. The smallest count at which it
falls to the complement of the quorum is `target_rounds`, a derived number of Canon, frozen
there with its boundary check and with the tail bound on what the variance touches. Where the crowd
of a round is the electorate through the divisor the expectation is exactly that count and depends on
nothing but the two frozen numbers behind it; where the floor of the crowd binds instead, the
expectation falls with the count of the electorate and a window closes sooner.

**The realized length concentrates with the population, and the set says so rather than promising
otherwise.** Each round is a sum of independent draws over the living, so the spread of one window
narrows as their number grows: at a thousand machines a window sits within a tenth of its
expectation, while at a handful every machine is drawn every round and a window closes in its
first ones — at a single machine in the round it answers. Nothing downstream rests
on the concentration of a single window: the tail bound above holds at every population including
one, and every constant denominated in windows spans at least `selection_interval` of them, where
the averaging lemma bounds the deviation of the sum. What the young network gets is windows of
uneven length, which costs it nothing it can observe; what it does not get is a promise of evenness
the mathematics does not make.

**Pace is pinned to the speed of light.** A round's duration is one echo across a sample scattered
like the population; a window is `target_rounds` echoes wherever the crowd of a round is the
electorate through the divisor, and fewer where the floor of the crowd binds; the floor under both is
the speed of light over the geography of the living. No processor, no width of silicon and no fleet
shortens a return from another continent. The remaining headroom — routes straightening
toward geodesics, propagation approaching the speed of light — is a small constant factor
with a hard floor. And the pace is the population's, not any machine's: a runner that spins
beacons without honest attestations advances nothing, because every round waits for an
eligible machine's echo, and the cement waits for the quorum of everyone.

**Invariants of the pulse and the close:**

- A window closes only on the decision of its agreement on the name of its predecessor and on a cement naming distinct machines of the electorate to the quorum share of the electorate's count and carrying the votes of their standing to the quorum share of the committee; no count of rounds, no measure and no clock closes it.
- The electorate of a window is the admitted set the proposal of the window two before carries, root, count and census; it is fixed before the window opens and nothing of the window moves it.
- A window closes, once its agreement has decided, on its final beacon: a beacon of its chain whose carried count reaches the quorum share of the electorate and whose carried votes reach the quorum share of the committee, reconciled by the closing machine against the heavy attestations and the ballots it held and answered by a verified attestation; that beacon's pair is the cement of the window — its living, whatever names they pledged — and the proposal and the share of every living machine read it.
- Every heavy attestation is verified natively before its part enters the cement: eligibility, signature and the proof of presence against the root of the electorate; a part the electorate does not hold enters no cement.
- The count of rounds a window took is public and names nobody; it is a function of the count of the electorate, which its proposal carries in the open, and so is the count of the living, which is the count of the cement.
- The round threshold is read out of the count of the electorate and the count of chains in force, by the rule of Canon; no observation, no count of rounds and no history enters it, and a chain of one machine and a chain of a million each compute theirs from state alone.
- A machine retains the heavy attestations, the ballots, the pledges and the frames of a window, and its proposals with their rolls, at their points for `retained_windows` windows after it closes; the retention is read from held state, and what it bounds is the walk of a device catching up and the replay of a machine that took another name.

## Parallel chains

At every height the schedule of Canon fixes the count of chains: independent beacon chains
run concurrently in every window, each with its own rounds, its own eligibility draws, its
own slot space and its own quota of frames, all accruing the one cement of the
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

- Every chain of a window accrues the one cement of the window; a part-nullifier enters it at most once whatever chain carried the heavy attestation.
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
- Losing it loses the machine's place in the electorate and nothing else: the value a person holds lives under their own secret and is untouched.

## The runner's draw

The draw answers one service question — **who runs this window** — and it answers nothing
about money. The share of a window is divided equally
among the living, and the machine on duty receives the same share as any other.

**A threshold, not a comparison.** Every living machine computes its own ticket at home from
its own secret and the cemented aggregate of the window two before the one being drawn, and
checks it against the threshold of the draw, which is the width at every window: every machine of
the electorate may run, and its ticket says when. It is that aggregate and no other: the aggregate
of the preceding window is still being cemented when the draw must happen and is therefore not
canonically available to everyone, whereas the aggregate two before is fixed in the preceding
proposal and cemented in time. A ticket drawn from any other window is not a variant — it is
a different network. Comparing tickets would require collecting them, and collecting them
would require naming the participants. Nothing is applied for and nothing is announced: the
one that cleared the threshold is revealed by the fact of publishing a window, and its proof
asserts that it cleared without disclosing the ticket, the secret or the machine.

**The ticket carries no weight.** Every machine of the electorate draws against one threshold, so
every living machine has the same chance and the expectation of income equals the share of a
window. What the network holds of "how many of us there are" is the counts a proposal carries in
the open — the admitted, the cement and the census of the standing — and nothing finer: the draw
weighs no machine, and names none. Standing weighs in the close and only there, through the votes
the section on the standing states.

**Two tickets clearing one window.** The draw is a threshold and not a comparison, so nothing
stops two machines from clearing it in one window, and each publishes. Their proposals carry one
identifier: Canon takes it over what the window decided — its predecessor, its roots and its counts —
and never over the beacon a runner closed on or the runner's key, proof or signature, so two runners
that closed on one cement publish one name whichever branch of the versions of a round each closed
on, and either one's bytes are the proposal of the window. Nothing is
compared and nothing is waited for: a machine pledges in attempt zero the identifier it recomputed
from what it verified itself, once it holds one verified proposal under it, and the absence or the
withholding of any one runner moves nothing. Two proposals of one height under two identifiers
decided two different things; a machine pledges in attempt zero only the one it recomputed, and
which of them the chain keeps is decided by the agreement of the window after — whose certificate a
device verifies — and never by a comparison of names.

**Why a draw and not a queue.** A queue in a circle is known years ahead, and every future
runner can be attacked before its turn, in sequence, until the network stops. The aggregate
the ticket is drawn from is cemented by the signatures of honest participants: it is not
computable offline and not enumerable, so the runner becomes known one window before duty
and there is no time to aim. Eligibility to attest a round is drawn the same way at a
faster pulse — from the nullifier of the machine's part in the window and the same cemented
aggregate — so a machine knows its own rounds the moment the aggregate cements, and nobody else
knows them at all.

**What the aggregate is bound to.** The aggregation Canon defines takes a context, and for the
draw that context is the height of the window whose cemented set it aggregates, as an unsigned
eight-byte little-endian integer — which makes it the aggregate the proposal of that window carries
and a machine drawing two windows on reads as it stands — and never an empty value. The distinction
matters twice over: it makes the seed of each window distinct even where two windows cemented the
identical set of signers, and it leaves no choice to an implementer, so two implementations cannot
compute two seeds and elect two runners from one cemented state.

**The lookback.** The aggregate that fixes the draw is that of the window two before the one
being run: its cemented set is fixed in the preceding proposal and canonically cemented by
the end of the current one, so every participant uses one and the same value and verifies the
endpoint with a single hash.

**Grinding.** Choosing a favourable keypair does not help: by the time the aggregate is
public, the keys of everyone who could be in the committee are already fixed, and the
aggregate is built by the rule Canon states for aggregation into a seed, which admits nothing
an author of an object may choose. Canon holds that rule; it is not restated here, because a
restatement is exactly how the two would come to prohibit different things.

### The threshold of the draw, and the order of the runners

The threshold of the draw is the width at every window, and nothing walks it. A runner carries what
the window decided and nothing of its own — the name of the proposal is taken over the decision and
the share falls to every living machine alike — so excluding a machine from running buys only the
bandwidth of its copy, and it costs a window: a threshold below the width leaves windows no ticket
clears, and a window nobody runs closes on nothing. A threshold walked by the windows that cleared
it never leaves the width, since a window closes only through a runner; one read out of state
leaves the windows no ticket clears in need of the runner the width already gives. Canon states the
value and why.

**The order of the runners.** What a lower threshold was for — fewer copies of one proposal — the
ticket gives as an order rather than an exclusion. Before it proves its own proposal a machine waits
the share of its patience its ticket stands at, and takes whatever proposal of its decision stands
verified at the points of the window meanwhile; the machine whose ticket is lowest usually carries
the decision first and alone, and nobody learns whose ticket that was. The wait is a machine's
conduct, not a rule of acceptance: a machine that publishes at once is a copy too many and nothing
worse.

**Invariants of the draw:**

- A ticket is derived from the machine's secret and the cemented aggregate, and from nothing else; it is never published.
- The comparison is unsigned and big-endian over the full width of both quantities.
- The aggregate is that of the window two before; a proposal drawn from any other window is rejected.
- The threshold of the draw is the width at every window; an implementation that lowers it leaves windows no ticket clears.
- The ticket orders who carries a decision first; the wait it sets enters no object and no verification.
- A machine whose proposal the quorum rejected takes no part in the draw of that window; its ticket is disregarded for that window and for no longer.
- Clearing the threshold is asserted by the ticket proof the proposal carries, under the description of the ticket; a proposal that discloses a ticket is malformed.

## Closing a window

**The confirmation of a window.** A machine that has verified a window attests it by publishing
a confirmation: an object carrying the identifiers of what it attests, in the canonical order
Canon fixes for them, and the nullifier of its own part in that window. It is signed under the
one-time key of the window, and the proof of presence it carries binds that key to the secret of a
machine the electorate admits. It names no machine and no owner:
what a reader learns is that a distinct machine of the electorate attested these operations, never
which one. A part-nullifier appearing again for one window adds nothing to the cement and is
lawful; one part-nullifier under two confirmations of one window attesting two different names is
the first of the equivocations the sanction of this document states.

A proposal is final when the agreement of the window after decides its name: closing pledges of
distinct machines of the electorate on it reaching the quorum share of its count, with the ballots
of their parts casting the quorum share of the committee its standing draws; the confirmations are
the pledges of attempt zero the agreement starts from. Every number of it is public and names nobody: the count of parts
against the count the electorate's proposal carries, and the votes against the committee its census
yields; nothing of it is added up in a proof, and each vote is proven by the machine that cast it.

The runner assembles the proposal from what the slots carried, commits the roots of
state and the roll of what it applied, proves its ticket in the proposal itself, and publishes the
proposal with its roll. Verification is independent and
complete: every attestation verified natively as it arrived, every beacon linked by hash to its
predecessor and, at round zero, to the proposal it stands on and cements, the roots recomputed, the
quorum counted, and the **control set** matched against its rule. The
control set of a window is the objects that change who runs windows, and it is exactly three: the
candidacies redeemed at a selection event of that window, the expiry of candidacies that no event
admitted, and the pruning of machines whose membership term ran out. Each is admitted canonically —
by the rule of this document and the order of Canon — and never at a runner's discretion, and a
proposal whose control set differs by one object from the one every verifier recomputes is
refused. Nothing in a proposal is taken on trust.

**When two clear the threshold**, their proposals are one proposal: the identifier is taken over
what the window decided, so no runner grinds a name through the randomness of a proof, and neither a
runner's key nor the beacon it closed on separates two names for one decision. A runner gains nothing by running and loses nothing by
being late: its share is the one it already holds as a living machine, and duty adds no part of a
mint to anyone.

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
rule every verifier recomputes. An objective that cannot be read: the one quantity inclusion
timing could tune is the cemented aggregate, and its consumers are tickets and eligibilities
keyed by other machines' secrets, which the runner cannot evaluate. And a duty that pays
nothing: delaying the crossing delays only the runner's own version while junior versions
complete and take the window — the slots are canonical, so the contents are identical either
way, and duty adds no share.

**The one place a proposer chooses, named.** In an attempt after the first, the name the machines
follow is the one its proposer took, verified by every machine that follows it — its roll replayed —
and not recomputed from what the follower holds. A proposer of a later attempt therefore chooses
when to include exactly as a runner does: what it leaves out applies in no window, and its sender is
told so when the window is decided and sends again. That is a delay of one window, it falls only on
a window whose machines took different names, and the place of a proposer is drawn from what nobody
chooses, so no machine holds it by choice.

**Skin in the game.** A machine whose proposal the quorum rejects loses the duty of that
window and takes no part in its draw. Its share as a living machine is untouched — the share
is equal and does not depend on duty.

## The agreement on what a window decided

**Why one vote does not suffice.** The name of a proposal is taken over what its window decided, and
two inputs of that name are what a machine held as it left the rounds: the final beacon it closed
on, whose pair is the cement, and the frames standing at the points of each round as it left that
round. Nothing makes two machines hold the same. A machine holding one heavy attestation more than a
beacon at the quorum cannot reconcile that beacon and closes on a later one, and a frame that
reaches one machine before it leaves a round and another after it enters one plane and not the
other; so two honest machines may take two names for one window, at any population. A machine
pledges one name of a window in its heavy attestation, and a second name under the same part is an
equivocation, so a single vote never recovers from a split: where no name reaches the quorum, both
halves wait forever on a name the other half never pledges. No rule a machine applies to what it
holds closes this — the smaller identifier among the candidates it has seen, the larger cement, the
first to arrive — because each agrees between two machines only where both saw the same candidates
before they pledged, and nothing bounds when a candidate arrives. It is the problem of agreement
under a bounded fraction of faults and unbounded delays (Lamport, Shostak and Pease, 1982; Dwork,
Lynch and Stockmeyer, 1988), and its known constructions vote more than once. The set takes the one
of Tendermint (Buchman, Kwon and Milosevic, 2018) and runs it in the window after, over the name of
the proposal before, with the pieces Montana already holds: the heavy attestation is its first vote,
the electorate and the quorum are the window's, and every wait is a machine's conduct and enters no
rule of acceptance.

**Where it runs.** The proposal of a window is agreed in the window after it, by the electorate of
that window, in **attempts** numbered from zero. Nothing of the agreement moves the electorate, the
quorum, the round threshold or the pulse of the window it runs in; it adds one object and the rules
of counting it.

**The pledge.** A machine of the window says, in an attempt, which name of the proposal of the window
before it stands behind, and on what: a **pledge** carries the window, the attempt, the name, the
attempt whose quorum it stands on — its `since`, or none — the nullifier of the machine's part in
the window, and the one-time key of the window, under which it is signed. Canon holds its layout and
its one length. A pledge whose `since` is its own attempt is a **closing pledge**: it says that its
machine saw the quorum of that attempt reached on that name. A pledge whose `since` is an earlier
attempt, or none, is an **open pledge**: it says which name its machine stands behind in that
attempt and which earlier quorum, if any, frees it to. The heavy attestation of a window is the open
pledge of attempt zero, standing on none — the name it attests beside the beacon of its round is the
name its machine took — and no other open pledge of attempt zero exists. A pledge is valid only
where a heavy attestation of the same part under the same key stands published for the window, whose
proof of presence binds the key to a machine of the electorate; until that heavy is seen the pledge
stands in escrow, as a light attestation does.

**The quorum of an attempt.** Pledges of one kind, of one attempt and on one name, from distinct
parts of the electorate, reach the quorum when their count reaches the quorum share of the
electorate's count and the votes the ballots of their parts cast reach the quorum share of the
committee — the one integer rule the close reads, `closes_window` of "The way back". Every verifier
counts by two rules, so that no pledge stands on what is not there:

- an open pledge counts only where its `since` is none, or where the open pledges of the attempt it
  names reach the quorum on its name;
- a closing pledge counts only where the open pledges of its own attempt reach the quorum on its
  name.

A part counts once per kind and attempt, at its first appearance; a second pledge of the same kind
and attempt under it on another name is evidence, and a repetition on the same name adds nothing.

**The decision.** A name is **decided** when the closing pledges of one attempt reach the quorum on
it. The decision makes the proposal of the window before final, and it is the event the pulse names
as the close of the window, which stands once the cement of a final beacon stands beside it. Two
names of one window are not both decided while fewer than `Q + Q - T` machines of the electorate
sign against the rules below, which "Finality" proves; and a decision is reached once delivery is
bounded, which the last paragraphs of this section show.

**What a machine holds of the agreement.** Its attempt; its **lock** — the name and the attempt of its
last closing pledge, or none; its **valid name** — the name and the attempt of the newest quorum of
open pledges it holds, or none; and every pledge it made. It keeps all four before it publishes
anything they govern, and through a restart, because a machine that forgot a pledge could sign its
contradiction; it lets them go when the window they govern closes, so what it keeps is one record
per open window and never a history.

**How a machine pledges.** In attempt zero its heavy attestation pledges the name it took, as the pulse
states. Then, in every attempt `a`:

1. **It closes on what it sees.** Holding the open pledges of `a` at the quorum on a name, it
   publishes its closing pledge of `a` on that name, once, and takes that name and `a` as its lock.
2. **It waits on a spoken quorum.** Holding open pledges of `a` from distinct parts of the electorate
   at the quorum share, whatever names they carry, and no name among them at the quorum, it waits
   one span of `a` and enters `a + 1`; holding its own closing pledge of `a` and no decision, it
   waits one span of `a` and enters `a + 1`.
3. **It proposes in the order of its place.** Entering an attempt `a` from one onward, it listens one
   span of `a`, waits then the share of a further span its place in that attempt stands at and,
   unless it holds by then an open pledge of `a` from a part at a lower place, publishes its own: on
   its valid name standing on the attempt of that quorum, or, holding none, on the name it took
   standing on none.
4. **It follows the lowest place.** Two spans of `a` after it entered, it takes the open pledge of `a`
   from the part at the lowest place it holds and pledges the same name on the same `since`, where
   it holds the quorum that `since` names or the `since` is none, where the name is valid to it, and
   where its lock admits it: it holds no lock, or its lock is on that name, or that `since` is at or
   after its lock's attempt. Otherwise it pledges nothing in `a`.
5. **It moves on.** Four spans of `a` after it entered without a decision, it enters `a + 1`; and
   holding pledges of a later attempt from distinct parts of the electorate beyond the share the
   quorum leaves — more than `T - Q` of them, which no faulty set within the bound fills alone — it
   enters that attempt.

A name is **valid to a machine** when it is the name the machine took, or a name the open pledges of
some attempt reach the quorum on, or a name whose roll the machine replayed and found to carry the
roots, the cement and the census of the proposal. The **span** of an attempt is a count of the
machine's own askings that doubles from attempt to attempt; it is conduct, read by no rule of
acceptance, and a machine that waited twice as long reaches the same decisions later.

**The place of a part.** The parts of a window propose, in an attempt, in the ascending order of
their **place**: a hash, under the domain Canon names for it, of the part-nullifier, the cemented aggregate of the
window two before — the aggregate the draw of the window reads — and the attempt, compared unsigned
and big-endian over the full width; Canon, "The round of a chain, in integers", holds the formula.
Nothing in it is anyone's to choose: the part is fixed by the machine's secret and the window, the
aggregate is cemented before the window opens, and the attempt is a count. It is known of a part once
that part's heavy attestation stands, and it names nobody, as the part does. A ticket cannot serve
here: a ticket is published by nobody, so a machine claiming the lowest would be believed by no rule,
and a proposer any machine can impersonate is a proposer a faulty machine always is.

**The roll of a proposal.** A name another machine took is followed only where it is valid to the
follower, and a machine that left the rounds holding other frames or another cement cannot recompute
it from what it holds. So every proposal names what its window applied: its **roll** — the
identifiers of the frames it applied, in the order they applied, then the parts of its cement,
ascending — in one body that stands at the points of its window beside it, for as long as the frames
it names, and whose identifier the proposal carries inside the scope of its name. One body suffices
because both of its counts are bounded before it is read: the frames by the frames a window admits,
the parts by the count of the electorate. A machine checks a roll by replaying it: the frames in
their order over the decided state of the window before, the parts against the heavy attestations of
the window; the roots, the cement and the census it recomputes are the proposal's, or the roll is not
that proposal's. Canon holds its layout and its length.

**When the decision is not the name a machine took.** A machine whose name is not the decided one
takes the decided proposal and its roll, replays the roll over the decided state of the window two
before, and holds what results as the decided state of the window before; it then applies again,
over that state and in their order, the frames of its open window it had applied. A payer learns what
its frame took as the round carrying it leaves — the strength Value names for one echo — and where
a replay moves it, the replay tells it again: the positions its commitments hold in the chain are
those of the decided rolls, and a note is never spent before they stand, since it spends onward only
once the root of its window stands in the horizon of proving.

**Why it decides once delivery is bounded.** Suppose that from some moment every message between two
honest machines arrives within a bound `Δ` no machine knows. A machine behind is drawn into a later
attempt by the pledges of more than `T - Q` parts, among which some honest machine stands, so from
that moment the honest machines enter each attempt within `Δ` of one another; the spans double, so
from some attempt on a span exceeds every multiple of `Δ` the steps above wait on. In such an attempt
the open pledge of the part at the lowest place reaches every honest machine before it follows, and
where that part is honest every honest machine follows one name: the attempt the proposer's valid
name stands on is at or after every honest lock, since the proposer listened a span after it
entered, and the quorum that set a lock had reached its holder before that holder entered; the name is valid to every follower, being backed by a
quorum or the proposer's own with its roll at the points; and the honest machines being at least
`Q`, their open pledges reach the quorum, their closing pledges follow, and the name is decided. The
lowest place falls to an honest part, once the heavy attestations of the honest stand, with
probability at least `(T - B) / T` in every attempt and independently of every other attempt, because
the place is drawn from the part, the aggregate and the attempt and from nothing a faulty machine
chooses. What a decision needs beyond the count is what the close always needed — the votes of the
standing of the honest machines reaching the committee — and the set says so rather than implying
more.

**Why it decides one name.** Two decisions of one window imply at least `Q + Q - T` machines of the
electorate each signing, under one part-nullifier, one of three contradicting pairs: two open pledges
of one attempt on two names; two closing pledges of one attempt on two names; or a closing pledge on
one name and, in a later attempt, an open pledge on another name standing on none or on an attempt
before the closing one. "Finality" carries the argument.

**Invariants of the agreement:**

- The proposal of a window is decided in the window after it, by the electorate of that window, at its quorum, and by nothing else; the agreement moves no electorate, no quorum, no threshold and no round.
- A pledge carries the window, the attempt, the name, the attempt it stands on or none, the part-nullifier and the one-time key of the window, under which it is signed; it is valid only where the heavy attestation of its part under that key stands, and the heavy attestation is the one open pledge of attempt zero, standing on none.
- An open pledge counts only where its `since` is none or the open pledges of the attempt it names reach the quorum on its name; a closing pledge counts only where the open pledges of its own attempt reach the quorum on its name; a part counts once per kind and attempt.
- A name is decided when the closing pledges of one attempt reach the quorum on it; the decision makes the proposal final and closes the window beside the cement of its final beacon.
- A machine keeps its attempt, its lock, its valid name and every pledge it made before it publishes what they govern, and through a restart; it never signs two open pledges or two closing pledges of one attempt on two names, nor, in an attempt after its lock's, an open pledge on another name standing on none or before its lock's attempt.
- The place of a part in an attempt is computed from the part-nullifier, the cemented aggregate of the window two before and the attempt alone, under the domain Canon names, and compared unsigned and big-endian; it names nobody.
- The span of an attempt is a machine's conduct and enters no rule of acceptance; it doubles from attempt to attempt, and no lock expires on one.
- Every proposal names its roll inside the scope of its name; a machine follows a name it did not take only where that name is backed by a quorum or its roll replays to the proposal, and a machine whose name is not decided replays the decided roll before it holds the decided state.
- A payer is told what its frame took as its round leaves and told again where a replay moves it; the positions a note is spent from are those of the decided rolls.

## Finality

The quorum of a window exceeds two thirds of the electorate, so two decisions of one height carry
quorums intersecting in at least `Q + Q - T` machines — a third of the electorate — and every
machine of the intersection has signed, under one part-nullifier, one of the three contradicting
pairs the agreement names: self-evident pairs, nameless, the sanction's own evidence. Finality is
therefore accountable: it takes a third of the electorate willing to convict itself, and above that
third it is self-evidencing. The votes of a close narrow this and never widen it: each of two
decisions of one height still carries the count, so the intersection is the count's whatever the votes — and a set of
machines that would close a window on the count alone must also hold the standing that draws the
committee's share, which a fleet admitted together does not hold until it has lived the censuses.

**Why two decisions leave the pairs.** Let the names `X` and `Y` be decided in the attempts `a` and
`b` of one window, `a` at or before `b`. Where `a` is `b`, the closing pledges of `a` at the quorum on
`X` and on `Y` intersect in at least `Q + Q - T` parts, each of which signed two closing pledges of one
attempt on two names. Where `a` is before `b`, the closing pledges on `Y` count only where the open
pledges of `b` reach the quorum on `Y`, so some attempt after `a` holds a counted quorum of open
pledges on a name other than `X`; let `j` be the first. Every open pledge of that quorum stands on
none, or on a counted quorum on its own name at an attempt before `j` — which, by the choice of `j`,
is `a` or an attempt before it. If one of them stands on `a`, the open pledges of `a` reach the quorum
on a name other than `X` beside the quorum on `X` the closing pledges of `a` stand on, and the two
quorums intersect in at least `Q + Q - T` parts, each of which signed two open pledges of `a` on two
names. Otherwise the quorum of `j` and the closing quorum of `a` on `X` intersect in at least
`Q + Q - T` parts, each of which signed a closing pledge on `X` in `a` and, in the later attempt `j`,
an open pledge on another name standing on none or on an attempt before `a`. In every case the
pairs are published objects, each under one part-nullifier, and the evidence is complete without a
word from anyone.

**What prices that third, and what does not.** The sanction is not what makes a reversal
expensive: an equivocating right loses the share of its window and nothing else, so a third of
the electorate willing to convict itself pays a third of one window's mint between them. What makes
it expensive is what a place in the electorate is. A machine enters the tree of admitted machines
through the gate of time — a lived continuity period that cannot be bought or parallelized, a
one-time right that names nobody, and the bounded rate of selection events — so a third of the
electorate is a third of everything the network has admitted through that gate, and it is not for
sale at any moment. A protocol whose places were purchased would need the sanction to carry the
price, because the places themselves would be for sale; here the gate is the price, and the
sanction is what makes a reversal **evident** rather than what makes it dear. Safety at this
boundary is structural and accountable, and the set says so instead of implying an economic
guarantee it does not give.

A machine that verified a decision never leaves it. Within one set of rules length decides
nothing; the length rule of the Constitution survives for the divergence of rules alone, and
it counts decided windows. The challenge of a window opens at its proposal and closes when the
window after it closes, and a pair presented after that close is refused. The attestations and the
pledges themselves outlive the challenge as the certificate of the window — retained for the windows Canon names — and their
longer life extends no challenge and names nobody.

**Invariants of finality:**

- A decided window is never abandoned by a machine that verified its decision, and no longer chain within one set of rules overrides it.
- Two decisions of one height imply at least `Q + Q - T` machines of the electorate, each under one part-nullifier, signing one of the three contradicting pairs of the agreement, and those pairs are the whole evidence.
- The challenge of a window runs from its proposal to the close of the window after it; a pair presented after that close is refused, the attestations and the pledges retained as the certificate extend no challenge, and nothing of it enters persistent state.

## The sanction of a double answer

One part-nullifier under two contradicting pledges of one window is proof that one right
equivocated, and it is the only proof this protocol accepts against a machine — a timeout, a
silence or a neighbour's account of what it saw are not evidence and change nothing. The pairs that
contradict are three, and the agreement names them: two open pledges of one attempt on two names —
two heavy attestations of one window attesting two names among them; two closing pledges of one
attempt on two names; and a closing pledge on one name followed, in a later attempt, by an open
pledge on another name standing on none or on an attempt before the closing one.

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

- Only one part-nullifier under one of the three contradicting pairs of pledges is evidence. A
  heavy attestation is the open pledge of attempt zero and carries the first pair as any pledge
  does; a light attestation pledges nothing, enters no quorum and is no evidence — its key is
  proven by the heavy it inherits, and what it moves is the pulse alone. A repetition of a pledge
  on one name is the lawful deduplication of its quorum, and a repeated round nullifier under one
  beacon is refused as a duplicate, never held as evidence; nothing observed about timing,
  presence or reachability is.
- The refusal falls on the right and not on a party, so no implementation needs a name to apply it.
- The first appearance stands and the second is refused, by the canonical order of the window and never by the order of arrival at a machine.
- A pair is admitted no longer than the window's challenge and enters no persistent state; the attestations retained for the join extend no challenge and name nobody, so nothing accumulates about anyone.

## The certificate of a window

A window leaves behind what convinces a device that was not there: the proposal that closed it, the
heavy attestations of the window after it, the pledges of that window's agreement its decision
stands on, and the ballots of their parts. Together they are the **certificate** of the window, and
a device verifies them exactly as the living did — every presence proof against the root of the
electorate it already holds, every signature under the key the attestation or the pledge carries and
every pledge's key against the heavy attestation of its part, the distinctness of the parts, the
counting of the agreement — every closing pledge against the quorum of open pledges of its attempt,
every open pledge against the quorum its `since` names — the count of the deciding quorum against
the count of the electorate, every ballot against the census, the aggregate and the committee of
that electorate, the votes against the committee, and the proposal's own ticket proof and
signature. Nothing in a certificate is a new object: its parts stand at the points of the rounds and
of the window that produced them, retained for `retained_windows` windows after the window closes,
and a device collects them from there.

**Why there is no fixed-size proof of a window, derived rather than regretted.** A proof of one
length asserting that a quorum of hidden weights was reached would have to be made by a prover who
holds what the quorum is made of. Under a commitment that hides every machine's weight behind
randomness that machine alone holds, the sum of the commitments opens only to the sum of the
randomnesses — which no single machine holds and no two may pool without disclosing their weights to
each other. The relation therefore has no prover, at any parameters and any population; a protocol
that stated it would state a proof nobody can write. The other route to one length — a proof that
verifies the presence proofs of the signers inside its own circuit — is refused by the set's own
measurement: a verification in circuit costs many times the height a frame stands at, at every
choice of parameters, and does not run on the device this protocol is derived against. What remains
is the certificate: the attestations themselves, each a proof of its own, and a count — and, where
the electorate weighs, the ballots, each a proof of its own machine's votes, and a sum of them. The
weight that no single proof could assert is asserted by every machine for itself.

**What the certificate costs, and who pays it.** A device verifies one presence proof per attesting
machine of each window it walks, and one signature per pledge — the same work every living machine
does as the window runs — so
the cost of catching up over `retained_windows` windows is that many windows of the duty every
machine already carries. A machine retains the attestations of a window for that long and no longer;
the bound is read from held state, exactly as the close is, and what it buys is stated beside its
derivation in Canon.

**The attestation of presence is what hides the signer, and the scheme is what hides the
witness.** A heavy attestation is public as an attestation by the object that carries it, and it
discloses that some machine of the electorate attested and nothing of which: its part-nullifier and
its one-time key join to nothing across windows, and its proof is zero-knowledge in the sense Canon
states for the scheme — the rows a query opens and the values outside the domain are drawn from a
free block of uniform randomness, so an observer holding every proof a machine ever published learns
nothing of its secret or its place in the tree. The reproduction that once extracted a machine's
spending half from its published proofs is refused by that construction and stands as a test
beside it.

**Invariants of the certificate of a window:**

- The certificate of a window is its proposal, the heavy attestations of the window after it, the pledges of that window's agreement its decision stands on, and the ballots of their parts; it introduces no object and no signature of its own.
- A device verifies a certificate as the living verified its parts: every presence proof against the root of the electorate of its window, every signature, every pledge's key against the heavy attestation of its part, the distinctness of the parts, the counting of the agreement and the count of the deciding quorum against the count of the electorate, every ballot against the census, the aggregate and the committee of that electorate, the votes against the committee, and the proposal's ticket proof and signature; nothing of it is taken on trust.
- The heavy attestations, the ballots and the pledges of a window survive at their points for `retained_windows` windows after the window closes, beside the frames of its rounds and its proposals with their rolls, and nothing else of a round outlives its window.
- No proof of one length asserts the quorum of a window: the relation that would need one has no prover, and the set names that rather than stating a proof nobody can write.
- A proposal is final when its certificate verifies — the decision of the window after it stands in it — and the head of the TimeChain is the newest proposal so verified.

## What a machine commits about itself

A machine is represented in every consensus structure by the half of its secret that names it,
which stands as a leaf of the tree of admitted machines, and by nothing else that joins to it. Two
quantities of a machine are its own and are published nowhere: the window its membership was
granted in and the window it last answered for, which tell a term from its lapse. They are proven
when a term is renewed, by the proof of presence renewal carries, and no timeline of a machine is
public. Its standing is committed nowhere at all: it is the census windows whose cements hold the
machine's parts, which the machine reads off the cements it lived and proves in its ballot, and
which no reader can join to it.

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
create. What a term rests on is proven when the term is renewed, so that the network holds no
public timeline of any machine.

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
The ticket asserts a draw and binds the key of a proposal under a digest domain of its own, so a
proof of a ticket names no attestation's key. A description that asserts a different statement is
a different artifact, and the network accepts proofs under the descriptions `air_hash` binds and
under no others.

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
- The root it answers against is the root of the electorate — the admitted set the proposal of the window two before carries; a proof against any other root is refused.
- The part-nullifier comes of the half of the machine's secret that spends, taken with the window under the domain Canon names; that half and the half that names the machine in the tree of admitted machines come of one absorption of the secret, squeezed twice, so a circuit reads the secret once.
- A light attestation carries no proof and is valid only where a heavy one under the same answering key stands published for the same window, whose proof it inherits.

## The standing of a machine, and the ballot

What a machine accumulates weighs in the quorum, and nobody learns how much any machine weighs.
Both halves of that sentence are owed, and neither may be bought with the other.

**What a standing is.** A machine stands one unit for every census window of the last period of
adaptation whose cement holds its part — `standing_censuses` windows, `census_interval` apart, Canon
holding both. A unit is earned the way presence is earned: by attesting a window and entering its
cement, witnessed by the quorum that closed it and asserted by nobody. A fleet admitted together
stands nothing until it has lived the censuses, and a machine that stopped answering stands less with
every census it misses, until it stands nothing.

**Why a machine alone can prove its own, and nobody needs to prove the sum.** The part of a census
window names nobody and joins to nothing across windows, so which censuses a machine lived is known
to that machine and to no reader. How many parts each census cement holds is public, and a proposal
carries the census — the root of the tree of each census cement and its count — so the standing of
the electorate is the sum of those counts, a number every verifier makes from state. The relation the
set once stated, a quorum asserted over a sum of hidden weights in one proof, has no prover, because
the opening of such a sum is the private randomness of distinct machines (the certificate section
derives it); this relation needs none, because no machine ever proves anything about another.

**The votes a standing draws.** Every unit is drawn in every window: its coin is a hash of the
machine's spending half, the census window and the cemented aggregate of the window two before — the
value the draw of the runner reads — and the unit votes where the coin falls below the threshold of
the committee. The committee is read off the standing alone: where the standing holds at least
`standing_censuses × standing_committee` units the threshold is the width times
`standing_committee` over the standing, so the electorate casts `standing_committee` votes in
expectation and a machine of full standing at most one; below that floor the threshold is nought, no
unit votes, and the close is the count of machines alone. A coin is nobody's to choose — the half is
fixed at admission and the aggregate cements after it — and nobody's but its machine's to compute.

**The ballot.** A machine whose standing drew at least one vote publishes a ballot beside its heavy
attestation: the window, the part, the count of votes and a proof under the description of the
ballot. The proof asserts that the part is the nullifier of the spending half it holds and of the
window, that for every census window the census of the electorate names the proof either walks the
part of that census under the same half to the root of its cement or casts nothing for it, that the
coin of every census under the same half clears the threshold or does not, and that the count is the
number of census windows where both hold. It reads no secret and walks no tree of admitted machines:
the part it binds to entered the cement beside a proof of presence deriving it from the secret of an
admitted machine, and a second half yielding the same part is a collision of the proof hash. Canon
holds its layout, its public input and the height it stands at.

**What a ballot publishes, and what it does not.** A count of votes, which is a draw whose expectation
is the machine's standing over the committee: a reader learns that some machine of the electorate
drew that many votes in that window, and nothing joins the ballot to the machine or to its ballots of
other windows. Not the standing, not which censuses were lived, not where the machine stood in their
cements, and not which of its units cleared — the coins are computed under the machine's own half,
so no reader can tell a lived unit that did not clear from one that was never lived. **Why a draw and
not the standing itself.** A tally of hidden weights that no single prover can witness is made either
of parts each machine publishes or of a computation the members of a window run together, and the
second is a quorum convened to compute a quorum, with keys and rounds of its own, which this set
does not run. Each machine therefore publishes the least part there is: a sample, which hides the
weight it is drawn from exactly where it is smaller than the population. That is why the committee begins at a floor: below it the sample would be the whole and
every ballot would be a weight, so the set weighs nobody there rather than publish anyone.

**Why the ballot is an object of its own.** The duty of every window is the proof of presence, at the
height its own statement fills; a ballot walks a cement for every census and stands at the frame's
height. Folding the two would charge every machine of every window the frame's price for a statement
most windows of most machines do not need — nobody below the floor, and above it only a machine whose
standing drew a vote. Apart, the presence keeps its price and the ballot is paid by whoever votes.

**What the votes buy, and what they cannot cost.** The close asks the count of machines and the votes
of their standing, each at the share the Decree names. The count is what makes two final proposals of
one height imply a third of the electorate equivocating, deterministically and accountably, and the
votes do not touch it: they can refuse a close the count admits and never admit one it refuses. What
they add is the barrier of time — a set of machines holding little of the standing does not close a
window however many of them stand admitted — and what they cost is a tail of liveness, never of
safety: a window whose answering standing falls short of the committee's share waits, as a window
short of the count waits, and `standing_committee` is derived so that three quarters of the standing
answering misses the share with probability below 2^-40.

**Invariants of the standing and the ballot:**

- A unit of standing is a census window whose cement holds the machine's part of that window; no other presence, no age and no quantity of anything weighs.
- The census of the electorate is the census the proposal of the window two before carries, and every verifier recomputes the census of each proposal from the one before it and the cement of its window.
- The committee is a function of the standing alone; below its floor it expects no vote and the close is the count of machines.
- A coin takes the spending half, the census window and the cemented aggregate of the window two before, and nothing else; it is computed by its own machine alone.
- A ballot counts for a part of the cement and for no other, once, at the largest count a verified ballot of that part casts; its votes are evidence of the close and enter no field of the proposal.
- A ballot publishes the count of votes and nothing else of the standing.
- The votes refuse closes and admit none: every window the votes close is a window the count closes.

## Presence is witnessed and never self-declared

Presence in a window is counted when, and only when, the network has witnessed it: a machine whose
attestation did not enter the cement of that window is not living in it, whatever work it performed
locally. Self-declared presence weighs nothing, and the rule takes no exception — not for the
opening cohort, which witnesses itself by the same quorum, and not for a part of a split, which
remains halted until the electorate's quorum is reached, as the way back states.

**The witness is the quorum of the window, and never a count of witnesses.** What stands as
testimony is the cement naming distinct machines of the electorate to the quorum share of its
count, and carrying the votes of their standing to the quorum share of the committee. There is no separate tally of who saw whom and no threshold over such a tally, and
the reason is that a tally of that kind is subjective: how many machines happened to receive one
machine's attestation before a window closed depends on the order of delivery, and two honest
verifiers would count differently. A quorum is one collective act — it is either gathered or it is
not, and every verifier reads the same bytes of it.

**The set of the living is therefore derived and never observed.** It is read off the cement: the
part-nullifiers that entered it, each once, are the machines that lived in that window. From that
the count of the living follows deterministically, and with it the divisor of the shares — which is
why the count is a quantity every machine reads off the cement rather than a quantity anyone
publishes or polls. Nothing observes absence and nothing needs to: a machine that did not enter the
cement takes no share of that window, and its term runs out in its own time by the rule of presence
and admission.

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
- The count of the living is the count of the cement and is read off it by every machine; it is never polled or observed.
- No count of witnesses, no threshold over such a count, and no measure of reachability enters the definition of the living.
- The opening cohort and a resuming part of a split witness themselves by the same quorum; the rule states no exception for either.

## The right to a window's share

Minting creates no note. A window mints a fixed quantity and issues, to each living machine,
a **right to a share** of it. The count of the living is the count of the cement of the window,
which every machine holds; the share is the mint divided by it, and the remainder that does not
divide is carried forward rather than appropriated.

Each living machine holds exactly one right to a share per window, and each such right is extinguished by
exactly one nullifier — so no machine takes its share twice, and no machine takes another's.

Consensus issues the right and states what it is worth: one equal part to every living machine,
with the remainder that does not divide carried forward rather than appropriated. How a right
is proven and consumed is Value's, and is not described here — a second description of one
construction is how two documents come to disagree about it.

## The join

A device that holds nothing enters the network by an anchor it trusts and walks from there to the
head by verifying, and the set states the trust rather than hiding it inside a word.

**The anchor.** An operator hands a joining device the proposals of two consecutive final windows,
exactly as an operator hands an acquaintance and the halves of an opening cohort: a line of the
world outside, which the protocol holds none of. Trust in the anchor is the trust a device places
in the operator who starts it, and it is the same trust the opening cohort already rests on. A
device that lived the network holds its own anchor — the last two proposals it verified — and
needs nobody's.

**The order of the join.** A joining device holds the Genesis State Hash, which is a number of
Canon and is recomputed rather than received, and its anchor: a proposal `E` and the proposal `L` of
the window after it, both final.

1. It asks any machine it can reach for the beacons and the heavy attestations standing at the round
   points of the window after `L`, and for the pledges and the proposals standing at the points of
   that window; it
   may ask several, and every answer is judged and never trusted.
2. It verifies the certificate of `L`, which is the heavy attestations of the window after it, the
   pledges of that window's agreement and the ballots of their parts: the electorate is the admitted
   set and the census `E` carries, the aggregate of the draw is the one `E` carries, every
   attestation is verified as the living verified it, every pledge under the key of its part's
   attestation, every ballot against that census, that aggregate and the committee of that census,
   and the agreement decides `L` — the closing pledges of one attempt on the name of `L` reach the
   quorum, each counted on the quorum of open pledges of its attempt and each open pledge on the
   quorum its `since` names.
3. It judges a proposal `N` of that window: `N` names `L` as its predecessor, its rules neither roll
   back nor exceed the ones the device implements, its signature verifies, its ticket clears against
   the electorate root and the aggregate `E` carries, and its cement is the pair of its final beacon,
   a beacon of the certificate just verified whose count reaches the quorum and whose votes reach the
   committee within what the verified ballots of the certificate cast, and whose chain stands at round
   zero on `E`. `N` is final when its own
   certificate verifies in the step after, against the electorate and the aggregate `L` carries; the
   pair `L`, `N` is then the anchor of that step.
4. It repeats until no newer certificate verifies. The head is the newest proposal whose certificate
   verified; a proposal awaiting its certificate is not final, and nothing is taken against its roots.
5. It takes the state it needs against the roots of the head — the whole of it, or the
   single leaf a person's own record occupies — by the inclusion proofs Canon lays out, and it
   recomputes every root it takes rather than accepting one.
6. It then follows the beacons of the open window as any machine does, and it is a machine of the
   network from that moment.

**What a device that was not there checks of the roots.** It holds no state to recompute the roots of
a proposal from. The roots of `N` are attested by the certificate that makes `N` final — every machine
of that quorum recomputed them from its own state before it attested — and the device checks every
leaf it takes against the roots of the head, so a root it never recomputed is a root a quorum did.

**What the walk costs, and where it ends.** Each step verifies the presence proofs of one window's
attesters — the duty every living machine carried as that window ran — so a device away for `k`
windows catches up in `k` windows of that duty. Machines retain the attestations of a window for
`retained_windows` windows after it closes; a device away longer than that finds no certificate to
walk and takes a fresh anchor from its operator, which is a change of trust and not a verification,
and the set says so.

**Two proposals, and no second count.** A device offered two proposals of one height takes the one
the agreement of the window after decided; where two decisions verify, the two are an equivocation
and the contradicting pairs of pledges under one part-nullifier are the evidence the sanction of this
document consumes, so the fork
resolves by the rule this document already states and never by asking who is more numerous.

**Invariants of the join:**

- A joining device starts from an anchor of two consecutive final proposals handed to it by its operator, or held from its own past; the trust in the anchor is explicit, and nothing of the protocol stands in for it.
- Every step of the walk verifies a certificate whole — every presence proof against the electorate root, every signature, every pledge, the counting of the agreement and the deciding quorum, every ballot and the votes — and the next proposal's link, rules, signature, ticket and cement; nothing of a step is taken on the word of whoever answered.
- The head of a walk is the newest proposal whose certificate verified; a proposal awaiting its certificate is not final.
- Every leaf of state a joining device takes is checked against a root the verified head carries, by recomputation; a leaf accepted on the word of whoever answered is a defect.
- A device asks several machines and judges every answer alone; nothing in the join is decided by how many answers agree.
- Joining publishes nothing about the joiner but the fact that some device asked, which the ledger of the wire already holds.

## The way back

A loss of quorum halts the chain. Reconnection resumes the same open window against the
same electorate and the same required share. Neither elapsed time nor an arbitrarily large number
of rounds establishes that an absent machine has died. A partition and a permanent loss can
present identical transcripts to a survivor.

**The denominator belongs to the electorate.** Let `T` be the positive count of the electorate the
proposal of the window two before carries and let `Q` be the least integer meeting the Decree's
`confirmation_quorum` of `T`. Each part is unique in that electorate and counts at most once. An
unverified attestation, a count of reachable peers or a count declared by a candidate proposal
cannot supply this denominator. The committee of the votes belongs to the electorate the same way:
it is read off the census that proposal carries, and nothing of the window moves it. Membership changes take effect only through a final proposal, and
they never retroactively change the electorate of an open window.

**The intersection argument and its assumptions.** Assume the proof of presence is sound, the
electorate is the one a final proposal carries, and an honest machine pledges by the conduct of the
agreement and never signs a contradicting pair. In particular, an honest machine preserves its
attempt, its lock and every pledge it made across changes of round, process restart and crash. If
the Byzantine count `B` is strictly less than `Q + Q - T`, two conflicting certificates cannot both
verify: their decisions leave at least `Q + Q - T` machines each signing a contradicting pair, by the
argument of "Finality", and among them stands an honest one, which signs none. The argument applies to any rounds because the electorate
and the threshold are identical. Induction from the opening cohort gives this conditional
uniqueness at every final height.

**There is no lower recovery quorum.** Comparing disjoint partitions is insufficient:
Byzantine machines can appear in both certificates. Lowering the share to just over half
can therefore authorize conflicting certificates even under the original fault bound.
No number of rounds lowers `Q`, expires a lock, or supplies evidence of absence.

**A restart does not create authority.** Naming a verified old head while choosing a new
electorate from whoever answers does not authorize that electorate. Two isolated groups
could each choose themselves and both satisfy their own quorum. Such a restart is refused
within this network. An operator may explicitly choose a different Genesis and thus a
different network; no identity, balance, finalized height or right is silently inherited
as a verified transition of the old network. This is a change of network and not automatic
recovery.

**The integer form.**

```
resume_share_num(r)        = confirmation_quorum_num
closes(cemented, total, r) = total > 0 and cemented <= total
                            and cemented x confirmation_quorum_den
                                >= confirmation_quorum_num x total
restart_admitted(r)        = false
closes_window(cemented, total, votes, expected)
                           = closes(cemented, total, r) and votes x confirmation_quorum_den
                                                             >= confirmation_quorum_num x expected
```

`cemented` is the count of distinct parts of the electorate in the cement and `total` the count of
the electorate; `votes` is the votes a final beacon carries and `expected` the expectation of the
committee its census draws, nought where the standing is below the floor of the committee. Every operand is unsigned; products are checked for overflow. The round argument
is irrelevant to admissibility and is retained to make this independence testable. Canon's
`finality_rule` distinguishes this rule from the retired lowering rule in the Genesis
parameters. A decoder must reject an unsupported rule instead of falling back to it.

**The liveness price.** If enough of the electorate never returns, the chain may
remain halted indefinitely. Progress additionally needs delivery of the necessary data,
an eligible proposer and a verified certificate; obtaining the numeric quorum alone is not progress.
Monitoring reports these conditions and authorizes no transition. Reconnection restores
liveness only when the original authorization and verification requirements are met.

**Invariants of the way back:**

- The electorate and the threshold are those of the proposal of the window two before, for all rounds of the window.
- A Byzantine machine can overlap competing certificates; the intersection argument counts it once.
- Honest signing locks survive restart and never expire on a clock or a round count.
- No silence, locally counted population, missing diagnostic or restart supplies authority.
- A certificate is verified whole before finality or issuance.
- A different Genesis is a different network and requires an explicit operator choice.

## The cold start

The first window is an empty literal with no operators. The first candidate is admitted by a
selection event while the set of machines is empty and the continuity gate therefore does not
apply, and it finalizes its own chain while the committee consists of itself alone.

## Observability ledger

| Quantity | Status |
|---|---|
| the coordinate of a window | closed by construction: it is the point of the whole layer, it names no one, and it is one number for the network |
| who ran a window | closed: the runner is nameless under a one-time key, and the ticket proof of its proposal asserts clearing without the ticket, the secret or the machine |
| how many machines are living | **deliberately observable**: the count of the cement is the divisor of the shares and the quorum is a count against the count of the electorate, so every machine reads both; they are numbers about the network and name nobody |
| the standing of a machine | closed: it is the census windows whose cements hold the machine's parts, and a part names nobody; no object carries it, the ballot proves it without disclosing it, and the sum of the electorate's standing is a sum of census counts that names nobody |
| the votes of a ballot | **deliberately observable**: the count of votes a standing drew in a window is what the vote half of the close adds up, and it is a draw whose expectation is the standing over the committee — joined to nothing across windows and to no machine, and published only above the floor of the committee, where a full standing expects at most one vote; below the floor no ballot exists |
| the presence of a machine over time | closed: a part-nullifier and a one-time key join to nothing across windows, and the proof of presence hides its witness, so no public timeline of a machine exists |
| an equivocation in the agreement of a window | **deliberately observable**: a contradicting pair of pledges under one part-nullifier is exactly the evidence a sanction requires, and it names no one |
| the name a part pledges, and its place as a proposer | **deliberately observable**: a pledge says which name some part stood behind in which attempt, and the place of a part is computed from the part, the aggregate and the attempt; both are quantities about a part, which names nobody and joins to nothing across windows |
| that a machine was admitted in a selection event | **deliberately observable**: admission adds a commitment about a machine and names no owner, no address and no person; it is what the bound per event is enforced against |
| the thresholds of the draw and of the round | **deliberately observable**: each is a quantity about the network and about no machine |
| the count of rounds in a window | **deliberately observable**: it is the coverage theorem's check, it stands at the derived target wherever the crowd of a round is the admitted through the divisor and falls below it where the floor of the crowd binds, so what it carries is the count of the **admitted** — already in the open at every admission — and never the count of the living, and it names nobody |
| the lived duration of a window | **observable**: it is the echo of committees drawn like the population — a property of the geography of the living as a whole, from which no machine is derivable |
| the count of published heavy attestations | **deliberately observable**: it is the count of the living, which every machine reads off the cement; a number about the network and about no machine |
| the eligibility of a machine for the remaining rounds of a window, after its first attestation | **observable to whoever links its key, and closed by two walls, of which the second is the load-bearing one**: the key names no address and [I-16] closes the link; the exposure then lasts to the cement, which is hundreds of rounds, so brevity is not a defence and is not claimed as one. What defends is redundancy — a round needs any one echo of a rolling fresh draw of one in `committee_divisor`, so silencing the pulse means silencing a fresh random share of a hidden population every round on every chain, a share no attacker can aim at |
| that some machine answered at some address | **a named physical prohibition**: answering is observable at the wire; Network holds what bounds it |

## Conformance set

An implementation conforms to this document when all of the following hold.

1. It advances a round only on a valid attestation — eligibility checked natively against the round threshold over the part-nullifier the attestation carries, the signature under the asserted suite, the proof of presence verified for a heavy attestation against the digest of the key that signed it, and its key's published heavy held for a light one — links every beacon to its predecessor by hash and round zero to the proposal of the window two before, enters each part-nullifier into the cement at first appearance only, whatever name it pledges, and carries the cement as the aggregate and the count, and closes a window only on the decision of its agreement and on a cement reaching the quorum share of the electorate's count, never on a count of rounds, a measure or a clock.
2. It computes eligibility from the nullifier of its part in that window, the cemented aggregate of the window two before and the pair of chain and round, under the domain Canon names, compared unsigned and big-endian; it attests every valid version of a round it sees, and presents one round nullifier per beacon.
3. It computes the round threshold from the count of admitted machines and the count of chains in force by the rule of Canon — the crowd floored, then the width divided by the admitted, the floor of the crowd applied before the division and the width after it — and reproduces the frozen vectors.
4. It takes the identifier of a proposal over the fields the window decided, verifies the ticket proof a proposal carries against the root of the electorate, the cemented aggregate of the window two before and the threshold of the draw, recomputes the public facts a proposal carries — the census among them — and retains the heavy attestations, the ballots, the pledges and the frames of a window, and its proposals with the pages of their rolls, at their points for `retained_windows` windows after it closes.
5. It finalizes a proposal only on the decision of the agreement of the window after it — closing pledges of distinct machines of the electorate on its name reaching the quorum share of its count, with ballots of their parts casting the quorum share of the committee the electorate's standing draws — verifying the roots and the control set — the canonically admitted objects that change who runs windows — by independent recomputation rather than by trust.
6. It takes two clearings that closed on one final beacon as one proposal under one identifier, and walks the cascade in the standby order Canon derives — the ascending order of the cascade key over the commitments of the active set — running the entitled parallel versions from the window's first round and closing on the senior completed cement.
7. It admits a candidate only through a selection event, in the canonical order, within the bound, and only after the lived continuity period Identity defines.
8. It issues one equal right per living machine per window, carries the indivisible remainder forward, and derives the count of the living from the cement and from nothing else.
9. It publishes of an admission the commitment that stands for the machine — derived under the domain Canon names from the answering key, its suite and a blinding factor — and nothing that names an owner, an address or a person.
10. It refuses a candidacy whose one-time right to raise a machine is already extinguished, and it derives that right under the domain Canon names.
11. It disregards, for the window in which a proposal was rejected, the ticket of the machine that published it — and restores it for the next window, because the loss is of duty and never of its place.
12. It refuses a repeated round nullifier under one beacon in silence, holds as evidence against a machine only one part-nullifier under one of the three contradicting pairs of pledges, extinguishes that right without issuing its share, applies the refusal by the canonical order of the window, and accepts no other evidence.
13. It treats a decided window as final: it never abandons a decision it verified, it resolves nothing by chain length within one set of rules, and it discards beacons, attestations, pledges and the evidence of an equivocation with the close that ends the challenge.
14. It derives a ticket from the half of its secret that spends and the aggregate of the window two before, compares unsigned and big-endian against the threshold of the draw, which is the width at every window, and publishes no ticket.
15. It orders its own running by its ticket — it waits the share of its patience its ticket stands at before it proves its own proposal and takes a verified proposal of its decision that stands meanwhile — and reproduces the frozen vectors of the recomputation of a walked threshold, which the schedule of chains takes.
16. It joins from an anchor of two consecutive final proposals its operator handed it, walks the retained certificates to the head verifying each whole — every presence proof against the electorate root, every signature, every pledge, the counting of the agreement and the deciding quorum, every ballot and the votes — and the next proposal's link, rules, signature, ticket and cement, takes as the head the newest proposal whose certificate verified, takes every leaf of state against the roots of the head by recomputation, and resolves two proposals of one height by which certificate verifies rather than by how many machines say so.
17. It counts a machine's standing as the census windows whose cements hold its parts, carries the census from proposal to proposal by the rule of Canon, reads the committee off the standing alone, draws every unit's coin from its own spending half, the census window and the aggregate of the window two before, publishes a ballot only where its standing drew a vote and the electorate is above the floor of the committee, verifies every ballot it gathers against the census, the aggregate and the committee of the electorate, counts a part's ballot once at its largest count, and refuses a beacon whose votes exceed what those ballots cast.
18. It runs the agreement on what a window decided: it pledges in attempt zero the name it took, counts every open pledge on the quorum its `since` names and every closing pledge on the quorum of open pledges of its attempt, a part once per kind and attempt, closes on a quorum of open pledges of its attempt, proposes in the order of its place, follows the open pledge at the lowest place only where its lock admits it and the name is valid to it, moves to a later attempt on its spans or on pledges beyond the share the quorum leaves, keeps its attempt, its lock, its valid name and its pledges through a restart, and reproduces the frozen vectors of the place.
19. It names in every proposal the roll of what its window applied, publishes the roll beside the proposal, follows a name it did not take only where a quorum backs it or its roll replays to it, replays the decided roll over the decided state of the window two before where its own name was not decided and applies its open window again over the result, and tells a payer again what its frame took where a replay moves it.
