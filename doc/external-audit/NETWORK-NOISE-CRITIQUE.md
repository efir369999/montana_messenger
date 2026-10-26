# Network noise: cost, leakage and the limits of the proposed defence

Status: analytical review; implementation and GPA closure remain open. Refs #2, #5.
Date: 2026-10-26 UTC. Reviewer: GPT agent [01a17795], gpt-6.

This reviews the [maintainer's criticism](https://github.com/TokTok/c-toxcore/issues/3112#issuecomment-6317108516)
and the [Montana reply](https://github.com/TokTok/c-toxcore/issues/3112#issuecomment-6317191059).
It is a proposal for the Montana chair, not a message posted to that upstream project.
All Montana source citations below use public snapshot
`a835c1c3ff4bc95ea3c75e02391d3d69e2e08833` (iOS 2314 / Android 552).
The separate [PR #33](https://github.com/efir369999/montana_messenger/pull/33)
is read at `7819d52a951d8393f6fba36767f4efae6a2c0ce7`; it is unmerged and its
older implementation pins are not silently replaced by this snapshot.

## 1. Verdict on the disagreement

The bandwidth objection identifies a real cost. Calling the cost prohibitive for
every application would still require a workload, latency target and resource
budget. Conversely, declaring a 4096-byte padding scheme negligible without its
frequency, directions, paths and duty cycle is not an engineering answer.

The maintainer is also right to ask for evidence of a particular timing attack.
The stated relay interval alone proves neither security nor an attack. We have
not measured or attacked a running Tox deployment. Its own
[protocol objectives](https://toktok.ltd/spec.html#non-goals) exclude anonymity
from the protocol's goals; its onion machinery does not amount to a promise of
whole-session protection from a global passive observer. Upstream is entitled
to keep a different threat model.

There are alternatives to rebuilding Tor or I2P, but an optional padding layer
must specify its own security and integration contracts. Tor's
[design paper](https://svn-archive.torproject.org/svn/projects/design-paper/tor-design.html)
explicitly leaves global traffic correlation outside its protection.
[obfs4's documented purpose](https://support.torproject.org/tor-browser/circumvention/unblocking-tor/)
is censorship circumvention, including disguising traffic and resisting bridge
discovery. That is not evidence that a pluggable transport removes end-to-end
timing or volume correlation.

The Montana reply overclaims in three places: a fixed block size does not supply
a complete anonymity proof; a secret-dependent switch to bulk mode can itself
be observable; shuffling preserves the amount of data that must cross a link.
These statements should be corrected before relying on that reply as a design
description. A source pin, cost model and explicit open obligations answer the
credibility objection better than claims about another project's motives.

## 2. What the present Montana specification actually says

| Subject | Pinned evidence | Consequence for this discussion |
|---|---|---|
| Observer boundary | [Constitution I-16, 378–430][constitution] | Both ends of the same delivery are explicitly excluded from the closed invariant. Correlation of envelopes is acknowledged. This is not an unconditional GPA guarantee. The stronger assertion for observers outside that exception still needs implementation evidence. |
| Cover supply | [Constitution, 401–426][constitution]; [Canon, 2490–2498][units] | Synthetic filler is forbidden; the proposed load is useful transit for others. The text acknowledges that superimposed flows need not be inseparable. |
| Deferred delivery | [Canon, 1323–1337][delay]; [Network, 437–443][deferred] | The proposed distribution is uniform over remaining chain residues, not a Poisson distribution. It is bounded by a window and does not apply to live traffic. |
| Logical unit width | [link splitting, 32–55][pieces]; [width derivation, 106–109][width] | A fixed unit width still leaves a message-dependent number of units. Width alone is not a schedule. |
| Network emission | [mt-net, 262–269][send]; [TCP stream, 34][tcp] | This function writes the pieces sequentially. It supplies no fixed-rate scheduler. Caller scheduling must be inspected separately; this function alone does not prove when a person pressed Send. A logical unit is not necessarily one IP packet. |
| Shipped client parity | [Public finding F-14][f14] | Client letters and frames have a separately acknowledged size problem. Reference-core unit properties cannot be promoted to every shipped client path. |

Consequently, the public reply's 4096-byte constant-rate signalling channel and
automatic bulk shuffling are not established by these sources. They must not be
presented as implemented Montana protection. This report does not introduce
filler, rewrite I-16, or certify the implementation of its remaining assertions.

Recognizing use of a protocol and identifying a correspondence are different
goals. A regular stream can make protocol use recognizable, but that does not
prove that constant-rate padding is universally worse for relationship secrecy.
Conversely, making a stream resemble ordinary traffic does not prove that its
two ends cannot be correlated. We retain the no-filler design constraint without
treating every argument offered for it as an established general theorem.

## 3. Six mechanisms, six different obligations

| Mechanism | What it can address | What does not follow from it |
|---|---|---|
| Padding a unit to one width | Distinguishing plaintext lengths within that unit's capacity | Equal counts, times, routes or total bytes |
| Emitting on a secret-independent schedule | Activity differences on the covered boundary during the covered period | Hidden startup/shutdown, other links, overflow or unmatched online periods |
| Random delay | Precision of matching an input to an output under a specified arrival process | Independence of input and output traces, or hidden volume |
| Mixing different users | Ambiguity among actual eligible candidates | A minimum honest candidate population, or protection when there is one candidate |
| Onion routing / resealing | Which identifiers and contents each hop can read | Resistance to an observer matching both boundary traces |
| Constant-time computation | Selected local processing-time dependence on secrets | A secret-independent network schedule |

The term noise must specify which of these is meant. Useful transit is traffic
paid for and carried somewhere; cryptographic randomness in its content does
not by itself randomize its observable envelope.

## 4. The bandwidth price is calculable before benchmarking

For hypothetical units of `S` wire bytes at one unit every `tau` seconds,
one direction on one link carries `S * 86400 / tau` bytes per day if continuously
active. These are analytic examples of the upstream proposal, not Montana
measurements or recommended settings. They omit headers, retransmissions and
connection setup; useful payload is smaller still.

| S | tau | One direction, MiB/day | Both directions at that rate, MiB/day |
|---|---:|---:|---:|
| 4096 bytes | 60 s | 5.625 | 11.25 |
| 4096 bytes | 10 s | 33.75 | 67.5 |
| 4096 bytes | 1 s | 337.5 | 675 |
| 4096 bytes | 0.1 s | 3375 | 6750 |

Multiply by the links actually carrying that schedule, not by an unspecified
hop count. A device's cost and the network's aggregate cost are different.
Radio wakeups, battery consumption and mobile data plans require measurement;
bytes alone do not establish that the cost is negligible.

At 4096 useful bytes/s, 1 GiB needs at least 262144 seconds (about 72.82 hours).
Delivering 1 GiB in 60 seconds needs at least 17,895,697.07 useful bytes/s,
or 143.166 Mbit/s. Maintaining that latter useful capacity as an always-used
wire floor for a day would carry at least 1440 GiB (1.40625 TiB) per direction
per link. These lower bounds optimistically ignore every overhead.

More generally, fix a cut crossed by all bytes of a burst, available useful
capacity `R(t)`, arrival `a`, deadline `a+D`, and no prior usable copy or
side information that reduces the transmitted information. Delivery of an
incompressible `B`-byte payload requires

```
integral_[a,a+D] R(t) dt >= B.
```

If constant capacity is `R`, this is `R*D >= B`. Add backlog `Q` only if those
bytes also have to cross that cut within the same interval. Random ordering
cannot change this conservation constraint. Parallel paths change the relevant
aggregate cut capacity; caching or compression changes the task's assumptions.

This does NOT prove that every anonymous protocol must send at one constant
rate. Variable schedules, user coordination and partial leakage models exist.
For a claim of indistinguishable idle and active observations, however, both
worlds must meet the same observable traffic law, within the allowed security
error. A public change in the permitted load is a different experiment.
The [Comprehensive Anonymity Trilemma](https://petsymposium.org/popets/2020/popets-2020-0056.php)
studies stronger tradeoffs under its stated model, including user coordination;
we do not treat its title as an assumption-free universal theorem.

## 5. Counterexamples to the proposed shortcuts

These are explicit mathematical models, not measured attacks on Montana,
Tox, Tor or Loopix. They refute implications between mechanisms. Activity
unobservability and relationship anonymity must not be confused.

### 5.1 Empty link and no synthetic filler

Consider a boundary with no unrelated traffic or mandatory background messages.
World 0 has no queued payload. World 1 must deliver a positive payload through
that boundary before the deadline. There is no prepositioned copy. Under the
rule that nothing is emitted when nothing waits, the event `at least one byte
crosses before the deadline` has probability zero in world 0, and at least the
delivery probability in world 1. This is an activity distinguisher.

Useful transit can invalidate the empty-link premise, but its mere possibility
cannot do so. A proof must supply an honest-load/admission contract with its
probability, duration and failure behavior. The receiver being offline, other
users going silent and a sparse network are explicit boundary cases. If these
worlds are excluded by the privacy experiment, state that exclusion: this
example alone does not refute relationship anonymity for matched public loads.

### 5.2 Uniform delay does not mean independence from arrival

In a discrete illustrative window with slots `0,...,N-1`, let arrival be `r`
and departure `D_r` be uniform on `{r,...,N-1}`. For two arrivals `r0 < r1`,

```
Pr[D_r0 < r1] = (r1-r0)/(N-r0),    Pr[D_r1 < r1] = 0.
```

The observable distributions differ. The draw maximizes entropy for its own
conditional support; it does not make different supports equal. This argument
concerns a tagged item's departure, not an assertion that an observer can tag
an item in a real mix. Establishing the latter requires the route, observer and
concurrent traffic model. Delaying live calls beyond their deadline is also a
functional failure, not a privacy solution.

### 5.3 Independent additive randomness can be averaged

Suppose a deliberately simplified observer sees counts over duration `T`:
`N0 ~ Poisson(lambda*T)` when inactive and
`N1 ~ Poisson((lambda+s)*T)` when an independent extra flow of rate `s>0` is
active. The threshold `(lambda+s/2)*T` and Chebyshev's inequality give

```
Pr[N0 >= threshold] <= 4*lambda/(s*s*T)
Pr[N1 <  threshold] <= 4*(lambda+s)/(s*s*T)
TV(law(N0), law(N1)) >= max(0, 1 - 4*(2*lambda+s)/(s*s*T)).
```

Here TV is maximum event-probability difference; equal-prior classification
success is `(1+TV)/2`. Finite independent background noise is therefore not
an unconditional shield against longer observation in this model. Actual
traffic need not be Poisson. A construction substituting real messages into
a fixed observable process does not satisfy this additive model.

[Loopix](https://www.usenix.org/system/files/conference/usenixsecurity17/sec17-piotrowska.pdf)
combines mix topology, exponential per-message delays, cover traffic, loops
and providers under an explicit adversary model. Its analysis is not a theorem
about adding a random sleep to an arbitrary transport. Poisson arrivals and
exponential waiting times must not be conflated with a Poisson-valued delay.

### 5.4 Shuffling and bulk-mode transitions

Permuting `n` units still emits `n` units. In the absence of other compensation,
changing the count or duration of emission changes the observer's evidence.
For example, one valid deposit versus two valid deposits changes the offered
load, even if every unit has the same width. This is again an activity/volume
example, not a matched-load sender-recipient swap experiment.

A bulk switch triggered by private demand needs an account of observable
rate changes, connection setup, destinations, ACKs and termination. Declaring
the switch public changes the leakage contract; it does not hide the switch.
Separating signalling from bulk can be a useful engineering choice, but it
does not prove that the combined trace conceals the relationship.

### 5.5 Equal marginals are insufficient

Let `U` be a uniform bit. Two windows with observations `(U,U)` in world 0 and
`(U,1-U)` in world 1 each have the same uniform per-window marginals, but the
event `the observations agree` distinguishes the full traces perfectly. This
is why per-window histograms and independent anonymity-set counts are not
enough. Persistent identifiers, repeated ciphertexts, online/offline behavior
and collection outcomes belong to the same joint view.

PR #33 already supplies the relevant [Definition C and joint-leakage obligations][joint]
and keeps [C-COLLECT-EXACT][collection] open pending a concrete execution law
and progress/error bounds. This report neither supplies that missing law nor
claims its conditional `q - delta - epsilon` bound as a measured advantage.
Failed and pending executions cannot be removed to manufacture a success-only
privacy result. A stalled system can hide deliveries by never delivering;
that is why liveness and privacy must be checked together.

## 6. Concrete closure gate for the chair

The analytical objections above are answered here. Whole-system protection is
not closed. The following evidence is required before a stronger public claim.

| Obligation | Required reviewable artifact | Current status |
|---|---|---|
| Exact claim | Observer positions; protected secret; permitted leakage; admissible matched workloads; observation horizon; allowed compromises and online histories | I-16 names its both-end exception; full implementation proof open |
| Traffic supply | Guaranteed or probabilistically bounded useful transit, resource ownership, admission/overload rules, and sparse-population behavior; retain the no-filler rule | Not supplied by a statement that peers carry others' traffic |
| Execution law | Concrete scheduler, transport/provider errors, progress bounds and a delivery deadline expressed in the actual authenticated window model | PR #33 obligations remain open; do not invent missing E |
| Complete route | Source-pinned path from each client send through holders to collection, with all observable setup/teardown/ACK/error traffic | Unit tests of a cutter or cipher are insufficient |
| Physical traces | Corresponding captures at ingress/egress and intermediate boundaries, actual TCP/UDP segmentation, retransmissions and time synchronization/error | Not measured by this document |
| Adversarial cases | Sparse and saturated networks; late-window arrival; idle versus burst; matched-load relationship swaps; sleep/wake; reconnection; failures; repeated windows; voice and bulk overlap | Required experiment matrix, not tests claimed to have run |
| Security metric | Predeclared full-trace distinguisher advantage or leakage bound with assumptions; held-out evaluation and confidence intervals for empirical attacks; known-bad negative control | Classifier failure alone is not a universal proof |
| Resource budget | Total wire bytes, per-device/network cost, queue sizes, deadline misses, battery/radio use and useful throughput under the same experiment | Arithmetic in section 4 is not a benchmark |
| Delivery and review | Exact core/client builds, device results and separate independent review | This document is self-review, not independent external certification |

The next implementation step is to establish the useful-transit and execution
contracts for the existing construction, then map them to the actual client
route. If the intended claim is stronger than the present both-end exception,
the chair must explicitly settle the conflicting bandwidth, latency and
sparse-load requirements. Adding filler contrary to the specification or
silently excluding difficult executions is not an implementation fix.

A candidate implementation contract can require admission only when enough
useful traffic and capacity are available, and an emission process independent
of the protected action, with real work substituted inside that process rather
than simply added to it. This is a design obligation, not a proved solution:
admission decisions and rejections are observable, useful payloads still have
deadlines, substituted traffic must reach its own recipients, and all affected
links must satisfy the joint-trace requirement. The proof cannot choose a
different unrelated background workload after learning the challenge bit.
If admission cannot meet the contract under the no-filler rule, it must report
that the stronger privacy claim is unavailable; it must not silently deliver
through an unprotected fallback while retaining that claim. The chair must
decide any change to the service's availability contract explicitly.

## 7. Proposed correction for review, not posted upstream

Our previous reply overstated the protection. A 4096-byte block does not by
itself provide traffic-analysis anonymity, and shuffling a bulk transfer does
not conceal its total volume. We should have supplied rates, latency budgets,
an observer model and source-pinned evidence. The Montana specification now
cited forbids synthetic filler, uses other users' useful traffic, and explicitly
does not close correlation by an observer of both ends of a delivery. Its
deferred-mail delay is uniform within a bounded window, not a general Poisson
padding layer. The implementation and joint-leakage obligations remain open.
We have not demonstrated the claimed timing attack against a Tox deployment.
A future optional transport proposal needs its own workload, integration and
resource results before being considered on technical grounds.

## 8. Validation and limits

Read the two upstream comments, primary specifications/papers linked above,
and the cited Montana source sections. Recomputed section 4 with the adjacent
standard-library script, which also prints exact example probabilities for
sections 5.2 and 5.3. These are arithmetic checks of stated models, not a
simulation, privacy test, network capture or measurement of a running product.
No Cargo/build, phone test or additional server workload was started for this
document. The separately running L2 audit does not establish traffic anonymity.

Self-review checked the distinctions between activity and relationship secrecy,
conditional entropy and independence, logical units and packets, present source
and deployed clients, deterministic bounds and probabilistic delivery, and
successful versus failed/pending traces. The unresolved items in section 6
remain open. No new private security finding from the separate audit is included.

[constitution]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/docs/Montana%20Constitution.md#L378-L430
[units]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/docs/Montana%20Canon.md#L2490-L2498
[delay]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/docs/Montana%20Canon.md#L1323-L1337
[deferred]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/docs/Montana%20Network.md#L437-L443
[pieces]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/Montana-Core/crates/mt-wire/src/link.rs#L32-L55
[width]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/Montana-Core/crates/mt-wire/src/lib.rs#L106-L109
[send]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/Montana-Core/crates/mt-net/src/lib.rs#L262-L269
[tcp]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/core/Montana-Core/crates/mt-net/src/lib.rs#L34
[f14]: https://github.com/efir369999/montana_messenger/blob/a835c1c3ff4bc95ea3c75e02391d3d69e2e08833/AUDIT.md#L323-L337
[joint]: https://github.com/efir369999/montana_messenger/blob/7819d52a951d8393f6fba36767f4efae6a2c0ce7/core/Montana-Core/protocol-13/GPA/INTERSECTION-MODEL.md#L255-L310
[collection]: https://github.com/efir369999/montana_messenger/blob/7819d52a951d8393f6fba36767f4efae6a2c0ce7/core/Montana-Core/protocol-13/GPA/C-NONEMPTY-COLLECTION.md#L213-L274
