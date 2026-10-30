# The closure of a window: definitions, theorems and proofs

This note states, as theorems with proofs, what the verifier of a window's closure establishes and
under which assumptions. It is the paper half of item 1 of the audit list (issue #4). Its relation
is the one of [WINDOW-RELATION.md](WINDOW-RELATION.md), section 3; its acceptance matrix is that
note's section 4. The code it is a statement about is `crates/montana-node/src/certificate.rs`
(`verify_certificate`, `decided_of`, `judge`, `walk`), `crates/montana-node/src/agreement.rs`
(`Book`), `crates/montana-node/src/attest.rs` (`verify_heavy`, `verify_pledge`) and
`crates/mt-pulse/src/close.rs`. Line numbers of the Rust code refer to the tree of commit `19834ae`
of this clone, which differs from `835a361` among the Rust files in `agreement.rs` and
`tests/certificate_matrix.rs` alone, and which the commits after it on this branch leave unchanged;
line numbers of `formal/Window.lean` refer to the file named in section 9. Commits cited below that do not resolve
in this clone are marked as of another clone.

The standard is the author's: a complete mathematical closure, a formal proof on paper, and code
held stricter than the paper. Section 8 states, clause by clause, where the code meets the paper,
where it is stricter, and where it is weaker; section 9 states which statements are checked by
machine and by which tool; section 10 lists what remains to be discharged.

## 1. Objects

Bytes are compared as unsigned big-endian integers of their full width. `H` is SHA-256 under the
domains of `mt-codec::domain`; `P` is the Poseidon digest family of `mt-proof`. `card(S)` is the
number of elements of a finite set `S`.

- A **part** `p` is a 32-byte part-nullifier; a **name** `n` is a 32-byte proposal identifier.
- An **electorate** `E = (root, T, census, committee)`: `root` a digest of the tree of admitted
  machines, `T = admitted_count`, and `K = committee.expected` the expected votes
  (certificate.rs:31-38).
- A **heavy attestation** `a = (W, att, p, k, pi, sigma)`: window, the two identifiers it attests,
  part, one-time answering key, presence proof, signature (attest.rs:102-120).
- A **round** `r = (b, H_r, L_r, B_r)`: a beacon, the heavy and the light attestations that
  answered it, and the ballots standing beside them (certificate.rs, `Round`).
- A **pledge** `g = (W, attempt, n, since, p, k, sigma)`; it is *closing* when it stands on its own
  attempt and *open* otherwise (agreement.rs:21-27; mt-state layout.rs:773-781).
- The **quorum rule** `Q(c, t)`: `t ≠ 0`, `c ≤ t`, and `100 c ≥ 67 t` (close.rs:20-31; the ratio is
  `Entry::Ratio("confirmation_quorum", 67, 100)`, mt-genesis/src/lib.rs:99). The **committee rule**
  `V(v, K)`: `100 v ≥ 67 K` (close.rs:36-46). The rule of the agreement is
  `Q*(c, t, v, K) = Q(c, t) and V(v, K)` (close.rs:50-57, agreement.rs:39-51).

## 2. The predicate of a certificate

Fix a window `W`, an electorate `E`, a predecessor `P` (a proposal of window `W - 1`, or Genesis), an
aggregate `A` (the cement aggregate carried by the proposal of `W - 2`), a count of chains `c`, rounds
`R` and pledges `G`. Let `theta = round_threshold(T, c)`.

An attestation `a` of round `r` is **valid in r** when all of the following hold:

1. `a.W = W` and `r.b.window = W`;
2. `a.att` is two identifiers strictly ascending, one of which is `id(r.b)`; the other is its
   **pledged name** `name(a)` (certificate.rs:408-417);
3. `eligible(a.p, A, r.b.chain, r.b.round, theta)` (round.rs:60-69);
4. `a.sigma` verifies under `a.k` over the signed scope of `a`, under the one suite
   (attest.rs:289-314);
5. `a.pi` verifies under the description of the presence with public input
   `(E.root, a.p, P(key_digest(a.k)), W)` (attest.rs:228-248).

Define the **cement** `C` as the set of parts of the heavy attestations of all rounds of `R`; the
**key** `kappa(p)` as the key of the attestations of part `p`; and the **votes** `v(p)`, for `p` in
`C`, as the largest count among the ballots of `p` that verify against `(W, E, A)`, and `0` where
none does (certificate.rs:353-371).

**Definition (Pi_cert).** `Pi_cert(W, E, P, A, c, R, G)` holds, with closure `L`, exactly when:

- (C1) `P` is Genesis, or `P.window + 1 = W` without overflow;
- (C2) `theta` is defined (certificate.rs:267-272); the beacon of every round of `R` is of window
  `W` and has an identifier (:278-283), which the code demands of a round even where it carries no
  heavy attestation; and every attestation of every round is valid in its round;
- (C3) any two attestations of one part carry one key;
- (C4) `Q(card(C), T)`;
- (C5) the sum of `v(p)` over `C` is below `2^64` and satisfies `V(sum, K)`;
- (C6) `id(P)` is defined (:266) and the book of the window decides it: its heavy attestations counted as open pledges of
  attempt zero on their pledged names, and the pledges of `G` whose part is in `C` and whose
  signature verifies under `kappa(part)`, each part counted once per kind and attempt under the
  least of its pledges there by `rank` (agreement.rs:148-154, :177-192, :201-228;
  certificate.rs:377-384);
- (C7) the aggregate of `C` under `W` exists;

and `L = (W, aggregate(C, W), card(C), C ascending, v, S)`, where `S` is what the light attestations
answer under `kappa` (:324-352, :404); they refuse nothing, so they enter the closure and no clause.
`formal/Window.lean` states this predicate as `PiCert`, clause by clause. The
cement is defined, not opaque: `cementOf` builds it from the parts of the heavy attestations as
`Cement::add` fills its set (cement.rs:16-51, certificate.rs:310), so it holds each part once
(`cementOf_nodup`), a part stands in it iff an attestation of the certificate is of that part
(`cementOf_mem`), and it is ascending where the order of parts is a strict total order
(`cementOf_ascending`); (C4) and (C5) read it. Its limit: the clauses (C2.1)-(C2.5) are one opaque validity of
an attestation in its round, and the book of (C6), the ballot of (C5) and the aggregate of (C7) are
opaque functions too: the Lean proves that the code takes exactly these clauses, not the strength
of each check, which is the subject of section 3.

## 3. Assumptions

- **(A1) Collision resistance of SHA-256** (FIPS 180-4) under every domain in which the
  identifiers, the aggregate and the place are taken.
- **(A2) Strong unforgeability of ML-DSA** (FIPS 204) for the answering keys and the runner keys:
  no adversary produces a valid signature under a key it did not generate, on a scope that key did
  not sign; `eps_sig` bounds its advantage over the keys of a walk.
- **(A3) Knowledge soundness of the proof scheme** for the descriptions of the presence, the ticket
  and the ballot: from any adversary that outputs an accepting proof for a public input, an
  extractor obtains a witness satisfying the description, except with probability `eps_K` per
  proof. The value of `eps_K` is a function of the parameters of the scheme; obligation O-1 of
  section 10 is its derivation, whose whole sum reaches the target of Canon on the Johnson bound,
  a theorem (Canon, `proof_queries`, decision 4 of the author, 24.10, and the author's word of 24.10 21:21 UTC).
- **(A4) Collision resistance of the Poseidon family** of `mt-proof`, for the tree of admitted
  machines and the part-nullifier, and, for the ballot, the tree of a cement (O-6).
- **(A5) The description of the presence** enforces that the leaf of the naming half of a secret
  `s` stands in the tree of `root`, that `p = part(s, W)`, and that the key digest is a public
  input bound to the proof (obligation O-2). **The description of the ballot** enforces, for the
  public part `p`, window `W`, census windows and roots of `E`, aggregate `A` and committee
  threshold, that the published count is at most the number of census windows of `E` whose cement
  holds the part the spending half of `p` derives for that census and whose coin clears the
  threshold, each counted at most once: the bound from above (O-6). A lower count can be written
  only by the holder of that spending half, as an abstention (F-539-1, a recorded property). **The
  description of the ticket** enforces that the leaf of the naming half of a secret stands in the
  tree of `root`, that the ticket of its spending half under `A` clears the draw threshold, and that
  the runner's key digest is a public input bound to the proof (O-6).
- **(A6) The admitted count is the count of leaves.** For every final proposal, `admitted_count`
  equals the number of distinct leaves of `admitted_root`: a state invariant carried by the roots
  of state, which every member of the deciding quorum recomputes (WINDOW-RELATION.md section 3,
  "Proposal"; obligation O-4).
- **(A7) The fault bound.** In every electorate the adversary holds the secrets of at most `f`
  admitted machines, with `100 f` below `34 T`.
- **(A8) Honest conduct.** A machine whose secret the adversary does not hold signs no contradicting
  pair of pledges in the sense of agreement.rs:71-90, answers under one key per window
  (attest.rs:49-53), and pledges a name only after recomputing the roots it carries. Its heavy
  attestations count as its open pledges of attempt zero (agreement.rs:177-192), so among them too it
  makes no contradicting pair: all heavy attestations of an honest part in one window pledge one name,
  whichever two certificates hold which of them.

## 4. Lemmas

**Lemma 1 (order).** `verify_certificate` returns `Ok` iff (C2) and (C3) hold together with the
remaining clauses, whatever the order of the rounds, of the attestations within them and of the
pledges.

*Proof.* The key map is extended only after an attestation verifies (certificate.rs:300-309), and
the second-key refusal at :293-299 reads only that map. If (C2) holds, the map at any point holds
the key of every earlier attestation of the part, so the refusal fires iff (C3) fails. If (C2)
fails, the first invalid attestation is refused at :284-292 or :300-307, or a second key is refused
before it is reached; in both cases the result is `Err`. The cement is a set; the ballots are read
after every part stands (:353-371) and the largest count is kept; the book counts a part, per
kind and attempt, under the least of its verified pledges there by the name ascending as 32 bytes
and then `since` descending, `STANDS_ON_NONE` being the greatest `u32` and so first
(agreement.rs:148-154, `rank`; :201-228, `Book::pledge`), and its evidence is the contradicting
pairs among the part's verified pledges, whose order in `Book::contradictions` no verdict reads
(:101-124, :216-218). The two dependences on order were the pledged name of a part in attempt zero
and the counted pledge of a part of one kind and attempt. The first is now that of the first heavy
attestation of the part in the canonical order (Consensus, "The sanction of a double answer"):
`Book::heavy` keeps the least `(place, name)` of the part, `place` being chain, round and round
nullifier (agreement.rs, `Place`). The second is the least pledge by `rank`, the canonical order of
the pledges of one part, kind and attempt that Consensus states beside that of the heavy
attestations (docs/Montana Consensus.md:613-616, :816). A least element of a total order, and a set
of pairs, do not depend on the order the elements are handed in (findings F-431-4 and F5 of review
526, closed, section 8). ∎

**Lemma 2 (exactness).** `verify_certificate(W, E, P, A, c, R, G)` returns `Ok(L)` iff
`Pi_cert(W, E, P, A, c, R, G)` holds with closure `L`.

*Proof.* Clause by clause against the code: (C1) :261-265; (C2) :267-272, :278-292 and :300-307
with attest.rs:205-249; (C3) Lemma 1, :293-299; (C4) :372 and :209-221 with close.rs:87-90 and 12-31, the refusal of `t = 0` and of `c` above `t`
standing at close.rs:21; (C5) :373 with :183-195 and :225-240; (C6) :266 and :377-394, a pledge whose
part is outside `C` or which fails `verify_pledge` adding nothing; (C7) :395-397; the closure :398-405. Every multiplication is taken in
`u128` over operands below `2^64` and factors of at most 100, so none overflows; the checked forms
refuse rather than wrap. ∎

**Lemma 3 (one part, one machine).** Under (A3)-(A6), except with probability `N eps_K` over `N`
verified presence proofs, distinct parts of verified attestations against one root and one window
come from secrets with distinct leaves. Hence `card(C) ≤ T`, and at most `f` parts of `C` come from
secrets the adversary holds.

*Proof.* Extract `s` from each proof (A3): by (A5), `leaf(s)` stands in the tree of `root` and
`p = part(s, W)`. The description reads the two halves of the secret as one absorption squeezed
twice (presence.rs:15-20, 103-108): the half that spends is taken at the seam of the first squeeze
and wired into the absorption of the part-nullifier (presence.rs:152-162; nullifier.rs:112-125),
and the half that names, of the second squeeze, is what the leaf is taken over; the window is a
boundary the verifier supplies (presence.rs:134-140). Two parts `p ≠ p'` of one window therefore
have `s ≠ s'`, and if they stood under one leaf the two secrets would give one half that names: a
collision of the map from a secret to its naming half, which (A4) excludes. The map from parts to
leaves is injective, so `card(C) ≤ T` by (A6), and the parts of the adversary's secrets number at
most `f`. ∎

**Lemma 4 (quorum intersection).** For finite sets `S1, S2` within a universe of `T` elements with
`Q(card(S1), T)` and `Q(card(S2), T)`, `100 card(S1 ∩ S2) ≥ 34 T`.

*Proof.* `card(S1 ∩ S2) ≥ card(S1) + card(S2) - T`. Multiply by 100 and use `100 card(Si) ≥ 67 T`:
`100 card(S1 ∩ S2) ≥ 134 T - 100 T = 34 T`. ∎

**Corollary.** Under (A7), two quorums of one electorate share a part whose secret the adversary
does not hold.

## 5. Agreement

**Theorem 1 (one decision per window).** Under (A1)-(A8), except with the probabilities of Lemma 3
and `eps_sig`, no two books of one window over one electorate decide two different names.

*Proof.* Let book `B1` decide `X` at attempt `a` and book `B2` decide `Y ≠ X` at attempt `b`; the two
books may hold different pledges. Every pledge either counts stands under a key proven by a heavy
attestation of its part (certificate.rs:377-384), so under (A2) a counted pledge of an honest part
is one that honest machine signed. All parts lie in one universe of at most `T` leaves (Lemma 3).

Case `a = b`. The closing pledges of attempt `a` on `X` in `B1` and on `Y` in `B2` each reach the
quorum; by the corollary an honest part signed two closing pledges of one attempt on two names, a
contradicting pair (agreement.rs:71-74), which (A8) excludes.

Case `a` before `b` (the other is symmetric). `B2` counts a closing pledge on `Y` at `b` only where
`(b, Y)` is an open quorum of `B2` (agreement.rs:263-266). Claim: for every attempt `e` not before
`a`, no book holds an open quorum `(e, Z)` with `Z ≠ X`. Induct on `e`. The counted open pledges of
such a quorum stand on none or on an open quorum `(e', Z)` with `e'` before `e`
(agreement.rs:240-244). By the corollary an honest part `h` closed `X` at `a` in `B1` and opened `Z`
at `e` in the open quorum. If `e = a`: a closing pledge on `X` counts at `a` only where `(a, X)` is
an open quorum of `B1`, so an honest part opened two names in one attempt, which (A8) excludes. If
`e` is after `a` and the open pledge of `h` stands on none or on an attempt before `a`, the pair is
the third contradiction (agreement.rs:81-90), which (A8) excludes. Otherwise it stands on
`(e', Z)` with `e'` not before `a` and before `e`: an open quorum on `Z ≠ X`, excluded by the
hypothesis of induction. Taking `e = b` and `Z = Y` gives the contradiction. ∎

## 6. Completeness and soundness of the certificate

**Theorem 2 (completeness).** If every attestation of `R` was produced by an honest machine of `E`
in a round it was drawn for, every pledge of `G` by honest machines, the honest parts reach
`Q(card, T)`, their ballots cast the votes their standing drew with `V(sum, K)`, and the book of
their pledges decides `id(P)`, then `verify_certificate` accepts.

*Proof.* Each clause of `Pi_cert` follows from the honest producer (attest.rs:38-120: the key from
the seed of the window, the proof from the secret, the attested pair ascending) and the
completeness of ML-DSA and of the proof scheme; (C3) from one key per window; then Lemma 2. ∎

**Theorem 3 (soundness).** Under (A1)-(A8), except with probability `N eps_K + eps_sig`, if
`verify_certificate` accepts then (i) a set of parts of distinct admitted machines reaching
`Q(card, T)`, at most `f` of them the adversary's, attested window `W` against `E.root`; (ii) the
agreement of a quorum decided `id(P)`, and by Theorem 1 no certificate of `W` decides another name;
(iii) the votes counted for each part are at most the votes its standing drew in `W`.

*Proof.* (i) Lemma 2, clauses (C2) and (C4), and Lemma 3; the parts of the closure are the cement,
each once and each the part of a verified attestation (cement.rs:33-51, certificate.rs:300-310).
(ii) Clause (C6) and Theorem 1. (iii) Clause (C5) and the knowledge soundness of the ballot (A3), the
ballot being verified against the census of `E`, with (A5) read for the ballot description: that the
description enforces the count it publishes to be at most the votes the part's standing drew in `W`
over the census of `E` (obligation O-6, discharged: read off ballot.rs, the bound from above holds,
and a count below it is the abstention of the holder of the spending half, which (iii) allows). ∎

**The matrix of WINDOW-RELATION.md section 4, row by row.**

- A window of distinct admitted machines reaching the quorum, honest roots, owned ticket — accepted:
  Theorem 2.
- Count strictly below the quorum — refused: (C4), close.rs:21-30.
- A presence proof against another electorate root — refused: (C2.5) and (A3).
- A repeated part-nullifier — counted once: the cement is a set (by machine: `cementOf_nodup`, and
  `soundness_parts`, whose closure counts a list of parts without repeat); (C3) for its key.
- An attestation signed by a key the presence proof does not name — refused: (C2.5), the key digest
  being a public input.
- A proposal whose roots differ from the recomputed ones — refused: `judge` with roots,
  certificate.rs:682-708.
- A proposal signed by a key another machine's ticket names — refused: certificate.rs:737-756, the
  runner digest being a public input.
- A predecessor that is not the final proposal of `W - 1` — refused: certificate.rs:659-663 and (C1).
- An observer given the serialized proofs alone — recovers no spending half: the hiding argument of
  WINDOW-RELATION.md section 5.
- A final beacon below the quorum, naming more parts than its certificate verified, or not linked to
  round zero and the predecessor — refused: `decided_of`, certificate.rs:464-519; see F-431-2 and
  F-431-3 for the two clauses of section 3 it did not check; the pair is now recomputed from the
  roll by `cement_of_roll` (decision 3), and a final beacon no verified attestation of the
  certificate answered is refused (F-431-2, closed on the author's word of 24.10 21:21 UTC).
- Two runners, or two branches of one round, of one decision — one identifier: `decided_identifier`,
  certificate.rs:601-625.
- The running node's own close — as above: one door, `verify_certificate`.
- A device walking from an anchor — the head is the pair of the latest step whose certificate
  verified, both its proposals final: Theorem 4.

## 7. The walk

**Theorem 4 (the head).** Let the anchor `(X0, X1)` be the final proposals of windows `w` and
`w + 1`, a proposal `X` of window `v` being *final* when the agreement of window `v + 1`, under
the electorate the final proposal of window `v - 1` fixes, decided `id(X)`. Under (A1)-(A8),
except with the probabilities of Theorem 3 over the certificates the walk verifies, if `walk` returns
`(Y, Z)` then: both proposals of every pair the walk kept are final; the kept pairs chain back to
the anchor, the earlier proposal of each being the later one of the pair kept before it; and `(Y, Z)`
is the anchor where the walk kept no pair, and otherwise the pair kept at the latest step, `Y` and
`Z` final, every other kept pair having verified at an earlier step.

*Proof.* Induction from the anchor. Let `G(X)` say that `X` is final; `G(X0)` holds. *The step.*
At step `j` the walk verifies the certificate of `later`, of window `W = later.window + 1`, under
`Electorate::of(earlier)` and `earlier.cement_aggregate` (certificate.rs:804-820), or carries the
certificate verified one step before (:809-810). If `G(earlier)`, that electorate is the genuine
electorate of `W`, the one the proposal of `W - 2` fixes, and (A6) and (A7) hold for it; by
Theorem 3 (ii) the agreement of a quorum of it decided `id(later)`, and by Theorem 1 no certificate
of `W` decides another name, so `G(later)`. This is Theorem 3 (ii) for one certificate under a
genuine electorate, and it is asked only of a genuine `earlier`: a forged `earlier` fixes an
electorate of the adversary's own machines, under which a certificate of any `later` verifies.
*The induction.* The walk keeps a pair only after its certificate verified (:821-824), and the pair
kept next has as its earlier proposal the later one of this pair: a candidate is taken only where
the judge accepts it and, where a step follows, the certificate of that step verifies with it as
predecessor (:849-893), and that certificate is carried into the step (:894-898). From `G(X0)` the
step gives `G` of both proposals of every kept pair. The pair kept at step `j` verified at step `j`,
so the head, the first of the kept pairs, is that of the latest step. Where no step follows, the
candidate is taken after `head` was fixed at :821-824 and never becomes the head. ∎

`formal/Window.lean` proves this as `walk_head` with `G` a free property of proposals and the step
as a hypothesis (section 9); it states no window and no uniqueness: "final" and "the one name of its
window" are the reading of `G`, which the step brings from Theorem 3 (ii) on paper.

The roots of a proposal a device behind takes are those the quorum that decided it recomputed:
(A8) makes an honest part pledge a name only after recomputing the roots, and by Lemma 4 and (A7)
every deciding quorum holds an honest part.

## 8. Code against paper

**Stricter than the paper.** `judge` refuses a proposal under rules above `implemented_major`
(certificate.rs:664-668) or rolling the version back (:669-673), any suite but the one, and any key or
signature of another width; `links_to` refuses a round past `u32::MAX` (round.rs:108-110); every count past
`u64` is refused and never wrapped.

**Weaker than the paper — findings.**

- **F-431-2 (closed, 24.10 21:21 UTC, the author's word "work by the specification"; see below).** `decided_of` takes the final beacon from any round of the certificate
  (certificate.rs:471-477), including a round whose beacon no verified attestation answered.
  WINDOW-RELATION.md section 3, "Close", names the final beacon as one "which a verified
  attestation answered". Required: the final beacon is answered by a verified heavy attestation
  of the certificate.
- **F-431-3 (closed, 24.10, decision 3 of the author).** `decided_of` bounded the final beacon's count by the certificate's
  (certificate.rs:508-512) and does not recompute its `cement_aggregate` from verified parts.
  WINDOW-RELATION.md section 3, "Cement": "Every verifier recomputes both from the attestations it
  holds and refuses a beacon whose state is not that pair." Required: the pair of the final beacon
  is the aggregate and the count of a set of verified parts of the certificate. Theorem 4 does not
  rest on F-431-2 or F-431-3: the head is fixed by the agreement of the window after, which decides
  an identifier carrying the final beacon and the pair. A proposal taken on the last step, which is
  not the head, did rest on them.
  *How decision 3 closes them.* Consensus 7.2.0, "The join", 3, now reads: "The device recomputes
  that pair rather than reading it off the beacon, by the rule a machine of the window applies when it
  replays a roll: the roll whose identifier `N` carries, standing beside `N`, names parts ascending
  and without repeat, each the part-nullifier of a heavy attestation of the certificate just
  verified, in the number `N` carries as the count of its cement, and aggregates with the window as
  context to the aggregate `N` carries." The step of the walk carries the rolls (`Step::rolls`,
  certificate.rs; `join` collects them with `rolls_of`, pulse.rs) and `walk` calls
  `cement_of_roll` after `decided_of` and before `verify_successor`. F-431-3 is closed: a pair that
  is not the aggregate of verified parts is refused (tests `walk` in a_walk_from_an_anchor.rs: a
  final beacon with an aggregate that is no cement; a final beacon over the pair of a set holding a
  part no verified attestation carries; a proposal whose roll was not handed in). F-431-2 is not
  closed as the finding stated it: "which a verified attestation answered" cannot be checked from a
  certificate of heavy attestations alone, since a round may be answered by light attestations only
  (pulse.rs:548-550, 828-833) and a certificate carries none, and the author chose the roll and not the
  lights. What a device now holds of the final beacon is that its pair is the cement of verified
  parts; the beacon itself stands outside the name of the proposal (Canon, "The proposal that closes
  a window"), so an unanswered beacon carrying a verified pair decides nothing the pair does not.
  If the specification is to require the answer, the certificate must carry the light attestations
  of the final round: a question for the author, not changed here.
  *How the author's word closes F-431-2.* Asked whether to put the light attestations of the final
  round into the certificate, the requirement "which a verified attestation answered" of Consensus,
  "The beacon a window closes on", standing, or to drop the requirement, the author answered "work by
  the specification" (24.10 21:21 UTC): the requirement stands. Consensus 7.3.0 and Canon 9.5.0, "The certificate
  of a window", now name in the certificate the light attestations of the window after answering the
  final beacon its proposal names, verified under the key their part's heavy attestation proved and
  on the name it pledged, and the retention keeps them beside the heavy ones; "The join", 1 to 3, asks
  for them and judges the final beacon "which an attestation of the certificate verified in 2
  answered". In code `Round` carries `light`, `verify_certificate` collects in `Closure::answered`
  every beacon a verified heavy or light attestation answered (a light one that does not verify
  answers nothing and refuses nothing, as a ballot or a pledge), `decided_of` refuses a final beacon
  outside that set ("a final beacon no verified attestation of the certificate answered"), and `join`
  reads the light attestations of every round (`rounds_standing`, pulse.rs). Tests:
  `a_final_beacon_no_verified_attestation_answered_closes_nothing` (certificate_matrix.rs) and the
  last block of `a_device_walks_from_its_anchor_to_the_head_and_no_further`
  (a_walk_from_an_anchor.rs).
- **F-431-4 (closed, 24.10, decision of the author).** In attempt zero the pledged name of a faulty
  part was that of its first heavy attestation in the order handed in (agreement.rs:112-118 of the
  tree the finding was read in, a commit of another clone; `Book::heavy` now stands at :181-192).
  Theorem 1 does not rest on it, the part being the adversary's either way; but two verifiers given
  one certificate in two orders could count that part under two names. Closed by the definition the
  reading below found missing: Consensus, "The sanction of a double answer", now states the canonical
  order of the heavy attestations of a window (chain, round, round nullifier, and the pledged name
  for a tie), Canon, "The confirmation of a window", states its bytes, and `Book::heavy` takes the
  place of the attestation and keeps the first (agreement.rs, `Place`, `Book::heavy`). Test:
  `the_first_heavy_attestation_in_the_canonical_order_stands_whatever_the_order_handed_in`, which
  refuses an implementation keeping the first handed in. The earlier wording of the finding asked for
  a contradiction counted under neither name; the author chose the first of the order, which is the
  rule the sanction already states. The live pulse still refuses a second heavy attestation of a part
  naming another name by arrival (pulse.rs, `gather_saying`), so its own book holds what reached it
  first; the book of a certificate does not depend on it. Of the pledges, neither the pulse nor a
  certificate keeps one by arrival: `gather_pledge` (pulse.rs:652-667) and `verify_certificate`
  (certificate.rs:377-384) hand every verified pledge to `Book::pledge`, which counts the least by
  `rank`, so the book of a machine, like that of a certificate, is a function of the set of pledges
  it verified (F5, below).
- **F5 of review 526 (closed in code, 25.10, `19834ae`).** `Book::pledge` kept the first pledge of a
  part, kind and attempt in the order handed in (agreement.rs:185-199 of `835a361`), and
  `verify_certificate` hands the pledges in the order of the certificate (certificate.rs:377-384).
  With `T = 4`, all four heavy attestations on `X`, two honest parts closing attempt zero on `X` and
  a faulty part closing it on `X` and on `Y`, the order `bX, bY, h1, h2` decided `X` and the order
  `bY, bX, h1, h2` decided nothing: a relayer could reorder a valid certificate into a refusal,
  against Consensus, "The sanction of a double answer" ("never by the order of arrival at a
  machine", docs/Montana Consensus.md:814), which then stated a canonical order of the heavy
  attestations alone. The book now counts, of the verified pledges of a part of one kind and
  attempt, the least by `rank`: the name ascending as 32 bytes, then `since` descending
  (agreement.rs:148-154, :219-226), and Consensus states this order (:613-616, :816). It is not the
  order first proposed, `(name, since)` ascending: `STANDS_ON_NONE` is the greatest `u32`, and an
  open pledge standing on none counts wherever one on the same name standing on an attempt counts
  (agreement.rs:241), so `since` ascending would count a part's pledge on an attempt in place of
  its pledge on none and could lose a quorum the part fills; descending puts none first. Every pair
  of a part's verified pledges the set calls a contradiction is evidence, whichever of the two
  counts, the lesser name first in a pair of one kind and attempt (:101-124, :216-218); a
  repetition of attempt, name and `since` adds nothing (:212-215). Theorem 1 is untouched: the
  pledges a book counts are one per part, kind and attempt, the book it quantifies over, and an
  honest part signs one pledge per kind and attempt (A8). The choice moves only what a faulty part
  adds by a second pledge in one slot: with the other name below `X` the part counts on it and `X`
  is not decided, the mirror of the case above under any rule that counts one name; what the honest
  parts reach alone it never takes away. Tests:
  `a_part_closing_on_two_names_counts_under_the_lesser_in_every_order` (agreement.rs, the scenario
  in all 24 orders: with the other name above `X`, `X` decided in each, with it below, nothing
  decided in any, and one pair of evidence in each) and
  `the_order_the_pledges_are_handed_in_changes_no_verdict` (certificate_matrix.rs, one certificate's
  pledges in two orders through `verify_certificate`: one verdict, accepted where the lesser name is
  the predecessor and refused where it is not), each of which refuses an implementation keeping the
  first pledge handed in; `of_two_open_pledges_on_one_name_the_one_standing_on_none_stands`
  (agreement.rs, all 24 orders) refuses one ordering `since` ascending.
- **Reading of F-431-2 to F-431-4 against the specification (24.10, Agent 432).**
  - F-431-2 and F-431-3 quote WINDOW-RELATION.md section 3, which states the conduct of a machine
    of the window. What a device that was not there verifies is stated in Consensus, "The
    certificate of a window" (docs/Montana Consensus.md:815-830): presence proofs, signatures,
    pledge keys, distinct parts, the counting of the agreement, ballots, votes, and the proposal's
    ticket and signature. It names neither an answer to the final beacon nor a recomputation of its
    pair, and the certificate carries what neither needs: heavy attestations and ballots, no light
    attestation (a final beacon answered by lights alone has no heavy beside it, pulse.rs:548-550,
    828-833) and no roll (the parts of the pair stand in the roll, pulse.rs:1939-1954, which no
    `Step` carried then; `Step::rolls` came with decision 3). Requiring either in `decided_of` would refuse honest walks. The two stay open as
    a question of the specification: a step carrying the roll of the proposal would let the device
    recompute the pair by the rule `replay` already applies. The head does not rest on them
    (Theorem 4).
  - F-431-4 is a divergence of code from the specification: Consensus, "The sanction of a double
    answer" (docs/Montana Consensus.md:814): "The first appearance stands and the second is refused,
    by the canonical order of the window and never by the order of arrival at a machine."
    `Book::heavy` kept the first in the order handed in (agreement.rs:112-118 of the tree read then,
    another clone; now :181-192) and recorded no
    contradiction. An open pledge of attempt zero other than the heavy cannot arise
    (layout.rs:759-765 refuses it at parsing), so the case is exactly two verified heavy
    attestations of one part on two names. The specification does not define the canonical order
    of the heavy attestations of a window -- the phrase stood at Consensus.md:812, Canon.md:4832 and
    Identity.md:124 without a definition -- so the fix waited on that definition (C-2: an ambiguity
    is flagged before code); the author decided it on 24.10 and Consensus 7.1.0 states it.
- **F-431-1 (closed).** The comment at round.rs:71 said round zero links to "the proposal of the
  window before"; certificate.rs:456-460 and the Canon it quotes say "two before", and `walk` passes
  the proposal of `W - 2` (:853-864). The pulse agrees with the Canon: `Pulse::open` takes
  `stands_on`, "the proposal of the window two before, which round zero links to" (pulse.rs:223-225),
  and its caller hands the identifier of `two_before` (pulse.rs:1270-1285). The comment now says so.

## 9. Checked by machine

- **Lean 4** (`formal/Window.lean`, Lean 4.35.0, core library only, no `sorry`, no axiom of its
  own; `#print axioms` names only `propext`, `Quot.sound` and `Classical.choice`):
  `quorum_intersection` (Lemma 4 over the naturals under the integer rule of close.rs,
  `100 c ≥ 67 T`, with inclusion-exclusion as a hypothesis, by `omega`); `more_than_the_faulty`
  (its corollary under `100 f < 34 T`); `meet_of_rule` (the Corollary on sets: two quorums of parts
  within a universe of at most `T`, each a list without repeat reaching `Q(card, T)`, share a part
  outside a list of at most `f` bad parts, `100 f < 34 T`; inclusion-exclusion proved, not assumed);
  `the_vectors_of_the_close` (the frozen vectors of close.rs:116-119 under the same rule, the third
  being the one a rule dividing first gets wrong, by `decide`); `no_other_open_quorum` and
  `one_decision` (Theorem 1) over an abstract book of parts, attempts and names under the counting
  rules of agreement.rs:230-275, with the three contradicting pairs of agreement.rs:71-90 as the
  honest predicate. The rational reading of the quorum rule is not stated in Lean; the integer rule
  is the only one the file reasons about.
  Lemma 1, section Order: `run_ok`, `lemma1`, `second_key_iff`, `order_free` over the loop of
  certificate.rs:277-318 as it is written, and `least_spec`, `least_order_free` for `Book::heavy`.
  The cement, section Cement: `setOf` fills a set as `Cement::add` does (BTreeSet::insert,
  cement.rs:33-35); `setOf_mem`, `setOf_nodup`, `setOf_ascending`.
  Lemma 2, sections Exact and Certificate: `reachesShare_exact`, `votesReached_exact`,
  `checkedSum_exact`, `cementOf_nodup`, `cementOf_mem`, `cementOf_ascending` and `lemma2` -- `verify`
  (certificate.rs:252-406, check by check in the order of the code) returns `some L` iff `PiCert`
  holds with closure `L`, for T and K below 2^64.
  Theorem 2: `completeness` -- Lemma 2 from right to left under `honestKey` and `honestValid`.
  Theorem 3: (i) `soundness_parts` -- valid attestations; the parts of the closure are the cement,
  without repeat, and a part stands in them iff a valid attestation of the certificate is of it;
  their count is the length of that list and reaches `Q(card, T)`; and at most `f` of them have
  leaves the adversary holds, with Lemma 3 (distinct parts carry distinct leaves) as the hypothesis
  `lemma3`; (ii) `soundness_one_name` -- two accepted certificates of one window decide one
  predecessor, by Theorem 1, and `soundness_one_name_by_rule` -- the same with `meet` discharged by
  `meet_of_rule`; (iii) `soundness_votes` -- no tally exceeds what its part drew, the hypothesis
  `ballotSound` carrying the ballot.
  Theorem 4, section Walk: `pick`, `go` and `walk` model certificate.rs:786-917; `pick_taken`,
  `closureOf_verify`, `go_inv`, `go_indexed`, `indexed_before`, `chain_good` and `walk_head` -- for a
  property `G` of proposals with `anchor : G X0` and the conditional step `step : ∀ j e l cl, G e →
  verify j e l = some cl → G l`, if the walk returns `(Y, Z)` then the anchor was consecutive, the
  kept pairs chain back to `(X0, X1)`, the pair kept at step `j` verified at step `j`, both
  proposals of every kept pair satisfy `G`, and `(Y, Z)` is the anchor where the walk kept no pair,
  else the pair of the latest step, with `G Y` and `G Z`, every other kept pair having verified at
  an earlier step. A candidate taken where no step follows is never the head. `G` is read as
  "final" (section 7); the Lean states no window and no uniqueness.
  **Hypotheses and readings, not theorems.** The theorems above are proved for every instance of
  what follows; what they give the protocol rests on these, named one by one.
  - (A1)-(A5) through the opaque functions of `Cert`: the validity of an attestation in its round
    (`att.shaped`, `att.verifies`: (C2.1)-(C2.5), the signature (A2) and the presence proof (A3),
    (A5)), the verification of a ballot (`cast`, A3), of a pledge (`pledgeOk`, A2), the book
    (`decides`), the aggregate (`aggregate`, A1), the beacon (`beacon`), the predecessor's
    identifier (`previous`, A1), the light answers (`answered`).
  - The order of the pledges: `decides` takes the pledges of a certificate as a list, and
    `order_free` of Lemma 1 speaks of the attestations alone. That the verdict on a certificate is
    a function of the set of its pledges is the rule of the code -- of the verified pledges of a
    part of one kind and attempt the least by `rank`, the name ascending and then `since`
    descending, is counted (agreement.rs:148-154, :201-228; F5, section 8) -- held by the tests
    `a_part_closing_on_two_names_counts_under_the_lesser_in_every_order`,
    `of_two_open_pledges_on_one_name_the_one_standing_on_none_stands` and
    `the_order_the_pledges_are_handed_in_changes_no_verdict`; it is no theorem of the file.
  - (A2) as `Faithful` and (A8) as `Honest`, inside `book1`/`book2` and `good` of
    `soundness_one_name`; (A8) including the heavy attestations of an honest part, one name per
    window (section 3), which `Faithful` and `Honest.one_open` at attempt zero need.
  - Lemma 3 (with (A3)-(A6)) as `lemma3` of `soundness_parts`; and, with (A6) and (A7), as the
    hypotheses `within` (the parts lie in a universe of at most `T`), `hbad` (at most `f` of them
    are the adversary's) and `bound` (`100 f < 34 T`) of `meet_of_rule`. The Lean does not tie
    `leaf` or `U` to the tree of `E.root`: "distinct admitted machines" is Lemma 3, on paper.
  - `meet` of `one_decision` and `soundness_one_name`: the Corollary of Lemma 4 with Lemma 3, a
    hypothesis there; `meet_of_rule` proves it from the integer rule under the hypotheses of the
    item above, and `soundness_one_name_by_rule` uses it.
  - `Counts` inside `book1`/`book2`: that the book of agreement.rs, `Book::open_quorums` and
    `Book::decided` (:230-275), satisfies the counting rules of the model. This is fidelity of the
    model, not cryptography, and no theorem checks it. Its evidence is the walk `every_book` (below:
    4 parts, 2 attempts, names 1 and 2) and the Kani harness of Theorem 1, which has not reported.
  - `ballotSound` of `soundness_votes`: no verified ballot casts more than its part drew. It
    stands for (A3) for the ballot and (A5) for the ballot description, which O-6 reads off
    ballot.rs constraint by constraint: an accepting ballot publishes at most the census units of
    `E` whose cement holds the part its spending half derives and whose coin clears, the spending
    half being that of the published part under (A4) -- the bound from above, which is the
    statement of O-6 and what `ballotSound` states; a count below it is the holder's abstention
    (F-539-1, a recorded property of section 10). `drew` is a free
    function in the Lean, not tied to the census of `E` or to `W`: the tie is the reading of O-6,
    on paper. The ticket description, read under O-6 likewise, enters no theorem of the file.
  - `honestKey` and `honestValid` of `completeness`: one key per part and every attestation valid,
    standing for honest production and the completeness of ML-DSA and of the proof scheme
    (Theorem 2).
  - `anchor` and `step` of `walk_head`: `step` is Theorem 3 (ii) for one certificate under a genuine
    electorate (section 7), on paper.
  - The readings of the model (Window.lean:808-823, :1320-1322): the map of votes is a total
    function, nought where it holds nothing (agreement.rs:42), summed over the cement, which equals
    the code's sum over `votes.values()` (certificate.rs:373) because the cement holds each part
    once (proved) and the map holds parts of the cement alone (:360); the two rows of the Decree the
    close reads are the constants `confirmation_quorum = 67/100` and `finality_rule = 1`, so the
    refusals of an incomplete Decree (close.rs:13-15, :37-38, :77-83; certificate.rs:209-213,
    :225-232) are not in the model and `lemma2` from right to left holds for a complete Decree; the
    order `below` of the cement is the byte order of the parts, a strict total order, which only
    `cementOf_ascending` reads; `Closure.window` and the arithmetic of the walk on windows
    (certificate.rs:795, :805-807, :881-883) are not modelled.
  - **Result.** Green on the build host (25.10.2026, Lean 4.35.0, file blob a9fd7faa, 1586 lines,
    61 theorems; it differs from blob 76ab7068 in four line numbers of agreement.rs in comments):
    `lean formal/Window.lean` exit 0, no error, no warning, no `sorry`; `#print
    axioms` of all 61 names only `propext`, `Quot.sound` and `Classical.choice` (none for
    `the_vectors_of_the_close`, `lookup_cons`, `run_append`, `Closure.eq_of`, `chain_tail`,
    `closureOf_verify`; `propext` alone for `go_inv`, `go_indexed`, `indexed_before`,
    `chain_good`, `pick_taken` and the section Cement; `walk_head` `propext` and `Quot.sound`;
    `soundness_parts`, `meet_of_rule`, `soundness_one_name` and `soundness_one_name_by_rule`
    all three).
- **Kani** (bounded model checking of the code itself, under `cfg(kani)`). Both harnesses read the two
  rows of the Decree the close reads -- the quorum and the finality rule -- through `kani_decree.rs`,
  which finds them in a constant from the table itself: a search of the table under the bound was cut
  rather than checked (F-438-1), and a name the stubs do not know fails the harness.
  - Theorem 1: `two_books_of_one_window_never_decide_two_names` (`crates/montana-node/src/agreement.rs`)
    runs the book of agreement.rs itself on two books of one window: the three honest parts say the
    same in both under the honest predicate, the fourth part is free in each, a decision in both is
    covered (`kani::cover`), and the two names are equal. Bounds: 4 parts, 3 honest, 2 attempts,
    names 1 and 2 (0 is a pledge not made), committee 0, unwind 13. The unwind was set for the book
    of `835a361`, which held three pledges of each of four parts in one map, twelve past the eleven
    of a node, so its dropping ran twelve times, and unwind 9 failed its unwinding assertions there
    whatever the memory; in the book of `19834ae` the same pledges stand in `said`, four lists of
    three under four keys, so no loop over what it holds runs more than twelve times
    (agreement.rs:770-774), a reading and not a run. Result: not yet in for the book of `835a361`
    (running on the build host since 25.10.2026 11:28 UTC); not run on the book of `19834ae`.
    Beside it, as a fact and not the proof of record (the
    author's decision 176): `agreement::every_book` walks the same bound whole on the book itself,
    `cargo test --release -p montana-node every_book -- --ignored --nocapture` on the build host
    (25.10.2026, agreement.rs blob 1e69d908, commit 8f38237): 332 150 625 books, 11 267 424 deciding;
    117 honest scripts per honest part, 1 601 613 honest triples, 276 962 deciding under them, none
    deciding two names; 8 918 triples of any scripts decide both names, so the honest predicate is what
    the result stands on; `ok`, 1 passed, 220.28 s. The rustfmt of `every_book` that followed (blob
    098b2380) breaks four lines and adds one trailing comma to an array; the walk is otherwise unchanged.
    On the book of `19834ae` (blob 26f18e9c), which counts the least pledge of a part, kind and
    attempt (F5, section 8), the same command gave the same counts number for number, `ok`, 1
    passed, 148.15 s (build host, 25.10.2026, Agent 527 helper); the walk puts at most one pledge
    per part, kind and attempt, so the change does not reach what it decides.
  - Lemma 2: `an_accepted_certificate_satisfies_the_predicate` (`crates/montana-node/src/certificate.rs`)
    runs `verify_certificate` itself, with presence proofs, signatures and ballot proofs as oracles the
    objects carry and with stubs for `Beacon::id`, `genesis_state_hash`, `round_threshold` and
    `Cement::aggregate`: every `Ok` satisfies (C2) to (C6); (C1) and (C7) rest on the stubs and are
    not proved here. `verify_light` and `Proposal::id`, which the harness never reaches (the round
    carries no light attestation, the window stands on the Genesis State Hash), are stubbed by
    functions that fail the harness were they reached. Two covers ask that a certificate is accepted,
    and that one is accepted with two attestations of one part. The lemma is checked in 27 classes,
    one harness each (`an_accepted_certificate_satisfies_the_predicate_on_1_1_1` to `..._on_3_3_3`):
    a class fixes the parts the three heavy attestations name, each drawn by `one_of(&PARTS)` below
    three, so the 27 triples part the input and their union is the whole of it; the first cover is
    reachable in the 18 classes of two parts, the second in the 6 whose first two attestations share
    a part. Bounds: 1 round, 3 heavy attestations over 3 parts, electorate 2, 2 ballots, 2 pledges
    over 2 attempts, unwind 4 (no loop of a class runs past three), `memcmp` unwound to 33 on the
    command line. Result: not yet in (0 of 27 classes; the first running on the build host since
    25.10.2026 10:37 UTC).
  Lemma 1 (the answer independent of the order of the rounds) has no harness yet: the canonical order
  of heavy attestations is defined since Consensus 7.1.0 and the book keeps it, but the harness is not
  written; the unit test of F-431-4 holds the rule on examples, which is not a proof. Of the
  pledges likewise: the verdict on a certificate is a function of the set of its pledges by the rule
  of agreement.rs:148-154 and :201-228 (F5, section 8), held on examples by the three tests named
  there, every order of four pledges in the unit tests and two orders through `verify_certificate`,
  which is not a proof either.
- **Tests** stand in for neither: they exercise the matrix (`tests/certificate_matrix.rs`,
  `tests/a_walk_from_an_anchor.rs`).

## 10. Obligations

- **O-1.** The derivation of `eps_K` for the three descriptions from the parameters of the scheme,
  at the security target of Canon. *The parameters* (params.rs:10-21, ext.rs:13-14, field.rs:17
  of mt-proof, read at 8d6409d, a commit of another clone; the line numbers re-pinned to 835a361,
  where `QUERIES` is 92; Canon, the table beside `proof_security_bits`): the base field `p = 2^64 - 2^32 + 1`,
  every challenge drawn in the cubic extension `K` of order `p^3` (about `2^192`), blowup 8 (rate
  `rho = 1/8`), 48 queries at distinct positions at that reading (transcript.rs:117-120; 92 since decision 4 and the derivation of the sum, below), fold 4, a tail of 64, and no
  proof-of-work term in the transcript. `eps_K` is the sum of three terms: the mixing and the deep
  composition, the commit phase of the folding, and the query phase. The first is a term over the
  order of `K` (Canon gives `2^-172`) and binds in no regime below; the commit phase is over the order
  of `K` too, but with the square of the domain and the seventh power of the parameter `m` of the
  Johnson analysis in it, and it binds `m` (derived below); the query term does not depend on the
  height, so the presence, the ticket and the ballot share it. Per
  attempt, by the regime of the proximity parameter `delta` the analysis of the folding reaches:
  - unique decoding, `delta` below `(1 - rho)/2` (a theorem): `((1 + rho)/2)^48 = (9/16)^48 = 2^-39.8`;
  - the Johnson bound, `delta` below `1 - sqrt(rho)` (a theorem for Reed-Solomon codes): at best
    `(sqrt(rho)(1 + 1/(2m)))^48`, which is `2^-69.9` at `m = 16` and tends to `2^-72`;
  - capacity, `delta` toward `1 - rho` (a conjecture on the proximity gaps of Reed-Solomon codes, not
    a theorem): `rho^48 = 2^-144`.
  *Closed by decision 4 (24.10, the author; Canon 9.3.0, `proof_queries`), and the sum derived on
  the author's word of 24.10 21:21 UTC (Canon 9.4.0).* The author chose the second of the two ways:
  parameters that reach the target on the Johnson bound, and not the capacity conjecture. Blowup
  stays 8, so the extension a prover holds and the time of the low-degree extension do not grow.
  The first pass (Canon 9.3.0) took 88 queries at `m = 16` from the query term alone; the target is
  `eps_K` whole, and the commit phase of the folding is what binds `m` from above.
  *The bound.* Ben-Sasson, Carmon, Ishai, Kopparty and Saraf, "Proximity gaps for Reed-Solomon
  codes", ePrint 2020/654, read in ECCC TR20-083 revision 3 (3 July 2021), section 8.2, Theorem 8.3
  (Batched FRI Soundness) with Lemma 8.2, verbatim up to typesetting: for integer `m >= 3`,
  `alpha = sqrt(rho)(1 + 1/2m)`, `s` invocations of the query step,
  `eps_FRI := eps_C + alpha^s`, where
  `eps_C = (m + 1/2)^7 |D0|^2 / (2 rho^(3/2) |F|) + (2m + 1)(|D0| + 1)/sqrt(rho) * sum_{i<r} l(i) / |F|`.
  The denominator of the first term is `2 rho^(3/2)` in the lemma; `3 rho^(3/2)` is the bound (8.8)
  on the batching event alone, which the lemma sums with the events of the `r` rounds. The
  revision of 30 May 2020 states the theorem differently (Theorem 7.2, through a gap `eta`); this
  paper uses revision 3. The field `F` of the theorem is `K` here: the code is read over `K`, the
  domain lies in the base field inside it, and every folding and mixing coefficient is drawn from
  `K`, so `|F| = p^3`.
  *The parameters.* `rho = 1/8`; `|D0| = 2^19`, the largest extended domain of the three descriptions
  (the ballot and the frame; the presence is `2^17`); five layers of fold 4, so `sum l(i) = 20`;
  `|K| = p^3`, about `2^192`; the mixing and the deep composition `2^-172` (Canon, the row of
  `proof_challenge_field`; independent coefficients, no factor for the count of columns).
  *The sum.* `m` trades the phases: the query term falls toward `2^-1.5 s` as `m` grows and the
  first term of `eps_C` grows as `m^7`. At `m = 16` the first term is `2^-122.19`, so no count of
  queries reaches 128 there; at `m = 9` it is `2^-127.77`, still above. At `m = 7`: `eps_C =
  2^-130.15 + 2^-163.27 = 2^-130.15`; the query term is `(2^-1.5 x 15/14)^92 = 2^-1.40046 x 92 =
  2^-128.84`; with the mixing, `eps_K <= 2^-130.15 + 2^-128.84 + 2^-172 = 2^-128.35`. At `m = 8` and
  92 queries the sum is `2^-128.32`, at `m = 6` it needs 93 (`2^-128.57`), at `m = 5` 94, at `m = 3`
  101. With 91 queries the sum is `2^-127.24` at `m = 7`, `2^-127.70` at `m = 8`, `2^-127.36` at
  `m = 9`, and no `m` reaches 128. So 92 is the least count, at `m = 7` or `8`, and `m = 7` gives
  the larger margin, 0.35 bit. The presence, `|D0| = 2^17` and four layers, has
  `eps_C = 2^-134.15` and a sum of `2^-128.81`. **128 bits are proved for `eps_K` whole**, for the
  three descriptions, on the Johnson bound, from the theorem and the parameters above; the knowledge
  extractor of (A3) beyond the soundness of the folding is the reference's and ethSTARK's (ePrint
  2021/582), not re-derived here.
  `PROOF_LEN` is 4 928 + 92 x 4 344 = 404 576 B and `PRESENCE_PROOF_LEN` 4 896 + 92 x 3 576 =
  333 888 B; every length that carries a proof moved with them (Canon: `opening_len`, `action_len`,
  `frame_len`, `ballot_len`, `candidacy_len`, `confirmation_len`, `proposal_len`, the frozen vectors
  of the proposal, the frame and the notice, and the cells of a delivery: `collect_answer_max` 336 ->
  608 -> 624, a round point 227 -> 127 -> 124 heavy attestations by the `u16` index); the largest
  message of the wire is 768 770 B, 96 s at 64 kb/s, inside `PATIENCE_SECONDS` = 120. One
  consequence decision 4 did not name: the free block of the trace must stay above what the queries
  open, `2 x proof_queries + 2 = 186` values (Canon, "The free block, the randomizer and the two parts
  of the composition"), and `proof_free_rows` was 128; it is 256 now, two blocks of the permutation,
  which changes no description (the identifier of a description does not take the free block into
  its bytes) and leaves the frame, the ballot and the presence inside their heights. (A3) now names
  no conjecture.
  *Accepted by the author, 24.10.2026 21:21 UTC:* the changes of 8e68627 (a commit of another clone;
  its changes stand in this tree, params.rs:40 `FREE_ROWS` = 256) beyond decision 4 --
  `proof_free_rows` 128 -> 256, a round point of at most 127 heavy attestations, the frames of a window 105.8 MB per chain.
- **O-2.** (A5) read off `mt-proof/src/circuit/presence.rs`, constraint by constraint
  (24.10.2026, read at 0fe6134, a commit of another clone; every line number below checked again
  against 835a361 and unchanged; the Poseidon permutation layer is taken as the permutation, as A4
  takes it). Width 12, rate 8, capacity 4 (poseidon.rs:17-22). Every chain opens under its domain:
  at each seam of `opens` (presence.rs:164) the four capacity cells one row on equal the limbs of the
  domain (capacity.rs:57) -- `MT_KEY_HALVES`, `MT_ADMITTED_LEAF`, `MT_ADMITTED_NODE` at each of the
  40 levels, `MT_PART_NF`, `MT_PART_KEY_DIGEST`. Every padding cell of every absorption is a literal
  (sponge.rs:45, presence.rs:147), so no rate cell past the elements is free.
  *The leaf.* The capacity crosses every seam inside the chain of the halves, the seam into the
  block of the second squeeze included (`carry_rows`, presence.rs:89; sponge.rs:126, 165), and the
  rate crosses that seam too (`squeeze_rows`, presence.rs:106; sponge.rs:96): the extra block enters
  with the whole state the absorption left. The four cells that block leaves enter the leaf block
  (`digest_carries` at the seam before the leaf, sponge.rs:102), whose remaining rate is padding.
  At every level the node block enters with the pair the bit orders, the child being the four cells
  the block before it left (path.rs:99); the four cells the last node leaves are bound to public
  word 0, the admitted root (presence.rs:117-125).
  *The part.* The lane loads the four cells the absorption of the secret leaves -- the first squeeze
  -- at its last row, holds them unchanged wherever no load stands, and wires them into the first
  four rate cells of the nullifier block (lane.rs:73; presence.rs:156-160); the lane is loaded once,
  before the wire, so the reading holds whether or not the rules close over the wrap. The fifth
  rate cell is the public window (presence.rs:137), the rest padding, and the four cells the block
  leaves are bound to the public part-nullifier (presence.rs:117-125).
  *The key.* The absorption of 488 limbs of the one-time key ends in the four cells bound to the
  public key digest (presence.rs:117-125, 62 blocks carried).
  *What the statement is.* The witness is a vector of field elements in the rate of the blocks of
  the halves, not a byte string: no rule ranges the limbs. (A5) therefore reads: there is a vector
  `v` of limbs whose naming half has its leaf in the tree of `root`, with `p` the part-nullifier of
  its spending half and `W`. Under (A4) the leaf fixes the naming half and the naming half fixes `v`,
  so `v` is the vector of the admitted machine and `p = part(s, W)` for its secret `s`; the range of
  the limbs is not needed by the argument. The tests `a_presence_cannot_graft_another_machines_public_membership_path`
  and `a_part_cannot_choose_extra_nullifiers_through_sponge_padding` refuse the two wrong circuits
  this reading names.
- **O-3.** Lemma 3 reads the two halves as two squeezes of one absorption from the shape of the
  description (presence.rs:15-20, 103-108, 152-162); the constraint that the half wired into the
  part-nullifier is the state of the first squeeze, and the half under the leaf that of the second,
  is checked constraint by constraint under O-2: the lane loads at the last row of the absorption,
  the leaf takes the cells the extra block leaves, and the extra block enters with the whole state
  (capacity and rate carried). Discharged with O-2.
- **O-4.** (A6) as a theorem of the roots of state (read at 8d6409d, a commit of another clone; the
  line numbers below re-pinned to 835a361). *The construction.* The roots a
  machine recomputes for a proposal take `admitted_root` as the root of its cohort and `admitted_count`
  as its count (montana-node state.rs:303, 306), and both are of one list: `Cohort::of` sorts the
  naming halves and removes repeats (pulse.rs:60-62), the root is `root_of` over that list
  (pulse.rs:63) and the count is its length (pulse.rs:90-92). `root_of` (mt-proof admitted.rs) places
  the leaves of the list at the first `n` positions of a tree of depth `D = note_tree_depth = 40`
  (mt-genesis lib.rs:146) and the empty leaf at every other position, the empty internal of a level
  standing for a missing right child. The leaf of a half and the empty leaf are one domain over two
  different blocks -- four words, the one-element and zeros against the one-element and zeros
  (poseidon.rs:242-253) -- so under (A4) no leaf is the empty leaf and two halves have two leaves; and
  under (A4) for the node the root fixes the vector of leaves it stands over.
  **Lemma 5 (the count is the leaves).** For every list of naming halves of length at most `2^D`, the
  count of its cohort is the number of distinct non-empty leaves under its root, except with the
  probability of a collision of the family. *Proof.* Equal roots fix equal vectors of leaves; the
  non-empty positions hold the leaves of the distinct halves of the list, `n` of them, and the count is
  `n`. QED
  *(A6) from Lemma 5.* A final proposal carries roots a quorum pledged; by the Corollary of Lemma 4
  the quorum holds a machine whose secret the adversary does not hold (A7), which pledges only after
  recomputing the roots (A8) and refuses a proposal whose roots differ from its own
  (certificate.rs:682-708), so the root and the count of the proposal are of one cohort and Lemma 5
  applies. *The bound.* Past `2^D` halves `root_of` leaves its loop with more than one node standing
  and returns the first -- the root of the first `2^D` leaves -- while the count is the length of the
  whole list, so the count would exceed the leaves of the root. `Cohort::of` names the case in its
  refusal ("a cohort the tree of admitted machines cannot hold", pulse.rs:63-65) and `root_of` does not
  refuse it: finding F-436-1, closed in code by a refusal in `root_of` of a list longer than `2^D`,
  with a test at depth one that refuses the named wrong implementation (three leaves taken under a
  tree of two). O-4 is discharged with that closure.
- **O-5.** F-431-1 to F-431-4 closed in code, each with a test that refuses the named wrong
  verifier. State: F-431-1 closed; F-431-4 closed (decision 2); F-431-3 closed (decision 3);
  F-431-2 closed on the author's word of 24.10 21:21 UTC (the certificate carries the light
  attestations answering the final beacon), see section 8. F5 of review 526 (the order of the
  pledges) closed in code at `19834ae`, see section 8: the verdict on a certificate is a function of
  the set of its pledges, each part counted per kind and attempt under the least of its verified
  pledges there by the name ascending as 32 bytes and then `since` descending (agreement.rs:148-154,
  :201-228; docs/Montana Consensus.md:613-616, :816); its three tests ran ok on `19834ae` on the
  build host (25.10.2026, Agent 527 helper: `test -p montana-node --lib agreement` and
  `test -p montana-node --test certificate_matrix`, exit 0). Discharged: the ring of the core on
  fc35ff0 (branch formal/window-479 of the clone on the build host, a commit not in this clone;
  recorded in 5889950; the build host, 25.10.2026, done 08:04:32 UTC, every step exit 0) ran
  `a_final_beacon_no_verified_attestation_answered_closes_nothing`,
  `a_device_walks_from_its_anchor_to_the_head_and_no_further` and
  `agreement::tests::the_first_heavy_attestation_in_the_canonical_order_stands_whatever_the_order_handed_in`
  ok. The tree of fc35ff0 differs from e6cfb3ee in AUDIT.md and three files of mt-proof alone
  (permutation.rs, params.rs, scheme.rs), so montana-node and mt-pulse, where the verifier and these
  tests stand, are the same.
- **O-6.** (A5) for the ballot and the ticket descriptions, read off
  `mt-proof/src/circuit/ballot.rs` and `ticket.rs` constraint by constraint, as O-2 reads
  `presence.rs` (25.10.2026 UTC, Agent 539 helper; read at a60ccf0, whose `crates` are those of
  `19834ae` the head of this note names, and which this branch leaves unchanged but for the test
  file `mt-proof/tests/ballot_and_ticket.rs` it adds; every line number below checked against the
  HEAD of this branch; reviewed independently and restated as the bound from above, 25.10.2026 UTC,
  Agent 541 helper, on the chairman's decision, council link 8383), with the gadgets they share:
  `sponge.rs`, `capacity.rs`, `lane.rs`, `path.rs`, `compare.rs`; the Poseidon permutation layer is taken as the permutation, as (A4)
  takes it, its answer standing at the last row of a block of 128 (permutation.rs:57-58, :99,
  :105-107). A rule holds at every live row but
  the last (air.rs:416-439; scheme.rs:144-200): the rules do not close over the wrap, and no reading
  below needs them to.
  *The ballot: the chains and their domains.* Block 0 is idle; the part of the window is block 1;
  then, per census `i`, the part of that census, its cement leaf, 40 nodes and the coin of two
  blocks (ballot.rs:139-178). Every chain opens under its domain at its seam (:238-252;
  capacity.rs:57-75): `MT_PART_NF` for the part of the window and for each census part,
  `MT_CEMENT_LEAF`, `MT_CEMENT_NODE` at each level, `MT_VOTE`. The spending half is a lane with no
  load (:511-515): the hold rule (lane.rs:80-89) makes it one constant over the live rows, the
  witness, wired into the first four rate cells of the part block, of each census part block and
  of the first block of each coin (:225-232; lane.rs:101-111). The fifth rate cell of the part
  block is the public window (:318-322), of each census part and each coin the public census window
  (:325-332), and every other rate cell of the single-block absorptions is padding by literals
  (:323, :333-334; sponge.rs:45-53). The coin takes the eight limbs of the public aggregate in the
  last three rate cells of its first block and the first five of its second (:344-353), padding
  after them (:354), and the capacity crosses its one inner seam (:212-216; sponge.rs:165-181), the
  only seam inside a chain of the ballot. So the state every block of the ballot enters with is
  fixed whole by the spending lane, the public input, the literals and the walk. The four cells the
  part block leaves are bound to the public part-nullifier (:309-317).
  *The walk of each census.* The four cells the census part leaves enter the leaf block
  (`digest_carries` at :219-223; sponge.rs:102-104), whose remaining rate is padding (:334). At
  each level the node block enters with the pair the bit orders, the child being the four cells the
  block before it left, the bit a bit (path.rs:99-157). The walk of census `i` ends at the last row
  of its last node, `root_seam(i)` (:189-191), which no level reads; there the sibling columns are
  bound to the public root of census `i` (:337-343). The accumulator of the position is bound to
  nothing public, and nothing needs it.
  *The bit of a unit.* `spike` is a bit at every row (:389-395) and nought off the seams a walk ends
  at (:396-402); where it is one, the four cells the walk reached equal the sibling cells there,
  the public root (:405-422). The carried bit takes `spike` at that seam and holds it elsewhere
  (:424-448), so at the row after the comparison of census `i` it is the bit of census `i`: the
  next seam stands 42 blocks on.
  *The comparison.* The coin lane loads the four cells the coin leaves at its last row (:234-236;
  lane.rs:90-100) and holds them through the 32 rows of the comparison, laid in the columns of the
  comparison at the rows after the coin (:195-201). Each row writes a byte of the coin and a byte
  of the difference by eight bits each (compare.rs:190-224), so both lie in [0, 255], and the
  borrow is a bit at every row (:194). The threshold byte of each row is a public limb
  (ballot.rs:355-360; compare.rs:443-460), which the verifier writes from a byte (ballot.rs:791-797,
  attest.rs:501-509). The subtraction `t - s - b - d + 256 b' = 0` of a row (compare.rs:228-252)
  takes, over the integers, a value within 511 of nought, so it holds over the integers; with the borrow in at one
  (ballot.rs:361) the 32 rows give `T - 1 - S = D - 2^256 b_out` with `0 <= D < 2^256`, so the
  borrow out at the row after is nought exactly when `S < T`. The bytes are those of the coin: the
  rows run the words from the last to the first and the bytes of a word from its most significant
  (compare.rs:112-114), so significance rises with the row in the big-endian order of
  `Digest::bytes` (poseidon.rs:51-57); each word is rebuilt from its eight bytes and equals the
  lane cell at its last byte (compare.rs:258-289, :328-346), and the canonical check (:352-437,
  `HIGH_CEILING` :33) holds the high half below `2^32 - 1`, or at it with a low half of nought, so
  the rebuilt integer is below `p` and is the cell itself and not the cell plus `p`.
  *The vote and the count.* The product is the carried bit times the borrow at every row
  (ballot.rs:450-459); the count opens at nought at row 0 (:365-369), holds, and at the row after
  each comparison takes the carried bit less the product (:462-476), `bit x (1 - b_out)`, in
  {0, 1}; it is bound to the public count one row after the last comparison (:370-374), inside the
  live rows (`the_runs_of_a_ballot_fit_its_height_and_its_bounds`, :884). The count is at most the
  number of censuses and does not wrap.
  *What the statement is, for the ballot.* `verify_ballot` builds the public input from `W`, the
  census windows and census roots of `E`, its committee threshold, `A` and the ballot's part and
  count (attest.rs:481-519; certificate.rs:73-110, the census of the length the Decree names), and
  the certificate counts a ballot for a part of the cement alone (certificate.rs:357-370). An
  accepting witness for `(p, W, (c_i, R_i)_i, A, theta, n)` gives four field elements `sigma` with
  `p = H_PN(sigma, W)` and `n = card(S)` for a set `S` of indices `i`, each with: the cement leaf of
  `H_PN(sigma, c_i)` stands at some position of the depth-40 tree under `MT_CEMENT_NODE` with root
  `R_i`, and `H_VOTE(sigma, c_i, limbs(A))` is below `theta` as 32 bytes big-endian. The prover
  chooses `sigma`, the walks, and `S` among the indices that satisfy both, and nothing else. Under
  (A4) -- the part-nullifier, as O-2 and Lemma 3 take it, and the tree of a cement, where the leaf
  of a part and the empty leaf are one domain over two different blocks (cement.rs:16-22) --
  `sigma` is the spending half of the machine whose presence put `p` in the cement, and each unit
  of `S` is a census window of `E` whose cement holds the part that half derives for it and whose
  coin clears: `n` is at most what the standing of `p` drew in `W`, each unit once, which is
  `ballotSound`. This bound from above is the statement of O-6 for the ballot. A census window
  that repeats (`census_windows` reads nought for a census before window nought,
  standing.rs:39-49) carries the root of the empty cement there, which no part walks to under (A4).
  *The holder's abstention (F-539-1, a recorded property; ballot.rs:389-422).* The bit may be nought
  where the walk does reach the root: the holder of the spending half may leave out a lived unit
  whose coin clears and publish fewer votes than its standing drew, which is the same as declining
  a vote it could cast -- a machine may always abstain. No one else can lower the count: a ballot
  of `p` needs the spending half behind `p` (the statement above), and the certificate keeps the
  largest count among the verified ballots of a part (certificate.rs:368-369), so a lower ballot
  beside the holder's changes nothing; a relayer may withhold a ballot whatever the circuit says.
  O-6 is stated as the bound from above (the chairman's decision, council link 8383), so this is a
  property of the statement and not a finding against it; an equality would need the ballot to
  prove that a part is not in a cement, which the description does not carry. Test:
  `a_ballot_counts_at_most_what_its_part_drew_and_its_holder_may_abstain`
  (tests/ballot_and_ticket.rs:154, not ignored; it replaces the ignored finding test
  `f_539_1_a_lived_unit_whose_coin_clears_cannot_be_left_uncounted` of 4ff22ed). It lowers the bit
  of a lived clearing unit and rewrites the carried bit, the product and the count: the trace
  satisfies the description with one vote fewer and is proven and verified, and is refused with the
  honest count. The same standing counted one more than it drew is refused twice: published over
  the honest trace, by the boundary of the count (ballot.rs:370-374); and written as the bit of a
  unit not lived whose coin clears, by the rules of the root at its seam and by no other rule
  (:403-422). It ran ok on the build host (25.10.2026, 822e431,
  `test -p mt-proof --release --test ballot_and_ticket`, 6 passed, 0 ignored, exit 0).
  *Refused, by test.* In ballot.rs: the public values the trace did not count -- the count one more
  and one less, a root moved, a census window moved, another aggregate, another window
  (`a_ballot_refuses_every_public_value_it_did_not_count`, :946); a vote forged for a census not
  lived, refused by the rule of the root alone (`a_census_not_lived_casts_nothing`, :1049); a coin
  at the threshold (`a_coin_votes_below_the_threshold_and_never_at_it`, :1004). In
  tests/ballot_and_ticket.rs, each refused by the one rule named and no other: a bit of two at a
  lived seam, the bit rule (`a_lived_unit_cannot_cast_two_votes_by_a_bit_of_two`, :246); a borrow
  out written as nought, the subtraction of the last byte
  (`a_borrow_out_written_as_nought_does_not_make_a_coin_clear`, :289); a coin, its lane and its
  comparison grafted from another spending half, the spending wire of the coin
  (`a_coin_drawn_from_another_spending_half_is_refused`, :324); the word 0xFF written as the bytes
  of 0xFF + p, which would clear a threshold of 0x80 where the canonical bytes do not, the
  canonical check (`a_word_written_in_bytes_above_the_modulus_does_not_clear`, :431, the gadget
  alone). The five new tests that refuse, the ticket's below among them, ran ok on the build host
  (25.10.2026, 4ff22ed, `test -p mt-proof --release`, the whole crate with its gate, exit 0).
  *The ticket: the chains.* Block 0 is idle; the halves (blocks 1 to 3), the admitted leaf, 40
  nodes, the ticket of two blocks, the key of 62, then the comparison (ticket.rs:41-89); they open
  under `MT_KEY_HALVES`, `MT_ADMITTED_LEAF`, `MT_ADMITTED_NODE` at each level, `MT_TICKET` and
  `MT_RUNNER_KEY_DIGEST` (:201-218). The halves are one absorption of eight limbs squeezed twice,
  as in the presence: the capacity crosses both seams inside it, the seam into the squeeze block
  included (:95-100), and the rate crosses that seam (:102-104, :272; sponge.rs:96-98), so the extra
  block enters with the whole state the absorption left; the rate of the first block is the witness
  and that of the second padding (:176). The spending lane loads the four cells the absorption
  leaves, the first squeeze, at its last row (:189-191) and wires them into the ticket's first block
  (:193-195); the naming half, the four cells the squeeze block leaves, enters the leaf block
  (:247-250, :273), padding after (:177). The walk ends at the seam before the ticket, where the
  four cells are bound to public word 0, the admitted root (:129-142). The ticket absorbs the lane
  and the eight limbs of the public aggregate (:146-159), padding after (:178), the capacity across
  its seam (:97); the four cells it leaves are loaded into the digest lane at its last row
  (:197-199) and never wired into a block. The key absorbs 488 free limbs and its last block leaves
  the four cells bound to the public key digest (:131), padding after (:179).
  *The comparison* is the gadget read above over the digest lane (:280-281), the threshold one
  public limb per row (:160-164), the borrow in at one (:168) and the borrow out bound to nought
  (:169-173): the ticket is below the threshold as 32 bytes big-endian.
  *What the statement is, for the ticket.* For the public input `(E.root, runner_digest(key), A,
  theta_draw)` that certificate.rs:740-748 builds, an accepting witness gives a vector `v` of eight
  field elements whose halves `(sigma, nu)`, one absorption squeezed twice, have the leaf of `nu` in
  the tree of `E.root` and `H_TICKET(sigma, limbs(A))` below `theta_draw`, and a vector `w` of 488
  elements with `H_RKD(w)` the public digest. Under (A4), as in O-2, the leaf fixes `nu` and `nu`
  fixes `v`, so `sigma` is the spending half of an admitted machine and that machine's ticket
  clears; `w` is the limbs of the key. The prover chooses which admitted secret it holds, and
  nothing else. Refused, by test: in ticket.rs another key, another aggregate and a threshold at
  the ticket (`a_ticket_is_proven_and_verified_end_to_end`, :550), a threshold at the ticket itself
  (`a_ticket_clears_a_threshold_one_above_it_and_never_the_threshold_itself`, :594), a stranger's
  ticket over an admitted machine's membership
  (`a_ticket_cannot_graft_another_machines_membership`, :666); in tests/ballot_and_ticket.rs an
  admitted machine whose ticket does not clear carrying a stranger's that does, refused at the
  spending wire of the ticket alone (`a_ticket_drawn_from_another_spending_half_is_refused`,
  :505), and the canonical check above, the comparison being one gadget for both.
  *Where it stands.* **O-6 is discharged**, with the ticket. The ticket is sound as read. The ballot
  is sound for the statement of O-6, the bound from above: no verified ballot casts more than its
  part drew over the census of `E`, which is what `ballotSound` and Theorem 3 (iii) rest on; a count
  below it is the abstention of the holder of the spending half, recorded above. No circuit, AIR,
  parameter or verifying key is changed. The sentence below is left as decided.

Item 1 stands closed when O-1 to O-5 are discharged, the Lean file runs green on the build host, and
the ring of the core is green on the commit that carries them. Model checking of the code with Kani
is the work of item 2 (#10), not a condition of item 1 (the chairman's decision of 25.10.2026 15:55
UTC on the author's word); its verdicts enter section 9 when they are in.
