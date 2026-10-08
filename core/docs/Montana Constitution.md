# Montana — Constitution

**Version:** 3.12.0

The Constitution holds the properties the protocol preserves across every one of its
components, and the rules by which the normative document set is read.

## Scope

**In scope.** The definition of a global invariant; the global invariants themselves;
the rules of the document set; the evolution of the protocol —
the lifecycle of a change, the `protocol_version` signal, advisory councils, and the
constitutional limits on the scope of a change.

**Not in scope.** Values, byte layouts, domain separators and test vectors — Canon.
The movement of the clock and the finalization of a window — Consensus. Notes, nullifiers,
proofs and transfers of value — Value. Records of people, keys, fingerprints and identity
operations — Identity. Transport, pipes, rights of carriage and delivery — Network.
Anchor semantics for applications and the client layer — App.

## The document set

Seven documents form the normative set: Constitution, Canon, Consensus, Value, Identity,
Network, App. The rules below hold the set together.

| Document | Holds | Never holds |
|---|---|---|
| **Constitution** | the invariants, the rules of the set, the evolution of the protocol | a value, a layout, the definition of a construction |
| **Canon** | the Genesis Decree and its parameters, primitive sizes, the registry of domain separators, the rules of canonical serialization, every layout with its invariants, every test vector | a rule of behaviour, a rationale, a narrative |
| **Consensus** | the canonical order, the windows, the round, the beacon, the chains of windows and of machine presence, the runner draw, the committee and the quorum, the closing of a window, finality, the admission of machines, the issue of the right to a window's share | note mechanics, transport, records of people, numeric values |
| **Value** | the note, the commitment, the nullifier, the note tree, the shape of a spend, the proving root, the proof, the redemption of the right, anti-inflation, disclosure, the double spend | the transport of a payment, records of people, numeric values |
| **Identity** | the record of a person, the operations of the identity plane, keys and their derivation, the fingerprint, the fabric of time, age stratification, the time barriers, the lifecycle of a record, the claiming of a name and of a channel and the slots they occupy, the slot of a channel | value mechanics, transport, numeric values |
| **Network** | transport indistinguishability realized: the pipe, the tag, the holder, the cell, the canonical slot, first contact by a claimed name, the rendezvous, a channel and how a publication reaches whoever reads it, carriage as the goods paid for, near transports, discovery without a map, the transport threat model | records of people, notes, consensus rules, numeric values |
| **App** | the semantics of an Anchor for applications, the application identifier, the economics of an application, the boundary between protocol and client, what a client tells the user | consensus rules, numeric values |

Each of Consensus, Value, Identity, Network and App carries its own observability ledger; each
document of the set carries its own conformance set. Where a document names a construction
that another owns, it names it and points; it does not restate it.

1. **Values and byte layouts live in Canon and nowhere else.** Every other document
   names a quantity and points at Canon; it never restates the number. A number outside
   Canon is a second source of truth, and two sources drift.
2. **One mechanism lives in one document.** A second description of the same mechanism —
   in another document or twice in the same one — is a defect at the moment it appears,
   not a summary. When a summary grows into a full description, the older text is
   replaced by a pointer in the same edit.
3. **Every layer document carries an observability ledger.** Each quantity observable
   from outside holds a row with one of two statuses: closed by construction, or a named
   concrete prohibition — physical, cryptographic or consensus. A quantity without a row
   is a defect: without a denominator of completeness a new leak passes unnoticed.
4. **Every document opens with Scope and closes with a conformance set.** Scope states
   what the document holds and where the rest lives. The conformance set lists what an
   independent implementation must reproduce to be the same network.

History is read from the version control system, not from the normative text.

## The layers of the core

The core of this protocol reads in four layers — the Kernel, the doors, the Decree and the planes —
and Canon names them, states the test by which a reader decides where something belongs, and holds
the law of each. This document points at that section rather than repeating it: a second
description of one arrangement is how two documents come to disagree about it.

What the list of invariants below adds to those layers is the one thing a layer cannot say about
itself — that the Kernel is where an invariant of this document lands when it is about the grammar
rather than about a value.

## What a global invariant is

A global invariant is a property the protocol is obliged to preserve across all of its
components. A violation in one part is a violation of the whole protocol. Global
invariants have no exceptions and are not subject to local trade-offs. A mechanism
incompatible with an invariant is rejected before any other property of it is weighed.

## The global invariants

**[I-1] Post-quantum security.** All cryptographic primitives are resistant to a quantum
computer. Allowed: SHA-256 (Grover weakens it to 128-bit, acceptable), ML-DSA (FIPS 204),
ML-KEM (FIPS 203), STARK (hash-based zero knowledge), lattice commitments. Forbidden:
ECDLP, RSA, classical Diffie-Hellman, Pedersen commitments over elliptic curves,
Bulletproofs, Schnorr and EdDSA. Sizes of the admitted primitives are held in Canon.

**[I-2] Absolute privacy of the financial layer.** Balances, payment amounts, payers and
payees do not exist as public quantities at any layer of the protocol. Consensus state
carries no balance field, no amount, no payer or payee identifier and no edge of the
payment graph. A payment publishes exactly four kinds of quantity and no fifth, by any
mechanism, ever: nullifiers of what it consumes, commitments of what it creates, a rate
nullifier holding the bound on payments per window without naming the payer, and a proof that
value is conserved.

What a nullifier position consumes is a note or a right to a window's share, and the two are
one kind: the positions are typeless, their count does not vary with what fills
them, and the proof asserts a disjunction over each — a note or a right — without disclosing
which branch holds. A position a payment does not use carries a note of zero value,
indistinguishable from any other, so a payment of one input looks exactly like a payment of
two. A blank belongs to a different plane: where an action carries no value at all — the
closure of a record — its commitment position holds one, and Identity states that. Were a redemption to publish a field of its own, a payment redeeming a share
would be distinguishable from every other payment, and the operator of a machine would be named
by the shape of what it spends. No quantity marks a redemption.

1. **No transparent pool.** The value layer is shielded from Genesis. A transparent pool
   would place the taint boundary inside the protocol and destroy fungibility for everyone
   crossing it — the boundary is therefore never created.
2. **No identity in the value plane.** A payment is not an action of a person: no
   sender, no previous hash, it extends the chain of nobody and increases the standing of
   nobody, because no chain of a person exists to extend. The actions of the identity plane
   are of a plane apart and never reference a payment.
3. **Disclosure belongs to the owner alone.** The protocol provides exactly one disclosure
   primitive — a proof of a single payment, produced by its owner at their own discretion.
   A viewing key granting standing visibility of all of a participant's payments is not
   part of the protocol: a secret that discloses everything forever is a hazard, not a
   feature.
4. **No transparent point exists — not even emission.** Minting creates no note and
   therefore no identifiable leaf. What emission creates is a right, and a right is
   redeemed inside a payment that nothing distinguishes from any other: no quantity marks a
   redemption, the moment of it is computed rather than chosen, and the nullifier of a right
   names nobody. Value holds how a redemption is performed. A coin born from emission carries no funding edge at all — not hidden,
   non-existent — and no leaf of the note tree is ever attributable to anyone. Neither the
   size of the window's committee nor the work of any machine nor any share is a public
   quantity: work rests under a commitment, division happens inside the window's proof,
   and each share is sealed to its own machine.

No count of payments exists at any point of the system. The counter of meaningful
quantities is closed for every plane at once by the closing rule of [I-16], and the
financial plane inherits that closure whole; it is not restated here. Whose the payments
are, for how much, between whom, and what anyone holds are not observable by any means.

A violation is an automatic mainnet blocker. Any mechanism publishing an amount, a
balance, a payer, a payee or an edge — including as a side effect of a data structure —
is rejected before it is designed further. This invariant is [I-17] enforced in the
monetary plane.

**[I-3] Determinism of consensus state.** Any state that enters the consensus root is
objectively computable identically by all machines.

**Corollary I-3.a.** Any mechanism whose result in consensus state or in protocol-level
behaviour — mempool prioritization, gossip ordering, fork choice, peer scoring — depends
on a measurement of the physical world, astronomical, geophysical, atomic, biological or
any other, is rejected as a violation. The corollary applies independently of the accuracy
of the measurement model.

**[I-4] The clock does not depend on the planes below it.** The TimeChain — the sequence of
cemented windows, defined in Consensus — advances from canonical inputs, the rounds and the
finalization by a committee, without depending on the state of the records of people.
Dependencies run one way: the TimeChain, then the presence of machines, then the tree of records
of people. A failure of anything downstream
stops nothing upstream, and the clock is upstream of everything.

**[I-5] Implementability without specialized hardware.** All primitives have
production-ready open-source implementations running on the commodity CPU of a machine,
without a trusted execution environment, without a mandatory GPU, without a mandatory
ASIC. The commodity boundary includes the premium consumer tier — consumer NVMe storage,
consumer memory, a desktop x86_64 or ARM64 processor, symmetric gigabit networking within
a city zone — and excludes the datacenter enterprise tier. The boundary is not
consensus-critical, and no machine's speed enters the pace of the chain at all: a window
advances by rounds, a round closes on the echo of an eligible machine drawn from the whole
population, and the cascade's parallel versions mean the network never waits on one machine.
What hardware buys its owner is comfort, never influence over the clock. The boundary defines the
target profile for calibrating the constants held in Canon and for evaluating operator
economics.

**[I-6] Perfect fungibility — no coin may be marked.** Every unit of Montana is
indistinguishable from every other unit, at every moment, forever. The protocol carries no
property by which one coin could be told from another: no origin, no age, no history, no
label, no list.

Forbidden without exception: any field, tag, list or set distinguishing coins by origin,
history, holder or age; freezing, seizure, blocking or reversal of value by any actor,
including a supermajority; allow-lists and deny-lists of participants or coins at the
protocol layer; any mechanism letting a third party learn the history of a coin, now or
retroactively.

**Retroactive marking is impossible by construction, not by policy.** A spend publishes a
nullifier unlinkable to the commitment it consumes, and commitments unlinkable to their
predecessors; the linking information is never recorded anywhere — not encrypted, not
escrowed, not sharded. A future actor holding the entire chain, all state and unlimited
computation still obtains no coin history, because absent data cannot be compelled.

The consequence is accepted deliberately: the protocol offers no compliance surface. This
is not an oversight to be repaired later — it is the property being built.

**[I-7] Minimal cryptographic surface.** Each new primitive requires a justification by
closing a concrete mechanism. Duplicating functionality through two different primitives
is forbidden.

**[I-8] Network-bound unpredictability of consensus seeds.** Any hash composition entering
a consensus-critical output — the runner draw endpoint, a selection sort key, admission
ordering, weight distribution, emission, ranking — carries at least one canonical and
unpredictable-offline component, computable deterministically by all honest machines only
after a cemented state with signatures from honest participants is fixed.
Canonical-predictable-offline inputs — state counters, any
forward-computable canonical input — are insufficient as the only source of
non-grindability. A violation is an automatic mainnet blocker.

**[I-9] Bit-exact deterministic arithmetic for consensus formulas.** Any formula whose
output, directly or through a transitive chain, enters a consensus-critical output
satisfies three requirements: a binding integer specification, with explicit width,
fixed-point format where applicable, and an explicit rounding direction; unsigned
operands, signed arithmetic being forbidden; and at least three test vectors per formula —
typical, boundary and edge — held in Canon. A real-valued form is admissible only as
commentary; the authoritative form is integer. Forbidden: binary floating point in
consensus code, rounding without a direction, a real-valued form without a parallel
integer form. A violation is an automatic mainnet blocker.

**[I-10] Single source of truth.** Any significant entity of the protocol exists in
exactly one place — a single authoritative definition. All other mentions reference the
source; they do not duplicate its content. The rule applies to the version of a document,
to protocol constants, to primitive sizes, to domain separators, to formulas, to object
layouts and to algorithm descriptions. Values, sizes, separators, layouts and vectors are
authoritative in Canon; every other document names them.

When a duplicate is found the refactor is immediate: one source is kept and the others
become pointers. A duplicated consensus-critical entity is a mainnet blocker, because
silent drift is guaranteed on evolution and produces a cross-implementation fork. A
duplicated non-consensus entity is a finding of medium severity.

**[I-11] State lifecycle and bloat resistance.** Every persistent record in consensus
state satisfies at least one of three requirements.

1. **Lived-time barrier.** Creating the record requires lived time, confirmed canonically and
   proven rather than declared. Lived time is the one scarcity that cannot be acquired: it is
   symmetric for every participant, it does not parallelize for one holder, and it is not for
   sale. Identity holds the gate that measures it and Canon holds what it is measured over.
2. **Lifecycle bound.** Under explicitly defined conditions the record is removed from
   persistent state — by inactivity, by temporal expiry, or by an explicit removal
   operation whose reward is strictly less than the record's storage cost.
3. **A ceiling indexed by time.** Canon names the ceiling of each plane; where a value has not
   yet been frozen there, the document that consumes it says so and claims no conformance over
   it. Where a plane holds no names, this and the lived-time
   barrier are the only paths open to it: a record that names nobody cannot be pruned for
   inactivity, since inactivity of whom is not observable. That is the price of the second
   clause of [I-17], and it is paid rather than argued away.

   In its ordinary form: An explicit bound on how many records may be created per
   window or per selection event, specified in Canon and enforced in the application of a
   proposal. A standing cap on the total number of records with no index in time is not
   admissible on two counts: it is not a time-based primitive and therefore fails [I-12],
   and it turns admission into a race in which whoever fills the ceiling first excludes
   everyone after them for good.

A persistent record created through a legitimate operation without one of these three
mechanisms is a mainnet blocker. The attack class is slow bloat: a series of legitimate
operations whose cumulative damage is state growth. Sybil defence on voting or on the
runner draw does not address it — a million records do not change the distribution of
draw weight, and still occupy a million records.

**[I-12] Time-based scarcity.** Every defence against spam, against bloat of state,
against Sybil on resources and against Sybil on the validator role is constructed
exclusively through canonical time-based primitives.

The scarce resource of the protocol is time: the TimeChain, the window
periods, the chain length of a machine, the activity of a record, the continuity of life.
This time-market is built into consensus as the single objective scarcity. Defences
through the existing scarcity are symmetric for every participant regardless of holdings,
free of duplication of the existing time-based limiters, and independent of the nominal
value of the currency.

Admissible primitives: rate per identity; a lifetime through activity; a cooldown of
activation; a chain-length requirement; seniority gating; the continuity gate; a ceiling per
window or per event; and the canonical unpredictable-offline binding required by [I-8]. Each
is a quantity of time, and none of them is a quantity of money. Each is proven and not
published: a barrier of time that names who cleared it would buy scarcity at the price of a
graph, which [I-17] forbids.

**The time a barrier reads is witnessed time, never asserted time.** A quantity of time a
participant asserts about itself is a quantity a timer produces, so a fleet of seeds on a
schedule clears any barrier written against it and the barrier prices nothing. What a barrier
reads is therefore time woven into the cemented fabric: presence attested by participants
themselves anchored to it, within a bounded reach, proven and never disclosed. A component that
witnesses only itself is an island — its order within itself holds and its weight to everyone
else is nothing, so its self-made history collapses, on contact with the fabric, to the genuine
crossings it has and not to the span it claims. The floor this sets is the one the network wants
and the only one money cannot lower: the price of admission is a corrupted participant already
witnessed by the living, and it does not fall with compute, with capital or with patience.

**Whoever admits is bounded by the same clock.** Were the anchor the whole rule, one corrupted
witness would admit a multitude, since witnessing is a by-product of ordinary correspondence and
costs its author nothing per newcomer. Admission therefore also spends a right of the admitting
participant, at a rate its own witnessed time earns and its own period bounds. The two halves are
one mechanism and neither stands alone: without the rate a single corruption opens the gate, and
without the anchor a fleet witnesses itself into the right to open it. Together the cost of N
admissions is N divided by the rate of the corrupted, each corruption priced in the one currency
this protocol never mints — a living participant the living already saw. Nothing of the admitting
or of the admitted is published: what enters is a commitment and a nullifier, and the connection
between them is proven and disclosed to nobody, so the gate buys its scarcity without buying a
graph.

**Delimitation.** The invariant applies to anti-spam, anti-bloat, state scarcity and Sybil
on the validator role. It does not apply to application services — those are implemented
by the application layer through direct transfers of value, and no protocol-level user
service exists. The distinguishing criterion: someone creating many records that consume
network resources without legitimate use is answered by a time-based defence; someone
claiming the validator role without invested time is answered by the continuity gate Identity
defines and by standing, which a machine earns only by carrying and answering across cemented
windows and which no fleet can buy at once. The draw itself is unweighted — every living machine
draws against one threshold — so influence is not bought there either; what a machine
accumulates weighs in the quorum, and it weighs under a commitment, so nobody learns whose
standing composed it.

**[I-13] Out-of-band identity binding.** The key by which a person is verified has a canonical
human-readable representation — a fingerprint derived deterministically from that key alone; the derivation is held in Canon
and its application in Identity. A client compares fingerprints outside the handshake that
carried the key and states the result of that comparison honestly at every moment. What the
invariant forbids is not an action of the person but a lie about the state: presenting an
unverified handshake as a verified one — by silence, by an ambiguous mark, or by a default
that reads as confirmation — is a violation of the protocol.

Exactly one representation exists. A second, differently derived representation of the
same identity is forbidden: two fingerprints for one person produce a comparison that
succeeds on one path and fails on the other, and a person cannot tell a mismatch from a
mistake in the choice of path.

A client does not block the first encrypted message: it marks the handshake as unverified
and keeps the mark until a comparison is made. Blocking would kill the very case a first
letter exists for — whoever writes first holds nothing to compare against yet and nobody to
compare with, and a network in which no one may write first is not a
network. The mark is not removed by time, by the number of messages exchanged, or by any
action other than a comparison. A change of that key generates a new
fingerprint, and interaction afterwards requires a fresh comparison.

**[I-14] Public audit surface of the client binary.** Every release build of an official
Montana client is reproducible byte for byte from publicly published source by any
independent builder. The hash of each release build is published in three independent
places: through an Anchor published by those who coordinate development,
as a signed tag in the public source repository, and as Anchor confirmations from
independent reviewers who rebuilt the binary from the same source.

The protocol does not block clients that fail verification from connecting — an open
ecosystem of alternative implementations, user modifications and research tools depends on
that. What the protocol provides is a detection surface: any divergence between an
executed binary and the published source is discoverable by independent audit, publicly.
A preventive approach would require trusted self-attestation, possible only with hardware
attestation and therefore a violation of [I-5], or a centralized allow-list, a violation of
decentralization.

**[I-15] No external time inside the protocol.** No measurement of the physical world
enters the protocol — none at Genesis and none after. The following are forbidden in
protocol code and consensus state: reading the system clock of the operating system, reading a monotonic
clock inside protocol logic, dependence on a network time oracle or a satellite time
source, signed objects carrying wall-clock stamps, and adaptations, lifecycle conditions,
timeouts or draw rhythm expressed in physical seconds.

Every duration in the protocol is expressed only in rounds or in window numbers, and both
are counts of events of the network, never of anything a machine measures alone. A new
machine begins at the current window at start-up and signs windows without local
self-calibration. The operator's judgement whether their
hardware is adequate is made before the machine is started; inside the protocol no such check
exists.

**Scope.** The invariant applies to protocol code and consensus state, including signed
objects, layouts and hash compositions. The network and transport layer — kernel-level
keepalive, operating-system socket primitives — and operator tooling — monitoring,
dashboards, local benchmarks taken before a machine starts — are outside
scope and may read the operating-system clock freely — as are the gathering of entropy at the
birth of a seed, where clocks are read for their noise and no reading enters any published
quantity, and the presentation layer of a client, where a coordinate of the chain is rendered
as a calendar date under the duty App states. The carve-out covers the service mechanics of the
operating system, never the observable behaviour of the protocol: any quantity that enters
what is visible on the wire — the moment of sending, an expiry, a lateness threshold — is
expressed in windows or in rounds.

A violation is an automatic mainnet blocker: any dependence of the protocol on external or
system time turns Montana into not-Montana, losing canonical determinism and the
independence of the window chain.

**[I-16] Transport indistinguishability.** The path an object takes discloses nothing that
its content conceals. For any object the network carries — a payment, a message, a chunk of
media, a unit of consensus data — an observer of the wire at one point, and at any set of
points that does not hold both ends of the same delivery, cannot determine what the object is,
who originated it, for whom it is destined, or whether a given machine is its origin or a
relay. An observer holding both ends is the one case the invariant does not close: there the
correlation of envelopes remains possible, its price is set by the delay profile and the
volume carried, and the prohibition behind it is physical and named in the third requirement.
Nothing weaker than both ends buys it. Cryptography
closes the content; this invariant closes the fact, the moment, the shape, the size and the
direction. A transport leak devalues [I-2] in full without touching a single cipher, and a
violation is therefore an automatic mainnet blocker. This invariant is [I-17] enforced in
the transport plane.

Requirements, every one of them obligatory:

1. **A payment has no transport of its own.** A payment travels in the same opaque
   envelope, along the same path and in the same size bucket as an ordinary message or a
   chunk of media. A separate financial path, a distinguishable format or a
   distinguishable rhythm is a defect.
2. **Sending is canonical, not reactive.** The moment of sending is derived from the window
   number and the ephemeral identity of the sender, not from the moment a person pressed a
   button. Reactive sending yields a watermark by timing.
3. **Nothing is made even, and evenness would itself be the mark.** A constant rate would be
   the worst solution: an even round-the-clock stream is almost absent from the network, so
   the defence itself would become the identifying mark — a list of machines is gathered from
   the backbone within a day without inspecting packets at all. Synthetic filler therefore
   does not exist, and neither does a price for it: the same bytes carry other people's
   letters and are paid for by a share of the window.

   What the sum of another's traffic with one's own does, and what it does not, is stated
   exactly, because this has been overstated before. It does remove the profile of a single
   correspondence from a single line: an observer of one line sees a sum whose composition it
   does not know, and every reachable device carries the traffic of others by the same rule
   that pays it. It does **not** make the summands inseparable. Separating superimposed flows
   by their envelopes is a standard technique that requires no machine on the path [Murdoch and
   Danezis 2005; Johnson et al. 2013; DeepCorr 2018], and against an observer of both ends of
   a path the correlation of envelopes remains possible. The price of that correlation is set
   by the delay profile and by the volume carried, not by the unpredictability of what people
   write. The claim that the summands are inseparable is stronger than the truth and is not
   made here.

   The prohibition is physical and is named rather than implied. A delivered envelope moves
   bytes at both ends within the horizon of a window; concealing a flow requires a floor at
   least as large as that flow, carried continuously by someone, and no construction supplies
   volume that nobody carries. Delay past the window is not privacy but the end of delivery.
   What the protocol sets is therefore the price of the correlation and not its impossibility,
   and the two quantities that set it — the delay profile and the volume carried — are named
   here rather than left to be discovered by whoever measures them.

   Unpredictability closes one thing exactly: a person's word of tomorrow exists nowhere
   today, so no schedule of sending is computable in advance from a person. That is why the
   rhythm of sending is taken from the window rather than from a keystroke — the canonical
   slot, below — and it is not a claim about volume.
4. **Division of knowledge by a single pipe.** There is exactly one pipe — the one that
   carries correspondence; no second pipe is established. A payment is an envelope
   addressed to an entry machine, and for one's own machine it is indistinguishable from an
   envelope addressed to a person. One's own machine knows whom and does not know what; the
   entry machine knows what and does not know whom, because the sender address in a frame is
   not authenticated and the envelope arrives in transit. Neither of them holds both pieces
   of knowledge.
5. **A stable entry, not a random one.** The anonymous entry is chosen from a small stable
   set of machines with rare rotation — a set of machines, which [I-17] admits, never a standing
   address of a person. Under a fresh choice for every payment, the probability of
   striking a hostile entry at least once tends to unity with the number of payments.
6. **Privacy is not rented.** External tunnels serve the circumvention of censorship and
   may hide a network address, but they are not a source of privacy: with them switched off,
   privacy remains fully intact.
7. **The path is no shorter than the minimum Canon holds, and no direct path
   exists.** Every envelope crosses that many distinct machines of the active set, each standing
   there through an admission priced in time. The sender assembles the number among the steps it
   chooses, and what follows on the path can add machines and never subtract one already
   crossed — so a guarantee established at the head of a path holds for the whole of it. The
   check belongs to the sender because the property protects the sender, and no second party
   verifies it: a party that skipped it would spend nobody's privacy but its own. What the bound
   buys is a price and not a proof — an operator holding several admitted machines can present
   itself as several owners, and Network states what that costs and what residue it leaves.
   When fewer machines are
   reachable, the envelope is not sent: it waits in a queue until the path assembles. No
   short path, no automatic fallback, and expressly no dialogue offering a person a trade of
   privacy for speed — a person under pressure consents always, so such a dialogue transfers
   responsibility instead of defending. Near mesh and courier delivery are not short paths
   but separate transports with a plainly stated property; a person chooses a transport,
   never a degree of privacy.
8. **No one lays a route — the tag chooses the holder, and the tag is a right.** A sender knows the keys of nobody
   but its own acquaintances and builds no layers on their behalf. Every step follows one local rule
   identical for all, and no two steps of one delivery ever carry the same value. Network holds
   the rule and both derivations. A directory is therefore unnecessary — the rule
   reads acquaintances, not a map, and acquaintance is not publication; the point of deposit
   is chosen by neither party but by the tag; and both sides converge on it without search,
   because it is computable from the tag alone. The first steps are random and only then does
   the rule apply: otherwise the very first step is directed and a neighbour of the source
   distinguishes arrival from birth. A pipe survives no longer than its tag, so a permanent
   mailbox does not exist and no holder accumulates anyone's history.

   The tag is not merely a label — it is a right, and that difference is what keeps a machine
   from being named. A right is proven by possession and never by a name; it is derived rather
   than stored; it is spent once; it belongs to a window and is spent in that window, so the
   moment of spending is computed and not chosen, as a share of emission is; and two exercises
   of it are not linkable to each other. It is sealed to the holder, and no hop ever sees it:
   a hop reads the label of its own step and nothing more, so a right is neither a constant
   along the path nor a thing another hand could spend. What a hop carries and what a holder
   redeems are different objects, and only the second is an entitlement.

   Three places would otherwise have to name a machine, and this one property closes all
   three: the right to inject stands where a quota per address would stand; the right to take
   stands where an address of a queue and a subscription to it would stand; the right to be
   paid for carriage stands where an account of who carried would stand.

   A spent right is recorded at the holder for the window and nowhere else. Consensus state
   never records it: the network keeps no count of its own activity, no record grows from
   carrying, and no separate expiry is introduced, the window already setting the horizon of
   freshness. Network holds the rule and Canon holds its integer form, both frozen with the vectors that
   check them, including the negative comparison that a tag derived from a public value fails.
9. **Deferred mail is delayed, and the delay is drawn by the holder.** A letter to a
   sleeping recipient leaves the pipe not at once but after a random value from a bounded
   profile. It costs nothing — the recipient sleeps and the letter waits regardless — and it
   severs the tie between entering the pipe and leaving it, so the moment of sending ceases
   to be a fingerprint of the sender. To live traffic and to real time the delay is never
   applied.
10. **A label exists per step, not per delivery.** No quantity of a delivery crosses the path
    unchanged, so two observations of one envelope are independent ciphertexts not reducible to
    each other on a single bit. There is one size, one type, no hop counter and no marker of
    position. Network holds the construction that achieves this and the derivation it stands
    on; what is constitutional is the property, and the property is that a constant travelling
    the whole path may not exist. A constant quantity travelling
    the whole path is a direct correlator: two machines on the route, and one when the receiving
    machine is hostile, bring sender and recipient together by its coincidence; the length of the
    path raises the price of collusion, not the price of matching. From the same source comes
    the indistinguishability of origin from transit, and its boundary is a named physical
    prohibition rather than an admitted remainder. A flow that is the sum of one summand
    equals that summand: a device carrying nothing for others has nothing to be hidden in, and
    no construction supplies what is absent. A machine serving a tenant receives that tenant's
    bytes by the definition of serving: being served and being invisible to the server cannot
    both hold. Neither is closable, and both are answered by what the protocol does
    compel. A device reachable from outside holds the duty of carriage by that fact alone —
    reachability being proven by an accepted inbound rather than declared — and carrying is
    one of the two things the living predicate requires, Consensus holding that predicate and the
    gate of admission in full. There is therefore
    no state of being reachable and carrying
    nothing, and no separate class of hardware that carries: the duty is a function of the
    device, and a phone holds it on the same terms as a desktop. The degenerate case is
    precisely the device that is not reachable — behind a translator, asleep, on a route that
    admits no inbound — and for it the link is held by its own machine out of the transit that
    machine carries in any case, so the exposure does not follow from being a client. What the degenerate case
    exposes is bounded, and is stated so that it cannot be read wider: the fact that a source
    is here, and the moments and volumes of its own activity, to the owner of that line and to
    the neighbouring hop. Content, recipient, path and the address of a correspondent remain
    closed in it, by the same rules that close them everywhere else.
11. **Real time runs through a rendezvous pipe, not through wandering.** Voice and video
    cannot seek a direction for every packet, so the path for them is built once and held:
    both sides holding a common session compute from its secret one and the same tag of the
    current window, send a handshake setup to it, and the machine reached by both splices the
    pipe. The rendezvous point is neither chosen from a list nor assigned — it is discovered.
    The number of distinct machines on the path is the same, no one holds both ends including the
    rendezvous point itself, and the correspondents do not learn each other's network
    addresses. This is not an exception to the path requirement but its form for a stream.
12. **A failure does not change the choice, and a layer does not answer.** The set of entries
    is a function of the period, not of network events: a dropped connection selects no new
    entry — otherwise an adversary tears the link until the victim settles on the adversary's
    machine. The layer of every hop is authenticated, and a failed check is extinguished in
    silence: an error reply is itself information. A header presented a second time is
    discarded by the digest set of the current window; no separate expiry is introduced, the
    window already sets the horizon of freshness.
13. **On a link with a sleeping device the exchange is held by the reachable side.** For the
    pair of a sleeping device and its machine, the exchange is sustained by the machine — not with
    empty filler, but with the transit of others which it carries in any case. Otherwise the
    switching on and off of a device becomes an event of the network in itself, and
    intersection by presence reconstructs who was online each time a recipient received mail.
14. **No quantity of time finer than a window, and the window itself is taken from the
    chain.** An object generated by a machine carries only the window index, and that index is
    the height of the last cemented window, not a quotient of the division of wall-clock time.
    The network has no clock — there is nothing to take away and nothing to forge; the drift
    of an oscillator ceases to be observable; the schedule ceases to be pre-computable,
    because every beacon of every round
    appears only after the signatures of honest participants — the tip is signature-gated
    hundreds of times per window.
15. **A late cell is not accepted.** One that arrives outside its canonical slot is
    extinguished in silence. An active observer need not drop traffic — it suffices to delay
    it in a pattern and to recognize the pattern at the other end; rejection of late arrivals
    turns a watermark into loss, and loss is closed by an erasure code. The rule works only
    together with the preceding one: a slot that depends on someone else's clock can be
    shifted by anyone.
16. **Consensus travels in the same cells.** The data of a window disperses in the same size
    and the same appearance as correspondence and counts within the same carried volume. A
    separate consensus profile would give away which machine is a machine, and the concealment of
    a machine would be devalued by a single pass of a filter.
17. **A window is a batch of mixing.** Frames leave not at the moment of a keypress but in
    the canonical slot of the window, so a single step of the path mixes everything the window
    has accumulated. Correlation by time between the entry and the exit of a path is closed by
    the clock itself, not by a separate mixer: that for which other networks build a mix-net
    is here already paid for by the construction of time.

**A counter of meaningful frames is held by no one.** Every transition emits a constant
number — a client emits envelopes, the device of a payer emits frames, a window emits
quantities of state — and the shortfall is made up with blank positions a real one cannot be told from: the proof
asserts a disjunction over each position — a real quantity or a blank — without disclosing
which branch holds, and Value holds the definition of that proof. These are positions inside
counted objects, not padding on the wire: the wire carries no synthetic filler at all, as the
third requirement states.
Neither the chain, nor the runner, nor the entry machine holds the quantity of how many were
meaningful.

**Transit is itself the goods that are paid for.** The path requirement brings no new price —
it names the purpose of a price already accepted: carrying is a condition of being counted
living, so a
threefold transit is exactly the work the network buys. The anonymity of the path and the
model of payment are one construction, not two.

Where a requirement above names a construction, it names it only so far as the requirement
is intelligible; Network holds the authoritative definition of every one of them.

**The price, named plainly.** A path of several machines adds to delivery on the order of
several network legs instead of one. For a letter this is invisible: it moves by the slots of
the window in any case. For a conversation in real time it is a perceptible delay, and that
delay is accepted — no direct path is established for a call either, because the single
direct path in a system becomes precisely the path into which an adversary drives the
victim.

**[I-17] No graph is created.** A graph is not hidden — it is not created. Montana holds no
quantity from which a graph could be assembled: no identifier and no address, neither of a
person, nor of their actions, nor of their pipes.

1. **No edge.** The protocol publishes no relation between two quantities and makes none
   derivable: name to person, sender to recipient, payer to payee, person to application,
   person to device, participant to participant.

   What a person publishes about themselves is not an edge the protocol created. A record
   carries no published identifier by default and needs none in order to send, to receive, to
   be paid or to be reached: the record without a name is the norm, not the exception, and
   the whole of it lives as a secret on a device. A name exists only where its holder claimed
   one by an act of their own. The protocol neither requires that act nor undoes it — a name,
   once claimed, is an edge for as long as it is held — and the person is told so plainly
   before claiming it rather than after, in the manner [I-13] requires of every statement made
   to a person about their own state.

   A descriptor a person does not control — a number issued by an operator, an account held at a
   company, any handle another party may reassign — is never an anchor of duration, is never
   published as proof of anything, and is given no entrance of its own. Ownership of such a
   descriptor is unprovable inside a protocol that has no entrance to the network which issued it,
   and an entrance keyed to one would be a space anybody may enumerate. What carries duration is a
   slot of the protocol's own plane of names — a name, or a channel in the space beside it: issued
   by the protocol, taken by an act of its holder, held by renewal, transferable to nobody.

2. **No identifier of a person exists.** Not a public one, and not a private one that could
   later be published: there is no quantity in the protocol whose meaning is "this person".
   What a person holds is a secret. What appears when they act is a commitment to their own
   state, a nullifier that names nobody, and a proof that the step was lawful — quantities of
   the kinds value publishes and of no other kind, with nothing beside them that names
   anyone. A record of a person is therefore of one kind with a note: it is created as a
   commitment, it is spent once, and what it carried — lived time, the height of its own actions, the standing of
   a key — is carried inside it and proven, never published beside it. Two actions of one
   person carry nothing in common that an observer could join.

   No quantity naming a person and observable from outside
   survives two of that person's actions. A persistent identifier is the same edge taken from
   the other side: an observer need only join the actions that carry it, and publishing the
   relation becomes unnecessary. A counter, a sequence number, or any quantity that tells
   later from earlier for one identity is forbidden on the same footing as the identifier
   itself — forbidden as an observable, not as a fact.

   Counting is not what is forbidden; being seen to count is. Lived time, the height of one's own
   actions, the
   length of a chain and the cooldown of an action are quantities a holder keeps and **proves**,
   in the manner an entitlement is proven: the proof asserts that the bearer's quantity meets
   the threshold without naming whose it is, and what appears is a nullifier that names nobody.
   A quantity of this kind that stands in the open today is a defect to be closed by the
   document that owns it, never an exception to this clause.
3. **No address.** A participant is reached by a **tag** derived from a secret two parties
   share and living for one window, never by an address that exists between windows. The tag
   is the reach; a **label** is what one step of a path carries and is rewritten at the next.
   The two words name two objects throughout the set and are never exchanged. Reachability is
   proven, not named.
4. **A machine is accountable without being named.** Consensus must be able to say that a
   window was carried and cemented by distinct members and that a share is owed. It never
   needs to say who they were, and it does not. A machine is therefore of one kind with
   everything else here: a commitment, re-made as it acts, carrying its accumulated presence
   inside; its part in a window is a nullifier that names nobody and that no observer joins to
   its part in another window. What quorum counts is distinctness, not identity, and a machine
   carries no owner, no address and no edge to another machine.

   Two things follow that would otherwise be lost with the names. A sanction still rests on
   proof: one part-nullifier attesting two different closings of one height is exactly an
   equivocation, detected by the same quantity that hides the machine. And everything
   belonging to a person — an action, an entitlement, lived time, height, membership — is
   proven by possession of a secret and extinguished by a nullifier that names nobody, in the
   manner minting already uses.

   What remains observable of a machine is what physics leaves: that some machine answered at
   some address. That is a prohibition named in [I-16], not a record in state.
5. **Every plane declares which clause closes it.** A plane closed by none is admissible
   only where a concrete prohibition is named: physical, cryptographic or consensus.
   Reference to practice elsewhere is not a prohibition.

The property binds every plane of the protocol without exception, and every plane names what
enforces it here rather than being covered by implication:

| Plane | What enforces the property there |
|---|---|
| Monetary | [I-2] — no party, no amount, no edge exists to be published |
| Transport | [I-16] — no address, nothing constant along a path, origin not distinguishable from transit |
| Identity | closed by the same construction as value: no identifier of a person exists, a record is a commitment, an action spends a nullifier, and lived time is carried inside and proven — there is no name for an observer to join two actions by |
| Application | closed the same way: an application acts through the same commitment and nullifier and names no one, so no label sorts people into kinds and no application learns who its users are |
| Consensus | closed the same way: distinctness without identity — a part in a window is a nullifier, quorum counts nullifiers, presence is carried inside a commitment and proven, and one nullifier under two closings of one height is proof of an equivocation, so a sanction keeps its evidence |

A violation is an automatic mainnet blocker in any of them.

**[I-18] No mechanism may require a secret bound to one publisher.** Montana is a protocol and
our client is one implementation of it. A mechanism that works only for whoever holds a
particular vendor's credential — a platform notification token, a store account, a signing
identity issued to one team — is not a mechanism of the protocol: another implementation cannot
participate in it, and a network in which implementations cannot all take part is not one
network but several that resemble each other.

The check is mechanical and admits no judgement: **could a second implementation, built by
strangers with their own publisher account, take part in this mechanism?** If not, the mechanism
is local to one application. It may still exist — an implementation is free to accelerate itself
with whatever its platform offers — but it may never be a step the protocol depends on, and
nothing between implementations may ride it.

The precedent this states plainly: a platform's notification token is bound to the pair of a
development team and an application identifier, so a letter that could only arrive through it
would never reach a person using somebody else's Montana. Waking a sleeping device that way is
therefore an accelerator inside one implementation, and the delivery it accelerates is the same
delivery every implementation performs without it.

A violation is an automatic mainnet blocker, and it is the one violation that cannot be repaired
after the fact: by the time a mechanism of this kind is load-bearing, the implementations that
cannot use it have already been excluded.

## What the set does not yet fix

Five things are open. They are named here, at the front, so that a reader learns them from the
first document rather than by exhausting the last, and each carries what closing it requires
rather than a promise that it will be closed.

| Open | Where it is stated | What closing it requires |
|---|---|---|
| **what a network does after losing more than the complement of the quorum** — the chain halts rather than parting, which is stated, and it does not resume by itself: membership expires by a term counted in windows, and windows stop with the chain, so the weight that died stays in the denominator until something outside the rules acts | Consensus, in the TimeChain and in the pulse | either a rule counted in rounds by which the denominator falls to the weight a window has manifested, with the cost to the intersection of quorums under a long partition stated beside it, or a canonical procedure of restart, so that a recovery is a rule of this document rather than a negotiation among survivors |
| **the Library as a document of its own** — the plane that keeps a body alive is stated inside Network today, and it graduates into a document of the set only when the quantities it stands on are frozen: the domain of the points of a root and their count, the domain the key of an offer is derived under, the domain of the nullifier of an offer, and the layout of a deposit | Network, in the plane that keeps a body; Canon, in the registry and the layouts | those four quantities entered in Canon and the period their points rotate by named among the ones Canon already holds — the shape of the ask is not among them, since the ask of a slot stands already and is taken as it is |
| **what carries the history across the retirement of a proof scheme** — a joining device inherits every window behind the one proof it verifies, so a scheme that fails lets a forged past cost nothing and announce nothing | Consensus, in the proof a window carries | a boundary that anchors the history it closes by a value the retired scheme cannot forge, or a stated argument that the recursion alone suffices, with the assumption it rests on named |
| **the constraint set of the two circuits** — every value it consumes is frozen, the statements it must assert are stated, the format of its description is fixed and the verifier that consumes it is frozen check by check; the artifact itself is machine-checkable and not writable in prose | Canon, in its own section, with the circuits that need it in Consensus and in Value | the artifact published, its hash entered as `air_hash` in the Genesis Decree, and the Genesis State Hash recomputed by the procedure Canon states — one line and one recomputation |
| **which of two frames spending one note stands first, before the window carrying them closes** — the race is visible in one echo, since the notice of a spend stands at a point derived from the nullifier it names and two frames spending one note meet there; what the point does not do is decide, because the identifier of a frame is drawn by its own author and a second frame is brought below a first in a couple of drawings, so a reader that sees a race waits for the canonical order of the window | Value, in settlement and in the notice of a spend | a rule separating two notices at the point itself by a quantity neither author chooses after seeing the other, or a stated argument that the wait is what the protocol offers and the claim is the whole of the fast path |

Two things follow from the entry of the constraint set and are named here rather than discovered
later, and both are consequences of it rather than entries of their own.

The field set of the committed record of a person freezes with the same artifact, since the circuit
that proves a record is what fixes what a record must carry. Canon marks that layout as awaiting it
and claims no conformance over the field set until the value lands.

The length of a proof does **not** wait with it, and the difference is worth stating because it
was once assumed the other way. A length follows from the height a description is built at and
from the parameters of the scheme, and Canon freezes every one of them — the heights among them —
so the family of lengths is derived rather than awaited: the lengths of every object carrying a
proof, the count of cells each of them takes, and the volume the schedule is checked against are
all computable today, and an implementation that arithmetizes differently produces objects of the
wrong size and is refused by the rule that refuses a frame of the wrong length rather than
diverging silently. Everything below a proof — every derivation, every domain, every layout, the
wire, the join, and the procedure that computes the Genesis State Hash — is settled and awaits
nothing. The value that procedure yields awaits the one open entry, because the parameter it is
taken over is the one this table names.

Every mechanism of the set reaches a derivation and a conformance item, and every quantity they
consume is frozen with its derivation and checked by a vector. What the one entry costs while it
stands open is bounded and stated: a proof has one length, one verifier and one transcript, and an
implementation reproduces all three today; what it cannot do is accept a proof, because accepting
one means evaluating constraints and the constraints are the artifact. An entry appearing in this
table is not a defect of the set; a mechanism missing from the documents while missing from this
table is.

## Evolution of the protocol

Changes to the rules of the protocol exist outside consensus state. Evolution runs through open
proposals, independent implementations, the voluntary choice of machine operators, and
fork resolution by cemented height.

### The principle

Consensus state carries only what the financial layer and timekeeping require. No fields of
governance, no councils in state, no votes in the registry of operations. Any attempt to
introduce on-chain governance introduces subjective components into consensus state and
creates a permanent attackable surface — a violation of [I-3].

### The lifecycle of a change

**Proposal.** Any participant publishes a proposal as an Anchor whose text
is held on the author's own device. It is an Anchor like any other and needs nothing of its
own: the proposal is the text, and what reaches the chain is the hash of it. Authorship and canonical position are provable through the signature of the Anchor
and the canonical position of the cemented window. The history of evolution stands
permanently through Anchors.

**Discussion.** Open discussion in public forums. No formal votes inside the protocol.

**Implementation.** Implementations release new versions of the machine software with the
change implemented. Every version is bound to a particular protocol version.

**Adoption.** Machine operators choose for themselves which version to run. No on-chain voting,
no formal activation window. Machines publish proposals carrying their own protocol version.

**Fork resolution.** Where rules diverge the network may split. Every machine follows the
chain that carries more cemented windows under its own rules of validation; within one set of
rules nothing is resolved by length, because finality — which Consensus holds — leaves no second
chain to follow. The minority either updates to the rules of the majority or goes on working
as an independent chain.

### The protocol version field

The protocol version in the proposal header is the single signal of evolution inside
consensus. A machine publishes proposals carrying the version implemented by its software. The
invariant that a proposal's protocol version is not lower than its predecessor's forbids a
rollback to older rules within one chain.

The field is neither voted on nor activated through governance. It reflects what a machine is
genuinely able to validate. A divergence between honest machines resolves through fork choice by cemented
height.

### Advisory councils

Groups of experts may exist as advisory structures publishing recommendations, reviews and
security analysis through Anchor. Their signatures carry no binding effect on consensus,
their memberships are not held in state, and their votes count in no state transition.
Capture of an advisory council grants no control over the protocol — only the ability to
publish a recommendation that operators are free to ignore. This removes the attack surface
of governance: no binding vote means no target for compromise. The protocol knows nothing of
their existence and allocates them no rights.

### Constitutional limits on the scope of a change

Evolution through operator choice is adequate for most changes. The set holds, however, a
layer of properties not subject to change through a proposal and operator choice, because
compromising them does not improve the network — it turns it into a different one. If a
coordinated supermajority of operators is architecturally possible, a social defence is
insufficient and a structural one is required.

**The constitutional layer.** A change at this level is not a valid update of the existing
network — it is a new network with a new genesis, and honest machines reject such proposals as
an unknown protocol rather than as a fork. The layer covers: the global invariants in force
and their operational requirements; the monetary constitution — the mint of a window read from a
schedule Genesis fixes and no later act may change, divided equally among the window's living
machines with the divisor private, supply growing strictly monotonically, no halving driven by the
protocol, no premiums, no protocol-level burning; a schedule of one row is a constant mint and is
what Genesis carries, and a founder shaping the early height writes rows rather than powers, since
what the layer forbids is a rule that mints differently over time by itself, not a value fixed once
before anyone joined; the emission constitution — the minting of a window divided equally among the
living, no emission lottery, no personal reward to the runner, the floor remainder
carried over rather than appropriated; the draw constitution — an unweighted ticket against
the threshold appoints the runner on duty, and the draw does not touch minting; absolute
privacy of the financial layer; perfect fungibility; transport indistinguishability; the absence
of a graph — no edge, no persistent identifier of a person, no address; the
time-based scarcity model; payment by time rather than by money; and byte-exact identity
recovery from the seed.

**Detection of a constitutional break** runs in two layers. Where the invariant is reflected
in the parameters or in the genesis state, a divergence of the Genesis State Hash is
automatic, and honest machines reject the chain at the first proposal. Where it is not — a
change of validation rules, the removal of a cooldown, a change of the reward formula
without a change of constants — detection runs through the protocol version: a
constitutional proposal bumps the major component, and honest machines on the older version
reject proposals carrying a newer major. The second layer is an explicit obligation of the
implementer, not an automatic detection; this is stated as a known limitation rather than
presented as closed. A future proposal may introduce a hash of the validation rules into the
parameters, at which point the first layer covers everything.

**The mutable layer.** Performance optimizations; bug fixes; new opcodes that are backward
compatible; parametric tuning within the bands documented in Canon; extension of
application-layer primitives; documentation and internal refactoring that changes neither
the wire format nor the semantics of applying a proposal.

**Evolution of the constitutional layer.** Extension of the list — the addition of new
immutable properties — is a standard proposal. Narrowing of the list requires a social
consensus broader than a cemented-height majority: coordinated adoption by all major
implementations, unanimity of the advisory councils, publication of the rationale through
repeated Anchors, and a prolonged observation period. The procedure is deliberately
heavyweight, to prevent gradual erosion of the constitutional protections.

## Conformance set

An implementation conforms to this document when all five hold.

1. It computes the Genesis State Hash for itself from the parameters of the Decree and the
   empty roots, by the procedure Canon fixes, and rejects a chain whose value differs from the
   one it produced, treating it as an unknown protocol rather than as a fork. While a parameter
   of the Decree stands unpublished there is no such value and no chain opens at all.
2. It rejects a proposal whose major protocol version exceeds the one it implements, and it
   bumps its own major version on any change touching the constitutional layer.
3. It refuses a proposal whose protocol version is lower than its predecessor's within one
   chain.
4. It implements no governance inside consensus state: no field of governance, no council
   membership, no vote counted in a state transition.
5. It enforces mechanically what can be enforced mechanically: the admitted primitives of
   [I-1], integer-only arithmetic in consensus formulas per [I-9], and the absence from
   consensus state of any balance, amount, payer, payee or edge per [I-2].
