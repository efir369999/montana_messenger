# Montana — Value

**Version:** 3.6.0

Value holds what money is in Montana and how it moves: the note, its commitment, its
nullifier, the trees they live in, the fixed shape of a spend, what the proof asserts, how a
right to a window's share is extinguished, and the single mechanism by which an owner may disclose
one payment. It holds no number — Canon holds those — and it names no party, because none
exists.

## Scope

**In scope.** The note and its three fields; the commitment and why it is blinded; the
nullifier and why it is derived from position; the note tree and the set of nullifiers; the
shape of a spend and its filler; the horizon of proving; what the proof asserts and what it
withholds; the redemption of a right; the conservation of issuance and its honest price; the
double spend; disclosure by an owner.

**Not in scope.** Values and layouts — Canon. The issue of a right and the movement of the
clock — Consensus. Records of people and keys — Identity. How a payment travels — Network.

## The note

A note is three fields: an amount, the payment key of its owner, and a blinding factor. None
of them is ever published. What is published is a commitment to all three.

**The blinding factor is not optional.** Without it a commitment is enumerable: the set of
meaningful amounts is small and the payment key of a recipient is known to whoever paid them,
so an observer would test "this note is such an amount to so-and-so" by direct hashing. The
blinding factor makes a commitment indistinguishable from thirty-two random bytes even when
both other fields are guessed.

**Two branches of secret, and they do not meet.** One branch proves ownership, another derives
redemption. A leak of either discloses nothing of the other.

**A commitment and a nullifier are not linkable.** The commitment carries the public part of
the owner's key, the nullifier the secret one. Joining them requires the secret, which the
network never holds — so which note was extinguished is underivable and the trace of a spend
breaks off.

## Redemption is derived from position

A nullifier is derived from the redemption branch, the commitment, and **the position of the
leaf in the tree** — never from randomness chosen by the sender.

This is a correction of a known and costly class. Where redemption was derived from a value
the sender picked, a sender who repeated that value in two payments to one recipient made the
second note permanently unspendable: spending it presented an already extinguished nullifier
and was refused as a double spend. The recipient saw a valid note, the proof agreed, and the
money was dead — extortion when done deliberately, and destruction of another person's funds
when a random number generator merely failed. The defect is old enough to have a name of its
own in the field.

A position in an append-only tree is unique by construction. Two notes identical in every
field therefore have different nullifiers, and no choice of the sender can affect whether a
recipient can spend. The position is already part of the path the proof carries, so nothing
new is added to close this.

## The trees

Two structures hold the whole of money.

- **The note tree** is append-only: a commitment enters it at the next free position and never leaves. Its depth is a number of Canon, chosen so that the tree is never the binding bound: at the rate of frames a window admits and at the cap of chains, filling it takes about a century and a half — stated as it computes rather than rounded upward — and what limits payment is throughput rather than positions.
- **The set of nullifiers** is a sparse tree keyed by the nullifier itself. Entering it is what spending means.

A third structure holds the rate: the **rate set of the horizon**, which holds the rate
nullifiers presented while the standing stride of the horizon stands, and nothing else. It is
not a tree and it does not persist beyond the stride: a value enters as a frame applies and
the set empties when the horizon moves to the next stride, because what retires it is the
proof itself — a frame cannot assert a window of a stride the horizon has left, so memory kept
past the stride would only accumulate what nobody may read. A rate nullifier already within
the set is a refusal.

Neither of the two trees introduces a construction of its own, and neither borrows the other's: Canon fixes two
shapes of tree — append-only indexed by position, and sparse keyed by a value — and each of
these two uses the one that fits it. What they share is the shape of the fold and the empty
values; the walk and the proof differ, and using the wrong shape yields a different root from
the same contents.

**Invariants of the trees:**

- A commitment enters the note tree at the lowest free position and is never removed or replaced.
- A nullifier enters the set exactly once; a second entry of the same value is a refusal, not an overwrite.
- Both roots are recomputed from the structures themselves and are compared, never accepted on the word of whoever published them.

## The shape of a frame

A transfer of value is not an action of a person: it has no sender, no link to a previous
operation, it extends no personal chain and increments no counter of one. It is the **meaning**
of a frame, and a frame has one shape whatever it means.

A frame holds a fixed number of **spends**, each of a fixed number of positions — the same
object Canon counts by `spends_per_frame` and `items_per_spend`. Within a spend the
positions are, in order: redemptions of what is consumed, commitments of the notes created,
and one rate nullifier. **A redemption position consumes a note or a right to a window's
share, and the two are one kind** — the positions are typeless, their count does not vary with
what fills them, and a verifier that handled only the note branch would refuse every redemption
of a right while believing itself correct. A spend carrying no transfer holds filler in every position, drawn by
its emitter from its own randomness and by no public formula.

**The emitter of a frame is the one who spends.** One proof spans every spend of a frame, so the
secrets of its redemptions stand with one holder: a frame is composed and proven on the device of
its payer, and a machine includes what it could not have composed. Where fewer frames arrive than a
window holds, the shortfall is made up by the runner with frames of filler alone — the filler
branch consumes no secret, so a runner can prove what it cannot read, and a window always carries
the count of frames Canon fixes.

**An unused position carries a note of zero value**, indistinguishable from any other, so a
payment consuming one note looks exactly like a payment consuming two, and the shape says
nothing about the character of what was paid.

**A spend has no empty state, and that is what makes the count unobservable.** Every position
of every spend enters the structures of the window by its position alone — redemptions into the
set, commitments into the tree, the rate position into the rate set — for a filler spend exactly
as for a spend carrying a transfer. Two things make the branch undetectable and neither is
optional. The proof discloses no count of meaningful spends: it asserts, for each spend
independently, that the spend carries a correct transfer **or** that it is filler, and the
number of true first branches appears in no public quantity. And insertion runs in the
canonical order of positions, so a frame always adds the same number of leaves. Were unused
positions omitted, every validator — who must rebuild the tree to accept a window — would read
the number of transfers off the number of new leaves, and the frame would carry a counter in
its shape while carrying none in its layout.

**Filler is harmless in both structures.** A filler nullifier can block no real note: making a
filler value equal a nullifier not yet published would require a preimage of SHA-256. A filler
commitment can be opened by nobody and therefore spent by nobody: no key to it exists and its
amount was never chosen.

**The proving root is canonical, and it is the fold of a stride.** Every transfer proves that the
root its redemptions stand under is a leaf of the horizon of proving of the window the frame
applies in — the fold Canon derives over the aligned stride of `proving_horizon` note roots
standing for that window, every root of it at least `proving_lag` behind. The horizon is not a
field of the frame, and no observable choice exists: which of its roots a proof stands under is
inside the proof, which is of one length and discloses nothing. A freely chosen root would say
how recently its bearer synchronized and would sort payers into classes; a hidden leaf of a
canonical reach says nothing — and what the stride buys is time: its fold enters the transcript
of a proof as one value standing for `proving_horizon` windows of landing, so a proof begun the
window the stride stood remains provable until the horizon moves. The word is deliberate: **an
anchor** in this protocol is the act of publishing a hash of content, which App owns, and it has
nothing to do with the root a proof stands on.

**No note travels beside a letter.** Value is the content of a message; no second object
accompanies it. Two entities where one suffices would restore distinguishability through form.

## What the proof asserts

For every redemption, one of two branches holds and the proof does not say which: either a note
exists whose commitment lies in a tree whose root the horizon of proving holds and the bearer
knows its ownership secret, or the bearer holds an unextinguished right to the share of a window and the
machine secret that proves it. In both branches the nullifier published is derived from what was
consumed by the canonical formula of that branch. What is created equals what is consumed. The rate nullifier
belongs to a window of the standing stride — every window of which stands before the one the
frame applies in — and its index is within the bound, neither the window nor the index being
published, so a first payment of a window is indistinguishable from a fourth, and a frame
proven over many windows from one proven in its own. And for each
spend, that it is either a correct transfer or filler, without saying which.

The proof is of fixed length. Its branch is never disclosed.

**Invariants of a frame:**

- The number of positions is exactly what Canon holds, and the length of the proof is what Canon derives from the height a frame's description is built at and from the parameters of the scheme; any other length is a refusal before anything is parsed. The length is one value for the scheme in force — a proof whose length varied with what it proves would carry the count in its size. Canon fixes the scheme and the parameters that yield that length; an implementation computes it from them rather than choosing it.
- The roots a proof may stand under are those the horizon of proving of the window the frame applies in holds — the fold of its standing stride; a frame carries none, and no observable choice exists — which leaf a proof stands under is inside the proof. The stride is one reach for every window-bound input: the root, the window of a rate and the computed moment of a right range over the same stride, and the public inputs of a proof stand for the whole standing period, which is what lets a proof begun early land late.
- Every nullifier is absent from the set, and within one frame the nullifiers are pairwise distinct.
- Every rate nullifier is absent from the rate set of the horizon.
- Length and bound checks run before allocation and before the verification of the proof, which is expensive.
- A frame is proven on the device of its payer, and the memory that proving demands is sized by the width of the trace, which the constraint set decides; a proof carries one length, one verifier and one transcript, all frozen in Canon, and the acceptance of a proof is conformance-checkable when the artifact Canon binds by hash is published.
- After a frame applies, every nullifier and rate nullifier enters its set, every commitment enters the tree, and both roots are recomputed. No balance is touched, because none exists.

## Extinguishing a right

A right to a window's share creates no note. It is extinguished inside an ordinary payment: the
bearer proves entitlement and consumes the right **in a nullifier position like any other**, so
nothing about the payment says that a right was what it consumed. The moment of extinguishing is
computed from the machine's secret and the window rather than chosen, and the landing stands
while the stride holding that moment stands as the horizon of proving: nothing lands before its
moment, the late is bounded by the standing period, and the slack is the proving time of a
device — which nothing published carries — so there is still no handwriting to read.

Nothing becomes public — not even that a right was what was consumed. The bound holds without
anyone seeing it: the nullifier of a right is derived from the machine's secret and the window,
so a machine that tried twice would present the same value and collide with itself, in a set
where no observer can tell which entries are rights and which are notes.

## Conservation of issuance

- **Per payment:** what is created equals what is consumed, asserted by the proof and never by adding open numbers.
- **Per window:** the change of supply equals the mint of that window — one right per living machine, each extinguished by exactly one nullifier — with the indivisible remainder carried forward.
- **Globally:** the sum of unspent notes, unredeemed rights and the carried remainder equals the supply, held by proof and induction and **unverifiable by addition** — amounts are hidden and rights are private.

**The honest price.** The ability to detect a breach of issuance by simple summation is lost
together with open amounts, and no reconciliation of balances replaces it. The integrity of
issuance rests on the correctness of the proof scheme. From that follow obligations rather
than wishes: two independent implementations of the verifier must accept and reject
identically, and a divergence between them is a release blocker.

## The double spend

Spending is entering a nullifier into the set. A second entry of the same value is refused.
Nothing about the refusal says which note, whose, or of what amount.

## Settlement

**A payment settles when it stands, and it waits for no window.** Applying a frame enters its
nullifiers into the set and appends its commitments to the note tree at the lowest free
positions; a payment is received at that moment. A note spends onward from the moment the
stride holding the root of its window stands as the horizon of proving — between `proving_lag`
and `proving_horizon + proving_lag − 1` windows later, when every verifier holds that fold —
and its owner then walks the path the tree answers with and proves under the leaf of the
horizon that holds it. Nothing of the pulse stands between a payment and
its receipt — no beacon is waited on, no cement moves, no proposal is assembled — and the
window carrying the payment closes afterwards without reaching back into it.

**The unit of that promptness is an echo, never a second.** Time is counted in rounds, in windows
and in periods, so what this document fixes is that a payment crosses in the turn of the round whose
slot carries it, and the floor under that turn is the speed of light over the geography of the
living, exactly as the pace of a round is. What an operator observes on a clock follows from where
the two people stand and follows from nothing here.

**What one echo rests on, and what the close of a window adds.** A frame stands at the points of the
round its slot names, and every machine holding those points verifies it against its own state and
applies it or refuses it there; the frame that enters a nullifier first is the one that stands. Two
frames spending one nullifier stand at the points their senders' slots name, so machines holding one
and not the other separate them by the canonical order of the window that carries them. What a
recipient holds within one echo is therefore the agreement of the machines holding the points of the
frame it was paid by; what the close of that window adds is the agreement of the cement. The two are
different strengths, and this document names which is which rather than letting one word cover both.
What makes the race visible before the window decides it is the notice.

**The notice of a spend.** A frame deposits, at the points Canon derives from every nullifier it
spends, one notice: that nullifier and the identifier of the frame spending it, and nothing else. It
carries no key, no signature, no amount and no party, so it publishes nothing the frame does not
publish already. Two frames spending one nullifier therefore meet at one point wherever they were
sent from and whatever slot carried either of them, and a reader of that point sees the race in the
turn of one round rather than at the close of a window.

**The notice reveals, and it decides nothing.** Which of two frames stands is the canonical order of
their window and nothing else. A rule letting the point decide — the smaller identifier, say — hands
the decision to a value the second author chooses after seeing the first: the identifier of a frame
is taken over bytes that include blinding factors its own author draws, so a second frame is brought
below a first in a couple of drawings, and whoever paid last would take back what it paid.

**A repetition adds nothing; a second frame is the race.** The point holds what arrives, and the two
are told apart the way the cement already tells them apart for a part-nullifier: a notice repeated
whole — one nullifier naming one frame — adds nothing and is lawful, while a notice of that
nullifier naming **another** frame stands beside the first, and that pair is the race itself. A rule
refusing the second as a repetition would refuse exactly the thing the mechanism exists to show. So
a reader that finds one frame named at every point of a nullifier takes its payment in that turn; a
reader that finds two frames named at any of them, or finds the points naming different single
frames, waits for the window that decides.

**What the notice costs, and what it cannot cost.** A frame spends `spend_inputs × spends_per_frame`
nullifiers, so it deposits that many notices of sixty-four bytes — three hundred and eighty-four
bytes against a frame of `frame_len`, under a fifth of a percent, and carried by the same factor of
replicas and hops every object of consensus is carried by, so the cap of the schedule is unmoved.
Depositing the frame itself at those points instead would multiply the payload of every payment by
the count of its nullifiers and is refused for that reason. And the failure of the notice is bounded
from below by the close: a notice withheld, a notice forged against a frame that stands nowhere, or
points that disagree all leave a reader waiting for the window it would have waited for anyway. No
attack on this mechanism reaches past its absence.


**Invariants of settlement:**

- A payment is received the moment the frame carrying it is applied, and its note spends onward the moment the stride holding the root of its window stands as the horizon of proving; no rule of settlement reads a beacon, a cement or a proposal.
- The position a payer walks is the one the tree answered with, and the root its proof stands under is one the horizon of proving holds.
- Settlement is counted in the round that carries the frame; no quantity of a clock enters it, and no duration is fixed for it anywhere.
- Within one echo a payment carries the agreement of the machines holding the points of its round, and the cement of its window raises that to the agreement of the quorum; neither strength is stated as the other.
- A notice carries a nullifier and the identifier of the frame spending it and nothing else; it is unsigned, and no party is derivable from it.
- A frame deposits one notice at every notice point Canon derives from every nullifier it spends; a notice standing anywhere else is not of this mechanism. A notice repeated whole adds nothing and is lawful; a notice of one nullifier naming another frame stands beside the first, since refusing it would refuse the race this mechanism exists to reveal.
- The point of a nullifier reveals a race and decides none: which of two frames stands is the canonical order of the window carrying them, and an implementation deciding it at the point is wrong whatever rule it decides by.
- A reader that sees one notice at every point of a nullifier settles in that turn; a reader that sees two, or points that disagree, waits for the close — so the fast path degrades to the window and never below it.

## Disclosure

The owner of a payment may disclose **one** payment and nothing beyond it: the commitment, its
fields, its position and the path to the root of the window in which it appeared. Verification
recomputes the commitment and folds the path. Neither the payments before it, nor those after,
nor the owner's remainder are touched. No standing viewing key exists: a secret that discloses
everything forever is a hazard, not a feature.

## Observability ledger

| Quantity | Status |
|---|---|
| payer and payee | closed: a transfer has no parties, and the proof discloses neither inputs nor outputs |
| amount and remainder | closed: the amount lives inside a commitment under a blinding factor |
| which note was extinguished | closed: commitment and nullifier are joinable only by a secret the network never holds |
| linkability of two payments of one owner | closed: rate nullifiers of different windows are unlinkable and name no one |
| the number of meaningful payments in a window | closed: the count of spends is constant at any load and filler is not subtractable |
| the shape and size of a frame | closed: one shape for every meaning, one length of proof, the branch undisclosed |
| who deposited a notice, and for whom | closed: a notice carries a nullifier and a frame identifier and no key, no signature, no address and no party; a deposit at a point names nobody, and the machine that carries it need not be the one that spends |
| the amount, the owner or the origin behind a notice | closed: a notice carries neither, and its nullifier joins to its commitment only by a secret the network never holds |
| how many notices a frame deposits | closed: a frame holds `spend_inputs × spends_per_frame` nullifiers whatever it means to pay, so the count is constant at any load and carries no signal |
| the shape, the size and the moment of a notice | closed: sixty-four bytes in one cell of the one width, deposited with the frame it names, indistinguishable on the wire from every other cell |
| two spends of one owner, joined through the points their notices stood at | closed: a notice point takes the window into its derivation, so the points of two windows do not join, and the tag dies with its window |
| the point a notice stands at, chosen by whoever spends | closed: the point is a function of the nullifier, the window and the index alone; and before a note is spent nobody but its owner can compute that nullifier, since it takes the redemption branch of the owner and the position the tree assigned |
| **that some note is named by two frames at once** | **deliberately observable to the holders of that point, and one echo earlier than the close**: this is the whole purpose of the claim. It names no owner, no amount and no party; the window that follows publishes both frames to everyone in any case, so what the point gives is earliness and never a fact the chain withholds |
| the choice of the root a proof stands on | closed: the roots a proof may stand under are the canonical horizon of its window, a frame carries none, and which leaf a proof stands under is inside the proof |
| the speed of the device that proved a frame, or when its proving began | closed: every window-bound input ranges over one standing stride, whose fold enters the transcript as one value for the whole standing period, hidden inside a proof of one length — a frame proven over many windows is byte-indistinguishable from one proven in its own |
| the origin of a coin | closed: a coin from emission is sent by nobody, and an edge of funding does not exist |
| that a right was extinguished at all | closed: a redemption position is typeless and the proof never says which branch it took, so nothing distinguishes the extinguishing of a right from the spending of a note. The bound of one share per machine per window holds by **uniqueness**, not by observation: the nullifier of a right is derived from the machine's secret and the window, so a second attempt yields the same value and collides in the set — and nobody needs to know which entries were rights for the collision to happen |
| the roots of the two structures | **deliberately observable**: they are quantities about the whole, and no participant is derivable from them |

## Conformance set

An implementation conforms to this document when all of the following hold.

1. It derives a commitment from the amount, the payment key and the blinding factor, and a nullifier from the redemption branch, the commitment and the leaf position — never from a value the sender chose.
2. It appends commitments to the note tree at the lowest free position and refuses a second entry of any nullifier.
3. It emits frames of the fixed shape, fills unused spends from its own randomness, and inserts every position of every spend into the structures in canonical order.
4. It folds each stride of the horizon of proving once, from roots it already holds, and holds that fold standing for the period the integer form of Canon names; it proves every transfer under a leaf of the standing stride, and rejects a frame that carries a root of its own.
5. It verifies the proof over the root of the horizon, the nullifiers, the commitments and the rate nullifier, and it performs length and bound checks before verification.
6. It extinguishes a right in a nullifier position indistinguishable from any other, never before the computed moment and only while the stride holding that moment stands, never at a chosen one.
7. It maintains the conservation of issuance by proof and induction, and it never attempts to verify it by summation.
8. It discloses a payment only at its owner's discretion, one payment at a time, and it implements no standing viewing key.
9. It receives a payment when the frame carrying it is applied, lets its note spend onward when the stride holding the root of its window stands, and makes no rule of settlement read a beacon, a cement or a proposal.
10. It deposits a notice at the notice points of every nullifier its frames spend, lets a notice naming another frame stand beside the first while a notice repeated whole adds nothing, and decides between two notices at no point — the canonical order of the window decides, and a reader that sees a race waits for it.
