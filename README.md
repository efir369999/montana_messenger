# Montana

Montana is a messenger for iPhone, iPad, Mac and Android built on a post-quantum protocol core. A person is twenty-four
words held on the device: there is no phone number, no e-mail address and no account on a server. This repository holds
the source of the protocol core and of the two Montana applications, laid out for an external audit.

[![iPhone and iPad on TestFlight](https://img.shields.io/badge/iPhone%20·%20iPad-TestFlight-D4AF37?style=for-the-badge&logo=apple&logoColor=white)](https://testflight.apple.com/join/BHaSYWkz)
[![Releases](https://img.shields.io/badge/IPA-Releases-C9A227?style=for-the-badge&logo=github&logoColor=white)](https://github.com/efir369999/montana_messenger/releases/latest)

[montana.quest](https://montana.quest) · [Whitepaper](WHITEPAPER.md) · [Audit package](AUDIT.md) · [13-item status](Audit/Protocol-13/README.md) · [Security](SECURITY.md)

**Protocol closure is open: 5 of 13 acceptance criteria are closed** -- items 1 to 4: the window proof and its
verifier, closing only a verified canonical Proposal, redemption bound to authorized issuance, and admission witnesses
bound to one state; and item 7: the earlier core's lottery removed ([status](Audit/Protocol-13/README.md), written from
`core/Montana-Core/PROTOCOL-13.json`). Items 5, 6 and 8 to 13 are open: continuity after a partition, authenticated
first joining, node anonymity and a run of the network on many hosts are among what the published snapshot does not
establish.
Read the source-pinned [reports in Audit](Audit/README.md) before treating historical readiness
statements or passing primitive tests as evidence of these properties.

## What this repository holds

| Path | What it is |
|---|---|
| [`core/`](core/) | The protocol core: the normative specification (`core/docs`), its reference implementation (`core/Montana-Core`) and the client core the applications link (`core/Code`), in Rust. See [`core/README.md`](core/README.md) |
| [`apps/messenger/ios/`](apps/messenger/ios/) | Montana for iPhone, iPad and Mac (Swift). From build 2180 it carries the VPN client that was published separately as MT VPN |
| [`apps/messenger/android/`](apps/messenger/android/) | Montana for Android (Kotlin, with a Rust JNI library over the client core) |
| [`AUDIT.md`](AUDIT.md) | The audit package: scope, builds, vectors, the catalogue of open findings, what can and cannot be verified from this repository |
| [`Audit/`](Audit/) | Current reports for the 13 protocol closure requirements, with explicit open status and source evidence |
| [`WHITEPAPER.md`](WHITEPAPER.md) | The protocol and what the applications implement of it today |
| [`RELEASES.md`](RELEASES.md) | The source commit, build and git tree of every folder, written by the publisher in the commit that changes the folder; the published binaries |
| [`SECURITY.md`](SECURITY.md) | How to report a weakness |
| [`CHANGELOG.md`](CHANGELOG.md) | Every build, newest first: its notes, what it changes for security and anonymity, and its source commit, written before the build is made; each build's full notes in [`doc/release-notes`](doc/release-notes) |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to review, test and propose changes |

Until 2026-10-11 the repository also held the folders of MT Wallet, MT Mesh, MT P2P and MT VPN. They were retired from
publication and remain in the history of this repository; nothing in the current tree depends on them.

## Download

| Platform | Install | Files |
|---|---|---|
| iPhone, iPad, Mac | [TestFlight](https://testflight.apple.com/join/BHaSYWkz) | [IPA](https://github.com/efir369999/montana_messenger/releases/latest/download/Montana-Messenger.ipa) |
| Android 8 or later | [montana.quest](https://montana.quest/messenger/) | APK from the site: [`latest.json`](https://montana.quest/download/android/latest.json) names its build, commit and SHA-256 |

The IPA is the export uploaded to the App Store and is published to be read and compared with the source; it installs
through TestFlight. Which build it is, and its SHA-256, is in the notes of each release. The APK is signed with the
project's Android key and is served by the site, not by the GitHub releases: none of the 75 releases of this repository
(`v1.0-2221` to `v1.0-2315`, read 2026-10-27 UTC) carries one. The source of each folder is the table Sources of
[`RELEASES.md`](RELEASES.md).

## What protects a conversation

Each row is what the code of this repository does today, with the place to read it. Lines are given for the trees named
in [`AUDIT.md`](AUDIT.md); the open findings behind the last column are catalogued there.

| Layer | What the code does | Where | Open |
|---|---|---|---|
| Identity | The twenty-four words give a seed; ML-DSA-65 (FIPS 204) and ML-KEM-768 (FIPS 203) keys derive from it in the core | `core/Code/crates/mt-mnemonic`, `mt-bindings` | |
| First contact | One ML-KEM-768 encapsulation to the key of the correspondent's card gives the conversation secret | iOS `MontanaFirstContact.swift`; Android `Meeting.kt` and `MontanaCard.kt` over `nativeMlkemEncaps`, `nativeMlkemDecaps`, `nativeFirstSecret` | F-10 |
| Letter content | ChaCha20-Poly1305 (the core's `mt_e2e_seal_blob`) under SHA-256("mt-pipe-key" ‖ 0 ‖ conversation secret ‖ minute). The key does not ratchet: whoever later obtains the conversation secret from a device opens every past letter of that conversation | iOS `MTPipe.swift`, `MTNodeWire.swift`; Android `Pipes.kt` | F-3 |
| Delivery | A letter is deposited under a tag derived from the conversation secret and the minute; it travels directly between two devices that reach each other, otherwise through Montana nodes, which hold the sealed body and not its key | iOS `MTPipe.swift`, `MontanaDirect.swift`; Android `Pipes.kt`, `Channel.kt` | F-4, F-14 |
| Channel to a node or a phone | A post-quantum handshake (ML-KEM-768 and ML-DSA-65) seals every frame with ChaCha20-Poly1305. The far side's key is read from the connection and not checked against a known key, and both sides sign with an identity drawn for that one handshake: the handshake encrypts but does not authenticate the far side. Inside TLS (port 443) the host certificate authenticates the name, classically | `core/Code/crates/mt-noise-pq/src/lib.rs`; iOS `MontanaDirect.swift`; Android `Channel.kt` | F-1 |
| Calls | DTLS-SRTP only, a classical key exchange. A frame layer (SFrame, AES-GCM under a key from a seed carried in a sealed letter) is written in the iOS code and switched off; Android has none | iOS `MontanaCall.swift`; Android `CallLine.kt`, `Calls.kt` | F-6 |
| VPN (iOS) | A client of Xray-core with a packet tunnel. Its protocols are classical; it carries traffic and is not a protection of Montana | iOS `scripts/xray-ios`, `Code/PacketTunnel` | |

The core carries three implementations of ML-DSA-65 and ML-KEM-768 (libcrux in `core/Montana-Core`, OpenSSL 3.5 in
`core/Code`, RustCrypto for the web target and as a test oracle); see [`AUDIT.md`](AUDIT.md), F-7.

## Build from source

Every command is run from the root of this repository unless it says otherwise. What a build of the published tree yields,
and what it does not prove, is in [`AUDIT.md`](AUDIT.md).

**Core.** Each workspace pins Rust 1.92.0 in its `rust-toolchain.toml`; `core/Code` builds OpenSSL 3.5.5 from source and needs
a C compiler and Perl.

```
cd core/Montana-Core
cargo test --workspace --release
cd ../Code
cargo test --workspace --release
```

**Montana for iPhone, iPad and Mac.** macOS with Xcode and its iOS SDK (the Xcode release is not pinned in the tree), Rust
1.92.0 through rustup with the device target (`rustup target add aarch64-apple-ios --toolchain 1.92.0`), Go for the VPN
engine. The deployment target is iOS 17.2. The core is built for devices only, so the application is built for a device:
with your own team, or with signing off to check that the source compiles. In `apps/messenger/ios`:

```
MONTANA_CORE_SRC="${PWD}/../../../core/Code/crates/mt-bindings" bash scripts/build-core.sh
MONTANA_PROTOCOL_CORE="${PWD}/../../../core/Montana-Core" bash scripts/build-protocol-core.sh
bash fetch-webrtc.sh
bash scripts/xray-ios/build-xray-xcframework.sh
bash scripts/hev-ios/build-hev-xcframework.sh
xcodebuild build -project Montana.xcodeproj -scheme Montana -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
```

The last engine script writes `Frameworks/HevSocks5Tunnel.xcframework` beside `Code/`, while the project links it from
`Code/Frameworks/`: move it there before `xcodebuild`. The two engine scripts are in the folder from build 2180; a folder of an
earlier build has no VPN and needs the first three steps and `xcodebuild` only.

**Montana for Android.** In `apps/messenger/android`, `python3 scripts/setup.py` installs the toolchain pinned in
`scripts/toolchain.json` (JDK 17, Android SDK 35, NDK, Kotlin, the call engine, each checked against its digest), and
`python3 scripts/build.py --check` compiles the resources and the Kotlin. The full build (`python3 scripts/build.py`) also
builds the JNI library from the core, and it expects the core as a git checkout of one exact commit in a folder named
`Montana Protocol` beside the Android tree (`scripts/toolchain.json`, `protocol`; `scripts/build.py`, `core`). That commit is
not the commit of `core/` in this repository, so the APK's native library cannot be rebuilt from this repository as it stands:
see [`AUDIT.md`](AUDIT.md), F-12.

## Diagnostics

Both applications send diagnostic journals (event records, timings, error codes, crash and hang reports, the device model,
the system and the build) to a Montana node. What a line may contain is decided in the code: iOS `MontanaLog.swift` and
`MontanaTrace.swift`, Android `Diary.kt`; each line passes a pattern pass that collapses addresses and replaces names by salted tags before it is
written (`hide` in both files). How long the node keeps the journals is the operator's statement and cannot be verified from
this repository.

## Reports

Open an issue with the build (Settings, About), the device and system version, the network on each side, the exact time and
what was expected instead. Do not paste recovery phrases, other people's addresses or message content into an issue. A
weakness goes by e-mail, not into an issue: see [`SECURITY.md`](SECURITY.md).
