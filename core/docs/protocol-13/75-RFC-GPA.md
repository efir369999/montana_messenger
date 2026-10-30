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

**What remains open.** Where the game is written (inside the set or beside it), and whether it is
closed by a proof, by the measurement of stage 22, or by both. Neither is possible against code
that does not yet route by tags. This stays with Protocol-13 item 11 (#22) and with this point.

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
- **Exposure in a stall.** At most 2^23 x 1 232 = 10 334 765 056 bytes per direction stay under one key.
- **Nonce safety.** Nonces are drawn at random, 96 bits wide (Canon:2438, 2505). Under one key the chance of a repeated nonce after `q` units is at most `q^2 / 2^97`, which is 2^-51 at the ceiling.
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
