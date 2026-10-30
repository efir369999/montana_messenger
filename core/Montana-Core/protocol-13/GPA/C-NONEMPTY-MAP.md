# A finite-horizon MUQ witness and its transport map

Implementation **M = `2c7eb0df782da1679d20fc220499e9e3ab72c6b6`** is retained.
Document parent: `adc7eed5dcc9e48e46239a59b76568405fc1e987`, PR #33.
This is the third-session contribution to issue #5, dated 2026-10-25 UTC.
Every code citation and quote below is at M. Source arithmetic is not a measurement.

**Result and boundary.** Section 1 supplies a nonempty, nontrivial instance of Definition C
for a pre-established MUQ API workload with offline recipients and a fixed finite horizon.
The proof couples complete active state and bytes, not just source lengths. The chair
[accepted this result for intake][chair-review] with the qualification **non-empty but
uninformative**: it shows that Definition C is satisfiable, not that Montana provides
unlinkability. It must not be cited as evidence of anonymity. Section 2 maps
one named API path, including its failure prefixes, to section 4 of
[INTERSECTION-MODEL.md](INTERSECTION-MODEL.md). Its physical transport subrows remain open;
this is not a completed MAP proof or a ciphertext simulator. No implementation is changed.
Observed setup, online receiving, the shipped phone caller and longer horizons remain open.

## 1. C-NONEMPTY first: deferred receipt with hidden capability ownership

### 1.1 The exact path and public experiment

Name **P-MUQ-DEFERRED** means: **one local payload construction, then on success one
`MuqClient::connect` followed, if it succeeds, by one `deposit_via_proxy`; one entry proxy,
one queue host, a pre-established secured queue,
receiver offline for the whole horizon, no fetch or application retry; all success, failure
and unfinished prefixes included**. There are two instances of this same path, one per sender.
This is an explicitly specified caller of the published `core/Code` library, not a claim that
an iOS send button selects it. It uses existing APIs; no new transport or code is proposed.

Fix four distinct honest physical machines A, B, C, D and two distinct carrier machines P, H.
Their physical endpoints, machine names, public long-term identities and transport setup retain
the same meanings in both worlds. P has the same route to H in both worlds. P and H run
`PostmanServer`; no phone process, reference-core node, discovery process or other application
runs in this experiment. The server's own prune task is included, not suppressed.
The registration/queue capability setup is pre-established private initial state. Observation
starts at t0; there is no previously observed registration or capability-exchange traffic.
This limitation is part of x before the bit is chosen, not traffic removed from a transcript.

Choose **o = G+P**, with read-only observations at **both P and H**: decoded MUQ requests,
responses and their lengths/order/times, in addition to all physical links. Neither C nor D's
private storage is observed. Use the original leakage projection of Definition C unchanged.
Fix **n = 1**, **t0 = 2026-10-25 00:00:00 UTC**, and the observation interval
**[t0, t0 + 60 seconds)**. These are experiment parameters, not a recorded observation.
Fix an observer resource bound in x before b; the coupling does not depend on its value.
This is an observation interval, not an authenticated chain window. All machines' clocks and
the transport's initial state have the same setup law. No end time depends on completion.

E has the following fixed policy. C and D stay powered off and disconnected throughout the
interval; their stored capabilities cannot be read by the runtime or any other machine.
A offers its operation at t0+1 second and B at t0+2 seconds. Each caller constructs its payload,
connects once and, if successful, calls deposit once. Errors end that caller without a retry;
a blocked operation stays in the trace until the fixed horizon. P and H serve the operations
using M, including pruning. The network/platform evolves causally from active machine state,
actual bytes and its own initially bit-independent randomness. It cannot read the disconnected
receivers' storage or a private recipient label in the experiment description. This is the
ordinary separation of machines, not a scheduler that equalizes sizes or departure times.

Fix any one such physical transport/runtime realization and its stochastic policy before b;
use it unchanged in both worlds. The proof below is pointwise for every realization/tape,
so it does not require an invented TLS packetizer, a constant-time implementation, a guessed
delay distribution or a loss-free run. E may include ordinary losses, retransmission and
OS delays; the passive observer controls none of them. No outcome is discarded.

### 1.2 Honest initial state, the two worlds, and real recipients

Provision two independent private capability bundles, X for A's outgoing queue and Y for B's.
For each bundle provision:

- A distinct send/receive queue-ID pair, positive rotation epoch and quota, and an empty
  registered queue on H, with ML-DSA receive and send authentication keys. Use honestly
  generated ephemeral keys, not either recipient's fixed public identity key. Queue IDs and
  public queue records may even be in x, provided no public record binds a bundle to C or D.
  The fixed setup contains valid distinct IDs; this is a choice of valid initial state, not
  rejection of execution traces. The public `Queue` input and its decode constraints are at
  M [mt-overlay/src/muq.rs:18-27,101-115][queue]; registration stores the two indexes at
  M [mt-overlay/src/queue_host.rs:82-104][register]. Ephemeral per-queue key derivation is
  explicitly separate from account keys at M [mt-overlay/src/muq.rs:478-491][queuekeys].
- An independently generated ML-KEM payload keypair. Give its public key to the sending
  caller; keep its secret key in the receive bundle. The generation API is at M
  [mt-crypto/src/lib.rs:380-404][kemgen]. A sender seals the offered bytes with that public
  key using M [mt-crypto/src/lib.rs:508-521][seal]; the receive bundle supplies the argument
  to `open_from` at M [mt-crypto/src/lib.rs:526-540][open]. This is an opaque payload valid
  for the MUQ API, not an assertion about an iOS envelope format or its identity handshake.

The setup sampler generates these keys honestly once and provisions a world before its
observed execution. Public outputs enter x; no seed or secret key enters z. The two workload
samplers use the same key-generation law. Coupling their draws identically is a proof device,
not a second real run with forced RNG, and does not condition on absence of collisions or
favorable encryption, transport or storage outcomes. Setup means a valid pre-existing API
state; a construction of that state from an **observed** first contact is a separate task.

The fixed per-sender workload is A's four bytes `left` and B's four bytes `rght`, with distinct
fixed message IDs. Each sender seals its payload to its bundle's payload public key, puts that
ciphertext in `HostDeposit.ct`, sets shard index 0, total 1 and TTL 240, draws a fresh deposit
nonce, signs with its bundle's send key, seals the encoded deposit to H and wraps it in
`ProxyForward { host_addr: H, sealed }`. These are existing input types and operations at M
[mt-overlay/src/muq.rs:117-150,208-221][deposit],
[mt-overlay/src/muq.rs:440-455][sign], and [mt-crypto/src/lib.rs:508-521][seal].
All lengths fit the M API limits: the four-byte payload seal is 1108 bytes by the 1088-byte
KEM ciphertext and 16-byte tag; M's shard cap is 2 MiB at
[mt-overlay/src/frame.rs:12-15][cap]. These are derived widths, not runtime observations.

| World | A's intended recipient | B's intended recipient | Private receive state at C | Private receive state at D |
|---|---|---|---|---|
| Q0 | C | D | X's recv ID, receive signing key and payload secret key | Y's corresponding capabilities |
| Q1 | D | C | Y's corresponding capabilities | X's corresponding capabilities |

A keeps X's sending state and B keeps Y's sending state. H keeps the same queue records and
P the same route. The workload's relationship association changes consistently with the
table; the API caller uses the selected bundle and has no address-book process or serialized
C/D identity. The difference in actual receive storage makes this more than that association. Each
recipient is offered one four-byte message in either world, while which message changes.
Unrelated workload, public machine identities and offered times are unchanged.

This is not an annotation-only recipient switch. The **actual decryption and collection
capabilities in C and D's storage differ**. After the fixed horizon, the designated recipient
has the key required by `open_from`, and its queue signing key is the one checked by
`subscribe_relay` at M [mt-overlay/src/queue_host.rs:158-182][subscribe]. The host buffers the
actual ciphertext under the receive queue at M [mt-overlay/src/queue_host.rs:109-135][store].
The other recipient is not provisioned that bundle. No exclusivity theorem against breaking
cryptography is needed or claimed here. Correctness means intended decryption with the
matching key, subject to the implementation's ordinary errors, not guaranteed delivery.
There are real offered, differently valued messages and deposit operations; this is not an
empty workload, universal dropping, or a renaming of the entire public machine set.

z gives both workload algorithms, both possible associations and the public setup, but no
actual receive-capability ownership bit, private provisioning trace or honest secret key.
In particular it does not give a previous observed trace connecting X to C. Supplying such
additional information defines a different experiment and requires another proof.

### 1.3 Complete joint equality, including the open transport boundaries

Couple the two executions by using the same setup draws for X, Y, P and H; the same per-sender
crypto draws; and the same random tape for every active process, allocator/hash table, TLS
session, clock, network and OS scheduler. Within either world draws retain their ordinary
joint law; we do not assume independence between successive observations. Only the ownership
of disconnected receive storage and the private relationship association differ.

Initially, every state component read by an active computation is identical. At each step:

1. A and B call the same APIs on identical bytes and identical keys. In particular
   `seal_to` has the same **public-key input and plaintext**, not merely the same output
   width. Key anonymity or a claim that encryptions under different keys are identically
   distributed is not used. Every success or error is the same under the coupled tape.
2. P decodes the same `ProxyForward` and uses the same route; H opens the same sealed
   deposit, checks the same signature and updates the same queue. Their source branches
   are M [mt-postman/src/muq.rs:215-259,455-487][handlers] and [queue_host.rs:109-135][store].
   Neither path consults the physical owner of the receive capability. Pruning also reads
   identical state and time, M [mt-postman/src/server.rs:110-119][server].
3. The transport receives identical bytes, calls and active state. Applying the **same**
   causal F_env with the same tape therefore produces identical physical bytes, connection
   events, packetization, timings, retransmissions and errors, however byte-sensitive its
   serialization or timing may be. The resulting events leave active states identical for
   the next step. C and D contribute no events because their fixed state is disconnected.

Induction over the complete execution prefix gives `O_o(T0) = O_o(T1)` pointwise in this
coupling, up to the predetermined horizon, including unfinished operations. Consequently
`(x,z,L_o(T0))` and `(x,z,L_o(T1))` have the same **joint** distribution. This argument uses
identical full active inputs to F_env; it never replaces F_env by a function of lengths.
It is stronger than rowwise marginal equality for this pair and does not supply a simulator
from leakage for other pairs. Ciphertext collisions, if any, and all visible equalities are
preserved pointwise rather than declared impossible.

Here is the accounting against **every event row of section 4**, in its original order.
Zeros below are exclusions proved by the selected API caller, not values filled into open
phone or physical-transport rows. All nonzero rows share the single coupling above.

| Section 4 row | Joint contribution in these two worlds |
|---|---|
| 4.1 observer/units | Same fixed G+P projection, same named machines and links; no conversion of writes into packet counts. |
| 4.2 first-contact wake | No iOS process or `wakeRdv` call in P-MUQ-DEFERRED; no row instance in either world. |
| 4.2 continuing-letter wake | No `wake` call; no row instance in either world. |
| 4.2 live phone letter | No `sendLetter` call; no row instance in either world. |
| 4.2 direct-channel overlay write | No phone overlay writer; no row instance in either world. |
| 4.2 long-text blob | No wake/blob uploader; the payload is an API `HostDeposit.ct`, not that phone branch. |
| 4.2 media body | No `sealAndUpload`, media bucketing or media upload; no row instance. |
| 4.2 media manifest/accompaniment | No manifest, blob PUT/GET, cache lookup or mirror process; no row instance. |
| 4.2 send moments/retries/background | No phone delivery engine or its retry timers; the API caller's offered times, server prune activity, transport retries and errors are included through 4.3/4.5, identically coupled. |
| 4.2 following agent/phone F3 and backoff paragraphs | No agent/card/letter or phone backoff entry point; no instances. The 60-second horizon is not `MTPipe.window`. |
| 4.3 sender to entry proxy | Same ordered per-sender requests, including exact host address, sealed bytes, lengths, visible equality and endpoint metadata; same open/error/close traces and timestamps. Successful full application writes have `q+4528` bytes, but failures retain their actual prefixes. |
| 4.3 entry proxy to host | Same route, forwarded bytes, host-decoded send ID/message ID/nonce/signature/ciphertext, storage decisions and replies. Full application writes have `q+4492` bytes. The ignored-ACK behavior in section 2 below occurs identically. |
| 4.3 first use/collection/ACK/shard fan-out | Each caller reaching `connect` attempts its probe after configuration; a successful probe permits one deposit. No `node_hello`, registration, fetch, receive ACK or erasure call occurs in the horizon. Probe failures/closures are retained. Deposit response bytes belong to the two deposit rows, not a receive-ACK call. |
| 4.4 first link acquaintance | No reference-core handshake or node process. MUQ TLS handshakes are accounted under 4.3/4.5, not mistaken for this row. |
| 4.4 ordinary link message | No reference-wire link sealing; no row instance. |
| 4.4 body to `publish::cells_of` | No such constructor called; no row instance. |
| 4.4 node deposit of cells | No reference-core cell deposit; no row instance. |
| 4.4 collection from public point | No reference-core collection; no row instance. |
| 4.4 multi-hop cell carriage/slot | No reference-core carriage/slot call; MUQ forwarding is the separate 4.3 row. |
| 4.5 all-link/open boundaries | Same complete physical trace under the coupling, including handshakes, connection shutdown, ACK packets, retransmissions and timing. No notification service is invoked by the chosen APIs. Actual packet/record sizes are still unspecified, not zero. |

Thus this pair satisfies Definition C's four clauses for the stated pre-established API
experiment. The chair [checked the coupling and accepted it for intake][chair-review].
**The witness is non-empty but uninformative.** Equality holds because the changed secret
ownership has no causal path to any observed event in this horizon. It shows that Definition C
is satisfiable; it does not show that Montana provides any unlinkability. No mixing, padding
or cover contributes, and **this witness must not be cited as evidence of anonymity**. It does
not establish an online-delivery witness or a numerical anonymity claim. Extending the horizon
through collection, or observing provisioning, can expose that
ownership. That limitation is why SEQ/W-M and the broader implementation obligations stay open.
No code change is required for this restricted witness; no claim of nonexistence elsewhere in M
is made, so there is no justified "smallest code fix" to report as necessary.

## 2. MAP second: P-MUQ-DEFERRED only

### 2.1 Boundaries, branches and event ledger

Use the same named path and observer as section 1. The map applies to each instance, with actual
interleavings retained. Let q be the opaque ciphertext length and h = q+4487, as in 4.3.
Endpoint opcodes are visible to P/H; they are not declared visible as plaintext to G through TLS.
Rows describe observable classes and causality, not invented physical timestamps or packet counts.
"Open subrow" means section 4 names the obligation but has not supplied its transport law.

| Observable event or absence on this path | Section 4 destination and exact evidence at M |
|---|---|
| Client configuration failure before connection | 4.3 first use: `tls_connector().map_err(...)` then `open_stream` at [muq_client.rs:72-79][client]. No network call if configuration fails. |
| Probe TCP open/attempt and TLS handshake, including failures | 4.3 first use and 4.5 transport: `TcpStream::connect(addr)` and `connector.connect(sni,tcp)` at [muq_client.rs:33-47][client]. Server accepts TCP/TLS at [server.rs:120-134][server]. Physical packet/record law: **MAP-TLS/TCP open** below. |
| Probe ends without an application tag; server read can end in EOF/error | 4.3 first use: local `_probe` at [muq_client.rs:74-80][client]; server `read_fixed(...tag).await?` at [server.rs:146-147][server]. Wire shutdown representation: **MAP-CLOSE open**. No probe reply opcode is written by this branch. |
| Deposit connection attempt after successful `connect` and local payload construction | 4.3 sender to proxy: another `self.open().await?` at [muq_client.rs:97-98][client], through the same open path. A failed or unfinished open prevents application writes; physical handshake still belongs to the trace. |
| Sender writes proxy operation tag 0x12 and flushes | 4.3 sender to proxy: [muq_client.rs:99][client], constant at [muq.rs:38][handlers], `write_all` then `flush` at [wire.rs:28-35][wire]. |
| Sender writes BE outer length, host overlay, LE sealed length and sealed bytes, then flushes | 4.3 sender to proxy: [muq_client.rs:100][client], [mt-overlay/src/muq.rs:208-221][deposit], [wire.rs:47-58][wire]. Prefix is BE; inner sealed length is LE. After the tag, `send_frame` may fail the size guard or an individual write; a partial write is not a full request. |
| Proxy reads tag/frame; parse or route rejection produces ERR if the reply write succeeds | 4.3 sender to proxy: [server.rs:146-152][server], [wire.rs:61-71][wire], [muq.rs:243-259][handlers]. Tag/frame read failure propagates without an application reply from that handler; decode/no-route becomes an ERR reply. An awaited read may remain unfinished. |
| Proxy resolves H, opens a fresh TCP+TLS stream, writes host tag 0x11, length and unchanged sealed bytes | 4.3 proxy to host: [muq.rs:455-487][handlers], opcode at [muq.rs:37][handlers]. Its stream uses `tls_connector` with the same SNI rule. Route lookup is local, not another network query. Open/write errors map to proxy ERR at :250-252 if that reply can be written. |
| Host reads tag/frame, opens deposit, validates and stores or rejects; replies 0x01 or 0x00 | 4.3 proxy to host: [server.rs:146-152][server], [muq.rs:215-239][handlers], [queue_host.rs:109-135][store]. Frame read failure propagates with no application ACK from that handler; completed frame with open/decode/store failure selects ERR. Host metadata includes every decoded deposit field, not just q. |
| Proxy awaits one host reply byte, or read error/EOF; then returns success regardless of value/error | 4.3 proxy to host and sender to proxy: **MAP-ACK finding**, [muq.rs:481-487][handlers]. A pending read can still stall; this is not a timeout or proof that an ACK arrived. |
| Proxy writes its own ACK; sender reads it or encounters error/pending read | 4.3 sender to proxy: [muq.rs:248-258][handlers] and [muq_client.rs:101-103][client]. Sender checks its byte against 0x01. Proxy OK does not imply host OK. |
| Connection return/drop, early return, TLS alerts, TCP FIN/RST/ACK and retransmissions if emitted | 4.5 lifecycle/physical transport and open parts of both 4.3 deposit rows: function boundaries at [muq_client.rs:72-104][client], [muq.rs:465-487][handlers], [server.rs:129-134,139-153][server]. Exact lower-layer events and times: **MAP-CLOSE and MAP-TLS/TCP open**. Neither a Rust return nor a flush specifies one physical packet. |
| Server prune timer and contention can affect subsequent timing; no prune network write | 4.5 background timing: `tick.tick().await` and `prune_expired(current_window())` at [server.rs:110-119][server]; [queue_host.rs:220-225][prune]. The host's clock also affects stored expiry at [queue_host.rs:128-134][store]. These effects cannot be silently omitted from timing. |
| Receiver, directory, registration, fetch, receive-ACK, erasure, notification and reference-core traffic | No instances in this selected caller/horizon. `connect` and `deposit_via_proxy` bodies are [muq_client.rs:72-104][client]; the proxy/host dispatch branches are [muq.rs:159-175,215-259][handlers]. Other MUQ methods are separate calls, not automatic continuations. The server's MUQ branch returns before its Stage 1 routing loop, [server.rs:149-153][server]. |

The ledger covers application I/O branches of this caller and identifies the lower-layer
boundaries they enter. It does **not** enumerate an OS's individual packet events from source
writes. Every packet/record instance must retain link, direction, connection, event kind, time,
length, public fields and visible equality in 4.5 and section 5.1; an unknown one is not absent.

### 2.2 Findings and precisely what remains open

**MAP-ACK — response semantics, open implementation obligation.** At M
[mt-postman/src/muq.rs:486-487][handlers] the exact lines are
`let _ = read_fixed(&mut st, &mut ack).await;` and `Ok(())`.
After a successful forward write, either a host ERR byte or a completed failed ACK read still
leads to proxy OK at M [mt-postman/src/muq.rs:250-251][handlers]. This event belongs to the two
existing 4.3 deposit rows; it is not an unlisted third network leg. It invalidates interpreting
their one-byte replies as equivalent success certificates. The smallest local correction to
that response interpretation would propagate the read error and reject a non-OK host byte;
that is an **open obligation, not a fix made here**, and is not needed for the witness's
coupling. A hanging read is a distinct outcome and must remain in the trace. This finding
makes no claim that the whole application loses data; caller retries/recovery are outside P.

**MAP-TLS/TCP — open transport subrows.** Source entry points are at M
[muq_client.rs:37-47][client], [muq.rs:466-477][handlers] and
[server.rs:120-134][server]. Configured SNI, TLS version, certificate generation and client
configuration are at M [mt-postman/src/config.rs:14,28-60][config]. Section 4.3 mentions fresh
TCP/TLS connections and explicitly leaves handshake/record/packet sizes and elapsed times
open; 4.5 reserves the rest. TLS handshake public fields, record overhead, TCP headers,
connection allocation, ACKs, retransmission, segmentation, any library-generated TLS
post-handshake traffic and scheduler times need actual F_env entries. They are not derivable
from q+4528 or q+4492. Settle this with a pinned runtime,
transport dependency/configuration map and its observation law; field corroboration stays
with the chair. No TLS security premise is counted as Montana post-quantum protection.

**MAP-CLOSE — open lifecycle subrow.** The probe's `_probe` lifetime at M
[muq_client.rs:74-80][client] and the operation returns/drops at M
[server.rs:129-134,149-153][server] and [muq.rs:481-487][handlers] do not specify whether a
particular platform emits a TLS close alert, TCP FIN, reset, delayed ACK, or later packet.
Keep every emitted instance under 4.5 and Definition C's connection lifetime. Settle with
transport drop/error semantics and the same pinned F_env, not a guessed "one close packet".

**MAP-OPAQUE — complete view still open.** Section 4 retains metadata and equality but not
all opaque ciphertext bytes in L. Therefore a literal reconstruction of `O_o` from those
rows alone is not established, even after classifying all events. The exact source dependency
is `O_o = Observe_o(F_env(W_M, state, E))`; replacing W_M by L is SIM/PQ-KEY/PQ-SEAL/JOINT,
which this assignment does not discharge. Adding the whole ciphertext to leakage here merely
to obtain a tautological function would change Definition C and is not done.

There is no application-level network write on P-MUQ-DEFERRED left without a named section 4 row
or an explicitly open boundary above. The physical event-to-row schema is specified, but
its lower-layer instances/distributions and a view factorization through the rows remain
**open**. This separates a scoped source map from completed MAP. The C witness does not
assume that factorization: identical *full active inputs* suffice for its pointwise equality.

## 3. Critic self-review and remaining obligations

Critic self-review used two perspectives; it is not an independent external review.

- Cryptographic: no equality-of-encryption-distributions across different keys is assumed;
  no key, ciphertext, signature, hash or collision is replaced by ideal randomness. The
  challenge changes private recipient capability ownership, not the per-sender crypto inputs.
  No simulator, post-quantum reduction or numerical anonymity statement follows.
- Distributed state/transport: pre-horizon provisioning is unobserved by explicit setup,
  both recipients are disconnected by workload, horizon is fixed independently of success,
  all failed/pending prefixes and server pruning remain, and the ignored host ACK is included.
  The same argument would not cover an observer of earlier provisioning or later collection.
  A hypothetical online caller with an address-book lookup or peer-dependent discovery is not
  silently substituted for this API caller.

**OPEN:** C-NONEMPTY for observed establishment, online delivery and the shipped phone path;
MAP-TLS/TCP, MAP-CLOSE and MAP-OPAQUE even for this path; MAP for every other path;
MAP-ACK as an implementation obligation; SIM, PQ-KEY, PQ-SEAL, JOINT, SEQ and W-M exactly as
written in INTERSECTION-MODEL.md. WIN remains issue #4's separate integration dependency.

**Review boundary:** the chair checked the coupling at `ac4f436` lines 129–160 and confirmed
MAP-ACK. The section 4 accounting table (lines 166–187) and MAP ledger (lines 198–229) were
read, **not checked row by row**, and taken as written pending that check. Acceptance is for
intake through the core line; it is not a completed MAP proof or permission to merge PR #33
as it stands. These review claims refer to the [third-session verdict][chair-review].

**NEXT:** row-by-row review of the accounting table and MAP ledger, and the named transport
boundaries. A broader witness must keep the actual provisioning and collection traffic and
its correlations; no such extension is supplied by this review correction.
No runtime work, alternate primitive, code fix,
RELEASES.md edit or issue #4 proof edit is proposed as completed here.

-- Codex, model id not visible to the agent, agent on issue #5

Co-Authored-By: Codex (model id not visible to the agent) <noreply@openai.com>

[queue]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/muq.rs#L18-L115
[register]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/queue_host.rs#L82-L104
[queuekeys]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/muq.rs#L478-L491
[kemgen]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-crypto/src/lib.rs#L380-L404
[seal]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-crypto/src/lib.rs#L508-L521
[open]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-crypto/src/lib.rs#L526-L540
[deposit]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/muq.rs#L117-L241
[sign]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/muq.rs#L440-L455
[cap]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/frame.rs#L12-L15
[subscribe]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/queue_host.rs#L158-L182
[store]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/queue_host.rs#L109-L135
[handlers]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/muq.rs
[server]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/server.rs
[client]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/muq_client.rs
[wire]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/wire.rs
[prune]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-overlay/src/queue_host.rs#L220-L225
[config]: https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/core/Code/crates/mt-postman/src/config.rs

[chair-review]: https://github.com/efir369999/montana_messenger/issues/5#issuecomment-6401464305
