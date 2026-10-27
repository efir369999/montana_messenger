# Montana Core

The reference implementation under active audit: primitives, encodings, trees, derivations,
transport, proof circuits, a node and a terminal wallet. Two running processes exercise transport
and local protocol scenarios. They do not establish that the live cohort has finalized a window.

The current source candidate repairs presence and frame branch binding, padding, round authorization,
beacon reconciliation and persisted predecessor choices. It also binds stores to Genesis. Canonical
window finalization, the complete window-proof statement, admission continuity and authenticated
bootstrap remain blockers. Read the current findings at the top of [AUDIT.md](AUDIT.md) before
running these examples. The changed AIR and genesis identifiers require a verified network
transition; this candidate is not a compatible replacement for a deployed node.

What is not here is the client layer — how a message is composed or displayed, how media is
chunked, how a profile is rendered, how a call is presented. That is built elsewhere, against the
bindings this tree exports. The line is the set's own: a client that pulls part of the protocol
into itself, or pushes part of itself into the protocol, breaks the property that any independent
implementation is the same network.

## One truth, held by the build rather than by discipline

The normative set is `../docs`, and this tree is subordinate to it: where the two disagree, the
documents state the requirement and a weaker implementation is a defect to fix.
The harness binds what the stages have built: every value of the Genesis Decree, every domain
separator, and the frozen vectors of the hash primitive and of the trees are parsed out of the set
and asserted against the code on every build, and a divergence fails the build and names what
diverged. Each stage that lands its code extends the gate to the sizes and vectors that code
answers for. This compares registered values and encodings; it does not prove that every circuit
constrains its intended statement or that the runtime executes the whole protocol.

The documents define what an independent implementation must reproduce. The harness checks
registered counterparts; the open findings identify requirements it does not yet establish.

## What the build does not hold

A gate compares what has a counterpart. A derive on a type, a feature of a dependency, a door left
wider than its use — these are not values of the set, so nothing stands opposite them to compare,
and the build passes over them. `AUDIT.md` is where those live: what was found by reading, where it
is, why it is a finding rather than a preference, and what closes it. Read it after the plan and
before the code, because it names the places the green build says nothing about.

## What the plan reaches

`ROADMAP.md` holds twenty-one stages, from an empty directory to a network a stranger joins by verifying
one proof, reaches a person in by name, keeps a library alive in, and writes their own client
against. It records intended stages. Current completion is tracked in [SESSION-35.md](SESSION-35.md),
including the incomplete window and admission statements, authorized issuance and authenticated
first synchronization. A stage label does not establish those properties.

## Two machines, from a terminal

Nothing is installed and nothing is configured. The tree builds two binaries, and each is handed a
directory to keep what it holds and an address to answer at — a port is of the world outside and
this protocol names none.

```
cargo build --release
target/release/montana-node --data ~/montana --listen 0.0.0.0:9635
```

The first start draws the secret of that machine — six sources with the health tests of the set
over them, and a refusal rather than a warning where a source is not alive — and prints four
things: where it answers, the acquaintance to hand to another operator, the six groups of five
digits two people compare by voice, and the naming half it stands in a window by. Every later start takes the secret that stands: a machine
cannot draw a second, so it cannot become a second machine wearing its name.

On the other host the same, and then each is given what the other printed:

```
target/release/montana-node --data ~/montana --listen 0.0.0.0:9635 \
  --acquaintance 198.51.100.7:9635@<the key that machine answers with>
```

An acquaintance is an address and a key and comes from the world outside: there is no directory and
none can be assembled. A handshake reaching a machine that answers with another key ends in
silence. What crosses afterwards is units of one width, sealed under the keys those four flights
established — post-quantum end to end, ML-KEM-768 and ML-DSA-65, with nothing classical anywhere on
the path. A machine answers up to the links the Decree allows it and holds each on a thread of its
own; at that ceiling it answers no further handshake at all, which reads exactly like an address
where nothing listens.

The wallet is the same shape and keeps what it holds beside itself:

```
target/release/montana-wallet --data ~/montana-wallet born
target/release/montana-wallet --data ~/montana-wallet balance
target/release/montana-wallet --data ~/montana-wallet words < phrase.txt
```

The words printed on a birth are the whole of that person. They are read back from the standard
input and never from a command line, where every other process on the machine reads them and the
history of a shell keeps them.

**What two machines do, written here rather than left to be discovered.** They read one another.
The kind of a message rides in the framing of every piece and inside the seal, so a machine
dispatches rather than guesses: a deposit at a point of the current window or round is kept, a
collection from that point is answered with what stands there, a query for a leaf of the tree of
notes is answered with the path to it, a head query naming this network is answered with the newest
proposal held and one naming another network with silence. An observer sees what it saw before —
units of `cell_bytes` and no second shape.

**An object larger than a cell crosses as a delivery, and the keys of it come of the point it
stands at.** A beacon is five times a cell and a frame is a hundred and seventy times one, so both
are cut into blocks, grouped by the erasure code with a quarter of every group parity, and every
block rides one cell. Both keys of such a cell — the one a step is sealed under and the one a
delivery is sealed under — are derived from the point, which every machine computes from the window,
the chain, the round and the index without asking anybody. So a publication keeps the one shape
every cell has: a beacon, a frame and somebody's letter are one shape on the wire.

**One person pays another from a terminal.** The payer's machine reaches the one holding the state,
asks it where the payer's notes stand, builds the frame, proves it and publishes it at the points of
its round:

```
target/release/montana-node --data ~/montana --listen 0.0.0.0:9635 \
  --pay 198.51.100.7:9635@<the key that machine answers with> \
  --wallet ~/montana-wallet \
  --to <the payee's naming half>:<the key their note is paid to> \
  --amount 250000000 --window 1000 --round 0:0
```

The machine holding the points reads its own, reconstructs the frame, verifies the proof against the
tree of notes as it stands and appends: the nullifiers recorded, the commitments taking positions.
It learns nothing of the payment — what it is handed is nullifiers, commitments and the nullifier of
a rate, and none of them carries an amount or names a person. A frame spending a note already spent
is refused by the state before its proof is looked at, and the same frame standing at every point of
a round is applied once for the same reason. What the payer prints for the payee is three public
values of the note created; the position of it comes of the window that applied the frame.

**The local window scenario.** A machine of an opening cohort is handed the naming half of
every machine admitted to the window, its own among them — a cohort that witnesses itself is exactly
that, and the halves pass between operators as an acquaintance does. Each machine prints its own on
start; neither is told the tree, and both reach the same one from the halves alone, because the
order is the ascending order of the halves and nothing else.

```
target/release/montana-node --data ~/montana --listen 0.0.0.0:9635 \
  --acquaintance 198.51.100.7:9635@<the key that machine answers with> \
  --admitted <this machine's naming half> \
  --admitted <the other machine's naming half> \
  --open --windows 1
```

`--open` is the operator opening a network: window zero, on the cohort the halves name, and only on
a store that holds nothing of a chain; on any other store it is refused before anything is written.
One that holds nothing and is not asked to open lives no window and says so (Consensus, "The cold
start"). One started without it on a store holding a chain is set to the window after the last it
closed, and the pulse refuses that window until it takes the proposals it stands on from its own
store, which issue #16 carries.

Each machine enters the window, publishes beacons, verifies answers and gathers attestations. It
closes the window on a beacon carrying a cement at the quorum share of the electorate of the window
two before, recomputes the six roots of state, proves its ticket and publishes the proposal under the
identifier of what the window decided, judges every proposal it takes at the one door of
`montana-node/src/certificate.rs`, links the next window to that identifier, and moves its head onto
a proposal only when the cement of the window after it reaches the quorum on it. A device holding
nothing joins from two consecutive final proposals its operator hands it and walks the retained
certificates to the same head (`montana-node::pulse::join`). The right a machine takes of a window
is still created locally from the count of the cement and is no evidence of issuance; item 3 of the
audit list carries it.

Round advancement now requires a verified answer. Polling uses a local sleep; exhausting its
budget returns without advancing the round. This testable property does not establish the missing
window-finalization property.

The addresses in these examples are transport configuration. Directly listening on a public
interface exposes that machine's origin; this implementation does not make it anonymous.
Cross-host testing of protected origins requires an authenticated private transport path and
operator-supplied peer information. No public dialable cohort is supplied by these examples.

The door and the pulse stand at once. A link a machine opened is its way of asking — a deposit and a
collection are both requests whose answer comes back on the link they went out on — and a link it
answered is its way of being asked. So one machine dialling the other is enough: the dialler writes
its objects into the answerer and reads the answerer's back, and the two converge.

`AUDIT.md` carries what remains with what it blocks.
