# Montana — Canon

**Version:** 10.0.0

Canon is the one place where the values and the bytes of Montana live. Every other document
of the set names a quantity and points here; none of them restates a number, a size, a
separator or a layout. A value found outside Canon is a second source of truth, and two
sources drift.

## Scope

**In scope.** The cryptographic primitives and their sizes; the rules by which a signed
object is scoped, identified and aggregated; the canonical serialization of every consensus
object; the Merkle construction and the domain-separated hash primitive; the registry of
domain separators; the parameters of the Genesis Decree; the layouts of consensus objects
together with their invariants; the test vectors that fix all of it.

**Not in scope.** Why a rule exists and what it protects — Constitution. The movement of the
clock and the finalization of a window — Consensus. Notes, proofs and transfers of value — Value.
Records of people, keys and the operations of the identity plane — Identity. Pipes, labels and
delivery — Network. Anchor semantics for applications — App.

Canon states what is; it argues nothing.

## Primitives

Two primitives carry consensus, with separated roles.

| Primitive | Role |
|---|---|
| SHA-256 | beacons and round eligibility, draw endpoints, tags and labels, Merkle trees, every hash composition |
| ML-DSA-65 (FIPS 204, NIST level 3) | signatures of the actions of a person and of the proposals of a machine |
| ChaCha20-Poly1305 (RFC 8439) | the sealing of a cell at every step and of a letter inside its pipe |
| `proof_hash` | the trees and the transcript inside a proof, and the tree of notes, whose paths exist only as witnesses of proofs |

SHA-256 carries the quantum resistance of consensus: Grover reduces its security from 256
bits to 128. ML-DSA-65 rests on module-lattice problems (Module-LWE and Module-SIS).

ChaCha20-Poly1305 carries no assumption of its own: its confidentiality rests on a permutation
and its authentication on a universal hash over a prime field, both quantum-indifferent at a
symmetric key of 256 bits, and both already required by any implementation that seals a cell.
The tag is 16 B, the nonce 12 B, and the associated data is stated at every use.

**A second hash exists, and its whole justification is one mechanism.** [I-7] admits a primitive
that closes a mechanism the set cannot close otherwise, and this one is named: what a circuit
verifies it must compute in its own arithmetic. A frame's proof walks the tree of notes and derives
the envelope of every note it redeems or creates, which is all but a handful of the rows the
circuit of a frame holds; a presence and a ticket walk the tree of the electorate and derive the
nullifier and the digests they publish. SHA-256 is built of bitwise operations, so one
compression of it costs about two thousand rows of a trace — and must carry its eight words of
state and sixteen of schedule through every one of those rows, which no trace within the width
bound can hold at all; a hash built of the additions and multiplications a proof already performs
costs about `rows_per_permutation` rows and carries twelve cells. With the first, the recursion
settles at a trace of `2²⁷` and a prover of hundreds of gigabytes, which [I-5] forbids outright,
and the frame nowhere, because the width refuses it before the height is asked; with the second,
both settle at the traces this document freezes. The mechanism is load-bearing, the cost of closing it any other way
is unbounded, and the primitive is therefore admitted rather than avoided.

**Its scope is a boundary, not a preference, and the boundary is drawn by the judge of the
binding, not by the wire.** Every hash whose binding must hold with no proof in hand stays
SHA-256 — the identifier of an object, every derivation of a key of a person or a machine, the
commitments and nullifiers of the identity plane, the trees of state and the leaf of the fabric,
every tag and every fingerprint, every quantity a person or an independent implementation
compares — because those bindings must not stand on an assumption younger than the rest, and the
table of demands enforces the split mechanically, row by row. What `proof_hash` binds is what
only a verifier of a proof ever judges: the Merkle trees of a proof, its transcript, the tree of
notes — and the envelope of a note, its commitment, the halves of its nullifier key, its
nullifier and the nullifier of its rate, because a spend is admitted by a verified frame and by
nothing else, so the one judge of those bindings is the verifier the circuit already stands
before, and a function the circuit cannot carry would put the envelope beyond proving. Machines fold that tree and carry its root,
as they already run this function over every proof they verify: carriage is not judgement. The
list of domains of the `proof_hash` family stands in the registry section, it is exact, and a
domain outside it computed with this function is a defect.

**The honest cost, stated rather than folded away.** An algebraic hash is younger than SHA-256 and
its family has lost members to attack. What rests on it is the soundness of a proof, the
structural binding of the one tree whose only judge is a proof, and — since the envelope of a
note is proven inside the circuit — the hiding of an amount and the unlinkability of a
nullifier: a break of the sponge forges proofs and mints value whatever function anything folds
under, and a break of its pseudorandomness reads the privacy of notes, so one primitive carries
both stakes and they are named together rather than folded away. No existing record, no name and
no cemented window that a verifier holds is reached or rewritten by either. The retirement of a weakened row is the era door, and
the tree of notes crosses it by the freezing rule the boundary section states for long-lived
trees. That is the trade, and it is taken with the name of what is risked written beside it.

**The proof hash, named.** `proof_hash` is the Poseidon2 permutation over `proof_field`, at the
authors' own instantiation for a state of width 12: the power is 7, the rounds are 8 external and
22 internal, and the constants are the reference's, reproduced verbatim and held to the known
answer below — an implementation that transcribed one constant wrongly, folded a matrix in
another order, or raised to another power reproduces none of its twelve words. The table of
demands is answered where it asks: collision resistance at 128 bits from a capacity of 256 bits,
the width from a digest of four elements, and provability inside the circuit by construction —
one permutation is about `rows_per_permutation` rows. Pseudorandomness the envelope of a note asks of
it, and the sponge answers with its capacity: two hundred fifty-six bits no absorbed limb ever
touches. Every key a person derives, every right of the identity plane and every quantity
compared without a proof in hand stays SHA-256, and the demand table says so row by row.

```
the permutation of (0, 1, 2, …, 11), the authors' known answer, each word unsigned little-endian:
proof permutation, words 0..3  = 01eaef96bdf1c0c1, 1f0d2cc525b2540c, 6282c1dfe1e0358d, e780d721f698e1e6
proof permutation, words 4..7  = 280c0b6f753d833b, 1b942dd5023156ab, 43f0df3fcccb8398, e8e8190585489025
proof permutation, words 8..11 = 56bdbf72f77ada22, 7911c32bf9dcd705, ec467926508fbe67, 6a50450ddf85a6ed
```

**The doors of the proof hash, and there are two: `sponge` and `node`.** Bytes enter the field
in little-endian limbs of four bytes each, the last limb short where the length demands — four
and never seven, because it is the one width at which every seam of this protocol falls on a
limb: a 32-byte field is exactly eight limbs, a word of SHA-256 is exactly one, a word of the
state is exactly two, and the limbs of a public boundary are these same limbs. Every limb is
canonical and no fixed-length byte string shares an encoding with another. A digest of this
family re-enters an absorption as `cells(x)` — its four unsigned eight-byte little-endian words,
each below the modulus, a 32-byte value whose word stands at or above it being refused — so a
derivation that consumes another never crosses bytes at all, and no splitting of a word into
limbs, whose second preimage a circuit would have to refuse, exists anywhere in the family. `sponge(domain, x)`
takes a domain of the registry: its capacity of 4 elements is the first four limbs of the
domain's empty hash — `SHA-256(domain || 0x00)`, the value the registry already fixes — its rate
of 8 absorbs the elements of `x` in blocks by overwrite, the input ends with a single one-element
and zeros to the block boundary, and the digest is the first four elements of the state, 32 B
little-endian, which is `hash_bytes` wide. `node(domain, left || right)` takes two digests —
eight canonical elements, exactly the rate, a form fixed with no padding between it and the
permutation — so one node of any tree of this family is one permutation, which is what the count
of a circuit stands on. A leaf of a tree is the sponge over the values its position carries.

ML-KEM-768 (FIPS 203, NIST level 3) is applied to client-side encryption, outside the
consensus surface. ML-DSA-65 and ML-KEM-768 stand at one security level and rest on one
family of problems.

Auxiliary compositions over SHA-256 — HMAC-SHA-256 (RFC 2104), PBKDF2-HMAC-SHA-256
(RFC 8018), HKDF-Expand (RFC 5869) — appear in client-side derivation from a mnemonic. They
introduce no independent assumption.

### Where a size stands

No table of sizes stands here, because a table of loose values is exactly what the law of the
layers forbids: a value would have no block, and therefore no layer. Every size of this protocol
stands in the block that gives it its layer, and this section says which.

- The sizes of a scheme — the two keys and the signature — stand in the row of its suite, since
  they move only when a suite does.
- The width of a hash output stands among the parameters of the Decree, as `hash_bytes`, since it
  is the width of every root that hash binds.
- The size of a cell stands among the forms, as `cell_bytes`, since a boundary may move it.
- The widths of a label, of a seal, of an AEAD nonce and of an AEAD tag stand in the row of the
  form table, which binds the layouts they belong to.

Montana uses the deterministic variant of ML-DSA-65 (RND = 0x00 × 32, FIPS 204): under one
(secret key, message) the signature is bit-exactly the same.

### The suite table

The suite table is a door, exactly as the hash table is: a row of it may be added at a boundary
between eras, and the sizes of a scheme follow its row rather than standing in a section of their
own. What a row binds is the scheme and every width that scheme brings with it.

| suite_id | Scheme | Secret key | Public key | Signature |
|---|---|---|---|---|
| 1 | ML-DSA-65 | 4 032 B | 1 952 B | 3 309 B |

The scheme of encapsulation a suite carries stands beside it, since it moves when the suite does:
row 1 carries ML-KEM-768, whose secret key is 2 400 B, whose public key is 1 184 B and whose
ciphertext is 1 088 B.

A future suite enters through a protocol version upgrade and an explicit row here. An object names
the row it was signed under, and a verifier reads the widths of that row rather than any it holds
of its own.

## Rules for a signed object

**R1 — signed scope.** Every signed object has canonical bytes with the signature field last.
The message given to sign and to verify is everything before that field:

```
signed_scope(obj) = canonical_bytes(obj)[0 .. len(canonical_bytes) - signature_size(signer_suite_id(obj))]
```

No SHA-256 layer is applied above signed_scope: ML-DSA forms its challenge with SHAKE-256
internally, so an outer hash is redundant.

**signer_suite_id(obj):**

| Class of object | signer_suite_id |
|---|---|
| an action of the identity plane | the current suite carried in the acting record |
| Proposal header | the suite the proposal carries, checked natively under the key the ticket proof names by its digest |
| window confirmation | the suite the confirmation carries, checked natively under the key the proof of presence names by its digest |
| a pledge of the agreement | the suite the pledge carries, checked natively under the key the proof of presence of its part's confirmation names by its digest |
| a publication of a channel | the suite the reveal of that slot published |

A candidacy carries no signature and stands in no row above: the key it would sign with is published
nowhere, so it is proven instead. Its identifier, like that of an object of the plane of names, is
taken over the whole of its canonical bytes under `mt-nodereg`.

**The proofs of consensus** are Consensus's: the proof a proposal carries asserts that the runner's
ticket cleared and names the key the proposal answers under by its digest, and the proof a
confirmation carries asserts the presence of a machine of the electorate, names the key it
answers under by its digest, and asserts the value of the line of the open slot of attempt zero,
and the proof a pledge carries asserts the value of the line of its
slot and names no key. None asserts a suite: the suite an object carries is checked
natively, by verifying its signature under that suite with the key the proof names. Consensus holds
the rule; Canon holds only what a signer must know to compute a signed scope.

For a change of key the **old** key signs; the new key defines verification of what follows.

**R2 — stable identifier.** The canonical identifier of a signed object in any consensus hash
composition:

```
identifier(obj) = SHA-256(class_domain(obj) || 0x00 || signed_scope(obj))
```

It is taken from signed_scope and never from the wire bytes, so it does not move when an
object is re-signed, under any present or future variant of the scheme.

**R3 — aggregation for a seed.** An aggregate feeding a consensus-critical seed takes only
signer identities and a temporal anchor — never content, never signatures, never identifiers:

```
aggregate_for_seed(S, agg_domain, empty_domain, context) :=
  S empty      ->  SHA-256(empty_domain || 0x00 || context)
  otherwise    ->  SHA-256(agg_domain || 0x00 || concat_sorted(signer_id(s) for s in S) || context)
```

`signer_id(s)` is the commitment standing for the signer's machine, the one derived under
`mt-node-commit`; Consensus holds how a signer enters a cemented set and Constitution holds why a
machine is accountable without being named.

The grinding surface of one participant is zero: its commitment is fixed at registration, the
context is canonical, and the composition of the set is emergent.

**R4 — the two are never mixed.** An R2 identifier carries content that its author may
choose; feeding it into a seed would restore the grinding knob R3 exists to remove.

## Canonical serialization

| Type | Size | Encoding |
|---|---|---|
| u8 | 1 B | the raw byte |
| u16 | 2 B | little-endian |
| u32 | 4 B | little-endian |
| u64 | 8 B | little-endian |
| u128 | 16 B | little-endian |
| bytes[N] | N B | raw, no length prefix |

Every integer is unsigned and little-endian. Fixed-length byte arrays carry neither prefix
nor separator. A structure is the concatenation of its fields in declaration order, without
padding. A variable-length array is a count field followed by its elements; where the struct
does not name the count field, the prefix is u16 little-endian.

**Canonical order.** Where order enters a hash, it is fixed: identifiers of attested
operations ascend lexicographically; the cemented set of a window ascends by the signer's
commitment; candidates of a selection event and registrations of a window ascend by their
sort keys. Lexicographic comparison runs from the most significant byte.

**Bijection.** One logical value has exactly one valid byte representation: fixed
endianness, fixed field order, an explicit count before every variable array, no optional
field, no alternative form. A breach is a consensus-critical defect — two implementations
would produce different signed scopes for one value, and a signature valid for one would
fail for the other. It is checked per class by round trips in both directions.

## The layers of this set

Four layers, named and never numbered. The word `tier` in this project stays with the four passes
made over the set and means nothing here.

- **The Kernel** — the grammar that has no replacement: the shape of a preimage, the alphabet of a
  name, the rule of fixed widths, the constructions of the trees, the rule by which a signed object
  is identified, the canonical orders. A network that changed any of it would not be reading the
  objects of this protocol.
- **The doors** — what may be replaced without changing the grammar: the table of functions, the
  table of suites, the table of forms. A row is added at a boundary between eras.
- **The Decree** — the numbers, in its two blocks: the parameters the Genesis State Hash binds and
  the forms a boundary may move.
- **The planes** — what the network publishes of an act, which is the vocabulary and nothing else.

**How a reader decides where something belongs**, without asking an authority: name its
replacement. If a replacement can be named, it is a door. If it stands as bytes on the wire and a
row could carry another value, it is of the Decree. If two implementations differing there would
produce different bytes for the same act, and no replacement can be named, it is of the Kernel. If
they would produce the same bytes, it is of neither and belongs to no layer of the core at all.
Nothing enters the Kernel by assertion.

**The Kernel holds no value.** Every number and every function of this set stands as a row of one
block — the parameters, the forms, the table of suites, the table of functions, the table of forms
— or as a frozen vector, which is an artifact of verification and belongs to no layer. The layer of
a value is therefore the block it stands in: read off rather than assigned, and a value standing in
no block, or in two, is a defect. What a mark would have left to judgement, placement settles. The
rule takes no exception: a quantity the Kernel *demands* is not thereby a value *of* the Kernel —
it stands in the block that binds it, and the Kernel demands it from there, as the shape of a
preimage demands its width from the parameters.

**The law of the planes, and its one carve.** A plane publishes of any act only the vocabulary —
a commitment, a nullifier, a proof — and nothing else: not a name, not an address, not a count, not
a party. The one carve is the deliberate publication a participant makes of itself, and it is
marked in every ledger of observability it appears in, so that a reader of a ledger never mistakes
a disclosure for a leak or a leak for a disclosure.

## The hash primitive

```
hash(domain, parts) := SHA-256(domain || 0x00 || parts[0] || parts[1] || ...)
```

A domain separator is raw ASCII, with neither terminator nor length prefix. The NUL byte
after it is what makes the construction self-delimiting: no domain name contains 0x00, so
for any domains and any attacker-chosen parts, equal hashes imply equal domains and equal
concatenations. Prefix-related names in the registry — one domain being the beginning of
another — therefore cannot collide.

**One concatenation, boundaries fixed by the rule.** The NUL delimits the domain, never the
parts: the parts of one call are one concatenation, and `hash(d, [a, b])` equals
`hash(d, [ab])` by construction. A rule that names a hash therefore fixes the length of every
part it passes, save at most one; two adjacent parts of open length would give one preimage
two readings, and no rule of this set states such a pair.

**The rule of fixed widths is normative.** Parts are one concatenation, and they read one way only
because every part but at most one is of a width the set fixes — by the type that carries it or by
a row of the Decree. A value of no fixed width enters a preimage only with its length before it, or
as the whole of a body where nothing follows it and nothing can be split from it. A rule of this set
that named two adjacent parts of open length would give one preimage two readings, and no rule
does.

**A domain separates preimages, never outputs.** Two quantities hashed under different domains
differ in value and are equally indistinguishable from random to anyone without the preimage.
Nothing about a published hash says which domain produced it, and a reader who concludes that
two domains make two visible kinds has confused what the construction separates: it separates
what may collide, not what may be told apart. This is why typeless positions and a registry of
many domains hold together without tension.

Throughout the set the short form `SHA-256("mt-x" || parts)` always denotes
`hash("mt-x", parts)`. The NUL is part of the primitive, never an option.

**The form and the function are two things, and this section is the form.** What stands above —
the shape `domain || 0x00 || parts`, the NUL that delimits, the one concatenation, the rule that
fixes every length save one — has no replacement: it is the grammar every object of this protocol
is written in, and a network that changed it would not be reading the same objects. What function
fills that shape is a door, and it stands in the table below. This section therefore names no
function and no width: the width is the row `hash_bytes` of the parameters, and the function is
the first row of the table.

### The form table

The third door. A row of it binds the shapes an implementation writes and reads, and a boundary
between eras may add one.

| Row | What it binds | Widths it carries |
|---|---|---|
| 1 | the layouts of the public objects, the layout of a deposit at a point, and the size of a cell | a label of a step 16 B, a seal of a step 16 B, an AEAD nonce 12 B, an AEAD tag 16 B |

A row binds shapes and never functions or numbers of the Decree: what a layout is made of stays
where it is stated, and what the row says is which set of layouts is in force. The size of a cell
stands in the row because it is the one width every layout of the wire is cut to, and a boundary
that moved the layouts while leaving the size would produce objects no drain could carry.

**The length of a proof is a declaration of its artifact.** It is not a number the set chooses: the
artifact `air_hash` binds declares it, and this document states the length that artifact declares
so that every layout carrying a proof has a total. Every total a proof enters is therefore a
quantity of the era in force — a boundary that admits another artifact moves those totals with it,
and an implementation reading a total reads it under the era of the object it is parsing. A
conformance set is claimed only over quantities that are frozen: while a quantity a document cites
as fixed is not yet frozen here, no implementation claims conformance over it, and the document
says so rather than implying otherwise.

### The three quantities of a boundary

A boundary between eras is where a row of a door changes. Three quantities size it, and none of
them is a number of its own: each is denominated in a quantity already frozen above, so a boundary
adds no constant to this set.

| Quantity | Value | What it is |
|---|---|---|
| `era_distance` | `membership_term` | the distance a boundary stands at, from the window that cements its adoption to the window it takes effect in |
| `drain_span` | `retarget_period` | the span through which the retired row and its successor are both accepted on the wire |
| `successor_support` | `membership_term` | how long after a boundary the opening era still verifies a proof of the era it closed |

**The distance a boundary stands at.** Target: no machine that is a member when a boundary is
adopted meets that boundary without having seen it. Derivation: membership ends after
`membership_term` of absence, so a machine present at the adoption and still a member at the
boundary has been present for some window between them, while a machine absent longer has lost
membership and rejoins by verifying one proof, which carries the rules in force. `membership_term`
is therefore exactly sufficient. Sensitivity: below it, a member can sleep through an adoption and
wake under a row it never read; above it, the network waits without gaining a reader, since the
machines that would gain are no longer members. Defence — why not a number of its own: a constant
chosen here would have to be re-derived every time membership moved, and the two would part.

**The span of a drain.** Target: no observable a retarget consumes spans two rows of a door.
Derivation: every retarget of this set consumes its observable over exactly `retarget_period`, so a
boundary inside a period would feed one of them two populations — cells of two sizes, tickets under
two shapes — and the rule that reads it would be reading a mixture rather than a network. A drain of
one period places every boundary between two periods for every observable. Sensitivity: shorter,
and a delivery in flight at the boundary is refused by a peer that has already retired the old row,
which the erasure code does not repair, since a group is of one size; longer, and two rows coexist
through a second period no observable needs. Defence — why not the longest deferred collection: a
collection deferred past a period is answered by a fresh request under the row in force, so it asks
nothing of the drain.

**The support a successor owes.** Target: a device returning with a proof of the closing era finds
a verifier for it rather than a refusal. Derivation: a device away at most `membership_term`
returns as a member and may hold a proof of the era it left; beyond that it rejoins from nothing
and takes the newest proof, which is of the opening era. Sensitivity: below it, a member that
merely slept is told its proof is unreadable and rejoins from nothing; above it, the opening era
carries a verifier nobody calls. Defence — why the same quantity as the distance: both answer the
same question from opposite sides, which is how long a member may be absent and still be one.

### How an era is resolved from a window

The era of a window is the count of boundaries whose effective window stands at or below it. A
boundary becomes effective by the lifecycle the Constitution states — a proposal published as an
Anchor, implementations released, machines running them — and the window it takes effect in stands
at least `era_distance` beyond the window that cemented its adoption.

**No object carries an era.** Every object carries the height it belongs to, and a reader resolves
the era from that height and from the boundaries the chain already holds. An era field on an object
would be a second statement of what the height already says, and two statements part: an object
whose era disagreed with its height would have to be judged by one of the two, and whichever a
reader chose would make the other decoration.

### The table of demands

Every form of the Kernel that consumes a function asks it for named properties, and a row of the
hash table is admitted when it answers all of them. Admission is therefore a check and never an
argument, and a reader sees what a successor function must carry before anyone proposes one.

| Form of the Kernel | What it asks of the function |
|---|---|
| the identifier of a signed object | collision resistance, width |
| the leaf and the node of both tree constructions | collision resistance, width, provability inside the circuit |
| the empty value of a construction | collision resistance, width |
| a commitment of a plane | collision resistance, preimage resistance, width |
| a nullifier of a right | preimage resistance, pseudorandomness, width |
| the envelope of a note — its commitment, the halves of its nullifier key, its nullifier, the bound on its rate | collision resistance, preimage resistance, pseudorandomness, provability inside the circuit, width |
| the redemption of a right — its nullifier and the moment it is extinguished at | preimage resistance, pseudorandomness, provability inside the circuit, width |
| a key derived for one use | pseudorandomness, width |
| the ticket of the draw, which only a circuit judges | pseudorandomness, collision resistance, provability inside the circuit, width |
| an order key — a selection event, a registration, the cascade | pseudorandomness, collision resistance, width |
| the label and the point of a delivery | pseudorandomness, width |
| the transcript of a handshake | collision resistance, width |
| the aggregation that feeds a seed | collision resistance, pseudorandomness, width |

The width is not a property a row declares: it is the parameter `hash_bytes`, and a function
answering at another width is refused. The other four are properties of the function itself, and a
row that answers three of them is not admitted for the forms that ask the fourth.

### The hash table

| Row | Function |
|---|---|
| 1 | SHA-256 |

A row names a function and nothing else. It does not name a width: the table admits only functions
answering at `hash_bytes`, so a function of another width is refused rather than admitted with a
note beside it, and the width is a parameter no boundary reaches. It does not name a shape either:
the shape is the form above, and every row fills the same one.

A row is admitted when the function it names answers every property the table of demands asks of
the forms that consume it — collision, preimage, pseudorandomness, the width, and provability
inside the circuit — so admission is a check and never an argument. Which row is in force at a
window is resolved from the era of that window by the rule the boundary states, and no object
carries a row: an object is read under the row its era holds.

## The Merkle constructions

Two shapes exist and they are not interchangeable: a **sparse** tree keyed by a value, which
holds sets, and an **append-only** tree indexed by position, which holds a growing sequence.
They share the shape of the fold and the shape of the empty values below, and nothing else — the
walk differs, the proof differs, and using one where the other is meant produces a different root
from the same contents. **Each use names its own leaf and node domains**: the trees of state fold
under the Merkle leaf and node domains, the tree of records under the record leaf and node
domains, the fabric of time under the fabric leaf and node domains, and the tree of notes under
the note leaf and node domains — the last three of the `proof_hash` family, by the boundary the
primitives section draws.

**What the boundary asks is who judges a path, and never who holds a root.** Every root of the
state is recomputed from state by every machine of the network as a proposal is verified — the note
root as much as the record root — so recomputing a root cannot be what decides the family, or no
tree could ever be of the proof hash and the tree of notes could not be the one it is. What decides
is the path: where the only reader of a path is a circuit, the fold is of the proof hash; where a
person or an independent implementation follows a path with no proof in hand, it stays SHA-256.

By that reading the fabric is the plain case — its every path is a witness and nothing outside a
proof ever follows one — and the tree of records is the case the tree of notes already settled: a
candidacy proves its continuity out of the record that holds it, so a circuit walks it, and no one
else does. What is new is only the cost, and it is what forces the question rather than answers it:
this tree is sparse at the width of a key, so a walk of it under SHA-256 is several times the whole
height the memory of a commodity device admits, and no choice of parameter moves that — the depth
is the width of a key and the family is a row of a table.

**The price is named and not hidden: the membership of a record stands on a function younger than
SHA-256** — the same price the tree of notes and the tree of admitted machines already carry, so
this is one more of a kind rather than a first. The two alternatives are worse for reasons the set
states elsewhere in its own words: a second tree of one content is two roots able to disagree,
which the law of one place exists against, and an accumulator in place of a walk owes a second
argument of soundness where the first is not yet written.
One construction serving two purposes still yields two unrelated roots from identical contents —
and the empty values of one use are its own, since the empty leaf is that use's leaf door applied
to nothing.

**Absence stands on the form.** The empty leaf is the leaf door of the construction over a body
of no bytes — `SHA-256(leaf_domain || 0x00)` where the family is SHA-256, the sponge under the
leaf domain over no elements where it is the proof hash. Every leaf that is present is that door
over at least one byte or one element, so no present leaf is the empty leaf, and the difference
is one of shape rather than one of luck: it holds for any function either table admits, and an
ideal one would not improve it. Thirty-two zeros would leave two things standing on a property of
the function instead — that the count of leaves a root binds is what no leaf hashes to zero, and
that a proof of absence means absence.

| Operation of the note tree | Formula |
|---|---|
| leaf | `sponge("mt-note-leaf", cells(commitment))` |
| internal node | `node("mt-note-node", left \|\| right)` |
| empty leaf | `sponge("mt-note-leaf", ())` |
| empty internal at level k+1 | the internal node of two empty internals at level k |

| Operation of the fabric | Formula |
|---|---|
| leaf | `sponge("mt-fabric-leaf", limbs(record_commitment \|\| window_8B_LE \|\| blind))` |
| internal node | `node("mt-fabric-node", left \|\| right)` |
| empty leaf | `sponge("mt-fabric-leaf", ())` |
| empty internal at level k+1 | the internal node of two empty internals at level k |


### The sparse tree, keyed by a value

The construction is one; the pair of domains it folds under belongs to the table, and two tables
of one pair is a defect the registry of mechanisms carries as such. Two pairs exist today.

| Operation, for a table no circuit walks | Formula |
|---|---|
| leaf | `SHA-256("mt-merkle-leaf" \|\| 0x00 \|\| serialize(record))` |
| internal node | `SHA-256("mt-merkle-node" \|\| 0x00 \|\| left \|\| right)` |
| empty leaf | `SHA-256("mt-merkle-leaf" \|\| 0x00)` |
| empty internal at level k+1 | the internal node of two empty internals at level k |

| Operation of the tree of records | Formula |
|---|---|
| leaf | `sponge("mt-record-leaf", limbs(serialize(record)))` |
| internal node | `node("mt-record-node", left \|\| right)` |
| empty leaf | `sponge("mt-record-leaf", ())` |
| empty internal at level k+1 | the internal node of two empty internals at level k |

The tree is sparse with a depth of 256; the key is 32 bytes and its bits are read from the
least significant. A bit of 0 places the value on the left, a bit of 1 on the right. The
array of empty internals for levels 0 to 256 is computed once and cached; it is 257 × 32 B.

Updating a leaf walks the 256 levels, folding the value with the sibling of each level,
taking an empty internal where the branch is absent.

**Inclusion proof:**

```
MerkleProof
  key               32 B    the index of the leaf
  leaf_length        4 B    u32, the size of leaf_value; zero proves absence
  leaf_value         ?      serialize(record), of leaf_length bytes
  sibling_bitmap    32 B    256 bits; a set bit marks a non-empty sibling at that level
  sibling_count      2 B    u16, the number of non-empty siblings
  siblings           ?      sibling_count × 32 B, ascending by level
```

**Invariants MerkleProof:**

- `key` is 32 bytes; every level from 0 to 255 is addressed by its bits, least significant first.
- `leaf_length` is zero exactly when the proof asserts absence; otherwise it equals the length of `serialize(record)` for the class of the record.
- `serialize(record)` is at least one byte for every record class. An empty record does not exist: a tree refuses to hold one, so a zero `leaf_length` denotes absence alone — and a verifier asks nothing about which case it is in, since a leaf value of no bytes folds to the empty leaf by the same formula every present leaf takes.
- `sibling_count` equals the number of set bits in `sibling_bitmap`; any other value is rejected.
- Bit L of the bitmap is bit `L & 7` of byte `L >> 3`, counted from the least significant bit of the byte.
- `siblings` are ordered by ascending level and each is 32 bytes; a level whose bit is clear takes the empty internal of that level.
- Verification recomputes the root and compares it with a root already held; a proof is never trusted for the root it carries.

### The append-only tree, indexed by position

Its depth is `note_tree_depth` wherever this construction holds state: the tree of notes and the
fabric of time share one number, and a second depth for a second use would be a second constant
buying nothing. The horizon of proving, below, borrows the walk itself at the width of its own
reach — a depth that is the binary logarithm of `proving_horizon`, a number the Decree already
carries, and no constant of its own.

Used for the note tree, for the fabric of time and for the operations of a window. Its depth is `note_tree_depth`, its leaves are filled from position
zero upward, and a leaf once written is never moved or removed. The index of a leaf is its
position, not a key: the walk reads the bits of the position from the least significant, and
every level above the written prefix takes the empty internal of that level.

```
AppendProof
  position           8 B    u64, the index of the leaf
  leaf_value        32 B    the commitment at that position
  siblings           ?      note_tree_depth × 32 B, ascending by level
```

**Invariants AppendProof:**

- `position` is below two raised to `note_tree_depth`; a proof for a higher position is refused.
- `siblings` holds exactly `note_tree_depth` entries of thirty-two bytes each — no bitmap and no count, because an append-only path has no absent levels: a level above the written prefix takes the empty internal, and both sides compute it identically.
- The walk reads the bits of `position` from the least significant; a zero bit places the value on the left, a one on the right — the same convention as the sparse tree, so no implementation carries two directions.
- `leaf_value` is the commitment itself, and what enters the fold is that commitment under the Merkle leaf domain, by the rule the introduction to these constructions states — folding the bare commitment yields a different root from the same contents, and the frozen vector of a tree of one leaf is what catches it.
- Verification recomputes the root and compares it with a root already held; the root a proof carries is never trusted.
- A leaf is written once. Two different values for one position is a defect of the writer, not a case to resolve.

### The roots of state

A proposal carries seven roots and the count of one tree, and every verifier recomputes all eight
from the state it holds once the frames of the window have applied; none of them is read off a
proposal.
Each root stands over one table of the state, under the construction and the pair of domains named
beside it, and an entry of each table is the one the last column names.

| root | construction and domains | an entry |
|---|---|---|
| `note_root` | append-only, under the note domains | the commitment of a note, at the position it entered |
| `nullifier_root` | sparse, under the Merkle domains | a nullifier the state holds spent, as its key |
| `record_root` | sparse, under the record domains | the commitment of a record, at the key that commitment is |
| `machine_root` | sparse, under the Merkle domains | the commitment standing for a machine a selection event admitted, as its key |
| `admitted_root` | append-only, under the admitted domains | the naming half of an admitted machine |
| `credited_root` | append-only, under the credited domains | the part-nullifier of a machine a window credited, appended by the proposal of the window after it |
| `operations_root` | append-only, under the Merkle domains | the identifier of a frame the window applied |

A table holding a set is a sparse tree whose every present key carries the one-byte record `0x01`:
the key is the whole of the entry, and the record stands because the construction holds no empty
one. `admitted_count` is the count of the leaves of the tree `admitted_root` stands over.

**The order of the entries of the append-only tables.** The frames of a window apply round by round,
over the decided state of the window before: the frames standing at the points of one round apply
when a machine leaves that round, in ascending order of their identifiers, and the rounds apply in
their order. A machine whose name of the window before is not the one its agreement decided replays
the decided roll over the decided state of the window two before and applies its own window's frames
again, in the order they applied, over what results — Consensus states when. A note enters the tree of notes at
the lowest free position as its frame applies. The tree of operations holds one window — it stands
empty when a window opens — and its leaves are the identifiers of the frames that window applied, in
the order they applied, so the two append-only roots that move with a frame move in one order. The
tree of admitted machines holds the naming halves ascending. The tree of credited rights moves with
no frame: the proposal of window `W + 1` appends the parts of the cement of `W`, ascending, less the
parts the challenge of `W` convicted, after every leaf an earlier proposal appended, so its leaves
stand in the order of the windows they credit and, within one window, in the order of the cement.

**What enters the two sets.** A nullifier enters the set of nullifiers when the object spending it
applies and never leaves it: the nullifiers a frame publishes in its redemption positions — of a note
or of a right to a coin, which no reader tells apart — the nullifier of an opening, and the
nullifier of a candidacy, whether or not a selection event later admits the machine it names. The
last adds no growth of a kind of its own: a candidacy spends the right its record carries, so the
candidacies the set can ever hold are at most the records the tree of records holds, which the
ceiling of openings already bounds. A rate
nullifier stands in the rate set of the horizon, which Value states is not a tree, and is no entry of
this one. A machine enters the table of machines by the commitment a selection event admits; a
machine of an opening cohort enters the tree of admitted machines by its naming half and writes no
commitment, so a network whose every machine came of an opening cohort carries the root of the empty
table of machines.

**Invariants of the roots of state:**

- Every root and the count a proposal carries are recomputed by the verifier from the state it holds; a proposal whose roots or count differ from the recomputed ones is refused.
- Each table folds under the construction and the pair of domains of its row and under no other; one content under two constructions is two roots.
- The tree of operations holds the frames of one window in the order they applied, and it stands empty at the opening of every window.
- A frame applies once, when a machine leaves the round whose points carry it, among the frames of that round in ascending order of identifier, over the decided state of the window before; a machine replaying a decided roll applies its frames in the order of the roll, which is the order they applied.

### The horizon of proving

A redemption proves membership under a note root; which root, the proof hides. The roots it
may hide among are taken by **strides**: stride `E` is the aligned run of `proving_horizon`
consecutive windows beginning at window `E × proving_horizon`, and its fold carries at leaf `i`
the canonical note root of window `E × proving_horizon + i` — ascending, the stride's first
window at leaf zero. The horizon of proving of window `W` is the fold of the stride standing
for `W`, the newest stride whose every root `W` canonically holds:

```
standing_stride(W) = (W − proving_lag + 1) / proving_horizon − 1
                     # unsigned, the division toward zero; defined from the first window
                     # it is non-negative at, and before that the horizon is the fold of
                     # the empty reach, nothing stands under it, and a window carries
                     # frames of filler alone
```

The last root of stride `E` is the root of window `(E + 1) × proving_horizon − 1`, held by
everyone from `proving_lag` windows after it — which is what the arithmetic above waits for —
and the stride then stands for exactly `proving_horizon` windows before the horizon moves to
the next. The walk is the append-only walk above at the width of the reach, under doors of its
own:

| Part | Derivation |
|---|---|
| leaf | `sponge("mt-horizon-leaf", cells(note_root))` |
| internal node | `node("mt-horizon-node", left \|\| right)` |
| empty leaf | `sponge("mt-horizon-leaf", ())` |

Every machine folds a stride once, when its last root cements, and the value a frame's proof
takes as its public input is the root of that fold — one value for every frame of every window
of the standing period, whatever leaf any proof stands under. A public input enters the
transcript of a proof, so a value that moved with the window would pin every proof to one
window of landing and hand the reach to fast devices alone; a value that stands for a stride
is what makes the reach real, and it sorts nobody because it is everybody's. The paths of the
horizon are read by circuits alone, which is what places its doors in the proof hash family;
the fold itself is carried by every verifier, and carriage is not judgement.

**Invariants of the horizon:**

- Leaf `i` of stride `E` is the canonical note root of window `E × proving_horizon + i`, ascending; an implementation ordering a stride newest-first computes a different root and parts with the chain at its first frame.
- The stride standing for window `W` is the one the integer form above names, and it stands for exactly `proving_horizon` windows; a frame is verified against the standing stride of the window it applies in and against nothing fresher.
- A closed stride fills every leaf, so the empty leaf enters no standing fold; it is the padding of the fold below the reach, which the frozen vector exercises and a chain never stands on.
- The reach is `proving_horizon` leaves and the depth is its binary logarithm; no constant of its own exists.
- The doors are the horizon's own: a horizon folded under the doors of the note tree is a different value, and the frozen vector catches it.
- The root is recomputed from roots already held and never taken from anyone; a frame carries none.

## Derivations of the frozen quantities

A number here is not chosen; it follows from a target stated before it. Each derivation below
names the target, the reasoning, what moves if the target moves, and the answer to the obvious
objection.

### `proving_lag` = 2 windows

**Target.** Every payer of a window must anchor on a root that every verifier already holds,
without waiting and without asking.

**Derivation.** A window's root is settled once that window is cemented, and a window is
cemented by confirmations that arrive during the next one. A root is therefore canonically held
by everyone from two windows after the one that produced it — the same lookback the draw uses,
and for the same reason. One window is not enough: the root of the previous window is still
being cemented while this window runs, so half the network would anchor on a value the other
half has not settled.

**Sensitivity.** At three the anchor grows staler by a window and nothing else changes; at one
the network splits into those who saw the cementing and those who did not. The floor is a
safety boundary, not a preference.

**Defence.** Why not the freshest root available to each payer — because that is precisely the
free choice the fixed anchor exists to remove: it would sort payers by how recently they
synchronized. The reach a payer may stand in without an observable choice is the horizon of
proving, derived next: the lag is the cementing margin the horizon waits after a stride
closes, the stride is how far the reach extends, and the choice within it lives inside a
proof of one length.

### `proving_horizon` = 128 windows

**Target.** A frame must stay provable for as long as the slowest device this protocol claims
needs to prove it, and nothing observable may sort payers by the speed of what they hold.

**Derivation.** Three inputs of a frame's proof are bound to a window — the root its
redemptions stand under, the window its rate nullifiers take, and the computed moment a right
is extinguished at — and every one of them is a public input of the proof or ranged against
one. A public input enters the transcript at the first permutation of proving, so an input
that moves with the window re-pins the proof to one window of landing: a margin of zero for
anything slower than a window, whatever reach the roots alone were given. The reach must
therefore be a standing of the public inputs and not a width of them: the horizon is taken by
aligned strides of `proving_horizon` windows, the fold of a stride stands for a whole stride
of landings, and all three bindings range over the standing stride, with the choice inside the
proof — a prover fixes its public inputs the window the stride stands and holds them for
`proving_horizon` windows of landing.

The width stands between two walls. Below, the reach must cover a prover a hundred times
slower than the window it lands in, so that who can pay is bounded by patience rather than by
hardware. Above, the burst the reach admits must leave the flood bound standing: one secret
holds `spends_per_window` rate positions per window of the standing stride,
`4 × proving_horizon = 512` spends against the `frames_per_window × spends_per_frame =
819` a window carries — five eighths of one window at most, once per stride, the budget
renewing only when the horizon moves — so one secret still fills no window, and the average
over any stride stays four per window. One hundred and twenty-eight is the largest power of
two under that wall, and a power of two because the fold of the reach is then a full binary
tree of seven levels with no absent ones.

**What a prover holds, and the one case that is not the whole stride.** The budget of a proof
is what remains of the standing period it began in, so a prover that begins at a boundary holds
the whole reach and one that begins later holds what is left. Nothing is lost by the
difference: the standing periods are contiguous — the fold of the next stride stands the window
after the last one's period ends — so a prover too slow for what remains proves against the
next fold instead, and holds the whole reach again. What that costs is a wait of at most one
reach before proving begins, and the wait is invisible: a frame carries no root, its landing
window sets which fold it verifies under, and two frames landing in one window are identical in
every byte whatever period their proving began in.

**The honest price, stated with its number.** A note is spendable when the stride holding the
root of its window stands: no earlier than `proving_lag` windows after its window and no later
than `proving_horizon + proving_lag − 1` after it, where a fold sliding every window would
have promised `proving_lag` always — and delivered it only to a device that proves within one
window, which is the sorting the target refuses. Receipt is untouched — a payment settles when
it stands — and what waits is only the spending onward of what was just received. The price
buys the reach its reality, and it buys it for everyone alike.

**Sensitivity.** At sixteen, a device sixteen times slower than a window stands outside
payment; at two hundred and fifty-six, `4 × 256 = 1 024` exceeds the spends a window carries
and one secret fills a window alone — the flood bound breaks.

**Defence.** Why a standing fold and not the freshest fold beside it — because a second lane
of fresher public inputs would verify under a different public vector, and which vector a
frame verified under is read by every verifier: the slow would stand in a class of their own,
which is the sorting the target refuses. Why one reach for three bindings — three reaches
would be three numbers to derive and three observables to argue away, and the tightest of them
would remain the wall the other two widenings fail to remove. Why the hidden choice does not
reopen what the fixed root's defence closed — that defence refuses an observable choice, which
sorts payers by how recently they synchronized; a choice inside a proof of one length sorts
nobody. Why not reuse `retained_windows` or `claim_spread` — one number carries one meaning.

### `spends_per_window` = 4

**Target.** One payment secret must not be able to fill a window, and ordinary use must never
meet the bound.

**Derivation.** A window admits `frames_per_window × spends_per_frame` transfers. At four per
secret, filling a window takes more than two hundred distinct secrets, each of which costs the
lived time a record costs — so flooding is bounded by the same scarcity everything else is.
What the horizon of proving admits on top is a burst and never a rate: one secret may derive
its four positions for every window of the standing stride and land them together — five
eighths of one window, once — after which its budget is drained until the horizon moves, and
the average over any stride stays at four per window. Filling every window still takes the two hundred distinct
secrets it took, and the ceiling the burst sets is where the derivation of `proving_horizon`
takes its upper wall.
Four covers ordinary use within one window: a payment, a correction of it, and two more beside
them. The index fits in two bits, so nothing about the bound leaks through the width of a
field.

**Sensitivity.** At two the bound starts refusing honest bursts; at eight the flood cost halves
while the honest gain is nil, because a person does not make eight payments in a minute.

**Defence.** Why bound at all — because without it one secret with one lived record could take
every transfer slot of every window, and the scarcity that guards records would guard nothing.

### `claim_spread` = 1 440 windows

**Target.** The moment a coin is taken must say nothing about who took it, and a machine must
not wait unreasonably to be paid.

**Derivation.** The spread is one continuity segment — the same unit lived time is measured in.
Over that span the claims of all living machines overlap thoroughly, so the moment carries no
signal; and no machine waits more than one segment for a coin it has already earned. Reusing
the segment introduces no new period into the protocol, which is the whole point of choosing it
over a number of its own.

**Sensitivity.** At a quarter of it the overlap thins and a machine that claims early stands
out among fewer; at four times it the mixing improves not at all while the wait quadruples.

**Defence.** Why not spread it over the adaptation period — because the wait would grow by an
order for a mixing that is already complete at one segment.

### `continuity_required_num` over `continuity_required_den` = 2 over 3

**Target.** A person carrying a telephone must clear the gate without noticing it, and a farm of
empty seeds woken by a timer must not.

**Derivation.** The threshold is a share of the segments of the period, not a run of them: a run
of every segment fails a person who flies, sleeps through a day or loses a signal, and failing
them is failing the gate's purpose. Two thirds of fourteen segments is ten days of life out of a
fortnight, which a person who uses their device at all reaches without effort. It is also what
makes a timer expensive: the cheapest automation that clears a share must run on two days out of
every three, so a farm pays two thirds of the attention a person pays, per seed, for the whole
period, and the saving that made farming worth doing is gone.

**Sensitivity.** At one third the farm wakes once in three days and clears the gate for the price
of a cron entry; at one the gate refuses everyone who travels.

**Defence.** Why a share rather than a run with an allowance for gaps — because two numbers where
one suffices is two things to derive, to freeze and to defend, and the share alone already prices
the timer out. Why not raise it with the pressure of applicants — because the count of segments
already rises with pressure, and the share applies to whatever count is in force.

### `max_openings_per_window` = 256

**Target.** The set of records grows no faster than the network can absorb, while a billion
people can join within a decade.

**Derivation.** A decade holds on the order of five million windows. Two hundred and fifty-six
openings per window admits above a billion records over that span — a margin of a fraction and
not of an order, stated as it stands rather than rounded upward — and the value is a power of
two, so the bound costs nothing to encode. Growth is therefore bounded by structure rather than
by anyone's judgement of demand.

**Sensitivity.** At sixty-four a billion takes four decades; at a thousand the bound stops
being a bound on anything a state can absorb.

**Defence.** Why a bound when opening already spends a one-time right — because the right bounds
one seed and not the count of seeds, and a bound by structure rests on nothing about the claimants.

### `name_reveal_windows` = 2 τ₂

**Target.** A reveal must survive an ordinary outage of the person who committed, and a slot
must not be held by a commitment that never reveals.

**Derivation.** Two periods of adaptation are four weeks of windows. A person who commits and
then loses a device has one full period to replace it and a second to act, which covers an
outage of a fortnight without special handling; and a slot blocked by a silent commitment
returns within a month, so squatting by commitment alone costs a month and yields nothing.

**Sensitivity.** At one period an ordinary two-week outage loses the slot; at eight, a name may
be blocked for a third of a year by a commitment that was never meant.

**Defence.** Why not release the slot the moment a competing reveal appears — because that
lets an observer probe which slots are committed, and probing is the beginning of a directory.

### `name_renew_windows` = 6 τ₂

**Target.** A name must return to the free space soon after its holder stops living with it,
and must never be lost by a person who simply travelled.

**Derivation.** Six periods of adaptation are twelve weeks: a quarter of a year. A holder acts
four times a year, which no living use notices, and an abandoned name returns within a season
rather than being held forever by a device that has stopped. The moment is computed rather than
chosen, so the four acts of a year say nothing about presence or timezone.

**Sensitivity.** At one period a person who travels for a season loses their name; at twenty-four
an abandoned name is held for two years and the free space stops being free.

**Defence.** Why not release by inactivity of the record instead — because that would make the
name an edge to its holder's actions, which is exactly what a name may not become.

### `name_chain_length` = 128

**Target.** A taking must last longer than anyone's use of one name, and it must still end, so
that no slot is held for ever by a chain nobody is behind.

**Derivation.** Each link buys one renewal period. A hundred and twenty-eight links at twelve
weeks each are ten thousand seven hundred and fifty-two days: a little over twenty-nine years.
That exceeds a working lifetime of one name, so no living holder meets the end of their chain;
and the end exists, so a name whose holder is gone returns after three decades even if the
renewals continue by machinery. The value is a power of two, so the chain costs one shift to
index and nothing to encode.

**Sensitivity.** At thirty-two a holder reaches the end in seven years and must retake a name
they never lost; at a thousand and twenty-four the end is beyond any horizon and the guarantee
of return becomes a fiction.

**Defence.** Why an ending chain rather than an unbounded one — because an unbounded chain
requires a signature to extend, a signature names a key, and a key names a person. The bound is
the price of renewing without being named, and it is paid once every three decades.

### `name_min_length` over `name_max_length` = 4 over 32

**Target.** A name must be a thing a person can say, and a slot must cost one hash whatever the
name.

**Derivation.** The alphabet is thirty-eight characters — the twenty-six letters, the ten digits,
the underscore and the hyphen — and a name begins with a letter. Four characters give more than a
million names, enough that first-come is not a race decided in the opening windows; below four the
whole space is exhausted by one holder in a day. Thirty-two
characters and a domain separator fit inside a single compression block of the hash, so slotting
any lawful name costs exactly one compression and the cost does not depend on the name.

**Sensitivity.** At a minimum of three the space falls to some thirty-seven thousand and is taken
in an afternoon; at a maximum of sixty-four a name spans two blocks and the cost of slotting stops
being uniform.

**Defence.** Why not allow the full range of human script — because a name that renders
differently in two implementations resolves to two slots, and one name resolving to two slots
is a fork of the only namespace the protocol has.

### `redundancy_num` over `redundancy_den` = 1 over 4

**Target.** A delivery survives the loss the late-cell rule creates, without a repeat — because
a repeat is the pattern an active observer is trying to induce.

**Derivation.** A quarter of the cells of a delivery may be lost and the whole still
reconstructs. That covers the ordinary loss of a path together with the cells the late rule
extinguishes, and it costs a third more carriage — which the network already pays for, since
carriage is the work it buys.

**Sensitivity.** At one in eight a modest delay pattern starts costing deliveries; at one in
two the cost of carriage doubles for a robustness nobody needs.

**Defence.** Why not ask again — because asking again is a repeat, and a repeat is exactly the
fingerprint this whole layer removes.

### `cell_bytes` = 1 232

**Target.** One cell of one size reaches any device on any path without fragmentation, and a
fragment would be a marker of size that the wire exists to remove.

**Derivation.** The minimum link maximum transmission unit every IPv6 path must carry is 1 280 B
(RFC 8200). A datagram of that size holds a fixed IPv6 header of 40 B and a UDP header of 8 B,
leaving 1 232 B. A cell is exactly that: no path in the world of IPv6 fragments it, and no
implementation needs a discovery of path size, which would itself be a probe with a pattern.

**Sensitivity.** At 1 500 B — the Ethernet frame — cells fragment on every tunnelled path and the
fragments say how large the whole was. At 512 B the overhead of the two seals rises from a
seventh to a third of every cell for no gain in reachability.

**Defence.** Why not negotiate a size per path — because a negotiation is a probe, its outcome
varies per neighbour, and a cell whose size depends on where it goes is a marker of where it goes.
Why not the IPv4 minimum of 576 B — because Montana carries IPv6 at every rung and the smaller
floor buys nothing but overhead.

### `path_max` = 15

**Target.** A delivery carries room for the seals of its whole path in a field of one size, so
that no observer and no hop learns how far a cell has come.

**Derivation.** The array holds `path_max` slots of 16 B, filled at the origin with values drawn
from the same source as any secret and overwritten by each hop at the slot its **own seal**
selects. The count of steps is therefore not carried at all: the array is full from the first
step, and a used slot is indistinguishable from an unused one. Fifteen is five times `hop_min`,
so a path may exceed its floor fivefold before slots collide, and a collision costs the sender's
own check nothing — that check runs over the sender's own first steps, which are machines of the
active set it knows directly.

**What the array bounds, and what it does not.** A delivery steps by rings of distance, halving
what remains at every step, so it reaches a population of `2^(path_max − hop_min)` — today four
thousand and ninety-six — and a population past that is reached in more steps than the array holds
seals for. That is a bound on the **reach of one cell**, and it is a row of the forms: a boundary
between eras widens it, and the price is written rather than discovered — each added slot doubles
the reach and takes sixteen bytes from the chunk a cell carries. Eight more slots reach a million
machines for a hundred and twenty-eight bytes of the chunk; eighteen more reach a billion for two
hundred and eighty-eight.

**There is no ceiling on the count of machines anywhere in this set, and none may be added.** A
node is any device reachable from outside — a telephone, a tablet, a desktop, a server, a set-top
box — and what limits how many of them stand is what a device carries, which is checked on the wire
and moves at a boundary, never a row of the block a chain opens on. A number frozen there would
make the machine past it not slow but unlawful, and a network whose growth is unlawful is not the
one this document describes. What the fold already says of the count of machines stands: the
population enters the depth logarithmically and the per-machine work not at all.

**Sensitivity.** At three the array equals the floor and the first collision falls inside the
guaranteed part of the path; at sixty-three the routing header takes more than four fifths of a
cell and the chunk it carries falls to under an eighth of what it was.

**Defence.** Why not a growing list — because its length is the count of steps, and a count of
steps tells a hop how far a cell has come, which the label rule forbids by name.

### `erasure_group` = 16

**Target.** A delivery survives the loss the frozen redundancy admits, and it survives it without
a repeat.

**Derivation.** A group holds `erasure_group` cells of which `redundancy_num` over
`redundancy_den` — a quarter, four of sixteen — are parity, so `erasure_data` = 12 cells carry the
body and any 12 of the 16 reconstruct it. The carriage cost is a third more than the body, which
is what the redundancy derivation already fixes. Sixteen is the smallest group at which a quarter
is a whole number of cells and the coding matrix stays inside one byte-wide field.

**Sensitivity.** At eight the same quarter is two cells and a burst of three defeats a group; at
sixty-four the coding matrix leaves the byte-wide field and the reconstruction of one group costs
sixteen times the arithmetic for the same fraction of loss.

**Defence.** Why not ask again for a lost cell — because asking again is a repeat, and a repeat is
the fingerprint the whole layer removes.

### `target_rounds` = 284

**Target.** A window closes on coverage: the cement must be expected to reach the quorum share
of the electorate's count, and the count of rounds that buys it must follow from frozen numbers
alone.

**Derivation.** Where the admitted stand above `round_floor × committee_divisor × k`, the crowd of a
round is the admitted through the divisor and the chains, so eligibility is an expected share of one
in `committee_divisor` per machine per round of a chain, drawn independently, and after `R` such
draws the expected uncovered share of the electorate is `(255/256)^R`, since every machine counts
alike and expectation is linear. The least `R` at which it falls to the complement of the quorum —
thirty-three hundredths — is 284: in integers, `100 · 255²⁸⁴ ≤ 33 · 256²⁸⁴` while 283 fails the same
comparison; in decimals, `(255/256)²⁸⁴ = 0.329049 ≤ 33/100 < 0.330340 = (255/256)²⁸³`. With several
chains a machine's draws spread across them and accumulate toward one cement, and the crowd is per
chain and per round, so each chain's window takes the target on expectation: the count is per chain,
and the strikes of a machine per window stay one family of numbers whatever the count of chains.

**Below that count of admitted machines the crowd is the floor and the count is smaller**, since the
count of rounds and the crowd move together: a window takes `1.109 × admitted / (k × crowd)` rounds
on expectation, which is 284 exactly where the crowd is the admitted through the divisor and fewer
everywhere below. A young network therefore passes its windows in fewer rounds, which is the same
network passing them quickly in lived time while its geography is one room.

**The tail, bounded without a distribution.** A window still open at `n` rounds has uncovered
share above `33/100`, and the expected uncovered share is `(1 − crowd/admitted)ⁿ`, so by Markov's
inequality `P(L > n) ≤ (100/33) · (1 − crowd/admitted)ⁿ` — for any number of machines, every one
of them counting alike. Where the crowd is
the admitted through the divisor that base is `255/256`, and the frozen points of the bound are: at
twice the target, 0.3281; at three times, 0.1080; at five times, 0.0117; at ten times, 4.51 · 10⁻⁵.
Below that the base is smaller and the tail falls faster, so the bound above stands at every
population — at a population of one the crowd is that one machine, the base is nought, and the
window closes in the round in which it answers.

**The averaging lemma.** Every constant of the Decree denominated in windows spans at least
`selection_interval` windows, so its lived duration is a sum of at least that many independent
window lengths, and the relative deviation of the sum is at most `1/√X` of the worst
single-window spread — 5.5 % at 336 windows, 2.6 % at one segment of continuity, 0.7 % at τ₂ —
around a mean the crowd rule fixes rather than walks to. No window-denominated constant is sensitive
at these magnitudes: the continuity gate demands a share of segments, not their exact lived
length; the name and membership periods are safety margins of whole multiples of τ₂;
`claim_spread` spreads within one period.

**Sensitivity.** The target moves only with the two numbers it stands on: at a quorum of two
thirds exactly the least count is 281, and at a committee divisor of 128 it is 142. Either
change moves the expected count of rounds and nothing else — the close is on the cement
itself, and the count is what the crowd rule yields rather than a bar anything is driven to.

**Defence.** Why not fix the length of a window in rounds — because a fixed count either
overshoots coverage and wastes rounds or undershoots and never closes; the close is on
coverage, and the derived count is a target for the threshold, never a terminator.

### `round_floor` = 50

**Target.** No round of a chain is ever empty. A round advances on an attestation and on nothing
else, so a round no machine is drawn for is not a slow round but a chain that stands — and without a
clock nothing tells that apart from an answer still in flight, so no observation of it exists to
repair it. The crowd of a round therefore carries a floor, and the floor holds at every population
the set admits, down to the one machine a cold start begins with.

**Derivation.** The machines drawn for a round are the living through the share of the round, so the
chance a round finds nobody is `(1 - share)^living` and a window of `target_rounds` rounds meets one
unless that chance stands below the bound this set holds everything else to. A window closes only
where the count of machines that answered reaches the quorum, so at the boundary of a close the living stand
at `confirmation_quorum_num` over `confirmation_quorum_den` of the admitted, and the crowd over the
living is that share of the crowd over the admitted:

```
target_rounds x e^(-floor x 67 / 100)  <=  2^-40
floor x 67 / 100                       >=  40 ln 2 + ln 284 = 27.726 + 5.649 = 33.375
floor                                  >=  49.81
```

and the least integer of it is 50. At forty-nine the chance is 1.58 x 10^-12, above the bound; at
fifty it is 7.88 x 10^-13, below it.

**Sensitivity.** The floor moves with the logarithm of what it guards and not with the population: a
bound of 2^-80 asks 91, and a window of twice the rounds asks 51. Nothing else of the Decree moves
with it — the strikes of a machine per window stay 1.1094 whatever the crowd, since the count of
rounds and the crowd move together.

**Defence.** Why a floor rather than a wider share everywhere — a share wide enough for three
machines is a crowd of a third of the network at a million, and the volume of a round is its crowd.
Why not adapt it to the living — the count of the living is closed and computed inside a window's
proof, so no observable of it exists to adapt against, while the count of the admitted is one the
tree already carries in the open. Why the quorum share of the admitted and not all of them — a
window where fewer than the quorum stand does not close at all, so the crowd that matters is the one
present at the boundary where a close is possible.

### The threshold of a round

The threshold of a round is not walked to by observation. It is read out of the state every window
already holds, so that a chain of one machine and a chain of a million each draw a crowd that
answers:

```
width              = 2^(8 x hash_bytes) - 1
crowd(admitted, k) = min(admitted, max(round_floor, admitted / (committee_divisor x k)))
round_threshold    = max(1, width x crowd(admitted, k) / admitted)
                                                  # unsigned, multiplication first, toward zero
```

`admitted` is the count of machines the tree of admitted machines carries at the window being
opened, which every machine recomputes from the roots a proposal carries, and `k` the count of
chains the schedule holds in force at that height. The crowd is per chain and per round, exactly as
the strikes of a machine are spread across the chains, so a step of the schedule moves the crowd
through this rule and never past it. Where the admitted are
none the threshold is the width: there is nobody to draw, and a chain that opened on an empty tree
draws whoever admits itself.

**Why this and not a retarget.** A retarget corrects what it can observe, and its observable must be
canonical or two machines walk two thresholds and the chain parts with them. The quantity that
would correct a round is the crowd, which is the count of the living — a number this set publishes
only at the close of a window, as the count of its cement, and never while a round runs. Aimed
instead at the count of rounds, a retarget walks the threshold toward
a share whose crowd falls below one machine at every small population, and there it stops: no
attestation, no cement, no close, and no observation of any of it. The count of the admitted is the
one measure of scale that stands in the open, and read directly it needs no adaptation at all.

**Vectors of the threshold of a round** (`hash_bytes` 32, `round_floor` 50, `committee_divisor` 256):

```
round_threshold(admitted 1,         k 1) = ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
round_threshold(admitted 3,         k 1) = ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
round_threshold(admitted 50,        k 1) = ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
round_threshold(admitted 100,       k 1) = 7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
round_threshold(admitted 12 800,    k 1) = 00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
round_threshold(admitted 1 000 000, k 1) = 00fffbce4217d2849cb252ce032db1e9f2778140dd3fe1975f2cb641700cd855
round_threshold(admitted 1 000 000, k 4) = 003ff69014b599aa60913a4f8726d04e618ce2d1f1cfbb9496249a133c1ce6c0
```

**The implementation these reject is named:** one that divides without the floor. It agrees with
every value at and above `round_floor × committee_divisor × k` admitted machines — the fifth line is
exactly that boundary and the two answers are identical there — and at three machines and at a
hundred its crowd is nought, so the whole width collapses to the floor of one — a threshold under
which a value clears once in `2^256`, which is a chain no machine is ever eligible for and therefore
a chain that never moves again. The first four lines are what separate the two, and they are the reason a
vector of this rule may not stand on a large population alone.

**Invariants of the threshold of a round:**

- It is a function of `admitted`, `round_floor` and `committee_divisor` alone; no observation, no count of rounds and no history enters it.
- The crowd never exceeds the admitted and never falls below `round_floor` unless the admitted do; the floor of the crowd is applied before the division, and the floor of one after it, by name and last — a threshold of nought is a chain whose rounds no machine is ever eligible for.
- Where the admitted are none the threshold is the width; a chain that opened on an empty tree draws whoever admits itself.
- Above `round_floor x committee_divisor x k` admitted machines the crowd is the admitted through the divisor and the chains, and a window of every chain takes `target_rounds` rounds on expectation; below it the crowd is the floor and a window takes fewer, which is the young network passing its windows quickly while its geography is one room.
- The strikes of a machine per window do not move with the crowd: the count of rounds and the crowd move together, and their product is the constant the volume of the Decree is checked against.

### `retained_windows` = 8

**Target.** A device that fell behind walks back to the head by verifying the certificates of the
windows it missed, and the material those certificates are made of must stand somewhere for it to
collect — while retention that grew without bound would be the slow bloat the lifecycle invariant
refuses.

**Derivation.** The certificate of a window is its heavy attestations, the light attestations
answering its final beacon and the pledges its decision stands on, which already stand at their
points; retaining them costs what the window cost — one attestation per attesting machine, of the
length Canon fixes for a confirmation, its pledges, each of nearly that length since each carries a
proof of the presence's length, and the light attestations of one round, each under a sixtieth of
one — for as many windows as the bound names, and the frames and the rolls the
same bound keeps for a machine replaying a decided window cost what the window carried. One
binary order over the open window's own load keeps every device that carries a window in the storage
class it already stands in, and it is three doublings above the one or two windows an ordinary
restart or a brief partition leaves a device behind by. A device behind by more than the bound finds
no certificate to walk and takes a fresh anchor from its operator; Consensus states that this is a
change of trust and not a verification.

**Sensitivity.** At two, a restart that spans a slow window already costs a fresh anchor; at
sixty-four, a device's retention leaves its storage class. Neither direction moves any other
quantity: the bound gates retention and the walk of a joining device and enters no proof, no draw
and no root.

**Defence.** Why a bound at all — because without one every machine would hold every attestation of
every window for ever, which is unbounded growth of what a machine keeps about the network. Why not a
clock — a clock is what this protocol admits nowhere; the bound is read from held state, exactly as
the close is. Why not reuse the proving lag of frames — that constant names where a frame proves, and
one number carries one meaning.

### `finality_rule` = 1

**Target.** A network identifier distinguishes fixed-parent finality from the retired rule
that lowered the quorum after a count of rounds and then accepted a self-selected restart.

**Derivation.** The value identifies the fixed-parent rule of Consensus, "The way back".
It is an enumeration, not a security parameter. It replaces the retired recovery-onset
parameter at the same position in the Genesis encoding; the changed value changes the
parameter digest and Genesis State Hash. Only this value is supported by this set.

**Sensitivity.** There is no numeric tuning. An unknown value is an unsupported rule and
is refused before accepting a proposal, a checkpoint or a proof.

**Defence.** Changing a rule while keeping its network identifier would let implementations
disagree about which chain is final. Changing Genesis separates the protocols before any
transition. It does not revalidate proofs or balances produced under the retired rules.

### `standing_censuses` = 10

**Target.** The standing of a machine is its presence at census windows spread evenly over one
period of adaptation, and a ballot proves every census of a standing in one proof of the frame's
height, so the count is the most that height carries among the counts that divide the period.

**Derivation.** A ballot spends per census one permutation for the part of that census, one for the
leaf of its cement, `note_tree_depth` for the walk of the cement and two for the coin — forty-four
blocks of `rows_per_permutation` rows — and beside them one block for the part of its own window
and the idle block every chain opens after; the comparisons stand in rows those blocks leave free,
in columns of their own. At the frame's height of 2^16 rows, less the free block, `n` censuses fit
while `2 + 44 n` blocks stand within 511: they do to eleven and not at twelve. τ₂ = 20 160 is
divided by ten and not by eleven, so the count is ten and `census_interval` is τ₂ / 10 = 2 016.

**Sensitivity.** At nine the interval is 2 240 windows and a ballot fills 398 blocks; at eleven no
interval divides the period. What moves with it is the interval, the length of the census a
proposal carries — forty bytes a census — and the floor of the committee, which is this count
times `standing_committee`; nothing of the count half of the close moves.

**Defence.** Why census windows rather than every window — a unit for every window of a period would
be a walk for every window, twenty thousand of them in one proof. Why the period of adaptation — it
is the span the gate of continuity already prices a person by, and a fleet admitted together holds
no standing until it has stood there for as long. Why presence and not the age of an admission —
the window a machine was admitted in is deliberately observable, so a weight read from it is a
weight anybody computes from the tree of admitted machines; a unit earned at a census window is
known to its machine alone, because the part it rests on names nobody.

### `standing_committee` = 6 499

**Target.** The half of the close that counts votes passes, but for 2^-40 — the bound this set
holds everything else to — whenever machines holding three quarters of the standing answer, at the
one share the Decree names for the quorum.

**Derivation.** Above the floor of the committee a unit of standing votes in a window with
probability `standing_committee / S`, independently of every other unit, since its coin is a hash
of its own spending half, its census window and a cemented aggregate. Machines holding a share `h`
of the standing cast votes whose expectation is `μ = h × τ`, and the close asks
`votes × 100 ≥ 67 × τ`; a failure is a sum of independent indicators falling to `(1 − δ) μ` with
`δ = 1 − 67 / (100 h)`, which the lower Chernoff bound holds to `exp(−δ² μ / 2)`. At `h` of three
quarters `δ` is 8 / 75:

```
exp(−(8/75)² × (3/4) × τ / 2) ≤ 2^-40    ⇔    τ × 8 / 1875 ≥ 40 ln 2 = 27.7259
least τ: 6 499 × 8 / 1875 = 27.7291 meets it; 6 498 × 8 / 1875 = 27.7248 does not
```

The Poisson tail the bound covers from above stands at 2^-45.7 at that committee.

**Sensitivity.** Four fifths of the standing answering asks 2 625 of the bound, seventy-two
hundredths asks 15 971 and seventy hundredths 43 130: the committee grows as the inverse square
of the margin over the quorum. The floor at which the committee begins, `standing_censuses ×
standing_committee` units, moves with it.

**Defence.** Why a committee rather than every unit — a vote of every unit publishes every standing
exactly, while a sample hides the weight it is drawn from wherever the sample is smaller than the
population; the floor is where a full standing expects one vote. Why the vote half beside the count
half rather than in its place — the count half keeps finality deterministic and accountable
(Consensus, "The way back"), and the vote half can only refuse a close the count admits, so a tail of
the vote half is a tail of liveness and never of safety. Why three quarters — the count half asks
two thirds of the machines; a vote half asking that share of a sample needs a margin above it for the
sample to land, and a quarter of the standing absent is the margin a committee of this size holds.

### `k_max` = 8

**Target.** The consensus-and-payment stream of a window stays inside the commodity envelope
[I-5] fixes, at any population the profile is calibrated for.

**Derivation.** The chains of a window cost `k` × 110.6 MB of frames — `frames_per_window`
frames of `frame_len` bytes each — while the volume of attestations and pledges stays flat in `k` at
≈ 458 KB per machine in a window decided in attempt zero ("The volume the schedule is checked
against"), so the volume of such a window is `k · 110.6 MB + N · 458 KB` and the share of it one machine
carries is that total over the population it is carried by. What the envelope is checked against
is that share and never the total: the frames of a window are divided among whoever carries them,
so the share falls as the population grows, and eight chains keep one machine's share inside the
commodity envelope [I-5] fixes at every population this document admits — which is every
population, since none is capped. A ninth leaves it at the population the profile is calibrated
for.

**Sensitivity.** The share formula is the frozen check: the envelope is readable at any
population, and every step of the schedule is checkable against it forever. What the check does
**not** do is bound the count of machines — it bounds the count of chains, which is what this row
is.

**Defence.** Why a cap at all — because a schedule without a ceiling would walk the stream
past the envelope and off the commodity boundary, which [I-5] forbids.

### `k_step` = 96 τ₂

**Target.** Capacity grows with age at a pace a founder chooses, with the trade stated.

**Derivation.** A chain is added when the chains in force are full and not when a height is
reached, and fullness is an observable of the cemented past like every other this set recomputes
against: the share of canonical slots a window carried, summed over the period and over the chains,
read from proposals every machine already holds. The rule takes the shape of the recomputation of a
walked threshold — integer, damped, bounded by one step — and adds a chain when the occupancy of the period
exceeds the share the envelope admits, to the cap `k_max`. Ninety-six periods of adaptation stands
as the floor of the cadence, so that a burst cannot walk the schedule up in a week.

**Sensitivity.** A lower share of occupancy adds chains sooner and spends the envelope earlier; a
higher one leaves capacity unused while senders wait for slots.

**Defence.** Why not leave it sovereign — because the set already recomputes against a public
observable, and a second instance of accepted machinery costs less than the one number in the Decree
that nothing derives. Why not let a runner add a chain — because that is discretion over
future capacity, which the control-plane rule forbids; the observable is the cement, which no
runner chooses.

### The profile of a deferred delay: uniform over the window

**Target.** The moment a letter leaves a holder must carry nothing of the moment it arrived,
and must not outlive the tag it belongs to.

**Derivation.** A delay drawn uniformly over the residues of its chain not yet reached maximizes the
uncertainty of the leaving moment for a bound that is already fixed by the tag's life. Any
shaped profile concentrates probability somewhere, and a concentration is a signal. The uniform
choice also needs no parameter, so there is nothing to configure and nothing to diverge on.

**Sensitivity.** Any other shape trades entropy for nothing; a bound beyond the window loses
the tag.

**Defence.** Why not an exponential profile as mixing networks use — because their bound is time
and ours is a window, and inside a fixed bound the uniform draw is the one that says least.

### The integer form of a tag

```
tag(shared_secret, W)        = SHA-256("mt-tag"  || 0x00 || shared_secret || W_8B_LE)[0 .. 16]
step_label(handshake_secret, W) = SHA-256("mt-step" || 0x00 || handshake_secret || W_8B_LE)[0 .. 16]
```

`W` is the height of the last cemented window as an unsigned eight-byte little-endian integer,
and both results are the first sixteen bytes of the digest.

**The secret a tag stands on walks with the window.** What the two correspondents establish is the
secret of the window their first letter travels under, and every later window has a secret of its
own, one step further down a one-way walk:

```
pipe_secret(W0)     = shared_secret, W0 being the window of the tag the first letter travels under
pipe_secret(W + 1)  = SHA-256("mt-pipe-ratchet" || 0x00 || pipe_secret(W))
```

Every quantity a pipe derives for a window takes `pipe_secret(W)` and never the value the first
letter established: the tag above, the right to collect and the key of the inner seal below. A
device holds the secret of the earliest window at which it still accepts a cell of that pipe and
erases every earlier value, so what a device holds at a window reaches every window after it and
none before it: whoever takes the device, or a copy of its storage, opens nothing that was sealed
before the window they took it at. The walk is one way by the primitive and costs one hash per
window, so a device returning after an absence walks to the present rather than asking anybody. A
publication of a channel and an object of consensus stand on no secret and walk nothing — their
point is public by construction — and the walk belongs to the letter alone.

**Invariants of the walk:**

- The walk begins at the window of the first letter's tag and advances exactly one step per window; an implementation that holds the established secret unchanged, or steps it by the height of the window rather than by one, derives tags the other side never computes, and the frozen vectors name both mistakes.
- A device erases every value of the walk earlier than the earliest window it still accepts a cell at; a value kept past that window is a defect.
- A value of the walk is held and never published, exactly as the established secret is; nothing of the walk crosses the wire, and a hop computes none of it.

The two take the same shape and different domains because they answer different questions. A
**tag** stands on the secret two correspondents share and names the pipe between them. A **step
label** stands on the secret two neighbouring machines established at acquaintance and names
nothing but that hop: a machine computes it with the neighbour it is handing to, holding no
secret of the delivery and needing none. Neither takes an index of any kind — a counter of steps
would be a marker of position, and a position tells a hop how far a cell has come.

**The negative vector is normative:** substituting any public value of a participant for
`shared_secret` yields a different tag, and an implementation that derives a tag from a
public value of that kind rather than from the shared secret must fail this comparison. The
vector itself is frozen with the transport vectors.

### The proof scheme

The scheme is chosen by the invariants, not by taste, and three of them decide it between them.

**[I-1] excludes the whole elliptic-curve family.** Every proof system resting on a discrete
logarithm — pairings, inner-product arguments, polynomial commitments over curves — falls to a
quantum computer, and a proof that falls takes the value layer with it. What remains is
hash-based and lattice-based.

**[I-7] chooses between the two.** A hash-based proof rests on functions the protocol already
carries — SHA-256 where value and identity bind, the proof hash the primitives section admits for
what circuits walk; a lattice-based one introduces a second family of assumptions for a gain in
size alone. The surface stays minimal only one way.

**[I-5] and privacy together fix the parameters.** The proof must verify on the commodity
machine of a machine without a graphics processor, and it must be of one length, because a length
that varied with what it proves would carry the count of meaningful spends in its size. And the
proof must be produced where the spending stands: a frame is proven on the device of its payer —
a phone among them — so the memory of the prover is a bound of this document rather than a detail
of a bench. What sizes that memory is the width of the trace together with the blowup; the blowup
stands with the parameters below, and the width is a quantity of the constraint set this document
binds by its hash, bounded where that binding is stated.

**The choice: a transparent hash-based proof of the STARK family, with no trusted setup.**
Transparent because a trusted setup is a ceremony whose failure nobody can observe — and a
protocol that refuses standing viewing keys cannot accept a secret that, if kept, forges value
forever. Hash-based because the hashes are already here: its soundness rests on the collision
resistance of the proof hash, whose honest cost the primitives section states with the name of
what is risked, and on the proximity gaps of Reed–Solomon codes up to the Johnson bound, which is
a theorem (Ben-Sasson, Carmon, Ishai, Kopparty and Saraf, "Proximity gaps for Reed–Solomon codes",
ePrint 2020/654), and on nothing else.

**Why the length is fixed by construction.** The circuit of a frame is fixed: `spends_per_frame`
spends, `items_per_spend` positions each, a Merkle path of `note_tree_depth` and the seven
levels of the horizon of proving for every redemption, one disjunction per position, one rate
bound ranged over the horizon. Nothing in it varies with what a
payer is paying, so the execution trace is of one size and the proof over it is of one size.
The number of bytes follows from the field, the security target and the number of queries:

| Parameter | Value | Why |
|---|---|---|
| `proof_security_bits` | 128 | the level SHA-256 leaves standing after Grover, and the level [I-1] fixes for the whole stack |
| `proof_field` | `2⁶⁴ − 2³² + 1` | one machine word, and the modulus is named rather than the width: two implementations over two sixty-four-bit primes compute two different proofs. Its multiplication reduces by shifts and additions with no division, and `p − 1 = 2³² · (2³² − 1)` carries a subgroup of order `2³²`, nine doublings above the extended domain this scheme uses |
| `proof_challenge_field` | `proof_field[X] / (X³ − 7)` | every challenge and every out-of-domain value is drawn here and never from the base field, and the degree is derived rather than chosen. The soundness of the mixing and of the deep composition is the degree of the trace over the size of the field the challenge came from, so the requirement is `|F|^e ≥ 2^(proof_security_bits) · 2^rows_log2`: the base field gives `2⁻⁴⁴` and a quadratic extension `2⁻¹⁰⁸`, both short of the target, while the cubic gives `2⁻¹⁷²`. Seven is a non-residue of this prime |
| `proof_line_field` | `proof_field[X] / (X⁴ − 7)` | the field a line of a slot is taken over, and nothing else: a lock-opening value, a slope, an abscissa and the value a pledge or a heavy attestation carries are its elements, and the degree is derived rather than chosen ("The forfeit of a node lock, and the evidence that moves it"). An abscissa must be 256 bits wide and four is the least degree that reaches it, so an element is a digest of the proof hash read as it stands. The prime is one more than a multiple of four and seven is no square of it, so `X⁴ − 7` has no factor and every element but zero inverts |
| `proof_blowup` | 8 | the rate at which the trace is extended; larger blowup buys fewer queries at more proving |
| `PROOF_LEN` | 404 576 B | derived below from the contents and the parameters |
| `proof_queries` | 92 | derived below: at blowup 8 and below the Johnson bound the whole soundness error of the scheme — the mixing and the deep composition, the commit phase of the folding and its queries — is at most 2^−128.35, and 91 queries leave it above 2^−128 at every parameter of the bound |

### `proof_queries` = 92

**Value.** 92, at `proof_blowup` 8, `proof_fold` 4, five folding layers and queries at distinct positions of the extended domain.

**Class.** Security.

**Target.** The whole soundness error of the scheme — the mixing and the deep composition, the commit phase of the folding, and the query phase together — is at most 2^−`proof_security_bits` = 2^−128 per attempt, proved and not conjectured: the bound is taken below the Johnson radius of the code, where the proximity gaps of Reed–Solomon codes are a theorem.

**References.** Ben-Sasson, Bentov, Horesh and Riabzev, "Fast Reed–Solomon Interactive Oracles of Proximity" (ICALP 2018; ePrint 2018/046), for the folding and its query phase; Ben-Sasson, Carmon, Ishai, Kopparty and Saraf, "Proximity gaps for Reed–Solomon codes" (FOCS 2020; ePrint 2020/654, ECCC TR20-083 revision 3), Lemma 8.2 and Theorem 8.3, for the soundness of the folding up to the Johnson bound; StarkWare, "ethSTARK Documentation" (ePrint 2021/582), for the sampling of positions and the accounting of the query phase.

**Derivation.** Theorem 8.3 of the reference bounds the error of the folding, for an integer m ≥ 3 the analysis chooses, by ε = ε_C + (√ρ(1 + 1/2m))^q, with the commit phase ε_C = (m + 1/2)^7 · n₀² / (2ρ^(3/2) · |K|) + (2m + 1)(n₀ + 1)/√ρ · Σ l / |K| (Lemma 8.2). Here the rate is ρ = 1 / `proof_blowup` = 1/8, so √ρ = 2^−1.5; n₀ = 2^19 is the largest extended domain of the set, that of the frame and the ballot; |K| = p³ ≈ 2^192 is the order of `proof_challenge_field`, from which every folding coefficient and every coefficient of the mixing is drawn; Σ l = 5 × 4 = 20 is the sum of the folding ratios over the five layers. The mixing and the deep composition add 2^−172 (the row of `proof_challenge_field`). m trades the two phases against each other: a larger m lowers the query term toward 2^−1.5 q and raises the commit term as m^7. At m = 7 the commit phase is 2^−130.15 + 2^−163.27 = 2^−130.15 and one query passes a false proof with probability at most 2^−1.5 × 15/14 = 2^−1.40046, so 92 queries leave 2^−128.84 and the sum is 2^−130.15 + 2^−128.84 + 2^−172 = 2^−128.35, which reaches the target. 91 queries reach it at no m: the sum is 2^−127.24 at m = 7, 2^−127.70 at m = 8 and 2^−127.36 at m = 9, and the commit phase alone is above 2^−128 from m = 9 on. 92 is the least count that reaches the target, at m = 7 or m = 8, and m = 7 leaves the larger margin. The presence, of the extended domain 2^17 and four layers, stands under the same query term with a smaller commit phase, 2^−134.15. The queries are at distinct positions, which only lowers the chance that all of them land where a false proof agrees; no proof-of-work term enters the transcript.

**Sensitivity.** One query more or fewer moves the query term by 1.40 bits at m = 7: 93 give a sum of 2^−129.20, 91 give 2^−127.24. The margin of 92 is 0.35 bit, and the term of the mixing and the deep composition could grow by a factor of 2^41 before it ate it. `PROOF_LEN` moves by 4 344 B per query and `PRESENCE_PROOF_LEN` by 3 576 B. The free block must stay above what the queries open: 2 × 92 + 2 = 186 values against `proof_free_rows` = 256.

**Defence.** Why not 48 queries on the capacity reading, 7 in 8 per query — it takes the proximity gaps of Reed–Solomon codes up to capacity, which is a conjecture, and a protocol whose target is a proof must not rest a security level on a conjecture; the unique-decoding and Johnson readings are theorems and give 2^−39.8 and at best 2^−72 for 48. Why not 88 queries at m = 16, which bounds the query phase alone below 2^−128 — the commit phase at m = 16 is 2^−122.19, so the sum stays above the target at every count of queries; the target is the whole error, not one of its terms. Why not blowup 16, which reaches the same level with fewer queries — it doubles the extended trace a telephone holds whole to prove, and the prover of every machine is a telephone; blowup 8 keeps the memory and the time of the extension as they stand and pays in bytes. Why the cost is acceptable — 191 136 B more on each proof than at 48 queries, carried once by each frame, ballot and candidacy and once by each machine's heavy attestation per window.

### What a proof contains, and therefore how long it is

A length cannot follow from parameters until the contents are fixed, so the contents are fixed
here. A proof is, in this order and nothing else:

| Part | Size |
|---|---|
| the commitment to the execution trace | 32 B |
| the commitment to the quotient | 32 B |
| one commitment per folding layer | 32 B each |
| the evaluations out of the domain, `proof_ood_values` of them | one element of `proof_challenge_field` each, 24 B |
| the tail: the coefficients of the last layer, `proof_tail_degree` of them | one element of the challenge field each |
| per query: the opening of the trace — a path of `log2` of the extended domain | 32 B per level, plus one value of 8 B per slot of the row, `proof_row_values` of them: the columns of the bound and the randomizer beside them |
| per query: the opening of the composition — a path of `log2` of the extended domain | 32 B per level, plus one value of 24 B per part, `proof_composition_parts` of them |
| per query and per folding layer: a path of `log2` of the leaves of that layer | 32 B per level, plus `proof_fold` values of 24 B |

| Parameter | Value |
|---|---|
| `proof_fold` | 4 |
| `proof_tail_degree` | 64 |
| `proof_ood_values` | 132 |
| `proof_trace_width_bound` | 64 |
| `proof_row_values` | 65 |
| `proof_composition_parts` | 2 |
| `proof_free_rows` | 256 |
| `rows_per_permutation` | 128 |

**The tail travels as its coefficients, once, and that is why the last layer opens no path.** A
degree is bounded either by counting the coefficients of a polynomial or by sampling it, and only
the first of the two is a bound: the openings of the last layer stand at query positions, and a
verifier holding some values of a function knows nothing about its degree that the prover did not
choose. Sixty-four coefficients ride once, one and a half kilobytes of a proof of about four tenths of a megabyte,
and the last check becomes counting them and evaluating them where the last fold lands — no
sampling, no interpolation, and no tree below the tail.

**`proof_ood_values` holds two evaluations per column, not one.** A constraint reads a column at
the row it stands on and at the row after it, so a verifier holding only the first of the two
could check no transition at all and the second check would pass over every rule the trace obeys
in time. The slot is therefore twice the values of a row plus the parts of the composition — every
slot of a row at the point, every slot at the point one row on, and the two parts of the
composition at the point.

**`proof_ood_values` covers the width rather than following it.** A proof carries two evaluations
per column of the trace and one for the composition, so a slot sized to the width would move when
the artifact settles the width. The bound is therefore fixed here, and what fixes it is a count of
the widest circuit this protocol proves rather than a margin above one:

```
34   the ring of the permutation, the walk of a tree, and the lane of three digests
 3   the bit of a decomposition, the amount it reaches, and the balance of a spend
 8   the two roots a walk may answer against, pinned where the walk ends: a public value
     reaches a trace only at a boundary, and a boundary knows no branch
12   the six splits of the disjunction — the root, the capacities, the leaf's input, the two
     blocks of the nullifier chain, and the moment — two columns each, one per seam whose rule
     differs between a note and a right
 5   the ranged witnesses of the moment of taking: the high half of the drawn element, the
     drawn word, the quotient and the remainder of its division by the spread, and the
     remainder's complement that holds it below the spread exactly
 2   persistent branch bits, binding every seam of one redemption and forcing filler value to zero
--
64   proof_trace_width_bound, counted on the written circuit
```

What the memory of a device says about that number is that it is affordable and not that it is
forced: at this bound the extended trace of a frame is a quarter of a gigabyte held whole,
against the half a gigabyte [I-5] admits, and a tenth of that streamed by the column. What the
length of a proof says is the price — every extra column adds eight bytes per query and two challenge-field
evaluations in every proof ever published, whatever circuit wrote it. The changed width must be measured on the target device; this count alone establishes no
latency or memory bound for the implementation. Room above the count remains a cost paid by every
proof, whether used or not.

**The slot is fixed at that bound.** The evaluations of a column above the width are zero, the
verifier refuses a proof carrying anything else there, and the `proof_ood_values` slots stand
whatever the artifact settles the width to be. Three things follow, and each of them
is a property this document states elsewhere and could not hold under a slot that moved. The
length of a proof stops depending on the circuit that produced it, so it tells an observer nothing
about what is being proven. One length covers a frame and a proposal alike, which is what the
layout of an object carrying a proof already assumes. And the family of lengths below stops
awaiting the artifact: every term of it is frozen here, so two implementations that never meet
compute one number. What the padding of the slot and of the opened rows
carries is bounded by the bound itself, and it is the whole price of a length that discloses
nothing.

**The free block, the randomizer and the two parts of the composition, which are what let a proof
say nothing of its witness.** The constraints of a description hold on the live rows of the trace
but the last — `proof_free_rows` rows at the end of every column carry no constraint and no
boundary, and the transition of the last live row would read the first of them — and the prover
fills those rows with values drawn uniformly at random before it commits to anything. What a query
opens of a column and what the two points outside the domain evaluate of it are linear forms over a
polynomial of degree below the height, of which more values are free than are ever opened: `2 x
proof_queries + 2` evaluations against `proof_free_rows` free values, so the opened values are
uniform and independent of the witness. A randomizer — one column of uniform values beside the
columns of the bound, at the slot `proof_trace_width_bound` of every row — enters the deep
composition under weights of its own, so what a folding layer opens is uniform as well. The
composition is divided by what vanishes on the rows the constraints reach, which is what vanishes on
every row divided by what vanishes on the excluded ones; its degree therefore stands above the height
by the free rows, and it is carried in `proof_composition_parts` parts, the first of the height and
the second of the free rows, so that the degree a folding layer tests stays the height. The
construction is the one of ethSTARK (StarkWare, 2021, section on zero knowledge) with the batch
randomizer of Haboeck and Kindi, "A note on adding zero-knowledge to STARKs" (ePrint 2024/1037).
A circuit must leave the free block empty: a description whose boundaries reach it is refused where
it becomes a description.

**The circuit of a frame, counted.** Every hash of the circuit is of the proof hash family, so
the circuit speaks one arithmetic and carries no second. Each redemption proves a path of
`note_tree_depth` node permutations and the one of its leaf, carries the walk on through the
leaf of the horizon and its seven node levels for eight more, opens its commitment at four,
derives the part of a right's window at one, absorbs its key once and squeezes the two halves out
of it at three, and derives its nullifier at two after the walk: fifty-nine permutations. What the
walk answers with costs no permutation of its own: the value the accumulator ends at is held, by
the split of the moment's seam, to one of the two roots the verifier computes — the horizon of
proving and the root of the tree of credited rights the proposal of the standing stride's last
window carries — pinned by boundaries where the walk ends. Each spend holds
two redemptions, two output commitments of four permutations each and one rate nullifier of
two: one hundred and twenty-eight permutations. A frame holds three spends: three hundred and
eighty-four permutations, which at `rows_per_permutation` is forty-nine thousand one hundred and
fifty-two rows, rounded up to the next lawful height — 2¹⁶, the least the folding
reaches the tail from above that count. Extended by `proof_blowup` the domain is 2¹⁹. The cost of
one permutation is measured rather than assumed: it is what the three bounds of a constraint
leave it — degree two, a factor naming this row or the one after it, and the bound on the width —
and the count they leave closes on a power of two of its own accord, so the schedule of a
permutation is carried by a periodic column without one idle row. The margin the frame keeps at
that cost is stated with it: a permutation of more than one hundred and seventy rows would
carry the trace past 2¹⁶ and move every length that carries a proof.

**The count of folding layers follows from the tail and is not chosen.** Folding by `proof_fold`
divides the degree bound by four at every step, so after `k` steps the bound is 2^(16 − 2k). The
folding stops when the bound reaches `proof_tail_degree` = 64 = 2⁶, and 16 − 2k = 6 gives
**k = 5**. Five layers, therefore, and the domain under the last of them is 2^(19 − 10) = 2⁹ =
512 — room enough for the sixty-four coefficients the tail carries, which is the check that the
two parameters agree. A further layer would carry the degree bound to 2⁴, below the tail: a tail
of sixty-four coefficients would then claim more degree than the folding leaves it, and the last
check would bound nothing.

**A query opens three kinds of path.** The trace and the composition stand over the base domain,
so each opens `19` levels. A folding layer commits the `proof_fold` values it folds as one leaf,
so layer `i` has `2^(17 − 2i)` leaves and opens that many levels — `17` down to `9` across the
five layers, sixty-five levels in all. One hundred and three levels a query opens in all, and the
tail opens none: it rides in the clear.

**The two branches of a redemption occupy the same blocks, and every row works in both.** A
redemption proves either a note or a right, and which of the two must not be readable from the
length or the shape. The blocks are one set: the key absorbed once and squeezed twice in either
branch; the commitment blocks computing a note's envelope — or, for a right, running that same
chain over the naming half and its worth, a note nobody reads; the block of the part, deriving for
a right the part of its window from the half that spends and the window — the preimage its
nullifier takes — and running for a note over the lane, read by nobody; the leaf and the walk
folding the tree of the branch — of notes, or of credited rights — under the domains of the branch,
a note's leaf taking its commitment out of the lane and a right's the part beside it; the nullifier
chain absorbing the lane and closing, for a note, over the position the walk accumulated, and for a
right over its window, squeezed once more for the moment it is due. Six kinds of seam differ, the
one that opens a chain on the lane standing twice — before the part and before the nullifier — and
each is a split of its selector — two columns whose sum is the schedule and whose product is
nothing — so a rule of a branch fires exactly where its half stands and the degree it carries is the
degree it carried. The window of a right is read at both of its chains as the window the frame
stands in less one remainder of the moment, held from before the part to the end of the nullifier,
so the part and the nullifier are of one window.
The trace is therefore the same shape whichever branch a redemption took, and a frame of rights
is indistinguishable from a frame of notes in every field and every length.

**Therefore:**

```
per query = 32 x 19 + 65 x 8 + 32 x 19 + 2 x 24 + 32 x 65 + 5 x 4 x 24 = 4 344 B

PROOF_LEN = 32 + 32 + 5 x 32 + 132 x 24 + 64 x 24 + 92 x 4 344 = 404 576 B
```

Every term of that sum comes from a number frozen above, and the sum is the same on every
machine that reads this document. It is one length for every frame whatever it carries, which
is the property the value layer needs: a proof that grew with what it proves would carry the
count of meaningful spends in its size.

**What remains to be confirmed rather than chosen, and what moves with it.** The row counts per
compression and per permutation are properties of the arithmetization the reference circuit uses;
a different arithmetization changes those two numbers and therefore `PROOF_LEN`. They are frozen
here as parameters for exactly that reason — an implementation that arithmetizes differently
produces a different length and is detected by the very rule that refuses a frame of the wrong
size, rather than diverging silently.

Every quantity the sum consumes is therefore frozen in this document, and the family derived from
it is frozen with it: `proposal_len`, `frame_len`, `candidacy_len`, the one length
of a confirmation, `pledge_len`, the count of cells every one of those objects takes, `collect_answer_max` which
stands on the largest of them, and the volume the schedule is checked against. **Conformance over
that family is achievable now**, and an implementation that reproduces the arithmetic above lands
on the same bytes as every other. What the artifact settles is the constraint set and the width it
occupies, neither of which enters a length: a circuit narrower than the bound is carried in the
same seventeen slots with the unused ones zero, and a circuit that arithmetizes to a different row
count produces objects of the wrong size and is refused by the very rule that refuses a frame of
the wrong length, rather than diverging silently. The one thing that awaits the artifact is
`air_hash`, which is a value and not a length.

### The birth of a seed

A seed is the root of a person, and it is born once. Two hundred and fifty-six bits are drawn
from the cryptographic source of the operating system and are subjected, before they become
anyone, to four tests. A block that fails any of them is refused rather than repaired: a source
that produced it is broken, and a broken source is answered by refusal.

| Test | Rule | Chance of a false refusal on a healthy source |
|---|---|---|
| repetition count | no byte value repeats eight times in a row | ≤ 32 · 2⁻⁵⁶ |
| adaptive proportion | no byte value occurs more than twelve times in thirty-two | ≈ 4 · 10⁻²¹ |
| distinctness | at least eight distinct byte values are present | < 10⁻³⁰ |
| continuity | the block differs from the block drawn before it | 2⁻²⁵⁶ |

The first three are the repetition-count and adaptive-proportion health tests of
NIST SP 800-90B, sized for a block of thirty-two bytes; the fourth is its continuous test. Every chance above is far below any rate
at which a refusal would inconvenience a person, so a test that fires is a diagnosis and never
noise.

**The sources.** The two hundred and fifty-six bits are never taken from one place. Six
sources are summed under the mixing domain, each preceded by its own length so that no two
different sets collapse into one input:

| Source | Required | What it does not depend on |
|---|---|---|
| the cryptographic source of the operating system | yes | — |
| the jitter of execution: the same short arithmetic work timed many times | no | the operating system and its generator |
| the latency of memory: a walk along a chain of references past the near levels of cache | no | the operating system, its generator and the state of any one core |
| the drift of the quartz: the clock that counts against the clock that names the date | no | the operating system, its generator and any outside party |
| the scheduling: how far a neighbouring thread advances while this one works | no | the generator and the count of idle cores |
| the overshoot of the timer: the shortest sleep asked for against the sleep received | no | the generator and the tick of interrupts |

The six are of four different natures — a generator, the timing of arithmetic, the timing of
memory, and the arbitration of a scheduler — so that no single failure of a machine takes more
than one of them at once. They are the same six on a phone, a laptop and a server: none of them
asks for a device, a peripheral or a permission. A random instruction of the die is not among
them: the dies this protocol runs on in the hand do not carry one, and a source that reports
itself dead on every device of a class is a row of a table rather than a source.

**The drift of the quartz is a physical property of THAT crystal.** A machine holds two clocks of
different natures: one counts the passing of time from its crystal, the other names the calendar
date and is corrected from outside. Over a short interval the two disagree, and by how much depends
on temperature, supply and age of the crystal in this particular device. The low bits of that
disagreement are noise nobody outside can reproduce, and they are what is taken; the high bits,
which merely say how much time passed, are not.

**A source counts as alive only when its own samples DIFFER, and the difference is measured.**
The measure is the most-common-value estimate of min-entropy of NIST SP 800-90B, Most Common Value Estimate, taken as
that standard takes it: not the observed share of the most frequent sample but the **upper bound**
of that share at the confidence the standard names. The observed share is what a short run
happened to show; the bound is what a short run supports, and the difference between the two is
the whole reason the estimator carries an upper bound at all. A source of `n` samples whose most
frequent takes `m` of them is alive when the bound stands at or below one half and at least four
distinct values were produced, so that an oscillation between two numbers does not pass for a
physical source. A run of identical measurements is the absence of a source under the name of the
source.

```
p_upper = m / n + z * sqrt( (m / n) * (1 - m / n) / (n - 1) )      NIST SP 800-90B, Most Common Value Estimate
alive when p_upper <= 1/2 and at least four distinct samples stand

in integers, with no square root and no division:
    n > 2 m   and   414736 * m * (n - m) <= 15625 * (n - 2 m)^2 * (n - 1)
```

The two integers are `4 z²` written as a fraction and nothing else: `z` is 2.576, the point of the
normal law the standard names for ninety-nine per cent, `z²` is 6.635776, and four times it is
414736 over 15625 exactly. Squaring both sides is what removes the root, and it is sound because
the right side of the comparison is non-negative exactly when `n > 2 m`, which the first condition
requires. Every operand is unsigned and no intermediate is negative, so two implementations agree
bit for bit.

**Why the bound and not the share.** At the counts a birth draws, the difference decides. Over
thirty-two samples a source whose true most-common value takes three fifths of its draws shows one
half or less about one time in six, and one whose true value takes eleven twentieths does so about
one time in three: the share alone would call each of them alive that often, and the person would
be told a bit per sample was collected where about half a bit was. The bound refuses them. What it
costs is stated too: over thirty-two samples the bound admits an observed share up to about
twenty-eight per cent, and a source at rest sits far below that.

**The generator of the operating system is judged by another rule, and naming one rule for both
would be the same error again.** It is a full-entropy source by construction, not a physical
process whose unpredictability is being estimated: what can go wrong with it is that it stops, and
what catches that is the four health tests of its own block, not a share of samples. It is alive
when it answered with a whole block and that block passes those four tests. A generator returning
one repeated value is caught by the repetition count and the distinctness test at once, which is
the failure that rule exists to catch.

The threshold is derived rather than assumed, and it is derived from measurement. On a machine at
rest the most frequent sample of every timing source takes between one and twelve per cent of its
samples, which the bound admits with room to spare. Under load the share climbs, and it climbs past the bound: on a laptop compiling its own
release the jitter of execution has been measured at four fifths, and the scheduling at three
fifths, because a core taken away turns a timing into a constant. **That is the rule working and
not failing.** A source degraded to a repeated number carries no unpredictability and is refused
rather than counted, and what carries the birth in that moment is the floor of three living
sources out of six — which is why the floor exists and why no single source is required beyond the
generator of the operating system.

The share of *distinct* samples cannot carry the rule instead: it moves far more between the same
two states — from three quarters down to two fifths — so a threshold on it would refuse an honest
phone in the middle of its work. Against the bound of one half, a dead source sits at the whole of
it and is caught with certainty; a false refusal costs a person a retry, a false pass costs them
their root, and the bound is placed where the second cannot happen.

**The report is taken from the measurements and never from the fact that the code for them ran.**
A length that is constant by construction, or a buffer that is non-empty by construction, says
nothing about the source it belongs to; a count built on such a fact cannot fall below its own
floor on any machine, and a floor that cannot be reached is not a floor.

```
entropy_32 = SHA-256("mt-entropy-mix" || 0x00 || place_0_1B || len_0_2B_LE || source_0
                                              || place_1_1B || len_1_2B_LE || source_1 || ...)
```

The living sources enter ascending by their place in the table above — the place counted from
zero, as one unsigned byte — each preceded by that place and by its own length as an unsigned
two-byte little-endian integer. A source that is not alive contributes none of the three.

**The place is what makes the sentence true.** Lengths alone keep the boundaries between the
summands and tell an absent source from a present empty one, and they leave one thing open: two
draws whose living sources differ but whose surviving bytes and lengths coincide would share a
preimage. The place closes it — the identity of every summand stands in the input — so no two
different sets of sources collapse into one, and the claim is a property of the construction
rather than a hope about coincidence.

An implementation refuses to create an identity when fewer than three sources are alive — and on a
machine where two of the timing sources fall silent four remain, so three is the floor of the set
and never what a phone gets by. An implementation also refuses when
its own self-test fails: a degenerate block is rejected, mixing depends on every
summand, and the machine sources differ between two draws made from one system block. Refusal
is the answer in both cases — a root created on a broken machine looks ordinary and is
guessable, and nothing later reveals that.

**The words.** The seed is shown to its holder as twenty-four words. Each word carries eleven
bits; twenty-four of them carry two hundred and sixty-four, which is the entropy plus one
checksum byte:

```
checksum = SHA-256(entropy_32)[0]
indices  = the 264 bits (entropy_32 || checksum), most significant bit first, in groups of 11
```

The canonical list holds 2 048 words, lowercase ASCII, sorted lexicographically, and is fixed
by its fingerprint:

```
SHA-256(word_0 || 0x0A || … || word_2047 || 0x0A)
 = 2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda
```

Four letters name one word: no two words of the list share their first four characters, so a
phrase written in shortened form resolves to exactly one reading. Case carries nothing.

**The master seed.**

```
master_seed = PBKDF2-HMAC-SHA-256(password = entropy_32, salt = "mt-seed",
                                  iterations = 1 048 576, length = 64)
```

The derivation takes the **entropy**, not the text of the words. Nothing about how a phrase is
typed — spacing, case, the Unicode form of its letters, the order in which a wallet renders
them — can therefore change a derived byte.

**Why 1 048 576 iterations.** Against a uniform 256-bit input a stretch buys nothing: the
search is already 2²⁵⁶ and no factor moves it. The iterations exist for the case the tests
above are meant to catch and cannot always catch — an input that carries fewer bits than it
should, because a source degraded in a way no statistic on thirty-two bytes detects. There the
stretch multiplies an attacker's cost by 2²⁰ against a defender's cost of one derivation. The
upper bound is what a person will wait: 2²⁰ iterations of HMAC-SHA-256 run in under a second
on a phone of the decade, and a phrase is entered when a device is set up, not per action.
A larger exponent buys the same insurance at a delay a person notices; a smaller one gives the
degraded case away for a saving nobody feels.

**One secret and no second.** There is no passphrase beside the words, and this is a decision
rather than an omission. A second secret buys deniability and costs a person everything when
they forget it, since a phrase that is written down and a passphrase that is remembered fail
in opposite ways. Montana holds one secret, states its whole weight to its holder once, and
refuses to hold half of it hostage to memory.

**The shape is BIP-39; the key is not.** The word list, the `bits_per_word` = 11 bits a word
carries and the
checksum byte are those of BIP-39, so that a person reads a familiar phrase and a familiar
tool checks it. The derivation is not: BIP-39 stretches the text of the words under the salt
`"mnemonic"`, Montana stretches the entropy under `"mt-seed"`. The same twenty-four words
therefore open a Montana person and a BIP-39 wallet as two unrelated keys, and an
implementation that treats one as the other produces keys that answer to nobody.

### The branches of a seed

One seed holds a person, and ten branches come out of it, each under its own domain and
each independent of the others. They are derived here and nowhere else in this document; the
sections below that use a branch name it rather than deriving it again:

```
signing_sk      = HKDF-Expand(master_seed, "mt-account-key",        32)
note_sk         = HKDF-Expand(master_seed, "mt-note-key",           32)
nf_key          = HKDF-Expand(master_seed, "mt-nf-key",             32)
encryption_sk   = HKDF-Expand(master_seed, "mt-app-encryption-key", 64)
open_secret     = HKDF-Expand(master_seed, "mt-open-nf",            32)
operator_secret = HKDF-Expand(master_seed, "mt-operator-nf",        32)
rate_secret     = HKDF-Expand(master_seed, "mt-rate-nf",            32)
act_secret      = HKDF-Expand(master_seed, "mt-act-nf",             32)
owner_secret    = HKDF-Expand(master_seed, "mt-owner-key",          32)
lookup_secret   = HKDF-Expand(master_seed, "mt-lookup-nf",          32)
```

**The owner branch is the one branch a person copies out of their device**, onto every machine
they run, and it exists for a single reason: the seal of a step must collapse to one value for
one owner, or a path crossing two machines of one owner would count as two where the owner
computes the seal as this set states it. What a leak of it costs is stated rather than hidden:
it links the hops of that owner to each other — which is exactly what the seal announces by
construction — and it reaches nothing else, because no other branch derives from it and it
derives from no other.

One further derivation stands outside that block because it is taken **per name claimed** rather than once per person, and it is stated
with the contact key below, because deriving it once per person would join two names of one
holder.

Each branch that seeds a key generates it deterministically from that branch and from nothing
else:

```
(record_pk, record_sk)     = ML-DSA-65.KeyGen(signing_sk)
(app_kem_pk, app_kem_sk)   = ML-KEM-768.KeyGen(encryption_sk)
```

**The keys of a handshake are not these.** A handshake is opened with an ML-KEM-768 pair drawn
fresh for that connection and discarded with it: a handshake standing on a branch of a person's
seed would make one handshake joinable to another and both to a person, which is the edge this
protocol does not create.

**The encryption branch seals to its owner and to nobody else.** It is what the content behind an
anchor is sealed to, so that content outlives a device without anything being published. It is
never a value a correspondent is handed: a standing key a stranger could seal to would be a
quantity meaning "this person", which the invariant on graphs forbids outright. What a
correspondent seals to is the secret their own handshake established.

The signing branch seeds the ML-DSA key a record answers with; the value branch seeds the
payment secret; the redemption branch seeds nullifiers; the encryption branch seeds the
ML-KEM key its owner seals their own stored content to. A machine's secret is not among them — it belongs to the
machine and not to the person, and Consensus states why the two are never one.

A machine derives its answering key the same way and from its own secret, which is no branch of
any person's seed:

```
answering_sk = HKDF-Expand(machine_secret, "mt-node-key", 32)
```

**Invariants of the branches:**

- Each branch takes its own domain, so a leak of one discloses nothing of another.
- The lengths above are exact: a scheme demanding a different seed length takes it from the same branch by its own expansion, never by widening this one.
- A branch is derived on the device and never transmitted; what leaves is always a public key or a value derived in one direction.
- The seed itself is never derived from anything: it is the root, and losing it loses the person.

### The one-time rights of a person

Two rights are issued once to a person and once only, and each is spent by a nullifier that
names nobody:

```
open_nf     = sponge("mt-open-nf",     limbs(open_secret))
operator_nf = sponge("mt-operator-nf", limbs(operator_secret))
```

Neither takes a window, an index or a counter, and that is the whole construction: a value with
nothing variable in it can be produced exactly once from a given seed, so a second attempt
presents the identical value and collides with the first. One seed therefore opens one record,
and the record carries the right to raise one machine: its opening writes `operator_nf` into it,
every successor carries it unchanged, and a candidacy spends it — so one record raises one machine,
and the network learns neither whose seed or record it was nor how many either person has — it
learns only that some right was spent, which is what a bound needs and all it needs.

**Invariants of the one-time rights:**

- Neither derivation admits any input beyond the branch: adding a window or an index would turn a right issued once into a right issued per window.
- Both are of the proof hash family, and that is what makes either bound a bound. Each is published by an object whose proof asserts where it came from — an opening spends the right to open a record, a candidacy the right to raise a machine its own record carries — and a circuit of this protocol works in that family alone. A value a proof cannot reach is a value a claimant draws afresh every time, and a ceiling counted over such values counts nobody.

**The vectors of the two rights.** The second line of each stands on a branch of thirty-two distinct
bytes rather than a repeated one, so a reading from the far end answers elsewhere.

```
open_secret = 0x11 x 32, operator_secret = 0x22 x 32, walking = the thirty-two bytes 00 .. 1f

open_nf                      = b7e9ca5694f98fe89483f19c0c81d1e27878701f6aeadb7964f52d56345312d8
open_nf of the walking branch = f03b0b2b5eb0b5e3b24a4f182b80621e597392e302e83d1af891bba6fe390072
operator_nf                      = aeea4d6acef552552144f4decd573616b555b73b0ddee09b37659870a2898fc0
operator_nf of the walking branch = aea5780c028debe8657884f5b6b4b632bd9b65424050d60a88acca15b1f3f9f0
```

- The two are separate branches, so spending one leaves the other untouched and unlinkable to it.
- A nullifier already present is refused in silence, and the refusal names nobody.

### The nullifier of the rate of payment

A payment publishes a nullifier that bounds how many payments a person makes in a window and
names nobody:

```
rate_nf(W, i) = sponge("mt-rate-nf", limbs(rate_secret || W_8B_LE || i_1B))
```

`W` is the height of the window as an unsigned eight-byte little-endian integer and `i` is the
index of the payment within that window, one byte. The proof asserts that `i` is below
`spends_per_window` without publishing it, and that `W` is a window of the standing stride —
every window of which stands before the window the frame applies in — without publishing which, so both
bounds are enforced while both positions stay secret: an observer sees a value it cannot place,
and a person who exceeds the bound presents a value already present.

**Invariants of the rate nullifier:**

- It takes the branch, the window and the index and nothing else; adding anything of the payment would join two payments of one person.
- The index is proven below `spends_per_window` and never published, so the count a person has already made in a window does not leak from what they publish.
- The window it takes stands within the standing stride of the window its frame applies in, asserted by the proof and never published, so a frame proven over many windows is indistinguishable from one proven in its own.
- A rate nullifier already presented against the standing stride is refused in silence; a value of a stride the horizon has left is unprovable, which is what lets the memory of refusals empty when the horizon moves rather than accumulate.
- Its branch is separate from the redemption branch, so a payment's rate and a note's spending do not join.
- It is of the proof hash family: the circuit of a frame proves this derivation, and the doors of that family are the ones a circuit carries.

### The nullifier of the rate of action

An action of the identity plane publishes a nullifier that bounds the actions of one record to
one per window and names nobody:

```
act_nf(W) = SHA-256("mt-act-nf" || 0x00 || act_secret || W_8B_LE)
```

It takes no index, and that is the whole difference from the nullifier of the rate of payment
above: the bound on actions is one per window, so a second action of one window presents the
identical value and collides with the first, while payments are bounded at `spends_per_window`
and therefore carry a position the proof keeps secret.

**Invariants of the nullifier of the rate of action:**

- It takes the branch and the window and nothing else; an index would turn a bound of one into a bound of many.
- Its branch is separate from the branch that bounds payments, so an action and a payment of one person in one window do not join.
- A nullifier already present in its window is refused in silence.

### The nullifier of a version of a record

A record lives as a succession of versions, and an action spends the version it acts from. What
spends it is a value taking that version's blinding factor and its commitment, and no window:

```
record_nf = sponge("mt-record-nf", limbs(blind || record_commit))
```

**Why no window, and why the blinding factor.** A version is spent once and forever, so a holder
cannot act again from a version they have already succeeded — which is what keeps a change of key
from being undone by acting from the record that carried the old one. The factor is drawn afresh for
every version and lives only in the preimage of that version's commitment: whoever holds the
commitment cannot derive it, and whoever can derive it holds that version. A branch of the seed
would be one value for a life, and a nullifier of a life is a nullifier that spends every version at
once.

**Why it is not the nullifier of the rate of action.** That one bounds how often a person acts and
takes the window for exactly that reason; this one bounds how often a version is acted from, and
takes none. One value serving both would leave a hole: a holder could act twice in a window by
acting the second time from the successor the first action created, since the two versions differ
and a value derived from the window alone does not.

**The vectors of the nullifier of a version.** The commitment stands as thirty-two distinct bytes
rather than a repeated one, so a reading from the far end and a swap of the two parts both answer
elsewhere; the second line is that reading and the third is another factor over one commitment.

```
blind = 0x77 x 32, record_commit = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f

record_nf                          = 36cd835235065093e7f0f81f06a23d8e137d7de8a99a344924dac2985e89a5b4
record_nf, the commitment reversed = e582be8498e05dc5ceb277707e50f3e3602222d8f94b617faf8a26fa6a2a0401
record_nf, blind = 0x88 x 32       = 410bfdd9e1673a887358db5884bb18d576b8235882301edfbe4610be59626c01
```

**Invariants of the nullifier of a version:**

- It takes the blinding factor and the commitment of one version and nothing else; a window or an index would turn a value spent once into a value spent per window.
- A nullifier already present is refused in silence, and the refusal names nobody.
- It is of the proof hash family: the circuit of an action proves this derivation, and the doors of that family are the ones a circuit carries.

### The round of a chain, in integers

```
runner_key_seed(machine_secret, W) = SHA-256("mt-runner-key"    || 0x00 || machine_secret || W_8B_LE)
part_key_seed(machine_secret, W)   = SHA-256("mt-part-key"      || 0x00 || machine_secret || W_8B_LE)
(one_time_pk, one_time_sk)         = ML-DSA-65.KeyGen(that seed)

round_elig(part_nf, A, j, r)       = SHA-256("mt-round-att" || 0x00 || part_nf || A || j_1B || r_4B_LE)
    eligible when round_elig < round_threshold, compared unsigned and big-endian over the full width

key_digest(one_time_pk)            = sponge("mt-part-key-digest", limbs(one_time_pk))
runner_digest(runner_pk)           = sponge("mt-runner-key-digest", limbs(runner_pk))

serialize(beacon) = W_8B_LE || j_1B || r_4B_LE || previous_32B || cement_aggregate_32B || cement_count_8B_LE
                    || cement_votes_8B_LE
beacon_len        = 8 + 1 + 4 + 32 + 32 + 8 + 8 = 93 B
beacon_id         = SHA-256("mt-beacon" || 0x00 || serialize(beacon))

round_nf(machine_secret, beacon_id) = SHA-256("mt-round-nf" || 0x00 || machine_secret || beacon_id)

place(part_nf, A, a)               = SHA-256("mt-proposer" || 0x00 || part_nf || A || a_4B_LE)
    the parts of a window propose in an attempt `a` of its agreement in ascending order of place,
    compared unsigned and big-endian over the full width
```

`part_nf` is the nullifier of the machine's part in that window, derived where that nullifier is
derived and asserted by the attestation of presence; the draw reads it rather than the one-time key
because a key comes of a lattice key generation no circuit can assert, so a key in this preimage
would be a value a fabricator draws candidates for. `key_digest` is what a proof of presence binds
the one-time key by, and `runner_digest` what the proof of a ticket binds the key of a proposal by:
a verifier computes each from the key the object carries, so a proof lifted from one object onto
another fails at the boundary that names it. Each digest takes a domain of its own beside the domain
of the key's seed, because a seed is SHA-256 and a digest is of the proof hash, and the registry
holds every domain to one family. `A` is the cemented aggregate
of the window two before — exactly the value and binding
the runner's draw consumes; `previous` is the prior beacon of the chain, or at round zero the
identifier of the proposal of the window two before — the proposal that fixed the electorate of the
window, final when it opens; `cement_aggregate` is the aggregate of the draw section below over the
part-nullifiers of the heavy attestations the beacon's chain has cemented so far, whatever name each
of them pledges, with the window as its context, and `cement_count` is how many of them there are;
`cement_votes` is the sum, over those parts, of the votes the ballot of each part casts — each
part's once, the largest its runner verified — and nought for a part that cast none.

The two one-time keys take two domains because they answer two different questions — one publishes
a window, the other attests it — and a machine that did both under one key would join the two acts.

**Invariants of the round derivations:**

- A one-time key takes the machine's secret and the window and nothing else, so one machine yields one key per window, no two windows share one, and nothing joins a key to the machine that made it.
- Eligibility takes the nullifier of the machine's part in that window, the cemented aggregate of the window two before and the pair of chain and round, and nothing else; nothing in the preimage is anyone's to choose, which is the property the aggregation rule buys the draw, extended to a faster pulse — and every atom of it is either asserted by a proof of presence or cemented before the window opened.
- The digest of a one-time key is taken under the part-key-digest domain over the limbs of that key, and it is what a proof of presence carries in its public input; the digest of a runner's key is taken the same way under the runner-key-digest domain and is what a proof of a ticket carries. A digest takes a domain of its own and never the domain of the key's seed: the seed is SHA-256 and the digest is of the proof hash, and one domain stands in one family. The keys themselves enter no proof, since asserting their generation would cost orders more than the statement around it.
- A beacon serializes the window, the chain index, the round index, the identifier of its predecessor, the cement aggregate, the cement count and the cement votes, in that order and no other; its identifier is taken under the beacon domain, every beacon links to its predecessor by that identifier, and round zero links to the proposal of the window two before.
- The round nullifier takes the machine's secret and the attested beacon's identifier, so one machine yields one value per beacon, versions of one round yield distinct values, and nothing joins a value to the machine that made it.
- One attestation stands per machine per beacon; a repeated round nullifier under one beacon is refused in silence.
- The place of a part takes the part-nullifier, the cemented aggregate of the window two before and the attempt, and nothing else; the part is fixed by the machine's secret and the window, so nobody draws places until one is low, and the place is known of a part once its heavy attestation stands.
- The cement of a beacon is the aggregate over the part-nullifiers of the heavy attestations published so far, whatever name each pledges, each at most once, under the aggregation rule of the set with the window as context, beside their count; every verifier recomputes both from the attestations it holds, and a beacon whose state is not that pair is refused.
- The votes of a beacon are evidence of the close and not a value the window decides: a verifier refuses a beacon whose votes exceed the sum, over the parts of its cement, of the largest count a verified ballot of each part casts, and takes any lower sum, which only delays the close of the version carrying it.

### The draw, and the two canonical orders

The aggregation above takes its domains from the call, and consensus makes exactly three such
calls. Here is what each substitutes, so that no implementation supplies a domain of its own:

```
aggregate(W)   = aggregate_for_seed(cemented set of W, "mt-bc-aggregate", "mt-bc-aggregate-empty", W_8B_LE)

ticket(W)      = sponge("mt-ticket", cells(spending_half) || limbs(aggregate(W - 2)))

selection_key(W, c)   = SHA-256("mt-selection"    || 0x00 || aggregate(W - 2) || c)
registration_key(W, c) = SHA-256("mt-nodereg-sort" || 0x00 || aggregate(W - 2) || c)
cascade_key(W, c)      = SHA-256("mt-cascade"      || 0x00 || aggregate(W - 2) || c)
```

The cemented set of `W` is the part-nullifiers that entered the cement of window `W`, which is what
the proposal of `W` carries as its cement aggregate. `c` is the commitment standing for the machine
being ordered. A ticket takes the half of the machine's secret that spends — the same half the
nullifier of a part takes, so a circuit reads the secret once — and the aggregate as its eight
limbs; it clears when it falls below the threshold, compared as an unsigned big-endian integer over
its thirty-two bytes, and it is never published: the proof the proposal carries asserts the
clearing.

**The ticket is of the proof hash and the three order keys are not, and the boundary is the judge
and never the wire.** A ticket is judged by one thing in this protocol — the description of the
ticket, which asserts that it cleared — and by nothing else, since it enters no object and no state
and is never published. A function the circuit cannot carry would therefore put the draw beyond
proving, exactly as it would have put the envelope of a note and the redemption of a right. The
three order keys stand the other way: every verifier computes them from state with no proof in
hand, so they stay SHA-256 like everything a person or an independent implementation compares.

**The standby order of a window** is the ascending order of `cascade_key(W, c)` over the
commitments of the active set, compared as unsigned big-endian integers, and the machines standing
first in it, to the count `cascade_width`, are the entitled of that window, senior first. Every
verifier computes the whole order from state, every machine finds its own place in it by its own
commitment, and neither learns whose the others are: what is ordered is commitments, which name
nobody. Two commitments sharing a key would be a collision of the function the hash table holds, which is
the property that table demands of a row and never a consequence of the inputs being distinct; the
order is therefore total for as long as the row in force answers that demand. A machine admitted or
pruned between two windows moves the order of the second and not of the first, because the set the
order runs over is the set the window holds.

**Both orders stand on the same aggregate as the draw, and for the same reason.** The aggregate is
canonical and cannot be computed offline before the honest signatures that fix it exist, so no
participant can grind a commitment toward a favourable position in either order — the position is
decided by a value that arrives after the commitment is already fixed.

**Invariants of the draw and the orders:**

- The four calls take four distinct domains, so no value of one is ever a value of another: a value serving two orders would make one mechanism readable from the other.
- All four read the aggregate of the window two before, never of the current one, which is not yet cemented when they are computed — so no order of a window can be computed before the signatures that fix it exist.
- The context of the aggregation is the height of the window whose cemented set it aggregates — the aggregate the proposal of that window carries — so two windows cementing an identical set of signers still yield two aggregates.
- A ticket enters no object and no state; only the assertion that one cleared does.

### The cell, and the two seals it carries

Everything that crosses the wire is this object and nothing else. Its length is `cell_bytes`
whatever it carries, and its three visible parts say nothing: a label that names one step, a
nonce, and bytes indistinguishable from noise.

```
serialize(cell)
  step_label                       16 B         the label of this step, by the derivation above
  outer_nonce                      12 B         drawn afresh for every cell from a cryptographic source
  outer_sealed         cell_bytes - 28 B        ChaCha20-Poly1305 over the routing layer, tag last

cell_bytes = 16 + 12 + outer_plaintext + 16 = 1 232 B, so outer_plaintext = 1 188 B

A sealed field holds the ciphertext and its tag together — the tag is the last sixteen bytes of it
and not a field beside it — so `outer_sealed` is 1 204 B and `inner_sealed` is 904 B. The frozen
vectors of the wire are what fix this: a cell built with either field sixteen bytes short does not
reproduce them.
```

**Invariants of the cell:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes.

**The outer seal — one step wide.** Its key is the directional key of the handshake the two
neighbouring machines hold, by the derivation of the post-quantum handshake above; its nonce is
`outer_nonce`; its associated data is `step_label`. Every hop opens this seal, rewrites what it
must, and seals again under the key of the next step with a fresh nonce, so no two points on a
path carry one byte in common.

```
outer_plaintext
  target_commit                    32 B         the commitment of the machine this cell is for
  seals              path_max x 16 B            one slot per possible step, full from the origin
  inner            cell_bytes - 316 B          the pipe layer, opaque to every hop

inner = 1 188 - 32 - 240 = 916 B
```

**Invariants of the routing layer:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes.

A hop rewrites the seal array at the slot its own seal selects — the seal and its slot are
those of the seal of a step, below: `relay_seal(owner_secret, path_id(inner))`, standing at
`seal_slot(seal)` — and rewrites nothing else: `target_commit` crosses
the path unchanged, which is what lets a hop forward toward it, and `inner` crosses it unread.

**The inner seal — one pipe wide.** Its key is `SHA-256("mt-pipe-key" || 0x00 || shared_secret ||
W_8B_LE)`, its nonce is `inner_nonce`, and it carries no associated data. No hop holds that key,
so the quantities a delivery needs of itself — which delivery, which block of it, how many blocks
— live where only those entitled to read them do.

**What stands in `shared_secret`, and why one formula serves three cases.** The key of a pipe is
derived from the value that carries the right to read what travels in it, and that value differs by
what is travelling:

```
a letter in a pipe        shared_secret = pipe_secret(W), the secret the two correspondents derive, walked to the window
a publication of a channel shared_secret = the slot of that channel
an object of consensus     shared_secret = the point it stands at, of its own round or window
```

**A cell that stands at a point takes both its keys from that point.** A cell carries two seals
whatever it carries, so a publication carries both; what differs is only where the keys come of.

```
point_step_key(P, W) = SHA-256("mt-step"     || 0x00 || P || W_8B_LE)
point_pipe_key(P, W) = SHA-256("mt-pipe-key" || 0x00 || P || W_8B_LE)
```

The label of such a cell is the point itself, which is what a collector asks its holder for, and
`target_commit` carries the point rather than a machine — what stands at a point is for whoever
collects from it, and there is no machine to name. Nothing is weakened by keys everyone computes:
what stands at a point is for everyone by construction, and the seals are there so that a beacon
and a letter are one shape on the wire and a holder of publications is a holder of mail.

The three are one rule read three ways: a hop never holds the key, and whoever holds the right to
read holds it. A letter is readable by two; a channel by whoever knows the name its slot comes of;
an object of consensus by everyone, since every machine computes the points of a round without
asking anybody. That is why the right to take a publication is public and its collection presents
nothing, while the right to take mail from a pipe is sealed to one collector — the difference is in
what the key is derived from and never in the shape of the cell, so an observer of the wire sees
one shape whatever crosses.

The word `secret` stays in the name because the derivation is one; what a case supplies to it is
what that case entitles. An implementation supplying a value of one case to another produces cells
nobody entitled can open, which the frozen vectors of the wire catch at the first delivery.

```
inner
  inner_nonce                      12 B         drawn afresh for every cell
  inner_sealed             inner - 12 B         ChaCha20-Poly1305 over the delivery layer, tag last

inner_plaintext
  delivery_id                      16 B         SHA-256("mt-delivery" || 0x00 || tag || body_root)[0 .. 16]
  block_index                       2 B   u16   the position of this block in its delivery
  block_count                       2 B   u16   the count of blocks the delivery holds
  chunk                           868 B         the bytes of this block

inner_plaintext = 916 - 28 = 888 B, so chunk_bytes = 888 - 20 = 868 B
```

**Invariants of a cell:**

- Its length is exactly `cell_bytes`; a cell of any other length is discarded in silence, and the discard names nobody.
- Both nonces are drawn afresh for every cell from a cryptographic source; a nonce repeated under one key destroys the confidentiality of both cells sealed under it, and an implementation that derives a nonce from a counter or from the content is defective.
- The seal array is full at every step: unused slots carry values drawn like any secret, so the count of steps a cell has crossed is carried nowhere and readable by no one.
- A hop rewrites the seal array at the slot its own seal selects and rewrites `target_commit` never; a hop that alters `target_commit` breaks the delivery and gains nothing, since it cannot read what it carries.
- The inner layer is opened only by the machine holding the pipe secret; a hop that cannot open it is the normal case and not an error.
- Consensus data and correspondence travel in cells of this one shape, and no field distinguishes them.

### The messages of the wire

Cells carry deliveries; these carry everything else that crosses between two machines. Each has
one length or one length rule, each is refused in silence when malformed, and none names anybody.

**The handshake, in four flights.** Roles are those of the derivation above: the side that opened
the connection is the initiator.

```
serialize(hello)              from the initiator
  suite_id                          2 B   u16
  kem_key                        1184 B         pk_i
  answering_key                  1952 B         the ML-DSA key of this device, under the node domain
hello_len = 3 138 B

serialize(hello_answer)       from the responder
  suite_id                          2 B   u16
  kem_key                        1184 B         pk_r
  kem_ct                         1088 B         ct_r, produced to pk_i
  answering_key                  1952 B
hello_answer_len = 4 226 B

serialize(hello_finish)       from the initiator, who now holds all four values of the transcript
  kem_ct                         1088 B         ct_i, produced to pk_r
  signature                      3309 B         sig_i
hello_finish_len = 4 397 B

serialize(hello_confirm)      from the responder
  signature                      3309 B         sig_r
hello_confirm_len = 3 309 B
```

**Invariants of the handshake flights:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes.

**Depositing and collecting.** A deposit places one cell at a point; a collection takes what
stands there. The right to take mail from a pipe is sealed to the collector by a value only the
two correspondents can derive — the secret of the pipe at that window, by the walk the integer form
of a tag fixes; the right to take a publication is public, so its collection presents nothing.

```
collect_right(shared_secret, W) = SHA-256("mt-collect" || 0x00 || shared_secret || W_8B_LE)

serialize(deposit)
  point                            16 B         the tag of a pipe or the point of a channel
  cell                    cell_bytes B
deposit_len = 1 248 B

serialize(collect)            from a pipe
  point                            16 B
  right                            32 B         collect_right for this window
collect_len = 48 B

serialize(collect_public)     from the point of a channel
  point                            16 B
  after                             2 B   u16   the cells of that point the asker already holds
collect_public_len = 18 B

serialize(collect_answer)
  cell_count                        2 B   u16   the cells standing at that point, zero admitted,
                                                and never above collect_answer_max
  cells       cell_count x cell_bytes B

collect_answer_max = 624, the cells of the largest object that stands at a point
```

**Invariants of the deposit and collection messages:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes.

**Waking.** A wake tells a sleeping device that a letter waits, and nothing else; Network holds
the rungs it travels by and what each of them may carry.

```
serialize(wake_inline)
  tag                              16 B         the tag of the pipe the letter waits in
  window                            8 B   u64   the window it waits for, little-endian
wake_inline_len = 24 B

serialize(wake_handle)
  handle                           16 B         an opaque value the holder drew beside that pipe
  window                            8 B   u64   the window it waits for, little-endian
wake_handle_len = 24 B
```

**Invariants of the wake messages:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes.

**Joining.** A device that holds nothing asks for the head, then — from the anchor its operator
handed it — collects at the points of the windows it walks the proposals and the heavy attestations
that are their certificates, and then asks for the leaves it needs. Every answer is judged against
what the asker recomputes and never against who answered; Consensus states the walk. The plane of
the head it reached it takes whole, table by table, as the leaves each table folds and never as a
root: it asks one table from the first leaf it does not hold, repeats until an answer carries fewer
leaves than the bound, and folds every root again from what it holds.

```
serialize(head_query)
  genesis_state_hash               32 B         the network the asker means, recomputed by itself
head_query_len = 32 B

serialize(head_answer)
  proposal            proposal_len B            the newest proposal the answerer holds, a hint of where the head stands and never a thing trusted

serialize(state_query)
  window                            8 B   u64   the window whose roots the asker verified
  root_index                        1 B         0 notes, 1 nullifiers, 2 records, 3 machines, 4 operations
  key                              32 B         the key of a sparse leaf, or the position of an append-only one, little-endian in its low eight bytes
state_query_len = 41 B

serialize(state_answer)
  proof_len                         4 B   u32   zero when the answerer holds no such leaf
  proof                     proof_len B         a MerkleProof for a sparse root, an AppendProof for an append-only one

serialize(table_query)
  genesis_state_hash               32 B         the network the asker means, recomputed by itself
  window                            8 B   u64   the window whose head the asker verified
  table_index                       1 B         0 notes, 1 nullifiers, 2 records, 3 machines, 4 admitted, 5 credited, 6 operations
  from                              4 B   u32   the index of the first leaf the asker does not hold
table_query_len = 45 B

serialize(table_answer)
  leaf_count                        4 B   u32   zero for a table read to its end and for a plane the answerer does not hold
  leaves           leaf_count x leaf B          from `from`, in the order the table folds them; a leaf of records is its key
                                                and its record, 64 B, a leaf of every other table 32 B

table_answer_max(table) = floor((2 + collect_answer_max x cell_bytes - 4) / leaf)
```

**Asking what a slot publishes.** One slot at a time, against the nullifier of a reach.

```
serialize(slot_query)
  slot                             32 B         the slot of a name or of a channel
  reach_nullifier                  32 B         of the current window
slot_query_len = 64 B

serialize(slot_answer)
  published_len                     2 B   u16   zero when the slot publishes nothing
  published            published_len B          the contact root of a name, or the key of a channel
```

**Invariants of the messages of the wire:**

- **Silence bounds the wire and never the account a machine keeps of itself.** Every refusal above is silent to whoever offered it, because an answer naming the reason publishes the state of this machine to whoever asked. A machine's own account is not the wire: it may write, for the operator who runs it, every one of its own doings — how many cells it held and how many it refused and under which of the rules, how many objects it published and pushed and to how many acquaintances, how many collections it asked and how many cells came back, how many attestations entered its cement and how many did not and why. An implementation that keeps no such account is an implementation whose operator must guess at every divergence, and a network of blind machines is one nobody can repair.
- **What an account may hold is what the machine did, and never who it did it with.** No peer, no address, no key, no person, no amount and no identifier of another machine enters it; the counts are of this machine's own actions, which the points of a round already publish by their nature. An account that named a peer would put on an operator's console the very linkage the whole construction of points exists to deny.
- Every message of a fixed length is refused before it is parsed when its length differs, and the refusal is silent.
- The four flights run in the order above; a side carries nothing until it has verified the other's signature over the transcript it computed itself.
- A deposit is accepted at the point of the current window alone; a deposit at a past point is refused in silence, exactly as under a past tag.
- A collection from a pipe presents `collect_right` of the current window, and a repeated right in one window is refused in silence; a collection from a channel presents the point and the count of cells of it the asker already holds, because the right there is public and the reading of a point takes more than one answer.
- A collection from a channel is answered with the cells standing at that point from the index it names, at most `collect_answer_max` of them, and an asker repeats until an answer is shorter than that bound. **Several objects stand at one point** — a beacon and the attestations answering it stand at the round points of one round — while `collect_answer_max` is the cells of the largest single object, so one answer cannot carry a round: without the index an asker reads the first object standing at a point and never the rest, its runner gathers nothing, and no window closes. The count of cells at a point discloses nothing the set does not already publish: the point names nobody, and Consensus already holds the count of published attestations as observable.
- A `collect_answer` of zero cells is the ordinary answer and is indistinguishable from any other, so asking says nothing about whether anything waits.
- `cell_count` never exceeds `collect_answer_max`, and an answer declaring more is refused before a cell of it is read. Every other count of this section is bounded by its own construction; this one is bounded by name, because nothing else bounds it and a holder that answered with the width of the field would spend a collector's memory on one reply. A collection whose answer is refused for this reason is repeated at no point: the deposit stands where it stood.
- A `slot_query` carries exactly one slot; a query carrying a set of slots is refused, and a repeated reach nullifier within one window is refused in silence.
- A `table_query` names the network as a `head_query` does and one of the seven tables in the order a proposal lays their roots out; a table index past them is refused in silence. A `table_answer` is answered only from the plane of a window the answerer holds whole — the window its last close closed and the one before it — and is otherwise of zero leaves, indistinguishable from a table read to its end. The tree of admitted machines a machine holds as its root alone and answers with zero leaves: its halves pass as an opening cohort's do, and the root and the count the head carries judge them. `leaf_count` never exceeds `table_answer_max`, which keeps every answer within the answer of a collection, the largest message of this wire, and an answer declaring more is refused before a leaf of it is read. Nothing an answer carries is a root: the asker folds every root again from the leaves it holds and compares it with the root the head it verified carries, and a leaf no root covers — the rate set of the horizon, the count of openings — is never taken from an answer.
- A `head_query` names the network by the hash the asker computed itself, so an answerer of another network is told apart before a byte of its proposal is parsed; a `state_answer` is verified by recomputing the root and comparing it with the root of a proposal already verified, and a proof of length zero is the ordinary answer for a leaf that does not exist.
- A wake carries a tag or a handle, and a window, and nothing else; a handle is drawn at random by the holder of the letter, lives beside its pipe for that window alone, and resolves nowhere outside the machine that drew it.
- No message of this section carries an address, a name, a person or a count of anything but its own cells.

**The vectors of the messages.**

```
shared_secret = 0x22 x 32, W = 1000
collect_right              = 0bf7dd6548455ec0650828135980e7dc9b05180d459ca2bae0006def6159ae39
pipe_key                   = 2097f12c25ecf20a14b191f77d0dc6407dbc3dc8fe28ecd90d1970d42faabefd
collect_right (W = 1001)   = ecde8139be6233ef23519ddb361dd6faea274138916b841d335b982d5c7aabb3
pipe_key (W = 1001)        = 63b394b362ae40d238abf09c174ef6bafd9e546c4325190bf1ffbcd375ca5e35
round_point(W = 1000, j = 0, r = 7, i = 0)  = 534c4a72958d71edd7425654f881f341
window_point(W = 1000, i = 0)               = a2e9b61c437f761c4bb35fc87c98af79
point_step_key(round_point(1000, 0, 7, 0), 1000)  = 6b0b6615179098270042b16f0856a77541db65c59a6bb81ade3717d046bab363
point_pipe_key(round_point(1000, 0, 7, 0), 1000)  = dfdf6cdeef7c83c2a96e7929e5104c911307e170d104ee4da71cc6dc18c8570c
point_step_key(window_point(1000, 0), 1000)       = aad5940942d98ef57ecef0e61c2d8770c70a5f14ef2d8247daaf586e15694bac
point_pipe_key(window_point(1000, 0), 1000)       = 6d06db4ed2c2d0a4a414a6edc28a847bb21898af1a0b5ecc85d5ac2c45f0dcb7
test_nullifier = SHA-256("mt-vector-nullifier")
               = b45c39841c60739734ab7bcb386fc865490f5eb7b3283c16e27859302aa73cee
notice_point(nf = test_nullifier, W = 1000, i = 0) = 9dbba996aa9baa809a74e40940f0c572
notice_point(nf = test_nullifier, W = 1000, i = 1) = 36a0b66cffbe152974ebec740fffb10e
notice_point(nf = test_nullifier, W = 1000, i = 2) = 40704a6a8149bee128df9e72d73446d9
pledge_point(nf = test_nullifier, W = 1000, b = 0, i = 0) = 8ae0d33e0e43bdc5a0038df8d37a8588
pledge_point(nf = test_nullifier, W = 1000, b = 0, i = 1) = 9b35a7e1410a156ff878e71bdf486347
pledge_point(nf = test_nullifier, W = 1000, b = 0, i = 2) = b2f2ce07f6147aabe3255b785f1c2b7d
pledge_point(nf = test_nullifier, W = 1000, b = 1, i = 0) = 358dd83f06afa82c016323ae173f0d65
```

The two rows at `W = 1001` stand on `pipe_secret(W + 1)`, the secret walked one step, so an
implementation that keys a second window off the established secret reproduces neither.
The nullifier of the vector stands on neither end of its own bytes and repeats no byte pattern, and
the three indices are given rather than one, so an implementation that read the window from the
other end, that dropped the index, that took the last sixteen bytes instead of the first, or that
hashed the domain without the NUL that closes it, reproduces none of the three. The pledge points
of band zero stand on the same nullifier, window and indices as the notice points and differ from
them by the domain and the four bytes of the band, so an implementation that took one domain for the
other reproduces none of either; the fourth pledge point differs from the first by the band alone, so
an implementation that dropped the band, or wrote it in another width, reproduces none of the four.

### How a message crosses a link

The messages above travel between two acquainted machines inside the channel their handshake
established, and what an observer sees of that exchange is what it sees of everything else on this
wire: units of `cell_bytes`, sealed, one indistinguishable from another and from a cell carrying a
delivery. There is no second shape and no second size anywhere.

```
serialize(link_unit)
  step_label                       16 B         the label of this step, by the derivation above
  outer_nonce                      12 B         drawn afresh for every unit
  outer_sealed         cell_bytes - 28 B        ChaCha20-Poly1305 under the directional key of that
                                                handshake, associated data step_label, tag last

link_plaintext                   1 188 B        cell_bytes - 44
  message_index                     2 B   u16   the position of this piece in its message
  message_count                     2 B   u16   the pieces the message holds
  message_kind                      1 B         which message of this section the pieces carry
  piece                        1 183 B          the bytes of the message at that position, the last
                                                piece padded with zeros

link_pieces(message) = ceil( len(serialize(message)) / 1 183 )

message_kind
  1 deposit           5 wake_inline      9 state_query
  2 collect           6 wake_handle     10 state_answer
  3 collect_public    7 head_query      11 slot_query
  4 collect_answer    8 head_answer     12 slot_answer
                                        13 table_query
                                        14 table_answer
```

**Invariants of the link unit:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes.

**A unit is one datagram**, of the size the derivation of `cell_bytes` fixes against the minimum
link maximum transmission unit of IPv6, so no path fragments a unit, no implementation discovers a
path size, and the reassembly of a message needs no length on the wire.

**Where a message ends is read from the message and never from the wire.** Every message of the
wire either has one length its layout fixes or carries its own count — `cell_count`, `proof_len`,
`published_len` — so a reader recovers the boundary from the bytes it has assembled and discards
the padding of the last piece. A length carried in the open would be a marker of size, which is the
one thing a wire of one shape exists to remove.

**What a message is, is read from the message and never guessed.** A machine receives what it did
not ask for — a deposit at a point it stands at, a collection, a query of the head — and every
message of this section either has one length its layout fixes or carries its own count, while the
last piece of every one of them is padded to the one width: so what a reader assembles is whole
pieces whatever arrived, and the length that would have told them apart does not survive the
padding. The kind therefore rides in the framing of a piece, beside the index and the count, and a
reader takes it from there rather than trying the layouts of this section in turn — two
implementations trying them in two orders would answer differently on the same bytes, which is the
one thing this document exists to prevent. **It rides inside the seal**, under the directional key
of that handshake and never in the open, so an observer learns nothing of it: what it sees is what
it saw before, units of `cell_bytes` and no second shape. A piece naming a kind outside the
vocabulary above, or a kind that differs from the kind of the piece before it in one message, ends
the link in silence.

**The four flights of a handshake travel the same way and are sealed by nothing**, because the
channel they open does not yet exist: each flight occupies whole units, padded to the one width,
and the label position of such a unit carries a value drawn like any secret. A flight is no message
of this section and carries no kind: the position of the kind in such a unit carries a drawn value
like the padding beside it, since a side reads the flight it awaits by the length that flight has
and nothing of the framing decides it. What an observer
learns of them is what they are — public key material and two signatures — and it learns it from
units of the same size as every unit after them.

**No address of a carrier is a quantity of this protocol, and that is why none is frozen here.** A
machine reaches another because an acquaintance handed it a way to — Network states where a first
connection comes from — and what it hands over is of the world outside: an address, a port, a
route. The protocol names none of them, holds none of them, and would be creating the very thing
[I-17] forbids if it did.

**Invariants of a link unit:**

- Its length is exactly `cell_bytes`; a unit of any other length is discarded in silence, exactly as a cell is.
- Both the nonce and, before a channel exists, the label are drawn afresh from a cryptographic source; a nonce repeated under one directional key destroys the confidentiality of both units sealed under it.
- A message is assembled from the pieces `message_count` names, in the order of `message_index`; a piece whose index repeats or stands outside the count is discarded in silence, and a message whose pieces do not all arrive is discarded with the window like everything else of that window.
- Every piece of one message carries one `message_kind`, and it is the kind of the message the pieces assemble to; a piece whose kind differs from the kind of the message being assembled is discarded in silence, and a kind outside the vocabulary ends the link.
- A reader takes the count of units it will read from the first piece it opens and reads exactly that many: a reader that read until the pieces happened to assemble would hold whatever a far side kept sending, and `link_pieces` of the largest message of this section is what bounds a count that names more.
- The last piece is padded to the one width, so no unit is shorter than another and no length of a message crosses the wire.
- A unit carries a message or a piece of one and never synthetic filler: where nothing waits, nothing is sent, and what fills a link is the transit of others by the rule that pays for it.

### The erasure code of a delivery

A body is cut into blocks of `chunk_bytes`, the last block padded with zeros to that length, and
the blocks are grouped `erasure_data` at a time. Each group yields `erasure_group` cells: the
`erasure_data` blocks themselves, then the parity blocks, so any `erasure_data` cells of a group
reconstruct it.

The code is Reed–Solomon over the field of 256 elements, with the modulus `0x11D` of the
polynomial basis every implementation of that field already carries. The coding matrix is the
Cauchy matrix of the field:

```
GF(2^8) with modulus 0x11D
cauchy[i][j] = inverse( (erasure_data + i) XOR j )      i = 0 .. 3, j = 0 .. 11
parity[i]    = XOR over j of ( cauchy[i][j] * block[j] )      byte by byte, in the field

erasure_data = erasure_group - erasure_group x redundancy_num / redundancy_den = 12
```

Reconstruction takes any `erasure_data` of the sixteen, forms the matrix of their rows — the unit
row for a body block, the Cauchy row for a parity block — and inverts it in the field. Every
square submatrix of a Cauchy matrix is invertible, which is why any twelve suffice and why the
matrix is Cauchy rather than Vandermonde.

**Invariants of the erasure code:**

- A group is `erasure_group` cells of which exactly `erasure_group` x `redundancy_num` / `redundancy_den` are parity; the arithmetic is exact and no group of another shape exists.
- Reconstruction succeeds from any `erasure_data` cells of a group and is attempted from no fewer; a missing cell is never asked for again.
- The last block of a body is padded with zeros to `chunk_bytes`, and the count of blocks in the delivery layer is what tells the reader where the body ends.
- The field, its modulus and the coding matrix are those above; an implementation that chooses another basis or another matrix produces parity nobody can use, and the frozen vector catches it.

**The vectors of the wire.**

```
step_key = 0x11 x 32, pipe_key = 0x22 x 32, handshake_secret = 0x33 x 32, W = 1000
step_label                 = eef748b204b940f9ede20ee4b9894248
outer_nonce = 0x44 x 12, inner_nonce = 0x55 x 12
target_commit = 0x66 x 32, seals = 0x70 .. 0x7E each x 16
delivery_id = 0x88 x 16, block_index = 3, block_count = 276
chunk = the 868 bytes 0x90, 0x91, ... counted modulo 256
SHA-256(inner)             = 6390c2fc9bfb2a44a75a787d131c1fbe7a94bef8f9d6b9b499788cd7e85ece19
SHA-256(cell)              = d799dd8b3581c2989edcd542f158467ff96bf83853d60c29978e635159304b14

erasure: block[j] = the byte 0xA0 + j repeated chunk_bytes times, j = 0 .. 11
parity[0 .. 3] first four bytes = a5a5a5a5, acacacac, b7b7b7b7, bebebebe
SHA-256(parity[0] || parity[1] || parity[2] || parity[3])
                           = 8963024273fc41fdf9afe063f3be77e7fbc312a7d8ede4f96a7fd99dd4fd0e69
reconstruction from the twelve cells remaining when 0, 5, 7 and 11 are lost returns the twelve
body blocks exactly
```

The sealing itself is checked against the known answer of RFC 8439, Example and Test Vector for AEAD_CHACHA20_POLY1305 rather than against a
vector of ours: an implementation that reproduces that answer holds the primitive, and one that
does not holds something else by the same name.

**What a delivery costs in cells.** A proposal is 392 blocks in 33 groups, so 528 cells; a frame is
467 blocks in 39 groups, so 624 cells; a heavy attestation is 391 blocks in 33 groups, so 528
cells; a candidacy is 467 blocks in 39 groups, so 624 cells; a publication of a channel is 4 blocks
in one group, so 16 cells; a beacon is 1 block in one group, so 16 cells; a light attestation is 7
blocks in one group, so 16 cells; a pledge is 391 blocks in 33 groups, so 528 cells; a roll grows with
what it names, and at 273 frames and 124 parts it is 12 724 bytes in 15 blocks of 2 groups, so 32
cells. The largest of them is what `collect_answer_max` stands on: a roll stands no longer than a
frame while its entries number at most 12 693, and a round point read by a `u16` index holds the heavy
attestations of no more than 124 parts. A heavy attestation stays 528 cells with the 32 B of
`line_value` the author's record 309 adds: 339 321 B is 391 blocks, 67 B under a 392nd. A pledge
point read by the same index holds the pledges of one part of one window, at most 124 of them at 528
cells each, which is one band of that part's pledges — in band zero, every pledge through the open
pledge of attempt 62, and in each band after it the next 124; a window point
holds one proposal and its roll and no pledge, since the same record moved the pledges off it, where
they would have held those of no more than 123 parts (Q11, Q12, "The forfeit of a node lock, and
the evidence that moves it"). Every count follows from `chunk_bytes`, `erasure_data` and
`erasure_group` and from nothing else.

### The points a round stands at

The objects of consensus name no recipient: a beacon is for whoever attests, an attestation is
for a runner who is nameless, and a proposal is for everyone. They therefore travel to **points**
rather than to machines, exactly as a publication does, and the holder rule below decides which
machine stands at each point.

```
round_point(W, j, r, i)  = SHA-256("mt-round-point"  || 0x00 || W_8B_LE || j_1B || r_4B_LE || i_1B)[0 .. 16]
window_point(W, i)       = SHA-256("mt-window-point" || 0x00 || W_8B_LE || i_1B)[0 .. 16]
notice_point(nf, W, i)    = SHA-256("mt-notice-point"  || 0x00 || nf_32B || W_8B_LE || i_1B)[0 .. 16]
pledge_point(nf, W, b, i) = SHA-256("mt-pledge-point"  || 0x00 || nf_32B || W_8B_LE || b_4B_LE || i_1B)[0 .. 16]
                           i = 0 .. consensus_replicas - 1
```

A beacon and the attestations answering it stand at the round points of their own round; a frame
and an operation of the identity plane stand at the round points of the round their canonical slot
names; a proposal and its roll stand at the window points of the window it closes; a pledge stands
at the pledge points of its own part, of the window it is made in and of its band, `nf` being its
`part_nullifier` and `b` the band of its attempt (the author's records 309 and 322); and the notice of every
nullifier a frame spends stands at the notice points of that nullifier, so that two frames spending
one note meet at one point whatever slot carried either of them. Value states what a notice is and
what a reader of such a point may conclude; the point of one is derived here because it is of this
family and its holder is decided by the same rule. Every machine computes the points
of the round it is in without asking anybody, deposits at all of them and collects from all of
them, taking the union of what they hold.

**Invariants of the points of a round:**

- The points are a function of the window, the chain, the round and the index alone; nobody chooses them and no machine can place itself at a point of its choosing, because the holder rule stands on commitments fixed before the window opened.
- The point of a notice is a function of the nullifier, the window and the index alone. Nobody but the owner of a note can compute it before that note is spent — a nullifier is derived from the redemption branch of its owner and from the position the tree assigned, so neither the payer of a note nor any reader of the chain holds what the derivation takes — and once the frame stands the nullifier is public and the point names nobody.
- The point of a pledge is a function of the part, the window, the band and the index alone; the part is public in the pledge and in the heavy attestation of the same part, and the band in the attempt and the kind the pledge carries, so the point names nobody and joins to nothing across windows, as the part does not. A machine computes the pledge points of a window from the parts of the heavy attestations of that window it holds, deposits its own pledges at the points of its own part, and collects at the points of every part whose heavy attestation it holds; the pledges of a part whose heavy attestation it has not yet seen wait at their points until it has, and none of them would count before it had in any case, a pledge without its heavy standing in escrow. One pledge point holds the pledges of one part in one band, at most 124 objects of 528 cells, and a delivery beyond that bound is refused whole, as every delivery at a full point is; the pledges of a later attempt stand at the points of their own band, so no pledge an agreement makes is refused for want of room, and a machine collects at the points of a band once its window's agreement reaches an attempt of it (Q12, "The forfeit of a node lock, and the evidence that moves it").
- **A machine opens what it can do before it opens the door to it.** Every rule of this section is read against something the machine holds — the round it stands in, the window it is at, the count of machines its window admits — and a door opened before that thing is in force refuses the work it was opened for, in the silence every refusal keeps. The neighbour that published in that moment published into nothing and never learns, because the wire tells it nothing; the loss is total and it is invisible from both ends. What follows for an implementation: the window is entered before the door answers, and every bound a door enforces is read when the work arrives and never once when the door was opened.
- **A point refuses a delivery whole and never its tail.** What a point holds is bounded, and a holder that took the first cells of a delivery and refused the rest would hold a body with a hole in it — which reads back as nothing, so a point filled to its bound stops answering with anything at all, exactly when the round it carries matters most. A holder therefore admits a delivery only where what remains of its bound holds the whole of it, and refuses the whole of it otherwise, in the same silence every other refusal keeps.
- A deposit at a point of a past round is refused in silence, exactly as under a past tag. The beacons of the rounds of a window, its heavy attestations, the light attestations answering its final beacon, the ballots and the pledges survive at their points for `retained_windows` windows after the window closes — they are the certificate a device behind walks to the head — and so do the frames of its rounds and its proposals with their rolls, which a machine that took another name replays. A holder opens a cell only down to its delivery and cannot tell one object of a point from another, so it keeps every point of the window whole for that time: the light attestations answering the window's other beacons survive with their point and nothing reads them, and nothing of a round outlives the retention.
- A machine deposits at every replica and collects from every replica; withholding therefore requires every holder of a round to withhold at once, and the objects themselves are self-carrying, so a holder can delay them and can forge none.
- The right to collect from a point of a round is public, like the right to a publication and unlike the right to mail from a pipe: what stands there names nobody.
- A holder answers what it holds and keeps no record of who asked or who deposited; the count of collections at a point says what the ledger of the wire already says about answering at all.

### `inbound_slots` = 96

**Target.** A device answers a neighbourhood several times the size of the one it asks for, holds
every such link inside the memory of the weakest device this protocol claims — a phone — and lets
no stranger take a link that already stands.

**Derivation.** A sender asks `outbound_connections` machines to serve it, one per ring of
distance. Reciprocity sets the floor: a device answering fewer than it asks cannot serve a
neighbourhood larger than its own, and a network of such devices carries nothing for anybody. The
multiple above that floor is pinned by memory: a link holds the reassembly buffer of one erasure
group, `erasure_group` x `cell_bytes` = 19 712 B, and the state of one handshake beside it, so
ninety-six links stand in 1.89 MB and a hundred and ninety-two in 3.79 MB. Four times the entries
is the largest multiple that keeps the whole inbound of a device inside two megabytes, which is
the budget a phone gives the wire without it competing with what the person is doing on the
device.

**Sensitivity.** At twice the entries a device answers as many as it asks and no more, which is a
network where no device carries for a neighbourhood larger than its own. At eight times the
inbound passes four megabytes on a phone. Neither direction moves any other quantity: the slots
bound one device, and enter no root, no proof and no value of consensus.

**Defence.** Why bound it at all — a stranger holding memory pays nothing for it, and a device
whose ceiling is discovered by measurement has a ceiling nobody agreed to. Why refuse rather than
evict — an eviction rule is a second mechanism, and the ranking it needs is exactly the thing an
adversary aims at; refusing keeps what stands, and the release of an idle link reclaims what a
flood holds. Why the entries a device chose itself are not counted here — those are its own
lifeline, standing at points nobody else can compute, and a stranger able to displace them would
undo the closure of the ring.

### `consensus_replicas` = 3

**Target.** No round depends on one machine being willing, and none costs the network more
carriage than the fewest replicas that buy it.

**Derivation.** A round stands at `consensus_replicas` points, whose holders are drawn by the
holder rule from commitments fixed before the window opened, so an attacker aiming at a round must
hold all three at once — a coincidence it cannot arrange and cannot predict, since the points
follow from a window and a round rather than from anything it chooses. Three is the count the
cascade already entitles to run a window, so the protocol trusts a round to no fewer machines than
it trusts a window to, and it triples nothing else: an object deposited at three points is one
object carried three times, and the volume paragraph of the Decree carries that factor where the
envelope is checked.

**Sensitivity.** At one a single unlucky holder stalls a round until the cascade replaces the
runner, turning a delay into a lost window; at seven the carriage of every beacon and every
attestation more than doubles for a coincidence already beyond reach at three.

**Defence.** Why not flood every object to every acquaintance instead — because a flood is a
second profile of traffic on the wire, and a filter that dropped it would stop consensus while
leaving correspondence untouched, which is the concealment of every machine undone in one pass.
Why not send an attestation straight to the runner — because the runner is nameless by
construction, and a machine that could address it could name it.

### The holder of a tag

```
holder(tag, S) = the least c in S with c[0 .. 16] > tag, and min(S) when no such c exists
```

`S` is the set of commitments of the machines living in the window the tag belongs to, compared
as unsigned big-endian byte strings; `tag` is sixteen bytes. The comparison runs over the first
sixteen bytes of a commitment, and the wrap is what makes the set a ring rather than a line.

**Invariants of the holder:**

- The result is a function of the tag and the cemented set alone; nothing about proximity, preference, load or history enters it.
- Two sides reading one cemented set compute one holder, so a disagreement about the holder is a disagreement about the chain.
- The wrap is mandatory: without it the tags above the highest commitment would have no holder at all.

### The seal of a step and the placement of a sender

Two values of the transport are derived here because both are consensus-visible in their effect:
a path is refused without the first, and a window's traffic is unreadable without the second.

```
path_id(inner)                    = SHA-256("mt-relay-path" || 0x00 || inner)[0 .. 16]
relay_seal(owner_secret, path_id) = SHA-256("mt-relay-seal" || 0x00 || owner_secret || path_id)[0 .. 16]
seal_slot(seal)                   = int_le(seal[0 .. 8]) mod path_max

ephemeral_id(sender_secret, W)  = SHA-256("mt-slot" || 0x00 || sender_secret || W_8B_LE)
slot(sender_secret, W)          = int_le(ephemeral_id[0 .. 8]) mod slot_modulus
chain(sender_secret, W)         = int_le(ephemeral_id[8 .. 16]) mod k(W)
k(W)                            = min(k_max, 1 + W / k_step)
```

`inner` is the pipe layer of the cell, the one part of it that crosses a path unchanged: every hop
opens the outer seal, rewrites one slot of the array and seals again, and the pipe layer it carries
is the same bytes at the first hop and at the last. `path_id` is therefore **one value for the whole
path and a different one for every other path**, which is what a seal of an owner stands on and
what a step label — chosen anew at every hop, and by the neighbour rather than by the hop itself —
can never be. The slot follows the seal for the same reason: a hop that read its slot from the label
it was handed would have its place chosen by the hop before it.
`int_le` reads eight bytes as an unsigned little-endian integer. `k(W)` is the count of
chains in force at the height of the window, its division toward zero: `k(0) = 1`,
`k(k_step) = 2`, `k(7 · k_step) = 8`, and the cap holds from the seventh step on.

```
span = 2^256

offset(sender_secret, P, j)
    = int_be( SHA-256("mt-entry" || 0x00 || sender_secret || P_8B_LE || j_1B) ) mod (span >> (j + 2))

entry_point(own_commitment, sender_secret, P, j)
    = ( int_be(own_commitment) + (span >> (j + 1)) + offset(sender_secret, P, j) ) mod span
```

**The entries are held one per ring of distance rather than uniformly.** Ring zero stands half the
ring away, ring one a quarter, and so on to `outbound_connections`. `int_be` reads a commitment as
an unsigned big-endian integer, which is the reading and the wrap the holder rule above already
runs on, so the ring of entries and the ring of tags are one ring and not two. Entry `j` is the
machine, among those the sender knows, whose commitment is the least standing above
`entry_point`, wrapping at the top exactly as the holder of a tag wraps; a point landing on a machine already taken
advances to the next unused one, so the set holds `outbound_connections` distinct entries or as
many as the sender knows. `P` is the period of adaptation the set belongs to, the window height
divided by `τ₂`, and `j` runs from zero to `outbound_connections`. Nobody assigns an entry and no
directory appears — the commitments are consensus state already, and the rule reads the machines
the sender knows rather than a map.

**The point of a ring is a secret of the sender, and that is what keeps a fleet from surrounding
one.** A machine draws the blinding factor of its own commitment and therefore chooses where it
stands in the ring. Were the point a public function of the sender's own commitment alone, an
adversary would grind that factor until its machines stood immediately above every one of a chosen
victim's points: the interval to land in is about one part in the population, so the tries per
ring are the population itself — a few thousand in a small network and more in a large one, cheap
either way against a value nobody hides — and the victim would be surrounded for the price of the
grinding alone. The offset moves the point by a value drawn from the sender's own secret,
inside the scale of the sender's own ring, so the point is known to that sender and to nobody
else, the halving of distance is untouched, and an adversary can no longer aim: to stand at a ring
it must hold a share of the ring, and every machine of that share costs an admission.

**Why uniform entries do not carry a delivery.** Forwarding steps to the acquaintance whose
commitment stands closest to the target. With entries drawn uniformly the nearest of `m` of them
sits about a `1/(m+1)` share of the ring from the target **wherever the sender stands**, so the
first step gains that much and every step after it gains nothing: a delivery at a thousand machines
takes hundreds of steps and at a hundred thousand it stalls. With one entry per ring each step
halves the distance, and a path is `log₂` of the population.

**Invariants of the entries:**

- The point of a ring takes the sender's own commitment, the sender's own secret, the period of adaptation and the index of the ring, and nothing else; two senders standing at one commitment hold two different sets.
- The addition runs modulo the ring and the search wraps at the top of it, so a sender standing high in the ring holds as many entries as one standing low.
- The offset of ring `j` is drawn inside `span >> (j + 2)`, half the distance from ring `j` to ring `j − 1`, so an entry never crosses into the ring above it and the halving of distance holds by construction.
- The set rotates once per period of adaptation and at no other moment: a failure, a send and a restart change nothing about it.

`owner_secret` is the owner branch above, held identically by every machine one owner runs.
`sender_secret` is the secret of the device that sends; Consensus defines it for a machine and states
that every device speaking on the network holds one of that kind and derives every published
value from it in one direction.

**The slot is a round of a chain and never a moment of a clock.** A window holds `slot_modulus`
residues on each of its chains; a sender emits at the first round of its chain whose index
matches its residue. The chain and the residue derive from the ephemeral identity as stated
above, and a beacon is an event of the whole network, so no sender is moved by anyone's idea
of the time, and the placement is reproducible by the sender alone.

**Invariants of the seal and the placement:**

- A seal takes the owner's secret and the identity of the path, so two hops of one owner on one path yield **one** seal at **one** slot: an owner computing the seal as this set states it collapses to a single owner's worth of distinctness instead of passing for a crowd.
- **A seal is a statement of its own owner and not a proof, and the set claims no more of it.** A hop writing a value of its own choosing counts as an owner it is not, and no construction of a wire closes that: telling two machines of one owner apart across a sender's acquaintances requires the sender to present one value to several of them, and a value one sender presents to several machines is itself the mark that joins what those machines see of it. The bound an operator that lies here meets is the price of admission and not the seal — three machines cost three one-time rights, three lived continuities and three slots of a selection event — and the guarantee a sender holds over its own first steps is stated in Network in those terms.
- Two seals of one owner on two different paths do not join, because the pipe layer of one delivery is not the pipe layer of another.
- The slot a seal stands at is a function of the seal alone, so no hop chooses where another hop's mark lands, and a collision of two owners undercounts distinctness rather than overcounting it — a bound of this shape fails closed.
- An ephemeral identity never leaves the device and appears in nothing published; only its reduction places the sender.
- The placement is a function of the window, so a sender occupies an unrelated position in the next one.

### The slot of a channel and its head

A channel is a slot of a space of its own, taken by three objects of the shape a name is taken by —
a commitment, a reveal within its period, a renewal before its own runs out — differing in the one
value a reveal publishes: where a name publishes the key a stranger encapsulates to, a channel
publishes the key its publications are verified under. The space is separate from the space of
names, so a channel and the record of whoever holds it are joined by nothing a reader may compute.

```
channel_slot(name)  = SHA-256("mt-channel-slot" || 0x00 || name_normalized)

channel_seed(slot)  = HKDF-Expand(master_seed, "mt-channel-key" || 0x00 || channel_slot, 32)
(channel_root, channel_sk) = ML-DSA-65.KeyGen(channel_seed(slot))

head(previous, body_root, W)
                    = SHA-256("mt-channel-head" || 0x00 || previous || body_root || W_8B_LE)

channel_point(slot, W)
                    = SHA-256("mt-channel-point" || 0x00 || channel_slot || W_8B_LE)[0 .. 16]
```

`name_normalized` is the normalization the naming derivations fix, under the same alphabet and the
same bounds, so a written word resolves the same way in both spaces. `channel_point` takes the
shape of a tag and its own domain: the slot names the channel for as long as it is held, while the
point where a publication stands lives one window like every other point of this network. `previous` is the head
published before this one, and the first head of a channel carries its slot in that position.
`body_root` is the root of the append-only tree over the pieces a publication is cut into, folded
by the construction this document fixes for a growing sequence.

**Invariants of a channel:**

- A channel slot is derived from the normalized name alone and under a domain of its own, so one written word resolves to two unrelated slots, one in each space, and neither is computable from the other.
- The key of a channel is derived per slot, so two channels of one holder answer to two keys that join to each other by nothing, exactly as two names of one person do.
- A head takes the head published before it and the window, so the order of publications is fixed by the chain rather than by the moment anything arrived, and a publication withheld and released later cannot claim a place it did not hold.
- A head is signed under the key the slot published; the signature names the channel, which is public by the act that created it, and nothing of a person.
- One head stands per slot per window; a second head presented for one window is refused in silence, and the refusal names nobody.
- The point of a window is derived from the slot and that window and from nothing else, so it is computable by whoever knows the name and by nobody else in advance of the window; two windows of one channel stand at two points that join to each other by nothing.

### The nullifier of a reach into the space of slots

Reaching into the space of slots — asking for what a slot publishes, or taking a slot by publishing
a commitment over it — spends a nullifier of this plane, bounding a record to one such reach per
window and naming nobody:

```
lookup_nf(W) = SHA-256("mt-lookup-nf" || 0x00 || lookup_secret || W_8B_LE)
```

It takes no index, so a second reach within one window presents the identical value and collides
with the first — the same construction the nullifier of the rate of action stands on, under a
domain of its own so that a reach and an action never refuse each other.

**Invariants of the nullifier of a reach:**

- It takes the branch and the window and nothing else; an index would turn a bound of one into a bound of many.
- Both a lookup and a taking spend it, so one record reaches into the space of slots once per window whichever of the two it does. A taking that spent nothing would let one record sweep up every name worth having in a single window, at the price of bandwidth alone.
- Its branch is separate from every other, so a reach joins to no action, no payment and no other reach.
- A nullifier already present in its window is refused in silence, and the refusal names nobody.

### The naming of a slot, a chain and a commitment

A name is normalized before anything is derived from it: lowercase ASCII, the letters `a`–`z`,
the digits `0`–`9`, the underscore and the hyphen, beginning with a letter, of a length within
the bounds this document fixes. Its bytes are the normalized characters and nothing else — no
padding, no terminator, no length prefix.

```
slot(name)     = SHA-256("mt-name-slot" || 0x00 || name_normalized)

link(n)        = HKDF-Expand(master_seed, "mt-name-own" || 0x00 || slot, 32)      for n = name_chain_length
link(k)        = SHA-256("mt-name-chain" || 0x00 || link(k + 1))                  for k from n - 1 down to 0

commit(slot, blind, tip) = SHA-256("mt-name-commit" || 0x00 || slot || blind || tip)
```

The chain is built from its far end and spent from its near one: `link(0)` is the tip a
commitment carries, and the renewal numbered `r` publishes `link(r)`, which anyone checks by one
hash against the value published before it. Nobody can compute `link(r + 1)` from `link(r)`, so
only the holder continues the chain, and after `name_chain_length` renewals it is spent.

**Invariants of the naming derivations:**

- A name outside the alphabet, the bounds or the leading-letter rule is refused before a slot is derived from it; two implementations therefore never resolve one written name to two slots.
- The chain branch takes the slot, so two names of one holder yield two chains that cannot be joined.
- A renewal is verified by one hash against the previously published link and by nothing else; a signature would name a key.
- A commitment takes the slot, a fresh blinding factor and the tip in that order, and a commitment carrying anything else is refused.

### The commitment standing for a machine

A machine publishes no key and no address about itself; what stands for it is a commitment:

```
node_commit = SHA-256("mt-node-commit" || 0x00 || answering_pk || suite_id_2B_LE || blind)
```

`answering_pk` is the key the machine answers with, of the size its suite demands; `suite_id` is
the row of the suite table it belongs to; `blind` is drawn afresh on the machine. The commitment
is what a signer set aggregates over and what the ordering of known machines runs on, so it is
canonical, and it names neither an owner, an address nor a person.

**Invariants of the commitment of a machine:**

- The three inputs appear in this order and no other; a commitment computed from any other order is a different value and is refused by every comparison it enters.
- `blind` is drawn from a cryptographic source and never reused, so two machines with one key would still not present one commitment, and a machine that rotates its key presents an unrelated commitment.
- Nothing of the owner enters it, so the machines of one owner are not comparable through it — the seal of a step is the only value by which owners are counted, and it is fresh for every path.

### The nullifier of a machine's part

A machine answers a window once, and the value by which a second answer is caught is:

```
machine_sk ‖ machine_pk = squeeze("mt-key-halves", limbs(machine_secret), 2)

part_nf(W) = sponge("mt-part-nf", cells(machine_sk) || W)
```

It is of the proof hash family, because the attestation of presence proves this derivation inside
its circuit: a value the circuit cannot speak could not be bound to an admitted machine, and the
draw of a round reads this value rather than the key for exactly that reason — Consensus states it
where the draw is stated. It takes the half that **spends**, while the half that **names** is the
leaf of the tree of admitted machines, and both come of the one absorption of the secret that the
machine's halves already take: a circuit reading a secret twice is a circuit where the two readings
may differ.

**Invariants of the nullifier of a part:**

- It takes the spending half of the machine's secret and the window and nothing else, so one machine yields one value per window and two machines never collide.
- The window enters as one element, for the reason the window of a right and the amount of a frame do: two limbs of one number are two witnesses inside a proof.
- Its domain is distinct from the one that spends a right to a coin, so answering a window and taking its coin are two acts that do not join.
- What a second appearance of one part-nullifier means is a rule and not a value, and Consensus holds it whole: a repetition within one window adds nothing to the cement and is lawful, and what a sanction rests on is one part-nullifier under one of the three contradicting pairs of pledges Consensus names. This document holds the derivation and nothing about the rule.

### The identifier of an application

```
app_id(name) = SHA-256("mt-app" || 0x00 || name_bytes)
```

`name_bytes` are the bytes of the application's name as its author writes it, without padding or
terminator. The identifier never travels on the wire; App states where it lives and why.

### The contact key of a name

A claimed name must be reachable by a stranger, and no two names of one person may be joined.
Both follow from deriving the key **per slot** rather than once per person:

```
name_contact_seed(slot) = HKDF-Expand(master_seed, "mt-name-contact-key" || 0x00 || slot, 64)
(contact_root, contact_sk) = ML-KEM-768.KeyGen(name_contact_seed(slot))
```

`contact_root` is the encapsulation key, and it is what the slot of that name publishes. The
tag of first contact takes the same shape as any tag and its own domain:

```
first_tag(contact_root, W) = SHA-256("mt-name-tag" || 0x00 || contact_root || W_8B_LE)[0 .. 16]
```

**What the request establishes.** First contact runs one encapsulation, not two: the stranger
encapsulates to `contact_root` and the holder decapsulates, and both then hold the same `ss`. The
secret every tag of that correspondence stands on is derived from it:

```
shared_secret = SHA-256("mt-name-first" || 0x00 || ss || contact_root || ct)
```

`ct` is the ciphertext the request carried. Both sides hold all three values and nobody else
holds any, so every letter of the correspondence — the first one included — travels under an
ordinary tag, and one begun by a name differs from one begun by acquaintance in nothing an
implementation or an observer can name. This value is where the walk of the pipe begins:
`pipe_secret(W0) = shared_secret` at the window the first letter's tag is derived for, and every
later window of the correspondence stands on the step after it, by the integer form of a tag. The contact root enters the derivation so
that two people writing to one name never land on one secret, and the ciphertext enters it so
that two letters from one stranger to one name do not either.

The separate domain is what keeps the two kinds of tag apart: an ordinary tag stands on a secret
only two parties hold, this one on a value anyone knowing the name can compute, and a shared
domain would let the public kind collide with the private kind.

**Invariants of the contact key:**

- The derivation takes the slot, so two names of one person yield two keys that cannot be joined to each other or to the person.
- The contact branch is separate from the encryption branch, so a name never leads to the key its holder seals their own stored content to, and a name and a correspondence do not join.
- The secret half never leaves the device; what the slot carries is the encapsulation key alone.
- A record that claimed no name derives no contact key, and none can be derived for it by anyone.
- The tag of first contact takes its own domain, so it never collides with a tag standing on a secret two parties hold.
- The tag of first contact carries a request and never a letter; the letters of that correspondence stand on the derived secret alone, so the public value of a name is an entrance and never a channel.

### The right of a machine to its coin of a window, and what redeems it

A machine is admitted once and stands in the tree of admitted machines from then on; the leaf it
occupies is the half of its secret that names it, and nothing else. A window it lived credits it
`window_credit` coins, one for every second of the window, and what the network holds of that credit is a leaf of a second tree, the **tree of
credited rights**, taken over the part its secret derives for that window:

```
machine_sk ‖ machine_pk  = squeeze("mt-key-halves", limbs(machine_secret), 2)
admitted_leaf            = sponge("mt-admitted-leaf", cells(machine_pk))
part_nf(W)               = sponge("mt-part-nf", cells(machine_sk) || element(W))
credited_leaf            = sponge("mt-credit-leaf", cells(part_nf(W)))
credited_node(l, r)      = node("mt-credit-node", l, r)
credited_root            = the fold of the append-only construction over the credited leaves in
                           the order they entered, at depth note_tree_depth, under those two doors;
                           the empty leaf is sponge("mt-credit-leaf", nothing)
credit_nf ‖ claim_delay  = squeeze("mt-credit-nf", cells(machine_sk) || element(W), 2)
```

`W` is the height of the window the right belongs to, absorbed as one element of the field —
`element(W)` is the door that reads an unsigned integer below the modulus as a single element.
One element and not two limbs, for the reason an amount of a frame is one element: two limbs of
a window are two witnesses inside a proof, and a pair of non-canonical limbs summing to the same
window would yield a second lawful nullifier of one right. One element admits one encoding. The
window is inside the derivation because the right is issued per window, which is exactly the
opposite of the one-time rights above, where a window would break the construction.
`part_nf(W)` is the nullifier of the machine's part in `W`, derived as the section on that
nullifier derives it — the value the cement of `W` holds for the machine, if it lived `W`.

**When a window's credit is written.** The challenge of `W` closes when the window after it closes
(Consensus, "Finality"), and from then on no pair can convict a part of `W`. The proposal of
`W + 1` therefore appends to the tree one credited leaf for every part of the cement of `W`,
ascending, less every part a contradicting pair presented within the challenge of `W` convicts, and
carries `credited_root`, the root of the whole tree after that append, which every verifier
recomputes from the state it holds and never takes from the proposal. Nothing else of the credit
persists: the tree holds parts, a part names nobody, and the pairs that convicted stand in the roll
of `W + 1` so that a machine replaying that roll leaves out the same parts — the layout they take
there is owed with the sanction itself (Registry, CNS-10), and until it lands a roll carries none
and the proposal of `W + 1` credits the whole cement of `W`.

**Why the window does not enter the leaf beside the part.** The part takes the spending half and
the window and nothing else, the window as one element, so one machine yields one part per window
and the parts of two windows are two unrelated values (the invariants of the nullifier of a part).
A leaf over the part of `W` is therefore a leaf of `W` and of no other window: a redemption that
derives the part from the window its nullifier takes reaches that leaf only by naming the window
whose cement held the part, and a second window reaching it is a collision of the proof hash. A
window written beside the part would bind again what the part already binds.

**What a redemption of a right proves.** In the one absorption of the machine's secret under
`mt-key-halves`, whose spending half yields `credit_nf`, it derives the part of `W` from that same
half and that same element of the window, and walks the credited leaf of that part to the
credited root the proposal of the standing stride's last window carries; the nullifier of this
window's right under that half is the published value, the amount the right brings into the
balance of the frame is `window_credit`, and the computed moment of taking falls within the standing
stride of the window the frame applies in — every window of a stride stands before its standing
period, so nothing lands before its moment, and a moment of a stride the horizon has left is
unprovable. It proves membership exactly as the redemption of a note does, and against a root of its
own; the two branches occupy the same blocks, so nothing of which was taken is readable from the
length of a frame or the shape of its trace. Neither the part, nor `W`, nor the position of the
leaf is published: `credit_nf` is the one public value of the position, and the part — public in
the attestations of `W` — does not join to it, since the two take distinct domains. The amount is
a constant of the construction and not a witness: a right is worth `window_credit` coins whatever the count of
the living of its window, so a frame prices a right alone and no count of a cement enters its proof
to do it. The credited root of a stride holds the parts of every window before the stride's last;
a right whose computed moment is its own window, where that window is the last of its stride, finds
its leaf under no root its stride stands under, and `AUDIT.md` carries that case open.

**Why the redemption walks no tree of admitted machines.** A part enters a cement only beside a proof
of presence deriving it from the secret of a machine whose naming half stands in the tree of
admitted machines: every heavy attestation is verified natively against the root of the electorate
before its part enters, and a part the electorate does not hold enters no cement (Consensus, "The
pulse and the close of a window", and "The attestation of presence"). The tree of credited rights
takes the parts of a cement and nothing else, so a credited leaf is the part of a machine that stood
admitted in its window, and a second secret yielding the same part is a collision of the proof hash —
the ballot stands on the same argument and walks no tree of admitted machines either (Consensus, "The
standing of a machine, and the ballot"). The walk of the credited tree therefore stands where the
walk of the admitted tree stood, and a position still costs one walk; what it adds is the one block
deriving the part.

**Invariants of the right of a machine:**

- A redemption of a right walks to a leaf of the tree of credited rights. Without a walk the nullifier binds nothing a network can check: the network holds no secret of any machine and can pre-register no value, so a fresh secret would yield a value it has not seen and it would pay for it. A walk to the tree of admitted machines closes that and no more: a machine admitted and absent from the cement of a window would take that window's coin. The walk to the credited leaf of the part closes both, because the tree holds a part only where a cement held it.
- The part the leaf is taken over and the nullifier both take the spending half and the one element of the window, of one absorption of the machine's secret. Two absorptions would be two readings of one secret, and a circuit reading a secret twice is a circuit where the two readings may differ — the same closure the key of a note takes, for the same reason; two elements of the window would be two windows.
- The proposal of `W + 1` appends the parts of the cement of `W` and no other value, ascending, after the challenge of `W` has closed, and the root it carries is recomputed by every verifier; a part a contradicting pair of that challenge convicts enters no leaf.
- The nullifier takes the spending half and the window and nothing else, so two machines never collide and one machine cannot spend one window twice.
- Nothing published by a machine carries either half's preimage, so a coin taken says nothing about who runs the machine.
- A redemption of a right brings exactly `window_credit` coins into the balance of its spend; a right standing for any other amount is not a right of this construction.
- A nullifier already present in its window is refused in silence.
- The moment of taking is the second squeeze of that same absorption, so no third reading of the secret exists anywhere in this construction.
- All of it is of the proof hash family, for the reason the envelope of a note is: a right is redeemed by a frame and by nothing else, so the one judge of these derivations is a verifier of a proof, and a function the circuit cannot carry would put the redemption of a right beyond proving.

### The forfeit of a node lock, and the evidence that moves it

The author's records 224, 231 and 233 decide three things:
- a machine is raised by a key that lived τ₂ and by a lock of coins its owner puts up;
- a violation of the protocol forfeits that lock and excludes the machine from consensus;
- a forfeited lock is burned.

This section holds the relation between the evidence of a violation and the lock that evidence
forfeits: what a verifier reads, what binds the evidence to the lock of exactly one machine, and
what it refuses.

It does not hold the lock itself. None of the following stands in a document of this set yet:
- the layout of a lock;
- what binds a lock to a candidacy;
- its amount as a row of the Decree;
- its release;
- the amendment the records require of the Constitution: [I-6], [I-12] and the monetary
  constitution's "no protocol-level burning".

Until they stand, no lock exists to forfeit, and conformance over this section is unachievable.

**What a verifier reads.** It reads the one evidence this protocol accepts against a machine, and
nothing else (Consensus, "The sanction of a double answer"): two objects of one window `W` under one
`part_nullifier`, forming one of the three contradicting pairs Consensus names. The three pairs are:
- two open pledges of one attempt on two names, two heavy attestations of `W` naming two names among
  them;
- two closing pledges of one attempt on two names;
- a closing pledge and, in a later attempt, an open pledge on another name standing on none or on an
  attempt before the closing one.

The first two move a lock. The third forfeits no lock and stays a sanction of the window's coin (the
author's record 296, below): a verifier presented with it as evidence of a forfeit refuses it as
such, and the part it convicts still loses the coin of `W` and nothing more.

From these objects the verifier reads:
- of each pledge, its bytes as "The pledge of a part" lays them, its signature under its
  `answering_key`, and its proof under the description of the pledge against its public input;
- of the part, the heavy attestation of `W` under that same key, whose proof of presence it verifies
  against the root of the electorate of `W`, the name it attests and its `line_value` ("The
  confirmation of a window"); of a first pair of attempt zero, the two heavy attestations are the
  two objects, and each `line_value` is the point the verifier reads;
- of the window, whether the challenge of `W` is open. The challenge runs from the proposal of `W` to
  the close of `W + 1` (Consensus, "Finality").

It reads no timing, no silence, no reachability, no account of a neighbour, and no statement of
whoever presents the pair.

**What binds the evidence to one machine.** `part_nf(W)` takes the spending half of one machine's
secret and the window, and nothing else ("The nullifier of a machine's part"). The proof of presence
the heavy attestation carries derives it from a secret whose naming half, of the same absorption,
stands in the tree of admitted machines. A second secret yielding the same part is a collision of the
proof hash. The part a pair convicts is therefore the part of exactly one admitted machine. The lock
that evidence forfeits is the lock that machine's candidacy put up: the candidacy that published the
naming half of the same absorption of the same secret ("The candidacy of a machine").

**The relation the author chose.** The verifier holds the part, not the secret. A part joins to
nothing across windows and to no naming half ("The confirmation of a window"; Consensus,
"Observability ledger"), and the attestation of presence rests on that. The author's record 285
(decision 282, 27.10.2026 14:11 UTC) chose how a convicted part reaches its machine's lock:
extractable on equivocation. Each pledge carries a value from which two contradicting pledges of one
part reveal a lock-opening value, and an honest single pledge stays unlinkable. The relation must
hold without the convicted machine's cooperation, as the evidence itself is complete without a word
from anyone (Consensus, "Finality"). As the observability ledger of Consensus stands, it must also
join no part of another machine, and no other part of the convicted one, to a naming half, a lock or
a candidacy. It is a new statement of a proof — of the proof a pledge carries (record 295), of the
proof of presence the heavy attestation carries (record 309), and of the proof of a candidacy — and
so a new network. The construction below goes as far as this set carries it, and says where it stops.
Until it lands whole, an implementation forfeits no lock on any evidence. The invariants below are
what it must meet when it lands, not a rule an implementation can apply today.

**The construction.** It takes no primitive this set lacks. It uses the proof hash, the
pseudorandomness the table of demands already asks of a nullifier of a right, and the split of one
absorption of a machine's secret into the half that spends and the half that names ("The nullifier
of a machine's part").
- A **slot** of a part is one kind of pledge, open or closing, in one attempt of its window. The heavy
  attestation is the open slot of attempt zero. A machine following the agreement signs at most one
  name in a slot (Consensus, "The agreement on what a window decided"); a repetition on one name is
  lawful.
- The **lock-opening value** is drawn from the spending half alone, so it is one value for the
  machine across all its windows. Neither the half, the naming half nor any part is computable from
  it.
- The **slope** of a slot is drawn from the spending half, the window as one element, and the slot.
  Every slot of every window has its own.
- The **abscissa** of a name is drawn from the name alone. An abscissa of zero is refused.
- The **value** a pledge carries is the line of its slot at the abscissa of its name: the
  lock-opening value plus the slope times the abscissa.

Each of the three is one sponge of the proof hash under a domain of its own, and its digest is read
as an element of `proof_line_field` as it stands:

```
opening        = sponge("mt-line-opening", cells(machine_sk))
slope(W, s)    = sponge("mt-line-slope", cells(machine_sk) || element(W) || element(s))
abscissa(name) = sponge("mt-line-abscissa", limbs(name))
s              = 2·attempt + kind
value          = opening + slope(W, s) · abscissa(name)
```

`machine_sk` is the spending half of the one absorption of the machine's secret, the half
`part_nf(W)` takes ("The nullifier of a machine's part"), and `element(W)` and `element(s)` are each
one element of `proof_field`, for the reason the window is one there. `name` is the identifier the
object pledges, 32 B, absorbed as its eight limbs. `kind` is one for a closing pledge and zero for an
open one, and the slot is one element. The open slot of attempt zero, the heavy attestation, is slot
zero; the closing pledge of attempt `u` is slot `2u + 1` and the open pledge of attempt `t` is slot
`2t`, one more than the position of each in its band ("Past attempt 62", below). So every slot of a
window has its own `s`, and the largest attempt stays below the modulus. An abscissa that is the zero
of the field is refused where the name is read, and the object with it.

**How a verifier extracts it.** Two pledges of one part in one slot on two names carry two points of
one line at two abscissas. That is exactly the first and the second pair of "The sanction of a double
answer". With the points (x₁, y₁) and (x₂, y₂), the lock-opening value is the line at abscissa zero,
(x₂·y₁ − x₁·y₂) / (x₂ − x₁), in the field the line is taken over. A repetition on one name carries one
point twice and reveals nothing.

**What it opens, and how a verifier checks that.** The candidacy that put up the lock carries a
commitment to the lock-opening value under the proof hash. The verifier recomputes that commitment
from the extracted value and compares. The commitment of another candidacy is another value, up to a
collision of the proof hash. So the extracted value opens exactly the lock of the machine whose
secret yields the convicted part, and no other. Two questions here await the author:
- whether a forfeit names that candidacy, or consumes the lock by a nullifier of the value without
  naming it (Q3);
- the layout of the lock and its tie to the candidacy (Q6, draft PR #52).

**Why one honest pledge reveals nothing.** Every slot of every window has its own slope, drawn by the
sponge from the spending half. One point of a line is therefore a value that the pseudorandomness of
the proof hash makes indistinguishable from random to anyone not holding the half. Two honest pledges
of one machine stand in two slots, of one window or of two. Their points lie on lines with unrelated
slopes: each point adds one unknown slope, so the lock-opening value stays hidden, and the points join
to each other no more than two parts do ([I-17]). This still holds after a forfeit makes the
lock-opening value public. The other points of the convicted machine still lie on slopes nobody else
holds, so its other parts stay unjoined.

**What the proofs must newly assert.**
- The proof that carries the value asserts the following, in the one absorption of the machine's
  secret whose spending half yields `part_nf(W)`. From that same half and the same element of the
  window it derives the lock-opening value and the slope of the slot. The value the object carries is
  that line at the abscissa of the name the object pledges. A pledge carries that proof as its own,
  under the description of the pledge ("The pledge of a part", "What its proof asserts"). The heavy
  attestation, the open slot of attempt zero, carries it inside its proof of presence, under the
  description of the presence (record 309; "The confirmation of a window", "What its proof
  asserts").
- The proof of a candidacy asserts that the commitment to the lock-opening value is taken from the
  spending half of the absorption whose second squeeze is `naming_half`.
- Each is a new statement of a proof: a new description, a new constraint set, a new `air_hash`, and
  a new network.

**Where the construction stops.** Two choices this set did not make stood between the construction
and a rule (Q8, Q9), and the author has made both. Two choices records 295 and 296 did not settle
followed from the first (Q10, Q11), and the author has made both too (record 309).
- **Which object carries the value under a proof (Q8).** A value no proof binds to the secret is a
  value its signer chooses, and two such values extract nothing. Before the decision a pledge carried
  no proof, and the heavy attestation was the one object of a part that did ("The confirmation of a
  window"). The author's record 295 (decision 290, 27.10.2026 17:19 UTC) chose: every pledge carries
  its own proof, which gives a new `pledge_len` and a proof of the presence's length on every pledge.
  So a pledge carries `line_value` and its proof of it ("The pledge of a part"), and `pledge_len` is
  339 263 B where it was 5 343 B. Its consequence: two pledges of one part in one slot on two names
  give the lock-opening value in any attempt, so the first and the second pair forfeit the lock
  whichever attempt they are made in. A new length of a pledge is a new wire, and the description of
  the pledge is a new statement of a proof, so this is a new network.

  Record 295 did not settle one object. The first pair of attempt zero is two heavy attestations
  naming two names, and the heavy attestation is the open slot of attempt zero. It is a confirmation
  and not a pledge, and it already carries a proof, the proof of presence. Three ways stood open: the
  proof of presence also asserts the value; a second proof, under the description of the pledge,
  beside it (32 + 333 888 B more); or no value, the first pair of attempt zero staying a sanction of
  the window's coin. The author's record 309 (decision 302, answer (a), 27.10.2026 19:48 UTC) chose
  the first (Q10). So:
  - **The wire.** The confirmation carries `line_value`, 32 B, at offset 138, after
    `round_nullifier` and before `suite_id`; every field before it keeps its offset, and every field
    after it moves by 32 B. `confirmation_len` is 339 321 B where it was 339 289 B ("The confirmation
    of a window"). The signature covers it as it covers everything before it. The light attestation
    does not carry it: it pledges nothing, carries no proof, and its length stays 5 401 B.
  - **One proof.** The proof of presence asserts, beside what it asserted, that `line_value` is the
    line of the open slot of attempt zero, drawn from the spending half of the same absorption that
    yields `part_nf(W)` and from `W`, at the abscissa of the name the confirmation attests: the
    identifier among `attested` that is not the beacon of its round. Its public input gains that name
    and `line_value`, after the window. No second proof is carried, and no length of a proof moves.
  - **Its height.** The presence lays 108 blocks of `rows_per_permutation` rows: the idle block, the
    absorption of the secret squeezed twice (3), the leaf and the walk of the tree of admitted machines
    (1 + 40), the nullifier of the part (1) and the absorption of the one-time key (62), so 13 824
    rows of the 16 384 of `presence_rows_log2` = 14, of which the last `proof_free_rows` = 256 are
    free and 126 blocks are live. The value adds at most four blocks: one for the lock-opening value
    over the half, one for the slope over the half, the window and the slot, and two for the abscissa
    over the eight limbs of a name. That is 112 blocks, 14 336 rows, so the presence stays at
    `presence_rows_log2` = 14 and `PRESENCE_PROOF_LEN` stays 333 888 B. The line itself, one product
    and one sum in the field of the line, adds columns and constraints and no block; that it stays
    under the bound on the width is counted on the written circuit.
  - **Its cost.** 32 B per heavy attestation. A heavy attestation is still 391 blocks of
    `chunk_bytes` in 33 groups, so 528 cells, 67 B under the next block ("What a delivery costs in
    cells"), and the volume per machine per window rounds to the same ≈ 230 KB ("The volume the
    schedule is checked against").
  - **Its consequence.** Two heavy attestations of one part of `W` naming two names carry two points
    of the line of one slot, so the first pair of attempt zero gives the lock-opening value and
    forfeits the lock, as the first and the second pair of every later attempt do. The description of
    the presence is a new statement, so its identifier and `air_hash` move when its artifact is
    published, and the confirmation is a new wire: a new network.
- **The third pair (Q9).** A closing pledge of attempt `u` on one name and an open pledge of a later
  attempt `t` on another name, standing before `u`, are not two pledges of one slot.
  - One line per closing attempt would extract from a machine following the agreement. Its open
    pledges of two later attempts on two names, both standing before an attempt in which it signed no
    closing pledge, would put two points on that attempt's line.
  - One line per pair of attempts makes a closing pledge carry a point for every later attempt. But no
    bound caps the attempt below `0xFFFFFFFF`, and a pledge has one length.

  So the third pair needed either a bound on the attempt, which is a new number of the Decree, or to
  forfeit no lock and stay a sanction of the window's coin. The author's record 296 (decision 291,
  27.10.2026 17:19 UTC) chose: the third pair does not forfeit the lock and stays a sanction of the
  window's coin, with no new number of the Decree. So a closing pledge of attempt `u` on one name and
  an open pledge of a later attempt `t` on another, standing before `u`, forfeit no lock: they convict
  the part and its right to the coin of `W` (Consensus, "The sanction of a double answer"), and
  nothing more. No bound on the attempt enters the Decree, and a pledge carries one point, of its own
  slot. Whether evidence other than the three pairs forfeits a lock is Q2 and still awaits the author.
- **Where a pledge stands (Q11).** A pledge now takes 528 cells, as a heavy attestation does ("What
  a delivery costs in cells"). While every pledge of a window stood at the window points of that
  window, a window point read by the `u16` index of a public collection held the pledges of no more
  than 123 parts beside one proposal and its roll, so the pledges of a larger electorate could not all
  be read where the set put them. Three ways stood open: points of their own by window and part; an
  index wider than `u16`, a new wire for every collection; or the round points of the part's heavy
  attestation, which halves what a round point holds. The author's record 309 (decision 302, answer
  (a), 27.10.2026 19:48 UTC) chose the first (Q11). So:
  - **The points.** A pledge stands at the pledge points of its part, window and band,
    `pledge_point(nf, W, b, i)` for `i` = 0 .. `consensus_replicas` − 1, where `nf` is its
    `part_nullifier`, `W` its `window` and `b` its band, below ("The points a round stands at"). The
    window points keep the proposal and its roll and nothing else.
  - **The domain.** `mt-pledge-point`, of the SHA-256 family, a domain of parts in the registry's
    sense, four values of fixed width: the part-nullifier (32 B), the window (8 B, little-endian),
    the band (4 B, little-endian) and the index (1 B), 45 B after the separator, the first 16 B of
    the digest being the point. It
    enters the registry of separators with this construction, as "No domain awaits a document"
    asks, and its row of the Registry is the row of the points (CNS-17).
  - **What a point holds.** The pledges of one part of one window in one band, and nothing of
    another part: read by the `u16` index, at most 124 objects of 528 cells, 65 472 cells. In band
    zero that is the closing pledge of attempt zero, the open and the closing pledge of each of
    attempts 1 to 61, and the open pledge of attempt 62, for a machine that signs one pledge in a
    slot. It no longer moves with the
    count of the electorate. A window point holds one proposal and its roll, 528 + 32 cells at 273
    frames and 124 parts.
  - **What it costs.** No cell more is deposited: a pledge is still 528 cells at each of
    `consensus_replicas` points. A collector reads the pledges of a part by `collect_public` (18 B,
    one link unit of `cell_bytes`) at each of its pledge points, one per 624 cells and at least one,
    where the window point took 528 / 624 of one per pledge; so a window decided in attempt zero
    costs one such collection per part and replica. It learns the part from that part's heavy
    attestation, so a pledge whose heavy it has not seen is neither found nor counted (it stands in
    escrow, as before). Each band an agreement reaches past zero adds one such collection per part
    and replica, so the cost of a window grows with the attempts it took and with nothing else. A
    domain is one row of the registry and one of the Registry.
  - **What it names.** The point is a function of the part, the window and the band, all public in
    the pledge itself, so it names no machine and joins nothing across windows, as the part does not.
- **Past attempt 62 (Q12).** Record 309 left one thing open: an agreement that runs past attempt 62
  of one window makes pledges of a part that its point cannot hold, and a point refuses a delivery
  whole. The author's record 322 (decision 321, answer (a), 28.10.2026 20:17 UTC) chose further
  points of the same domain, keyed also by a band of attempts, with no new number of the Decree. So:
  - **The band.** A part's pledges take positions in the order the agreement makes them: the closing
    pledge of attempt `u` stands at position `2u`, the open pledge of attempt `t` at `2t − 1`, and
    no position is negative, since an open pledge of attempt zero is refused. A pledge stands in
    band `b = ⌊position / 124⌋`, 124 being what a point read by the `u16` index holds, so band zero is
    exactly what one point held before and each band after it holds the next 124 positions. The
    largest attempt, `0xFFFFFFFE`, stands in band 69 273 666, under the four bytes the band takes.
  - **What it costs and what it moves.** A window decided by attempt 62 stands in band zero alone and
    costs what it cost before. No pledge an agreement makes is refused for want of room, and no
    number enters the Decree; the band is derived from the attempt and from the bound of a point.
    The domain's input is 45 B for every band, band zero included, so the points of band zero move
    with the width, and the vectors of "How a message crosses a link" are written at the new width.
  - **The word.** In this set a lock is what a machine puts up in coins to be raised and what a
    violation forfeits ("The forfeit of a node lock, and the evidence that moves it"); a pledge is
    the signed word of a part in an attempt and is no lock.

Two things are also owed with the construction, derived rather than chosen:
- **The width of the abscissa.** A proposer who grinds two names to one abscissa makes their pair
  extract nothing. The birthday cost of that is 2³² in `proof_field` and 2⁹⁶ in
  `proof_challenge_field`, both below `proof_security_bits`, so the abscissa must be 256 bits wide.
  The line is taken over a field of that width, so the value a pledge or a heavy attestation carries
  is four elements of `proof_field`, 32 B, the width of a digest of the proof hash; that is the
  width of `line_value`. Four is the least degree over `proof_field` that reaches that width, as three is the least that
  reaches the bound of `proof_challenge_field`. The field itself, with the polynomial that defines it,
  stands among the parameters of the scheme as `proof_line_field`; the domains enter with the construction.
- **The domains** of the lock-opening value, the slope, the abscissa and the commitment. They enter
  the registry with the construction and not before ("No domain awaits a document"), each with its
  row of the Registry and its owner. The first three entered with the derivations above:
  `mt-line-opening`, `mt-line-slope` and `mt-line-abscissa`, of the `proof_hash` family, owned by the
  row of this section. The commitment enters with the layout of the lock and its tie to the candidacy
  (Q6).

**Invariants of the evidence of a forfeit:**

- A forfeit moves the lock of the machine whose secret yields the convicted part, and no other lock. Evidence under the part of one machine presented against the lock of another is refused, and that lock stands untouched: a lock bound to another naming half, another `node_commit` or another secret.
- A machine the evidence does not convict keeps its lock. Such a machine holds a part outside the pair, the part of another window, or a part whose pledges contradict nothing. A machine whose part only the third pair convicts keeps its lock too (record 296): it loses the coin of that window and nothing else.
- Forged evidence is refused:
  - a pledge whose signature does not verify under its `answering_key`;
  - a pledge whose proof does not verify under the description of the pledge against its public input;
  - a pledge whose key is not the key of the heavy attestation of its part in `W`;
  - a heavy attestation whose proof of presence does not verify against the root of the electorate of `W`, the name it attests and its `line_value`;
  - two objects under two parts, or of two windows;
  - two objects that are not one of the three pairs: a repetition on one name, a light attestation (which pledges nothing), an open pledge of a later attempt standing on the attempt of the closing pledge or after it, or a repeated round nullifier under one beacon.
- The third pair is refused as evidence of a forfeit, and no lock moves on it (record 296); it stays the sanction of the window's coin that Consensus states.
- Incomplete evidence is refused, and no verifier completes it from what it holds or hears: a pair lacking either object, either signature, the proof of either pledge or of either heavy attestation, or the heavy attestation of its part in `W`.
- Evidence presented after the close of the challenge of `W` is refused, as Consensus refuses the pair itself.
- A lock is consumed once. Every first or second pair under one part of `W` convicts that one part, and the parts of several windows of one machine convict that one machine, so together they forfeit one lock. A forfeit of a lock already forfeited is refused. A lock is consumed by a forfeit or by its release, never by both. When a release may come, and how it is ordered against the challenge of the last window the machine lived, awaits the author.
- A forfeited lock is burned (record 233). It goes to no one: not to the presenter of the evidence, not back to issuance, and to no other lock.
- The machine whose lock is forfeited is excluded from consensus (record 231). The extracted value joins no other part of that machine, so no verifier can find its later parts by reading them. How a verifier keeps those parts out of every later cement without naming the machine awaits the author (Q3, Q4).
- A forfeit names no person, no record and no note that funded the lock ([I-6], [I-17]). The pair itself names no one (Consensus, "Observability ledger"). Whether a forfeit may disclose which admitted machine's lock it consumed awaits the author.

### The post-quantum handshake, in integers

Roles are fixed by the connection: the side that opened it is the initiator. `pk_i` and `pk_r`
are the ML-KEM-768 encapsulation keys of the two sides, `ct_i` the ciphertext the initiator
produced to `pk_r` and `ct_r` the one the responder produced to `pk_i`, and `ss_i` and `ss_r`
the shared secrets those ciphertexts open to. `id_sk_i` and `id_sk_r` are the answering keys
of the two devices — the ML-DSA key each derives from its own secret under the node domain above,
and the only key either signs a handshake with; a device that signs a handshake with a branch of
a person's seed binds a handshake to a person and is a defect.

```
transcript = SHA-256("mt-noise-pq-v1-transcript" || 0x00 || suite_id_2B_LE || id_pk_i || id_pk_r
                     || pk_i || pk_r || ct_i || ct_r)
master     = SHA-256("mt-noise-pq-v1-master"     || 0x00 || ss_i || ss_r || transcript)
k_i2r      = SHA-256("mt-noise-pq-v1-i2r"        || 0x00 || master)
k_r2i      = SHA-256("mt-noise-pq-v1-r2i"        || 0x00 || master)

sig_i = ML-DSA-65.Sign(id_sk_i, "mt-noise-pq-v1-sig-i" || 0x00 || transcript)
sig_r = ML-DSA-65.Sign(id_sk_r, "mt-noise-pq-v1-sig-r" || 0x00 || transcript)
```

**What the transcript covers, and why each part of it is there.** A signature proves possession of
the key that made it and nothing about which key was meant. If the answering keys stood outside the
transcript, a third party could relay the encapsulation untouched, put its **own** answering key in
the first flight and sign with it: nothing would be readable to it, and the responder would finish a
channel it attributes to that third party while the bytes belong to the initiator — every credit,
every count of participation and every place in a ring going to the wrong machine. The suite stands
inside for the mirror of that reason: a value negotiated outside the transcript is a value an
intermediary may lower the day a second row of the table exists. Both flights name the suite, and a
pair naming two is refused before a key is derived from either.

**Invariants of the handshake:**

- The order of folding is fixed by role and not by arrival, so both sides compute one master from one exchange.
- The transcript covers the suite and the answering key of each side, so a channel names the two keys it belongs to and a signature over it cannot be carried under another name.
- Both shared secrets enter the master, so a channel is secure if either encapsulation was.
- The two directional keys come from the master under distinct domains, so a key protecting one direction never protects the other.
- Each signature covers the transcript, and the two signatures take distinct domains, so neither can be replayed as the other.
- A side that cannot verify the other's signature over the transcript it computed carries nothing.

### The derivations of a note

```
note_pk        = SHA-256("mt-note-pk" || 0x00 || note_sk)
nf_sk ‖ nf_pk  = squeeze("mt-key-halves", limbs(nf_key), 2)
cm             = sponge("mt-note-cm", cells(nf_pk) || limbs(value_16B_LE) || limbs(note_pk) || limbs(rcm))
nf             = sponge("mt-note-nf", cells(cm) || cells(nf_sk) || element(position))
```

`squeeze(domain, elements, 2)` is the sponge of this document absorbing once and squeezed twice:
the first four cells of the state after the absorption are `nf_sk`, and the first four after one
further permutation are `nf_pk`. One absorption is the whole of the point. Two derivations over
one preimage would read the same key twice, and a circuit reading a secret twice is a circuit
where the two readings may differ: nothing in an arithmetic of rows ties a value at one row to a
value forty blocks on unless a column carries it. Here the key enters once and the second half is
what the state became.

`sponge`, `limbs` and `cells` are the doors and the readings of the proof hash: the circuit of a frame proves the three
derivations below the payment key, so they are of that family, while the payment key — which
nothing proves and anyone may compare — stays SHA-256. `value` is an unsigned sixteen-byte
little-endian amount, a count of coins — the coin is the unit of value Value names, and one
coin is the amount one — `rcm` a thirty-two-byte blinding factor drawn from a cryptographic source,
`position` the unsigned eight-byte little-endian index of the leaf the commitment occupies.

**Invariants of the derivations:**

- `cm` binds the naming half of the nullifier key and `nf` takes the spending half, and both halves come of one absorption of that key: the nullifier of a note is therefore one value, and a second spending of one note presents the same value and collides with the first. Two wrong constructions are refused here rather than described. A commitment binding no half of that key lets its own holder spend one note once per key drawn. A nullifier taking the limbs of the key where this takes a half of it lets the same holder do the same, and by a route the first refusal does not close: a circuit proving both derivations reads the key at two rows dozens of blocks apart, and two readings of one secret are two secrets unless a column carries the value between them.
- `nf` takes the half the commitment does not name. Were both derivations to take the naming half, anyone holding a note's commitment and that half — its payer, who computed the commitment — could compute the nullifier and burn what they paid.
- `nf` takes the position of the leaf and never a value the sender chose; one commitment at two positions yields two unrelated nullifiers, which is what keeps a sender from making a recipient's note unspendable.
- The position enters as one element, for the reason the window of a right and the amount of a frame do: two limbs of one number are two witnesses inside a proof, and a non-canonical pair summing to the same position would yield a second lawful nullifier of one note — a note spent twice by encoding alone. One element admits one encoding.
- The halves are one-way, so joining a commitment to its nullifier requires a key the network never holds.
- `rcm` is fresh for every note; a repeated blinding factor makes two commitments comparable and is a defect of the emitter.
- The widths above are exact: a differently sized amount or index yields a different digest and a frame that no verifier accepts.

### Frozen vectors

Every vector below is computed from the rules of this document and from nothing else.
An implementation that reproduces them has the hash layer right; one that does not has it
wrong, whatever else it passes.

**A vector names the wrong implementation it catches, and one over a degenerate input never
stands alone.** Thirty-two zero bytes, one repeated byte, a tree of one leaf at position zero —
each reads the same under a permutation of itself, so a vector over one of them accepts an
implementation that reverses what it reads, and that implementation then diverges on the first
real value. Where a vector below stands on such an input, a second vector stands beside it over
an input no permutation of which is itself, and the prose says which wrong reading the pair
rejects.

**The domain-separated primitive.**

```
hash("mt-op", [0x11 x 32])
 = 50e711d4d67814251fdccb022b04f17a6437d6a4ce2818a822e2a80e28dfe308
hash("mt-proposal", [0x11 x 32])          # same input, different domain
 = c1fbc6418289edabcbea889f671e6105a939035d3f9f833a5be3b570142e2038
hash("mt-op", [000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f])
 = d450ca6bd76af1cfe805542da23a714bb033b080ac2673d3e1f16f4c950fdfbc
hash("mt-proposal", [000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f])
 = 59228d800875b3072396cb4424699822ef5ebd9845a3657b5c6306828f0e0a82
```

The first two differ in every byte, which is the separation the NUL byte buys. The second pair
stands on a part no permutation of which is itself: a part of one repeated byte reads the same
backwards, so an implementation that reversed what it hashes would reproduce the first two and
fail these — which is the whole reason a vector of a repeated byte never stands alone.

**The empty values of both trees.**

```
empty_leaf                = 04ab7bd805dd7b2d30670eb1e2b5a67f76759dab83a0f0df17f2ddf2986d4914
empty_internal(1)         = ecac2a25cc4b5f4559596ddd51e9d9c2421b9dcf90e080ab2d73af63a2d2fc45
empty_internal(40)        = 8b254df2236b5d6d6f1e6d1400974c9949ce1886829b15a150f8583c5dc76ce0
empty_internal(256)       = 6249214087bea24b692371726558a82f5248e3daaef8dd20361e5f5bcfcfcc08
```

**The empty values of the fabric, and a fabric of one leaf.** The fabric folds under its own
two domains and under the proof hash, since a path of it exists only as the witness of a proof,
so its empty internals are its own and are not those above. The leaf absorbs the limbs of the
observation, the same door every use of this family takes.

```
fabric empty_leaf         = 485f6d5a17733be019f832a9afdef807a2de802b0d67e6b7f86215cfec9f9769
fabric empty_internal(1)  = 684377c2c30f21f2c7ce5001e0cb7bcf2d66b2a682be12f4d3c679dce9dc56d2
fabric empty_internal at note_tree_depth
                          = f8ce8823cb84fefd02b91dfee0952fce699b60819fb30dc2cd091418f600a4b0

witnessed commitment = 0xE1 x 32, W = 1000, blind = 0xE2 x 32
fabric leaf               = 3e2072a1cbd0e1316c39fb92e5bddae40c6c51ef29bcc69f3ff4d6fb5038190e
fabric root (one leaf at 0)
                          = b738d9334e9ee3ebf60d9ca485df936b931e4728ca26a6cd4b1d510e0c2ffbf4

a second witnessed commitment = 0xE3 x 32, W = 1001, blind = 0xE4 x 32
fabric leaf (second)      = c83cb66da7d730e5aa4e3fbd7b29b463d3db05887654f519c98fb6629952ec48
fabric root (two leaves)  = 68ff0f2d0e60617574d87a2cd935c5893079cc3dca1bd178b5469109396b74f2
```

An implementation folding a fabric under the Merkle domains, or under SHA-256 beneath its own
domains, produces a different root from the same observations, and these values are what catch it
before anything is committed.

**A root over two leaves is what pins the pairing, and a root over one leaf cannot.** At one leaf
there is no genuine pair: every level folds that leaf with the empty of its own level, so an
implementation assembling a level with the pair folded right-then-left reproduces the root above
and parts from this one. The second observation carries its own window besides, so a leaf that
took the window of the first parts here as well.

**An empty note tree, and the same tree after one commitment.** The commitment, the halves of
the nullifier key and the tree are all of the proof hash family — a spend is admitted by a
verified frame alone, so their one judge is a verifier of a proof — the leaf absorbs the four
words of the commitment, the empties are the tree's own, and an implementation folding any of it
under the Merkle domains or under SHA-256 — or absorbing limbs where words are meant — reproduces
none of these values.

```
value = 5 000 000 000, note_pk = 0x22 x 32, rcm = 0x88 x 32, nf_key = 0x33 x 32, a second commitment = 0xA1 x 32
nf_sk                     = 075aa13ad3f9f4dadaddd4c6ab64e5df4487aafef28fbe58c59a20faffca28a4
nf_pk                     = 011f0770c754d876439c2514399f5f19a82135825388b0aac90b3706b5ccfe14
cm                        = 8b3e18e90778fd34db944685f6a88427f98d5f416722152d6dae9418bf2ae94d
note_root (empty)         = ddb45d51743c16e0cafd22c7ad96151c76976b07a7ddd76aef16b38ddae09e5e
note_root (one leaf at 0) = 62725819a6c8e362c61e9aef1401dbe797e570f4dd0a755358beac24eae4234e
note_root (two leaves)    = 1c0e91d47e6a111419375e5c36bf59953fd76790c6dd6fcc419649863a657232
```

**The last of those is what pins the pairing of a level.** A tree of one leaf folds that leaf with
the empty of every level and never with another leaf, so an implementation that assembles a level
with the pair folded right-then-left reproduces every value above and parts from this one — and
then computes a note root no other implementation computes, at the first window holding two notes.
The vector of the node of a proof pins the order of the two arguments of the fold; it does not say
which of two neighbours of a level is the left one, and that is what this value says.

**The walk of both trees, pinned away from position zero.** A tree of one leaf at position
zero exercises no bit of a walk — every bit of that position is zero — so the vectors above
cannot tell an implementation reading bits from the wrong end from a right one. These five
values can. The key and the position below have bits at both ends, and a walk that reads the
key from the wrong byte, takes the wrong bit of a byte, or folds left where right is meant
reproduces none of them. A proof too long to stand raw stands as the SHA-256 of its canonical
encoding — the bare function, since what it fingerprints is already the output of the
domain-separated layer.

```
record key = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
record = 0xAA x 8, absent key = 0xFF x 32
sparse root (one record)  = ee472331bbb71e0deccd71e6ffe3e7bd3a5c5683153987338329007174e46811
record proof, SHA-256 of its encoding
                          = c4cfcb080495e93ffc90359eea6104e5a3b35858537af3d01015befe7368a3c6
absence proof, SHA-256 of its encoding
                          = 1d669f6e303041eb273eb3d5bbcc51f9341b9e0b2ae4a5669c036b5b8a592a41
```

**The tree of records, which a circuit walks and which therefore folds under its own pair of the
proof hash.** The values above are of the sparse construction under the Merkle domains, which the
tables no circuit walks keep; the same construction, the same key and the same record under the
record domains give none of them. An implementation folding the tree of records under the Merkle
domains, or under SHA-256 beneath the record domains, reproduces nothing here — and the last of
the four pins the walk, since the key has bits above the first byte and below the last.

```
record empty_leaf         = 1864821258cbc57d9016a6cd43d3042e0fd165b7718edf5d6ef0394b23eab401
record empty_internal(1)  = bb3813e21aebf25d85278237fcf59bec349e9c263b92bac3236584bcc3ba2bec
record empty_internal(256)
                          = b24969faf6830c191d017706a4f64b08b4dcee056474f0c510a39004552cab37
record root (one record)  = 3a290efee6666be7a67b661204287d28dd7a4f729135a5f064ca0e19f10586c7
```

**The walk of the append-only tree, at three leaves.**

```
commitments at positions 0, 1 and 2 = 0xA1 x 32, 0xB2 x 32, 0xC3 x 32
append root (three leaves)
                          = c797c80c949e193285729df3a670ab8f2072ffef0f34606166e4c004cb10be36
proof of position 2, SHA-256 of its encoding
                          = a955e90abf0c10b301549bb4952d59b62203903a62035f2ca32de3b079128439
```

The record proof carries an all-zero bitmap and no siblings: one record fills no sibling on
its own path. The absence proof diverges from that record at level 255 — the highest bit the
two keys disagree on — so its bitmap sets that one bit, the most significant of byte
thirty-one, and carries the one sibling standing there. The proof of position 2 carries the
empty of level zero, the fold of the first two leaves at level one, and the empties above.
Each value binds what the prose of the constructions states: the bits of a key or a position
read from the least significant, byte by byte from the first, a zero bit folding left and a
one bit folding right.

**The horizon fold, at three of its reach.** Leaf 0 walks its bytes upward, so a reading from
the far end answers elsewhere; the next two are repeated bytes; every leaf above the three is
the padding of the fold below the reach — the empty leaf, a shape no standing fold takes,
exercised here so the padding rule is frozen with the rest. The three lines after the root are
the three named wrong implementations — the order of the stride reversed, the absent leaves
dropped and the fold taken only to the width of what is present, and the doors of the note
tree in place of the horizon's own — and each answers elsewhere, which is what the vector
measures.

```
leaf 0 = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
leaf 1 = 0x21 x 32
leaf 2 = 0x22 x 32

horizon_root (three of the reach)
                          = 7b163740b7f98eb22eee50fb061f9787a0eb0efe58fe9debe2aff27a864c819c
horizon_root, the order reversed
                          = 32b0bc09f92f93ec8f110a9595c758d8952b34233708e196ff320f56f3060159
horizon_root, absent leaves dropped
                          = bc430c57a154b35ca248e66423634a243d376f7e790de1f302034ac6d6a14db1
horizon_root, under the note doors
                          = 4b3f158f844a06967c4fdd4032c31f53a4020102958b82513827a8e584d70e46
```

**A nullifier, and its independence from the commitment.**

```
nf_key = 0x33 x 32
nf(position 0)            = cab435f7a7c58a35181ef636557f3e44e18a0e757f05eed554b5b0744ebac73e
nf(position 7)            = 0c11b79ba4ee91b2686b63d266dd21ab36258f45954193d74f5f40dc79ab4b79
```

One commitment at two positions yields two unrelated nullifiers — which is why the position, and
not a value the sender picks, decides it. The wrong implementation these two catch beyond that:
one taking the naming half where the set takes the spending one reproduces `cm` exactly and parts
from the tree here, at the first nullifier it writes. What the construction gives is independence, never a
count of differing bytes: two digests of one function agree somewhere often enough that a claim
about their bytes would be a claim about luck.

**A tag and the labels of its steps.**

```
shared_secret = 0x44 x 32, W = 1000
tag                          = 1d99467017fe1d0cc7c7ba29df6fd1b6
pipe_secret(W + 1)           = 1defe2877d6630f056ebaff2b6b94cd31baeb24747346b542ff5f31fe35db94d
pipe_secret(W + 2)           = a84614faf98fddb2d569aaf7a8bd3d6ff8b20fb5c22e72338af4558993176798
tag (W = 1001)               = 5bcdd791565a49a2764157d72a8450dc
tag (W = 1002)               = 7d15bb090586a75f651ab429b86e62f4

handshake_secret = 0x51 x 32 for one pair, 0x52 x 32 for the next
step_label(first pair)       = 4b8cb5c6442a52d0750bfb4fac0ba39d
step_label(second pair)      = 401d8ab71a2e2554ab30c11aab1ae97d
step_label(first pair, W + 1)= 1cc3ac539a8b1d2701e489455a8b04d5

test_secret = SHA-256("mt-vector-pipe-secret")
            = a225e0b87df8a5568331badccfa4b217aaee3c7077b6021a52fab89d8856ef56
pipe_secret(test_secret, W + 1)                  = 92aa039f4d82a59e12a6e65eacaa998fa06455b63e4aef6405556f9e99e4c666
tag(test_secret, W)                              = 42b13c7133439d4222c9bdf52b5f27b0
tag(pipe_secret(test_secret, W + 1), W + 1)      = 39e4abcd4db155761253830a3afa9959
pipe_key(pipe_secret(test_secret, W + 1), W + 1) = eed13b68a4fecd9c91ff7ddca945f8289b62b02835f95260639616d2ba236ba8

negative: substituting a public 32-byte value for the shared secret
tag(public value 0x55 x 32) = 783b2b17dffaab016d1aca852f60ea3e
negative: a secret that did not walk, and one walked by the height of the window
tag(unwalked secret, W = 1001)    = c146445f67c990e25256dd88dfb39a49
tag(walked 1001 steps, W = 1001)  = 11062c7ece61d640abf601e486170994
```

The negative lines are normative: an implementation that derives a tag from anything public
produces the value frozen for that mistake instead of the first, and fails this comparison; one
that keys the second window off the established secret, or walks it once per unit of height rather
than once per window, produces one of the last two instead of `tag (W = 1001)`, and fails it too.
The secret of the first block repeats one byte, so the walk and the key stand a second time on
`test_secret`, a value no permutation of which is itself: an implementation reading the secret from
its other end reproduces the first block and parts from the set here.

**The right of a machine, and the moment of extinguishing it.** One absorption of the machine's
secret yields the half that names it and the half that spends; the leaf it stands at is over the
first, its nullifier over the second, and the moment is the second squeeze of that nullifier's own
absorption. The wrong implementations these refuse: one deriving in SHA-256 reproduces none of
them; one taking the naming half where the spending one stands reproduces the leaf and parts at the
nullifier; one absorbing the secret a second time for the moment reproduces every value here and
still admits a machine that answers with two secrets.

```
machine_secret = 0x77 x 32, a second naming half = 0xB2 x 32
machine_sk                    = e1e356a2ace4106e5a1a6412daed903689a8548e0d24494325d826ed26960b23
machine_pk                    = b4defe598cb0b40af9685bc131eb9186d8f88435de5113ff2485c4cf5f6cdeb6
admitted_leaf                 = 730f64c5ce672a2134147f8c37d63db3e12962fb81f481eee12d0f78ab49ca31
admitted_root (empty)         = 9a7b8fd0429574d96fe4fcf30dcac47684ccb3414e9adbab88b2a3cc2f6a4338
admitted_root (one leaf at 0) = d119df71887e96e06f6ad1d9930c1c76059708353f0fd8b8122cae8b2068e97e
admitted_root (two leaves)    = f6af2f8e3e06a193fb7536cd721ac0754753817e905d3c09eb1d60ded8b76f76
credit_nf(1000)               = 5b2123e556ede6e1fdf0c2f99baa381a11df3d96b8f1928567c8490e39cb9108
credit_nf(1001)               = e4bc0bc3b4642713f3980387443d704e7e917e9d1953223333ca30b9f4990a24
claim_window(1000) = 1000 + 1284 = 2284
claim_window(1001) = 1001 + 368 = 1369
part_nf(1000)                 = 90e8ec8b288c98ade06b92a0160ab271ab82032e45a283d8ce15f971c711531d
credited_leaf(1000)           = 2f1c2ed85f87c48fae91c1df82d27dd1ea04b4f1051193750b4be3edc2f4a472
credited_root (empty)         = 1655d5c14345e38d6e109f95b56ac3f5c817c573899cca32ab14d821b6a35f73
credited_root (one leaf at 0) = 55be983245eb2d47c1df90a20085beaa755bc30e3c8d00ee4b6e4d9c8689986f
credited_root (two leaves)    = 35c3cc5f188c1af3791caa2aab5f8f641fc388c53c89f76efbeab33d2b459897
```

The tree of credited rights stands on the parts of this machine: `credited_leaf(1000)` is the leaf
over its part of window 1000 alone, which is what an implementation writing the window beside the
part parts from, and the root over two leaves holds its parts of windows 1000 and 1001 at positions
0 and 1, in the order they were credited — two windows of one machine are two leaves, and the root
pins the pairing of a level as the root of admitted machines over two halves does. An
implementation taking the naming half where the part stands reproduces the roots of admitted
machines above and none of these.

The last of them holds the naming half above at position 0 and the second at position 1, each
through the leaf door, and **it is what pins the pairing of a level**: a root over one half folds
that half with the empty of every level and never with another leaf, so it says nothing about which
of two neighbours is the left one. An implementation assembling a level with the pair folded
right-then-left reproduces every root over one leaf this document holds and parts from this value —
and then computes a root of admitted machines no other implementation computes, at the moment a
second machine is admitted.

The secret is a machine's own and Consensus states that nothing published ever carries it; the value
above is a stated literal for exactly this reason, so that the vector is reproducible from this
document while the real input never is.

**The vector of a candidacy.** A record of the layout of Canon carrying the right of the branch
of the vector of the two rights, standing alone in the tree of records at the key its commitment
is, and a machine's secret beside it: what the public input of a candidacy holds and the values it
is assembled from. The wrong implementations these refuse: one placing `operator_nf` anywhere but
after `own_height`, or writing the branch itself into the record in place of its sponge, parts at
the commitment and at the root over it; one taking the naming half of a second absorption of the
secret in place of the second squeeze of one parts at the half; one ordering the public input
otherwise, or leaving the machine's commitment or the suite out of it, parts at its digest.

```
machine_secret = 0x5A x 32, operator_secret = 0x22 x 32, window = 1000, node_commit = 0x66 x 32, suite_id = 1
record = segment_bitmap 11, last_active_segment 7, opened_window 990, own_height 4, operator_nf of operator_secret, fabric_root 0x11 x 32, suite_id 1, current_pubkey 0x44 x 1952, blind 0x33 x 32
operator_nullifier of the candidacy = aeea4d6acef552552144f4decd573616b555b73b0ddee09b37659870a2898fc0
record_commit of the candidacy      = e795f229b47d3a835faef33f30e1e8d581eea2bbf75e41940e5213c4e686d543
record_root of the candidacy        = 397e75dc054ebcebed04cd7107bffa17a8502639955e33b5ebb1b8169494bac2
naming_half of the candidacy        = 34f171bc0471f01de0765a81708f5daaec4117ca0610e2e89f43a7ff9e7b9755
SHA-256(public input)               = df4a8b89d020b8bb07d24272a9f607a5245728ca958be140df6d95631dbdb9da
```

**The birth of a seed, end to end.**

```
entropy                   = 0x00 x 32
the words joined by single spaces, and by nothing else
SHA-256(the 24 words)     = 69be79ef3c28f55d7cb84db2dd3c18dfff45eeefebd09b8c5f7f3489b8ba09ac
SHA-256(master_seed)      = f1818e1a354e6020ddf11ed9da140c93f42fdc530c498734e732e6db6e607536
SHA-256(signing branch)   = 095c344ee139b874f0c54ea93603fc06cef984546d0c12b9cbd4ddd281940113
SHA-256(record_pk)        = a1e69b6a4e0c1740c3800852553b1609ab46e8dd48f6b94bfbd81503135fff00

a second chain, over an entropy of thirty-two distinct bytes
entropy of distinct bytes = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
SHA-256(the 24 words of it)
                          = 51f03d9ccd90c12c02b3804d0d0695f7ba64e4de48e261719f55931da24fc806
SHA-256(its master_seed)  = 82ddcce728e45cfe4e66418caf24c5076a59baa16131633568bc9e4135986060
SHA-256(its signing branch)
                          = c67360c0e04c6b38c69abe6f99c7aa3064138088fcf791673ada70b42e3e92e1
SHA-256(its encryption branch)
                          = b7cd19502047d8946a0bf5fd3c9fa3487ff88a15a1d44e77e3cf430f6098697b

the mixing of four living sources, by their place in the table and their own lengths
living sources = 0 : 0x01 x 32, 1 : 0x02 x 32, 3 : 0x03 x 24, 5 : 0x04 x 16
entropy_32                = f89ccf6875e8f636774057e55b24f1f5d3753191c44f4f0e26aded865ff47d4a
```

The chain is given whole on purpose: a vector that stops at the seed lets an implementation
pass while deriving the wrong key from it.

**Two chains stand here, and the second is the one that binds.** Thirty-two zero bytes read the
same backwards, so every value of the first chain is reproduced by an implementation that
reverses the entropy before packing it into words — and that implementation then writes different
words for every real seed, which loses a person their own phrase. The second chain stands on an
entropy of thirty-two distinct bytes, where the bits stand at both ends: reversing it, taking the
bits of a byte from the least significant, or stretching the text of the words instead of the
entropy each produce a different value of the second chain while leaving the first untouched. Its
last line carries the expansion of sixty-four bytes, so the counter of a second block is bound
too. **A vector over an input that is its own mirror never stands alone.**

The mixing beside them stands on four sources of different lengths at named places, which is what
catches an implementation writing a length of the wrong width, admitting a source that is not
alive, or moving a source to another place: each produces a different value here. The first three lines are reproducible from
PBKDF2 (RFC 8018) and HKDF-Expand (RFC 5869) with no Montana code; the fourth adds
ML-DSA-65 key generation and nothing beyond it.

**The chain ends at the key and goes no further.** A value standing for a person past their
key — an identifier derived from it, however named — is the quantity [I-17] forbids outright,
and a vector reaching one would oblige every implementation to compute it. What a record
answers with is a key; what stands for a person is nothing.

**The fingerprint compared out of band.**

```
identity key = 0x66 x 32, iterations = 5 200
fingerprint  = 00534 22536 46923 62969 86064 85215
```

**The nullifiers of the two rates.** The nullifier of a right to a coin stands with the right it
extinguishes, where its two halves are derived.

```
rate_secret = 0x55 x 32, act_secret = 0x66 x 32, W = 1000
rate_nf(W, i = 2)         = a8a93575275a22c234290aa51717ced537e24014719decd6b3f97268d00ce15e
rate_nf(W, i = 3)         = 920a6cf0c84798d7eab5b7e6a3e6a3b530163e54a029c0f080488d59bba37518
act_nf(W)                 = 8816f366666263bf7a12076ef05815b037a60abe66ff21999daaf246df11129a
act_nf(W + 1)             = 6e08f0c78060ee27fb284376f48451b61db76318a87196e5035c81bc58f70110
```

Two positions of one window give two unrelated values, and one branch across two windows gives
two more: the bound holds inside a window and joins nothing across windows.

**The round, the beacon, and the chain of a sender.**

```
machine_secret = 0x77 x 32, W = 1000
runner_key_seed           = 2c7b73b5b598bf841cc5d6a389e78657ce7ace1b3c9b4eab3debb920854e101e
part_key_seed             = 23eb0952bd165b4cb0f8bb6b0e549a4e7d2d4e301802f35734b1a32eb15aaf57
```

The two key seeds differ under one secret and one window, which is the separation the two
domains buy.

The vectors of the round are self-contained: every input derives from a stated string, so any
implementation reproduces the table from this document alone.

The strings below are inputs of a test and separate nothing; they take no row of the registry,
and no derivation of the protocol reads them. They are therefore plain SHA-256 of the literal,
**without** the NUL of the primitive: the NUL delimits a domain separator from what follows it,
and a string that separates nothing is not a domain.

```
test_machine_secret = SHA-256("mt-vector-machine")
                    = 569c721ea193dc9fbffa78d938a8eac29af86dcc6c1f40e6fe5c450120a308fd
test_aggregate      = SHA-256("mt-vector-aggregate")
                    = 5794ec157270d5c8364ca9aead3d4cbef0fbd714297077ea029111b127781dca
test_prev_beacon    = SHA-256("mt-vector-prev-beacon")
                    = e7b1b25222707aca10af6a07b6adceb4c6fc7580bdbe965cddf82ad8133f5c7f
test_answering_key  = block_i = SHA-256("mt-vector-pk" || i_4B_LE), i = 0 … 60, concatenated (1 952 B)
                      SHA-256(test_answering_key) = 53d0417583a05cfdced15d3dcfbfa0657fddc860ed59c2c86638c38cda1be245

round_elig(part_nf below, test_aggregate, j = 0, r = 7)
  = 0a1509175bb9075e37f0b7d0f06620240ef424ef8c6f60f8a18a624424b3bc05

key_digest(test_answering_key)
  = 3888ef390fd9b3bd0cbc3c0cbd35ddca12969aac512ea24e39eb964fb21b0707

runner_digest(test_answering_key)        (the same key under the digest domain of a runner: one key, two duties, two digests)
  = 13aedba22e149bfa704688fd23916b3d46178977c86fa3214140d96240c217ef

beacon_id(W = 1000, j = 0, r = 7, previous = test_prev_beacon, cement_aggregate = test_aggregate, cement_count = 2, cement_votes = 1)
  = 9e7b3876e53354deff5e04dd7f2770e2a162ad43ab1595059fcf77ef3ab21d64

round_nf(test_machine_secret, beacon_id above)
  = 638fa4aa9bfcea5aafeaaf1778ef56419588465c18c1fbe37d5d807b7ab462f1

part_nf(test_machine_secret, W = 1000)        (what the draw of a round reads, and what a proof of presence asserts)
  = df2934b97d4d17a49cd1a010f71c40d6da6db5182b8d92a93ba6e234b6b1bc92

Coverage theorem: (255/256)^284 = 0.329049 ≤ 33/100 < 0.330340 = (255/256)^283
```

**The seal of a step, and the placement of a sender.**

```
owner_secret = 0x99 x 32, inner = 0x5A x 916, then inner = 0x6B x 916
path_id (first inner)     = 987275243eca62412618c55d69b2a1a6
path_id (second inner)    = fcdf2fc03faee3894c3238b9d6d21c93
relay_seal (first path)   = 1b847b1f5192a58d17722ab7191d58b7
relay_seal (second path)  = dbca283d657a22e135671435e71b36cf
seal_slot (first seal)    = 6
seal_slot (second seal)   = 14

sender_secret = 0xBB x 32
ephemeral_id(W = 1000)    = e0c80bc1e2aed9036f057863b56a09fd8cd90405ac1dbacd606008cf06b43cbf
slot(W = 1000)            = 32
ephemeral_id(W = 1001)    = 62a174f307d8db5b3529fc9fb9a0216a32e04ca0b5f5eaaff0047cf77a4f7894
slot(W = 1001)            = 34

ephemeral_id(W = 1 935 360)  = 354c059669790156d450f1304c1901e57b7dd1a47f8b2f8d5dc78c55e6faddfd
chain(W = 1 935 360)      = 0
ephemeral_id(W = 13 547 520) = d6ec8f75faf35bbfe194a9234301f0081f2563fa788798f04666c2eb395ffeba
chain(W = 13 547 520)     = 1
```

One owner on two steps of one path yields **one** seal at **one** slot, because both stand on the
pipe layer the path carries unchanged and not on a label the hop before it chose; two paths of that
owner do not join, because their pipe layers differ. That is what makes a count of marks a count of
owners rather than a count of machines. One sender occupies unrelated positions in consecutive
windows. The two later
windows are the first of the second chain and the first of the eighth: below the first of them
every count of chains is one and every implementation agrees by accident, which is why the chain
is pinned where the counts part. The chain reads bytes eight through sixteen of the ephemeral
identity, least significant first; an implementation reading the first eight — the bytes of the
slot — or reading its eight from the other end fails both windows above.

**The nullifier of a reach into the space of slots.**

```
lookup_secret = 0x88 x 32, W = 1000
lookup_nf(W)              = 1bc58d1f29771ebde0d6591d6a771158f2aeeec154f0c8f8448ab8ad1dc5541f
lookup_nf(W + 1)          = 54f816fad3496caab8665459e9a2282bef606f8528849fd95434a4d7eaf704b0
```

One branch across two windows gives two unrelated values, so a reach of one window joins to a
reach of another by nothing.

**A name: its slot, its chain and its commitment.**

```
name = "alice", name_own = 0xEE x 32, blind = 0xDD x 32
slot(name)                = b5793a0d4f7f0737ebffb1374d24d3eed05efef5bd63eb1e4b03d81652c2575e
link(127)                 = 83be15d760052903e3b1a2d304f56861ad92b8fed97a0b08452c6eb029fe1b5a
link(0), the published tip= b49373b194e6358022b8fbcbecb5beccdd4f0b275d1ccd53be130f76a1367a8e
commit(slot, blind, tip)  = 929fccf5c511d3d1123707db473cf21732a9349bcb578ddea91ca08b2d9dae41
```

The tip is `link(0)` after one hundred and twenty-eight foldings of the branch, and each renewal
walks one step back toward it.

**A channel: its slot, and the head of a publication.**

```
name = "alice", master_seed = 0x11 x 32, previous = 0xAB x 32, body_root = 0xCD x 32, W = 1000
channel_slot(name)        = 21d9d4d5dd4245cb6844bacd463f9ec4e8cf0058f5d2a4f1bd03ecad26d6610a
SHA-256(channel_seed)     = 7225eb3ba9d07a5c3e54a25abff4a7f88a81849521b9615b0e8b438de016b17f
head(W)                   = 1912f7e2e761cdada560fb0170ddeb54365a3f5548692932e83c320e101da0f2
head(W + 1)               = 7cdd3fac87481f6bd9be451615c140bad8edbbf19df1e0ebe6dcf49597769682
channel_point(W)          = f76164012d5601ab75dc478181dd2a13
channel_point(W + 1)      = e4145e07ad3cd0a1bc747e7ae3222ebb
```

One written word gives two unrelated slots: the slot of the name above and the slot of the channel
here, and neither is computable from the other. The two points of one channel are unrelated as
well, though one slot stands behind both. What separates them is the domain each takes, and the
frozen values are what an implementation compares — a count of differing bytes is luck and is
claimed nowhere in this set. The key itself follows the generation
its suite fixes, so what is frozen of it is the seed that generates it.

**The commitment standing for a machine.**

```
answering_pk = 0xA1 x 1952, suite_id = 1, blind = 0xB2 x 32
node_commit              = 08e640011db3702bb5ea5f1a3ea6aa62d7aa274b4acfcada27346e093d60fdc5
```

**The nullifier of a part, and the identifier of an application.**

```
machine_secret = 0x77 x 32, W = 1000
part_nf(W)                = 90e8ec8b288c98ade06b92a0160ab271ab82032e45a283d8ce15f971c711531d

app_id("montana")         = a3ededc374700026f1f872bebf3ba0199103f4082ea609688f82e69e64fa8a82
```

**The aggregate, the ticket and the two orders.**

```
cemented set = { 0x10 x 32, 0x40 x 32 }, W = 1000, machine_secret = 0x77 x 32
aggregate (non-empty)    = 673a9549b24ae601ebf3e3aa8d5215883518cbcf9fcbaeea3e4e7fb67a3d98de
aggregate (empty set)    = 5d25d6189f62e347d8075dc3485e31e66e4c67492f1b25c1131a57d9e1af62f7
ticket                   = d2ca93d9be5af8ee3cad183f185fea7df9925946a3006ce84d5d54d9fcd9884b
selection_key(0x10 x 32) = 8878a966c5c9952f92d873170044c4d25a2e8c3c398eab4626979591e2321512
registration_key(0x40 x 32) = 801171079fc782bdd6d28cef81dd3c1ec30db517b59d6e7fbc78a67c936ff9f2
```

An empty cemented set yields an aggregate unrelated to any non-empty one, so a window that
cemented nothing is not silently equal to a window that cemented something. The ticket takes the
half of the secret that spends, as four cells, and not the secret's bytes: an implementation
absorbing the secret reproduces the two aggregates and misses the ticket.

**The holder of a tag.**

```
S = { 0x10 x 32, 0x40 x 32, 0x90 x 32, 0xf0 x 32 }, ordered ascending
tag  = 45468cdd9bcdebe6f622c46257c27fe3   ->  holder = the commitment 0x90 x 32
tag  = ff x 16                            ->  holder = the commitment 0x10 x 32 (the ring wraps)
```

**The point of a ring of entries.**

```
own_commitment  = 08e640011db3702bb5ea5f1a3ea6aa62d7aa274b4acfcada27346e093d60fdc5
reversed        = c5fd603d096e3427dacacf4a4b27aad762aaa63e1a5feab52b70b31d0140e608
sender_secret   = 0xBB x 32, P = 3

entry_point(own_commitment, j = 0)   = 991c058327cbe19ac1b39ee1b4b9b0a1f0b8510fcdf662e9810a8084d9ac83be
entry_point(own_commitment, j = 1)   = 6672a6c3c858e84be4dc720ae1bec56580b8fda84efa73c13f9d236e2d21a943
entry_point(own_commitment, j = 23)  = 08e641690b245dc1d89caf7793c94d4110fb4f1eb2c324186ed6f5953d7dd8b8
entry_point(reversed, j = 0)         = 563325bf1386a596e6940f11c13ab1167bb8d0029d8682c48546c5989d8c6c01
entry_point(own_commitment, P = 4, j = 0) = ae1ff71e8e7cdba1c960a2eb52c4df5c978b65c646220957a0ba5713f6143836
```

The first commitment is the one this set freezes for a machine, so the block stands on a value of
the set rather than on a pattern. The second is that value read backwards, so an implementation
taking a commitment from the low end reproduces one line of this block at the other and the pair
catches it; it also stands in the upper half of the ring, where the sum passes the top and the
wrap shows. The five
lines together refuse an implementation that drops the offset and takes the bare point of a ring,
one that shifts by `j` where the rule shifts by `j + 1`, one that does not wrap, and one that
ignores the period of adaptation and holds one set of entries forever.

**A proposal, and its length.**

```
window = 1000; protocol_version = 0x00010000
previous, final_beacon and the seven roots = 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0xAA, 0x88 each x 32
roll = 0xBB x 32
admitted_count = 3; cement_aggregate = 0x99 x 32; cement_count = 2
census entry i of ten: root = (0xC0 + i) x 32, count = i
suite_id = 1; runner_pubkey = 0xA1 x 1952; ticket_proof = 0x00 x 333 888; signature = 0x5E x 3309
proposal_len                     = 339 931
SHA-256 of the serialized proposal = 362e6b4ac382261d876bcd43ea1b9294bf2a63bdebb74f0b0c6db07b14390fe7
proposal_id over the 750 bytes the window decided
                                 = a99a95547645bdb30a4c039352e003ce55b9fcecf5a1b7409482dc209ba26a33
```

The identifier line catches the implementations the scope rule names: one that hashes the whole
object reproduces the serialization hash above and misses the identifier, because the ticket proof
and the signature stand outside the name, and one that hashes through `final_beacon` or
`runner_pubkey` misses it because the beacon and the key of the runner stand outside it too. The two counts, the cement aggregate and the
census stand inside it: an implementation taking the name over the fields the proposal carried before
them reproduces neither line, and one writing the census oldest first, or a root after its count,
misses both.

**A frame, and its length.**

```
spend s: nullifiers = (0x20 + s) x 32, commitments = (0x30 + s) x 32, rate nullifier = (0x40 + s) x 32
proof = 0x00 x 404 576
frame_len                       = 405 056
SHA-256 of the serialized frame = aca4fb73e19afbaff5e63dd9a37e1a823f1c283cad16dc03148a07e0c11a80ed
```

**A notice, and its length.** It carries the nullifier it names and the identifier of the frame
spending it, and nothing else — no key, no signature, no amount and no party — so it publishes
nothing the frame does not publish already and needs no identifier of its own, nothing referring to
it. The nullifier below is the one the vectors of the messages stand on and the frame is the one
serialized above, so both ends of this line are values this set already holds.

```
serialize(notice) = nullifier_32B || frame_id_32B
notice_len        = 32 + 32 = 64
nullifier = test_nullifier; frame_id = the identifier of the frame serialized above
SHA-256 of the serialized notice = 520f523e85fbf2ce7629b38843e40c92666794b1fab64606ca6bbc6c29afaff3
```

**The tag of first contact to a claimed name.**

```
contact_root = 0xCC x 1184
first_tag(W = 1000)       = 45468cdd9bcdebe6f622c46257c27fe3
first_tag(W = 1001)       = 2751a149c51e219b73fadc85ca8b107b
ss = 0x05 x 32, ct = 0x03 x 1088
shared_secret             = 437a425f0c5afe9af675a0767680f6e48be71b22e95fa14aac52cfa2d184a556
```

The shared secret takes the encapsulated secret, the key and the ciphertext in that order; an
implementation writing the ciphertext before the key produces a different value and fails the
line above.

**The branches of the two spaces, from a stated master seed.**

```
master_seed = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f
name = "alice"
SHA-256(chain branch)     = bb8f878477dc5405cdf74c9079a0c2ba2c1dd55f0eda2de1598e5f120bdc4f5a
SHA-256(contact seed)     = e76fe9dde36740c309209ea51a81f42d43a5b82160963af7c47fe4f5c34526be
SHA-256(channel seed)     = b97abd0f496b1b57f3fc76108256f16da8b8be11722610f549c26b3b104c2b0f
```

The master seed of these three stands on sixty-four distinct bytes, no permutation of which is
itself, and each expansion composes its info as the domain, one NUL and the slot. An
implementation that omits the NUL, that writes the slot before the domain, or that reads the
seed backwards reproduces none of the three. The channel seed here therefore stands beside the
one frozen earlier over a repeated byte, which a reversed seed cannot tell apart.

**The post-quantum handshake.**

```
suite_id = 1, id_pk_i = 0x0A x 1952, id_pk_r = 0x0B x 1952
pk_i = 0x01 x 1184, pk_r = 0x02 x 1184, ct_i = 0x03 x 1088, ct_r = 0x04 x 1088
ss_i = 0x05 x 32,   ss_r = 0x06 x 32
transcript                = ed9ca2f7898c073ed4d62159b3219c9b3e1bdb9f4527c7564ee77d611338bbf2
master                    = 0e0518c8ad43bd274b49c8c98d2c8321dad8adde9bb7a065f5f6c10bd2ca50ef
k_i2r                     = 271ff1e9b997151f5925fa83e8b846c0c503ae8222d07b8d3b31acc62a5296c2
k_r2i                     = 08a031d18e42a5793274dcf0943bfe9df730d7c8acf118f7d77ae8e1ea9845aa
```

The two directional keys differ in every byte though both come from one master, which is the
separation the two domains buy.

## The registry of domain separators

Some separators carry, inside their frozen bytes, words the prose of this set does not use:
`mt-node-key`, `mt-node-commit`, `mt-nodereg` and `mt-nodereg-sort` name the participant this
set calls a **machine**, and `mt-account-key` names the signing branch of the person this set
holds as a **record**. The bytes are frozen with the vectors that check them; the words of the
prose are these, and no second kind of participant stands behind either spelling.

Every cryptographic domain string of the protocol lives here and nowhere else. A literal
`"mt-*"` appearing in any other document is a defect.

**The alphabet of a name is normative.** A name of this registry opens with `mt-` and holds
nothing but lowercase ASCII letters, digits and the hyphen. Freedom from prefixes follows from the
alphabet and not from a walk of pairs: no name holds the byte `0x00`, so the NUL of the primitive
separates the name from the body whatever two names share at their start, and a registry whose
names were checked pairwise would be answering a question the alphabet has already closed.

**A row names the shape of the preimage its domain opens.** The shape is one of two: a **body**,
where the domain stands over one value and nothing follows it, or **parts**, where the domain
stands over values whose widths the set fixes, at most one of them open. A caller who lays two
values beside each other and offers them as one body under a domain of parts is refused by the
door rather than trusted, and an implementation reading this column knows, before it writes a
line, which of the two it is writing.

| Domain | What it separates |
|---|---|
| `mt-op` | identifier of an identity-plane operation |
| `mt-nodereg` | identifier of a candidacy |
| `mt-proposal` | identifier of a proposal, over the fields the window decided |
| `mt-safety` | derivation of the fingerprint two people compare out of band |
| `mt-node-commit` | the commitment standing for a machine |
| `mt-merkle-leaf` | leaves of Merkle trees |
| `mt-merkle-node` | internal nodes of Merkle trees |
| `mt-ticket` | the ticket of the runner's draw |
| `mt-vote` | the coin a unit of standing draws in a window, over the half that spends, the census window and the cemented aggregate |
| `mt-round-att` | eligibility to attest a round, over the nullifier of the machine's part in that window, the cemented aggregate and the pair of chain and round |
| `mt-beacon` | the identifier of a beacon |
| `mt-frame` | the identifier of a frame |
| `mt-round-nf` | one attestation per machine per beacon |
| `mt-runner-key` | the one-time key under which a runner publishes a window without being named |
| `mt-runner-key-digest` | the digest a proof of a ticket binds the key of a proposal by |
| `mt-bc-aggregate` | the aggregate over a non-empty cemented set |
| `mt-bc-aggregate-empty` | the same for an empty cemented set |
| `mt-selection` | the sort key of a selection event |
| `mt-nodereg-sort` | the sort key of registrations inside a window |
| `mt-cascade` | the sort key of the standby order a window's cascade walks |
| `mt-genesis-state` | the hash binding the parameters of the Decree to the genesis state |
| `mt-seed` | the salt of the derivation from a mnemonic |
| `mt-account-key` | the signing branch of the derivation from a master seed |
| `mt-node-key` | the answering key of a machine, derived from the machine's own secret |
| `mt-note-key` | the payment-secret branch of the derivation |
| `mt-nf-key` | the redemption branch, separate from the payment secret |
| `mt-key-halves` | the two halves of a secret that spends: the half that spends and the half that names, in that order |
| `mt-note-pk` | derivation of a payment key |
| `mt-fabric-leaf` | a blinded leaf of the fabric: the record commitment observed, the window it was seen in, and a blinding factor |
| `mt-fabric-node` | an internal node of the fabric tree |
| `mt-note-cm` | the commitment of a note |
| `mt-note-nf` | the nullifier of a spend |
| `mt-rate-nf` | the nullifier bounding spends per window without naming a payer |
| `mt-act-nf` | the nullifier bounding actions of the identity plane per window, without naming anyone |
| `mt-record-nf` | the nullifier spending one version of a record, without naming its holder |
| `mt-credit-nf` | the nullifier extinguishing a right to a window's share |
| `mt-admitted-leaf` | a leaf of the tree of admitted machines: the naming half of the machine at that position |
| `mt-admitted-node` | an internal node of the tree of admitted machines |
| `mt-credit-leaf` | a leaf of the tree of credited rights: the part-nullifier of a machine a window credited, at the position it entered |
| `mt-credit-node` | an internal node of the tree of credited rights |
| `mt-cement-leaf` | a leaf of the tree of a census cement: the part-nullifier at that position |
| `mt-cement-node` | an internal node of the tree of a census cement |
| `mt-operator-nf` | the one-time right to raise a machine |
| `mt-part-nf` | the nullifier of a machine's part in one window: first appearance enters the cement, and equivocation in the agreement of the window is caught by it |
| `mt-open-nf` | the one-time right of a person to open their record |
| `mt-noise-pq-v1-master` | the master key of the post-quantum handshake |
| `mt-noise-pq-v1-i2r` | the directional key, initiator to responder |
| `mt-noise-pq-v1-r2i` | the directional key, responder to initiator |
| `mt-noise-pq-v1-sig-r` | the identity signature of the responder |
| `mt-noise-pq-v1-sig-i` | the identity signature of the initiator |
| `mt-noise-pq-v1-transcript` | the transcript exposed as a channel-binding token |
| `mt-lookup-nf` | the nullifier bounding a record to one reach into the space of slots per window |
| `mt-channel-slot` | the slot a channel occupies, derived from its normalized name |
| `mt-channel-key` | the key a channel signs its publications under, derived per slot |
| `mt-channel-head` | the head of a publication, chaining to the head published before it |
| `mt-channel-point` | the point of one window at which the publication of a channel stands |
| `mt-name-commit-op` | class domain for the identifier of a commitment over a slot of a name |
| `mt-name-reveal-op` | class domain for the identifier of a reveal of a name |
| `mt-name-renew-op` | class domain for the identifier of a renewal of a slot of a name |
| `mt-channel-commit-op` | class domain for the identifier of a commitment over a slot of a channel |
| `mt-channel-reveal-op` | class domain for the identifier of a reveal of a channel |
| `mt-channel-pub-op` | class domain for the identifier of a publication of a channel |
| `mt-part-key` | the one-time key a machine attests a window under |
| `mt-part-key-digest` | the digest a proof of presence binds the one-time key of an attestation by |
| `mt-entropy-mix` | the mixing of the sources a seed is drawn from |
| `mt-name-slot` | the slot a name occupies, derived from the normalized name |
| `mt-name-own` | the branch of a seed from which a name chain is built |
| `mt-name-chain` | a link of the chain that proves continuity of a holder |
| `mt-name-commit` | the commitment that takes a slot |
| `mt-owner-key` | the branch by which the machines of one owner seal alike |
| `mt-entry` | the offset of a ring in the choice of the entries a sender holds for a period |
| `mt-name-contact-key` | the contact key a claimed name is reached by |
| `mt-name-tag` | the tag of first contact to a claimed name |
| `mt-name-first` | the secret a first letter establishes, from which the walk of that pipe begins |
| `mt-tag` | the tag of a pipe, derived from a shared secret and a window |
| `mt-step` | the label of one step, derived from the secret two neighbouring machines share and the height of the window |
| `mt-slot` | the ephemeral identity from which a sender's slot within a window is placed |
| `mt-relay-seal` | the seal a hop attaches to prove distinctness of owners within one delivery |
| `mt-relay-path` | the identity of a path, taken over the pipe layer that crosses it unchanged |
| `mt-pipe-key` | the key sealing the delivery layer of a cell, held by the two correspondents alone |
| `mt-pipe-ratchet` | the step of the walk by which the secret of a pipe moves from one window to the next |
| `mt-collect` | the right to take mail from a pipe, sealed to the two correspondents for one window |
| `mt-round-point` | the points a beacon and its attestations stand at |
| `mt-window-point` | the points a proposal and its roll stand at |
| `mt-pledge-point` | the points the pledges of one part of one window stand at, over the part, the window, the band of attempts and the index |
| `mt-proposer` | the place of a part of a window in an attempt of its agreement, over the part-nullifier, the cemented aggregate and the attempt |
| `mt-roll` | the identifier of the roll of a proposal |
| `mt-notice-point` | the points the notice of a spend stands at |
| `mt-delivery` | the identifier a delivery carries inside its pipe layer |
| `mt-proof-transcript` | the running transcript from which every challenge of a proof is drawn |
| `mt-proof-query` | the seed from which the query positions of a proof are drawn |
| `mt-app` | derivation of an application identifier |
| `mt-app-encryption-key` | the encryption branch of the derivation from a master seed |
| `mt-proof-air` | the identifier of a description of a set of constraints |
| `mt-proof-leaf` | a leaf of a tree of a proof: the values one position of it carries |
| `mt-proof-node` | an internal node of a tree of a proof |
| `mt-note-leaf` | a leaf of the tree of notes: the commitment at that position |
| `mt-note-node` | an internal node of the tree of notes |
| `mt-record-leaf` | a leaf of the tree of records: the serialized record at that key |
| `mt-record-node` | an internal node of the tree of records |
| `mt-horizon-leaf` | a leaf of the horizon of proving: the note root at that position of its stride |
| `mt-horizon-node` | an internal node of the horizon of proving |
| `mt-line-opening` | the lock-opening value of a machine, drawn from the spending half of its secret |
| `mt-line-slope` | the slope of the line of one slot of one window, over the spending half, the window and the slot |
| `mt-line-abscissa` | the abscissa of a name on the line of a slot, drawn from the name alone |

**The domains of the `proof_hash` family, and there are thirty-four.** They are computed by the
doors of the proof hash; every other domain of the registry is computed by SHA-256, and either
function under a domain of the other family is a defect. The list is exact by the boundary the
primitives section draws — what a verifier of a proof judges, and the nullifiers and digests a
circuit asserts and a verifier recomputes beside it — and the capacity each door starts from is
written out, since it is the one value a second implementation must take byte for byte:

```
capacity("mt-proof-leaf")       = the first four limbs of SHA-256("mt-proof-leaf" || 0x00)
capacity("mt-proof-node")       = the first four limbs of SHA-256("mt-proof-node" || 0x00)
capacity("mt-proof-transcript") = the first four limbs of SHA-256("mt-proof-transcript" || 0x00)
capacity("mt-proof-query")      = the first four limbs of SHA-256("mt-proof-query" || 0x00)
capacity("mt-note-leaf")        = the first four limbs of SHA-256("mt-note-leaf" || 0x00)
capacity("mt-note-node")        = the first four limbs of SHA-256("mt-note-node" || 0x00)
capacity("mt-ticket")           = the first four limbs of SHA-256("mt-ticket" || 0x00)
capacity("mt-note-cm")          = the first four limbs of SHA-256("mt-note-cm" || 0x00)
capacity("mt-note-nf")          = the first four limbs of SHA-256("mt-note-nf" || 0x00)
capacity("mt-key-halves")       = the first four limbs of SHA-256("mt-key-halves" || 0x00)
capacity("mt-rate-nf")          = the first four limbs of SHA-256("mt-rate-nf" || 0x00)
capacity("mt-credit-nf")        = the first four limbs of SHA-256("mt-credit-nf" || 0x00)
capacity("mt-admitted-leaf")    = the first four limbs of SHA-256("mt-admitted-leaf" || 0x00)
capacity("mt-admitted-node")    = the first four limbs of SHA-256("mt-admitted-node" || 0x00)
capacity("mt-record-leaf")      = the first four limbs of SHA-256("mt-record-leaf" || 0x00)
capacity("mt-record-node")      = the first four limbs of SHA-256("mt-record-node" || 0x00)
capacity("mt-fabric-leaf")      = the first four limbs of SHA-256("mt-fabric-leaf" || 0x00)
capacity("mt-fabric-node")      = the first four limbs of SHA-256("mt-fabric-node" || 0x00)
capacity("mt-horizon-leaf")     = the first four limbs of SHA-256("mt-horizon-leaf" || 0x00)
capacity("mt-horizon-node")     = the first four limbs of SHA-256("mt-horizon-node" || 0x00)
capacity("mt-part-nf")          = the first four limbs of SHA-256("mt-part-nf" || 0x00)
capacity("mt-part-key-digest")  = the first four limbs of SHA-256("mt-part-key-digest" || 0x00)
capacity("mt-runner-key-digest") = the first four limbs of SHA-256("mt-runner-key-digest" || 0x00)
capacity("mt-open-nf")          = the first four limbs of SHA-256("mt-open-nf" || 0x00)
capacity("mt-operator-nf")      = the first four limbs of SHA-256("mt-operator-nf" || 0x00)
capacity("mt-record-nf")        = the first four limbs of SHA-256("mt-record-nf" || 0x00)
capacity("mt-vote")             = the first four limbs of SHA-256("mt-vote" || 0x00)
capacity("mt-cement-leaf")      = the first four limbs of SHA-256("mt-cement-leaf" || 0x00)
capacity("mt-cement-node")      = the first four limbs of SHA-256("mt-cement-node" || 0x00)
capacity("mt-credit-leaf")      = the first four limbs of SHA-256("mt-credit-leaf" || 0x00)
capacity("mt-credit-node")      = the first four limbs of SHA-256("mt-credit-node" || 0x00)
capacity("mt-line-opening")     = the first four limbs of SHA-256("mt-line-opening" || 0x00)
capacity("mt-line-slope")       = the first four limbs of SHA-256("mt-line-slope" || 0x00)
capacity("mt-line-abscissa")    = the first four limbs of SHA-256("mt-line-abscissa" || 0x00)
```

### No domain awaits a document

A domain exists here only for a mechanism the set describes: every row of the registry
separates a construction some document performs, and no separator stands reserved for a
mechanism nobody has written — a name reserved in advance is a name for nothing. Should a
document come to describe a new mechanism, its separator enters this registry with it, by the
rule of evolution the Constitution fixes.

### The threshold of the draw

**The threshold of the draw is the largest value the width carries**, which is `hash_bytes` bytes of
`0xff`, at every window. Every ticket of that width but the one equal to it stands below it, so every
machine of the electorate may run every window, and the draw does not choose who runs: it orders
them.

**Why nobody is excluded.** A runner carries what the window decided and nothing of its own. The name
of a proposal is taken over the decision, so every runner of one decision writes one name, and the
coin of a window falls to every living machine alike, runner or not. Excluding a machine from
running therefore buys nothing but the bandwidth of its copy, and it costs a window: a threshold
below the width leaves windows no ticket clears, and such a window closes on nothing. Neither way of
setting a lower threshold escapes that. A threshold walked by the windows that cleared it is held at
the width by construction, because a window closes only through a runner and so every window clears;
the walk never starts. A threshold read out of state, as the threshold of a round is, leaves the
windows no ticket clears in need of a runner, and the runner they need is the one the width already
gives. What excluding was for — fewer copies — the order gives without a window that stands.

**The order of the runners.** A machine runs after a delay its own ticket sets: before it proves its
own proposal it waits the share of its patience its ticket stands at, and it takes whatever proposal
of its decision stands verified at the points of the window meanwhile. The machine whose ticket is
lowest usually carries the decision first and alone, and nobody learns whose ticket that was. The
delay is a machine's conduct and enters no object and no verification: a machine that publishes at
once is one copy too many and nothing worse, because its proposal carries the name of the decision.

**Vector of the threshold of the draw** (hash_bytes 32):

```
threshold of the draw = ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
```

**Invariants of the threshold of the draw:**

- It is the largest value the comparison carries, so every value of that width but the one equal to it stands below it: every machine of the electorate may run, and a draw clears by standing below rather than by standing at.
- It is derived from `hash_bytes` alone and stands in no row of the Decree, since a row would be a second place for a value the width already fixes.
- It is the same at every window. Nothing walks it, and an implementation that lowered it would leave windows no ticket clears.
- The ticket orders who carries a decision first and decides nothing a verifier checks beyond clearing; the delay it sets is conduct and never a rule of acceptance.
- The threshold of a round is another quantity: it is a function of the state, and the first window computes it exactly as the millionth does.

### The recomputation of a walked threshold

A quantity of this set walked by an observable of the cemented past moves by one rule, integer,
damped and bounded by one step; the schedule of chains takes its shape. The threshold of the draw
does not walk — it is the width at every window, as the section above states — and the threshold
of a round is read out of state.

```
recompute(target_old, cleared, period, damping, step_bound):
  numer      = damping × period + period
  denom      = period + damping × cleared
  target_new = target_old × numer / denom          # unsigned, division toward zero
  clamp target_new into [ target_old / step_bound , target_old × step_bound ]
  target_new = max(1, target_new)                  # the floor is explicit, not implied
```

`cleared` is the number of windows of the period in which the threshold was met. A value clears a
threshold when it falls **below** it, so a higher threshold is an easier one — and the direction of
the rule follows from that and is not a matter of taste. Where every window met it the two terms
are equal and the threshold holds. Where none did, the denominator shrinks, the quotient rises, and
meeting it becomes easier by the next period; the clamp bounds that rise to one step. The arithmetic is unsigned throughout and the division
truncates toward zero, so two implementations agree bit for bit.

**The direction is the whole point.** Written the other way — the quotient falling when nothing
was cleared — a network that stalled once would make its next window harder, and harder again,
until it could not close a window at all. That is not a slow adaptation but a spiral with no
bottom, and an implementation that reproduces the arithmetic while inverting the direction is
not a variant of Montana: it is a network that stops.

**Vectors of the recomputation** (period 20 160, damping 4, step bound 4):

```
target_old 2^248                     = 0100000000000000000000000000000000000000000000000000000000000000
recompute(cleared 20 160)            = 0100000000000000000000000000000000000000000000000000000000000000
recompute(cleared 0)                 = 0400000000000000000000000000000000000000000000000000000000000000
recompute(cleared 10 080)            = 01aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
recompute(target_old 3, cleared 0)   = 000000000000000000000000000000000000000000000000000000000000000c
recompute(target_old 1, cleared 0)   = 0000000000000000000000000000000000000000000000000000000000000004
```

The first three are the ratio doing its work — held where every window cleared, at the clamp where
none did, and at five thirds where half did. The last two are the floor doing its: without it the
quotient and the clamp both reach zero, and a threshold of zero is a network that never closes
another window.

**Invariants of the recomputation:**

- Every operand is unsigned and no intermediate is negative; the multiplication precedes the division, and the division truncates toward zero.
- The result is clamped after the division, never before.
- The product is exact and its quotient may exceed the width: from a threshold standing at the width the ratio of five does. Such a quotient stands above every upper bound the clamp can hold and therefore takes that bound. An implementation that wrapped would turn the largest threshold into a small one, and one that refused would stop a walk whose threshold stands at the width.
- The threshold never falls below one because the floor is applied last and by name. Integer division alone does not give it: a threshold below the step bound has a clamp floor of zero, and the quotient itself reaches zero, so a rule without the explicit floor would let the network reach a state where no ticket can ever clear.
- The ratio exceeds one exactly when fewer windows were cleared than the period holds, and equals one exactly when every window was cleared; an implementation that produces the opposite direction is rejected by this invariant before any vector exists to catch it.
- The vectors above are normative: an implementation that reproduces the shape but not those numbers has the arithmetic wrong.

### The close of a window, and the slots an event offers

Three rules of the pulse are comparisons rather than derivations, and all are written without a
division so that no rounding is left for two implementations to disagree about.

```
quorum_reached(cemented, total) = cemented × confirmation_quorum_den
                                  ≥ confirmation_quorum_num × total
votes_reached(votes, expected)  = votes × confirmation_quorum_den
                                  ≥ confirmation_quorum_num × expected
offered(active)                 = max(1, active / admission_divisor)   # division toward zero
```

Both of the first two hold of every quorum the close reads: over the final beacon of a window — the
count of its cement against the count of the electorate, and the votes of that beacon against the
committee the electorate's standing draws, which the section below derives — and over the pledges of
one kind, attempt and name in the agreement of the window, their count of distinct parts against the
same count and the votes the ballots of those parts cast against the same committee. Where the
standing is too narrow to be sampled the committee expects nought, and the second rule holds of every
beacon and every set of pledges.

`cemented` is the count of distinct machines of the electorate whose confirmations entered the
cement of the window, or whose pledges of one kind, attempt and name the agreement counts, `total`
the count of the electorate — the admitted set the proposal of the
window two before carries — both unsigned. The comparison multiplies rather than divides, so a
window closes at exactly the share the Decree names and never at the nearest integer below it.

`active` is the count of living machines at a selection event and `offered` the number of
candidates it admits. **The floor of one is the whole of what lets a young network grow**: below
`admission_divisor` living machines the quotient is zero, an event that offers no slot admits
nobody, and a network that admits nobody never reaches the count at which the quotient would rise
above zero. It is the same shape of defect as a threshold that reaches zero, and it is closed the
same way — by a floor applied last and by name.

**Vectors:**

```
votes(votes 4 354, expected 6 499)      = 0
votes(votes 4 355, expected 6 499)      = 1
votes(votes 0, expected 0)              = 1
quorum(cemented 67, total 100)          = 1
quorum(cemented 66, total 100)          = 0
quorum(cemented 2, total 3)             = 0
quorum(cemented 100, total 100)         = 1
offered(active 0)                       = 1
offered(active 129)                     = 1
offered(active 130)                     = 1
offered(active 260)                     = 2
offered(active 4 096)                   = 31
```

**Vectors of the way back** (quorum 67 over 100; rounds never lower the required share):

```
resume_share_num(rounds 0)              = 67
resume_share_num(rounds 2 840)          = 67
resume_share_num(rounds 2 841)          = 67
resume_share_num(rounds 2 858)          = 67
resume_share_num(rounds 2 982)          = 67
resume_share_num(rounds 3 123)          = 67
resume_share_num(rounds 3 124)          = 67
closes(cemented 51, total 100, rounds 3 124)  = 0
closes(cemented 67, total 100, rounds 3 124)  = 1
restart_admitted(rounds 3 407)          = 0
restart_admitted(rounds 3 408)          = 0
```

A counterexample to the retired rule has two honest groups of 49 machines and an equivocating
group of 2. Each conflicting certificate carries 51 and was accepted after
3 124 rounds. Neither certificate meets the fixed parent quorum. Choosing a new denominator
from each responding group would still fork; a round count never authorizes that choice.
The boundary rounds remain in the vectors to detect accidental restoration of either bypass.

**Invariants of the close and the offering:**

- Both are unsigned; the quorum takes no division at all, and the offering divides toward zero.
- The floor of the offering is applied last and by name; an implementation that divides and stops has a network that cannot grow from below the divisor, and no vector of a larger population catches it.
- Two thirds of a hundred is not the quorum: a cement of two against an electorate of three does not close a window, because the Decree names sixty-seven hundredths and the comparison holds it exactly.
- The vectors above are normative.

### The standing of an electorate, and the votes it draws

The standing of a machine is a count of census windows: windows a fixed interval apart, the newest
`standing_censuses` of them at or before the window being judged, whose cement holds the part the
machine's secret derives for that window. Which census windows a machine lived is known to that
machine alone, because a part names nobody; how many parts each census cement holds is public, and so
the standing of an electorate is a sum every verifier makes and no machine's standing is anybody's
to read.

```
census_windows(w) = c_i = (floor(w / census_interval) − i) × census_interval,    i = 0 … standing_censuses − 1,
                    and nought where floor(w / census_interval) < i
census(w)         = the census the proposal of window w carries, newest first: one pair of the root of the
                    tree of a census cement and the count of that cement per census window
                  = census(w − 1) with the pair of w's own cement entering first and the last pair leaving,
                    where w mod census_interval = 0, and census(w − 1) as it stands otherwise
                  = standing_censuses pairs of the empty cement root and nought, before the first window
standing(w)       = the sum of the counts of census(w)
committee(S)      = threshold nought and expectation nought,                where S < standing_censuses × standing_committee
                  = threshold width × standing_committee / S and expectation standing_committee, otherwise
                                                   # unsigned, multiplication first, toward zero
cement_leaf(p)    = sponge("mt-cement-leaf", cells(p))
cement_node(l, r) = node("mt-cement-node", l, r)
cement_root(w)    = the fold of the append-only construction over the part-nullifiers of the cement of w,
                    ascending, at depth note_tree_depth, under those two doors; the empty leaf is
                    sponge("mt-cement-leaf", nothing)
coin(σ, c, A)     = sponge("mt-vote", cells(σ) || element(c) || limbs(A))
```

The electorate of window `W` reads `census(W − 2)`, its standing and its committee, beside the
admitted root and count the same proposal carries; `A` is the cemented aggregate of `W − 2`, the one
the draw reads, and `σ` the half of the machine's secret that spends. A unit of standing votes in
`W` where the machine's part of census `c` stands in the cement of `c` and `coin(σ, c, A)` falls
below the threshold of the committee, compared as an unsigned big-endian integer over its thirty-two
bytes. A census entry standing at nought because its window would precede window nought, or because
the network had not opened by then, carries the empty root, which no part walks to.

**Why the committee begins where it does.** A sample hides the weight it is drawn from only where it is
smaller than the population: below `standing_censuses × standing_committee` units a full standing
would cast every unit it holds, and every ballot would publish its weight. There the threshold is
nought, no unit votes, and the close is the count of machines alone — a young network discloses no
standing because it weighs none. From the floor on, a machine of full standing expects at most one
vote, and the expected votes of the whole electorate are `standing_committee`.

**The standing of an electorate, and the votes it draws.**

```
part(0x5A x 32, W = 4032)                       = 1e1dfefe3f14c4432f88e0f02c6b781291453c8f1f75594cb50141eff499d68c
part(0x7B x 32, W = 4032)                       = 05cd5246ac28bae967c51d066b459b758f495c96f181460b7a5e584064a216fb
cement_leaf(part of 0x5A x 32 at 4032)          = c3d633f515d6c0b00f1c19b59f35726f582335aff525245a23c2b9ac8cb28b05
cement_root (empty)                             = e12b6c1107fc49f5c135ee4fa1cff11bfb567e65da807cb134e15401065ae5c1
cement_root (the part of 0x5A x 32 alone)       = d9f70c6df55e9fa6c9e098c84b3880e7a78173e0909a5a6347080e15e1063f2d
cement_root (both parts, ascending)             = ac0afdbdf5ab0f05d668b8859d0af19afba8fe53d9b8b3341115ae0929e689b6
coin(0x5A x 32, census 4032, aggregate 0x33 x 32) = 50148730ea13bedaadba803315858bdf31aea02f053b1a2996d2644f87522685
coin(0x5A x 32, census 6048, aggregate 0x33 x 32) = 1cd1ebd784805280310eccecaffeb2da9ee9df6e8ee5542de8effc8f82c98ac6
census_windows(w 50 000)                        = 48384, 46368, 44352, 42336, 40320, 38304, 36288, 34272, 32256, 30240
census_windows(w 4 032)                         = 4032, 2016, 0, 0, 0, 0, 0, 0, 0, 0
threshold(standing 64 989)                      = 0000000000000000000000000000000000000000000000000000000000000000
threshold(standing 64 990)                      = 1999999999999999999999999999999999999999999999999999999999999999
threshold(standing 1 000 000)                   = 01a9eb2074ea8da7f3cf70153bd1676640a6b93ccd0fe8ab4fa48301a79fec99
threshold(standing 1 000 000 000 000)           = 0000001be9b9dfa709d301a4712fa4c30fc56d67e7d53123c2a2f9c45cee3363
expected(standing 64 989)                       = 0
expected(standing 64 990)                       = 6499
```

The parts are those of the two secrets at one census window, so the two roots of one and of both
parts pin the pairing of a level, and the second coin moves only the census window: an implementation
drawing the coin from the part rather than from the spending half — which every machine could then
compute for every other — reproduces neither line. The first census windows are those of a window
that is not a census window, so an implementation counting from the window itself rather than from
the census at or before it misses the line; the second shows the entries that would precede window
nought standing at nought. The thresholds stand at the last standing below the floor, at the floor —
where a unit votes one time in `standing_censuses`, the width over ten — and twice above it.

**Invariants of the standing:**

- The census a proposal carries is recomputed by every verifier from the census of the proposal before it and the cement its own window decided; a proposal whose census differs is refused, and the census stands inside the name of the proposal.
- A unit of standing is a census window whose cement holds the machine's part of that window; the tree of a census cement folds its parts ascending, so the root a ballot walks to is the root every verifier computes from the parts it held.
- The committee is a function of the standing alone; no observation, no count of rounds and no history beyond the census enters it, and below its floor it expects no vote.
- A coin takes the spending half, the census window and the cemented aggregate of the window two before, and nothing else; it is computed by its machine alone, so no reader learns which units of a ballot cleared.
- A ballot publishes the count of the votes its standing drew and nothing else of the standing: neither how many census windows the machine lived, nor which, nor where it stood in their cements.

### What a device answers a stranger with

Two rules bound what a device spends on links it did not choose. Both are written without a
constant of their own beyond the count of slots: the budget of carriage belongs to the operator of
the device, and what this set fixes is its division.

```
answers(inbound)           = inbound < inbound_slots
share(budget)              = budget / (inbound_slots + outbound_connections)   # division toward zero
```

`inbound` is the count of **held** links the device did not open, and `budget` is what its
operator gives the wire for one window. A deposit at a point of a window or of a round is one
cell and not a session: it arrives over a link that already stands — routing brought it, hop by
hop — and it opens none of its own, so it takes no slot. It is accepted inside a handshake like
every other byte of this wire and outside one never. Were the ceiling to count deposits, it would
turn the holder of a point into a target: the holder rule is public, so anyone computes which
machines stand at the points of the next round, and filling their slots ahead of time would censor
a round the network can neither see nor repair. What makes a device at its ceiling still reachable
by routing is that the entries it chose for itself stand outside that ceiling. A device at its ceiling refuses in silence — an answer
saying "full" tells a stranger it found a device — and a link that carried nothing across a whole
window is released, so holding a slot costs exactly the carriage it displaces and an idle flood
gives its slots back within one window.

**Vectors of what a device answers:**

```
answers(inbound 0)      = 1
answers(inbound 95)     = 1
answers(inbound 96)     = 0
share(budget 120)       = 1
share(budget 119)       = 0
```

**Invariants of what a device answers:**

- The entries a device chose for itself are not counted against the slots and are not released by this rule; they stand at points no one else computes, and a stranger able to displace them would undo the ring.
- A deposit at a point of a window or of a round takes no slot and opens no link of its own, and it is accepted inside a handshake like everything else: the ceiling counts the sessions a device holds, and the points a machine stands at are computable by everyone, so a ceiling counting deposits would hand a censor the roster of the next round.
- A refusal is silence: no answer of any kind distinguishes a device at its ceiling from an address where nothing listens.
- The division of the budget is equal across every link a device holds, the entries among them; a device feeding one link from another's share is a device an adversary starves its neighbours through.
- What exceeds a link's share is dropped without an answer and without being remembered, so the set of accepted digests is bounded by the budget and needs no ceiling of its own.
- The release runs on the window and on no clock of its own: the window is already the horizon of freshness of everything on this wire.

### The verifier of a proof

A proof is accepted by this procedure and by no other. Every parameter it names stands frozen
above, and the one thing it takes from elsewhere is the evaluation of the constraints, which the
arithmetization below supplies.

**A proof, by its parts.** The bytes of `PROOF_LEN` are, in this order:

```
trace_root                       32 B         the Merkle root of the extended trace
composition_root                 32 B         the Merkle root of the composition polynomial
fri_roots                    5 x 32 B         the root of each folding layer, in order
ood_values                  132 x 24 B         evaluations out of the domain, in the challenge field:
                                              every slot of a row at z, every slot at z one row on,
                                              and the two parts of the composition at z; those of a
                                              slot above the width and below the randomizer zero
tail                        64 x 24 B         the coefficients of the last layer, low order first
queries              92 x 4 344 B             one block per query, laid out below

per query = the block the contents above fix, in that order and of that width: the path of the
            trace and the row it opens — the columns of the bound and the randomizer beside them —
            the path of the composition and the two parts it opens, and for each of the five
            folding layers its path and the values it folds
```

**Invariants of the proof encoding:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes.

**The trees of a proof, and what a leaf and a node of one are.** They stand under `proof_hash`
and under domains of their own, because the law of the Kernel holds here as everywhere: every
door of the proof hash takes a domain of the registry through its capacity, and a tree whose
preimages were bare elements would be a tree two implementations build two ways. The identifier
of a description is the one quantity here that people and documents compare with no proof in
hand, and it stays SHA-256 by the boundary.

```
identifier of a description = SHA-256("mt-proof-air" || 0x00 || the description in its
                                     canonical form)

leaf of a tree of a proof = sponge("mt-proof-leaf", the values that position carries, in
                                   order, as field elements)
node of a tree of a proof = node("mt-proof-node", left || right)
```

**The vectors these stand or fall by.** A rule written in prose admits two readings the day the
values it hashes are not bytes but elements of a field, and an element of `proof_challenge_field`
is three words. Each vector below stands on an input that matches no permutation of itself, and
each names the implementation it refuses — a vector that named none would certify inattention.

```
leaf over two elements of the challenge field, (1, 2, 3) and (4, 5, 6)
proof leaf                = 9f8602c51ac7a7e939e7f3012f6cd66902f7f35f3b5fb25389b5fb0d39d23631
    refuses an implementation writing the coefficients of an element high order first, one
    packing an element as a single twenty-four-byte number rather than three words, and one
    ordering the two elements the other way

node over children 0xAA x 32 and 0xBB x 32
proof node                = 3af8333927c66404b8480e2aa6beaa262365c81b1af3ed5d2ad438fb7be278bc
    refuses an implementation folding the children in the other order

identifier of the description frozen above, over its 160 bytes
proof air                 = bf608bb95f13629ffbe0f7d2928359faaeec03f9bf55d6d501cd994484185fec
    refuses an implementation hashing a description without its domain, and one hashing a
    description in a form other than the canonical one

transcript over that identifier and public inputs 01 02 03 04 05 06 07 08
proof transcript zero     = a8a7863871540452ecbdd68eb6becb7284291bc822517303e99b055a7fede924
transcript after absorbing a trace root of 0xCC x 32
proof transcript one      = a06d60666c1eb06be89040b5e2fc402e465cfe7ef8283cac4233fec439d292d1
    refuses an implementation absorbing the root before the identifier, one ignoring the public
    inputs, and one restarting the transcript at every step instead of running it

query seed over that transcript
proof query seed          = a4e7dcfe975963187b33950e34869c8caf97162f20dc08c376c940ff5a5b2f47
the first three positions it draws over the domain of a frame
proof query positions     = 133310, 42341, 245103
    refuses an implementation drawing positions from the transcript itself rather than from a
    seed of its own domain, one reading a draw high order first, and one keeping a repeat
```

A position of the tree of the trace carries the row of the extended trace at it — the columns of
the trace and the randomizer after them, and nothing of the padding; a position of the tree of the
composition carries the two parts of the composition there; a position of a folding layer
carries the `proof_fold` values that layer folds, which is why that tree has a quarter of the
leaves its layer has values. The first folding layer is the deep composition itself — the quantity
the fourth check recomputes — so it is committed like any other and the folding starts where the
check lands. An odd position at any level rises unchanged, as
in the append-only construction of the state, so no position ever holds a blank child.

**The transcript, which decides everything nobody may choose.** Every challenge is drawn from one
running transcript under the sponge of the proof hash, so a prover cannot aim at a query it has
not yet committed to. the two doors below are the sponge over the limbs of the bytes given:

```
S(x)        = sponge("mt-proof-transcript", limbs(x))
Q(x)        = sponge("mt-proof-query", limbs(x))

transcript_0 = S(air_hash || public_inputs)
transcript_1 = S(transcript_0 || trace_root)
    constraint mixing coefficients = the field elements drawn from transcript_1
transcript_2 = S(transcript_1 || composition_root)
    z, the out-of-domain point = the first field element drawn from transcript_2, rejected while
    it lies in `proof_field` at all — a point of the base field may be a row of the trace or a
    point of the extension of it, and the point one row on lies in the base field exactly when
    this one does, so one condition covers both and covers them strictly
transcript_3 = S(transcript_2 || ood_values)
    the deep composition coefficients = the field elements drawn from transcript_3
transcript_(3+m) = S(transcript_(2+m) || fri_roots[m-1])
    the folding coefficient of layer m = the first field element drawn from it, m = 1 .. 5
transcript_9 = S(transcript_8 || leaf of the tail)
query_seed  = Q(transcript_9)
    the 92 query positions = eight-byte little-endian draws from the digests of query_seed with a
    counter, as below, each taken modulo the size of the evaluation domain, repeats redrawn

drawing a challenge, which is one rule for every challenge above:
    digest_i    = S(transcript || i_8B_LE), i from zero
    the digest reads as four unsigned eight-byte little-endian words, in order; a word at or above
    the modulus is passed over, and the words that stand below it are taken in that order — a
    digest of this sponge serializes canonical elements, so the rule never fires under it, and it
    stands for any function a door of an era may put here. An element of `proof_challenge_field`
    is the next three such words, least significant coefficient first; a draw that has spent a
    digest takes the next, and the counter never repeats inside one challenge. Where a challenge
    is a position rather than an element it is one such word.
```

`public_inputs` are what the description names: for a frame, the bytes of the frame that stand
before the proof field; for the presence and the ticket, the values their sections fix, in that
order, computed by the verifier from state and from the object the proof stands in; for the
admission and the opening, likewise. A proof is thereby bound to the object it proves and to the
state it is judged against, and to nothing else.

**What the verifier checks, in order.** A proof failing any check is refused, and the refusal is
silent.

1. The length is `PROOF_LEN`, the parts split as above, the evaluations of a slot above the
   width and below the randomizer are zero — the slot covers the bound of the width, and a proof
   that wrote anything into the unused evaluations would carry two encodings of one claim — and
   the tail carries no more than `proof_tail_degree` coefficients, which is the whole of the sixth
   check's bound.
2. The composition identity at `z`: the constraints of the arithmetization, evaluated at `z` over
   the trace values of `ood_values`, mixed by the coefficients of `transcript_1` and divided by what
   vanishes on the live rows but the last, together with every boundary divided by what vanishes at
   its row, equal the first part of the composition the same list carries plus `z` raised to the
   height times the second — this is the one step the arithmetization supplies and the only step
   that knows what is being proven.
3. For every query position: the row against `trace_root` by the path of the trace, the value of
   the composition against `composition_root` by its own path, and the values of every folding
   layer against that layer's root, each root recomputed under `proof_hash` — the trees of a proof
   are its own and stand under its own hash — and never taken from the proof.
4. The deep composition at each query: the value formed from the opened leaves and the
   out-of-domain values by the coefficients of `transcript_3` equals the value the first folding
   layer opens at the folded position.
5. For every folding layer in order: the opening at the position of that layer folds to the
   opening of the next by the coefficient of that layer, each against its own root.
6. The tail answers where the last fold lands, and it carries no more coefficients than the
   frozen bound — a degree bounded by counting rather than by sampling.

An implementation that performs these six in this order, with the frozen blowup, the frozen count
of queries and the frozen field, accepts exactly the proofs every other such implementation
accepts — the frozen field and the frozen extension being part of what "frozen" means here, since
two primes of one width are two protocols.

### The arithmetization, and how the set is bound to it

The constraint set is the one part of the protocol whose right form cannot be argued in prose: it
is a machine-checkable artifact, and a set that described it in words would let two implementations
write two circuits that agree sentence by sentence and accept different proofs. So the set does
what it does with every other quantity it cannot leave to taste — it fixes the artifact by its
hash and states what the artifact must contain.

```
air_hash = the hash, under the domain of a description's identifier, of the identifiers of the
           descriptions the network accepts proofs under, in the order the planes stand:
           the frame, the ticket, the admission, the presence, the opening, the ballot,
           the pledge

identifier of the frame     = 01f51109574f2c463fa5bf4da0d43dd314447e10bd79aa17820f0827e65b2562
identifier of the ticket    = 0c50e4291fede09b20945f9070e50746429b40153911600a690832aab6e65378
identifier of the admission = df6b61c212011e407d44462c1cd253556c5feccf44246cb201c6c87eb66b4323
identifier of the presence  = 7118d09319ec036384ec1ed4b47c1491481d7934996795dc4ecac3f0f70e747a
identifier of the opening   = 34c92be6edfe2e089be14dc59489dd2d1ef3483db4fab5d08abc28eaa0ca18da
identifier of the ballot    = a329f7e7ae7656e26147604e0f757ff9cea56facbf953eb30fd01a3f59fe9928
identifier of the pledge    = d6b31441516052c28a4be0d23713244f273237a807b42e8564dd82d33f9ab71e

each identifier = the hash, under the same domain, of the canonical description of its
                  constraint set, which is:
  trace_width                       2 B   u16
  rows_log2                         1 B   u8
  periodic_count                    2 B   u16
  for each periodic column, in order:
    period_log2                     1 B   u8
    values                 2^period_log2 x 8 B   u64, field elements
  constraint_count                  2 B   u16
  for each constraint, in order:
    degree                          1 B   u8
    term_count                      2 B   u16
    for each term:
      coefficient                   8 B   u64   a field element
      factor_count                  1 B   u8
      for each factor: column 2 B u16 || shift 1 B || power 1 B
  boundary_count                    2 B   u16
  for each boundary: column 2 B u16 || row 8 B u64 || kind 1 B || value 8 B u64
    kind 0: the value is a literal of the field
    kind 1: the value is the index of a limb of the public inputs — the bytes of the object the
            proof stands in, taken in the four-byte limbs the doors of the proof hash define —
            and one frozen description binds every frame to its own roots, nullifiers and
            commitments, while a proof of one frame asserts nothing about another
    kind 2: the value is the index of the lower of two adjacent limbs, and the cell is held to
            `limb(index) + 2³² · limb(index + 1)` — a 64-bit word of a hash state, which no
            single limb can carry
```

**Invariants of the constraint description:**

The field order and widths above are normative. A decoder refuses a length outside the declared
shape before reading fields; an encoder checks that shape before publishing or signing bytes. The identifier binds the encoded constraints; its existence does not establish that they
enforce the complete intended statement.

**What a description means, so that two readers of it hold one circuit.** A constraint holds at
every row of the trace: the sum of its terms is zero in `proof_field`, and a term is its
coefficient times the product of its factors, a factor being one column at this row or at the one
after it, raised to one power. Row indices are taken modulo the length of the trace, so the domain
closes on itself and the row after the last is the first. **A shift names those two rows and no
other**, and what decides it is a value already frozen rather than a taste: the slot beside the
roots holds every column at the point outside the domain and at the point one row on, so a factor
at a further row is a value no proof carries. A description naming one is refused where it becomes
a description — not read as the row after this one, which would judge a trace against the row the
artifact names while proving the row beside it.
A column index below `trace_width` names a column of the trace; one at or above it names the
periodic column of index `column − trace_width`, whose value at a row is `values[row mod period]`.
A periodic column carries no witness and costs a prover nothing: it is what turns a constraint on
over one region of the trace and off over another, which a trace of many gadgets cannot do without.

**A constraint is of degree two, and that follows from the three frozen values rather than from
taste.** The composition of a constraint of degree `d` over a trace of `n` rows carries degree
about `(d − 1) · n`. The folding divides a degree by `proof_fold` at every layer, and the count of
layers is exactly what carries `n` down to `proof_tail_degree` — so the same folding carries the
composition down to `proof_tail_degree · (d − 1)`, and a tail of `proof_tail_degree` coefficients
therefore admits `d ≤ 2`. The bound holds at every height, since `n` cancels.

Nothing of what a circuit must say is lost by it. A constraint of any degree becomes constraints of
degree two over intermediate columns: the choice of three bits is `e·f + (1 − e)·g` and already of
degree two, the majority is `t + c·(a + b − 2t)` with `t = a·b`, and the exclusive or of three is
two of two. What is paid is columns, and columns are what the bound on the width already counts. A
description of higher degree is refused where it is made rather than where a proof of it fails to
fit its tail.

**A term is a monomial and not a single column, and that is what makes the format sufficient.** The
constraint that decides a bit — `b − b²` — needs one column; the constraint that multiplies two
cells, and therefore every gate of every hash this protocol computes, needs their product. A format
of one column per term expresses the first and not the second, and a circuit for SHA-256 cannot be
written in it at all.

**Invariants of a description:**

- Every coefficient and every literal boundary value is below `proof_field`; a description carrying one at or above it is refused before it is hashed. A public boundary is resolved by prover and verifier alike to the named limb of the public inputs, and an index beyond the limbs the object yields refuses the proof.
- The declared `degree` of a constraint equals the greatest sum of powers over its terms; a description whose declaration differs from what its terms give is refused, so the bound a verifier budgets by cannot be misstated.
- Every column index is below `trace_width + periodic_count`, every `shift` is zero or one, and every boundary row is below `2^rows_log2`. The two refusals a shift can draw say different things and are never confused: a shift at or beyond the length of the trace names no row at all, and a shift above one names a row the shape of a proof does not carry.
- Terms stand in the order given and are not sorted: the description is the artifact's own bytes, and two orderings are two artifacts with two hashes, which is the point of binding by hash.

**The vector of the encoding.** The artifact itself awaits its author; the encoding of it does not,
and an implementation checks its encoder today against a description small enough to read and real
enough to exercise every part of the format — a boolean column, a multiplication gate, a transition
gated by a periodic column, and one boundary:

```
trace_width = 3, rows_log2 = 3
one periodic column of period 2, values (1, 0)
constraint 1, degree 2:  c0 − c0²
constraint 2, degree 2:  c2 − c0·c1
constraint 3, degree 2:  per·(c1[+1] − c1 − c0)
one literal boundary: column 1 at row 0 equals 1
one public boundary: column 2 at row 2 equals limb 0 of the public inputs
one word boundary: column 1 at row 2 equals the pair at limb 0
public inputs of the vector = 0x05 then seven zero bytes: two limbs, 5 and 0, so the single
                              limb and the pair resolve to the one value the trace carries

canonical description = 199 B
SHA-256 of it = 703186b6adf3929c84fec81da75ab7353856015318252d8ef1a197a4eb193e24
```

The description above is satisfied by a real trace of eight rows, so what the vector fixes is an
encoder of something rather than an encoder of nothing.

**What the constraints must assert**, statement by statement, so that the artifact is checkable
against this document rather than against its author's memory: for a ticket — that the two halves
of the runner's secret come of one absorption of it squeezed twice; that the half that names stands
at a leaf of the tree of the electorate under the root the public input carries; that the ticket,
the sponge over the half that spends and the eight limbs of the cemented aggregate the public input
carries, falls below the threshold the public input carries, compared unsigned and big-endian byte
by byte with every byte held in range and every word held canonical; and that the digest of the key
the proposal answers under, taken under the runner-key-digest domain over the limbs of that key, is
the one the public input carries — and nothing of the ticket, the secret or the place in the tree.
For a frame — that every redemption takes one of the two branches without
saying which; where the branch is a note, that its root stands at a leaf of the horizon of
proving — the fold of the standing stride of the window the frame applies in — and where it is
a right, that the part its secret derives for its window, from the half its nullifier takes and the
same window, stands at a leaf of the tree of credited rights under the root the proposal of that
stride's last window carries; that what is created equals what is consumed, a right counting
as `window_credit` coins; that
every nullifier derives from what was consumed by the canonical formula of its branch; that the
rate nullifier belongs to a window of the standing stride and its index is within the bound;
that the computed moment of a right falls within the standing stride, which is what stands
between its moment and its landing; and that every spend is a correct transfer or filler.
For a candidacy — that the record it absorbs, limb by limb under the record leaf domain, stands at
a leaf of the tree of records under the `record_root` the public input carries, the root of the
proposal of the last window of the stride standing for its `window`; that the eight limbs of that
record's `operator_nf` are the eight limbs of `operator_nullifier` the public input carries; that
`operator_nullifier` is the sponge, under the domain of the right to raise a machine, of a branch
absorbed once; that the machine's secret is absorbed once and squeezed twice, and the second squeeze
is the `naming_half` the public input carries; that every absorption ends in its canonical padding;
and the continuity of that record that Identity states — and nothing of the record, the branch, the
secret or the place in the tree. The record, the right and the half meet in one proof by those
equalities and by nothing else: no walk of the tree of admitted machines stands in it, since a
claimant who could walk that tree would need no candidacy.

**The width is counted above.** The bound is sixty-four columns, including the persistent
branch bits. At the frame's height and blowup, the extended trace alone occupies 256 MiB.
Merkle trees, quotient and folding domains require additional memory. A column count establishes
neither a device's peak allocation nor its proving time; both require a measured full proof.

**The rule this closes.** `air_hash` is a parameter of the Genesis Decree like any other, and a
chain whose value differs is a different protocol by the rule this document already states. While
the row carries no value the table has no encoding and no Genesis State Hash exists; a network
opens on a table where the row carries one, and its Genesis State Hash is what the frozen
procedure yields over that table. No implementation disagrees silently about the circuit, because
the value binding it is a parameter every one of them reads from the same row.

**A description stands at the height of its duty, and the length of a proof is why heights are
few.** A proof is bytes of one length per height: the count of folding layers, the levels a query
opens and the coefficients of the tail all descend from the height of the trace, so a description
built at the height its own blocks happen to fill would carry a length of its own — and every
object carrying a proof carries a length this document freezes. Two heights exist and no third.
The descriptions whose proofs ride in objects of `PROOF_LEN` — the frame, the admission and the
opening — stand at the tallest circuit's height, the frame's, the shorter ones paying the
difference in idle rows rather than in disclosure: what a query opens is a row of the bound on the
width whatever the circuit is, so a padded trace says nothing about the statement it proves. The
presence stands at a height of its own, derived below, and the ticket stands with it: the ticket
lays the chains the presence lays and a comparison of thirty-two rows beside them, so it fits the
presence's height and the proof a proposal carries is of the presence's length. The proof of a
presence is public as such by the object that carries it, so padding it to the frame's height
would buy no concealment — and it is the one description a machine proves every window, so the
padding would be paid by every machine of the network at the pulse of the network. A duty of every
window is priced by its own statement, not by the tallest. An implementation building any
description at another height computes another identifier, and `air_hash` refuses it.

The presence's own height is derived below, with the length that follows from it.

**What the row binds, and in what order.** The value the Decree carries is taken over seven
identifiers — the frame, the ticket, the admission, the presence, the opening, the ballot and the
pledge — in the order the planes stand. Each was written, proven and verified end to end before its identifier was
allowed to stand, because an identifier frozen before the thing it names has run is a number that
measures nothing. The values standing behind `air_hash` — the Genesis State Hash and the digest
of the published parameters — move when this row moves, and a chain opened on one value is a
different protocol from a chain opened on the other. The identifier of the admission is the
identifier of the statement of a candidacy written above, and a network accepts a candidacy under
that identifier alone: a chain whose Decree binds another statement of the admission is a different
protocol, and no verifier of this one takes a proof under the other in its place, as a fallback or
otherwise. The same holds of the opening, whose record carries the right a candidacy spends.

### The height of the presence, and the length of its proof

**Target.** The one description a machine proves every window must be priced by its own
statement, and every length a proof carries must still follow from a height the set names.

**Derivation.** A description is built at a height, and the height decides the length: the
count of folding layers, the levels a query opens and the coefficients of the tail all descend
from it. The frame is the tallest circuit and fixes the height every description whose proof
rides in an object of `PROOF_LEN` is built at. The presence rides in no such object — its proof
stands inside a confirmation, whose length is derived here rather than shared — and it is the
one description proven once per window by every machine of the network. The ticket, whose proof
stands inside a proposal, is built at the same height: its blocks are the presence's, without the line
record 309 adds, with the ticket's two in place of the nullifier's one, and a comparison of thirty-two rows stands after the
last of them, so what fits the presence fits the ticket. Padding the presence to the
frame's height would buy nothing: an attestation is public as an attestation by the object
carrying it, so the idle rows conceal no statement, and the cost would be paid at the pulse of
the whole network. Its blocks — the absorption of the secret squeezed twice, the walk of the
tree of admitted machines, the nullifier of the part, and the absorption of the one-time key,
whose limbs dominate the count, 108 blocks with the idle one, and since the author's record 309 at
most four more for the line of the open slot of attempt zero ("The confirmation of a window") —
fill under 2¹⁴ rows at `rows_per_permutation`, 14 336 of them at 112 blocks against the 16 128 that
stand before `proof_free_rows`, and 2¹⁴ is the least height at or above that count the folding
reaches the tail from. The arithmetic of the
length is the arithmetic of `PROOF_LEN` at that height — the folding stops at the same tail,
`14 − 2k = 6` gives four layers, and the extended domain is 2¹⁷:

```
per query = 32 x 17 + 65 x 8 + 32 x 17 + 2 x 24 + 32 x 48 + 4 x 4 x 24 = 3 576 B

PRESENCE_PROOF_LEN = 32 + 32 + 4 x 32 + 132 x 24 + 64 x 24 + 92 x 3 576 = 333 888 B
```

| Parameter | Value |
|---|---|
| `presence_rows_log2` | 14 |
| `PRESENCE_PROOF_LEN` | 333 888 B |

The queries, the blowup, the tail, the slot of the evaluations and the bound on the width are
the scheme's, unchanged: a second height is not a second scheme, and a verifier reading the
height of a description holds everything else where it held it. What the height buys is named
with its number: the extended trace of a presence is a quarter of a frame's, and so is the
proving of the duty every machine carries every window.

**Sensitivity.** At 2¹² the blocks do not fit and no trace of a presence exists; at 2¹⁶ the
presence stands at the frame's height again and every machine pays a frame's proving once a
window for a statement a quarter of that size.

**Defence.** Why not one height for everything — because one height is one length only where
every description rides in one object, and the presence rides in an object this document
derives separately; the property a shared height buys is that a proof discloses nothing by its
length, and it is bought within each object rather than across all of them. Why not a third
height for the admission or the opening — both ride in objects of `PROOF_LEN`, so a height of
their own would be a length no object has room for. Why the blocks are counted rather than
measured — the count is what the description assembles from, and a height chosen above it would
be a tax with no name.

**The ballot stands at the frame's height**, because it rides in an object of `PROOF_LEN`: per census
window it walks a cement of `note_tree_depth` levels beside a part, a leaf and a coin, so ten census
windows fill 442 blocks of `rows_per_permutation` rows, past 2¹⁴ and within 2¹⁶ less the free
block. What keeps that price off the pulse is who pays it: a ballot is proven by a machine whose
standing drew a vote, once a window, and only where the standing of the electorate is sampled — a
network below the floor of its committee proves none.

### The computed moment of extinguishing a right

```
claim_window(W) = W + ( u32_le(claim_delay) mod claim_spread )
```

`claim_delay` is the second squeeze of the absorption that yields the nullifier of the right, taken
where the right of that window is derived. `machine_secret` is the secret a machine holds;
Consensus defines it and states that nothing it publishes ever carries it. Only values derived from
it in one direction leave the machine.

The right of window `W` is accepted while the stride its computed moment falls in stands as
the horizon of proving — never earlier than that moment, since every window of a stride stands
before its standing period, and never later than the horizon moves on. A person chooses no
moment: the base is computed, and the margin above it is the proving time of a device, which
nothing published carries. `claim_spread` and `proving_horizon` are frozen in the Decree below.

### The fingerprint compared out of band

Two people bind a handshake to a key by comparing one number derived from that key alone. There
is exactly one derivation of it, and a second would let a comparison succeed on one path and
fail on the other.

```
fingerprint(identity_key):
  h = the identity key
  repeat fingerprint_iterations:   h = SHA-256("mt-safety" || 0x00 || h)
  take the first 30 bytes of h; read them as six groups of five bytes, each group
  reduced modulo 100000 and written as five decimal digits
  -> thirty digits, shown as six groups of five

pair_fingerprint(a, b):
  order the two keys ascending as big-endian integers, then concatenate their fingerprints
```

**Invariants of the fingerprint:**

- The iteration count is `fingerprint_iterations` and no implementation varies it; a different count yields a different number and a comparison that cannot succeed.
- Thirty digits carry close to a hundred bits, so a collision is out of reach and one number serves speech, screen and a scanned code alike.
- The pair form is ordered, so both people read identical digits without agreeing who reads first.
- A change of the key yields a new fingerprint, and a handshake bound to the old one is unverified again.

| Parameter | Value |
|---|---|
| `fingerprint_iterations` | 5 200 |

## The Genesis Decree

The Decree parts into two blocks, and the parting is what a boundary between eras may move and
what it may not. Each block has its own order of encoding, and every row stands in exactly one of
them.

### Parameters


These are the numbers of Montana. They enter the Genesis State Hash and cannot be changed
after genesis by anything short of a new network.

**Why the width of a hash output stands here.** It is the width of every root the Genesis State
Hash binds, of every identifier, of every nullifier and of every commitment, so a boundary able to
move it would open a chain that is not this one. What retires at a boundary is the function and
never its width: a chain that needs another width is another chain, and this document already
stands on this number where it says what Grover leaves of it. A future table of functions therefore
demands the width from this row rather than declaring one of its own.

| Parameter | Value |
|---|---|
| `hash_bytes` — the width of a hash output, and therefore of every identifier, commitment, nullifier and root | 32 |
| `τ₂` — the period of adaptation, in windows | 20 160 |
| `window_credit` — the coins credited to every machine living in a window, one for every second of it (article 11); derived: 86 400 / `segment_windows`, never read from a clock | 60 |
| `slot_modulus` | 64 |
| `retarget_period`, in windows | τ₂ |
| `retarget_damping` | 4 |
| `retarget_step_bound` | 4 |
| `continuity_period`, in windows — derived: `continuity_segments` x `segment_windows` | τ₂ = 20 160 |
| `continuity_segments` | 14 |
| `segment_windows` | τ₂ / 14 = 1 440 |
| `continuity_required_num` over `_den` | 2 over 3 |
| `max_entry_segments` | 56 |
| `selection_interval`, in windows | 336 |
| `confirmation_quorum_num` over `_den` | 67 over 100 |
| `committee_divisor` | 256 |
| `admission_divisor` | 130 |
| `adaptive_entry_threshold_num` over `_den` | 1 over 100 |
| `adaptive_entry_multiplier` | 100 |
| `membership_term`, in windows | 2 τ₂ |
| `candidate_expiry`, in windows | 3 τ₂ |
| `record_bucket_base` | 4 |
| `frames_per_window` | 273 |
| `name_chain_length` | 128 |
| `name_renew_windows` | 6 τ₂ |
| `name_reveal_windows` | 2 τ₂ |
| `name_min_length` | 4 |
| `proving_lag`, in windows | 2 |
| `proving_horizon`, in windows | 128 |
| `spends_per_window` | 4 |
| `claim_spread`, in windows | 1 440 |
| `max_openings_per_window` | 256 |
| `hop_min` — distinct machines of the active set on a path | 3 |
| `outbound_connections` — entries, one per ring of distance | 24 |
| `inbound_slots` — the links a device answers, beside the entries it chose | 96 |
| `target_rounds` — derived: the least count of rounds at which the expected uncovered share of the electorate falls to the complement of the quorum | 284 |
| `round_floor` — the fewest machines a round of a chain draws in expectation, whatever the population | 50 |
| `retained_windows` — the windows the beacons of the rounds of a closed window, its heavy attestations, the light attestations answering its final beacon, the ballots and the pledges stand at their points for, which is the certificate a device behind walks | 8 |
| `k_max` — the cap of parallel chains | 8 |
| `k_step`, in windows — one chain added each step of height, to the cap | 96 τ₂ |
| `cascade_width` — entitled parallel versions per chain | 3 |
| `consensus_replicas` — points a round and a window stand at | 3 |
| `finality_rule` — fixed-parent quorum, with no round-based lowering or self-selected restart | 1 |
| `standing_censuses` — the census windows the standing of a machine is counted over, newest first | 10 |
| `census_interval`, in windows — derived: τ₂ / standing_censuses, so the censuses span one period of adaptation | τ₂ / 10 = 2 016 |
| `standing_committee` — the votes the standing of an electorate draws in a window, in expectation, once it is wide enough to be sampled | 6 499 |
| `air_hash` — the constraint sets the proofs of this network are accepted under | 0fc05c930fca6dbfde9af0bd036dd90afd0f4337ed831d52f92990a2f3c20f06 |

**The volume the schedule is checked against.** Per machine, per window, across its chains:
eligibility strikes 1.1094 times in expectation; 0.6710 of machines publish one heavy
attestation of 339 321 bytes, and the remaining 0.4384 expected strikes publish light attestations
of 5 401 bytes — ≈ 230 KB per machine per window, flat in the count of chains, because the crowd of
a round carries the count of chains and spreads the strikes across them. Every machine that
published a heavy attestation pledges too, and since the author's record 295 a pledge is of
`pledge_len`, 339 263 bytes: in a window its agreement decides in attempt zero, the closing pledge of
each adds 0.6710 × 339 263 ≈ 228 KB, so ≈ 458 KB per machine per window, and each later attempt adds
its pledges beside it.
Frames add 110.6 MB per chain per window, payer-borne, and beacons add `target_rounds` objects of
`beacon_len` per chain per window — 24 KB, runner-borne — so the payload of a window decided in
attempt zero is `k · 110.6 MB + N · 458 KB`. What crosses the wire is that payload times what carriage costs: every
object of consensus stands at `consensus_replicas` points, and every envelope crosses at least
`hop_min` distinct machines. The cap of the schedule is the frozen ceiling of that product per machine, with both
multipliers in it, and neither is left to be discovered by whoever measures the wire. It caps the
count of chains and never the count of machines. The share
of that stream one machine carries falls as the population grows — the frames of a window
spread over every reachable device — so growth lightens carriage, and age adds no duty: what
a step of the schedule grows is capacity, paid in the shared stream and nowhere at a machine.
What grows with the population is the count of heavy attestations and of pledges, each a proof at
the presence's height, that each living machine verifies as they arrive; the envelope and the gate of entry bound that count, and the light
majority costs a signature check alone. **The young
network pays itself while it is everyone who exists:** the length of a window in rounds falls with
the population below the floor of the crowd and stands at the target above it, so windows pass
quickly in lived time while the geography is one room, and the credit of one coin for every second
of a window to every living machine pays a machine quickly in those early days — its coins of a
window last the lived length of that window, which is short while the network is small, and what a
window adds to the supply is the credit times the count of its living, which is small with it.

**Every parameter of the table is published.** The last to land was the hash binding the constraint
sets — the identifiers of the seven descriptions the network accepts proofs under. These bind
exact constraint bytes; they do not establish that every intended relation is implemented. With
them the whole Decree has an
encoding, and the Genesis State Hash exists: the value below is what the frozen procedure yields
over this table, computed by the gate on every build rather than remembered by anyone.

**The Genesis State Hash** binds the parameters to the state they open. Every parameter of the
table enters as an unsigned eight-byte little-endian integer, resolved to its numeric value and in
the order the table stands; a parameter written as a ratio enters as two such integers, numerator
first; a parameter written as a hash enters as its thirty-two bytes. After them stand the seven roots of the genesis state in the order a proposal carries them,
each the empty root of its own structure — the notes, the admitted machines, the credited rights
and the operations under the append-only construction, the nullifiers, the records and the machine
state under the sparse one:

```
genesis_state_hash = SHA-256("mt-genesis-state" || 0x00 || parameters
                             || note_root || nullifier_root || record_root || machine_root || admitted_root
                             || credited_root || operations_root)

                   = c4088d6b996dca3185a5089510bf3b3f047e5b339f538d713e28d0e954d94906

published_parameters = SHA-256("mt-genesis-state" || 0x00 || the parameters that are published,
                               in the order and the encoding above)
                     = a24f1ca2a688919cf660d3384324ce0fd12f37d14de12dfe4bb13d527411de1f
```

A chain whose value differs is not a fork of Montana but a different protocol, and honest
implementations refuse it at the first proposal rather than diverging from it later.

**Why both values stand here.** The first is the hash a chain opens on, and honest implementations
refuse a chain whose value differs at the first proposal. The second is the digest of the
parameters alone, without the seven roots, and it exists so that an implementation whose encoding of
the table has moved fails on the digest before it fails on the chain — the nearer alarm of the two.
Both are computed by the gate on every build; neither is remembered by anyone.

Every row above is a fixed number and enters that hash as such. Three of them
are divisors and a base consumed by rules whose other input is the state of a window — the
size of a committee, the capacity of a selection event, the pressure gate of entry, and the
boundary of an age bucket, which is the base raised to the index of the bucket and multiplied
by τ₂. The rules themselves are not numbers and do not live here: Consensus holds those of the
committee, of admission and of entry, and Identity holds that of the buckets. What Genesis
fixes is the constant each rule consumes, never the rule.

Every quantity this set consumes stands frozen above with its derivation, save one.

**The rule for a quantity not yet frozen.** Canon names it and gives it no value. Any document
that consumes such a quantity writes "awaits Canon" rather than "Canon fixes" — the present
tense asserts a value exists — and states that conformance over it is unachievable until the
value lands. Enforcing against a number nobody holds is the defect this rule exists to prevent.

Every other quantity this set consumes is frozen here with its derivation, and every rule is
checked by a vector frozen beside it. The length of a proof and the lengths that carry it follow
from the contents fixed above and from the parameters that size them, and they are frozen with
them: the slot of the out-of-domain evaluations covers the bound of the trace width rather than
following the width, so no length of this document waits on the artifact.

Every value of this document is frozen and every layout is reproducible from it. One thing is not
a value: the constraint set of the two circuits is a machine-checkable artifact, and this document
binds the network to it by `air_hash` rather than describing it in words — the section above states
what it must assert, the format its description takes, and the verifier that consumes it, all six
checks of which are frozen here. Until the reference artifact is published, `air_hash` carries **no value at all** — not a
stand-in, not a row of zeros, nothing — so no block of the whole Decree exists, no Genesis State
Hash exists, and no network starts. A number written in place of a value that does not exist is a
number some build ships and some chain opens on; the table names the parameter and why it is
missing, and every door that would compute over the Decree answers nothing while it is. Every other
byte of the protocol — the wire, the objects, the derivations, the commitment, the join — is
reproducible from this document alone.

**No measurement stands here, and none is missing.** The pace of a window is the derived
count of rounds, each one echo of an eligible machine drawn from the whole population; the
floor under the echo is the speed of light over the geography of the living, and Genesis
chooses nothing about pace except through geography: the network ticks where its people live.


### Forms

These fix the shape of what crosses the wire and what a circuit is built to, and a boundary
between eras may move a row of this block. The Genesis State Hash does not bind it: a boundary
that moves a form must leave that hash untouched, or a form could not move at all. What holds two
machines to one shape is then the row of the form table and the span of a drain, checked on the
wire rather than at the join — before the split a machine holding the wrong one failed the genesis
hash and never joined, and after it the machine joins and fails when it first speaks. What binds a
form is what proves over it: a form the circuits prove over — the depth of the note tree, the shape
of a frame — stays bound through the artifact `air_hash` binds, since a circuit built to another
shape is another artifact and another hash, while a form the circuits never touch leaves the
binding of the chain altogether.

The split is closed under derivation: no parameter is derived from a form. One relation would have
broken that — a population of the network derived from what its paths reach — and it is closed by
there being no such parameter: no row of the Decree bounds the count of machines, and none may be
added. What the reach of a path bounds is the reach of one delivery, which is a row of this block
and moves at a boundary at the price stated beside it, and nothing of the block of parameters is
derived from it.

| Form | Value |
|---|---|
| `spends_per_frame` | 3 |
| `spend_inputs` | 2 |
| `spend_outputs` | 2 |
| `items_per_spend` — derived: inputs plus outputs plus the rate position | 5 |
| `note_tree_depth` | 40 |
| `name_max_length` | 32 |
| `redundancy_num` over `redundancy_den` | 1 over 4 |
| `cell_bytes` — the one length of everything that crosses the wire | 1 232 |
| `erasure_group` — cells per group of a delivery, of which a quarter is parity | 16 |
| `path_max` — slots in the seal array of a cell, and therefore the reach of one delivery | 15 |

## Layouts

### The committed record of a person

A record of a person is never published: what reaches the network is a commitment to it. This
layout is therefore the **preimage** of that commitment — the bytes every implementation must
produce identically so that one record yields one commitment everywhere, and so that a proof
about it verifies for everyone.

```
serialize(record)
  segment_bitmap                   8 B   u64   the lived segments of the continuity period
  last_active_segment              4 B   u32
  opened_window                    8 B   u64   the window the record was opened in
  own_height                       4 B   u32   the number of the holder's own actions
  operator_nf                     32 B         the one-time right to raise a machine this record carries
  fabric_root                     32 B         the root of the leaves this holder witnessed
  suite_id                         2 B   u16
  current_pubkey                1952 B         the key that verifies the holder's next action
  blind                           32 B         the blinding factor of the commitment
```

**Invariants of the committed record:**

- The record is a preimage and never appears on the wire or in state; only its commitment does.
- `suite_id` is a row of the suite table, and `current_pubkey` is of the size that row demands.
- `opened_window` is written once, at opening, and carried unchanged into every successor: age is the distance from it to the current window, and a record able to rewrite it would buy standing it never lived.
- `operator_nf` is the one-time right to raise a machine of Canon, `sponge("mt-operator-nf", limbs(operator_secret))` over the holder's own branch. It is written once, at opening, and carried unchanged into every successor, and it is the value a candidacy spends: one record raises one machine, and a record able to rewrite it would raise a machine for every value it wrote. It stands at the limbs six to thirteen of the serialization, the first limbs after the four fields an opening binds.
- `own_height` never decreases across a succession, and a successor carries the height of its predecessor incremented by one.
- `segment_bitmap` holds one bit per segment and is wide enough for `max_entry_segments`, the greatest count of segments the gate of entry demands under pressure; bits above that count are zero. What a gate compares is the number of bits set, never a run of them: a person who missed a day and a person who missed none both pass while they hold the share. A narrower field would leave the raised requirement unprovable — a record cannot show segments it has no room to carry.
- `last_active_segment` names the segment the bitmap is written against, and the bitmap is read only after shifting it by the distance from that segment to the current one — a bitmap read without the shift measures continuity against a past that has moved.
- `last_active_segment` never exceeds the current segment and never decreases across a succession.
- `fabric_root` is the root of the fabric of time this holder has folded; it enters the commitment and never appears beside it, so witnessing publishes no object of its own. A record that has witnessed nothing carries the empty root of that construction.
- `blind` is drawn from a cryptographic source for every record, including every successor; a repeated blinding factor makes two commitments of one holder comparable and is a defect.
- No field of the record identifies its holder: there is no identifier of a person in this protocol, and a field bearing one would contradict the invariant on graphs.

The field set awaits Canon: it freezes together with the one open link the Constitution names, and
with nothing else. Until then an implementation reproduces the order and the widths above and
states that the set is not final rather than assuming it, and **conformance over this layout is
unachievable** — the rule this document states for a quantity not yet frozen applies to its own
layouts, and the conformance item that consumes this one says so.

### The opening of a record

What a claimant publishes to bring a record into being. It carries no key and no signature, and it
names no window: a verifier holds the window it is applying and the ceiling of openings that window
allows, and a field restating either would be a second place for them to stand.

```
serialize(opening)
  open_nullifier                   32 B         the extinguished one-time right of a person to open a record
  record_commit                    32 B         the commitment of the record this opening creates, and its key in the tree of records
  proof                     PROOF_LEN B         the right spent and the commitment opened, disclosing neither

opening_len = 32 + 32 + PROOF_LEN = 404 640 B
```

**Invariants of an opening:**

- Its length is exactly `opening_len`; an opening of any other length is refused before it is parsed.
- `open_nullifier` is the one-time right of Canon, taking no window and no index, so one seed opens one record and a second opening under it presents the identical value and collides.
- `record_commit` is the leaf of the tree of records over the record this opening creates, and it is the key that leaf stands at: a key derived from anything of the holder would join their openings to their actions.
- The proof asserts the opening of `record_commit` and the spending of the right, and asserts of the record that `own_height` is zero, that `segment_bitmap` is zero, that `last_active_segment` is the segment of the window being applied and that `opened_window` is that window — a record opened with a height or a lived segment already in it would buy standing it never lived.
- It demands no lived time and asserts none: the segments of a record begin at its opening, and a gate of time here would be a lock whose key lies inside it.
- It asserts nothing of `operator_nf`, and publishes nothing of it: the field is the holder's, it stands unread until a candidacy spends it, and the proof of that candidacy is the one that asserts its preimage. A record opened with a value no branch yields raises no machine, which costs its holder alone; a value bound here in public would join the record opened to the machine it later raises.
- A window admits no more openings than `max_openings_per_window`, in the canonical order of the window, so the outcome does not depend on the order of arrival at any machine.
- It carries no signature and no key, and an implementation that adds one names a person for the whole of their life.

### The action of a record

What a holder publishes to move their record from one version to the next. Anchoring a hash,
changing a key, witnessing and closing are one object: the plane publishes what a transition is and
never which transition it was, so a closure and a change of key are the same shape and the same
length.

```
serialize(action)
  record_nullifier                 32 B         the nullifier of Canon spending the version acted from
  successor_commit                 32 B         the commitment of the successor, and its key in the tree of records
  act_nullifier                    32 B         the nullifier of the rate of action of this window
  proof                     PROOF_LEN B         the transition lawful, the predecessor a member, the signature verified, disclosing all three

action_len = 32 + 32 + 32 + PROOF_LEN = 404 672 B
```

**Invariants of an action:**

- Its length is exactly `action_len`; an action of any other length is refused before it is parsed.
- `record_nullifier` is the nullifier of a version of Canon, taking the blinding factor and the commitment of the version acted from; a nullifier already present is refused in silence.
- `act_nullifier` is the nullifier of the rate of action of Canon, taking the window and no index, so a second action of one window presents the identical value and collides with the first. The two nullifiers are separate values and neither serves for the other: one bounds how often a version is acted from, the other how often a person acts.
- `successor_commit` is the leaf of the tree of records over the successor, and it is the key that leaf stands at. Where the action creates no successor it is a blank drawn by its emitter from its own randomness, and the proof asserts of that position that it holds either a successor or a closure without disclosing which — publishing two quantities where others publish three would make a closure visible by its shape.
- The proof asserts that the version acted from stands in the tree of records under the root the window carries, that the transition follows the rules of the record — `opened_window` and `operator_nf` carried unchanged, `own_height` incremented by one, `last_active_segment` and `segment_bitmap` moved by the rules of continuity, `fabric_root` the holder's own — and that the transition is signed by the key standing in the version acted from. The signature is a witness of that proof and no field of this object: a signature beside it would name the key, and a key names a person.
- It carries no field naming which of the four acts it is, no counter, no sender and no recipient: what an observer reads is that some version was spent and some commitment appeared.

### The proposal that closes a window

A proposal is what a runner publishes to close a window, and its length is one number for every
window ever closed. It carries the proof of one thing only — that the runner's ticket cleared the
draw — and the public facts the windows after it stand on: the count of the machines it admits, the
cement of its living, among whom its predecessor was decided, the roll of what it applied, and the
census the standing of the electorate is counted over.

```
serialize(proposal)
  window                            8 B   u64   the height being closed
  protocol_version                  4 B   u32   the rules this proposal is published under
  previous                         32 B         the identifier of the proposal before it
  note_root                        32 B
  nullifier_root                   32 B
  record_root                      32 B
  machine_root                     32 B
  admitted_root                    32 B         over the tree of admitted machines, appended at admission
  credited_root                    32 B         over the tree of credited rights, after the parts of the window before entered
  operations_root                  32 B         over the frames the window applied, in the order they applied
  roll                             32 B         the identifier of the roll: the frames applied and the parts of the cement
  admitted_count                    8 B   u64   the machines the tree of admitted machines holds
  cement_aggregate                 32 B         the aggregate over the parts of the window's cement: its living, among whom its predecessor was decided
  cement_count                      8 B   u64   how many parts that cement names
  census x standing_censuses                    newest first, by the rule of the standing of an electorate
    root                           32 B         the root of the tree of a census cement
    count                           8 B   u64   how many parts that cement names
  suite_id                          2 B   u16
  final_beacon                     32 B         the beacon its runner closed the window on, carrying the cement above
  runner_pubkey                  1952 B         the one-time key this proposal answers under
  ticket_proof     PRESENCE_PROOF_LEN B         the clearing of the runner's ticket, under the description of the ticket
  signature                      3309 B         over everything above, by the rules for a signed object

proposal_len = 8 + 4 + 9 x 32 + 8 + 32 + 8 + 10 x (32 + 8) + 2 + 32 + 1952 + PRESENCE_PROOF_LEN + 3309
             = 339 931 B
```

**The identifier of a proposal is taken over what the window decided** — the bytes from `window`
through `suite_id`, under the proposal domain of the registry:

```
proposal_id = SHA-256("mt-proposal" || 0x00 || serialize(proposal)[0 .. 750])
```

The reason is what reads the identifier. An attestation attests it and the sanction of a double
answer stands on a pair of them, so the name must be one no party can grind and one the window
decides rather than its runner. A proof carries randomness of its own, and a name taken over proof
bytes is a name its maker redraws by reproving. A name taken over the runner's key is a name every
runner of one window writes differently, and a name taken over the final beacon is a name every
branch of the versions of a round writes differently: machines closing one window on one cement
would attest as many names as the window had runners and branches, and the cement of the window
after it would part among them. The fields from `window` through `suite_id` offer neither freedom —
the roots and the census are recomputed by every verifier, the cement and the counts are what the
final beacon carried, and the roll is a function of the frames and the parts those already fix — so two runners that closed on one cement write one name whichever beacon of
whichever branch carried it, and either one's bytes are the proposal of the window. The final beacon
stands after the name as the evidence a device that was not there reads the cement and its votes
off; the votes stand in no field of the proposal, because two runners holding one cement may have
verified the ballots of its parts at different moments, and a name over a tally would part one
decision between them.

**Invariants of the proposal:**

- Its length is exactly `proposal_len`; a proposal of any other length is refused before it is parsed.
- Its identifier is taken under the proposal domain over the fields from `window` through `suite_id`, 750 bytes; an implementation hashing the whole object gives every proposal a name its runner can grind through the randomness of a proof, and one hashing through `final_beacon` or `runner_pubkey` gives two branches or two runners of one decision two names.
- `census` is the census of the standing of an electorate the rule of that section carries from the proposal before: at a census window the window's own cement — the root of its tree and its count — enters first and the oldest leaves, and at any other window it is carried as it stands. The electorate of the window two on reads its standing and its committee off it.
- `runner_pubkey` is one-time and answers for this proposal alone; a key seen for two proposals is a defect, and it names no machine and no owner.
- `protocol_version` carries the major component in its upper sixteen bits and the minor in its lower. A machine refuses a proposal whose major exceeds the one it implements, and refuses one whose value stands below its predecessor's — so rules never roll back inside one chain, and both rules the Constitution states are a comparison of this field.
- `previous` is the identifier of the proposal of the window before, so the chain of proposals is a chain by construction and round zero of every window stands on bytes that are fixed. The first window of a network has no proposal before it, and its `previous` is the Genesis State Hash, so the chain of every network begins at the parameters it opened on.
- The roots are recomputed by every verifier and never taken from the proposal on trust; `admitted_count` is the count of leaves of the tree `admitted_root` stands over, recomputed with it.
- `credited_root` is the root of the tree of credited rights after this proposal appended the parts of the cement of the window before it, ascending, less the parts its challenge convicted; the first window of a network appends nothing. A verifier recomputes it from the tree it holds and the decided roll of the window before, and a proposal whose root differs is refused.
- `roll` is the identifier of the roll of this proposal, laid out below: the identifiers of the frames the window applied, in the order they applied, then the parts of its cement, ascending. A machine replaying the roll recomputes `operations_root` from its frames and the cement from its parts, and a proposal whose roll does not replay to it is followed by no machine that did not take it.
- `cement_aggregate` and `cement_count` are the aggregate and the count of the cement of this window, its living machines whatever names they pledged: the state the beacon `final_beacon` carried, a count reaching the quorum of the electorate, which a machine of the window recomputed from the heavy attestations it held when it answered that beacon, and which a device walking a certificate reads off that beacon among the beacons of the certificate; a proposal whose pair differs is refused. They are what the electorate of the window two on and the draw of that window read, and `cement_count` is the coins the window credits, one to each of its living machines.
- `ticket_proof` asserts that the ticket drawn from the runner's secret and the cemented aggregate of the window two before clears the threshold of the draw, that the half the secret names stands in the tree of admitted machines of the electorate, and that the digest of the key this proposal answers under is the one the proof names — without disclosing the ticket, the secret or the machine. It stands at the height of the presence and is of its length.
- The signature covers every byte above it, and the rules for a signed object fix what is signed and how.

### The certificate of a window

The certificate of a window is not an object: it is the proposal that closed the window with its roll, together with
the heavy attestations of the window after it, the light attestations of that window answering the
final beacon its proposal names, the pledges of that window's agreement its decision
stands on and the ballots of their parts, which stand at their points exactly as they were
published. A device verifies a certificate as the living
verified its parts, and Consensus states the procedure.

**The proof a machine writes with a window it closed is the proposal, and never the certificate.**
When a machine closes a window it writes one record: the tables of its plane at that window, the
head, the number of the window closed, and as the proof of that transition the bytes of the
proposal that closed it — `proposal_len` bytes, its `ticket_proof` and its signature among them —
whose roots are the ones those tables recompute to. The certificate of that window cannot stand in
the record: it is made of the attestations, the pledges and the ballots of the window after it,
which do not exist when the window closes, so a record waiting on them would write the tables and
the head of one window apart. The certificate is what a device walking to the head verifies, from
the points where its parts are retained, and it enters the record of no machine (the Author's
decision of 27.10.2026 19:48 UTC, issue #19).

**Invariants of the certificate:**

- A certificate introduces no object, no signature and no key; its parts are a proposal with its roll, the heavy attestations of the window after it, the light attestations of that window answering the final beacon its proposal names, the pledges its decision stands on and the ballots of their parts, each of the layout and the length this document already fixes. A final beacon no verified attestation of the certificate answered closes nothing for a device, as it closes nothing for a machine of the window.
- The beacons of the rounds of a window, its heavy attestations, the light attestations answering its final beacon, the ballots and the pledges, the frames of its rounds and its proposals with their rolls survive at their points for `retained_windows` windows after the window closes; a deposit at a point of a past round is refused, and what stands there is held whole until the retention ends, the light attestations answering the window's other beacons among it and read by nothing; nothing of a round outlives the retention.

### The frame of a payment

A frame is what a payment publishes, and its length is the same for every frame ever sent.

The root the redemptions prove against is **not a field of it**: a proof stands under a leaf of
the horizon of proving — the fold of the standing stride of the window the frame applies in,
which every machine computes from roots it already holds — so every frame of a standing period
is verified against the same value, a sender chooses nothing observable by it, and nothing
about which root was used can be read from what is published.

```
serialize(frame)
  spend x spends_per_frame
    nullifier x spend_inputs         32 B each     what this spend consumes
    commitment x spend_outputs       32 B each     what this spend creates
    rate_nullifier                   32 B          the bound on payments per window
  proof                     PROOF_LEN B

frame_len = spends_per_frame x (spend_inputs + spend_outputs + 1) x 32 + PROOF_LEN
          = 3 x 5 x 32 + 404 576
          = 405 056 B

frame_id  = SHA-256("mt-frame" || 0x00 || serialize(frame))
```

The name of a frame is taken by the rule every identifier of this set is taken by: the class domain
of the object over its signed scope, which for an object carrying no signature is the whole of its
canonical bytes. It is what the notice of a spend names a frame by, and a reader that named a frame
by its bare bytes would name it differently from every other object of this set.

**Invariants of the frame:**

- Its length is exactly `frame_len`; a frame of any other length is refused before it is parsed, and the refusal costs one comparison.
- It holds exactly `spends_per_frame` spends whatever it means to pay: a spend that redeems nothing carries values drawn like any other, so the count of meaningful spends is not published by the shape.
- Every nullifier in one frame is distinct, and a repeat within a frame is refused without looking further.
- Every nullifier and every commitment of it reads as four unsigned eight-byte little-endian words, each below the modulus of the proof field: those values are digests of the proof hash, and bytes that are not one are refused before anything is proven against them.
- It carries no root and no window number: the horizon its redemptions prove into and the stride its rates and moments are ranged against are computed by the verifier from the window the frame applies in, by the integer form of the standing stride, and never taken from the frame.
- No field of it names anyone: there is no sender field, no recipient field, no amount and no index of a person, and a field bearing one would contradict the invariant on graphs.
- The order above is the canonical order, and an implementation reproduces the round trip in both directions.

### The confirmation of a window

A machine that has verified a window attests it with this object. It names no machine, no owner and
no address: what a reader learns is that a distinct participant attested these operations.

```
serialize(confirmation)
  window                            8 B   u64   the window attested
  attested_count                    2 B   u16   the number of identifiers below
  attested                            ?         attested_count x 32 B, ascending lexicographically
  part_nullifier                   32 B         the nullifier of this machine's part in this window
  round_nullifier                  32 B         bound to the beacon attested; one per machine per beacon
  line_value                       32 B         the line of the open slot of attempt zero at the abscissa of the name attested
  suite_id                          2 B   u16
  answering_key                  1952 B         the one-time key of this window, under the part domain
  proof           PRESENCE_PROOF_LEN B          under the description of the presence, at its height
  signature                      3309 B         over everything above

confirmation_len = 8 + 2 + 64 + 32 + 32 + 32 + 2 + 1 952 + 333 888 + 3 309 = 339 321 B
```

**What its proof asserts.** That the bearer is a machine of the electorate of this window: its
secret's one absorption, squeezed twice, yields a naming half standing at a leaf of the tree of
admitted machines under the root of the electorate, and a spending half from which `part_nullifier`
is the nullifier of the part of `window`; that the digest of `answering_key` is the one the public
input carries; and, since the author's record 309, that from that same spending half alone it draws
the lock-opening value, and from that half, `window` as one element and the open slot of attempt zero
it draws the slope of that slot, and that `line_value` is the lock-opening value plus that slope
times the abscissa of the name attested — the identifier among `attested` that is not the beacon of
its round — in the field the line is taken over ("The forfeit of a node lock, and the evidence that
moves it"). It discloses neither half, the place in the tree, the lock-opening value nor the slope.
Its public input is the root of the electorate, the digest of the key, `part_nullifier`, `window`,
the name attested and `line_value`, in that order (Consensus, "The attestation of presence"). The
derivations of the line are those of the pledge's proof, so the open slot of attempt zero has one
slope whichever object is read; they add at most four blocks to the presence's 108, and it stays at
`presence_rows_log2` ("The height of the presence, and the length of its proof").

**Invariants of a confirmation:**

- `attested` ascends lexicographically and holds no repeat; an implementation sorting it any other way produces a different identifier for the same attestation.
- `part_nullifier` is derived from the machine's secret and this window alone, so one machine yields one value per window; its first appearance enters the cement and every later one adds nothing, and what Consensus sanctions is one part-nullifier under one of the three contradicting pairs of pledges, two confirmations of one window attesting two names among them.
- Two confirmations of one `part_nullifier` are ordered by the chain and the round of the beacon each attests, ascending, then by `round_nullifier` compared as 32 bytes from the first, ascending, then by the name among `attested` that is not the beacon, ascending; the first stands and the second is refused (Consensus, "The sanction of a double answer").
- `attested` holds exactly two identifiers — the beacon of the round and the name its machine took of the proposal of the previous window, which is its pledge of attempt zero — ascending; `round_nullifier` is derived from the machine's secret and the attested beacon, so versions of one round yield distinct values and attesting them all is duty, while a repeat under one beacon is refused in silence.
- `answering_key` is the one-time key of this window and verifies this object alone; the key a machine answers the wire with is published nowhere, and a confirmation carrying it would name the machine across every window it ever attested.
- The proof asserts that the bearer is a machine of the electorate of this window, that the nullifier and the key derive from one secret, and that `line_value` is the line of the open slot of attempt zero at the name attested — disclosing none of them. It carries no weight: a part counts once in the cement or not at all.
- `line_value` reads as four unsigned eight-byte little-endian words, each below the modulus of the proof field, and bytes that are not one are refused before the proof is verified. It joins the confirmation to nothing: the slope of every slot of every window is its own. Two confirmations of one `part_nullifier` naming two names carry two points of one line, and that pair gives the lock-opening value (record 309).
- The length of this object is one number, 339 321 B: `attested` holds exactly two identifiers and every field above has a fixed width, and its proof is of the presence's height and length. A confirmation of any other length is refused before it is parsed.

**The light attestation** is the same object without `line_value` and without `proof`:

```
serialize(light_attestation)
  window                            8 B   u64   the window attested
  attested_count                    2 B   u16   two
  attested                         64 B         the beacon of the round and the name its heavy attestation pledged, ascending
  part_nullifier                   32 B
  round_nullifier                  32 B         bound to the beacon attested
  suite_id                          2 B   u16
  answering_key                  1952 B         the one-time key of this window, under the part domain
  signature                      3309 B         over everything above

light_attestation_len = 8 + 2 + 64 + 32 + 32 + 2 + 1952 + 3309 = 5 401 B
```

**Invariants of the light attestation:**

- It is valid only where a heavy attestation under the same answering key stands published for the same window, whose proof it inherits; until that heavy is seen it stands in escrow — neither admitted to a beacon's pulse nor refused — so that a heavy still in flight is never mistaken for a heavy that never existed.
- It pledges nothing: it carries the name its heavy attestation pledged, enters no quorum of the agreement and is no evidence of an equivocation, and one carrying another name than its heavy's is refused. Its key is the machine's own, its binding to a living machine already proven by the heavy it inherits.
- A machine's first attestation of a window is heavy and enters the cement; every later one is light and enters only the pulse.
- Its length is exactly `light_attestation_len`; a light attestation of any other length is refused before it is parsed.

### The ballot of a part

What a machine publishes beside its heavy attestation where the standing of its electorate is
sampled and its own standing drew a vote. It carries no key and no signature: its proof binds the
part, the window and the count, and nobody but the holder of the half that derived the part can
write one.

```
serialize(ballot)
  window                            8 B   u64   the window whose cement the part enters
  part_nullifier                   32 B         the part of that window the ballot answers to
  votes                             8 B   u64   the votes the standing drew, at least one
  proof                     PROOF_LEN B         under the description of the ballot, at the frame's height

ballot_len = 8 + 32 + 8 + 404 576 = 404 624 B
```

**What its proof asserts.** That the part is the nullifier of the spending half the proof holds and
of the window; that for every census window of the electorate the proof holds a bit, and where the
bit is one the part of that census under the same half stands in the tree of its cement, whose root
the census of the electorate carries; that the coin of every census under the same half, the census
window and the aggregate of the window two before falls below the threshold of the committee or does
not; and that `votes` is the count of census windows where both hold. Its public input is the part,
the window, the census windows, their roots, the aggregate, the threshold one byte to a limb in the
order of the rows of a comparison, and the count, in that order.

**Invariants of a ballot:**

- Its length is exactly `ballot_len`; a ballot of any other length is refused before it is parsed, and one casting no vote or more votes than `standing_censuses` is refused where it is read.
- A ballot counts for a part that entered the cement of its window and for no other: the heavy attestation of that part carries the proof of presence binding the part to an admitted machine, and the ballot binds its votes to the part through the half both derive from. A half other than that machine's yielding the same part is a collision of the proof hash.
- It is valid only against the census, the aggregate and the threshold of the electorate of its window, which every verifier computes; a ballot standing against any other is refused.
- Two ballots under one part count once, at the larger of their votes: a ballot can cast fewer votes than its standing drew and never more, so the larger is the one nearer the truth and no tally exceeds it.
- It names no machine and no census window: what a reader learns is that some machine of the electorate drew this many votes in this window, a draw whose expectation is its standing over the committee and which joins to nothing across windows.

### The pledge of a part

What a machine of a window publishes in an attempt of the agreement on the proposal of the window
before. It names no machine: what a reader learns is that some part of the electorate stood behind a
name in an attempt, on a quorum it names or on none. It carries the value of the line of its slot at
the abscissa of its name, and its own proof of that value (the author's record 295; "The forfeit of
a node lock, and the evidence that moves it").

```
serialize(pledge)
  window                            8 B   u64   the window whose part signs it
  attempt                           4 B   u32   the attempt of the agreement it is made in
  name                             32 B         the identifier of a proposal of the window before
  since                             4 B   u32   the attempt whose quorum it stands on, or 0xFFFFFFFF for none
  part_nullifier                   32 B         the nullifier of this machine's part in this window
  line_value                       32 B         the line of this pledge's slot at the abscissa of name
  suite_id                          2 B   u16
  answering_key                  1952 B         the one-time key of this window, under the part domain
  proof           PRESENCE_PROOF_LEN B          under the description of the pledge, at the presence's height
  signature                      3309 B         over everything above

pledge_len = 8 + 4 + 32 + 4 + 32 + 32 + 2 + 1 952 + 333 888 + 3 309 = 339 263 B
```

**What its proof asserts.** That the proof holds a secret whose one absorption yields the spending
half from which `part_nullifier` is the nullifier of the part of `window` ("The nullifier of a
machine's part"). That from that same half alone it draws the lock-opening value, and from that same
half, `window` as one element and the slot of this pledge it draws the slope of the slot. The slot is
the kind of the pledge, closing where `since` equals `attempt` and open otherwise, in `attempt`. And
that `line_value` is the lock-opening value plus that slope times the abscissa of `name`, in the
field the line is taken over. It discloses neither half, the lock-opening value nor the slope. Its
public input is `window`, `attempt`, `name`, `since`, `part_nullifier` and `line_value`, in the
order this layout carries them. The proof is of this scheme at `presence_rows_log2`, the height of
the presence, and so of `PRESENCE_PROOF_LEN` bytes, as the record asks. What fits the presence fits
it: its blocks are the absorption of the secret and the nullifier of the part, as the presence's,
and three short derivations and the line in place of the walk of the tree of admitted machines and
of the absorption of the one-time key, whose limbs dominate the count of the presence ("The height of
the presence, and the length of its proof"). The description of the pledge is a new description, so its identifier is the seventh
`air_hash` folds, after the ballot's, and `air_hash` moved with it.

**Invariants of a pledge:**

- A `since` equal to `attempt` makes a closing pledge, and a `since` below `attempt` or of `0xFFFFFFFF` an open pledge; a pledge whose `since` stands above its attempt and is not `0xFFFFFFFF`, or whose attempt is `0xFFFFFFFF`, is refused where it is read, and so is an open pledge of attempt zero, the heavy attestation being the one open pledge of that attempt.
- `answering_key` is the one-time key of the window and the key of the confirmation of the same part; a pledge whose part has no confirmation standing under that key stands in escrow, and one whose key is another is refused.
- `part_nullifier` is the part of the window, so a pledge joins to the confirmation of its own machine and to nothing across windows; Consensus counts a part once per kind and attempt and sanctions three pairs.
- `line_value` reads as four unsigned eight-byte little-endian words, each below the modulus of the proof field, and bytes that are not one are refused before the proof is verified. It joins the pledge to nothing: the slope of every slot of every window is its own, so one point of a line is indistinguishable from random to anyone not holding the half ("The forfeit of a node lock, and the evidence that moves it").
- A pledge whose proof does not verify under the description of the pledge against its public input is refused: it enters no quorum and is no evidence. A pledge the agreement counts therefore carries a value its part's half drew, and two of them in one slot on two names give the lock-opening value.
- Its length is exactly `pledge_len`; a pledge of any other length is refused before it is parsed.

### The roll of a proposal

The frames a window applied and the parts of its cement, in one body beside the proposal, whose
identifier the proposal's `roll` carries inside the scope of its name.

```
serialize(roll)
  window                            8 B   u64   the window of the proposal the roll belongs to
  frames                            4 B   u32   how many frames the window applied, at most frames_per_window
  parts                             8 B   u64   how many parts its cement names
  entry x (frames + parts)         32 B each    the frames in the order they applied, then the parts ascending

roll_len = 8 + 4 + 8 + 32 x (frames + parts) = 20 + 32 x (frames + parts)

roll_id = SHA-256("mt-roll" || 0x00 || serialize(roll))
```

One body suffices because both of its counts are bounded before it is read: the frames by
`frames_per_window`, the parts by the count of the electorate. A roll is therefore at most
`20 + 32 x (273 + T)` bytes, and it stands at the window points for as long as the frames it names.

**Invariants of the roll:**

- `frames` is at most `frames_per_window` and `parts` is the `cement_count` of the proposal; the frames are the leaves of `operations_root` in their order, and the parts are those `cement_aggregate` aggregates. A roll whose frames do not fold to that root, or whose parts do not aggregate to that pair, is not the proposal's.
- The parts ascend and hold no repeat, and each is the part of a confirmation of the window the proposal closes.
- A roll carries no key and no signature: it is verified by its identifier, which the proposal names.
- Its length is exactly `roll_len` of its own two counts; a roll of any other length, or whose `frames` exceeds `frames_per_window`, is refused before an entry is read.

### The candidacy of a machine

What a claimant publishes to enter the set of machines. It carries no key and no signature: the key
a machine answers with is published nowhere, so a candidacy is proven rather than signed.

```
serialize(candidacy)
  window                            8 B   u64   the window it is published in
  naming_half                      32 B         the half that names this machine, and what a selection event writes into the tree of admitted machines
  node_commit                      32 B         the commitment standing for the machine
  operator_nullifier               32 B         the extinguished one-time right to raise a machine
  suite_id                          2 B   u16
  proof                     PROOF_LEN B         the continuity met, the record a member, the right it carries spent, and the naming half of one reading of the secret

candidacy_len = 8 + 32 + 32 + 32 + 2 + PROOF_LEN = 404 682 B
```

**Invariants of a candidacy:**

- Its length is exactly `candidacy_len`; a candidacy of any other length is refused before it is parsed.
- `operator_nullifier` is the one-time right of Canon, taking no window and no index, and it is the `operator_nf` the claimant's record carries, so one record raises one machine and a second candidacy under it presents the identical value and collides. It enters the set of nullifiers when the candidacy applies, whether or not an event admits the machine.
- `node_commit` is the commitment of Canon over the answering key, its suite and a fresh blinding factor; the key itself appears in no field of this object. It is a field of this object and of its identifier, and it stands in the public input of the proof, so a proof made under one `node_commit` stands under no other: a relay rewriting the field of a candidacy it has seen presents a proof of another statement, and the node refuses it with the right unspent.
- `naming_half` is the half that names the machine, and it is what a selection event writes into the tree of admitted machines, whose leaf Canon folds over exactly that value — so what a candidacy publishes and what an admission records are one value. Without it an event would hold a commitment and be asked to write a half, and no rule would say how one becomes the other.
- Publishing it discloses nothing a machine does not disclose by being admitted: that tree is public and its leaf is that half. A candidacy that is not admitted publishes it too, and no later admission can be joined to that attempt — the right it spent is one-time, so there is no second candidacy under it and no success for a failure to be linked to.
- The proof asserts that the record, the right and the half come of one admissible state: a record standing in the tree of records under the root the verifier takes for this window, the `operator_nf` that record carries equal to `operator_nullifier` and to the sponge of a branch the claimant holds, and `naming_half` the second squeeze of one absorption of a secret the claimant holds. A claimant cannot spend one person's right to seat another person's machine, cannot pair a record with a right it does not carry, and cannot publish a half whose secret it does not hold.
- The public input is `window ‖ record_root ‖ naming_half ‖ node_commit ‖ operator_nullifier ‖ suite_id`, 138 B, each value in its own bytes. `window`, `node_commit` and `suite_id` bind no cell of the trace: they enter the transcript every proof opens with, and a proof stands under no other value of any of them. `window` is the field of this object, and a verifier applying another window refuses the candidacy before it verifies anything. `record_root` is no field of this object: it is the root of the tree of records the proposal of the standing stride's last window carries, the stride standing for `window` by the integer form of the horizon of proving, taken by the verifier from that one proposal — the same rule by which a frame walks a right against the root of admitted machines. Before the first stride stands no root does, and no candidacy applies.
- The proof asserts the lived continuity the gate of entry demands of this window, out of that same record, disclosing neither the record nor its history.
- It carries no signature and no key, and an implementation that adds one names a machine for the whole of its life.

### The three objects of a name

A name is taken by three objects and none of them is signed: a signature would name a key, and a
key names a person. **A class domain names one shape and never a plane holding several**: each of
the three takes a domain of its own, so the shape of an object is recoverable from its preimage
rather than inferred from its length. Two shapes under one domain would let two objects whose
canonical bytes coincide carry one identifier, and nothing in the form would say they differ — the
two spaces share the shape of a commitment and of a renewal, so a domain per space would not
suffice either. The identifier of each is therefore taken over the whole of its canonical
bytes, under the class domain of that object, there being no signature to
exclude.

```
name_commit_id = SHA-256("mt-name-commit-op" || 0x00 || serialize(name_commit))
name_reveal_id = SHA-256("mt-name-reveal-op" || 0x00 || serialize(name_reveal))
name_renew_id  = SHA-256("mt-name-renew-op"  || 0x00 || serialize(name_renew))
```

```
serialize(name_commit)
  commitment                      32 B         over the slot, a blinding factor and the chain tip

serialize(name_reveal)
  name_length                      1 B   u8    the length of the normalized name
  name                            32 B         the normalized name, zero-padded to the maximum
  blind                           32 B         the blinding factor the commitment was taken with
  contact_root                  1184 B         the encapsulation key of that slot

serialize(name_renew)
  slot                            32 B         the slot being renewed
  link                            32 B         hashes once to the value published before it

name_commit_len = 32 B
name_reveal_len = 1 + 32 + 32 + 1184 = 1 249 B
name_renew_len  = 64 B
```

**Invariants of the three objects of a name:**

- A commitment carries thirty-two bytes and nothing else; it names no slot, so nothing about it says which name was meant until a reveal arrives.
- A commitment spends the nullifier of a reach for its window, so one record takes at most one slot per window whether the slot is of a name or of a channel.
- A reveal carries no slot field: the slot is the hash of the normalized name and every verifier recomputes it, so publishing it beside the name would be a second source for one value.
- `name` holds `name_length` bytes of the normalized name followed by zeros to the fixed width, and every derivation reads the first `name_length` bytes — the padding enters no hash, and one length serves every lawful name.
- A reveal is accepted only within `name_reveal_windows` of the commitment it opens, and only for a slot no cemented commitment already holds.
- A renewal is accepted only when hashing `link` once yields the value published before it for that slot, and only within `name_renew_windows`.
- A commitment no reveal opens within `name_reveal_windows` is discarded, so committing accumulates nothing.
- A slot whose renewal does not come is released and carries nothing of whoever held it; this and the expiry above are the lifecycle bound this table stands on.
- None of the three carries a signature, a key, a record commitment or a nullifier of the identity plane, and an object bearing one is refused.

### A publication of a channel

A publication is a signed object of the wire, and it is the only object of a channel that carries
a signature: the objects that take the slot carry none, exactly as those of a name carry none.

```
serialize(channel_publication)
  slot                            32 B         the channel slot this publication belongs to
  window                           8 B   u64   the window it is published for, little-endian
  previous                        32 B         the head published before it, the slot for the first
  body_root                       32 B         the root of the tree over the pieces of the body
  signature                     3309 B         over everything above, under the key the slot published

channel_publication_len = 32 + 8 + 32 + 32 + 3309 = 3 413 B
```

Its identifier is taken under `mt-channel-pub-op` over its signed scope — every byte before the
signature, by the rule this document states for a signed object, and not over the whole of its
canonical bytes: a publication carries a signature, so the rule of a signed object is the one that
applies, and two signings of one content therefore yield one identifier. Its head
is the value the derivation above computes from `previous`, `body_root` and the window.

```
channel_commit_id = SHA-256("mt-channel-commit-op" || 0x00 || serialize(channel_commit))
channel_reveal_id = SHA-256("mt-channel-reveal-op" || 0x00 || serialize(channel_reveal))
channel_pub_id    = SHA-256("mt-channel-pub-op"    || 0x00 || serialize(channel_publication))
```

**Invariants of a publication:**

- The signature covers every field before it and is verified under the key the reveal of that slot published, in the suite that reveal carried; a publication whose signature does not verify is discarded without a reply.
- `previous` is the head of the publication before it and the slot itself for the first, so a reader who holds the slot verifies the whole chain forward and needs no other origin.
- `window` is the window the publication stands in; one publication stands per slot per window and a second is refused in silence.
- It is an object of the wire and never of consensus: it stands at the holder of its slot for the window, exactly as a deposit does, and no structure of the chain records that it existed.
- It carries no record commitment, no nullifier of the identity plane and nothing of whoever holds the slot.

### The objects of a channel

A channel is taken by three objects of the same shape, and the single difference is the value a
reveal publishes: the key its publications are verified under rather than the key a stranger
encapsulates to. The difference is what makes them separate objects rather than one, since two
values of two sizes in one field would be a field of two meanings.

```
serialize(channel_commit)
  commitment                      32 B         over the slot, a blinding factor and the chain tip

serialize(channel_reveal)
  name_length                      1 B   u8    the length of the normalized name
  name                            32 B         the normalized name, zero-padded to the maximum
  blind                           32 B         the blinding factor the commitment was taken with
  channel_root                  1952 B         the verification key of that slot
  suite_id                         2 B   u16   the row of the suite table that key belongs to

serialize(channel_renew)
  slot                            32 B         the slot being renewed
  link                            32 B         hashes once to the value published before it

channel_commit_len = 32 B
channel_reveal_len = 1 + 32 + 32 + 1952 + 2 = 2 019 B
channel_renew_len  = 64 B
```

**Invariants of the objects of a channel:**

- Each carries what the corresponding object of a name carries, save that a reveal publishes the verification key of the slot and its suite rather than the key a stranger encapsulates to; an object carrying both keys is refused.
- A reveal is accepted within `name_reveal_windows` of its commitment and a renewal within `name_renew_windows`, the same periods the objects of a name stand on: one plane of slots keeps one pair of periods, and a second pair would be a second clock over one mechanism.
- None of the three carries a signature, a record commitment or a nullifier of the identity plane; the key a reveal publishes belongs to the slot and to no person, and the signature a channel makes stands on its publications alone.
- A commitment spends the nullifier of a reach for its window, so one record takes at most one slot per window whichever space the slot belongs to.
- A slot of a channel is held by the first cemented commitment for it, and a second reveal for a held slot is refused: a channel is owned inside this protocol, unlike a number, which nobody owns here.
- The three carry no signature, no record commitment and no nullifier of the identity plane; the signature a channel makes stands on its publications and never on the objects that take its slot.
- A slot whose renewal does not come is released and carries nothing of whoever held it, so a channel abandoned by its holder returns to whoever takes it next.

## Conformance set

An implementation conforms to this document when all of the following hold.

1. It encodes every integer little-endian and unsigned, in declaration order, without
   padding, and reproduces the round trip in both directions for every class.
2. It computes every hash through the domain-separated primitive with the NUL byte, and it
   draws every domain string from the registry above and from nowhere else.
3. It reproduces `identifier(obj)` from signed scope, and it never feeds an identifier,
   a content field or a signature into an aggregate for a seed.
4. It builds the sparse tree with the stated leaf and node domains, the stated empty values,
   the stated bit order, and the stated direction convention.
5. It carries the parameters of the Genesis Decree bit for bit as they stand here, and it
   refuses a chain whose Genesis State Hash differs from the one they produce.
6. It rejects a record whose encoded length, suite, ordering or bounds violate the invariants
   stated beside its layout. This item **awaits Canon**: the field set of that layout freezes with
   the artifact the Constitution names, so an implementation reproduces the order and the widths
   and claims no conformance over them until the value lands.
7. It reproduces **every frozen vector of this document byte for byte**, from the domain-separated
   primitive and the empty values and the pinned walks of both trees through the note, the nullifiers of both rates and
   of a right to a coin, the tag and its step labels, the walk of the secret of a pipe, the seal of a step, the placement of a sender, the slot
   of a name and the slot of a channel, the tag of first contact, the handshake and the words of a
   seed. This item is the first an implementation
   should run and the cheapest to run: an implementation that reproduces the vectors has the hash
   layer right, and one that does not has it wrong whatever else it passes.
8. It derives every branch of a person only from the block that states them, and it takes no
   secret of a derivation from anywhere but the document that owns it.
9. It derives a channel slot, the key of a channel and the head of a publication under the domains
   this document names, resolves one written word to two unrelated slots in the two spaces, and
   refuses a second head for one slot within one window.
10. It carries the census of a standing from one proposal to the next by the rule of the standing
    of an electorate, folds the tree of a census cement over its parts ascending under the two
    doors of the cement, reads the committee off the standing alone — nought below its floor —
    draws the coin of a unit from the half that spends, the census window and the aggregate of the
    window two before, and reproduces the frozen vectors of that section and of the close.

Every row above is proven by comparison against a frozen vector. The one exception is the
acceptance of a proof, whose vector follows the artifact this
document binds by `air_hash`; the verifier itself, its transcript and its six checks are frozen
here and reproducible today.
