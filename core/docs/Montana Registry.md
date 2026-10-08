# Montana — Registry

The Registry is the inventory of the mechanisms of the set. It is not normative: no rule of the
protocol lives here, every cell of it points at a document of the set or at the plan of the
reference tree, and the one thing it owns is the number of a mechanism. The gate of the
reference tree parses this file on every build and refuses a build in which a cell and the set
disagree, so the table below is held by comparison rather than by attention.

## The rules of the Registry

1. **A number is given once and never reused.** An identifier is a layer prefix and a number:
   `CNS` for consensus, `VAL` for value, `IDN` for identity, `NET` for network, `APP` for
   applications, `CAN` for the meta layer of Canon and the Constitution. A mechanism that
   leaves the set leaves its number empty behind it, exactly as a domain separator would.
2. **An anchor resolves or the build fails.** The anchors column names a document of the set
   and a heading inside it, verbatim. The gate resolves every anchor against the document it
   names; a renamed heading is a red build naming the row, which is why the seven documents
   carry no numbers back — the reference runs one way, and the gate makes one way enough.
3. **Every domain has exactly one owner.** The domains column partitions the registry of
   domain separators: each of its names appears in exactly one row, and a name outside that
   registry fails the build. A frozen vector computes under domains, so a vector's owner is
   the row that owns its domains, and no second ownership map is kept.
4. **Every derivation has an owner.** Each backticked quantity derived in Canon under
   "Derivations of the frozen quantities", and each derived alone beside its own heading,
   appears in at least one row.
5. **The awaits column is a claim with a vocabulary of three.** `—` states that what the row
   stands on is frozen and compared today. `stage N` names the stage of the plan that owes the
   row its remaining proof, and the gate refuses a stage the plan does not carry. `air_hash`
   names the one artifact the Constitution leaves open. Nothing else may stand in the column.
6. **The counts are recomputed, not remembered.** The gate recounts the table and refuses a
   build in which the counts below and the rows disagree.

A row whose awaits cell is `—` claims that its frozen material is compared on every build; it
does not claim the mechanism is beyond audit. A row awaiting a stage is not a defect: it is the
honest state of a mechanism whose proof is scenario-shaped and whose scenario arrives with the
code that computes it.

## The counts

| Count | Value |
|---|---|
| rows | 96 |
| closed — nothing awaited | 37 |
| awaiting a stage of the plan | 59 |
| awaiting the artifact `air_hash` | 0 |

The artifact stands published, so no row awaits it; what a row may still await is its stage.

## Consensus

| id | mechanism | anchors | derivations | domains | proven by | awaits |
|---|---|---|---|---|---|---|
| CNS-01 | the TimeChain | Consensus, "The TimeChain" | — | `mt-proposal` | vectors: "A proposal, and its length", the identifier over the deterministic fields among them | — |
| CNS-02 | the round | Consensus, "The round"; Canon, "The round of a chain, in integers" | — | `mt-beacon`, `mt-round-att`, `mt-round-nf`, `mt-part-key` | vectors: "The round, the beacon, and the chain of a sender" | stage 13 |
| CNS-03 | the pulse and the close of a window | Consensus, "The pulse and the close of a window" | `target_rounds` | `mt-cascade` | the derivation; a scenario of the close | stage 13 |
| CNS-04 | the threshold of a round, computed from the admitted | Canon, "The threshold of a round"; Canon, "`round_floor` = 50" | `round_floor` | — | the derivation; the integer form; vectors: "Vectors of the threshold of a round", compared by the gate | — |
| CNS-05 | parallel chains | Consensus, "Parallel chains" | `k_max`, `k_step` | — | the derivations; a scenario of the split | stage 13 |
| CNS-06 | the runner's draw | Consensus, "The runner's draw"; Canon, "The draw, and the two canonical orders" | — | `mt-ticket` | vectors: "The aggregate, the ticket and the two orders" | — |
| CNS-07 | the nameless runner | Consensus, "Closing a window" | — | `mt-runner-key` | the proof that a ticket passed, inside the circuit | — |
| CNS-08 | the fold of the cement | Consensus, "Closing a window"; Canon, "The node of the fold" | — | `mt-bc-aggregate`, `mt-bc-aggregate-empty`, `mt-fold-work`, `mt-fold-node` | vectors: "The vector of the node's identifier" | — |
| CNS-09 | finality and the quorum | Consensus, "Finality"; Canon, "The commitment that carries standing" | — | `mt-weight`, `mt-standing-matrix` | vectors of the standing commitment | stage 13 |
| CNS-10 | the sanction of a double answer | Consensus, "The sanction of a double answer" | — | `mt-part-nf` | vectors: "The nullifier of a part, and the identifier of an application"; a scenario of two closings of one height | stage 19 |
| CNS-11 | the proof a window carries | Consensus, "The proof a window carries" | — | — | the circuit of a window; the argument the accumulation carries stands written in the document, symbol by symbol | — |
| CNS-12 | the constant join | Consensus, "The join" | — | — | a scenario of a stranger joining from the Genesis State Hash | stage 14 |
| CNS-13 | membership for a term | Consensus, "Presence and admission" | — | — | a scenario of a term expiring unobserved | stage 19 |
| CNS-14 | selection events | Consensus, "Presence and admission"; Canon, "The close of a window, and the slots an event offers" | — | `mt-nodereg`, `mt-nodereg-sort`, `mt-selection` | vectors: "The aggregate, the ticket and the two orders"; a scenario of admission | stage 19 |
| CNS-15 | the one-time right to raise a machine | Consensus, "Presence and admission" | — | `mt-operator-nf` | a scenario of the right spent once | stage 19 |
| CNS-16 | the commitment of a machine | Consensus, "What a machine commits about itself"; Canon, "The commitment standing for a machine" | — | `mt-node-commit`, `mt-node-key` | vectors: "The commitment standing for a machine" | — |
| CNS-17 | the three points of a round | Canon, "The points a round stands at" | `consensus_replicas` | `mt-round-point`, `mt-window-point` | the derivation and the ring rule | stage 13 |
| CNS-18 | the right to a window's share | Consensus, "The right to a window's share" | — | — | VAL-08, where the right and what redeems it stand | — |
| CNS-19 | the cold start | Consensus, "The cold start" | — | — | a scenario of the first window closing itself | stage 14 |
| CNS-20 | the way back | Consensus, "The way back"; Canon, "The close of a window, and the slots an event offers" | `recovery_onset_multiple` | — | the derivation; vectors: "Vectors of the way back"; a scenario of a split where one part resumes and the other never does | — |
| CNS-21 | the attestation of presence | Consensus, "The attestation of presence"; Canon, "The arithmetization, and how the set is bound to it" | — | — | the description written, proven and verified end to end at the height of its own duty, its length derived beside it, and `air_hash` recomputed over the five | stage 13 |
| CNS-22 | presence witnessed and never self-declared | Consensus, "Presence is witnessed and never self-declared" | — | — | a scenario of a machine outside the cement taking no share | stage 13 |
| CNS-23 | the proof of a window, carried apart | Consensus, "The proof a window carries"; Canon, "The proof of a window, carried apart"; Canon, "`unproven_depth` = 8" | `unproven_depth` | `mt-window-proof` | the derivation; vectors: "The proof of a window, and its length"; a scenario of a chain running ahead of its prover to the bound and waiting there | stage 14 |
| CNS-24 | the canonical order | Consensus, "The canonical order" | — | — | a scenario of one coordinate carrying one meaning for every participant and recomputed from the chain alone, and of a machine that has not seen the network holding no current window | stage 13 |
| CNS-25 | the secret of a machine | Consensus, "The secret of a machine" | — | — | a scenario of every published value derived from it in one direction under a domain of its own, of the owner branch kept apart from it, and of a device that is not a machine placing itself in a window by the same kind of secret | stage 13 |

## Value

| id | mechanism | anchors | derivations | domains | proven by | awaits |
|---|---|---|---|---|---|---|
| VAL-00 | the halves of a secret that spends | Canon, "The derivations of a note" | — | `mt-key-halves` | vectors: "An empty note tree, and the same tree after one commitment"; "The right of a machine, and the moment of extinguishing it" | — |
| VAL-01 | the note | Value, "The note"; Canon, "The derivations of a note" | — | `mt-note-pk`, `mt-note-cm` | vectors: "An empty note tree, and the same tree after one commitment" | — |
| VAL-02 | redemption derived from position | Value, "Redemption is derived from position" | — | `mt-note-nf` | vectors: "A nullifier, and its independence from the commitment" | — |
| VAL-03 | the two trees | Value, "The trees"; Canon, "The Merkle constructions" | — | `mt-merkle-leaf`, `mt-merkle-node`, `mt-note-leaf`, `mt-note-node`, `mt-record-leaf`, `mt-record-node` | vectors: "The walk of both trees, pinned away from position zero", "The tree of records, which a circuit walks", "The walk of the append-only tree, at three leaves" | — |
| VAL-04 | the rate set of the horizon | Value, "The trees" | — | — | a scenario of the set emptying when the stride of the horizon moves, and of reuse refused by the range rather than by memory | stage 15 |
| VAL-05 | the frame of fixed shape | Value, "The shape of a frame"; Canon, "The frame of a payment" | — | `mt-frame` | vectors: "A frame, and its length"; the circuit of a frame | — |
| VAL-06 | typeless positions | Value, "What the proof asserts" | — | — | the disjunction inside the circuit of a frame | — |
| VAL-07 | the horizon of proving | Value, "The shape of a frame"; Canon, "The horizon of proving"; Canon, "`proving_horizon` = 128 windows" | `proving_lag`, `proving_horizon` | `mt-horizon-leaf`, `mt-horizon-node` | the derivations; vectors: "The horizon fold, at three of its reach"; a scenario of a frame refused a root of a stride the horizon has left | stage 15 |
| VAL-08 | the right of a machine and the moment of extinguishing it | Value, "Extinguishing a right"; Canon, "The right of a machine to a share, and what redeems it" | `claim_spread` | `mt-admitted-leaf`, `mt-admitted-node`, `mt-credit-nf` | vectors: "The right of a machine, and the moment of extinguishing it"; the landing ranged over the standing stride inside the circuit | stage 15 |
| VAL-09 | the nullifier of the rate of payment | Canon, "The nullifier of the rate of payment" | `spends_per_window` | `mt-rate-nf` | vectors: "The nullifiers of the two rates"; the window ranged over the standing stride inside the circuit | stage 15 |
| VAL-10 | conservation by induction | Value, "Conservation of issuance" | — | — | the chained circuits of the windows | — |
| VAL-11 | disclosure of one payment | Value, "Disclosure" | — | — | a scenario of one payment opened and nothing else | stage 13 |
| VAL-12 | the double spend | Value, "The double spend" | — | — | a scenario of the second entry refused in silence | stage 13 |
| VAL-13 | settlement before a window | Value, "Settlement" | — | — | a scenario of a payment received in its round, and of its note spent onward the moment the stride holding its root stands | stage 15 |
| VAL-14 | the notice of a spend | Value, "Settlement"; Canon, "The points a round stands at" | — | `mt-notice-point` | vectors: "The vectors of the messages", "A notice, and its length"; a scenario of two frames meeting at one point | stage 13 |

## Identity

| id | mechanism | anchors | derivations | domains | proven by | awaits |
|---|---|---|---|---|---|---|
| IDN-01 | the birth of a seed | Identity, "The birth of a seed"; Canon, "The birth of a seed" | — | `mt-seed`, `mt-entropy-mix` | vectors: "The birth of a seed, end to end"; "Two chains stand here, and the second is the one that binds" | — |
| IDN-02 | the branches of a seed | Identity, "A person is a secret"; Canon, "The branches of a seed" | — | `mt-account-key`, `mt-note-key`, `mt-nf-key`, `mt-app-encryption-key` | vectors: "The branches of the two spaces, from a stated master seed" | — |
| IDN-03 | the record is a commitment | Identity, "The record of a person"; Canon, "The committed record of a person" | — | — | the layout and its invariants; the field set freezes with the artifact | — |
| IDN-04 | an act is three quantities and the rate beside them | Identity, "Acting"; Canon, "The action of a record" | — | `mt-op` | the layout and its invariants, compared by the gate | stage 17 |
| IDN-05 | opening a record | Identity, "Opening a record"; Canon, "The opening of a record" | `max_openings_per_window` | `mt-open-nf` | the layout and its invariants, compared by the gate; a scenario of the one-time right | stage 17 |
| IDN-06 | the nullifier of the rate of action | Canon, "The nullifier of the rate of action" | — | `mt-act-nf` | vectors: "The nullifiers of the two rates" | — |
| IDN-07 | changing a key | Identity, "Changing a key" | — | — | a scenario of standing moving inside the commitment | stage 17 |
| IDN-08 | closing a record | Identity, "Closing a record" | — | — | a scenario of a blank in the successor's position | stage 17 |
| IDN-09 | the fabric of time | Identity, "The fabric of time" | — | `mt-fabric-leaf`, `mt-fabric-node` | vectors: "The empty values of the fabric, and a fabric of one leaf" | stage 19 |
| IDN-10 | continuity | Identity, "Opening a record" | `continuity_required_num`, `continuity_required_den` | — | the derivation; the proof inside the circuit | — |
| IDN-11 | the age buckets | Identity, "Age and the barriers of time" | — | — | the proof inside the circuit: proven, never published | — |
| IDN-12 | a name: commit, reveal, renew | Identity, "Claiming a name"; Canon, "The three objects of a name" | `name_reveal_windows`, `name_renew_windows`, `name_chain_length`, `name_min_length`, `name_max_length` | `mt-name-slot`, `mt-name-own`, `mt-name-chain`, `mt-name-commit`, `mt-name-commit-op`, `mt-name-reveal-op`, `mt-name-renew-op` | vectors: "A name: its slot, its chain and its commitment" | stage 17 |
| IDN-13 | a channel | Network, "A channel"; Canon, "The objects of a channel" | — | `mt-channel-slot`, `mt-channel-key`, `mt-channel-head`, `mt-channel-point`, `mt-channel-commit-op`, `mt-channel-reveal-op`, `mt-channel-pub-op` | vectors: "A channel: its slot, and the head of a publication" | stage 17 |
| IDN-14 | the nullifier of a reach | Canon, "The nullifier of a reach into the space of slots"; Network, "Asking what a slot publishes" | — | `mt-lookup-nf` | vectors: "The nullifier of a reach into the space of slots" | — |
| IDN-15 | the fingerprint compared out of band | Canon, "The fingerprint compared out of band"; Identity, "Binding a handshake to a key" | — | `mt-safety` | vectors: "The fingerprint compared out of band" | — |
| IDN-16 | the contact root of a name | Network, "First contact by a claimed name"; Canon, "The contact key of a name" | — | `mt-name-contact-key`, `mt-name-tag`, `mt-name-first` | vectors: "The tag of first contact to a claimed name" | stage 18 |
| IDN-17 | the nullifier that spends a version of a record | Canon, "The nullifier of a version of a record" | — | `mt-record-nf` | vectors: "The nullifier of a version of a record" | — |

## Network

| id | mechanism | anchors | derivations | domains | proven by | awaits |
|---|---|---|---|---|---|---|
| NET-01 | the post-quantum handshake | Network, "Where a shared secret comes from"; Canon, "The post-quantum handshake, in integers" | — | `mt-noise-pq-v1-master`, `mt-noise-pq-v1-i2r`, `mt-noise-pq-v1-r2i`, `mt-noise-pq-v1-sig-r`, `mt-noise-pq-v1-sig-i`, `mt-noise-pq-v1-transcript` | vectors: "The post-quantum handshake", with the normative negative | — |
| NET-02 | the tag of a window | Network, "There is no address"; Canon, "The integer form of a tag" | — | `mt-tag` | vectors: "A tag and the labels of its steps" | — |
| NET-03 | the holder rule | Network, "Which machine holds a tag"; Canon, "The holder of a tag" | — | — | vectors: "The holder of a tag" | stage 18 |
| NET-04 | the ring entries and the path | Network, "The path"; Canon, "The seal of a step and the placement of a sender" | `path_max` | `mt-relay-seal`, `mt-relay-path`, `mt-owner-key` | vectors: "The seal of a step, and the placement of a sender" | stage 18 |
| NET-05 | the cell | Network, "The cell"; Canon, "The cell, and the two seals it carries" | `cell_bytes` | `mt-step`, `mt-pipe-key` | the derivation; the messages of the wire, compared by the gate | — |
| NET-06 | the canonical slot | Network, "The canonical slot" | — | `mt-slot` | vectors: "The seal of a step, and the placement of a sender" | stage 18 |
| NET-07 | the right of carriage | Network, "The tag is a right of carriage" | — | — | a scenario of the right spent once at the holder | stage 18 |
| NET-08 | deferred collection | Network, "Deferred collection"; Canon, "The profile of a deferred delay: uniform over the window" | — | `mt-collect` | the stated profile; a scenario of the holder pulling | stage 18 |
| NET-09 | waking a sleeping device | Network, "Waking a sleeping device" | — | — | a scenario of sixteen random bytes and a window | stage 18 |
| NET-10 | the rendezvous of a stream | Network, "A stream" | — | — | a scenario of two derivations meeting at one tag | stage 18 |
| NET-11 | the erasure code | Canon, "The erasure code of a delivery" | `redundancy_num`, `redundancy_den`, `erasure_group` | `mt-delivery` | the derivations; vectors of the delivery, compared by the gate | stage 18 |
| NET-12 | the digest set of a window | Network, "Entry, and failure" | — | — | a scenario of a repeated header discarded in silence | stage 18 |
| NET-13 | the stable entries | Network, "Entry, and failure" | — | `mt-entry` | vectors: "The point of a ring of entries" | stage 18 |
| NET-14 | the inbound slots | Canon, "`inbound_slots` = 96" | `inbound_slots` | — | the derivation; a scenario of silence at the ceiling | stage 18 |
| NET-15 | silence on failure | Network, "Entry, and failure" | — | — | a scenario of a failed check answered with nothing | stage 18 |
| NET-16 | carrying is the work | Network, "Carrying is the work"; Canon, "What a device answers a stranger with" | — | — | a scenario of the budget spent on a stranger | stage 18 |
| NET-17 | discovery without a map | Network, "Discovery without a map" | — | — | a scenario of a rule reading acquaintances, not a directory | stage 18 |
| NET-18 | what a device spends on a stranger | Network, "What a device spends on a stranger" | — | — | a scenario of a deposit at a point taking no slot, of a link released for carrying nothing across a window, and of a budget divided equally across the links a device holds | stage 18 |
| NET-19 | what carries a message | Network, "What carries a message" | — | — | a scenario of a body cut into cells of one width and carried hop by hop, with no quantity of the delivery crossing the path unchanged | stage 18 |
| NET-20 | nothing is made even | Network, "Nothing is made even" | — | — | a scenario of no synthetic filler on the wire, the volume carried being other people's letters | stage 18 |
| NET-21 | how the objects of consensus travel | Network, "How the objects of consensus travel" | — | — | a scenario of an object of consensus riding the same cells as correspondence, deposited at every point of its round by a machine that computed them without asking anybody | stage 13 |
| NET-22 | privacy is not rented | Network, "Privacy is not rented" | — | — | a scenario of privacy standing whole with every external tunnel switched off | stage 18 |
| NET-23 | the threat model of the wire | Network, "Threat model of the wire" | — | — | the model itself, read against the observability ledger of this document | stage 22 |

## App

| id | mechanism | anchors | derivations | domains | proven by | awaits |
|---|---|---|---|---|---|---|
| APP-01 | the anchor | App, "The anchor" | — | — | a scenario of thirty-two bytes on the identity plane | stage 17 |
| APP-02 | the identifier of an application | App, "The identifier of an application"; Canon, "The identifier of an application" | — | `mt-app` | vectors: "The nullifier of a part, and the identifier of an application" | — |
| APP-03 | the economics of an application | App, "The economics of an application" | — | — | held by construction: no protocol fee exists to build | — |
| APP-04 | the reproducibility of a client | App, "The reproducibility of a client" | — | — | a scenario of one release hash in three places | stage 20 |
| APP-05 | the boundary of the protocol and the client | App, "The boundary" | — | — | a scenario of a client holding none of the four layers and asking the protocol to carry none of its own, and of proving moved only between the devices of one owner | stage 21 |
| APP-06 | what a client owes the person | App, "What a client owes the person" | — | — | a scenario of an unverified handshake marked as such until a comparison, and of a consequence stated before the act | stage 21 |

## Canon

| id | mechanism | anchors | derivations | domains | proven by | awaits |
|---|---|---|---|---|---|---|
| CAN-01 | the single source of values | Constitution, "The document set" | — | — | the gate compares every value on every build | — |
| CAN-02 | the registry of domain separators | Canon, "The registry of domain separators" | — | — | the gate parses the registry; the alphabet closes prefixes | — |
| CAN-03 | canonical serialization and the signed object | Canon, "Canonical serialization"; Canon, "Rules for a signed object" | — | — | the round trip in both directions for every class | — |
| CAN-04 | integer arithmetic | Constitution, "The global invariants" | — | — | the integer forms of Canon with their vectors | — |
| CAN-05 | the Genesis State Hash | Canon, "The Genesis Decree" | — | `mt-genesis-state` | the gate recomputes it from the parameters | — |
| CAN-06 | the doors and the boundaries of eras | Canon, "The suite table"; Canon, "The three quantities of a boundary" | — | — | the tables and their demands, compared by the gate | stage 16 |
| CAN-07 | the observability ledgers | Constitution, "The document set" | — | — | a ledger per layer document, each with a denominator | stage 21 |
| CAN-08 | the conformance sets | Canon, "Conformance set"; Constitution, "What the set does not yet fix" | — | — | the sets themselves, one per document | — |
| CAN-09 | the evolution of the protocol | Constitution, "Evolution of the protocol" | — | — | a scenario of a version crossing and a fork resolved by height | stage 16 |
| CAN-10 | the proof scheme | Canon, "The proof scheme"; Canon, "The verifier of a proof"; Canon, "The height of the presence, and the length of its proof"; Canon, "The arithmetization, and how the set is bound to it" | — | `mt-proof-transcript`, `mt-proof-query`, `mt-proof-air`, `mt-proof-leaf`, `mt-proof-node` | vectors: "The vector of the encoding"; the five domains of a proof | — |

## What the Registry does not claim

A row is an address book entry and a status, never a second description: the mechanism lives
where its anchors point, and a reader who stops at this table has read none of the protocol.
The awaits column speaks about proof material only — a vector or a scenario not yet frozen —
and says nothing about the maturity of the prose it points into, which is the concern of the
conformance set of each document.
