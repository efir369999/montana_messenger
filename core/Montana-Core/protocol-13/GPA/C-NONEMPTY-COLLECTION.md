# Causal collection: a joint-endpoint separator and its proof boundary

Implementation **M = `2c7eb0df782da1679d20fc220499e9e3ab72c6b6`** is retained.
Document parent: `c47d8a66239cf04953bf9a78a622e44a684c5761`, branch
`codex/issue-5-leakage`, PR #33. Fourth session, 2026-10-25 UTC.
**Every implementation citation, line number and code quote in this file is at M.**
Names below abbreviate files under `core/Code/crates/`; the source links at the end
pin that same commit. Source widths and counts are deductions, not measurements.

Part A is separate: [PR #44][ack-pr], commit
`83f372b8c49f7460526ebd8703e230aef1bf559f`, based on the chair's main pin
`7e7e4e10759cac17b0cff1e8ab118153d883d8cd`. At the part-B pin check on
2026-10-25 UTC, that PR was open, unmerged, and main was
`c7270dd1a9e0c5866053e745a947c87db22acf0f`; the ACK fix had not landed there.
This document does not silently import it into M or revise the old M-specific ledger.

**Result.** The offline witness cannot be extended by its old identical-active-state
coupling: the receive ID now enters a sealed request and is opened at H. P and H's
joint endpoint projection joins that request to its physical receiver. Correctly
opened requests separate the ownership worlds already at the first collection nonce,
before subscription, response or ACK. Section 3 proves a conditional distributional
obstruction, retaining all failed and unfinished traces. An unconditional assertion
that no admissible pair exists for the actual finite-horizon M execution remains
**open**, with the exact outstanding premise stated there. No equal-joint-leakage
collection witness is claimed. In particular, a successful-path argument is not
silently promoted to a proof about unconditioned execution distributions.

## 1. Exact extension of P-MUQ-DEFERRED

Name **P-MUQ-DEFERRED-COLLECT** means the two sender instances of
[C-NONEMPTY-MAP.md section 1](C-NONEMPTY-MAP.md#1-c-nonempty-first-deferred-receipt-with-hidden-capability-ownership),
followed by **each receiver connecting to P, subscribing through P to its own queue
at H, locally opening the returned payload, and acknowledging through P if it received
and opened its expected single item; no application retry, all prefixes retained**.
This is a specified MUQ library caller, not the shipped phone path.

Keep A, B, C, D, P, H, their physical endpoints and public identities fixed. Keep A's
bundle X and B's bundle Y, secured queue records, send states, routes and messages
unchanged. Let the distinct receive IDs be rX and rY, and the fixed distinct message
IDs be mA and mB. Choose the version of the earlier setup that puts the two public
queue records and A-to-X/B-to-Y associations in x. This is allowed by that witness;
it gives no receive signing key, payload secret key or C/D ownership bit to the
observer. z gives the two workload descriptions and no prior provisioning trace.

| World | A / B intended recipients | C owns and collects | D owns and collects |
|---|---|---|---|
| Q0 | C / D | X: rX, receive signing key, payload secret key | Y: corresponding bundle |
| Q1 | D / C | Y: rY, receive signing key, payload secret key | X: corresponding bundle |

Only actual ownership and necessary receive inputs switch. Per-sender offered bytes,
times and IDs stay fixed; each recipient is offered one four-byte message. There is
no complete-machine renaming, duplicated receive capability or fetching both queues
as cover. Those would be different experiments, not this extension.

Choose o = G+P at **both P and H**, just as before: all physical links and each named
endpoint's decoded requests/responses with connection, order, lengths, times and
visible equalities. P decodes a wrapper containing the sealed blob; H decodes the
inner receive ID. Joining these observed records does not grant an observer either
endpoint's secret key or arbitrary internal state. It is not a claim for G alone,
P alone, H alone, or a non-colluding observer.

Fix n = 3 adjacent 60-second observation intervals, starting at
**t0 = 2026-10-25 00:00:00 UTC**, ending at **t0+180 seconds**, before selecting b.
These are hypothetical experiment parameters, not measured times or chain windows.
A and B offer their original operations at t0+1 and t0+2 seconds. C and D remain
disconnected in the first interval, then offer their collection at t0+61 and t0+62.
Each calls `MuqClient::connect(P)` once; on success it calls
`subscribe_via_courier(H, H_kem_pk, own_recv_id, own_recv_sk)` once. On an API error
it stops. On a decoded response it checks for its one expected message ID and shard
0/1 and opens its payload with its own payload secret key. Only a matching successful
receipt triggers one `ack_via_courier` call using that same receive bundle. An empty,
unexpected or unopenable response stops without ACK. No local check writes network
bytes. A blocked operation remains blocked in the trace at the fixed end time.

The same causal E and initial randomness law govern both worlds; E may depend on
actual execution history, not privately on b. It includes losses, TLS/TCP behavior,
errors, OS scheduling, clocks, server pruning and contention. No successful completion
or fixed latency is assumed by extending a wall-clock deadline. No trace is rejected.
The old sender APIs can still be pending when collection starts. H's queue contents
are what M produced, not overwritten with a desired response. All earlier and later
traffic in the three intervals is retained, including operations that fail or finish
after the original first interval. This is a new joint experiment under Definition C.

## 2. Source path, observable join and complete collection map

The old deposit map still applies at M, including its MAP-ACK defect. The following
maps the additional caller. Every event listed belongs to section 4.3 **First use /
collection / ACK / shard fan-out** and its section 4.5 transport/lifecycle subrows;
the unchanged sender deposits retain their own two section 4.3 rows.

| Event on the extension, including failure branches | Evidence at M and observer-visible consequence |
|---|---|
| Receiver probe, TLS establishment, EOF/drop without an operation tag | [client:33-47,72-83][client]; [server:120-152][server]. Fixed physical C/D endpoints remain visible. Probe failure stops the caller. TLS record/packet counts, timing and close form remain open. |
| First collection nonce: seal the owned receive ID, fresh connection, tag 0x18, frame | [client:159-175][client], specifically `seal_to(host_kem_pk, &recv_id)` at :165. P decodes H and the sealed blob, on the receiver's connection; it does not decrypt that blob. Local seal/open-stream/write errors or pending operations retain their actual prefixes. |
| P decodes wrapper, resolves route, forwards identical sealed blob on a fresh connection, tag 0x19 | [handlers:282-293,455-478,500-509][handlers]: `forward_nonce_to_host(addr, &pf.sealed).await?` at :291, `send_frame(&mut st, sealed).await?` at :506. No route or forwarding error propagates; no replacement nonce is written by P. Visible blob equality joins the two endpoint records even if operations interleave. |
| H reads sealed nonce request, opens it to 32-byte receive ID; writes 16-byte nonce | [handlers:297-315][handlers]: `open_from(&state.host_kem_sk, &sealed)` at :302, `rid.copy_from_slice(&b)` at :305, `.issue_nonce(&rid)` at :310. Open/length failure selects zero bytes at :312. [queue-host:65-73][queue-host] issues/stores a random nonce; it does not check queue membership here. H's decoded rX/rY, correlated with P's receiver connection, is the first source-certified ownership separator on a correctly opened request. It is not inferred from a unique random nonce. |
| P returns the same nonce to the requesting receiver | [handlers:507-509,291-292][handlers]; [client:173-175][client]. Host read failure propagates; an unfinished read does not become a response. A valid random nonce can itself be zero; no proof here treats nonzero as a success certificate or assumes nonce collisions impossible. |
| Receiver signs the nonce with its receive key, seals QueueSubscribe, opens new connection, tag 0x14, frame | [client:135-154][client], [encoding:299-329][encoding]. This is the subscription/fetch half of the same API call, not an independent automatic poll. The encoded receive ID, nonce and signature become decoded request metadata at H. Signing/sealing/open/write failures stop the call. |
| P forwards sealed subscription unchanged with tag 0x15; H opens/decodes, validates and builds QueueResp | [handlers:264-277,364-389,490-497][handlers]. Wrapper/route/forward errors propagate. At H an open/decode failure attempts an empty QueueResp (:375); queue/signature/nonce errors become empty items (:382-383), not an ERR byte. [queue-host:158-182][queue-host] verifies the stored receive key and consumes the issued nonce. Fetch does not drain the buffer. |
| H sends framed QueueResp; P receives it and sends the same response bytes to that receiver | [handlers:385-388,497,275-276][handlers]. [queue-host:227-240][queue-host] copies stored message IDs, shard fields and ciphertext into QueueItem; [encoding:346-357][encoding] writes those fields without a new end-to-end response seal. P therefore observes mA or mB and ciphertext equality as well as the receiver connection. Payload plaintext remains sealed. Empty/error/partial replies stay in the trace. |
| Receiver decodes response, locally checks and opens payload | [client:153-154][client], [encoding:360-400][encoding], [crypto:526-540][crypto]. The local caller policy in section 1 determines whether the next call occurs; it is not a hidden new network event. Bad or empty responses cannot be counted as successful collection. |
| Receipt ACK first requests a second host-issued nonce | [client:180-189][client]. This repeats the entire 0x18/0x19 path above with fresh API randomness, including its failures, visible blob equality and decoded receive ID. It is not reuse of the consumed subscription nonce. |
| Receiver signs and seals QueueSubscribe again, tag 0x1A; P forwards unchanged with tag 0x1B | [client:190-206][client], [handlers:319-330,512-519][handlers]. H opens/decodes and invokes `ack_drain` at [handlers:334-359][handlers]. [queue-host:189-211][queue-host] checks key/signature and issued nonce before draining that queue. H replies OK/ERR; the forwarding read uses `?` and returns the actual byte (:517-518); P writes that byte (:329). Read/write failure or pending states remain. |
| Return/drop, partial reads/writes, TLS alerts, FIN/RST/ACK, retransmissions and background contention | [wire:28-71][wire], [client:33-47][client], [handlers:465-519][handlers], [server:110-152][server]. All physical events enter section 4.5. Prune tick at server :114-117 and queue-host :220-225 can change later contents/timing. Exact event realization is open, not absent. |

**Widths, not transport measurements.** At M [crypto:508-521][crypto], sealing adds
1088+16 bytes. A 32-byte receive ID gives a 1136-byte seal; the wrapper and tag/frame
produce 1177 application bytes receiver-to-P and 1141 P-to-H. Each successful nonce
reply is 16 bytes on each leg. A subscription is 32+16+3309 = 3357 bytes at M
[encoding:305-311][encoding], hence 4461 sealed bytes, 4502 receiver-to-P and 4466
P-to-H application bytes. ACK uses the same request encoding and a one-byte reply.
A successful QueueResp frame is `6 + sum_i(22 + q_i)` application bytes, including
its four-byte length prefix and two-byte item count; the single original 1108-byte
payload seal gives 1136 response bytes. Empty QueueResp is six framed bytes.
These totals apply only to completed writes. A full receiver sequence has one probe
and four operation connections to P (nonce, fetch, nonce, ACK), plus four P-to-H
connections. Failures and the caller's receipt gate can reduce that sequence. No
number of TLS records or physical packets follows from these application counts.

**Why the join is in the existing leakage.** P's decoded wrapper retains the blob
and its visible equalities; H's request processing receives that same blob and adds
the decoded ID. These are endpoint-visible application bytes, not an equality guessed
between two independent TLS ciphertexts by G. Match the sealed-blob equality class
across P and H, retaining the original P connection and the H decoded ID. Deterministic
opening under the same H key gives the same result for identical blobs; duplicates
do not yield two different decoded IDs. No collision-free RNG assumption is needed.
The equality relation suffices; the observer need not reconstruct either TLS stream
from lengths. This argument uses neither PQ key anonymity nor a simulator.

The first established **semantic** separator is the H nonce-open event at handlers
:302-305, joined to the prior P wrapper at :286-291. The earlier receiver probe/tag
identifies C or D but not its queue. We do not prove equality of every earlier physical
timestamp or opaque ciphertext law: a byte-sensitive implementation might leak earlier.
Thus “first” here means the first directly decoded ownership event on this source
path, not a theorem that every preceding physical observation has equal distribution.

## 3. What follows for Definition C, without dropping failed traces

Let J(T) be the following deterministic statistic of the **full** declared joint
leakage: for C's first collection-nonce connection, return the receive ID decoded at
H from the identical forwarded blob, or bottom if no such decoded record occurs
before the horizon. Request tags distinguish this connection from the probe/fetch/ACK.
Visible blob equality and connection identities define J even with concurrent D
traffic. All failures remain in the input; bottom is an output, not a discarded trace.
The public setup specifies rX != rY and associates them with A/B's fixed queues.

**Trace lemma.** Whenever C's first nonce request is forwarded and opens to its
actual input ID, J(T0)=rX in Q0 and J(T1)=rY in Q1. This follows directly from
client :165 and handlers :291, :506, :302-305. The secret is now a causal input.
Any two such complete traces have different leakage, irrespective of matching sizes,
randomness, packetization, times, later fetch results or ACK outcomes. Appending
observations cannot erase an earlier differing prefix. This refutes an extension
of the old pointwise induction through that event.

**Distribution lemma with an explicit premise.** Write

```
p0 = Pr_Q0[C's first request reaches H and opens to its input rX by the horizon]
e1 = Pr_Q1[J(T1) = rX]  // a wrong-ID result, since C's actual input is rY
B  = {Lambda : J(Lambda) = rX}.
```

These probabilities are over all executions, including failures and setup/runtime
randomness. B is observable and uses public IDs, not a challenged secret key. Then

```
Pr_Q0[B] >= p0,       Pr_Q1[B] = e1.
If p0 > e1, then Law(Lambda_0) != Law(Lambda_1).
```

Proof: correct Q0 openings imply B; the Q1 probability is its definition. The strict
inequality gives an observable event with unequal probability, contradicting
Definition C clause 3. Consequently **no coupling** can make the full joint leakage
equal in distribution for these worlds under that premise. A symmetric argument
uses rY, or D, if that receiver supplies the reachable request. This is a symbolic
criterion, not a numerical anonymity estimate.

In the usual functional model where honest sealing either opens to its input or
fails, e1=0; any positive probability p0 suffices. Loss and noncompletion can have
positive probability in both worlds and do not invalidate the argument. We do not
condition on delivery, assert perfect ML-KEM correctness, or replace e1 by zero merely
because a failure is thought unlikely. The wrapper's source calls ML-KEM decapsulation
and AEAD decryption at [crypto:480-501,526-540][crypto]; reading that wrapper does not
prove the exact distributional contract of its FFI/dependency implementation.

**C-COLLECT-EXACT remains open.** To turn the conditional obstruction into the
requested unconditional no-pair result for the concrete fixed-horizon M execution,
settle `p0 > e1` (or its symmetric version): specify the transport/runtime E enough
to establish positive timely correct-opening probability, and establish an adequate
honest round-trip/wrong-output contract for M's sealing implementation. A checked
functional correctness argument plus a justified reachability/error bound would
settle it. Test examples alone would not prove exact distributional non-equality.
Those facts are not supplied by equal source lengths, a longer deadline, or this
no-runs source review. We do not close PQ-KEY/PQ-SEAL or import unverified bounds.

There is also no valid universal claim over every E permitted by Definition C:
an E in which every receiver remains stalled before producing an owner-dependent
request preserves the earlier obstruction to observing ownership, despite attempted
collection. The definition expressly retains these executions. Restricting to
“successful collections only” after execution would violate its clause 4. The two
fixed ownership permutations above exhaust the two-bundle experiment, not every
possible MUQ workload/queue setup or observer. No impossibility theorem for all M,
no smallest necessary code change, and no equal-leakage online witness is asserted.

Fetch supplies a second, later semantic separator on correct receipt: C's response
contains mA in Q0 and mB in Q1, with unchanged stored ciphertexts, by queue-host
:128-134, :227-240 and encoding :346-357. P can read these fields. This does not
remove the nonce proof's reachability/correctness boundary; it also requires actual
queue contents and a completed valid response. ACK is still mapped above because it
belongs to the requested horizon, not because waiting for ACK is needed to identify
the earlier decoded-ID exposure.

### 3.1 C-COLLECT-EXACT: why the source does not supply the missing bound

Follow-up to the chair's fourth-session review, 2026-10-26 UTC; same M and
same 180-second experiment. The requested source-only alternative can be settled:
**the stated experiment does not determine a strictly positive separation bound.**
This settles the reason for the missing bound, not the unconditional no-pair claim.

Here is a sufficient contract that does not assume independence. In Q0, let R be
the event that C's first collection blob is presented for H's opening and that
opening finishes by the fixed horizon. Let F be the subset of R on which it does
not open to C's actual input rX (including rejection). Write q0 = Pr_Q0[R] and
f0 = Pr_Q0[F]. Then, by the definition of p0 in section 3,

```
p0 = q0 - f0.
If q0 >= q, f0 <= delta and e1 <= epsilon, then
Pr_Q0[B] - Pr_Q1[B] >= q - delta - epsilon.
q > delta + epsilon is sufficient for unequal full leakage laws.
```

All probabilities are unconditional, over the original executions. F is a subset
of R, so this subtraction is exact; no multiplication of independent transport
and cryptographic probabilities is used. An error rate conditional on completed
openings cannot silently be substituted for these unconditional bounds. An upper
bound for e1 must cover the *joined statistic* J, including its association with
C's blob, rather than only an unrelated invocation of the decryption primitive.
When q <= delta + epsilon this criterion is inconclusive; it proves neither
equal leakage nor absence of another distinguishing event.

The following missing inputs are distinct:

| Obligation | Source establishes | Still needed for a concrete strict bound |
|---|---|---|
| q0, timely reachability | Client :33-47, :159-175 and handlers :282-315, :455-509 define awaited operations and error branches. Section 1 permits unfinished operations at 180 seconds. | A specified E and initial randomness law with a justified lower bound on completion before that horizon, including scheduling, connection/probe, forwarding and opening. An offered call is not a completed call. |
| f0, honest failure | Crypto :454-540 calls encapsulation, decapsulation and AEAD and propagates errors. | A correctness/error contract for the actual generated key pair, encapsulation randomness, native provider, AEAD and executed build, sufficient to bound failed or wrong honest openings in the joint experiment. |
| e1, wrong joined output | Handlers :286-305 and :506 preserve the blob and expose H's opened ID; the section 2 equality join applies. | A bound that this blob from C with input rY is joined to decoded rX, with the request association and any permitted transport behavior included. Source comments asserting integrity are not this probability proof. |

The implementation dependency is concrete: at M,
`mt-crypto-native/csrc/mt_crypto.c:454-545` calls OpenSSL
`EVP_PKEY_encapsulate` and `EVP_PKEY_decapsulate`. Its `build.rs:15-24`
selects either `MT_OPENSSL_DIR` or an `openssl_src` build. The Rust AEAD is
`chacha20poly1305` 0.10.1 (`Cargo.lock:302-314`). Reading these call sites
identifies proof dependencies; it does not certify the selected binary/provider,
its correctness probability, or a concrete cryptographic error bound. No such
certificate is introduced by this document.

There is a decisive obstruction even if perfect honest round-trip correctness is
added as an assumption. Choose the same causal E in both worlds that never
schedules C or D beyond the pre-request probe during the horizon. Offers and all
failed/pending traces remain; there is no conditioning and no scheduler access to
b. This E is permitted by Definition C and section 1. Then q0 = p0 = e1 = 0:
J is bottom in both worlds and the strict premise cannot follow from M for every
allowed E. This is a counterexample to a *universal bound*, not a proof that the
entire earlier/later physical leakage is equal in the concrete execution.

Thus selecting another horizon, asserting eventual progress, or running examples
cannot fill this gap. A fixed E with a proven timely-progress lower bound and
adequate joint wrong-output/error bounds must be supplied to apply the displayed
criterion. No numerical anonymity estimate, equal-leakage collection witness,
PQ-KEY/PQ-SEAL result or unconditional C-NONEMPTY impossibility follows here.
C-COLLECT-EXACT remains open for any particular execution law until those inputs
are supplied; its source-only underdetermination is now explicit.

## 4. Accounting against every section 4 row

This is a row-by-row **obstruction map**, not a table claiming equal marginals or
complete view simulation. All rows refer to the same experiment and joint leakage.

| Section 4 row | Contribution and equality/proof boundary |
|---|---|
| 4.1 observer/units | Same named G+P endpoints, physical identities and application/physical distinction. Joint endpoint equality is visible; G alone has no such declared plaintext equality. |
| 4.2 first-contact wake | No phone wakeRdv caller; no instance. |
| 4.2 continuing-letter wake | No phone wake caller; no instance. |
| 4.2 live phone letter | No sendLetter caller; no instance. |
| 4.2 direct-channel overlay write | No phone overlay writer; no instance. |
| 4.2 long-text blob | No wake/blob uploader; API ciphertext is not that branch. |
| 4.2 media body | No media constructor/uploader; no instance. |
| 4.2 media manifest/accompaniment | No manifest, PUT/GET, cache or mirror caller; no instance. |
| 4.2 send moments/retries/background | No phone delivery engine. The defined API offers, errors, prune activity and all transport reactions remain in 4.3/4.5. No equality of later timing is inferred. |
| 4.2 following F3/backoff paragraphs | No agent/card/letter or phone backoff; no instance. Observation intervals are not MTPipe or authenticated windows. |
| 4.3 sender to entry proxy | Original deposit caller unchanged. Its first-interval trace can use the old coupling while C/D are disconnected. Pending deposits can overlap collection later; no assertion that their later timing stays equal. |
| 4.3 entry proxy to host | Same deposit source map and M-specific ACK defect. Actual stored/failed/pending outcomes retained; shared host contention after receivers start may change timing. |
| 4.3 first use / collection / ACK / shard fan-out | Receiver probes, nonce/fetch/nonce/ACK events map to section 2 above. Joined decoded receive ID is J, and correct fetch exposes message ID. **This is the first source-certified distinguishing row**; matching widths cannot equalize its joint endpoint fields. No node_hello, registration, erasure or replication call is added. |
| 4.4 first link acquaintance | No reference-core handshake; MUQ handshakes belong to 4.3/4.5. |
| 4.4 ordinary link message | No reference-wire link writer; no instance. |
| 4.4 body to publish::cells_of | No constructor invocation; no instance. |
| 4.4 node deposit of cells | No reference-core cell deposit; no instance. |
| 4.4 collection from public point | No reference-core point query; MUQ fetch is the 4.3 collection API, not this row. |
| 4.4 multi-hop cell carriage/slot | No reference-core carry/slot call; no instance. |
| 4.5 all-link/open boundaries | All opens, closes, failures, pending prefixes, packets, retransmissions, timestamps and contention remain. Physical transport laws are open. They cannot erase a present J event, but they affect whether it occurs before the horizon. No notification process exists in this caller. |

No new application event in the selected extension is left without a section 4
destination. MAP-TLS/TCP and MAP-CLOSE remain open subrows; MAP-OPAQUE remains open
for full-byte simulation. Source coverage is not completeness of a physical transport
law, and the earlier table/ledger still awaits the chair's row-by-row check.

## 5. Status and next check

**DONE:** written collection caller, all-branch source map, joint-endpoint join,
correct-opening trace lemma, and conditional unconditioned-distribution obstruction.
The old disconnected-state proof cannot be reused once collection reads ownership.
Part A's fix/tests are separately submitted in PR #44, not applied to this M.

**OPEN:** C-COLLECT-EXACT as defined in section 3; an equal-joint-leakage collection
witness has not been established either. SIM, PQ-KEY, PQ-SEAL, JOINT, SEQ and W-M
remain open as written. No statement here closes the shipped phone path, transport
subrows, observed provisioning, or issue #4. There is no numerical anonymity claim.

**NEXT:** chair review of section 3.1: the sufficient unconditional bound and
the admissible stalled-environment counterexample. Supply the stated E/provider
contracts before treating this as an unconditional negative C-NONEMPTY result. The new source map needs line-by-line review; earlier
intake acceptance does not imply acceptance of this file. A different observer or
caller would require a separately authorized experiment, not relabeling these rows.

Verification: pinned source reading and separate Critic self-review of projection,
quantifiers, failures, causality and claim strength; static diff inspection only.
No cargo, builds, tests, benchmarks, measurements, captures or proof-checker runs.
No RELEASES.md, WINDOW-THEOREM.md or formal/Window.lean edits.

-- Codex, model id not visible to the agent, agent on issue #5

Co-Authored-By: Codex (model id not visible to the agent) <noreply@openai.com>

[ack-pr]: https://github.com/efir369999/montana_messenger/pull/44
[client]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/muq_client.rs
[handlers]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/muq.rs
[queue-host]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/queue_host.rs
[encoding]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/muq.rs
[crypto]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-crypto/src/lib.rs
[wire]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/wire.rs
[server]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/server.rs
