# Montana: an ecosystem of time on a post-quantum core

*Whitepaper of the Montana Time ecosystem. The protocol is defined by the normative set in [`core/docs`](core/docs); where
this paper and the set differ, the set governs. Section references in square brackets point into that set.*

## Abstract

Montana is a protocol in which a person is a secret held on a device, value moves as shielded notes, and the order of
events is a chain of cemented windows that no clock and no majority can rewrite. Every primitive is post-quantum:
ML-DSA-65 signs, ML-KEM-768 agrees keys, SHA-256 and SHA-3 hash, ChaCha20-Poly1305 seals. On this core stands an
ecosystem of applications for iPhone, iPad, Mac and Android — a messenger, a wallet of the coins of time, a Bluetooth
mesh, direct phone-to-phone delivery, a VPN client and a messenger for companies — which share one 24-word identity and
one core library. This paper states what the protocol is, what each application implements of it, and where a reviewer
finds the code, the vectors and the open items.

## 1. Stance

Four properties are fixed before any mechanism is weighed, and a mechanism incompatible with one of them is rejected
first [Constitution, What a global invariant is].

- **Post-quantum only.** The admitted primitives are SHA-256, ML-DSA [2], ML-KEM [1], hash-based zero knowledge and
  lattice commitments; ECDLP, RSA, classical Diffie-Hellman, elliptic-curve commitments, Schnorr and EdDSA are excluded
  [Constitution, I-1].
- **Privacy of value is absolute.** A payment publishes exactly four kinds of quantity: the nullifiers of what it
  consumes, the commitments of what it creates, a rate nullifier, and a proof that value is conserved; state carries no
  balance, amount, payer or payee [Constitution, I-2].
- **A person has no identifier.** Everything of a person derives from one seed on their device, and nothing that means
  "this person" exists in state, on the wire or in any document [Identity, A person is a secret].
- **No fee exists as a protocol notion.** An application pays and charges nothing at the protocol level; scarcity is
  enforced by time [App, The economics of an application].

## 2. The TimeChain

The TimeChain is the sequence of cemented windows [Consensus, The TimeChain]. A window is a run of consecutive rounds on
each of its parallel chains and leaves one proposal: the height, the identifier of the previous proposal, the roots of
state and the proof that all of it holds. The link from one window to the next is that identifier alone — no timestamp,
no sequence number of anyone's making, no signature of an authority.

A window advances when the cement of its predecessor, accumulated by the rounds, reaches the quorum share; at that moment
the predecessor is final and the next window opens. Nothing else closes a window: no count of rounds, no duration, no
clock. Two proposals of one height are separated by which proof verifies, never by length or by the number of machines
holding them. A network that cannot reach the quorum waits rather than falling back to a timeout or a reduced quorum, so
a partition does not become two chains [Consensus, The TimeChain].

The pace of the chain is a theorem rather than a number: the length of a window is the count of rounds at which the
standing no round has touched falls to the complement of the quorum, and the floor under a round is the echo of the
population across its geography [Consensus, The pulse and the close of a window; Canon]. Machines enter the set that runs
windows through admission, and each window issues an equal right to its share to every machine its cement names
[Consensus, Presence and admission; The right to a window's share].

## 3. Value

A note is three fields — an amount, the payment key of its owner and a blinding factor — none of which is published; the
chain holds a commitment to all three [Value, The note]. The nullifier that extinguishes a note is derived from the
redemption branch of the owner's secret, the commitment and the position of the leaf in the append-only tree, never from
randomness chosen by a sender, so two notes identical in every field still carry distinct nullifiers [Value, Redemption is
derived from position]. Every spend has one fixed shape; an unused position carries a note of zero value, so a payment of
one input is indistinguishable from a payment of two [Constitution, I-2; Value, The shape of a frame]. Emission creates a right rather than a note, and
a right is redeemed inside a payment that nothing distinguishes from any other [Constitution, I-2 (4); Value, Extinguishing
a right]. The one disclosure primitive is a proof of a single payment, produced by its owner [Constitution, I-2 (3);
Value, Disclosure].

## 4. Identity

A seed is drawn once from the cryptographic source of the device and tested before it becomes anyone; a source that
fails the tests is refused, not warned about [Identity, The birth of a seed]. A person sees twenty-four words from the
Montana word list and holds the seed those words stand for; the derivation reads the seed, not the text, and four letters
name a word. There is one secret and no second: Montana adds no passphrase. From the seed come independent branches — the
one that signs (ML-DSA-65), the one that proves ownership of value, the one that derives redemption and the one a
person's stored content is sealed to — and a leak of one discloses nothing of another [Identity, A person is a secret;
Canon].

Two people bind a handshake to a key by comparing, once and out of band, the fingerprint of the identity key [Identity,
Scope; Network, Where a shared secret comes from].

## 5. Network

Two devices that have never spoken agree on a secret by a post-quantum key agreement: each sends an ML-KEM-768
encapsulation to the other, the two results are folded with the transcript into a master secret, and two directional keys
are derived from it [Network, Where a shared secret comes from]. Each side signs the transcript with its ML-DSA-65 identity
key; the identity keys travel inside the encapsulation and never in the open; a handshake whose signature does not verify is
abandoned in silence. There is no elliptic curve on the path.

Delivery has no address and no map of the network. A sender and a recipient share a pipe identified by a tag; the holder
of a tag is chosen by rule rather than by a directory; what crosses the wire is cells of one width, so a beacon, a frame
and a letter are one shape to an observer [Network, There is no address; Which machine holds a tag; The cell]. Near
transports carry delivery between devices that are close to one another [Network, Scope; The path].

## 6. Applications

An application publishes into the chain exactly one thing, a hash — an anchor; what stands behind it lives with its owner,
sealed to the encryption branch of that owner's seed [App, The anchor]. An application identifier never reaches the wire,
because an identifier attached to a public action would sort people by the applications they use [App, The identifier of
an application]. A client states to a person what it does with their data and when, and its build is reproducible [App,
Scope].

## 7. The ecosystem

Every application below opens or creates a person from the same 24 words and links the same client core
([`core/Code`](core/Code)) through its C interface; nothing cryptographic is reimplemented in an application.

| Application | Platforms | What it does | Source |
|---|---|---|---|
| Montana (Messenger) | iPhone, iPad, Mac; Android | Letters, media, voice messages, voice and video calls. A letter is sealed end to end; it travels directly between two phones when they reach each other and otherwise through nodes that forward sealed envelopes and hold no key. Call media is sealed by SFrame [7] under a key derived from a call seed carried inside the sealed envelope. | `apps/messenger/ios`, `apps/messenger/android` |
| MT Wallet | iPhone, iPad, Mac | Opens a machine of the reference implementation on the phone, which reaches the machines of the genesis cohort by the handshake of §5 and reads the wallet state the core holds. Beside it, the coins of time: each source of coins keeps its own time chain on the phone, one link per move, each link sealed by SHA-256 over the link and the seal before it. | `apps/wallet/ios` |
| MT Mesh | iPhone, iPad, Mac | Rooms carried over Bluetooth Low Energy between phones that are near one another. | `apps/mesh/ios` |
| MT P2P | iPhone, iPad, Mac | The phone as its own node: it learns its outward address, keeps its own door open and delivers straight to another phone. | `apps/p2p/ios` |
| MT VPN | iPhone, iPad, Mac | A VPN client with a packet tunnel, reading the common subscription and link formats; a person may place their own VPN on their wall for the people they write to. | `apps/vpn/ios` |
| MT Business | iPhone, iPad, Mac | The messenger for a company: departments, offices, channels, administration, shifts and supply; sign-in by a phone number or an e-mail address confirmed by a service that signs the confirmation with ML-DSA-65, or by the 24 words. | [montana_business](https://github.com/efir369999/montana_business) |

The public sites serve the applications and hold nothing about a person: montana.quest (the Messenger, its privacy
policy, and the card and name links that open the application through the associated domain), montana.xxx (the store of
the applications and the home of MT Business), efir.org (a mirror) and pronoia.my (MT VPN).

## 8. Implementation

| Purpose | Primitive | Standard | Where |
|---|---|---|---|
| Signatures | ML-DSA-65 | FIPS 204 [2] | `libcrux-ml-dsa` in `core/Montana-Core`; OpenSSL 3.5 built from source in `core/Code` |
| Key encapsulation | ML-KEM-768 | FIPS 203 [1] | `libcrux-ml-kem` in `core/Montana-Core`; OpenSSL 3.5 in `core/Code` |
| Hashing | SHA-256, SHA-3 | FIPS 180-4 [3], FIPS 202 [4] | RustCrypto `sha2`, `sha3` |
| Authenticated encryption | ChaCha20-Poly1305 | RFC 8439 [5] | RustCrypto `chacha20poly1305` |
| Transport of the client core | Noise XX pattern [6] with ML-KEM-768 and ML-DSA-65 | | `core/Code/crates/mt-noise-pq` |

`core/Montana-Core` is the reference implementation of the set: its build parses every value of the Genesis Decree, every
domain separator and the frozen vectors of the hash primitive and the trees out of the documents and fails on any
divergence ([`core/Montana-Core/README.md`](core/Montana-Core/README.md)). `core/Code` is the client core the
applications link; it carries the NIST known-answer tests of its primitives and records in its `VERSION.md` the
specification generation it was written against. Where `core/Code` and the set differ, the set governs.

**What is open.** The set names one open item at its front: the constraint set of the two circuits, which it binds by hash,
with the statements the circuits must assert, the format of their description and the verifier fixed in Canon
([`core/docs/README.md`](core/docs/README.md)). What the green build does not hold is listed, with what closes each item,
in [`core/Montana-Core/AUDIT.md`](core/Montana-Core/AUDIT.md) and [`core/Code/docs/SPEC_DEVIATIONS.md`](core/Code/docs/SPEC_DEVIATIONS.md).

## 9. Reviewing

The frozen vectors in Canon are the first thing to run against: an implementation that reproduces them has the hash layer
right [core/docs/README.md]. Each document of the set closes with a conformance set listing what an independent
implementation must reproduce to be the same network [Constitution, The document set]. The applications are built from
their folders in this repository; the binaries released beside the source are the exports uploaded to the App Store and
the Android package, so a reader can compare a build with its tree.

Findings go to the issues of this repository; a weakness that should not be public goes by e-mail as
[`SECURITY.md`](SECURITY.md) describes.

## References

1. NIST, FIPS 203: Module-Lattice-Based Key-Encapsulation Mechanism Standard, 2024.
2. NIST, FIPS 204: Module-Lattice-Based Digital Signature Standard, 2024.
3. NIST, FIPS 180-4: Secure Hash Standard, 2015.
4. NIST, FIPS 202: SHA-3 Standard, 2015.
5. Y. Nir, A. Langley, RFC 8439: ChaCha20 and Poly1305 for IETF Protocols, 2018.
6. T. Perrin, The Noise Protocol Framework, revision 34, 2018.
7. E. Omara, J. Uberti, S. G. Murillo, R. Barnes, Y. Fablet, RFC 9605: Secure Frame (SFrame), 2024.
