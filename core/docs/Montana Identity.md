# Montana — Identity

**Version:** 3.2.0

Identity holds what a person is in Montana — and the answer is that a person is a secret and
nothing else. There is no identifier of a person in this document, because there is none in
the protocol. What a person holds is a record of their own standing; what the network sees is
a commitment to it and, when they act, a nullifier that names nobody.

## Scope

**In scope.** The record of a person and what it carries; opening a record and the bounds
that hold it; acting, and what an action publishes; changing a key; closing a record; the
fabric of time; the stratification of age; the barriers of time and what they bound; the
claiming of a name and the slot it occupies; the slot of a channel and what a space of its own
buys; the out-of-band comparison by which two people bind a handshake to a key.

**Not in scope.** Values, layouts and vectors — Canon. Notes, proofs and transfers — Value.
Windows, quorum and admission of machines — Consensus. Delivery — Network. Anchors for
applications — App.

## A person is a secret

Everything of a person derives from one seed held on their device. Out of it come the branches
Canon derives — among them the one that signs, the one that proves ownership of value, the one
that derives redemption and the one their own stored content is sealed to — and Canon holds their full set,
their domains and their lengths, so this document names a branch and never counts them. The
branches are independent: a leak of one discloses nothing of another.

Nothing of this is published. No name, no address, no number that means "this person" exists
in state, on the wire, or in any document of this set. A person who never claims a name is
indistinguishable from a person who does not exist — and that is the default, not a mode.

## The birth of a seed

A seed is drawn once, from the cryptographic source of the device, and is tested before it
becomes anyone: a block that repeats itself, leans on a few values or equals the block drawn
before it is refused rather than accepted with a warning. A source that returns such a block is
broken, and the answer to a broken source is refusal — an identity born of it would look
ordinary and be guessable, and nobody would learn that until it was emptied.

The seed is drawn by the same code in every implementation, and this is deliberate: were each
application to draw its own, the quality of the root would be a property of that application
rather than of Montana, and a person could not tell the two apart from the outside. Canon fixes
the width, the tests and the derivation; an application supplies the words to a person and
nothing else.

What a person sees is twenty-four words, and what a person holds is the seed those words stand
for. The derivation reads the seed and not the text: how the words are spaced, capitalised or
rendered changes nothing, and a phrase copied through a password manager opens the same person
as one written by hand. Four letters of a word are enough to name it.

There is one secret and no second. Montana adds no passphrase beside the words, because a
second secret is remembered where the first is written down, and the two fail in opposite
ways — the pair costs a person everything on the day memory goes, and buys a deniability that
is worth less than what it risks. The whole weight of the one secret is stated to its holder
before it is shown, once, in plain words.

The words look like those of BIP-39 and are checked like them, and the key they open is not
the same: Canon states the difference, and an application that treats a Montana phrase as a
wallet phrase derives keys that answer to nobody.

## The record of a person

A record is of one kind with a note: it is a set of quantities its holder keeps, and what the
network holds is a **commitment to it** — created once and re-made whenever its holder acts, carrying inside it everything the protocol needs to know about their
standing — the lived segments of their continuity, the height of their own actions, the
standing of their current key.

What the network holds is the tree of these commitments and the set of nullifiers spent
against them. Neither holds a name.

**Invariants of a record:**

- A record is created by a commitment and altered only by spending it and creating its successor; it is never edited in place.
- Its contents are never published; every quantity inside it is proven when needed and disclosed never.
- One action spends exactly one nullifier of the record, and a nullifier enters the set exactly once.
- Two records, and two actions of one record, carry nothing in common that an observer can join.
- A record holds no balance and never did: value lives in notes, and a person's notes are untouched by anything that happens to their record.

## Opening a record

A record is opened by its own claimant, and by no one else. There is no sponsor, no inviter,
no approver — they do not exist as notions. Two bounds hold the opening, and both are of this
plane: a one-time right, extinguished by a nullifier that names nobody, and a ceiling of
openings per window. Lived time is not among them, and could not be: the segments of a record
are earned by its own actions, and a claimant has no record to act with — a gate of lived time
at the opening would be a lock whose key lies inside it.

What opening creates is the point lived time is measured from. A segment counts as lived when
the record acted in it — one action of this plane within the segment marks it, and the rate of
one action per window already bounds how fast marking can go. Continuity is measured against
**now**, not against whenever the record was last written: the bitmap of segments is read
after shifting it by the distance from the segment it was written against to the current one,
so a record that lapsed and returned does not pass on the strength of a past that has moved
away.

The gates that consume continuity — the candidacy of a machine and the first renewal of a
name — demand a **share** of the segments and not all of them: an implementation counts the
bits set within the segments of the period in force and compares the count against

```
required_segments = ceil(segments_in_force x continuity_required_num / continuity_required_den)
```

with the multiplication before the division and the division rounding upward. `segments_in_force`
is `continuity_segments`, raised by the gate of entry under pressure to at most
`max_entry_segments`; the share holds against whatever count is in force, so one rule serves
every gate that consumes it. The proof asserts that the threshold is met; it names no record
and discloses no history.

Lived time is the one scarcity that cannot be acquired. It does not parallelize for one
holder, it cannot be bought, and there is nobody to ask for it. This is what stands where
other protocols put a fee — at every gate that guards a role or a slot, while the record
itself is guarded by the two bounds above, which is the ceiling path the invariant on state
admits.

A friendly hand may carry a newcomer's frame into the network. That is a convenience of
delivery and not a right: it hastens nothing, because the time lives with the claimant alone.

**Invariants of opening:**

- The right to open is one-time and is extinguished by a nullifier, so one claim cannot be replayed.
- A window admits no more openings than the bound Canon fixes, in the canonical order of the window, so the outcome does not depend on the order of arrival at any machine.
- Opening demands no lived time: the segments of a record begin at its opening, and every gate that consumes them stands after the record exists.
- A segment is marked lived by an action of the record within it, and by nothing else; a segment no action touched is not lived, whatever the device did on the wire.
- Opening carries no value and touches no note.

## Acting

An action of the identity plane — anchoring a hash, changing a key, witnessing, closing —
publishes exactly three things about the transition: the nullifier that spends the version
acted from, the commitment of its successor, and a proof that the transition is lawful.
Beside them stands one quantity that is not about the transition at all — the nullifier of the
rate below, which bounds how often a person acts — and nothing further. No sender, no
recipient, no chain that an observer may follow, no counter that tells a later action from an
earlier one.

**Why two nullifiers and not one.** They bound two different things and neither serves for the
other. The first spends a version and takes no window, so a version is spent once and forever
and a change of key cannot be undone by acting again from the record that carried the old one.
The second takes the window and bounds the person, so a second action of one window collides
with the first. One value in both roles leaves a hole either way: taking the window, a holder
acts twice in a window by acting the second time from the successor the first action created,
since the two versions differ; taking none, the bound on frequency disappears entirely.

**All three are published by every action, closing included.** Where an action creates no
successor, the commitment position carries a blank drawn by its emitter from its own
randomness, and the proof asserts of that position that it holds either a successor or a
closure, without disclosing which. Publishing two quantities where others publish three would
make closing visible by its shape, and the shape of an action is as much an observable as its
content.

The rate at which a person may act is bounded by a nullifier of rate of this plane, under the
domain Canon names for it — a domain of its own, separate from the one that bounds payments,
so that a payment and an action can never produce one value and refuse each other. The bound
is on frequency, and it is not a counter on the wire. It carries **no index**, because the bound
is one action per window: a second action of one window presents the identical value and collides
with the first. That is what separates it from the nullifier a payment carries, where several are
allowed in a window and the position among them is what the proof keeps secret.

## Changing a key

A change of key spends the record under the **old** key and creates the successor carrying the
new one. The old key signs the transition; the new key verifies everything after it. The
standing of the person — their lived time, their height — carries across intact, because it
travels inside the commitment rather than beside it.

A change of key produces a new fingerprint, and a handshake bound to the old one is unverified
again until the comparison is repeated.

## Closing a record

Closing spends the record and creates no successor. The record leaves the tree and the person
leaves the identity plane. It publishes the same three quantities as any other action, its
commitment position carrying a blank that nobody can open and therefore nobody can spend, so
nothing about the action says that it was a closure.

**It touches no value and cannot.** A record holds no balance; a person's notes live in the
note tree, bound to a branch of their seed, and are untouched by the closing. Somebody who has
closed their record goes on spending their notes exactly as before — **a payment requires no
identity at all**. Closing therefore burns not one coin and leaves the conservation of issuance
entirely intact.

## The fabric of time

People witness each other's continuity. Witnessing is an action of this plane and publishes
what every action of the plane publishes and nothing beside it: the nullifier of the current
record, the commitment of its successor, and a proof. Of the fabric itself **one** quantity
exists, and it lives inside that successor commitment rather than beside it — a single root,
built like this: for each thing observed, a leaf commits to what was seen — the
record commitment of the other and the window it was seen in — under a blinding factor of its
own, so that two observations of one person are not comparable and no leaf can be guessed from
anything public. The leaves are ordered lexicographically and **take positions from zero
in that order**, then folded by the tree construction Canon fixes for a growing sequence, under
the fabric leaf and node domains Canon names. The position rule matters as much as the fold: the
construction fills from position zero upward, so without a stated assignment two holders who saw
the same people in a different order would commit to different roots. Ordering the leaves makes
the root a function of the **set** of what was witnessed and not of the sequence in which it
happened, which is also why the moment of an observation cannot be read back out of it. Only
the root goes on, and it goes into the successor commitment, so no object of the fabric ever
appears on the wire or in state.

From that root the chain learns neither with whom the participant exchanged witnesses nor how
many there were: one root of thirty-two bytes stands whether one edge was seen or a
hundred, and it is proven rather than shown.

This is what makes lived time provable without a graph: the fabric records that time passed
and was seen, never who saw whom.

## Age and the barriers of time

Records are stratified by age, the boundary of each bucket being the base of Canon raised to
the index of the bucket and multiplied by the period of adaptation. Age raises standing and
nothing else; it is carried inside a commitment and proven, never published.

Every barrier of this plane is a quantity of time: one action per window per record, a ceiling
of openings per window, a required continuity at the gates that stand after a record exists, a
threshold of standing. **Not one is a quantity of money.** A barrier of time that named who
cleared it would buy scarcity at the price of a graph; each of them is therefore proven and
not published.

**The price of having no names, stated rather than argued away.** A plane that names nobody
cannot be pruned for inactivity — inactivity of whom is not observable. Of the three paths
open to a growing structure, this plane uses the ceiling per window for the record itself, and
the barrier of lived time for every role and slot granted after it — the time a record proves
is earned by its own actions, so a gate of that kind stands only where a record already
exists. Pruning it does not use, and that is a consequence of the second clause of the
invariant on graphs rather than an oversight.

## Claiming a name

A name is what a person publishes about themselves, and publishing it is deliberate. Nothing
about a record requires it, and a record without one is the norm.

**A name occupies a slot, and a slot holds no identifier.** The slot is derived from the name
itself, so anyone who knows a name can compute where it lives; what the slot holds is not a
person but a commitment and a way to reach whoever holds it. Two names cannot be joined, and a
name cannot be joined to any action of its holder — the record, the payments and the witnesses
of that person go on naming nobody.

**Taking a name, in three acts.**

- **Commit.** The holder publishes a commitment over the slot, a blinding factor of their own, and the tip of a chain derived from their seed and that slot. Nothing in it names them, and nothing yet says which name was meant.
- **Reveal.** Within the reveal period the holder publishes the name, the blinding factor and the contact root of that slot, and anyone recomputes the commitment. The contact root is the encapsulation key Canon derives from the seed and the slot; it is what makes the name reachable, and it is the only public value a name carries beyond the name itself. A slot revealed to be already held is refused, and the first commitment cemented for a slot is the one that holds it — uniqueness comes from the order of the chain and from no other party.
- **Renew.** Before the renewal period runs out the holder publishes the next link of the chain backwards: a value that hashes to what was published before. Anyone verifies it with one hash, nobody learns who published it, and a name whose renewal does not come is released to whoever takes it next.

A name works from the moment it is revealed, and it is **held** from the first renewal: that renewal carries the same proof of lived continuity every gate of the protocol carries, so a seed drawn to sweep up names and abandoned holds nothing — the proof does not assemble, the renewal does not come, and the slot returns. Between the reveal and that renewal a name is a candidacy like any other, and the holder is told so before they claim it.

**A channel is a slot of this plane in a space of its own.** It is taken by the same three acts —
commit, reveal, renew — spends the same reach of the window, is held from its first renewal by the
same proof of lived continuity a name is held by, and is released the same way when a renewal does
not come. A seed drawn to sweep up channels and abandoned holds none of them, for the reason it
holds no names. Two things differ and only two: the space, so that one written word resolves
to two slots that are not computable from each other and a channel is joined to the record of
whoever holds it by nothing; and the value a reveal publishes, which is the key its publications are
verified under rather than the key a stranger encapsulates to. What a publication is and how it
reaches a reader is Network's; the layouts are Canon's.

**The three acts above — of a name and of a channel alike — are objects of the plane of names,
not actions of the identity plane.** They spend
no nullifier of a record, they create no successor to one, and they carry nothing of whoever
publishes them — which is why a reveal publishes a name without publishing a fourth quantity of
an action, and why holding a name adds nothing an observer can join to what its holder does.
Canon holds their layouts.

**Why a chain and not a signature.** A signature would name a key, and a key names a person. A
chain proves continuity of the same holder without carrying anything of them: each link is
verified against the previous one, and the links run out — the length Canon fixes is how many
renewals a taking is good for, after which the name is taken afresh.

**Renewal happens at the start of its period, not when the holder remembers.** The moment is
computed from the chain and the period, so the time of publishing carries no signal about
presence, activity or timezone.

**A name resolves to a request, never to an address.** What the slot holds is the contact root
Network derives the first-contact tag from, and what a stranger who knows a name may do with it
is ask once for the one-time tag a meeting would have given them in person. They learn nothing
else: not an address, not a record, not another name, not whether anything was delivered. A directory of names to participants therefore does not
exist, and cannot be assembled from what the slot publishes.

**Invariants of a name:**

- A slot is derived from the normalized name alone, so two implementations resolve one name to one slot.
- A commitment holds the slot, a fresh blinding factor and the chain tip, and nothing else; a commitment naming anything of its holder is refused.
- A reveal is accepted only within the reveal period after its commitment, and only for a slot no cemented commitment already holds.
- A renewal is accepted only if hashing it once yields the value published before it, and only within the renewal period.
- A name whose renewal period passes is released; the slot returns to free and carries nothing of whoever held it.
- Releasing is not reversible by the former holder, and holding is not transferable: a name is taken by living with it, and there is nowhere to sell it.

## Binding a handshake to a key

Two people who wish to be certain they hold each other's true key compare a fingerprint
derived canonically from that key, outside the handshake that delivered it. Canon holds the
derivation.

The invariant here forbids not an action of a person but a lie about the state. A client does
not block a first message: it marks the handshake unverified and keeps the mark until a
comparison is made. Blocking would kill the very case the mark exists for — a stranger has
nothing to compare and nobody to compare with, and a network where no one may write first is
not a network. The mark is removed by a comparison and by nothing else: not by time, not by
the number of messages, not by a dismissal. A code scanned from the other person's screen
verifies at once, and no mark appears.

## Observability ledger

| Quantity | Status |
|---|---|
| who a person is | closed: no identifier of a person exists in the protocol |
| that a particular person acted | closed: an action publishes a nullifier, a commitment and a proof, and none of them names anyone |
| two actions of one person | closed: nothing common travels between them, and the nullifier that bounds actions in one window does not join to the one of another, and it is a branch of its own — never the one that bounds payments |
| the lived time, height and standing of a person | closed: they live inside a commitment and are proven, never published |
| with whom a person witnessed | closed: the fabric publishes a commitment over blinded leaves |
| the contents of what is anchored | closed: only a hash reaches the network, and the content stays with its owner |
| that some record reached into the space of slots in a window | **deliberately observable**: a nullifier of a reach names nobody, joins to nothing of another window, and is what the bound of one reach per window — a lookup or a taking alike — is enforced against |
| that a name was claimed | **claimed by the person, not created by the protocol**: publicity is a deliberate act, its consequence is stated to the person before the act, and the edge lasts as long as the name is held |
| that a channel slot was taken | **claimed by the person, not created by the protocol**: taking a slot is a deliberate act, it publishes a commitment naming nobody and a key belonging to the slot, and nothing computable joins that slot to the record of whoever took it or to any name they hold |
| that some record was opened in a window | **deliberately observable**: it names nobody, and it is what the bound per window is enforced against |
| how a seed was drawn | closed: the source and its tests are fixed by Canon and run inside the device; nothing about the draw leaves it |
| the words of a person | closed: they exist on the device and on whatever a person writes them onto, and no path of the protocol carries them |
| the roots of the tree and of the set | **deliberately observable**: quantities about the whole from which no participant is derivable |

## Conformance set

An implementation conforms to this document when all of the following hold.

1. It derives every branch of a person from one seed and publishes none of them.
2. It holds a record as a commitment, alters it only by spending it and creating a successor, and never edits it in place.
3. It publishes for an action exactly a nullifier, a commitment and a proof, and it emits no field that names a person.
4. It opens a record only against a one-time right extinguished by a nullifier, within the bound Canon fixes and in the canonical order of the window, and it demands no lived time at the opening — continuity is consumed by the gates that stand after a record exists, and a segment is marked lived only by an action of the record within it.
5. It carries standing across a change of key inside the commitment, and it treats the handshake as unverified again afterwards.
6. It closes a record without touching a single note, and it lets a closed person spend exactly as before.
7. It carries a witness as a root over blinded leaves inside the successor commitment, and publishes no object of the fabric beside it.
8. It expresses every barrier of this plane in time and never in money, and it proves each rather than publishing it.
9. It marks an unverified handshake as unverified until a comparison is made, and it removes the mark by nothing else.
10. It draws a seed through the sources and the health tests Canon fixes, sums at least three of them, refuses a block that fails one of them, refuses when its self-test fails, and draws no identity material by any other path.
11. It derives the master seed from the entropy rather than from the text of the words, accepts a phrase in any case and in four-letter form, and reproduces the frozen chain of Canon from the words to the key a record answers with — which is where the chain ends, no quantity standing for a person beyond it.
12. It holds one secret and offers no passphrase beside it, and it states the weight of that secret to its holder before showing it.
13. It derives a name slot from the normalized name alone, refuses a name outside the alphabet and the bounds Canon fixes, and resolves a name to a first-contact capability and never to an address.
14. It spends the nullifier of a reach for the window on every taking of a slot and on every ask of what one publishes, and it refuses a second reach of one window in silence.
15. It takes a name only by commitment, reveal within the reveal period and renewal within the renewal period, verifies a renewal by a single hash against the value published before it, and releases a slot whose renewal does not come.
16. It takes a channel slot by the same three acts in a space of its own, holds it from the first renewal by the same proof of continuity a name is held by, publishes at its reveal the key its publications are verified under rather than the key a stranger encapsulates to, and joins that slot to the record of its holder by nothing computable.
17. It keeps the words out of every shared surface of the device — clipboards that leave it, screenshots, backups, logs and diagnostics — and out of every path that leaves the device at all.
