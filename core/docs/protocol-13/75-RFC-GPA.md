# 75. RFC: GPA resistance, padding, post-quantum forward secrecy, queue resynchronization

**Status: open (council point 1). Requirement 3 is answered by the section "How a link renews its
keys" of Network, which the Author adopted on 2026-10-29 (decision 333 = (b), record 338); its code
follows at stage 18, after the network run of issue #24. This file itself is not normative: the
section of Network and its form in Canon are. Line references below were read on the branch named
next and may since have moved.**

This is the council's answer to the RFC of issue #75, requirement by requirement. It was written
on 2026-10-27 UTC on the branch `agent-632/issue-75-pcs`, cut from `main` at `826aa8b`. It builds on
the chairman's map of 18:42 UTC on the issue and on the Author's decision 304 of 19:48 UTC
(constitution record 307; the chairman's comment of 19:52 UTC): #75 is its own open task and is not
merged into #22, and the handshake stays pure ML-KEM-768 with no hybrid, per [I-1] and [I-7].

"Network", "Canon", "Constitution" and "Registry" mean `core/docs/Montana <name>.md` on this
branch. Network lines 193-316 are the proposed section this branch adds; every Network line after
it stands 125 lines lower than on `main`. Other paths are relative to the repository root. Every
reference below was read on this tree. This is self-verification by the council, not an
independent external audit.

## Requirement 1. A formal proof of GPA resistance

**What the RFC asks.** A proof, for instance in the UC framework, that the active routing state is
indistinguishable from an idle background-noise distribution `D_idle`, under a rushing adversary
that delays or drops packets.

**What the specification says today.**

- The invariant does not claim GPA resistance. [I-16] closes every set of observation points "that does not hold both ends of the same delivery", and "An observer holding both ends is the one case the invariant does not close" (Constitution:378-386). A global passive adversary holds both ends. The threat model and the ledger name that case: Network:797 and Network:820.
- No idle background distribution exists to compare against. "Synthetic filler therefore does not exist" (Constitution:401-406; Network:640-646), and a link unit "never synthetic filler: where nothing waits, nothing is sent" (Canon:2510).
- Delay and drop are answered by construction rather than by a bound. A late cell is extinguished, and loss is repaired by the erasure code, never by asking again (Network:472-482; Constitution:555-560).
- Protocol-13 item 11 is open: "Total anonymity is required and has not been established" (`core/Montana-Core/protocol-13/11-ANONYMITY.md:3`). Closure "must specify and satisfy the adversary model" (`11-ANONYMITY.md:18-22`). The measurement of what an observer sees is owed by stage 22 of the plan (`core/Montana-Core/ROADMAP.md:1217-1230`).
- The token routing a proof would be about is not running. The node puts every object straight onto every link it holds (`core/Montana-Core/crates/montana-node/src/lib.rs:1614-1631`). The holder, the path, the slot, the right of carriage and deferred collection await stage 18 (Registry:129-134).
- The audit inventory excludes the claim outright. `doc/external-audit/snapshot.py:81-82` lists `'GPA resilience'` among what it does not attest.

**The council's answer: taken in a changed form.** The game Montana can state is the [I-16] game,
not a `D_idle` game. An adversary that observes, delays, drops and injects at any set of points not
holding both ends of one delivery must not tell two worlds apart beyond what the ledgers of the set
admit. A game against an idle-noise distribution is refused, because it presupposes synthetic
filler, which Constitution:401-406 forbids. A claim of resistance to the global passive adversary
is refused too: the both-ends case is a named physical prohibition, and "no construction supplies
volume that nobody carries" (Constitution:420-423).

### The [I-16] game, written by the council (Q7)

Written on 2026-10-30 UTC by the chairman on the Author's word of that day (council link 13380): the
council does its own part and does not wait on the reviewers, so decision 390 = (c) no longer holds
the wording back. Lines cited here were read on `main` at `a95210b`. The game is stated over the specification, not over the code: the routing by
tags it is about is not running (`montana-node/src/lib.rs:1614-1631`). The full statement, with its
references, is `docs/issue-75/03-transport-game.md` of the iOS tree; what follows is what the council
proves and what it does not.

**The game `G^X(A, P)`.** A network of honest machines runs Network and Canon over an advancing
chain. Traffic the adversary does not choose comes from a background `D_bg` (variant `G_bg`), or
the adversary chooses all of it (variant `G_adv`). The adversary names two scenarios `σ_0`, `σ_1` of
a challenge type `X`, the challenger draws `b` and runs `σ_b`. On every point of the set `P` (links
and access lines) the adversary sees every cell -- its bytes, its canonical slot, its direction --
and may delay, drop, reorder or inject cells there; it corrupts no machine. It outputs `b'`, and
`Adv` is the absolute value of `2·Pr[b' = b] - 1`. In both scenarios every honest device sends and
receives the same number of letters, of the same length, in the same windows. `P` is **admissible**
when it holds both ends of no delivery of either scenario -- the exclusion of Constitution:391-394
and nothing more. Challenge types: **KIND** (one delivery, same ends, same length, same class of
carriage: a payment in one world, a letter in the other -- [I-16] requirement 1), **REL** (`u_0 → v_0`
and `u_1 → v_1` against `u_0 → v_1` and `u_1 → v_0`), **ORIG** (a machine originates in one world and
relays a delivery of the same length in the other).

**Theorem 1 (KIND; proved).** For every set `P`, admissible or not, and every adversary making `q`
observations and `q'` injections, `Adv ≤ 2q·Adv^{ind$} + q'·Adv^{int}`, where the two terms are the
advantages against the confidentiality and the integrity of the one cipher Canon names,
ChaCha20-Poly1305 (Canon:33). Outside the delivery's own cells the bound assumes that what the
recipient does after opening is the same for both kinds; a reaction that depends on the kind (a
transfer it then announces to the chain, say) is a trace of its own and is counted against [I-16]
requirement 1, not hidden by this theorem.

*Proof.* Everything the adversary sees of a cell other than its sealed bytes is the same function
of the window, the pair and the length in both worlds. Its length is `cell_bytes` = 1 232 B for
every cell (Canon:955, :5025; Network:835). Its moment is the canonical slot, derived from the window
and the sender's ephemeral identity (Network:473-480), never from the content. Its open fields are
the target commitment, a function of the pipe and the window, and the label of its step, which
takes nothing of the delivery (Network:403-404, :867). Its path is the path of the pair, because a
payment has no transport of its own (Constitution:402-405). So the two views differ only in the
plaintexts under the seals: the routing layer and the delivery layer, each ChaCha20-Poly1305
(Canon:2152-2154, :2236) with a nonce drawn afresh for every cell (Canon:2250), no field telling one
kind of content from another (Canon:2254), re-sealed at every step (Network:406). Replace the sealed bytes of the observed cells one by one with uniform strings of the
same length: each of the `q` steps, for each of the two layers, changes the adversary's success by at
most `Adv^{ind$}`, and at the end the view does not depend on `b`. An injected or altered cell of
another length is discarded in silence (Canon:2249); one of the right length that does not open ends
the link, and a new handshake replaces it (Network:280-281). Both reactions are the same in both
worlds unless the cell forges a seal, which bounds the injection term by `q'·Adv^{int}`. ∎

**Proposition 1 (both ends; proved).** In `G_adv`, with `P = ends(d)` and an otherwise empty
workload, the scenarios `u → v` and `u → v'` are told apart with advantage 1. *Proof.* Without
synthetic filler (Constitution:412-414) a delivery to `v` brings at least one cell onto `line(v)`
within its horizon, and none arrives there in the other world; consensus cells on that line do not
depend on `b`. ∎ This is the case the invariant names and does not close (Constitution:391-394,
:428-431); it is why the RFC's claim of resistance to the global passive adversary is refused.

**Proposition 2 (interior observer, adversary-chosen workload; a finding, shown as a sketch).**
In `G_adv` with type REL, let `P` be every link except the access lines of `v_0` and `v_1`, let their
first machines differ and be known to the adversary, and let the workload be otherwise empty. `P`
is admissible. The adversary follows the volume of `u_0` hop by hop to the holder of its tag and the
collection of each recipient from its first machine to a holder, and pairs them; re-sealing hides
bytes, not volume (Constitution:420-423). Its advantage is close to 1. The sketch in full is
`docs/issue-75/03-transport-game.md` section 5. **Consequence:** read word for word, [I-16] claims
indistinguishability for every set short of both ends, and when the adversary chooses the workload
no design without synthetic filler can give it. The invariant's own third requirement says the
same in prose: the protocol sets "the price of the correlation and not its impossibility"
(Constitution:432).

**What the council proposes in its place (Claim C3′).** In `G_bg`, for every polynomial adversary
and every admissible `P`, `Adv ≤ ε(D_bg, profile, ℓ) + negl(λ)`, where `ε` is set by the honest
volume on the links of `P`, the delay profile and the path length `ℓ`, and falls toward 0 as that
volume grows; for KIND, `ε = 0` by Theorem 1. Bounding `ε` for REL and ORIG is the measurement of
stage 22 (`core/Montana-Core/ROADMAP.md:1217-1230`), which belongs to #22 (decision 386 = (b)).
Whether the words of [I-16] change to C3′ is the Author's alone (Q7 below); this file amends nothing.

## Requirement 2. Adaptive, stochastic traffic padding

**What the RFC asks.** Padding drawn from a Poisson process or under differential-privacy
constraints, adapting to congestion and to the power state of the device, without leaking changes
of volume to a global observer.

**What the specification says today.**

- Padding of any distribution is synthetic filler, and synthetic filler does not exist (Constitution:401-406; Network:640-646; Canon:2510; Registry:146, NET-20).
- A constant rate is specified only for a voice or video stream (Network:619).
- The deferred delay is uniform over the residues of the window, not a Poisson profile (Network:562-568). Canon states why a shaped profile would say more (Canon:1333-1342).
- What hides one line's traffic is the transit of others. A reachable device carries it by the duty that pays it (Network:622-638), and a sleeping device's link is held with real transit, not filler (Network:635-638).
- What the RFC calls adaptation to power is the operator's budget. "The budget belongs to the operator; its division belongs to the protocol" (Network:711-718).
- The legacy client core still carries a padding frame whose flag stands in the plaintext header: `core/Code/crates/mt-net/src/framing.rs:21` (`FLAG_PADDING`) and `:53-59` (`Frame::padding`). The new core has none.

**The council's answer: refused. It contradicts [I-16] requirement 3.** "Synthetic filler therefore
does not exist, and neither does a price for it" (Constitution:405-406), and "A unit carries a
message or a piece of one and never synthetic filler" (Canon:2510). A padding schedule, adaptive or
not, is exactly that filler. The Constitution names why a constant or shaped rate becomes the mark
itself (Constitution:401-404). It also names what the sum of others' traffic does and does not
give (Constitution:408-418).

**What remains open.** The padding frame of the legacy client core (`framing.rs:21,53-59`) belongs to
the removal of that module (#5), not to this point. Whether the volume a line shows matches its
ledger row is measured at stage 22.

## Requirement 3. A post-quantum handshake per hop, forward secrecy and post-compromise security

**What the RFC asks.** Each hop's key exchange moves to a hybrid of ML-KEM over classical ECC, and
"each routing token validation must guarantee immediate post-compromise security (PCS) at every
discrete hop".

**What the specification and the code say today.**

- The link handshake is post-quantum only: ML-KEM-768 encapsulation both ways, ML-DSA-65 signatures over the transcript, SHA-256 folding, and "There is no elliptic curve anywhere in it" (Network:25-58, the sentence at :47-50; Canon:3056-3094).
- The code draws a fresh ML-KEM pair per handshake (`core/Montana-Core/crates/mt-net/src/lib.rs:323-329`). It encapsulates both ways (`:347-364`, `:426-429`). The master and the directional keys are `mt-wire/src/handshake.rs:239-252`, in the fold of `mt_codec::hash` (`mt-codec/src/lib.rs:87-95,146-152`: SHA-256 over the domain, `0x00` and the parts).
- A link keeps its two directional keys for its whole life. `Channel` holds them from the handshake on (`mt-wire/src/handshake.rs:277-324`), and `Link` reads them from the channel at every unit (`mt-net/src/lib.rs:243-257`). `send` seals every unit under that one key with a drawn nonce (`:262-271`; `mt-wire/src/link.rs:92-118`). Nothing re-keys a link. Whoever reads those keys reads the link's past and future until the link ends.
- A pipe's secret walks one way per window (Canon:1354-1371), which gives forward secrecy. "The walk does not heal, so the pipe is read from that window until the correspondents establish a new secret" (Network:803).

**The council's answer.**

- **The hybrid is refused**, by the Author's decision 304 (record 307) and by two invariants. [I-1] forbids "classical Diffie-Hellman" and the elliptic-curve family (Constitution:77-81). [I-7] forbids "Duplicating functionality through two different primitives" (Constitution:183-185).
- **"Immediate" PCS is refused in that form.** No construction heals before fresh secret material, which the attacker does not hold, has been exchanged after the compromise. What Montana can take is healing at the next renewal.
- **Forward secrecy and PCS per hop are taken in a changed form.** A link renews its keys once in every window it carries anything, on pure ML-KEM-768. A pipe heals by a pair of letters carrying a fresh ML-KEM-768 encapsulation key and an encapsulation to it. Both are drafted as the proposed section "How a link renews its keys", **Network:193-316**, marked "Status: proposed (issue #75)". The gate of the reference tree requires a Registry row for every section of Network (`mt-conformance/src/registry.rs:299-347`), so Registry:151 adds row NET-25, marked "proposed, issue #75, not adopted" and awaiting stage 18.

The Network draft holds no number, no domain string and no layout. The set keeps those in Canon
alone: Constitution:40-42 for values and layouts, Canon:3779-3780 for domain strings. What Canon would
receive on adoption stands below.

### The integer form proposed for Canon

The naming follows Canon:3058-3061. `pk_i` and `pk_r` are the encapsulation keys drawn for this
renewal by the side that opened the link and by the other side. `ct_i` is the encapsulation the
initiator produced to `pk_r`, and `ct_r` the one the responder produced to `pk_i`. `ss_i` and `ss_r`
are the secrets those open to. Whichever side offered, the fold takes the initiator's values first.

```
link_secret(0) = master                                            Canon:3069, unchanged
link_secret(n) = SHA-256("mt-link-renew" || 0x00 || link_secret(n-1) || ss_i || ss_r
                         || pk_i || pk_r || ct_i || ct_r)
k_i2r(n)       = SHA-256("mt-noise-pq-v1-i2r" || 0x00 || link_secret(n))
k_r2i(n)       = SHA-256("mt-noise-pq-v1-r2i" || 0x00 || link_secret(n))

healed(W0 + 1) = SHA-256("mt-pipe-heal" || 0x00 || pipe_secret(W0) || ss_h || pk_h || ct_h)
healed(W + 1)  = SHA-256("mt-pipe-ratchet" || 0x00 || healed(W))   the walk of Canon:1358-1361
```

- At `n = 0` the two directional keys are exactly `k_i2r` and `k_r2i` of Canon:3070-3071. The handshake, its transcript, its signatures and its vectors do not move. The two directional domains stay with NET-01. The new domains `mt-link-renew` and `mt-pipe-heal` would enter the registry of separators with NET-25 as their owner. Their names keep the alphabet of Canon:3782-3786.
- Every part has a width the set fixes: 32, 32, 32, 1 184, 1 184, 1 088 and 1 088 bytes. The concatenation is self-delimiting, as the transcript's is.
- `W0` is the window of the tag the answering letter of a heal travelled under. Both correspondents know it: the sender because it deposited there, the other because it collected there.

Layouts and kinds. The pieces are counted by `link_pieces`, Canon:2449. A piece is 1 183 bytes (Canon:2446), and a unit is `cell_bytes` = 1 232 bytes (Canon:955).

```
serialize(renew_offer)    kem_key 1 184 B                          1 184 B   2 units
serialize(renew_answer)   kem_ct  1 088 B   to the offer's key
                          kem_key 1 184 B                          2 272 B   2 units
serialize(renew_finish)   kem_ct  1 088 B   to the answer's key    1 088 B   1 unit

message_kind  15 renew_offer   16 renew_answer   17 renew_finish   (beside 1-14: 13 and 14 are table_query and table_answer)
```

The ceiling, for the Decree: `rekey_units` = 8 388 608 (2^23) units sealed under one sending key.

- **Why the window decides.** The derivation sizes a count and reads no clock. The commodity link of [I-5] is symmetric gigabit (Constitution:150-155). A window is nominally sixty seconds: `window_credit` = 60, "one for every second of it" (Canon:4735). In one such window a gigabit link carries 10^9 x 60 / 8 / 1 232 = 6 087 662 units. 2^22 = 4 194 304 is below that and 2^23 is the first power of two above it. So in a chain that advances, the window renews a commodity link first, and the ceiling binds only when the chain stalls or on a faster link.
- **Exposure in a stall.** A renewal is offered at 2^23 units, so while the far side answers at most 2^23 x 1 232 = 10 334 765 056 bytes per direction stay under one key. A key that has sealed 2^24 units without a completed renewal refuses every further message of a caller and its link ends, so with a far side that never answers at most 2^24 x 1 232 = 20 669 530 112 bytes do, beside the at most three messages of the renewal itself, which are never refused for the count.
- **Nonce safety.** Nonces are drawn at random, 96 bits wide (Canon:2438, 2505). Under one key the chance of a repeated nonce after `q` units is at most `q^2 / 2^97`, which is 2^-51 at the ceiling and 2^-49 at twice the ceiling, where a key ends its link.
- **Cost.** A renewal at the ceiling adds 5 units per 2^23, which is 6 x 10^-7.

### What a renewal and a heal cost

| Exchange | Units | Bytes on the wire | Signatures | Computation |
|---|---|---|---|---|
| a renewal of a link (draft) | 5: offerer 3, answerer 2 | 6 160 (3 696 + 2 464) | 0 | 2 key generations, 2 encapsulations, 2 decapsulations, 1 hash |
| a renewal signed by both answering keys (option, Q2) | 11: offer 2, answer 5 (5 581 B), finish 4 (4 397 B) | 13 552 | 2 | the above, 2 signings and 2 verifications |
| a new handshake (today's only way to new keys) | 14: flights of 3 138, 4 226, 4 397, 3 309 B take 3, 4, 4, 3 units | 17 248 | 2 | 2 key generations, 2 encapsulations, 2 decapsulations, 2 signings, 2 verifications |
| a heal of a pipe (draft) | inside two letters | +1 184 B in the offering letter, +1 088 B in the answering letter, each cut into blocks of `chunk_bytes` = 868 B (Canon:2240-2242) | 0 | 1 key generation, 1 encapsulation, 1 decapsulation, 1 hash |

The flight lengths are Canon:2263-2283 and `mt-wire/src/handshake.rs:432-437`. The unit counts are
`ceil(length / 1 183)`, as `handshake::units_of` takes them (`mt-wire/src/handshake.rs:419-421`). A
renewal costs once per window in which a link carries anything, and never on a link that carries
nothing.

### How it composes with the handshake

- The handshake draws its encapsulation pair afresh, through the one door that draws (`mt-net/src/lib.rs:323-329`). A renewal draws its two pairs through the same door, and `kem::encapsulate` draws its own randomness (`mt-suite/src/kem.rs:117-127`). No randomness is ever taken from a caller.
- The secret of a link starts at the handshake's master. The transcript a person compares out of band (`Link::transcript`, `mt-net/src/lib.rs:232-236`) stays the handshake's. Each renewal chains on the previous secret, so the messages of a renewal replayed into another link fold into a secret nobody holds.
- Renewal messages are messages of the link, so their kind rides inside the seal (Canon:2481-2483). Nothing of a renewal is visible except units of the one shape.
- The step label (Canon:1348) is left untouched by the draft. The code draws a random label for every unit today (`mt-net/src/lib.rs:133,266`), which is already a finding of #22.

### What an attacker holding the link state at time t learns

This is the statement of Network:266-273, made exact.

- **Before the next renewal completes:** every unit of the link, both ways, read and forgeable. This is what today holds for the link's whole life.
- **Units sealed before the renewal that preceded t:** nothing. `link_secret(n)` is one way in `link_secret(n-1)`, and every earlier value is erased.
- **After the next renewal, if the attacker is passive during it:** nothing. Both fresh decapsulation keys were drawn after t, and the attacker sees `pk` and `ct` but not `ss`, by the IND-CCA security of ML-KEM-768. One fresh side suffices, as Canon:3091 says for the handshake.
- **If the attacker is active during the renewal:** it stays in the middle. Only a signature it cannot make would heal that case, and an attacker who took the machine holds the machine secret that the answering key derives from (`mt-net/src/lib.rs:186-201`). That is option Q2.
- **The pipe:** a renewal of a link changes nothing of a pipe. A heal changes it from `W0 + 1` on, provided the heal was not altered and the offer was drawn after t. Letters the answering side sends before it opens a healed letter remain readable to the holder of the old walk. Network:289 names that residue.

### The code that must follow, on adoption (none is changed here)

- `core/Montana-Core/crates/mt-codec/src/lib.rs:299` and `:333`: the two new domains beside `MT_NOISE_PQ_V1_I2R` and `MT_PIPE_RATCHET`.
- `mt-wire/src/handshake.rs:239-252`: the directional keys taken from `link_secret(n)`, and the renewal fold beside `master`. Also `:277-324`: `Channel` holds the secret of the link beside its keys, and its `Drop` (`:295-301`) wipes it.
- `mt-wire/src/message.rs:21-70`: the three kinds in `Kind`, `Kind::of` and `Kind::byte`.
- `mt-net/src/lib.rs`:
  - `:208-214`: `Link` holds the secret of the link, the window it was set in, the count of units sealed under the sending key, a pending renewal and the previous receiving key.
  - `:243-257`: keys from the current renewal.
  - `:262-271`: `send` offers before a message of a later window or at `rekey_units`, and counts units.
  - `:286-320`: `receive` handles the three kinds inside the link and opens under the previous key until the first unit opens under the new one.
  - `:323-329`: the same door for the renewal's draws.
- `send` must learn the window. Its callers in the node are `montana-node/src/pulse.rs:2737,2774`, `pay.rs:511` and `lib.rs:1937,1944,1990,2018`. The reader loop is `lib.rs:1814`, and the push to every link is `lib.rs:1614-1631`. The tests that drive a link are `mt-net/tests/two_machines.rs` and four files in `montana-node/tests/`: `a_round_over_the_wire.rs`, `a_payment_crosses_the_wire.rs`, `a_payers_own_frame_applies_with_its_round.rs` and `a_payer_is_told_again_where_a_replay_moves_its_frame.rs`.
- `mt-derive/src/tag.rs:103-105`: the heal beside `pipe_secret_step`. The clients that compute pipes in Swift (`apps/messenger/ios/Code/Montana/MTPipe.swift:5-46`) and in Kotlin follow the same derivation.
- Canon: the domains in the registry of separators (Canon:3771 and on), the three layouts and kinds (Canon:2436-2456), the row `rekey_units` in the Decree, and frozen vectors for `link_secret(1)`, `k_i2r(1)`, `k_r2i(1)` and `healed(W0 + 1)` with a named negative (the fold in the order of the renewal rather than of the roles). The gate's wire check (`mt-conformance/src/parse.rs:1317`) compares them.
- Network: the two ledger rows and the conformance item the draft states at Network:303-316 move into the ledger and the conformance set. "In scope" (Network:11-15) names the renewal.
- `core/Montana-Core/ROADMAP.md:1134-1150`: stage 18 does not name the renewal today. NET-25 awaits it, so stage 18's "Holds" would gain it.

## Requirement 4. Resynchronizing a token queue with NIZK proofs or accumulators

**What the RFC asks.** A zero-knowledge recovery, by NIZK proofs or cryptographic accumulators,
for a single-use token chain that packet loss desynchronizes.

**What the specification says today.**

- There is no such chain. A tag is `SHA-256("mt-tag" || 0x00 || pipe_secret(W) || W)[0..16]`, with no counter (Canon:1347-1352). "Neither takes an index of any kind" (Canon:1383-1384).
- The walk of a pipe needs no exchange to resynchronize. "A device returning after an absence walks to the present rather than asking anybody" (Canon:1368-1369). "Nothing of the walk crosses the wire" (Canon:1377).
- Loss is repaired by the erasure code and never by asking again (Network:477-482; Canon:2536-2539). A holder that is away costs a wait: "the sender's queue keeps the letter" (Network:153).
- The one shared state that can diverge is the window height. [I-16] requirement 14 takes it from the chain (Constitution:547-549), and [I-15] forbids the system clock in protocol logic (Constitution:348-353). The iOS client still takes it from the wall clock, with a tolerance of one window either side (`apps/messenger/ios/Code/Montana/MTPipe.swift:24-35`). That is a finding of #22.

**The council's answer: refused.** It answers a problem the design does not have, and it would add
what two norms forbid. [I-7] admits a new primitive only "by closing a concrete mechanism"
(Constitution:183-185), and no mechanism here desynchronizes. A resynchronization dialogue is a
repeat, and "a repeat is a pattern, and a pattern is what an active observer is trying to induce"
(Network:479-481). The proposed renewal of Requirement 3 follows the same rule. It keeps no counter
that two ends must hold alike (Network:240-245). A renewal that does not complete ends the link in
silence and costs a handshake, never a divergence (Network:257-264).

**What remains open.** The wall-clock window of the clients (`MTPipe.swift:24-35`) stays with #22.

## The RFC's action items

1. **A formal protocol whitepaper.** It exists: `WHITEPAPER.md:1-5`, governed by the normative set. Token generation is frozen with vectors in Canon:1344-1389 and compared today (Registry:128 NET-02, Registry:150 NET-24).
2. **A pluggable C/Rust library.** Two C boundaries exist. The client core `core/Code/crates/mt-bindings` builds as `staticlib`, `cdylib` and `rlib` (`Cargo.toml:11`). The new core's boundary is `core/Montana-Core/crates/mt-boundary/src/lib.rs:1-21`. What the RFC says rightly is that the apps compute the delivery derivations themselves, in Swift (`apps/messenger/ios/Code/Montana/MTPipe.swift:5-46`). Moving them behind the boundary is stage 21 (`core/Montana-Core/ROADMAP.md:1207-1215`).
3. **A verifiable test suite.** The gate compares the set with the code on every build (`core/Montana-Core/crates/mt-conformance/build.rs:22-49`). The GPA lab contract states that "There is no runnable production-equivalent Montana GPA testnet here" (`doc/external-audit/LAB.md:6-10`). The simulation of an observer is stage 22 (`ROADMAP.md:1217-1230`).

## Open questions for the Author

Each question is stated as options with a recommendation. None of them is decided here.

- **Q1. What renews a link.**
  - (a) The window, with the ceiling `rekey_units` for a stalled chain (the draft).
  - (b) The window alone.
  - (c) A count of units alone.

  Recommendation: (a). Without the ceiling, a stalled chain leaves one key over an unbounded volume. Without the window, a link that carries little keeps one key for many windows.
- **Q2. Whether a renewal is signed.**
  - (a) Not signed (the draft): 5 units.
  - (b) Both answering keys sign the renewal: 11 units. This heals also against an active attacker who read the link's state but not the machine's secret.

  Recommendation: (a). The threat model this set names is the taking of a device (Network:803), and that taking yields the answering key.
- **Q3. How a link gets fresh keys.**
  - (a) The renewal of the draft: 5 units, one new domain, chained on the previous secret.
  - (b) A whole new handshake inside the standing channel: 14 units, two signatures, no new domain, not chained.

  Recommendation: (a).
- **Q4. Whether a pipe heals.**
  - (a) In band, by a pair of letters (the draft).
  - (b) Not at all. Network:803 stays a named limit, and healing is a new first contact.

  If (a), when a correspondent offers a heal:
  - (i) in the first letter it sends in a window while no heal of its own is pending;
  - (ii) once per period of the entries (Network:657-663).

  Recommendation: (a) with (i). The cost falls only on letters that are sent anyway, and the exposure after a taking is bounded by the conversation's own rhythm.
- **Q5. The step label.** Should it stand on the renewed secret of the link rather than on the handshake's? Recommendation: leave it to #22, where the random label of the code already stands.
- **Q6. Adoption.** Should the draft move into the in-force text of Network, with the Canon form, the ledger rows, the conformance item and stage 18 of the plan in one change? Or should it stay proposed until the transport routes by tags (Registry:129-134)? Recommendation: adopt the text and the Canon form together. The code follows the list above.
- **Q7. The wording of [I-16].**
  - (a) Restate the invariant's second sentence as Claim C3′ above: for any set of points that does not hold both ends of a delivery, an observer's advantage in telling what an object is, who sent it, for whom it is, or whether a machine is its origin or a relay is bounded by the honest volume it does not control, the delay profile and the path length, and is nil for what the object is.
  - (b) Keep the present words and name Proposition 2 as a limit in the observability ledger (Network:830-836).

  Recommendation: (a). Proposition 2 shows the present words cannot be proved; (a) claims what Theorem 1 proves and what stage 22 can measure.
