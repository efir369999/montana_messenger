# Montana — App

**Version:** 3.4.0

App holds the boundary between the protocol and everything built on it: what an application may
put into the chain, what it may never learn about the people using it, and what a client owes
the person in front of it.

## Scope

**In scope.** The anchor and what it publishes; the identifier of an application and why it
must not sort people; the economics of an application; the boundary between protocol and
client; what a client states to a person and when; the boundary of the machine that runs an
agent; the reproducibility of a client build.

**Not in scope.** Values and layouts — Canon. Notes and proofs — Value. Records of people —
Identity. Delivery — Network. Windows — Consensus.

## The anchor

An application publishes into the chain exactly one thing: a hash. What stands behind it lives
with its owner, sealed to the encryption branch of that owner's seed — a key the network never
holds, nobody publishes, and no correspondent is handed. The protocol sees thirty-two bytes
and nothing further.

This is the whole of the storage model, and it is deliberate: data that never enters the
protocol cannot be demanded from it, cannot leak from it, and cannot be lost with it.

**Invariants of an anchor:**

- An anchor publishes a hash and never content, a length, a type or a name of what it stands for.
- An anchor is an action of the identity plane and publishes what any such action publishes — a nullifier, a commitment, a proof — and nothing that names a person.
- The content behind an anchor is retrievable only from its owner, and only by their decision.
- An anchor confers no right to the content and proves only that the content existed at the coordinate the window fixes.

## The identifier of an application

An application has an identifier derived canonically from its name. It exists so that a client
can tell which kind of thing a hash belongs to.

**It must not sort people into kinds.** An identifier attached to a person's public action is an
edge: through a known list of names it decodes into a meaning — this person uses that
application — and a set of such edges is a graph the protocol forbids. What is affected is not
the mainstream case, where the crowd is enormous, but the narrow one, where a rare application
identifies its user by volume and timing alone.

The rule that follows is therefore plain, and it admits no narrow case: **an application
identifier never reaches the wire at all.** An action of the identity plane publishes exactly
three quantities and no fourth, so there is no field for an identifier to travel in. Where an
application must be told apart, it is told apart inside what only its correspondents can
open — the identifier lives with the content, under the same key, and is proven rather than
published where the protocol needs to know of it. An application whose design requires a
public label states the concrete prohibition that forces it, or it does not ship.

## The economics of an application

An application pays for nothing at the protocol level and charges nothing there: no fee, no
rent, no subscription exists as a protocol notion. What an application charges, it charges by
ordinary transfers of value between people — which name no party and enter no chain of anyone.

Storage, delivery and computation are the work of the devices that do them, and the network
already pays for carriage out of the share of a window. An application that needed a
protocol-level fee would be asking the protocol to name who paid.

## The boundary

The protocol holds the canonical order of events, the value layer, the identity plane and
delivery. Everything else is the client layer: how a message is composed and displayed, how
media is chunked, how a profile is rendered, how contacts are organised, how a call is
presented. None of it enters consensus and none of it is normative here beyond what this
document states.

The boundary is not a suggestion. A client that moves any part of the four layers into itself,
or that asks the protocol to carry any part of its own, breaks the property that any
independent implementation is the same network.

**Proving is movable within one owner, and only there.** A frame is proven on the device of its
payer, and the payer is a person, not a piece of hardware: identity recovers byte-exact from
the seed, so the devices of one person are one payer, and a client is free to compose a payment
on the weak device of a person and prove it on their strong one. The protocol neither sees nor
carries this — nothing published says where a proof was made — and the freedom ends at the
owner's edge: carrying the witness of a proof to anybody else's device hands over the secrets
of the notes it spends, and a client that offers such a path does not implement this protocol.
The person is told which of their devices proves, in the manner every statement about their
own state is owed to them.

## What a client owes the person

A client states the truth about the state at every moment, and the invariant it serves forbids
not an action of a person but a **lie about the state**.

- A handshake not yet bound to a key by an out-of-band comparison is shown as unverified, and the mark is removed by a comparison and by nothing else — not by time, not by the number of messages exchanged, not by a dismissal.
- Before a person claims a name, they are told what claiming it does: it creates an edge that lasts as long as the name is held, and the record without a name is the normal state rather than a mode.
- Before a person destroys a seed, they are told that identity is the seed: nothing recovers it, and no one can be asked.
- Where a transport with a plainly different property is used — a device in physical range, a courier — the person is told which transport is in use, never asked to choose a degree of privacy.
- Where a client renders a coordinate of the chain as a calendar date, the date is the client's own local reading — marked as such where it could mislead — and no quantity taken from the clock of the device enters any object the client emits.

A client that hides, weakens or lets a person dismiss any of these does not implement this
protocol, whatever else it implements.

## An agent

An agent is a program that holds a seed and acts on it without a person present at each act: it
opens the letters of its pipes, composes answers, and may hold and move value. The protocol has no
notion of an agent and needs none. A mark that told the seed of an agent from the seed of a
person would be exactly the edge the identifier of an application is forbidden to be — it sorts the
holders of seeds into kinds — and the rule that keeps an application identifier off the wire keeps
this mark off it by the same argument. To the protocol an agent is what a person is: a seed, the
record it opens, and the pipes its secrets stand on. Its letters are cells like every other cell,
and its windows, barriers and value are those Identity and Value state for every record, with no
exemption and no surcharge. Because every barrier of the identity plane is a quantity of time, a
population of agents costs its operator the time those barriers count and nothing cheaper: to start
an agent is to open a record, which the ceiling of openings per window already bounds.

What remains to fix is therefore not a mechanism of the protocol but the boundary of the machine
that runs an agent, and it is fixed here because each of its four clauses, broken, hands somebody's
secret to somebody else.

**The seed of an agent is its own.** It is born on the machine that runs the agent, by the birth
Identity defines, and it is never the seed of the person who operates the agent. Everything of a
person derives from one seed: an agent holding its operator's seed would sign as the operator, open
every correspondence of the operator, and expose all of it to whatever compromises a machine that
reads untrusted text by design. Whose agent it is, is a statement the operator makes in content,
under the keys of a pipe, and never a derivation that joins the two seeds.

**The machine of an agent is a node.** It holds the pipes of the agent and deposits and collects
for them itself, as any device does under Network. No third machine stands between an agent and its
correspondents, and none is needed: a tag points at its holder without a directory.

**The reasoning program holds no key.** The program that decides what an agent says — a language
model or any other — receives the plaintext of the letters the node opened and returns the plaintext
of the letters to send, and nothing else crosses between the two: no seed, no branch, no shared
secret and no witness of a proof enters its context. A letter is untrusted input to that program, so
a letter that persuades it can at most make the agent say something; it cannot make the agent
disclose a key the program never held, and value moves only under the rules the operator fixed at
the node, never at the request of a letter. The interface between the node and the reasoning program
lives on that one machine and leaves it by no path.

**Where reasoning runs is declared.** The protocol protects a letter up to its recipient and no
further, so a letter to an agent whose reasoning runs at a model provider reaches that provider in
plaintext — the act of a recipient forwarding what it received, chosen by the operator and not by
the correspondent. A conforming agent therefore declares, inside its content and under the keys of
the pipe, that it is an agent and where its reasoning runs: on its own machine, or at a provider it
names. A client shows the declaration to the person before their first letter to that agent, as a
statement of the correspondent and not as a fact the protocol checks, in the manner a transport of
a plainly different property is owed to the person.

**Invariants of an agent:**

- No field of any object of the protocol tells an agent from a person.
- The seed of an agent is born on its machine and shares no derivation with any seed of its operator.
- No seed, branch, shared secret or witness of an agent enters the context of its reasoning program.
- A letter moves no value of an agent and discloses no secret of it; value moves only under rules its operator fixed at the node.
- The interface between the node of an agent and its reasoning program is reachable only from that machine.
- An agent declares inside its content that it is an agent and where its reasoning runs, and a client shows the declaration before a person's first letter to it.

## The reproducibility of a client

Constitution states the property and why prevention is refused in favour of detection. App
states only the duty that follows for whoever ships a client: publish the hash of every release
in the three independent places the invariant names, and make the build reproducible from
public source before shipping rather than afterwards.

A client that ships without this does not become invalid — nothing blocks it — but it forfeits
the only thing that distinguishes an honest binary from a compromised one, and it does so at
the expense of people who cannot check for themselves.

## Observability ledger

| Quantity | Status |
|---|---|
| the content behind an anchor | closed: only a hash reaches the network |
| who published an anchor | closed: an anchor is an action of the identity plane and names nobody |
| which application a hash belongs to | closed: an action publishes three quantities and no fourth, so no identifier reaches the wire; it lives with the content, under the owner's key |
| that some anchor was published in a window | **deliberately observable**: it names nobody. What bounds anchors is the rate of a person's own actions, held by the rate nullifier of the identity plane — not the per-window cap on opening records, which is a different bound on a different act. An anchor competes with nothing for that cap |
| what a person pays an application | closed: payment is an ordinary transfer, which names no party |
| the hash of a client build | **deliberately observable**: it is the detection surface, and it is about a binary rather than about a person |
| the calendar reading a client shows beside a coordinate | closed to the protocol: it is derived locally from the client's own clock and enters nothing the client emits |
| that a seed belongs to an agent | closed: no field of the protocol carries it; the agent declares it in content, under the keys of a pipe, and the person learns it from that declaration alone |
| the plaintext a reasoning program of an agent reads | **deliberately observable to the place of reasoning the agent declares**: its operator chose it, the declaration precedes the first letter, and nothing of it reaches the network |
| the keys of an agent | closed to its reasoning program: none enters its context |

## Conformance set

An implementation conforms to this document when all of the following hold.

1. It publishes for an anchor a hash and nothing else, and it stores the content with its owner under a key the network never holds.
2. It emits no application identifier on the wire at all, carrying it with the content under the owner's key.
3. It charges and pays at the protocol level for nothing, expressing every economic flow as an ordinary transfer of value.
4. It keeps the four layers of the protocol out of itself and its own layer out of the protocol.
5. It implements the duty Identity states about an unverified handshake, in the form Identity states it — this document adds no second obligation over the same mechanism.
6. It states the consequence before the act for claiming a name, for destroying a seed, and for using a transport of a different property.
7. It builds reproducibly from public source and publishes the hash of every release in the three independent places.
8. It derives any calendar rendering of a coordinate locally, marks it as its own reading where it could mislead, and lets no quantity of the device's clock enter anything it emits.
9. It moves proving only between the devices of one owner, tells the person which of their devices proves, and offers no path that carries the witness of a proof beyond the owner's devices.
10. It emits nothing that tells an agent from a person, and runs an agent on a seed born on the agent's machine that shares no derivation with any seed of its operator.
11. It keeps every seed, branch, shared secret and witness of an agent out of the context of the agent's reasoning program, moves value only under rules fixed at the node, and reaches the interface between the node and the reasoning program only from that machine.
12. It declares, for an agent, that it is one and where its reasoning runs, inside content under the keys of a pipe, and, as a client, shows a correspondent's declaration before a person's first letter to it.
