<p align="center">
  <img src="https://montana.quest/download/icon.png" width="132" alt="Montana">
</p>
<h1 align="center">Montana</h1>
<p align="center">The Montana Time ecosystem: letters, calls, coins of time, a mesh, direct delivery and a VPN, on one post-quantum core. No phone number, no e-mail: 24 words are your account.</p>
<p align="center">
  <a href="https://testflight.apple.com/join/BHaSYWkz"><img alt="iPhone and iPad on TestFlight" src="https://img.shields.io/badge/iPhone%20·%20iPad-TestFlight-D4AF37?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/efir369999/montana_messenger/releases/latest"><img alt="Releases" src="https://img.shields.io/badge/IPA%20·%20APK-Releases-C9A227?style=for-the-badge&logo=github&logoColor=white"></a>
</p>
<p align="center"><a href="https://montana.quest">montana.quest</a> · <a href="https://montana.xxx">montana.xxx</a> · <a href="WHITEPAPER.md">Whitepaper</a> · <a href="core/">Core</a></p>

## What this repository is

The whole source of the Montana Time ecosystem: the protocol core with its specification and its cryptography, and
the client of every application, each in its own folder. The business application lives in its own repository,
[montana_business](https://github.com/efir369999/montana_business). Every folder is the tree of one commit of the
project's private history, published as it builds, under the publication notes below.

| Path | What it is |
|---|---|
| [`core/`](core/) | The protocol: the normative specification, the reference implementation and the client core in Rust; ML-DSA-65, ML-KEM-768, ChaCha20-Poly1305, SHA-256. See [`core/README.md`](core/README.md) |
| [`apps/messenger/ios/`](apps/messenger/ios/) | **Montana** (Messenger) for iPhone, iPad and Mac |
| [`apps/messenger/android/`](apps/messenger/android/) | **Montana** (Messenger) for Android |
| [`apps/wallet/ios/`](apps/wallet/ios/) | **MT Wallet**, the coins of time |
| [`apps/mesh/ios/`](apps/mesh/ios/) | **MT Mesh**, rooms over Bluetooth between phones that are near |
| [`apps/p2p/ios/`](apps/p2p/ios/) | **MT P2P**, delivery straight from phone to phone |
| [`apps/vpn/ios/`](apps/vpn/ios/) | **MT VPN**, a VPN client and the wall where a person shares their own VPN |
| [`WHITEPAPER.md`](WHITEPAPER.md) | The ecosystem in one paper, with the specification it rests on |
| [`RELEASES.md`](RELEASES.md), [`CHANGELOG.md`](CHANGELOG.md) | The build and the source commit of every folder, written by the publisher with the folder itself; the published binaries; the log of changes as it stood on 2026-10-03, when the log stopped being published |
| [`SECURITY.md`](SECURITY.md) | How to report a weakness |

## Download

| Application | Install | Files |
|---|---|---|
| Montana (Messenger) | [TestFlight](https://testflight.apple.com/join/BHaSYWkz) on iPhone, iPad and Mac; [APK](https://github.com/efir369999/montana_messenger/releases/latest/download/Montana-Messenger.apk) on Android | [IPA](https://github.com/efir369999/montana_messenger/releases/latest/download/Montana-Messenger.ipa), [APK](https://github.com/efir369999/montana_messenger/releases/latest/download/Montana-Messenger.apk) |
| MT Wallet | [TestFlight](https://testflight.apple.com/join/n9UqzRDp) on iPhone, iPad and Mac | [IPA](https://github.com/efir369999/montana_messenger/releases/latest/download/Montana-Wallet.ipa) |
| MT Business | [TestFlight](https://testflight.apple.com/join/MSMfey6f) on iPhone, iPad and Mac | [montana_business releases](https://github.com/efir369999/montana_business/releases/latest) |

MT Mesh, MT P2P and MT VPN are built from their folders in this repository.

The IPA files are the exports uploaded to the App Store: they are published to be read, compared with the source or
re-signed, and the way to install on iPhone, iPad and Mac is TestFlight. The APK installs directly on Android 8 or later.
Android carries one application, the Messenger.

## The ecosystem

**One person, one key, every application.** Each application creates or opens a person from the same 24 words. The
words produce the seed; from the seed come the ML-DSA-65 signing key that is the person's identity and address, and the
ML-KEM-768 key that others encrypt to. Nothing about a person is stored on a server: the history lives on the device.

- **Montana (Messenger).** Text, photos, video, files and voice messages; voice and video calls with screen sharing; typing
  seen live; delivery and read receipts, replies, reactions, editing, forwarding and deletion for everyone. A letter is sealed
  end to end and travels directly between two phones when they can reach each other (one local network, IPv6, or a port the
  router forwards), otherwise through Montana nodes that forward sealed envelopes and hold no key that opens them.
- **MT Wallet.** The coins of time. Every source of coins keeps its own time chain: one link per move of coins, numbered,
  stamped and sealed by SHA-256 over the link and the seal before it, so a changed or moved link breaks every seal after it.
  The wallet shows every chain, its length, its head and whether every seal holds. One second is one coin.
- **MT Mesh.** Rooms that live on Bluetooth Low Energy between phones that are near one another: a word hops from phone to
  phone without the internet.
- **MT P2P.** Delivery straight from phone to phone: the phone is its own node, learns its outward address and keeps its own
  door open, so two people talk without any machine between them.
- **MT VPN.** A VPN client with a packet tunnel on iPhone, iPad and Mac. It reads the common subscription and link formats, and a
  person can put their own VPN on their wall for the people they write to.
- **MT Business** ([its repository](https://github.com/efir369999/montana_business)). The messenger built for a company:
  departments, offices, channels with discussion, administration, shifts and supply, and sign-in by phone number, e-mail or the
  24 words.

## The sites

| Site | What it is for |
|---|---|
| [montana.quest](https://montana.quest) | The Messenger's home: download, privacy policy, and the links a person hands out: a card (`/r/`, `/perp/`, `/temp/`) and a name (`/n/name`), which open the app through the associated domain |
| [montana.xxx](https://montana.xxx) | The store of Montana applications, one page per application with its download doors and its source; the home of MT Business with its privacy policy, terms and support |
| [efir.org](https://efir.org) | A mirror of the Montana site |
| [pronoia.my](https://pronoia.my) | The home of MT VPN, with its privacy policy, terms and support |
| pzr.me | The earlier form of a name link; the applications still read it, new links are written on montana.quest |

The applications reach the network through public names of the Montana nodes; no node address is written in this
repository.

## What protects a conversation

| Layer | Primitive |
|---|---|
| Identity and signatures | ML-DSA-65 (FIPS 204) |
| Key agreement | ML-KEM-768 (FIPS 203) |
| Message content | ChaCha20-Poly1305 under the session key |
| Hashing | SHA-256 |
| Link between two machines | Noise XX with ML-KEM-768 and ML-DSA-65 in place of classical Diffie-Hellman |
| Call media | SFrame with a key derived from a call seed carried inside the sealed envelope; DTLS-SRTP is transport admission only |

ML-DSA-65 and ML-KEM-768 come from the Montana core, checked against the NIST known-answer tests. Read
[`core/README.md`](core/README.md) for the implementations and versions, and [`WHITEPAPER.md`](WHITEPAPER.md) for the design.

## Build from source

**Core.** Rust 1.92.0 (pinned in each workspace):

```
cd core/Montana-Core
cargo test --workspace --release
cd ../Code
cargo test --workspace --release
```

**iPhone, iPad and Mac applications.** Xcode 26.2 on macOS 15.7 or later, Rust 1.92.0 through rustup with the device target
(`rustup target add aarch64-apple-ios --toolchain 1.92.0`); the applications run on iOS 17.2 or later. The core is built for the
device, so an application is built for a device: with your own team for signing, or with signing off to check that the source
compiles. In the folder of an application, the core's two frameworks are built from `core/`, the call engine is fetched, and the
project is built:

```
cd apps/messenger/ios
MONTANA_CORE_SRC="$PWD/../../../core/Code/crates/mt-bindings" bash scripts/build-core.sh
MONTANA_PROTOCOL_CORE="$PWD/../../../core/Montana-Core" bash scripts/build-protocol-core.sh
bash fetch-webrtc.sh
xcodebuild build -project Montana.xcodeproj -scheme Montana -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
```

The same four steps build `apps/wallet/ios`, `apps/mesh/ios` and `apps/p2p/ios`. MT VPN links two more engines, built by the
scripts in its `scripts/xray-ios` and `scripts/hev-ios`; they are published with its next build.

**Android.** `apps/messenger/android/scripts/setup.py` installs the pinned toolchain of `scripts/toolchain.json`
(JDK 17, Android SDK 35, NDK, Kotlin, the call engine, each by digest); `scripts/build.py` builds the APK.

## Publication notes

Node endpoints in this tree are documentation addresses (RFC 5737) and the VPN test credential is a made-up one; the
released binaries carry the live endpoints. The trees hold the code, its build files and its tests; signing material,
process documents and deployment scripts stay with the project. Comments and documents are in English. Apart from those
endpoints and that credential, the code is the code of the commit named for each folder in the Sources table of
[`RELEASES.md`](RELEASES.md).

## Beta, testing and reports

| Item | State |
|---|---|
| Platform | iPhone and iPad with iOS 17.2 or later; Apple silicon Mac; Android 8 or later for the Messenger |
| TestFlight | Messenger, Wallet and Business: the links above carry the newest build of each |
| Feedback | GitHub Issues in this repository, or contact@montana.quest |
| Privacy policy | https://montana.quest/privacy/ |

Open an issue with the *Bug report* template and name the build (Settings → About), the device and system version, the
network on each side, the exact time and what was expected instead. Do not paste recovery phrases, other people's addresses
or message content into an issue. Weaknesses go by e-mail, not into an issue: see [SECURITY.md](SECURITY.md).

## Diagnostics

The applications send their diagnostic journals (event records, timings, error codes, crash and hang reports, the device
model, the system version and the build) to a Montana diagnostics node, where they are kept for seven days and then deleted.
They never hold message content, names, phrases or network addresses.

## Known limits

- History lives on the device; deleting the application erases it there. A copy sealed under a key only your 24 words open is
  kept by the people you write to (on by default; the application asks once, at the first opening), and can be kept in the
  application's own iCloud container and on a node you run yourself.
- Two phones that are both behind carrier NAT, without IPv6 and without a forwarded port, cannot reach each other directly and
  talk through the nodes.
- The coins of time are a tally kept on the phone in its own time chains, separate from the notes of the core's wallet.
