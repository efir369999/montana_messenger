# Montana — Network

**Version:** 3.2.0

Network holds delivery: how a thing crosses from one person to another when neither of them
has an address and no map of the network exists. It is the layer that makes the transport
invariant real, and it is written from that invariant rather than from any earlier practice.

## Scope

**In scope.** The pipe and its tag; the holder a tag chooses; the label of a step; the right that governs
injection, collection and carriage; the cell; the canonical slot; deferred collection;
rendezvous for a stream; a channel and how a publication reaches whoever reads it;
the path and its owners; what a hop knows; discovery without a map;
near transports; the threat model of the wire.

**Not in scope.** Values and layouts — Canon. Notes and proofs — Value. Records of people —
Identity. Windows and quorum — Consensus. Why any of it must hold — Constitution.

## Where a shared secret comes from

Everything below rests on a secret two devices hold and nobody else does, so this is where that
secret begins.

Two devices that have never spoken agree on one by a post-quantum key agreement: each sends a
key encapsulation to the other under ML-KEM-768, each opens what it received, and the two
resulting values are folded together with the transcript of the exchange into a master secret
under the domain Canon names for it. From that master secret two directional keys are derived,
one for each direction of the handshake, so a value that protects what one side sends never
protects what the other sends.

**Both sides prove who they are, and neither says who they are to anyone else.** Each signs the
transcript with its ML-DSA identity key, and the signature covers the key material of the
exchange, so an attacker who relays the messages of two honest devices cannot place itself in
the middle: the transcripts it would have to sign are not the ones it holds. The identity keys
are exchanged inside the encapsulation, never in the open, so an observer of the wire learns
neither key.

**The transcript is the binding, and it is exposed on purpose.** Both sides compute the same
value from the exchange, and each signature covers it, so a handshake whose transcript the two
sides cannot make agree is not a handshake between them. What people compare out of band is not
this value but the fingerprint of the identity key, which Identity defines and Canon derives —
the transcript binds the handshake to a key, and the fingerprint tells a person which key that
is. Two values with two purposes: one is checked by machines every time, the other by people
once.

Nothing about this exchange is classical: the agreement is ML-KEM-768, the authentication is
ML-DSA-65, the folding is SHA-256, and every one of them is a primitive Canon already holds.
There is no elliptic curve anywhere in it, because a handshake that a quantum computer opens
retroactively would open every letter that ever crossed it.

**Invariants of the exchange:**

- Every secret of a handshake derives from both encapsulations and the transcript; a derivation from one side's material alone is a defect that hands the handshake to whoever supplied it.
- The two directions carry different keys, derived under different domains.
- Both identity signatures cover the transcript, and a handshake whose signature does not verify is abandoned in silence rather than answered.
- The identity keys travel inside the encapsulation and never in the open.
- The transcript value the two sides compare is the same value or the handshake is not theirs.

## There is no address

A device is not reached by an address that exists between windows. It is reached by a **tag**,
derived from a secret two parties share and from the height of the chain, living
exactly one window.

From this three things follow at once, and they are the whole design. A tag cannot be
computed by anyone who does not hold the shared secret, so knowing everything public about a
person builds not one valid tag for them. A tag of one window does not join to a tag of
another, so watching a pipe over time assembles nothing. And a tag points at its own
**holder** — the device that will accept a deposit for it — so no directory is needed to find
anybody: the rule reads acquaintances rather than a map, and both sides arrive at the same
holder without asking.

**Invariants of a tag:**

- A tag is derived from a secret the two parties share and the height of the last cemented window, and from nothing else; deriving it from a public address is a defect a conforming implementation must fail on. For a first letter to a claimed name the shared value is the contact root that name published, and every later tag of that correspondence comes from the secret established inside the first letter.
- A tag lives one window; a deposit under a tag of a past window is refused in silence.
- Tags of two windows, and tags of two correspondents of one owner, are unlinkable to each other.
- A pipe lives no longer than its tag, so no permanent mailbox exists and no holder accumulates anyone's history.

## Which machine holds a tag

A tag points at its holder, and this is the rule that takes it there. The living machines are
consensus state, so everyone holding the chain holds the same set, and each of them stands in it
as a commitment and as nothing else. Order those commitments ascending. **The holder of a tag is
the machine whose commitment is the least one standing above the tag, and the lowest of all when
none stands above it** — the ring closes rather than ending.

Both sides compute it and neither asks anyone: the sender from the tag it derived, the recipient
from the same tag, and the set they read is the one cemented for that window, so they cannot
disagree without disagreeing about the chain itself. There is no directory to publish, none to
query, and none to seize.

**Entries stand one per ring of distance, and that is what makes a step converge.** A machine holds
its entries not as a uniform sample of those it knows but one per ring: the first about half the
ring of commitments away, the next a quarter, and so on. Canon derives the placement from the
sender's own secret, so nobody assigns it and two senders hold two sets. Each step then halves the
distance to the target and a path is `log₂` of the population — where uniform entries would leave
every step after the first gaining nothing, and a delivery of a large network would never arrive.

**Why positioning does not work.** A machine cannot place itself where a particular pipe will
land. Its commitment is fixed when it is admitted and carries a blinding factor of its own, while
a tag stands on a secret two strangers hold and on a window height that had not arrived when the
commitment was made — so there is nothing to aim at. Grinding commitments buys an attacker
exactly the share of the tag space its count of machines already buys, which is the share it
would hold by doing nothing.

**How a cell travels toward that machine.** Each hop passes the cell to the acquaintance whose
commitment stands closest to the target in the same ordering, and stops when it is the target
itself. A machine knows the commitments of the acquaintances it has spoken to, so the step needs
no map and no lookup; and because the target is a machine rather than a person, a hop that reads
it learns which machine will accept a deposit and nothing about who deposits or who collects.
Many pipes of many strangers share one holder in one window, so the target separates nobody from
anybody.

**What the holder learns and what it does not.** A tag of one window, a deposit, and a collector
who presents the right to it. Not who sent, not who received, not what was said, and nothing that
outlives the window: the tag dies with it, and a deposit nobody collected decays with it too.

**Invariants of holding:**

- The holder of a tag is a function of the tag and of the cemented set of living machines, and of nothing else; a holder chosen by preference, by proximity in the network or by a list is a defect a conforming implementation must fail on.
- The ordering is over commitments ascending, and the comparison runs over the first sixteen bytes of a commitment against the tag.
- Where no commitment stands above the tag, the lowest holds it; the ring has no end and no machine sits at one.
- The set is the one cemented for the window the tag belongs to, so two sides never read two sets.

## The tag is a right of carriage

A tag is not merely a name for a pipe: it is a **right of carriage**, and that is what keeps a machine
from ever being named.

A right is proven by possession and never by a name. It is derived rather than stored. It is
spent once, in the window it belongs to, so the moment of spending is computed and not chosen.
Two exercises of it do not join. It is sealed to its holder and no hop ever sees it.

Three places would otherwise have to name a machine, and this one property closes all three.

| Place | What would stand there | What stands there |
|---|---|---|
| putting something in | a quota per address | a right to inject, proven without a name |
| taking something out | an address of a queue and a subscription to it | a right to take, extinguished on use |
| carrying for others | an account of who carried how much | a right to be paid for carriage |

A spent right is recorded at the holder for the window and nowhere else. Consensus state never
records it: the network keeps no count of its own activity, no record grows from carrying, and
no separate expiry is introduced — the window already sets the horizon of freshness.

**Invariants of a right of carriage:**

- A right is extinguished exactly once; a second presentation is refused in silence.
- Its nullifier is recorded at the holder for the window and never enters consensus state. This is what separates it from the right to a window's share, whose nullifier is consumed inside a payment and does enter the set of the chain: one buys carriage and dies with its window, the other buys value and is spent once for good.
- A false route costs a wait and never a disclosure: a deposit under a tag the holder does not hold is refused, and the sender's queue keeps the letter.
- No hop can spend a right it forwarded, because no hop ever holds one.

## The cell

Everything on the wire is a cell of one size and one type. There is no field of address, no
counter of hops, no marker of position, no type of message. Consensus data travels in the same
cells as correspondence and counts within the same carried volume: a separate profile for
consensus would say which machine is a machine, and a single pass of a filter would undo the
concealment of every machine at once.

**A label exists per step, not per delivery.** The tag belongs to the pipe; what crosses the
wire is a label of one step, and each hop derives the next one under its own key, so no quantity of a delivery crosses the path unchanged, and two observations of
one envelope are independent ciphertexts. A constant crossing the whole path would be a direct
correlator: two hops on the route — or one, when the receiving device is hostile — would bring
the ends together by its coincidence, and the length of the path raises the price of collusion
rather than the price of matching.

## What carries a message

A cell crosses a hop and a message crosses a link, and the two are one shape: a link between two
acquainted machines carries units of the one size everything on this wire has, sealed under the
directional key that handshake established, and every message of this document travels as pieces of
those units. Canon holds the layout, the reassembly and the invariants. Three things follow, and
they are the whole of the binding.

**A unit is one datagram**, sized against the minimum every path of IPv6 must carry, so nothing
fragments and nothing probes for a path size — a probe being a pattern, and a pattern the thing
this layer removes.

**No length crosses the wire.** Where a message ends is recovered from the message's own bytes,
every one of them carrying either a fixed length or its own count, and the last piece is padded to
the one width. An observer counts units and learns the volume it would have learned anyway; it
reads the size of nothing.

**No address of a carrier belongs to this protocol.** A machine reaches another because an
acquaintance handed it a way to, and what was handed over — an address, a port, a route — is of the
world and not of the set. Freezing one here would be publishing the very quantity that must not
exist, so the set names none, and an implementation carries what its acquaintance gave it.

## The path

Every envelope crosses at least the number of **distinct machines of the active set** Canon
fixes, and no direct path exists — not as a default, not as a retreat, and not as a choice offered to a person.
When fewer are reachable, the envelope is not sent: it waits in the sender's queue until the
path assembles.

There is no dialogue offering a trade of privacy for speed. A person under pressure consents
always, so such a dialogue transfers responsibility instead of defending. Near transports —
device to device by radio, a courier carrying a device — are not short paths: they are
**separate transports** with a plainly stated property, and a person chooses a transport,
never a degree of privacy.

**How an owner is marked without naming anyone.** Each hop attaches to the layer it rewrites a
**seal**: a value derived from its owner's secret together with the identity of the path, under
the domain Canon names for it. Within one delivery the seals can be compared, and two machines of
one owner derive the same seal for the same path and collapse into a single step's worth of
distinctness — where that owner computes the seal as the set states it.

**The check belongs to the sender, and it is performable because distinctness only grows.** A
sender does not build the whole path — the tag chooses the holder — so it can know nothing of the
machines a delivery meets later. It does not need to. The steps a sender chooses are the first
ones, out of its own entries, and what it requires of them is `hop_min` **distinct machines of
the active set**: distinct because the rule of entries yields distinct machines, and of the
active set because a machine stands there only through an admission the Decree prices — a
one-time right to raise a machine, a lived continuity, and a slot of a selection event. That is
what a sender can establish about its own first steps, and it is what the bound is compared
against. What happens beyond those steps can add machines and can never subtract one already
crossed, so a guarantee established at the head of a path holds for the whole of it, and no
second party needs to verify what protects only the one performing it.

**What the bound buys, and what it does not.** A seal is what its own owner computes, so an
operator holding several admitted machines can present several owners and no rule of a wire
refuses it. Nor can one: telling two machines of one owner apart across a sender's acquaintances
would require that sender to present one value to several of them, and a value one sender
presents to several machines is itself the mark that joins what those machines see of it — the
graph this document refuses everywhere else. **The bound therefore buys a price and not a
proof**, and the price is the one the identity plane sets: an operator wanting to stand at every
first step of a sender buys a machine at a time, each with its own one-time right, its own lived
continuity and its own slot of a selection event, at the rate an event offers and no faster.

What that price is worth is stated rather than left to be discovered. The points of a sender's
rings are secrets of that sender, so an operator cannot aim at them and can only own the
machines that happen to stand there: an operator holding a share `f` of the active set stands at
all `hop_min` first steps with probability about `f` cubed — one delivery in a thousand for an
operator holding a tenth of every machine alive. Against an operator that holds the majority of
the network nothing here helps, and nothing anywhere else in this set does either.

Across deliveries nothing joins: the label of a step is fresh for every delivery and every
window, so the same owner produces a different seal each time. The seal is therefore not an
identifier — it is a comparison valid inside one envelope and meaningless outside it. Reusing
the nullifier of the one-time right to raise a machine for this would have been the opposite: a value stable for
the life of a machine, visible to every neighbour, and joinable across every delivery it ever
carried — a persistent identifier of an owner in all but name.

**The first steps are random and only then does the rule apply.** Otherwise the very first step
is directed, and a neighbour of the source distinguishes "arrived from" a neighbour from "was
born at" one.

**How a hop derives the next label, holding no secret of the delivery.** The label of a step is
not a value of the delivery at all: it stands on **the handshake between those two machines**,
derived from the secret that pair established at acquaintance and from the height of the window.
It takes the same shape as a tag and its **own domain**, which is what keeps a label of a hop from
ever colliding with the tag of a pipe. A hop therefore computes the label of its next step from what
it shares with its next neighbour and needs nothing of the letter it is carrying. Two steps of one
delivery carry unrelated labels because they belong to different pairs, and two deliveries across
one pair in one window carry the same label, which joins them to each other and to nothing else.

**Everything but the target is sealed to the next machine.** A cell carries in the open only the
target commitment, which routing cannot do without, and the label of its own step. All the rest —
including the value under which the holder will file the deposit — travels inside the handshake to
the next machine and is re-sealed at every step, so no two points on a path carry one byte in
common, and a hop sees a different ciphertext from the one its neighbour saw.

**Why the holder does not recount what was crossed.** It cannot, and it need not. It cannot,
because one cell of one size carries one seal, and an accumulator growing along a path would
publish the position of every hop in its own length. It need not, because the bound protects
**the sender**: a sender that skips the check spends nobody's privacy but its own, and a check
that protects only the one performing it needs no second party to enforce it. The seals therefore
serve the sender's assembly of its first steps and stop there.

**What a hop knows.** Its own step's label, the target commitment, and one decision: for me, or
onward. It does not
know what the object is, who originated it, for whom it is destined, or whether the device that
handed it over is the origin or a relay.

## First contact by a claimed name

A tag needs a secret both sides hold, and there are exactly two ways to come by one: an
acquaintance made in the world, which the section on discovery states, or a claimed name. Neither
is privileged and the second is not required. A record that claimed no name is reached exactly as
one that did — the same tag, the same holder, the same path — because everything after a secret
exists is one mechanism. What a name adds is a single thing, that somebody holding nothing but
the name establishes that secret without meeting anyone, and what it costs is stated at the end
of this section.

Two strangers hold no secret. A claimed name closes that gap without an address: the slot of a
name carries a **contact root**, and the tag of first contact is derived from that root and the
height of the last cemented window, by the rule above and by no other. The holder of the name computes it because they published the root; the
stranger computes it because they know the name; nobody else has a reason to, and nothing about
either party enters it.

What crosses that point is a **request** and never a letter. It carries one encapsulation to the
contact key under the post-quantum mechanism Canon fixes and nothing else, in a cell of the one
size everything on the wire travels in. Both sides derive the secret of the correspondence from
it by the derivation Canon holds, and the sender holds that secret at the moment it encapsulates,
so nothing waits for an answer: the request and the first letter leave in the same window, the
letter under an ordinary tag like every letter after it.

**There is therefore no difference at all, rather than a difference that ends after a letter.** A
correspondence begun by a name and one begun by acquaintance are one object from the first letter
onward — the same tag, the same holder, the same path, the same shape, the same slot — and there
is no second kind of pipe for an implementation to build or an observer to tell apart, exactly as
there is no identifier for either of them to compare. What a name gives a stranger is what a
meeting gives an acquaintance and nothing besides: one secret, from which one one-time tag
follows. Asking for it automatically is the whole of what a name does, and no letter has ever
travelled through the point where the asking happens.

What this deliberately costs: the point of a claimed name is computable by anyone who knows the
name, so an observer may deposit there or watch for deposits. What it learns is that somebody
asked. It does not learn who asked, whether anyone answered, or anything whatever of a
correspondence — no letter, no size and no moment of one touches that point, because
correspondence does not travel through it. One request is indistinguishable from another and a
genuine one from a probe; requests are placed in the canonical slot like everything else, so
their number and moment carry no signal; and one that is not collected decays with its window
like any other deposit.

**Invariants of first contact:**

- A contact root is a public value of a claimed name and of nothing else; a record without a name has no contact point, and none can be derived for it.
- A first-contact tag lives one window, exactly as any tag does, and a deposit under a past one is refused in silence.
- The point of a name carries a request and never a letter: a request holds one encapsulation and nothing else, and an implementation that sends content through that point fails this invariant.
- Every letter of the correspondence, the first one included, travels under an ordinary tag derived from the established secret; deriving a tag of correspondence from the contact root is a defect a conforming implementation must fail on.
- The holder answers from the established secret and never from the contact root, so the answer is not attributable to the name.
- A request is opened only by the holder of the contact key; a deposit that does not decapsulate is discarded without a reply, so the point cannot be probed for liveness.

## The canonical slot

A frame leaves in the canonical slot of its window, derived from the window and the sender's
**ephemeral identity** — never at the moment a person pressed a key.

**The ephemeral identity** is a value a sender derives, for one window only, from its own secret
and that window, under the domain Canon names for it. It never leaves the device and appears in
nothing published: its only use is to place this sender's slot inside the window, so that two
senders do not collide and no sender chooses when to speak. It is fresh every window, so the
slot a sender occupies this window says nothing about the slot it will occupy in the next. Reactive sending is a
watermark by timing, and it is the root of the whole class of attacks the rest of this document
defends against.

Because sending is canonical, one step of a path mixes everything the window has accumulated:
correlation by time between the entry and the exit of a path is closed **by the clock itself**,
without a mixer. What other networks build a mix-net for is here already paid for by the
construction of time.

**A late cell is not accepted.** One arriving outside its slot is extinguished in silence. An
active observer need not drop traffic — it suffices to delay it in a pattern and recognize the
pattern at the other end. Refusing late arrivals turns a watermark into loss, and loss is
closed by the redundancy below rather than by asking again.

**The redundancy that makes refusal affordable.** A delivery is cut into cells and encoded so
that any sufficient subset of them reconstructs the whole; the fraction of cells a receiver may
lose and still reconstruct is fixed in Canon with its derivation. Asking again is
what this replaces, and deliberately: a repeat is a pattern, and a pattern is what an active
observer is trying to induce. A sender that retransmits on loss undoes the rule above. The rule works only because the slot comes from the chain: a slot
that depended on somebody's clock could be shifted by anyone.

## Asking what a slot publishes

A stranger who knows a claimed name derives its slot and asks the network for the contact root it
publishes. The asking device presents the slot and the nullifier of a reach for the window; the
machine holding that slot answers with what the slot publishes, and refuses in silence a nullifier
already seen in that window. One slot is asked at a time and never a bucket of them: a bucket would
hand a sweep in one exchange everything the bound of one reach per window exists to price.

What the answering machine learns is a slot and that some record spent its reach — never who asked,
never whether anything followed.

## A channel

A channel is what a person publishes to strangers. Its slot is taken in the plane of names and
Identity states that taking; this document states where a publication stands, how a reader takes
it, what it costs whom, and what any of it is observable by.

**The barrier against a space filled with empty channels is one this network already carries.** A
channel costs a slot, and a slot costs a reach into the space of slots, of which a record holds one
per window whether it takes a slot or asks what one publishes. Nothing here is priced in money, and
nothing needs to be.

**A publication stands at a point of one window, not at the slot.** The slot names the channel for
as long as it is held; the point is derived from the slot and the window by the derivation Canon
fixes, and it moves every window as every point of this network moves. Both sides compute it
without asking anyone: the holder because it holds the name, the reader because it knows the name.
The machine standing at that point is found by the rule that finds the holder of any tag.

Two things follow, and they are why the point takes the window at all. Nothing stands anywhere
longer than one window, so no machine accumulates a channel and the rule that no permanent mailbox
exists holds for this object exactly as for a pipe. And the machine that will carry a given channel
next window is a different one, so a channel cannot be aimed at a chosen machine: a name ground
until its slot lands on somebody's commitment buys one window of it and no more.

**A publication is a deposit whose right to take is public, and that is its only difference from a
letter.** The publisher deposits at the point of the window the head and the cells of the body,
encoded with the redundancy this document fixes like any delivery. A reader collects them and
verifies: the head under the key the slot published, and every cell against the root the head
carries. Nothing else is trusted — not the machine that answered, not the device that handed a
cell over, not the order they arrived in. A cell that does not fold to the root is discarded, and
a reader that already holds a body may serve it to another, which nothing obliges it to do and
nothing rewards.

**Collecting is not a reach.** A reach is priced because the space of slots is enumerable and
sweeping it must cost something; a reach is what a reader spends **once**, to learn what a slot
publishes — for a channel, the key its publications are verified under. After that the reader
computes the point of each window itself and collects, and collecting is carriage like every other
collection in this network. Were reading itself a reach, one record could follow exactly one
channel and only by spending its whole window on it.

**One publication per window.** The machine at the point accepts one head for one slot within one
window and refuses a second in silence, so the chain advances at the rate of its rounds and at no
other.

**A channel is alive while its holder keeps depositing it.** A publication is not stored by the
network and is not carried into the next window: to stay readable it is deposited again, window
after window, until it is superseded. This is stated rather than softened, because it is a real
cost and a real property. The cost falls on the publisher, which is the party that wants to be
read; the property is that a channel whose holder falls silent stops being readable, and what
survives of it is what its readers kept for themselves. The network holds nothing for anybody, and
this object is no exception to that.

**What this deliberately costs.** The machine at the point of a widely read channel answers many
collections within that window. It carries them as the work a machine is already paid for, and
what accumulates at it is nothing: the point dies with the window and the next one belongs to
somebody else.

**Invariants of a channel on the wire:**

- A publication stands at the point of its window, derived from the slot and that window; a deposit at the point of a past window is refused in silence, exactly as under a past tag.
- One head stands per slot per window; a second is refused in silence and the refusal names nobody.
- A head is accepted only if it verifies under the key its slot published and chains to the head published before it; a head that does neither is discarded without a reply.
- A cell of a body is accepted only if it folds to the root the head carries; a reader trusts no source and asks no source twice.
- The right to take a publication is public and names no collector; the right to take mail from a pipe is sealed to one collector, and the two are never one object.
- Nothing of a channel outlives its window at any machine, and a publication carried into a second window is a defect.

## Deferred collection

A letter for a sleeping device leaves the pipe not at once but after a delay drawn by the
holder. The delay is bounded by one window and never exceeds it — the bound is canonical and
needs no number of its own, because a delay outliving its window would outlive the tag it
belongs to. The holder draws the delay uniformly over the residues of its chain not yet reached; Canon states why a
shaped profile would say more than a uniform one. It costs nothing — the recipient sleeps and the letter waits
regardless — and it severs the tie between entering a pipe and leaving it, so the moment of
sending stops being a fingerprint of the sender. To live traffic the delay is never applied.

## Waking a sleeping device

A letter waits at its holder while the device it belongs to sleeps, and waiting is the whole of
the mechanism until something wakes that device. What wakes it is a rung, and there are four of
them, ordered by how little they depend on anyone outside the network. A wake is one of two
objects whose layouts Canon holds: one carries the tag of the pipe the letter waits in and the
window it waits for — values the recipient already holds, since the tag stands on a secret it
shares — and the other carries an opaque handle in the tag's place, for the one rung the tag
itself must never travel.

The first three rungs carry the tag: a live tunnel the device already holds, a beacon of a
machine standing where the device sleeps, and the moment a person unlocks another device of
their own. All three reach the device without anyone outside the network learning of it.

The fourth rung carries the handle and exists because a device asleep under an operating system
that suspends it can be reached only through the notification service of its vendor. What that
service receives is sixteen opaque bytes and a window. It never learns the tag: the handle is
drawn at random by the machine holding the letter, kept beside the pipe it belongs to for that
window and no longer, and resolved back only by that machine. Letters of one pipe within one
window carry one handle, and a handle says nothing about which pipe it stands for to anyone
who has not stored it.

**Invariants of waking:**

- A wake carries no content, no sender and no name; a wake bearing any of them is refused.
- The first three rungs carry the tag and the fourth never does, so the vendor of an operating system holds a value that resolves nowhere outside the machine that issued it.
- A rung is chosen highest-first, and the fourth stands only when none of the first three answers; the choice is made by the machine holding the letter and is not carried on the wire.
- A handle is drawn at random and never derived from a pipe, a record or a name; it lives beside its pipe for one window and dies with it, so two pipes are not joinable by their handles and nothing of a person survives in one.
- A wake is an accelerator and never a condition: a letter that no wake reaches is delivered when the device wakes on its own, and the delivery is the same delivery.

**The key of a publisher is not a rung.** The notification service of a vendor answers only to the
publisher whose key signs the request, so a second implementation of Montana cannot enter that
door with its own key and reach a device carrying the first. This makes the fourth rung an
accelerator inside one implementation, never a step of the network: everything that crosses
implementations rides the mesh, and what the fourth rung buys is speed for those who happen to run
the same client.

## A stream

Voice and video cannot seek a direction for every packet, so their path is built once and held.
Both sides holding a session compute the tag of the current window from that session's secret
by the ordinary rule — a stream introduces no value of its own — send a handshake setup to it,
and the device reached by both splices the pipe. The point therefore rotates every window like
everything else, and holding a stream open across a boundary is recomputing the same tag both
sides already know how to compute. The
rendezvous point is neither chosen from a list nor assigned — it is **discovered**. The number
of machines on the path is the same as for anything else, no one holds both ends including the
rendezvous point itself, and the correspondents do not learn each other's network addresses.

A stream runs at a constant rate for the life of the pipe, so its volume says nothing about
what is being said.

## Carrying is the work

A device reachable from outside holds the duty of carriage by that fact alone — reachability is
proven by an accepted inbound, never declared — and Consensus states when a machine counts as living:
carrying is one of the two things that predicate requires, and this document restates neither
the other nor the gate of admission that membership passes through. There
is no state of being reachable and carrying nothing, and no class of hardware reserved for the
duty: a phone holds it on the same terms as a desktop.

This is not altruism and not a rule of etiquette: carrying is precisely the work the network
pays for. The path of distinct machines therefore brings no new price — it names the purpose of
a price already accepted.

**On a link with a sleeping device the exchange is held by the reachable side** — not with
empty filler, but with the transit it carries in any case. Otherwise the switching on and off
of a device would itself become an event of the network, and intersection by presence would
reconstruct who was online each time a recipient received mail.

## Nothing is made even

A constant rate would be the worst solution: an even round-the-clock stream is almost absent
from the network, so the defence itself would become the identifying mark, and a list of
machines would be gathered from the backbone within a day without inspecting a single packet.
Synthetic filler therefore does not exist, and neither does a price for it — the same bytes
carry other people's letters and are paid for by a share of the window.

What the sum of another's traffic with one's own does, and what it does not, is stated exactly.
It removes the profile of a single correspondence from a single line. It does **not** make the
summands inseparable: separating superimposed flows by their envelopes is a standard technique
requiring no machine on the path, and against an observer of both ends of a path the correlation
of envelopes remains possible. Its price is set by the delay profile and the volume carried,
never by the unpredictability of what people write.

## Entry, and failure

The set of entries holds `outbound_connections` machines and is derived from the sender's own
secret and the period of adaptation, so an outsider cannot compute it and the sender cannot
choose it. The derivation is in Canon; the selection runs over the machines the sender knows,
ordered canonically by the commitment each publishes about itself, and an index that repeats is
advanced to the next unused machine, so the set holds that many distinct entries or as many as
the sender knows. It rotates once per period and at no other moment, so neither a failure nor a
send changes it. A fresh choice for every send would drive the probability of
striking a hostile entry to one over enough sends.

**A failure changes no choice.** A dropped connection selects no new entry — otherwise an
adversary tears the link until the victim settles on the adversary's device. Every hop's layer
is authenticated and a failed check is extinguished in silence: an error reply is itself
information. A header presented twice is discarded in silence by the digest set below.

**The digest set.** Every device keeps, for the current window only, the set of digests of the
step-headers it has accepted. A header whose digest is already in the set is discarded without
an answer. The set is emptied with the window and no separate expiry is introduced — the window
already sets the horizon of freshness, and a lifetime of its own would be a second clock.

## What a device spends on a stranger

A device reachable from outside answers links it did not choose, and that is the duty of carriage.
What it is not is an unbounded duty: a stranger able to hold memory and work without paying for
either would need no consensus weight, no lived time and no admission to make a device useless.
The bound is one number of Canon and two rules, and both rules are quantities of time rather than
of money.

**The slots are counted, and a full device refuses in silence.** A device answers at most
`inbound_slots` links it did not open. At its ceiling a further handshake is refused without an
answer of any kind — a reply saying "full" would tell a stranger it had found a device, which is
the one thing the scan of an address must not learn. There is no eviction and no ranking of the
links that stand: a ranking is a second mechanism, and whatever it ranks by is what an adversary
optimises for.

**A link that carried nothing across a window is released.** Occupation therefore costs carriage —
the very work the network pays a share of a window for — and a flood that holds slots without
carrying gives them back within one window. Nothing here observes idleness of a person or of a
machine: what is observed is that this link carried nothing, which the device holding it knows
without asking anyone.

**A deposit at a point takes no slot.** Depositing at a point of a window or of a round is one
cell and not a session. It arrives the way everything arrives — over a link that already stands,
carried hop by hop — and it opens none of its own; it is accepted inside a handshake like every
other byte here and outside one never. This is not a convenience: the holder rule is public, so
anyone computes which machines stand at the points of the next round, and a ceiling that counted
deposits would let an adversary fill those machines ahead of time and censor a round nobody could
see being censored. What keeps a device at its ceiling reachable is that the entries it chose for
itself stand outside that ceiling, so routing reaches it over links no stranger can displace.

**The entries a device chose for itself are outside this count.** They are its own lifeline,
standing at points derived from its own secret that nobody else computes, and they are neither
counted against the slots nor released by this rule. A stranger able to displace them would undo
the closure the ring of entries stands on.

**The budget belongs to the operator; its division belongs to the protocol.** How much a device
gives the wire in a window is the choice of whoever runs it — a phone on a metered line and a
machine on a symmetric gigabit are not the same device. What this set fixes is that the budget is
divided **equally** across every link the device holds, its own entries among them, and that
whatever exceeds a link's share is dropped without an answer and without being remembered. A
device feeding one link out of another's share is a device an adversary starves its neighbours
through; and because an unaccepted header is never remembered, the set of accepted digests is
bounded by the budget and needs no ceiling of its own.

**What this closes and what it does not.** It closes the exhaustion of memory and work by a
stranger who pays nothing: a slot costs carriage, and carriage is the work the window pays for. It
does not stop an adversary holding many admitted machines from occupying many slots across the
network — that is the same price the path of distinct machines is bought at, and it is stated
there. And it does not make a device reachable to everyone at once: a device at its ceiling is
reached through the mesh like anything else, because a tag chooses a holder and a holder is not a
device anyone had to be introduced to.

**Invariants of what a device spends:**

- A device holds at most `inbound_slots` links it did not open, and a further handshake at the ceiling is refused in silence.
- A deposit at a point of a window or of a round takes no slot and opens no link of its own, and it is accepted inside a handshake like everything else; a device at its ceiling serves the points it stands at exactly as one below it does, over the entries it chose for itself.
- A link that carried nothing across a whole window is released; no other condition releases one, and idleness of anybody is not observed to do it.
- The entries a device chose for itself are not counted against the slots and are not released by this rule.
- The budget of a window is divided equally across every link a device holds, and what exceeds a share is dropped without an answer and without being remembered.
- No refusal, no release and no drop produces a reply: every one of them is silence, exactly as a failed check is.

## How the objects of consensus travel

A letter has a recipient and a delivery finds them. The objects of consensus have none: a beacon
is for whoever attests it, an attestation is for a runner nobody can name, and a proposal is for
everyone at once. They travel the way a publication travels — to a **point** of the window, held
by whichever machine the holder rule places there.

Canon derives the points of a round and of a window from the window, the chain, the round and an
index, so every machine computes them alone and none can choose to stand at one. Everything a
window carries stands there: a beacon and the attestations answering it at the points of their
round, a frame at the points of the round its canonical slot names, an operation of the identity
plane likewise, and a proposal at the points of the window it closes. A machine deposits at every
point and collects from every point; the right to collect is public, because what stands there
names nobody, and a runner assembles a window from what it collects rather than from what anybody
chose to hand it. Withholding a round
therefore requires holding every one of its points at once, which the holder rule makes a
coincidence rather than a choice — and delay is all a holder could buy in any case, since every
object is verified by whoever receives it and forged by nobody.

**Why not a flood.** Sending every object to every acquaintance would put a second profile of
traffic on the wire, and a filter that dropped that profile would stop consensus while leaving
correspondence untouched — the concealment of every machine undone in a single pass. Points keep
consensus in the same cells, the same deposits and the same collections as everything else.

## Discovery without a map

No global list of devices exists and none can be assembled. A first connection comes from the
world: from a device in physical range, from somebody already spoken to who conveys a one-time
introduction, or through a door that an operator deliberately opened. A door tells only about
itself: passing it yields one handshake, never a map.

A first connection is also where a shared secret without a name comes from. The two devices run
the exchange this document opens with, and from the secret it establishes they derive every tag
of that correspondence by the ordinary rule — so the two are the one object the section on first
contact states, from the first letter onward, and a person who never claimed a name is reachable
by everyone they have met and by nobody else. Reachability without a
name is the general path rather than a lesser one; the name is the special case, and what it adds
is a stranger.

An introduction spreads by living contact rather than by a record: tags are ephemeral, an
address is never relayed beyond one step, and an acquaintance exists only while the connection
does. There is nothing to collect, so no list forms.

## Privacy is not rented

External tunnels serve the circumvention of censorship and may hide a network address, but they
are **not** a source of privacy: switched off, they take none of it away. A construction that
needed them would have no privacy of its own.

## Threat model of the wire

| Adversary | What they get |
|---|---|
| the neighbouring hop | one label of one step, and an address it cannot tell origin from transit by |
| the device serving a tenant | that this tenant is served, and nothing of what is carried — a named physical prohibition, closed only by the tenant owning the device |
| an observer of one line | a sum whose composition is unknown, at a volume that is not made even |
| the count of steps a delivery has crossed | closed: the seal array is of one size from the origin and its unused slots are drawn like any secret, so a hop reads no position of its own and no length of the path |
| how much of a path remains | **deliberately observable to a hop, and named rather than implied**: a step goes toward the target by distance, so a hop that holds the target commitment sees roughly how far is left. What it does not see is where the cell has been — the distance behind it is not carried — nor who sent it, nor for whom it is destined. The exchange is taken knowingly: without it a delivery of a large network does not arrive at all |
| that some device is joining | **observable to whoever it asks**: a device holding nothing asks for the head and for the proof of a window, and asking is what joining is; it names no person, carries nothing of what the device will do, and every answer is judged rather than trusted, so what an answerer gains is the knowledge that somebody asked |
| an observer of both ends of one delivery | the correlation of envelopes, at a price set by the delay profile and the volume carried — the single case the transport invariant does not close |
| an adversary who tears connections | nothing: the set of entries is a function of the period, not of events |
| an adversary who delays traffic in a pattern | loss rather than a watermark, and loss is repaired by the erasure code |
| an adversary scanning for participants | the fact that some machine answers at some address, and no way to tell whether it is a machine |
| that a device is at its ceiling of links | closed: a refusal is silence and reads exactly as an address where nothing listens |
| that a link carried nothing in a window | **observable to the device holding it, and to nobody else**: it is the one fact the release stands on, it names no person and no machine, and it leaves the device with the window it was read in |

## Observability ledger

| Quantity | Status |
|---|---|
| the address of a recipient | closed: there is no field of address, and no address exists between windows |
| who originated an envelope | closed: no marker of position, no hop counter, one size, and a per-step label |
| origin against transit | closed by carriage: a reachable device carries others' traffic by the rule that pays it |
| two deliveries of one pipe | closed: tags of different windows do not join |
| the moment of sending | closed: the canonical slot, taken from the height of the chain |
| the shape and size of anything | closed: one cell, one type |
| the count of what a device carried | closed: rights are spent at the holder and enter no state |
| the size of one letter, to the machine holding its pipe | **deliberately observable to that holder, and bounded by the window**: the cells standing under one tag are countable, and their count is the size of the letter to the nearest group of the erasure code. It is a fact about one delivery and about no party — the holder learns neither who sent, nor who collects, nor what is carried — it joins to nothing of another window, since the tag dies with this one, and the size of a letter is not a quantity any construction can supply from bytes nobody carries |
| that a device is being woken through the notification service of a vendor | **a named contractual prohibition**: the service of a vendor sees that it was asked to wake a device, and how often. It is told sixteen bytes drawn at random and a window, so it learns no tag, no pipe, no correspondent and no content; the value resolves nowhere outside the machine that drew it and dies with the window. What remains — that some device was woken — is what a party outside the network holds by operating the door, and the rung stands last for exactly that reason: a letter that no wake reaches is delivered when the device wakes on its own |
| a live conversation on one's own line | **a limit of volume, named**: a stream runs at tens of kilobits while the floor of correspondence is units, and hiding a flow inside a smaller floor is impossible without paying for it continuously |
| both ends of one delivery | **a named physical prohibition**: delivery moves bytes at both ends, and no construction supplies volume nobody carries |
| that a device serves this tenant | **a named physical prohibition**: a machine serving a tenant receives that tenant's bytes by the definition of serving, and being served while invisible to the server cannot both hold. What it does not learn is what is carried; and where the device is the tenant's own, there is no second party left to know |
| that a device went on or off, and that mail arrived near that moment | closed: the link of a sleeping device is held by the reachable side out of the transit it carries anyway, so switching on and off is not an event of the network and intersection by presence has nothing to intersect |
| the machine a cell is being carried toward | **deliberately observable to a hop**: routing cannot move a cell toward a target without naming the target. It names a machine and never a party, many pipes of many strangers share one holder in one window, and nothing of the sender, the recipient or the letter follows from it |
| that a machine answers at an address | **a named physical prohibition**: answering is observable at the wire; what it does not reveal is whose it is or whether it is a machine |
| that some record asked what a slot publishes in a window | **deliberately observable to the answering machine**: it sees a slot and a nullifier that names nobody, and learns neither who asked nor whether anything followed |
| that a person claimed no name | closed: claiming is an act and not claiming is not, so nothing is published either way; a correspondence begun by acquaintance is indistinguishable from one begun by a name, and no quantity marks a record as nameless |
| that a contact point of a claimed name was used | **claimed by the person, not created by the protocol**: the point exists only where a name was published by a deliberate act, it is computable by anyone who knows that name, and it yields no address, no record, no other name and no evidence that a deposit was collected. What is deposited there is a request and never a letter, so no correspondence crosses it and nothing of one — content, size or moment — is observable at it. Requests enter the canonical slot like all others, so their number and moment carry no signal |
| that a channel published in a window | **deliberately observable**: a channel is a public object by the act that took its slot; a publication names no person, and nothing computable joins a channel to the record of whoever holds it |
| that a channel fell silent | **deliberately observable to whoever reads it**: a channel is readable only while its holder deposits it, so silence is visible by the absence of a publication. It is a fact about a channel and about no person: the holder of a slot is not derivable from it, and a person who wants their silence unobservable claims no channel |
| that some record read a channel | **deliberately observable to the machine at that point**: it sees a point of one window and a collection, and learns neither who collected, nor which other channels they follow, nor whether the body was reconstructed. The point joins to no other window, so two collections of one reader are not joinable |
| which channels one record follows | closed: a reach carries no index and joins to no other reach, and no subscription is held anywhere, so the set a reader follows exists on a device and in no other place |
| how many readers a channel has | closed: nothing counts them — a publisher deposits once whatever the number, and no party holds a list to count |

## Conformance set

An implementation conforms to this document when all of the following hold.

1. It derives a tag by the integer form Canon fixes, from a secret the two parties share and the height of the last cemented window, never from a public address, and it fails the negative comparison that substitutes one.
2. It treats a tag as a right: derived not stored, spent once within its window, sealed to the holder, and recorded nowhere but at the holder for that window.
3. It emits one cell of the one length Canon fixes, sealed twice — the routing layer to the next step under the directional key of that handshake, the delivery layer to the correspondent under the pipe key — with a fresh nonce for each seal, a full seal array from the origin, and consensus data carried in the same cells as correspondence.
4. It derives the label of a step under the step domain from the raw secret the two neighbouring machines share and the height of the window, taking nothing of the delivery and no index of any kind, and re-seals everything but the target commitment at every step so that no two points on a path carry one byte in common.
5. It sends only in the canonical slot, refuses a late cell in silence, and applies the bounded delay to deferred mail but never to live traffic.
6. It refuses to send at all when fewer than the fixed number of different seals can be assembled along a path, and it offers no dialogue trading privacy for speed.
7. It holds a stable set of entries as a function of the period and re-selects none of it on failure.
8. It carries others' traffic whenever it is reachable, and it holds the link of a sleeping tenant with real transit rather than filler.
9. It builds no directory, relays no address beyond one step, and assembles no list from what it learns.
10. It encodes a delivery by the Reed-Solomon construction Canon fixes — the field, the modulus and the Cauchy matrix named there — in groups of the frozen size, reconstructs a group from any sufficient subset by inverting the rows it holds, reproduces the frozen parity vector, and never retransmits a lost cell.
11. It keeps a digest set for the current window, discards a repeated header in silence, and empties the set with the window rather than by an expiry of its own.
12. It establishes a handshake in the four flights Canon lays out, by ML-KEM-768 encapsulation in both directions, folds both results with the transcript under the domain Canon names, derives a distinct key per direction, and verifies both ML-DSA identity signatures over that transcript before carrying anything.
13. It computes the holder of a tag as the least commitment standing above it among the living machines of that window, wraps to the lowest when none stands above, forwards toward that target by closest commitment among its acquaintances, and asks no party where anything is.
14. It derives a first-contact tag from the contact root of a claimed name and the height, sends through that point a request carrying one encapsulation and never a letter, carries every letter of the correspondence — the first one included — under an ordinary tag from the established secret, answers from that secret rather than from the root, and discards a deposit that does not decapsulate without any reply.
15. It reaches a record that claimed no name by the same tags, the same holder and the same path as one that did, taking the secret from an acquaintance made in the world, and it requires a name for nothing.
16. It asks what a slot publishes by the query Canon lays out, one slot at a time against the nullifier of a reach for that window, answers with that slot alone and never with a set of slots, and refuses a repeated nullifier in silence.
17. It derives the point of a channel for each window from the slot and that window, deposits at it and collects from it, refuses a deposit at the point of a past window, and carries nothing of a channel into a second window.
18. It accepts a head only against the key the channel slot published and against the head published before it, accepts a cell only against the root that head carries, deposits and collects by the messages Canon lays out — the right to a publication public, the right to mail from a pipe sealed to the window by the collect derivation — and holds no list of who reads what.
19. It spends a reach to learn what a slot publishes and never for collecting a publication, and it deposits a channel again in every window it is to remain readable.
20. It holds at most `inbound_slots` links it did not open, serves a deposit at a point of a window or of a round without taking a slot for it, refuses a further handshake at that ceiling in silence, releases a link that carried nothing across a whole window, counts neither its own entries against that ceiling nor releases them by that rule, divides the budget of a window equally across every link it holds, and drops what exceeds a share without an answer and without remembering it.
21. It deposits at every point Canon derives — a beacon and an attestation at the points of their round, a frame and an operation of the identity plane at the points of the round their slot names, a proposal at the points of its window — collects from every one of them and takes the union, treats the right to collect there as public, and floods nothing to anybody.
