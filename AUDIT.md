# Audit package

Refs #15: author decision 233 is recorded in the partial K0d node-lock proposal in
[ADMISSION-LEVEL1-K0.md](core/Montana-Core/protocol-13/ADMISSION-LEVEL1-K0.md). The amount,
continuity-plus-lock gate and burn rule are decided. Anonymous evidence-to-lock binding,
revocation, release/slash layouts, complete continuity and circuit costs
remain open; no implementation or acceptance is claimed.

Current protocol closure is tracked separately in [Audit/Protocol-13](Audit/Protocol-13/README.md).
As of 2026-10-14, all 13 acceptance criteria remain open. Those reports distinguish the published
snapshot from candidate repairs and do not convert the historical findings below into closure.

For the proposed third-party review in issue #2, the [commissioning package](doc/external-audit/README.md)
adds a source-pinned assessment, executable premise checks and a lab/funding decision record.
It is preparation, not an independent audit or closure of the findings below.

This file is the entry point for an external audit of this repository. It states what is in scope, which bytes are under
audit and how to pin them, how to build and test each part, where the vectors are, what can and cannot be verified from
this repository, and the open findings known to the project, each with its place in the code. It claims no test run: what a
run yields is what the run says.

## 1. Scope

In scope:

| Folder | What it is |
|---|---|
| `core/docs` | The normative specification set (Constitution, Canon, Consensus, Value, Identity, Network, App, Registry) |
| `core/Montana-Core` | The reference implementation of the set (Rust workspace): primitives, encodings, trees, derivations, the wire, the pulse, the proof, a node and a terminal wallet |
| `core/Code` | The client core the applications link (Rust workspace): keys from the words, signatures and key encapsulation, the post-quantum handshake, sealed letters, names, delivery, and an earlier consensus line |
| `apps/messenger/ios` | Montana for iPhone, iPad and Mac (Swift), with its notification, share and packet-tunnel extensions |
| `apps/messenger/android` | Montana for Android (Kotlin) and its JNI library `native/montana-jni` over the client core |

Outside this repository, and therefore outside what can be audited here:

- the services of the Montana nodes: delivery boxes, the plane of names, wake-up, diagnostics and the coin transfer log
  (F-4);
- the project's private history, signing material and deployment (section 3);
- third-party engines fetched at build time: WebRTC (iOS: a binary framework; Android: an archive pinned by digest),
  Xray-core (Go modules pinned by `go.sum`), hev-socks5-tunnel (cloned), OpenSSL (built from source by `openssl-src`).

## 2. Which bytes are under audit

Every folder is a snapshot of one commit of a private repository, without its history. The table Sources of
[`RELEASES.md`](RELEASES.md) names, for each folder, the build, the source commit and the git tree of the folder. The
publisher writes that table in the commit that changes the folder, and the tree it writes is the tree of that commit:

```
git rev-parse HEAD:core
git rev-parse HEAD:apps/messenger/ios
git rev-parse HEAD:apps/messenger/android
```

answer the hashes of the column Folder tree. A finding pinned to a tree hash stays meaningful after later publications.

The line numbers in this file refer to these trees: `core` at source commit `3848245e308b`; `apps/messenger/ios` at build
2191, source commit `c7e7dd0e60fe`; `apps/messenger/android` at build 411, source commit `07e5f3cde2e0`. Every finding also
names the function or symbol, so that it can be found in a later tree.

## 3. What can be verified from this repository, and what cannot

Can be verified:

- the exact bytes under audit, by the tree hashes of section 2, recomputed by any clone;
- that the published trees build and that their tests pass, by the commands of section 4;
- that the primitives agree with the NIST vectors and with a second implementation, by the tests of section 5;
- every statement of this file about the code, by the file and line it names.

Cannot be verified:

- That a published binary was built from a published tree. No reproducible build of the applications is published and no
  comparison of a rebuilt binary with a released one has been made. The iOS IPA is an App Store export, signed for
  distribution. The Android build aims at one APK per commit (`apps/messenger/android/scripts/build.py`, lines 171 and
  204-206), but its native library is built from a core commit that is not the commit of `core/` (F-12).
- That `core/` is the core the binaries link. It is not, byte for byte: `core/` is an English translation of the project's
  core line in which comments, documents and the text of messages were translated, and the applications link builds of
  other commits of that line (F-12).
- The private history. The source commits named in `RELEASES.md` point into private repositories; the folders carry no
  history and the commit messages are not published. The history is kept private because it carries signing material and
  identifiers of the project's accounts, the addresses of the project's machines and the names of people, in files and in
  commit messages; each snapshot is stripped of these before it is published. The consequence is the one stated by a critic of
  this repository: the history of review cannot be checked here. `core/Montana-Core/AUDIT.md` (lines 1790-1797) places the
  reasons of one stage in commit messages that are not published, and the earlier external reviews of the core are held in
  the private history.
- What the nodes do. The clients' side of every exchange with a node is in this repository; the node's side is not (F-4).

## 4. How to build each part

Core (each workspace pins its Rust compiler in `rust-toolchain.toml`; `core/Code` builds OpenSSL from source and needs a C
compiler and Perl):

```
cargo test --workspace --release --manifest-path core/Montana-Core/Cargo.toml
cargo test --workspace --release --manifest-path core/Code/Cargo.toml
```

Two tests depend on the machine: the differential test of `core/Montana-Core/crates/mt-suite/tests/differential.rs` compares
with the `openssl` command of the machine and fails when that command does not carry ML-DSA-65 and ML-KEM-768 (OpenSSL 3.5 or
later); the proof of a window takes about nineteen minutes in the debug profile on the project's machine
(`core/Montana-Core/AUDIT.md`, line 1763), less in release.

Montana for iPhone, iPad and Mac, and Montana for Android: the steps are in [`README.md`](README.md), section Build from
source. The iOS steps build the two core frameworks from `core/`, fetch the call engine, build the two VPN engines and compile
the project with signing off. On Android, `python3 scripts/build.py --check` compiles resources and Kotlin from this
repository alone; the full build needs the core at the commit pinned in `scripts/toolchain.json` (F-12).

## 5. Vectors, fixtures and earlier audit documents

| What | Where |
|---|---|
| Frozen vectors of the set (hash layer, trees, derivations) | `core/docs/Montana Canon.md`; compared on every build by `core/Montana-Core/crates/mt-conformance` |
| NIST ACVP vectors, reference implementation | `core/Montana-Core/crates/mt-suite/tests/fixtures/` (`mldsa65_acvp.txt`, `mlkem768_acvp.txt`, `chacha20poly1305_rfc8439.txt`) |
| NIST ACVP vectors, client core | `core/Code/crates/mt-crypto-native/tests/fixtures/nist_acvp/`, `tests/nist_acvp_kat.rs` |
| Second implementation of the primitives | `core/Montana-Core/crates/mt-suite/tests/differential.rs` (against the `openssl` command); `core/Code/crates/mt-bindings/tests/wasm_backend_kat.rs` (OpenSSL against RustCrypto) |
| Protocol vectors of the client core | `core/Code/crates/mt-noise-pq/tests/kat.rs`; `mt-mnemonic/tests/keygen_vectors.rs`, `test_vectors.rs`; `mt-names/tests/vectors.rs` with `fixtures/name_vectors.json`; `mt-net/tests/test_vectors.rs`; `mt-bindings/tests/kat_cross_client.rs`, `kat_overlay.rs` |
| Conformance of the client core | the machine-readable contract in `core/Code/conformance/`, `core/Code/crates/mt-conformance`, `core/Code/docs/CONFORMANCE.md` |
| Application tests | iOS `Code/MontanaTests/MontanaTests.swift`; Android `native/montana-jni/src/lib.rs` (each JNI door against the iOS door of `mt-bindings`) |
| Earlier audit documents | `core/Montana-Core/AUDIT.md`, `core/Code/AUDIT.md`, `core/Code/docs/audit-checklist.md`, `core/Code/docs/SPEC_DEVIATIONS.md`, `core/Code/docs/security-cards.md`, `apps/messenger/ios/docs/call-security-card.md` |

## 6. Open findings

Each finding names where it is, what it is, why it matters and its state. None is closed by this file.

### F-1. The channel handshake sends identities in the clear and, as the applications use it, authenticates neither side

Where: `core/Code/crates/mt-noise-pq/src/xx_handshake.rs`, `responder_send_msg2` lines 205-209 (the responder's ML-DSA-65
key, line 208) and `initiator_send_msg3` lines 315-318 (the initiator's key, line 317); `core/Code/crates/mt-noise-pq/src/lib.rs`,
lines 364-366 and 290-291 (the same in the variant the applications use); `core/Code/crates/mt-bindings/src/ffi_noise.rs`,
`node_id_from_seed` lines 22-26; iOS `Code/Montana/MontanaDirect.swift`, `initiatorHandshake` lines 975-986 and
`acceptInbound` line 1614; Android `Channel.kt`, `dial` lines 202-205 and `respond` lines 232-235.

What: both handshakes put the ML-DSA-65 public keys of both sides on the wire unencrypted; the whitepaper said the opposite
and is corrected. The applications use the variant of `lib.rs`, in which the initiator encapsulates to the responder's static
ML-KEM-768 key. They read that key from the first frame of the connection and compare it with nothing, and both sides sign
with an ML-DSA-65 key drawn at random for that one handshake. The registration that follows binds a device key to the channel
(`Channel.kt`, `registerInit` and `signable`, lines 284-311), but no side holds an expected key of the other. The comments of
the applications and of `ffi_noise.rs` call this handshake XX; it is the XK-like variant of `lib.rs`.

Why it matters: an active party on the path can terminate both sides of a channel on a bare port. Letter bodies stay sealed
end to end (F-3), so what such a party gains is the channel's metadata: which tags a device registers and reads, and when.
Inside TLS (port 443 and the web-socket door) the host certificate authenticates the name of the node, classically.

State: open. Encrypting the identities and pinning the keys of the nodes change the wire protocol.

### F-2. The asynchronous key agreement of the library stands on encapsulations alone and cannot check a signed prekey

Where: `core/Code/crates/mt-messenger-e2e/src/handshake.rs`, `RecipientBundle` lines 37-43, `build_handshake` lines 104-105
and 140, the initiator's account key at line 145.

What: the root of a session is derived from the encapsulations to the recipient's keys (`ss_id`, `ss_spk`, `ss_opk`) and the
transcript; the initiator's ephemeral key enters the session only through the recipient's reply in the ratchet, not the root.
The bundle type carries no signature over the signed prekey, so the library cannot verify one. The initiator's ML-DSA-65
account key travels in the handshake bytes.

Why it matters: the set calls a secret derived from one side's material alone a defect
(`core/docs/Montana Network.md`, line 54), and without a verifiable signature over the prekey whoever serves bundles can
substitute one.

Reachability: neither application calls these functions. iOS has no caller of `mt_e2e_build_handshake` or
`mt_e2e_process_handshake` (the wrappers left in `Code/Montana/MontanaPQ.swift` are the session's encrypt and decrypt, and
those have no caller either). The Android library does not link `mt-bindings` (`native/montana-jni/Cargo.toml`, lines 12-15
and 30-31), and `MtBindings.kt` declares no handshake door. The web target exposes them (`core/Code/crates/mt-bindings/src/ffi_wasm.rs`).

State: open, in the library.

### F-3. A letter's key does not ratchet

Where: iOS `Code/Montana/MTPipe.swift`, `windowSeconds` and `window` lines 31-38, `bodyKey` and `sealBody` lines 56-72;
`Code/Montana/MTNodeWire.swift`, `bodyKey` lines 41-46; Android `Pipes.kt`, lines 30-31.

What: a letter body is sealed with ChaCha20-Poly1305 (the core's `mt_e2e_seal_blob`) under SHA-256("mt-pipe-key" ‖ 0 ‖
conversation secret ‖ minute), the minute read from the device's clock. The conversation secret is set at first contact and
the code read does not replace it. The core's KEM ratchet (`core/Code/crates/mt-messenger-e2e/src/session.rs`, lines
296-343) is wrapped in `MontanaPQ.swift` (lines 55-65) and called by neither application.

Why it matters: there is no forward secrecy and no recovery after a compromise. Whoever obtains a conversation secret from a
device, or from a copy of its storage, opens every past and future letter of that conversation that they hold or later
capture.

State: open.

### F-4. The node services are not in this repository; the coin transfer log checked the form of a record, not its signature

Where: the services run on the project's nodes; their source is not published. The clients' side is in this repository: iOS
`Code/Montana/MTWalletCore.swift`, `MTCoinTx` from line 3058, the reader's verification at line 3157.

What: delivery boxes, names, wake-up, diagnostics and the coin transfer log are services of the nodes, whose code an auditor
of this repository cannot read. The project's own audit of the coin transfer service found that the service checks the form
of a transfer record and not its ML-DSA-65 signature, and that the rule which takes a version-2 record only on top of the head
of its key's chain therefore lets a record carrying another person's key, with a signature that does not verify, become that
chain's head. Readers verify the signature before they credit a record (line 3157), so such a record moves no coin; it
blocks the owner's next transfer, which no longer stands on the head.

State: the signature part is closed on both transfer nodes since 2026-10-11 20:5x UTC: the service verifies the ML-DSA-65
signature of every record with the core's own verifier (the `mt_verify` function of `core/Code/crates/mt-bindings`, the
function the phone links), after a self-test of that verifier at start, refuses a record whose signature does not verify
(400), takes no record at all when the verifier is absent (503), and never makes an unverified record a head; the phone in
turn builds only on a head it has read back and verified as a record of its own key (from build 2192). Open: the source of the
node services is still not in this repository.

### F-5. One machine holds the quorum weight of the earlier consensus line

Where: `core/Code/docs/SPEC_DEVIATIONS.md`, DEV-012, lines 220-245; line 680; line 679.

What: the weight of a confirmation is the confirmer's `chain_length` (line 225). The register's operational note records
that one machine holds `chain_length = 25 766` and each of the others at most 1, so that machine's confirmation alone meets
the 67 % quorum (line 243). The register is inconsistent about DEV-012: partially closed at line 230, closed at line 680. The
same line of implementation selects a fallback proposer by elapsed wall-clock time (DEV-023, line 679, 120 seconds), while the
set replaces a stalled runner without a timeout, "because a timeout is a clock" (`core/docs/Montana Consensus.md`, lines
453-454); where `core/Code` and `core/docs` differ, the set governs.

Why it matters: while the weight is so concentrated, the property that no majority can rewrite the chain reduces to the
honesty of the operator of that machine. No later figure in this repository replaces the note of line 243.

State: open.

### F-6. Call media is protected by DTLS-SRTP alone

Where: iOS `Code/Montana/MontanaCall.swift`, `myCaps` lines 933-939, `maybeEnableSframe` lines 1679-1687, the summary of a
call at line 3172; Android `CallLine.kt`, lines 397-402, and `Calls.kt`, line 128.

What: a frame layer (SFrame, AES-GCM, under a key derived by the core from a call seed carried in a sealed letter) is written
in the iOS code and switched off: it was turned off after enabling proved one-sided, and while it is off the confidentiality of
call media rests on DTLS-SRTP, whose key exchange is classical. Android has no frame layer. The project's diagnostic journals
of the deployed builds, read in October 2026, hold 81 call summaries; every one names the protection `dtls-srtp`, none
`dtls-srtp+sframe-pq`.

Why it matters: call media is not protected against a quantum adversary recording traffic now, and the protection rests on a
classical primitive the project otherwise admits only as transport admission.

State: open. Enabling the frame layer is a change of live call behaviour, accepted on two devices.

### F-7. Three implementations of ML-DSA-65 and ML-KEM-768, two of them before version 1.0

Where: `core/Montana-Core/Cargo.toml`, lines 32-33 (`libcrux-ml-dsa`, `libcrux-ml-kem`); `core/Code/crates/mt-crypto-native/Cargo.toml`,
line 18 (OpenSSL through `openssl-src`); `core/Code/crates/mt-bindings/Cargo.toml`, lines 35-39 and 53-54, and
`core/Code/crates/mt-messenger-e2e/Cargo.toml`, lines 21-23 (RustCrypto `ml-dsa` and `ml-kem`, for the web target and as a test
oracle).

What: the applications link OpenSSL through `core/Code`; iOS also links a framework of `core/Montana-Core` (libcrux). Each
implementation passes the NIST vectors, and two differential tests compare libcrux with the `openssl` command and OpenSSL with
RustCrypto (section 5). No vector compares the protocol computations (seed to keys, handshakes,
domain separators) across the two workspaces, which implement different generations of the specification
(`core/Code/VERSION.md`). The libcrux and RustCrypto crates are pinned below version 1.0, and
`core/Code/docs/audit-checklist.md` (line 71) states that no pre-1.0 dependency stands in the consensus path; that holds for
`core/Code`, not for `core/Montana-Core`.

State: open.

### F-8. The value layer of the set is not reachable end to end

Where: `core/Montana-Core/AUDIT.md`, lines 96-105, 236-241, 243-249 and 1763.

What: a wallet of the reference implementation answers `this wallet holds no note to pay from`: the first value of the
network cannot be created, because a right is redeemed inside a frame and a frame needs notes only a redeemed right creates.
The proof of a window binds every cell of its public input and takes about nineteen minutes in the debug profile.

Why it matters: the shielded notes the whitepaper describes are specified and partly implemented, and carry no value in any
deployed application (section 7).

State: open.

### F-9. The applications compute cryptography outside the core

Where: iOS `Code/Montana/E2ECore.swift` (the local vault, ChaCha20-Poly1305 under a device key, lines 163-174; the key handed
to a new device, HKDF and ChaCha20-Poly1305 around an ML-KEM-768 encapsulation, lines 87-97); `Code/Montana/MTGroupRoom.swift`,
lines 112-134 (AES-GCM under SHA-256 of an encapsulated secret); `Code/Montana/MontanaBackup.swift` (ChaCha20-Poly1305 frames
under HKDF, lines 32 and 287); `Code/Montana/MTPipe.swift` and `MTNodeWire.swift` (the derivations of the pipe); Android
`Pipes.kt`, lines 23-31, `Backup.kt`, `Identity.kt` (AES-GCM), `HomeNode.kt`.

What: the platforms' own cryptography (CryptoKit, `javax.crypto`) implements symmetric sealing, key derivation and hashing in
both applications, and the derivations of delivery are written in Swift and in Kotlin. AES-GCM is not among the primitives the
set admits.

Why it matters: the statement that applications reimplement nothing cryptographic was false and is withdrawn; these
computations need their own review and their own cross-platform vectors.

State: open.

### F-10. The safety number is derived from the conversation secret

Where: iOS `Code/Montana/MTPipe.swift`, lines 114-138; Android `PeerInfo.kt`, lines 136-149.

What: the number two people compare is 5200 rounds of SHA-256 over the conversation secret; the set derives it from an
identity key. A replaced conversation secret changes the number on both sides, so the comparison still detects a party in the
middle of the first contact; it does not bind a person's key.

State: open, a deviation from the set.

### F-11. The iOS build fetches third-party code without pinning it

Where: `apps/messenger/ios/fetch-webrtc.sh`, lines 9-12 (a binary framework downloaded with no digest check);
`scripts/xray-ios/build-xray-xcframework.sh`, lines 18-19 (`gomobile` and `gobind` at `@latest`);
`scripts/hev-ios/build-hev-xcframework.sh`, line 14 (the tunnel cloned at its newest commit) and line 10 (the output lands
beside `Code/`, the project links `Code/Frameworks/`); the Xcode release is not pinned.

Why it matters: two builds of one tree may link different third-party code, and a substituted download is not detected. The
Android build pins every download by digest (`scripts/toolchain.json`).

State: open.

### F-12. A binary's core is not recorded against this repository

Where: Android `scripts/toolchain.json`, lines 42-45, and `scripts/build.py`, `core`, lines 84-93; iOS `scripts/build-core.sh`
and `scripts/build-protocol-core.sh`, line 6 of each; `core/`.

What: the Android build builds its native library only from a git checkout of the core at commit `ae36d1f927a7`, beside the
Android tree, and refuses any other commit or an uncommitted change. That commit is five commits before the source commit of
`core/` (`3848245e308b`): two commits of code, the translation, the bridge the phones link and a formatting commit. The iOS build
takes its two core frameworks from a path outside the tree and keeps them out of git; nothing in the iOS tree records the
commit they were built from. `core/` itself is the English translation of the core line: comments, documents and the text of
messages differ from the line the binaries were built from.

Why it matters: an auditor reads a core that is close to, and not exactly, the core inside the released binaries, and cannot
rebuild the Android native library from this repository.

State: open.

### F-13. Panicking calls in library code

Where: `core/Code/crates/mt-messenger-e2e/src/handshake.rs`, lines 224, 226 and 253 (`unwrap` after a length check);
`core/Code/crates/mt-messenger-e2e/src/ratchet.rs`, line 55 (`expect`).

What: the project's code rules exclude `unwrap` and `expect` from library code; these sites are guarded by the lengths
checked before them, and a panic there aborts the calling process.

State: open, low.

### F-14. Letters and frames are not cells of one width

Where: the set, `core/docs/Montana Network.md`, line 157 ("Everything on the wire is a cell of one size and one type");
`core/Code/crates/mt-messenger-e2e/src/media.rs`, `seal_blob` lines 40-48 (no padding; `pad_len`, lines 28-38, is applied
by callers to media only, iOS `Code/Montana/MontanaMediaKit.swift`, line 162); iOS `Code/Montana/MTPipe.swift`, `sealBody`
lines 70-72, and `Code/Montana/MontanaDirect.swift`, `seal` lines 1929-1934; Android `Pipes.kt`, `seal` lines 78-80, and
`Channel.kt`, `NetMsg` and `OverlayFrame` lines 64-99.

What: a letter body is sealed at its own length and carried in length-prefixed frames of variable size; the sealing of letters
and of channel frames uses the associated data of media (`mt-media`).

Why it matters: the length of a letter, and therefore its kind (a receipt, a word of typing, a text, a piece of media), is
visible to the nodes and to the path, which the set's single cell is designed to deny.

State: open.

## 7. Coin TimeChain

Two different things carry the word coin, and an audit must keep them apart.

The value layer of the set. `core/docs/Montana Value.md` specifies shielded notes, nullifiers and proofs; `core/Montana-Core`
implements them in part and cannot yet create the first value (F-8). No deployed application holds such a note.

The coins of time of the applications, version 2. Montana for iOS keeps, for each seed, a book of coins on the device; coins
are minted into that book by the application's rules (`Code/Montana/MTWalletCore.swift`: `MTChatMint` from line 171,
`MTVPNWallMint` from line 1369, `MTCallMint` from line 1450; the book, `MTLocalCoinLedger` from line 2232), and the book is laid
on the nodes in pieces sealed by the seed, so that another device of the same words reads it back. A transfer is one record
of 5362 bytes: magic `MTTX`, version 2, amount, the sender's time, a nonce, a tag of the pair derived from the conversation
secret, the identifier of the previous record of the same coin key, the sender's ML-DSA-65 key and its signature
(`MTCoinTx`, from line 3058). The records of one key form a chain on one of two nodes, chosen by the first byte of the
hash of the key (`chainNodes`, line 3068); that node takes a record only on top of the head it holds, so of two records on one
predecessor one is refused. A receiver credits a record only after verifying its signature with the core (line 3157) and
only as read from the chain's node.

What version 2 does not close, as the project states it: the node checks no balance, because coins are minted in the seeds'
books by the application's rules and no supply is proven; a chain's node that is down stops that key's transfers; a node that
loses its disk loses the records of its keys. Added here: until 2026-10-11 the node did not verify the signature of a record (F-4, closed), and the
node's code is not in this repository. Montana for Android at build 411 carries no transfer records.

Version 3 (Montana for iOS from build 2193; the nodes since 2026-10-11 21:2x UTC; the specification of the record and of the
node's rules is `Audit/COIN-TX-V3.md` of the iOS project and is summarised here). Every move of a coin key's balance is a
signed record of that key's chain: GENESIS (announces the book a phone held before version 3, once per key, before the cut of
version 2, at most what time could have minted since 2026-09-01), MINT (an interval of the node's seconds, at most
2 x min(13, max(1, bit_length(s) - 1)) coins for the s-th second of the key's life, intervals of one key never overlapping),
SEND (names the declared part of its amount -- proven is spent first -- and commits to the receiver's coin key as
SHA-256("mt-coin-to", receiver, blind), the blind an HMAC under the pair's secret over the record's nonce), RECV (the receiver
opens the commitment; one RECV or one REFUND per SEND, decided by the SEND's chain node) and REFUND (the sender takes back a SEND
no one took within a day). A key's balance is the fold of its chain in two parts, proven and declared; declared coins are
spent as declared and stay declared in every chain they reach. The chain's node refuses a record whose fold step fails
(overspend, a wrong split, a mint above its time, a receipt that is not the receiver's, a second fate of a SEND), and verifies
every signature with the core before it takes a record. Each of the two nodes keeps a checked replica of the other's chains;
a phone that agreed to keep copies for others pulls every chain, verifies and folds them by the same rules, computes the root
of a checkpoint (every ten minutes of node time: SHA-256 over each key's last record and count, keys in ascending order) and
signs it with its coin key; the nodes keep the last signature of each holder. The Explorer at montana.xxx/explorer folds a
key's whole chain in the browser and shows the root of the newest checkpoint on both nodes with the number of holders whose
signature over that root it verified.

What version 3 does not close, by design or not yet: minting is a phone's claim bounded by time, not a proof of a call or a
letter, and many keys mint in parallel; GENESIS announces and proves nothing, and any key may announce up to its cap before
the cut; the application shows one balance, while the Explorer shows the proven and declared parts; the chains are ordered by
two nodes, so a node that is down stops its keys' records; a holder's signature proves what that holder folded, not that it is
independent; no server other than the two chain nodes keeps a replica yet; the node services are not in this repository.

## 8. Reporting

Findings go to the issues of this repository; a weakness that should not be public goes by e-mail as
[`SECURITY.md`](SECURITY.md) describes.
