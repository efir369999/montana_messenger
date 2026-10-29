# P13-11 K3 (#22): carriage and path, the map

Box K3 of issue #22: "carriage and path: a node carries others' objects and `hop_min` is read, so the
source is not the sender". This is the map of generation A. It was read on `origin/main` `8a6e7bc`
(2026-10-29 UTC). Line numbers are of that tree.

**Verdict: map only.** Several rules K3 needs are not fixed by the set (section 4). One more rule
cannot be met without a Gate 0 decision (G-1/G-2). Following the assignment, nothing is implemented.
Each open rule is stated below as a question for the Author, with its places, the options and a
recommendation. The questions are in section 5.

Gate respected: this map does not depend on the key on the wire (G-1), the adversary model (G-2),
DNS names (G-3), literal addresses (G-4), rotation (G-5) or K4. Where a rule of K3 runs into one of
them, the map says so and stops there.

## 1. What the set says

### 1.1 The path

- **Bound.** "Every envelope crosses at least the number of distinct machines of the active set Canon
  fixes, and no direct path exists ... When fewer are reachable, the envelope is not sent: it waits
  in the sender's queue until the path assembles." `Network:320-323`. Constitution, invariant 7:
  `Constitution:454-460`. Conformance: "It refuses to send at all when fewer than the fixed number of
  different seals can be assembled along a path" (`Network:843`, item 6).
- **The number.** `hop_min` = 3, "distinct machines of the active set on a path"
  (`Canon:4784`; Decree in code `mt-genesis/src/lib.rs:109`). It applies to consensus too: "every
  object of consensus stands at `consensus_replicas` points, and every envelope crosses at least
  `hop_min` distinct machines" (`Canon:4807-4809`). Consensus data travels in the same cells
  (`Network:158-162`, `Canon:2252`).
- **Who checks.** The sender, over "the first ones, out of its own entries" (`Network:337-347`,
  `Constitution:456-460`). "The seals therefore serve the sender's assembly of its first steps and
  stop there" (`Network:392-397`).
- **The first steps.** "The first steps are random and only then does the rule apply. Otherwise the
  very first step is directed, and a neighbour of the source distinguishes 'arrived from' a
  neighbour from 'was born at' one." (`Network:373-375`).
- **The seal of a step.** `path_id(inner)`, `relay_seal(owner_secret, path_id)` and `seal_slot(seal)`
  are defined in `Canon:2709-2711`, and `owner_secret` = HKDF(master_seed, "mt-owner-key") in
  `Canon:1850`, "held identically by every machine one owner runs" (`Canon:1854-1858`, `:2778`). A
  hop rewrites the array at that slot and nothing else (`Canon:2185-2188`, `:2250`).
- **No position.** The seal array is full from the origin (`Canon:979-985`, `:2249`). A label takes
  "no index of any kind" (`Canon:1383-1384`). "The count of steps a delivery has crossed" is closed
  (`Network:794`).

### 1.2 The cell and its keys

- One shape, `cell_bytes` = 1 232 (`Canon:2140-2252`). The outer seal is one step wide: "Every hop
  opens this seal, rewrites what it must, and seals again under the key of the next step with a
  fresh nonce" (`Canon:2165-2169`).
- A letter's step: `step_label(handshake_secret, W)` (`Canon:1348`, `:1379-1384`) under the
  directional key of the handshake of that pair (`Canon:2165-2167`).
- **A cell at a point** (every object of consensus): both keys come from the point,
  `point_step_key(P, W)` and `point_pipe_key(P, W)`. "The label of such a cell is the point itself,
  ... and `target_commit` carries the point rather than a machine" (`Canon:2205-2217`).

### 1.3 Who forwards, and to whom

- "Each hop passes the cell to the acquaintance whose commitment stands closest to the target in
  the same ordering, and stops when it is the target itself. A machine knows the commitments of the
  acquaintances it has spoken to" (`Network:109-113`). Conformance: "forwards toward that target by
  closest commitment among its acquaintances" (`Network:850`, item 13).
- The holder: `holder(tag, S)` = the least commitment above the tag, wrapping (`Canon:2687-2701`,
  `Network:84-88`, `:121-126`). `S` = "the set of commitments of the machines living in the window"
  (`Canon:2693`).
- A point of consensus is held by the machine the holder rule places there (`Network:739-742`,
  `:510`; `Canon:2600-2603`).
- Carrying is a duty of every reachable device (`Network:624-629`; conformance item 8,
  `Network:845`).

### 1.4 When an object is accepted from a carrier

- "A deposit at a point ... arrives the way everything arrives, over a link that already stands,
  carried hop by hop, and it opens none of its own; it is accepted inside a handshake"
  (`Network:697-701`, `:731`).
- A deposit is accepted at the point of the current window alone (`Canon:2407`). Points of a past
  round are refused (`Canon:2629`). A delivery is taken whole or not at all (`Canon:2628`).
- The digest set: "the set of digests of the step-headers it has accepted ... A header whose digest
  is already in the set is discarded" (`Network:671-674`; item 11, `Network:848`).
- The message is `deposit` = `point` 16 B + `cell` (`Canon:2299-2302`), kind 1 of the link vocabulary
  (`Canon:2469-2475`). The vocabulary has no other kind for carriage.

### 1.5 What a carrier learns

- "Its own step's label, the target commitment, and one decision: for me, or onward. It does not
  know ... whether the device that handed it over is the origin or a relay." (`Network:399-402`).
- Threat model: "the neighbouring hop: one label of one step, and an address it cannot tell origin
  from transit by" (`Network:791`). Ledger: "origin against transit: closed by carriage"
  (`Network:811`).
- "Why not a flood. Sending every object to every acquaintance would put a second profile of
  traffic on the wire" (`Network:757-760`; `Canon:2681-2683`; item 21 "floods nothing to anybody",
  `Network:858`).

### 1.6 Where the set places this work

- Registry: NET-03 (holder), NET-04 (path), NET-07 (right of carriage), NET-12 (digest set), NET-16
  (carrying is the work) and NET-19 (what carries a message) await **stage 18**
  (`Montana Registry.md:129-145`).
- Roadmap stage 18 holds "a cell carried over a path of hops, each opening one step, rewriting the
  one slot its own seal selects and sealing again" (`core/Montana-Core/ROADMAP.md:1134-1150`).

## 2. What the code already has

| Piece | Where | State |
|---|---|---|
| `hop_min` = 3 | `mt-genesis/src/lib.rs:109` | in the Decree; read by no crate outside `mt-genesis` (search for `hop_min` over `crates/`) |
| The cell, its two seals, `Routing::new` drawing a full array | `mt-wire/src/cell.rs:150-156`, `:237-277` | done, with vectors (`mt-conformance/src/parse.rs:1389`) |
| One hop: `carry(step_key_in, cell, owner_secret, step_key_out, label_out)` | `mt-wire/src/cell.rs:284-303` | done; tested in `mt-wire/tests/wire.rs:86` (three machines, the carrier learns nothing) and `tests/timing_cell.rs:72,107,129`; **no caller in montana-node** |
| A cell at a point: keys and label of the point, target = the point | `mt-wire/src/publish.rs:19-58` (keys `:24-25`, target `:50-51`, label `:53`) | done |
| `path_id`, `relay_seal`, `seal_slot`, `step_label` | `mt-derive/src/tag.rs:44`, `:67`, `:74`, `:85` | done, with vectors |
| `holder(tag, living)` | `mt-derive/src/pulse.rs:76-85` | done; used only by the conformance gate (`parse.rs:1526`), **not by montana-node** |
| `entry_point`, `entries` (K4) | `mt-derive/src/delivery.rs:117-147`, `:153-179` | done; not called by montana-node |
| `node_commit(answering_pk, suite_id, blind)` | `mt-derive/src/lib.rs:35-48` | done; `blind` is the machine's own secret |
| An acquaintance: address + answering key | `mt-net/src/lib.rs:181-184`; `montana-node/src/lib.rs:161-190` | no commitment of the far side |
| A link unit: the label is drawn per unit | `mt-net/src/lib.rs:262-271` | not `step_label(handshake_secret, W)`; the handshake secret is not exposed by `Link` |

## 3. What montana-node does today (the gap)

- **Every machine stands at every point.** `points_of` returns every point of the head window and
  of the open round (`montana-node/src/lib.rs:127-142`), and `accepts_point` takes a deposit at any
  of them (`:662-670`). The holder rule is not applied. The comment at `:1744-1748` states the design:
  "A point is one blackboard and a deposit is how a copy of it reaches another machine".
- **The source is the sender.** `publish_at_the_point` writes the object at its own point, then sends
  every cell to **every** link it holds (`lib.rs:1760-1792`, loop `:1776-1790`). Its callers:
  `stand_at_the_round` for beacons and attestations (`pulse.rs:1091-1105`), `pulse.rs:2708` for the
  objects of a window, and `pay.rs:231`, `:234` for a frame and its notices. Each object goes to 3
  points × every acquaintance, directly from its source.
- **Pushing back.** `objects_at_the_point` collects from every link, then pushes back every standing
  cell the far side has not acknowledged, its own included (`lib.rs:1798-1870`; push at
  `:1851-1868`).
- **Collection.** It collects from every link held: `collect_public` (`lib.rs:1901-1928`) and the
  collection in `objects_at_the_point` (`:1834`), through `pulse::collect_from`
  (`pulse.rs:3269-3290`).
- **Nothing is carried.** An arriving deposit is held or refused and never forwarded
  (`lib.rs:1994-1999`, `take_the_deposit` `:2032-2091`). No call of `mt_wire::cell::carry`,
  `mt_derive::pulse::holder`, `mt_derive::delivery::entries`, or the scalar `hop_min` exists under
  `montana-node/src`.
- **No living set.** The state keeps the root of the admitted tree, not the commitments of the
  living machines (`montana-node/src/state.rs:20-23`). The machines of an opening cohort "write no
  commitment" (`Montana Consensus.md:1334-1335`). So a network opened by a cohort, which is every
  network the tests and the genesis machines run, has no `S` for the holder rule.
- **No owner secret.** montana-node holds the machine secret (`lib.rs:1933-1940`). `mt-seed`
  derives the owner branch from a person's master seed (`Branch::Owner`,
  `mt-seed/src/lib.rs:245`, `:273`), but no owner branch reaches montana-node: nothing under
  `montana-node/src` names it. The only caller of `relay_seal` is `mt-wire`.

## 4. The rules K3 needs

FIXED = the set fixes it at the line given. UNDEFINED = the set does not fix it. GATE = fixed, but
it cannot be met without a Gate 0 decision this box must not depend on.

| # | Rule | Where | Status |
|---|---|---|---|
| R1 | An envelope crosses at least `hop_min` = 3 distinct machines of the active set; no direct path; with fewer, it waits in the queue | `Network:320-323`, `:843`; `Canon:4784`, `:4807-4809`; `Constitution:454-456` | FIXED |
| R2 | The sender is not one of the `hop_min`: they are steps it chooses "out of its own entries" | `Network:339-342` | FIXED (the first hop stays today's acquaintances until K4, as the assignment allows) |
| R3 | Who chooses steps 2..`hop_min`, and how a hop knows it is in the random head ("The first steps are random and only then does the rule apply") when no position is carried | `Network:373-375` against `Canon:2249`, `:1383-1384`, `Network:794` | **UNDEFINED** |
| R4 | How the sender checks "the fixed number of different seals ... along a path" when the seals are written into a cell it never sees again, and no message brings them back | `Network:843`, `:337-347`, `:392-397`; vocabulary `Canon:2469-2475` | **UNDEFINED** |
| R5 | The next hop is the acquaintance whose commitment is closest to the target | `Network:109-113`, `:850` | **GATE**: an acquaintance is an address and a key (`mt-net/src/lib.rs:181-184`). Its commitment needs `blind` (`mt-derive/src/lib.rs:35-48`). Binding the two is G-1/G-2 (K4 addendum on #22) |
| R6 | A hop stops when it is the holder of the target, `holder(point, S)` with `S` the living commitments of the window | `Network:109-113`; `Canon:2687-2701`, `:2213-2214` | **UNDEFINED** for a cohort network: its machines write no commitment (`Consensus:1334-1335`), so `S` is empty and no point has a holder |
| R7 | "Closest ... in the same ordering": the metric (forward distance on the ring to the target, or absolute) | `Network:109-111` | **UNDEFINED** (the holder rule fixes "least above", not the distance between two others) |
| R8 | One hop crosses as a `deposit` message (point + cell) over a link that stands, opening no link of its own | `Network:697-701`; `Canon:2299-2302`, `:2469-2475` | FIXED |
| R9 | Keys and label of a step for a cell at a point: `point_step_key(P, W)`, label = P, target = P | `Canon:2205-2217` | FIXED (`publish.rs:24-53`) |
| R10 | A carrier writes `relay_seal(owner_secret, path_id(inner))` at `seal_slot` and nothing else | `Canon:2185-2188`, `:2709-2711`, `:2778`, `:1850-1858` | FIXED in the set. **UNDEFINED in practice:** no line says how a machine receives the owner branch, or what it seals with when its operator gave none |
| R11 | A carrier accepts a deposit at a point of the current window or round, whole or not at all | `Canon:2407`, `:2628-2629` | FIXED (`lib.rs:2032-2091`) |
| R12 | A repeated step-header is discarded by the digest set of the window | `Network:671-674`, `:848` | **UNDEFINED**: "step-header" is not laid out. Every hop re-seals with a fresh nonce (`Canon:2168-2169`), so the cell bytes never repeat along a path. Which bytes the digest covers decides whether a loop is caught |
| R13 | A collection reaches a holder the collector holds no link to, and the answer comes back | `Network:527-531` ("collecting is carriage"), `:750-752`; `Canon:2620-2621` | **UNDEFINED**: a cell carries only a target (`Canon:2171-2177`), no message carries a collection hop by hop, and no rule returns an answer along a path |
| R14 | The bound in a network of fewer than `hop_min` + 1 machines (the genesis cohort is three; the tests run one to four) | R1 against `Consensus:1330-1337` | **UNDEFINED / in conflict**: by R1 and `Canon:4807-4809`, no object of consensus ever leaves a machine of a three-machine network, so no window closes |
| R15 | A machine's own object at a point it holds itself: is that a direct path? | `Network:750-752` against `:320-321` | **UNDEFINED** (follows from R6, R14) |
| R16 | A carrier cannot tell the source from a carrier: a source's array is drawn whole, and a relay seal is a hash of a secret the next hop does not hold | `Network:399-402`, `:791`; `Canon:2249`; `cell.rs:150-156`, `:296-301` | FIXED. It holds only if the source does not fan out: today one object goes to every link at once (`lib.rs:1776-1790`), and that pattern alone marks the source |
| R17 | Every reachable machine carries | `Network:624-629`, `:845` | FIXED |

Five rules are UNDEFINED in substance (R3, R4, R6, R13, R14). R7, R10, R12 and R15 are smaller.
R5 waits on Gate 0. Any one of these is enough to stop at A. Without R6, R13 and R14, the consensus
path cannot be moved onto a path at all: a holder rule with no living set, collection that does not
cross hops, and a bound a three-machine network never meets would stop every window. That is the
assignment's own test (3).

## 5. Questions for the Author

**Q1 (R14). Does `hop_min` bind objects of consensus in a network of fewer than `hop_min` + 1
machines?** Places: `Canon:4807-4809`, `Network:320-323` against `Consensus:1330-1337`.
- (a) Yes. A network needs at least four machines before any window closes, and the cold start
  says so.
- (b) No while the living set is below `hop_min` + 1. Objects wait for nothing and go to whoever is
  reachable. The ledger names this as a stated exposure of a small network.
- (c) Objects at points are not envelopes for the bound until stage 18. The current replication
  stays, and K3 applies to letters only. montana-node carries no letters today, so K3 would carry
  nothing yet.

Recommendation: (b). Write it into Network "The path" and into the ledger as a named exposure of a
network below `hop_min` + 1 machines. (a) stops the three genesis machines, and (c) leaves the box
with nothing to carry.

**Q2 (R6). Who holds a point when the living machines wrote no commitment (an opening cohort)?**
Places: `Canon:2693`, `Consensus:1334-1335`, `montana-node/src/state.rs:20-23`.
- (a) Each cohort machine stands in `S` at a canonical value derived from its naming half under a
  new domain.
- (b) Until the first commitment is admitted, every machine holds every point (today's
  `lib.rs:127-142`), and the holder rule starts with it.
- (c) The holder rule runs over naming halves.

Recommendation: (a). It keeps one rule for every window. (b) is today's code and needs only a
sentence. Either way, `S` has to be held by the node, which today keeps a root only.

**Q3 (R3, R4). How is the random head of a path assembled, and how does the sender count its
seals?** Places: `Network:337-347`, `:373-375`, `:392-397`, `:843`; `Canon:2249`.
- (a) A layered head: the sender seals for its first step a cell whose target is its second step,
  and so on, `hop_min` deep. This needs a layout Canon does not have, and bytes of `inner`.
- (b) A per-hop coin: each hop forwards to a random acquaintance with a fixed probability before the
  directed rule. No position is carried, but the bound becomes an expectation, which contradicts
  "at least".
- (c) The sender's check is over its own knowledge only: its first step is one of `hop_min`
  distinct entries, and the seals check nothing at the sender. The text of item 6 is then rewritten.

Recommendation: the Author fixes one of these in Canon before code. (a) is the only one that keeps
"at least `hop_min`" as a guarantee to the sender.

**Q4 (R13). How does a collection cross hops, and how does its answer come back?** Places:
`Network:527-531`, `:750-752`; `Canon:2171-2177`, `:2632`.
- (a) A collection rides a cell to the holder. Each hop keeps, for the current window only, the link
  it came on, and the answer returns along it. That is a per-window record at the hop, which
  `Canon:2632` ("keeps no record of who asked") would have to allow.
- (b) A collector collects only from holders it has a link to (its entries). This needs K4, and
  entries that cover the holders.

Recommendation: (a), held for one window and emptied with it, as the digest set already is.

**Q5 (R12). What is the "step-header" whose digest the window keeps?** Place: `Network:671-674`.
Options: the whole cell (useless, since it is re-sealed every hop); `step_label` + `outer_nonce`;
`path_id(inner)`, which is constant along a path. Recommendation: `path_id(inner)` per point. It
catches a loop and joins nothing a hop does not already hold.

**Q6 (R10). Where does a machine get `owner_secret`, and what does it seal with without one?**
Places: `Canon:1850-1858`, `:2778`, `:2792`.
- (a) The operator hands the owner branch over, and the machine refuses to carry without it.
- (b) Without it, the machine seals under a branch of its own machine secret. That makes it an owner
  of one, which `Canon:2792` already admits a machine can claim.

Recommendation: (b), stated in Canon, with (a) as the operator's option.

**Q7 (R7).** Is "closest" the forward distance on the ring to the target, matching "least above"
of the holder rule? Recommendation: yes. Then the step agrees with the holder at the last hop.

R5 is not a question for this box. It is Gate 0 (G-1, G-2), as the K4 addendum on #22 states.

## 6. What stays as it is

Nothing in the tree changes with this map. The deposit by the source to every acquaintance
(`montana-node/src/lib.rs:1776-1790`, `:1851-1868`) stands until the questions above are answered.
Box K3 stays open.
