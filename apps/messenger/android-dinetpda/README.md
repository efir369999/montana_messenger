# Montana for Android: DinetPDA's counterpart build

**A development port: work in progress, not a release, and not the project's Android app.** Its package is
`quest.montana.app.dev`, and it is signed with a debug key. **Never install it on a phone that holds a real identity:**
use an emulator or a test device, with test identities only.

This folder holds DinetPDA's Android app for Montana. It is the phone side of the checks of Montana for Windows
(`apps/messenger/windows`). Those checks need one identity, one set of 24 words, on several devices, and the wire as the
iOS reference (`apps/messenger/ios`) speaks it. The project's own Android app is `apps/messenger/android`, staged by the
project's build road. This branch does not touch that folder, and it does not touch `core/`.

The two Android trees are published side by side so that they can be compared. The project's Android developer is free
to read anything here and take what helps. No APK of this folder is published. Only emulators have run it: no physical
phone, and no iPhone.

## Contents

- [Where it comes from](#where-it-comes-from)
- [Layout](#layout)
- [State per feature](#state-per-feature)
- [Build](#build)
- [Tests](#tests)
- [Deviations from the specification and from iOS](#deviations-from-the-specification-and-from-ios)
- [Cryptography that is not Montana's own](#cryptography-that-is-not-montanas-own)
- [Not run, open questions](#not-run-open-questions)
- [Third-party components and licences](#third-party-components-and-licences)
- [Left out of this folder](#left-out-of-this-folder)

## Where it comes from

**The start.** The app began as upstream's `apps/messenger/android` build 411. That is folder tree `674ab0c96f69…`
from source commit `07e5f3cde2e0`, which `main` held until 2026-10-25. Since `86d5b28`, `main` holds the project's newer
builds: 543 to 552, and at `d5a334e` build 552, tree `af8316a93370…`. It was imported on
2026-10-17 at 14:22 UTC from upstream commit `97433815677a` into a local repository. The core `4ce3d6705224…` sat beside
it.

**The local work.** 70 commits followed, up to local commit `02f92553bc19` (2026-10-25 08:12 UTC). Of those, 51 touch the
app or its tools. This folder is that commit's `android/` and `tools/`, copied as files: the local history is not part
of this repository.

**Changes made for this folder.** Apart from this README, 33 files differ from that commit.

- 11 for the build here:
  - the paths to the core;
  - the build copy of `tools/wsl-build.sh`;
  - two tool paths;
  - comments that named files of the local repository;
  - `.gitignore` and `.gitattributes`.
- 5 comments reworded in English, so that none cites a file that is not published: `CoinChain.kt`, `CoinLocalTest.kt`,
  `Archive.kt`, `Presence.kt` and `Twin.kt`.
- 10 that keep the 24 words out of the system backup (see [The words and the system backup](#the-words-and-the-system-backup)):
  `BackupSeed.kt` is removed, `BackupWithdraw.kt` is new, and `AndroidManifest.xml`, `BoxJob.kt`, `MainActivity.kt`,
  `Onboarding.kt`, `Settings.kt` and the three `strings.xml` follow. The local repository carries the same change.
- 5 for the author field's self-check, which now reads each vector on its own day (see [Tests](#tests)): `AuthorCanon.kt`,
  `tools/author_canon_check.kt` and `tools/author_canon_check.sh` are new, and `Pipes.kt` and `tools/author_vectors.py`
  follow. The local repository carries the same change; here the check script reads `app/`.
- 2 for the VPN engine's delay measure, written anew (see [The VPN engine's delay measure](#the-vpn-engines-delay-measure)):
  `native/montana-xray/montanaxray.go` and its new tests, `native/montana-xray/measuredelay_test.go`.

`scripts/toolchain.json`, one of the 11, also pins the core's tree (see [Build](#build)). Every other file is byte for
byte the same.

**Comparing with the project's app.** This command shows what differs from `main`'s Android app:

```
git diff --stat origin/main:apps/messenger/android HEAD:apps/messenger/android-dinetpda
```

On 2026-10-26, for this folder as of folder tree `d0faa10afd19`, the result was:

| `main`'s Android folder | Equal | Changed | New here | Only in `main` |
|---|---|---|---|---|
| build 411 (tree `674ab0c96f69`, `main` up to `2c7eb0d`), where this app began | 247 | 53 | 135 | 1: `BackupSeed.kt`, removed here |
| build 552 (tree `af8316a93370`, `main` since `d5a334e`) | 213 | 91 | 131 | 20: `BackupSeed.kt`, 18 files that build 543 added, and `FloorGuard.kt` |

The new files are those of `app/`, `native/` and `tools/`, plus `.gitattributes` and this README. Builds 543 to 552 have
not been compared with this app feature by feature.

## Layout

| Path | What it is |
|---|---|
| `app/src/main/kotlin/quest/montana/app` | The app: 116 Kotlin files (about 55 000 lines). The package is `quest.montana.app` and the application id is `quest.montana.app.dev` |
| `app/src/main/res` | Resources: en, ru and zh-rCN strings, drawables, the network security config, the coin-writes flag |
| `native/montana-jni` | The Rust JNI library `libmontana.so`, linking the core's own crates. Its tests compare every JNI function with the C function iOS calls |
| `native/montana-xray` | The VPN wall's engine wrapper: `montanaxray.go` (iOS's, with its delay measure written anew), its tests `measuredelay_test.go`, iOS's `go.mod` and `go.sum` byte for byte, and `protect_android.go` |
| `scripts` | The build road, with no Gradle: `toolchain.json` (every pin), `setup.py`, `build.py`, `toolchain.py`, `version` |
| `tools` | WSL wrappers, APK verification, vector checks, the LZFSE check, the twin-reference tool, the emulator driver |

## State per feature

**What the states mean**

- **works**: checked by running it.
- **partial**: some of it was checked, and the rest is named as not checked.
- **prototype**: the code is in the app and builds, but no run has checked it.
- **missing**: iOS has it, and this app does not.

**How the checks were made.** All of them used test identities only. They ran on Android 14 x86-64 emulators (AVD
android-34 default image) against the live Montana nodes. A row is Android to Android unless it names Windows.

**Where the evidence comes from.** The development journal and the Windows app's check scenes
(`apps/messenger/windows/app/tools/`), on the UTC dates given. None of these was run again for this publication. What
was run for it is under [Tests](#tests).

### Identity and the 24 words

| Feature | State | Evidence |
|---|---|---|
| The 24 words and their keys (PBKDF2 2^20, HKDF roles, ML-DSA-65, ML-KEM-768, all in the core) | works | 2026-10-17: the core's crates passed 455 tests, and JNI matched the iOS C ABI in 20 of 20. On the emulator, 24 words of the Montana wordlist came out with `seed write: words=24 stored=true` |
| Restore from the 24 words | works | 2026-10-17: the words of A on a second emulator gave the same identity. Its call sign matched the one the core predicts from the words (`tools/identity-ref`, `tools/callsign_of.py`). 2026-10-20: Windows, opened with an Android test identity's words, took that identity's name and conversations from the light copy Android had laid |
| The words at rest | works | 2026-10-17: Android Keystore AES-256-GCM (`Identity.kt`). The words screen is under FLAG_SECURE, so a screenshot of it is empty |
| The words kept out of the system backup (`core/docs/Montana Identity.md:343`) | prototype | Built for this publication, not run. No record of the words is written to the system backup or read from it, and a record an earlier build wrote is withdrawn at the next backup; see [The words and the system backup](#the-words-and-the-system-backup) |
| Several identities on one phone (iOS MontanaSeats) | missing | |
| Safety number (`mt-safety`) | prototype | |

### Contacts and the first letter

| Feature | State | Evidence |
|---|---|---|
| Card links `/perp/`, `/temp/`, `/r/`, the rendezvous, the first letter (ML-KEM) and its confirmation | works | 2026-10-17: A and B through the nodes, and JNI `first_contact_matches_ios`. 2026-10-20: Android opened a Windows card and wrote first |
| QR `MTC1:` / `MTR1:` | prototype | |
| Names (`/name-*`) and call signs | partial | `names_canon ok` at every launch. `/name-get` has not been run live |
| Card ring (`mt-card-ring`) | missing | |

### Letters and the pipe key

| Feature | State | Evidence |
|---|---|---|
| The envelope of 2048 bytes (fields 1 to 7), the author field (eighth field, HMAC `mt-letter-author`), receipts, presence, the delivery queue | works | 2026-10-17/18, Android to Android: Cyrillic and emoji arrived character for character. 2026-10-20, Windows and Android both ways: letters in 2 s and 5 s, delivered and read, presence, reactions, edits, deletion for everyone, replies with a quote. 2026-10-25: the self-check that lets a letter carry the author field reads each vector on its own day (`AuthorCanon.kt`), so the field stays from 29.10.2026; `tools/author_canon_check.sh` passed 13 of 13 |
| The pipe key's daily step (iOS 2305 `MTNodeWire.pipeSecret`). The secret walks from 2026-10-29 00:00 UTC, anchor day 20754 | partial | `walk_canon` checks iOS's own walk vectors at every launch. Letters past the step on the real date are not checked yet: the Windows scene `walk.ps1` is due after 2026-10-29 00:00 UTC. Without the step, Android would stop reading Windows and iOS on that day |
| Long letters `LB:` | prototype | |

### One identity on several devices

| Feature | State | Evidence |
|---|---|---|
| The twin's history (`twin:history`, blocks `hist`) | works | 2026-10-17: Android to Android. 2026-10-20: Windows took Android's blocks |
| The twin mirror (iOS `lt` words): one's own sent letters, a correspondent's letter taken by one device, reads (`TR:`), landed quietly | works, with Windows | 2026-10-24: scene `twin3.ps1`, 4 of 4 |
| The mirror of group words | works, with Windows | 2026-10-24: scene `twingroup.ps1`, 4 of 4 |
| The ear held on the twin's pipe | works, with Windows | 2026-10-24: scene `twinlane.ps1`. A read on Windows reached the open Android in 39 s |
| Rows asked of the other devices and given back (`TA:` / `TW:`) | works, with Windows | 2026-10-24: scene `twinask.ps1`, after the D27 fix. The gap was seen, `TA:` went out, and 5 rows came back as `TW:` and were laid. 79 blocks were read across two holes |
| Saved Messages carried in the archive (iOS `savedMessagesKey`) | works | 2026-10-24: scene `saved19.ps1`. A verified copy and manifest were made before the carrying, the result was `check ok letters=4 folder=4`, and every letter appeared once, after a restart as well |
| The box as iOS 2306 speaks to it (`devs`, taken by device) | partial | 2026-10-25: the live nodes answer `/box-del {"taken": …}` with `200 {"ok":true,"taken":1}`. The flow across several devices has not been run as a scene yet |
| Live cards for the other devices (`rdvTwin`) | prototype | |
| A media letter's pieces stay on the nodes for their week (D8, as iOS 2305) | prototype | |
| Any of this with an iPhone | not checked | No iPhone was available |

### The copy kept by correspondents

| Feature | State | Evidence |
|---|---|---|
| MTKeeping (RS(16,12), slots, the ring), the light copy, back and given | works | 2026-10-17: owner A, keeper C, and the copy rebuilt on B. `tools/keep_vectors.py` passed 20 of 20, and `keep_canon ok` appears at every launch |

### Groups and channels

| Feature | State | Evidence |
|---|---|---|
| Groups and channels as in iOS 2235: events, typing, reads, admins, views, pages, folders, the `@` plate, «N Seen», Join, Delete and Exit, the groups in a copy (`d:groups.held`) | works | 2026-10-17/18: A and C. 2026-10-20: a group and a channel made on Windows reached Android, with letters both ways |
| Joining by a `jg` link, `kk`, bans, `kp`, dissolving | prototype | |
| Group rooms (voice and video, up to 13) | missing | |

### Calls

| Feature | State | Evidence |
|---|---|---|
| 1:1 calls over WebRTC, as iOS does them (TURN, DTLS-SRTP) | partial | 2026-10-18, A and C: audio both ways, measured in bytes. Video carried sound only, because the emulators have no camera. Decline, no answer and the call records in the chat all worked. 2026-10-20: voice between Windows and Android both ways reached ICE connected. Not checked: the picture, whether the voice is heard, screen sharing, a call in the background or on a locked screen |
| Call receipts, the device word, `/wake-voip`, call recording, the system's call screen (ConnectionService), iOS 2307 and 2308 | missing | |

### Files and media

| Feature | State | Evidence |
|---|---|---|
| Files and media (`MD:` manifest, 512 KiB pieces, `/blob-*`) | partial | 2026-10-20, Windows and Android: a picture went from Android to Windows, and documents went both ways. Not checked: voice and video notes (the emulators have no microphone or camera), link previews, location, music, stickers |
| YouTube (iOS 2231) | missing | |

### Notifications, background and the node

| Feature | State | Evidence |
|---|---|---|
| Notifications and the background | partial | 2026-10-17: the ear (`EarService`, a foreground service with a long poll) and `BoxJob` bring letters while the app is closed and after a reboot. There is no push: nothing here stands for APNs or PushKit, and FCM would need support on the nodes |
| The node: doors (`nodes.txt`, `/doors`, `/health`), the Noise_PQ channel over TLS 443 and WSS, registration | works | 2026-10-17: `noise_done` on 3 doors, then `reg_ready` and `path_up` ×3. Further doors were learned from the network |
| Phone to phone (TCP 8447), the LAN (NSD, off), NAT-PMP and UPnP, BLE mesh | partial (8447) / missing | The app listens on 8447. A phone-to-phone path has never been checked, because the emulators sit in isolated networks |
| A check's own node at 10.0.2.2 (for checks with the clock moved) | prototype | Added on 2026-10-25. It is on only when a file that the emulator's root lays in the app's own folder names it |
| One's own home node (vault) with its pinned certificate | prototype | It builds. There is no node with a pinned certificate to check it against |

### The wallet and coins

| Feature | State | Evidence |
|---|---|---|
| Coins v3: the rules, the records, the replica of the network's chains, the coin vault kept by the words | partial | Vectors V1 to V6: `tools/coin_vectors.py` 13 of 13, and V5 by the core on the phone. 2026-10-17: the replica's root equalled the nodes' root (8380 records, `same=1`), `CoinLocalTest` passed 48 of 48, and the vault on live nodes went from A to B with `balance=10`. LZFSE matched Apple's reference in 895 of 895. **Writes to the live chains are off** (`res/values/coin_flags.xml`), and the build with writes was never launched |
| The wallet's pages: history, analytics, the Money Flow, auto-reactions, «Give a coin», levels, the person's chain, the TimeChain page | works, local book only | 2026-10-18: A and C, with screenshots and logs. The coins move in the local book only |
| The TimeChain tip and the top (`MTTimeChainTip`) | missing | |

### The VPN wall

| Feature | State | Evidence |
|---|---|---|
| Xray-core and hev-socks5-tunnel in a VpnService: plans, ping, the life watch, minting for live seconds | partial | 2026-10-18, against a local Xray 26.3.27 test server: subscriptions, retries, ping, consent, traffic and a letter through the tunnel, a live switch, a dead server released after 90 s, and the wall raised again after an update and after a killed process. Not checked: real panels and servers, QR and file import, always-on VPN, a physical phone |

### Settings, look and language

| Feature | State | Evidence |
|---|---|---|
| Settings, privacy, access by level | works | 2026-10-18: screenshots. Account deletion was not run |
| The look of iOS 2235 | partial | Ported from the SwiftUI source. It has never been compared with an iPhone screen |
| Localization en / ru / zh | partial | 2026-10-17: 839 strings against 1501 keys in iOS |
| Passwords and one-time codes, chess, the wall `WL:`, diagnostics | prototype | |
| Login by phone number, the app library | missing | |

### Build and tests

| Feature | State | Evidence |
|---|---|---|
| The build and its signing | works | Run for this publication; see [Tests](#tests). It signs with a debug key, and the package is `quest.montana.app.dev` |

## Build

### Where it builds

**Host.** Linux x86-64 or macOS on Apple silicon: the hosts `scripts/toolchain.json` knows. On Windows, use WSL2. The
checks below ran on Ubuntu 24.04.

**No Gradle.** `scripts/build.py` calls the SDK's own tools in turn: aapt2, javac, kotlinc, d8, zipalign and apksigner.
`cargo ndk` builds the core's library. gomobile and the NDK build the VPN engines.

### Toolchain

Every version below is pinned by `scripts/toolchain.json`, and every download is checked against the digest pinned
there. The Rust version is the core's own pin.

| Piece | Version |
|---|---|
| JDK | Temurin 17.0.20.1+1 |
| Android command-line tools | 22.0 |
| Android SDK | build-tools 35.0.0, platform android-35 (targetSdk 35), platform-tools; minSdk 26 (`scripts/build.py`) |
| NDK | 27.2.12479018 |
| Kotlin | 2.0.21 |
| WebRTC | `io.github.webrtc-sdk:android` 144.7559.15, pinned by SHA-256 |
| Rust | 1.92.0 (`core/Code/rust-toolchain.toml`), targets `aarch64-linux-android` and `x86_64-linux-android` |
| cargo-ndk | 4.1.2 |
| Go, gomobile | Go 1.26.8; gomobile `v0.0.0-20260803200217-62cee1672c8e` |
| hev-socks5-tunnel | 2.18.0 (commit `d9dca26c7ad0`) |
| Xray-core | v1.260327.0 (`native/montana-xray/go.mod`) |

The machine that ran the checks of 2026-10-25 had the following: Windows 11 Pro 10.0.26200 with WSL2 Ubuntu 24.04.4 LTS,
kernel 6.6.87.2, Python 3.12.3, git 2.43.0, rsync 3.2.7, Perl 5.38.2, gcc 13.3.0, GNU Make 4.3, `lzfse` 1.0 and
platform-tools 37.0.1. The vector tools ran under Python 3.14.2 on Windows.

### Get the source

The build checks the core's files against the tree that `core/` has in git, so line endings must not be converted:

```
git clone -c core.autocrlf=false https://github.com/efir369999/montana_messenger.git
cd montana_messenger
git checkout dinetpda/android
cd apps/messenger/android-dinetpda
```

### On Linux or macOS

Run these from this folder:

```
python3 scripts/setup.py                                 # once: the pinned toolchain
python3 scripts/build.py --check                         # resources and Kotlin compile; no core, no signing
python3 scripts/build.py                                 # build/Montana.apk for arm64-v8a phones
python3 scripts/build.py --abi arm64-v8a --abi x86_64    # phones and the x86-64 emulator
python3 scripts/build.py --core-only                     # libmontana.so only
python3 scripts/build.py --install                       # and adb install -r, then start
```

- **Where the toolchain goes.** Linux: `/opt/montana-tools`, which must be writable by the builder. macOS:
  `~/Library/Montana-tools` and `~/Library/Android/sdk`.
- **What setup needs.** Network access, plus `unzip`, `tar` and `git`. The core's tests also build OpenSSL 3.5 from
  source, so they need Perl, make and a C compiler.
- **Signing.** The default key is `~/.android/debug.keystore`, made on first use. With `--keystore PATH`, the build signs
  with that key, and its password is read from `PATH.pass` beside it.

### On Windows, through WSL2

The default distribution is `Ubuntu-24.04`; set `MONTANA_WSL_DISTRO` to use another.

```
powershell -File tools\build.ps1 setup          # once
powershell -File tools\build.ps1 check
powershell -File tools\build.ps1 apk            # add --abi arm64-v8a --abi x86_64 for the emulator too
powershell -File tools\build.ps1 test-jni
powershell -File tools\build.ps1 test-core
```

Inside WSL the same commands are `bash tools/wsl-build.sh <command>`.

- **The build copy.** `tools/wsl-build.sh` copies the repository's git data, `core/` and this folder to `~/montana-build`
  (or `MONTANA_BUILD_DIR`) and builds there. OpenSSL's build breaks on paths with spaces, and `/mnt/c` is slow.
- **What comes back.** The APK returns as `out/Montana-<commit>[-dirty]-<abis>.apk` with its `.sha256`, and the log of
  every run goes to `out/logs/`.
- **What the checkout must be.** A plain clone. In a git worktree `.git` is a file that names a path of the host, and the
  copy cannot use it.

### Installing

`adb install -r out/Montana-<commit>-<abis>.apk` installs the app, and `tools/verify-apk.sh <apk>` checks a built APK.
The application id is `quest.montana.app.dev`, the same as the project's own Android build, but the signature is
another. Android therefore refuses to install one over the other, and uninstalling deletes that app's data. **Use a
test device or an emulator, never a phone that holds a real identity.**

## Tests

### What there is

| Command (from this folder) | What it checks |
|---|---|
| `bash tools/wsl-build.sh test-jni` | 20 tests compare every JNI function of `libmontana.so`, byte for byte, with the `mt-bindings` C function iOS calls. They cover ML-DSA and ML-KEM keys, the master seed and entropy, the owner role, sealing, the first contact and its tag, the history key, the archive (reading and writing), signatures, the Noise_PQ handshake both ways and the refusal of a forged msg2, a wrong phrase, and the Canon name vectors |
| `bash tools/wsl-build.sh test-core` | The core crates the app links: mt-mnemonic, mt-crypto, mt-crypto-native, mt-codec, mt-noise-pq, mt-names, mt-messenger-e2e, mt-bindings |
| `python3 -I tools/vectors_check.py` | Android's own wire vectors recomputed from the formula, with three of the iOS frozen ones |
| `python3 -I tools/coin_vectors.py` | Coins v3 vectors V1 to V4 and V6, from `Audit/App/COIN-TX-V3.md` alone |
| `python3 -I tools/keep_vectors.py` | MTKeeping: RS(16,12), the slot secrets, the keeping key, the light secret, the head and its seal, the ring |
| `python3 -I -X utf8 tools/author_vectors.py` | The author field, over the established secret and, from the day after the anchor day, over the conversation's root. The values must equal the frozen ones in `AuthorCanon.kt` |
| `bash tools/author_canon_check.sh` | `author_vectors.py`, then the author field's self-check (`AuthorCanon.agrees`) over a mirror of the code a letter is signed with, run on the days 20700, 20754, 20755, 20757, 20758, 20760, 20761, 20800 and 20754 + 36605; and letters signed on 28.10, 29.10, 01.11 and 03.11.2026 read back as the person's own |
| `bash tools/lzfse_check.sh` | The Kotlin LZFSE against the `lzfse` reference command, in both directions, with damaged streams |
| `python3 -I tools/groups_copy_check.py <file>` | A groups copy written by the test door below, decoded the way iOS decodes `[String: MTGroupState]` |
| `bash tools/verify-apk.sh <apk>` | The signature, the package, its processors, 16 KiB alignment, and the JNI functions |

**Checks at every launch.** The app checks itself each time it starts, and logcat tag `Montana` shows the result of each
check: `names_canon`, `author_canon`, `walk_canon`, `keep_canon`, `coin_canon`, `twin_canon`, `person_self`,
`coins_vault canon`.

**Test doors.** A `.dev` build opens three test doors:

```
adb shell am start -n quest.montana.app.dev/quest.montana.app.MainActivity --ez coinLocalTest true
```

`coinLocalTest` runs two chain nodes in memory with throwaway keys. The other two doors are `--ez groupsCopyTest true` and
`--ez genesisDialog true`.

**What there is not.** There are no Kotlin unit tests and no instrumented tests. Screens are checked by hand over adb
with `tools/ui.ps1`. The checks with Windows are the Windows app's scenes in `apps/messenger/windows/app/tools/`:
`android.ps1`, `twin3.ps1`, `twingroup.ps1`, `twinlane.ps1`, `twinask.ps1`, `saved19.ps1`, `walk.ps1` and `clocknode.py`.

### Run for this publication (2026-10-25, UTC)

Commit hashes change each time this branch is rebased onto `main`; folder trees do not, so the runs are named by the
folder tree (`git rev-parse HEAD:apps/messenger/android-dinetpda`) and by the commit they ran on.

**On folder tree `d0faa10afd19`** (2026-10-26), after the VPN engine's delay measure was written anew and the core was
pinned to `main`'s tree `6aeb359d095b`, on commit `9844b50`. The checks ran from a plain clone in WSL, with a build copy
of its own. The Go steps ran in `native/montana-xray` with the pinned Go and no network for modules
(`GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=mod`). This README's update came afterwards and changes nothing that is built.

| Command | Result |
|---|---|
| `go version` | exit 0. `go1.26.8 linux/amd64` |
| `go vet ./...` | exit 0 |
| `go test -race -count=1 -v -run 'TestDelay\|TestMeasure' .` | exit 0, 26 s. 16 tests passed, none skipped; 60 calls (10 of them batches) left goroutines 3 → 3 and open files 7 → 7 |
| `gofmt -l .` | lists `montanaxray.go` for one comment's alignment in its closing `const` block (`ipBoundIf`), as in the earlier file and in iOS's |
| `bash tools/wsl-build.sh check` | exit 0, 105 s. The VPN engines rebuilt; the code compiles: 1008 classes |
| `bash tools/wsl-build.sh apk` | exit 0, 110 s. `core: tree 6aeb359d095b, Rust 1.92.0, NDK 27.2.12479018, arm64-v8a`. Output `Montana-9844b50-arm64-v8a.apk`, 39 528 089 bytes, SHA-256 `731edb99be9ee77775829ce426b97b3f1edab707f4f8c23167e360ab285d501c` |
| `bash tools/verify-apk.sh out/Montana-9844b50-arm64-v8a.apk` | exit 0. Signature v2 + v3 (debug certificate), `quest.montana.app.dev`, arm64-v8a, `zipalign -c -P 16 4` OK, every library LOAD-aligned to 16 KiB, 41 JNI functions |
| `bash tools/wsl-build.sh test-jni` | exit 0. 20 passed, 0 failed |
| `bash tools/wsl-build.sh test-core` | exit 0, 694 s. 455 passed, 0 failed, 0 ignored, against the core's tree `6aeb359d095b`. Run on folder tree `3eb818d8d2e1` (commit `6e8e34a`), which differs from this one only by the wording of two lines of `measuredelay_test.go`; the same steps there gave the same results, and an APK with the same SHA-256 |

The APK was not installed or started, and no delay was measured against a real server.

**On folder tree `4a40ba2312bc`**, after the author field's self-check was fixed, on commit `8244d8e`. The checks ran
from a plain clone in WSL, with a build copy of its own. This README's update came afterwards and changes nothing that is
built.

| Command | Result |
|---|---|
| `bash tools/author_canon_check.sh` | exit 0, 7 s. `author_vectors.py` gives the frozen values over the secret and over the root (`authorTag(root)` `7guflqG5E43OLPFovkhhWg==`, `withAuthor(head, root)` `fcfc401b…`, `withAuthor(card, root)` `544da6e5…`); `author_canon: ok=13 bad=0` |
| `bash tools/wsl-build.sh check` | exit 0, 97 s. `Montana 1.0 (348 → 1277)`; the code compiles: 1008 classes |
| `bash tools/wsl-build.sh apk` | exit 0, 117 s. Output `Montana-8244d8e-arm64-v8a.apk`, 39 528 089 bytes, SHA-256 `95b5a74eac4001f4f5e788b55b2fd90f936f340089613668681f266db36b9087` |
| `bash tools/verify-apk.sh out/Montana-8244d8e-arm64-v8a.apk` | exit 0. Signature v2 + v3 (debug certificate), `quest.montana.app.dev`, versionCode 348, minSdk 26, targetSdk 35, arm64-v8a. `zipalign -c -P 16 4` OK, every library LOAD-aligned to 16 KiB, 41 JNI functions |

Not run on this tree: `test-jni`, `test-core`, `lzfse_check.sh`, the identity reference and the other vector tools; the
change touches none of the files they check. The APK was not installed or started, so the launch log's `author_canon ok`
has not been read on a device, before or after 29.10.2026.

**On folder tree `441322aca813`**, after the words left the system backup, on commit `e3bc335`. The checks ran from a
plain clone in WSL, with a build copy of its own.

| Command | Result |
|---|---|
| `bash tools/wsl-build.sh check` | exit 0, 119 s. `Montana 1.0 (336 → 1277)`; the code compiles: 1004 classes |
| `bash tools/wsl-build.sh apk` | exit 0, 171 s. Output `Montana-e3bc335-arm64-v8a.apk`, 39 528 089 bytes, SHA-256 `5e53284835ede8dd99836288adfc19d73c447470fc79dbb4c6629e0a12ee7c8b`. The same compiler warning as below |
| `bash tools/verify-apk.sh out/Montana-e3bc335-arm64-v8a.apk` | exit 0. Signature v2 + v3 (debug certificate), `quest.montana.app.dev`, versionCode 336, minSdk 26, targetSdk 35, arm64-v8a. `zipalign -c -P 16 4` OK, every library LOAD-aligned to 16 KiB, 41 JNI functions. The manifest names `WithdrawBackupAgent`; `classes.dex` holds it, and neither `SeedBackupAgent` nor `MontanaBackupID` |

Not run again on this tree: `test-jni`, `test-core`, `lzfse_check.sh`, the identity reference and the vector tools. The
change touches none of the files they check. The APK was not installed or started, and no backup or restore was made.

**Earlier, on commit `739f8bdc004c`** (folder tree `7b11aebe861f`), the same way. That commit is not in this branch's
history: the branch's first commit (folder tree `dd856e6460c9`) differs from it only by two comments reworded in English
(`CoinChain.kt` lines 19-20, `CoinLocalTest.kt` lines 8-9). No code changed from there up to folder tree `372e43755838`.

| Command | Result |
|---|---|
| `bash tools/wsl-build.sh check` | exit 0, 125 s. `Montana 1.0 (323 → 1277)`; the code compiles: 1007 classes |
| `bash tools/wsl-build.sh test-jni` | exit 0, 75 s. 20 passed, 0 failed |
| `bash tools/wsl-build.sh apk` | exit 0, 189 s. `core: tree 4ce3d6705224, Rust 1.92.0, NDK 27.2.12479018, arm64-v8a`. Output `Montana-739f8bd-arm64-v8a.apk`, 39 544 473 bytes, SHA-256 `b1345836f7e001f8c85fe590b694ebe3e98caaef1b11c203daf8705f602b1c79`. One compiler warning: an unneeded `mut` at `native/montana-jni/src/lib.rs:340` |
| `bash tools/verify-apk.sh out/Montana-739f8bd-arm64-v8a.apk` | exit 0. Signature v2 + v3 (debug certificate), `quest.montana.app.dev`, versionCode 323, minSdk 26, targetSdk 35, arm64-v8a. `zipalign -c -P 16 4` OK, every library LOAD-aligned to 16 KiB, 41 JNI functions |
| `cargo +1.92.0 build --release` in `tools/identity-ref` (build copy) | exit 0 |
| `bash tools/lzfse_check.sh` | exit 0. 895 ok, 0 bad, 465 damaged streams refused; the reference opened all 87 Kotlin streams |
| `bash tools/wsl-build.sh test-core` | exit 0, 455 s. 455 passed, 0 failed, 0 ignored |
| `python -I tools/vectors_check.py`, `tools/coin_vectors.py`, `tools/keep_vectors.py`, `tools/author_vectors.py` | exit 0 each: «all agree», «all hold», «all hold», and the author values equal to those then in `Pipes.kt` |

The APK was not installed or started for this publication.

## Deviations from the specification and from iOS

### From the specification (`core/docs`)

1. **No release, no published hash.** `Montana App.md:133` (conformance item 7) asks for a reproducible build and the
   hash of every release. No release of this app is published. The APK's content is fixed per commit (`scripts/build.py`
   fixes the zip times and modes), but the signature is the builder's own debug key, so APKs from two builders differ in
   their signature.
2. **Where the messenger's wire is defined.** The boxes, pipes, twin mirror and Coins v3 are defined by the iOS source and
   `Audit/App/COIN-TX-V3.md`, not by `core/docs`. The deviations below are therefore named against iOS.

### The words and the system backup

`Montana Identity.md:343` (conformance item 17) keeps the words out of backups and out of every path that leaves the
device, and iOS carries no seed in the Apple account (`MontanaAppleID.swift:4-8`). This app follows both since
2026-10-25; until then this was the first deviation from the specification.

- No file of the app is copied: `fullBackupContent="false"`, and `res/xml/data_extraction_rules.xml` excludes every
  domain, as before.
- The backup agent, `WithdrawBackupAgent` in `BackupWithdraw.kt`, writes no record, and at install it reads none. There is
  no switch, and the page of opening offers no seed from a backup.
- Earlier builds of this folder could write the words into the system backup when the person turned that on in Privacy
  (`BackupSeed.kt`, off by default). On such an installation, every start of the app asks the system for a backup while
  that build's switch or record name is still held. That backup withdraws every record the last backup held, so the copy
  no longer holds the words.
- The words on the device are not touched: the active seed in the vault, and a seed an earlier build brought from a
  backup, both stay where they are.
- `main`'s `apps/messenger/android` made the same change in build 547 (`c7270dd`, `main`'s commit). It keeps the names `BackupSeed.kt` and
  `SeedBackupAgent`, asks for the withdrawing backup once, and deletes from the vault a seed an earlier build brought from
  a backup (`BackupSeed.kt:38` there); this app keeps that seed.

Not run: no backup or restore was made on an emulator with this build (`adb shell bmgr`).

### From iOS

1. **When a twin row is confirmed.** iOS 2305 confirms a row of the twin's pipe as soon as it takes it
   (`MontanaPQ.swift` 951-960 at upstream commit `3926188`). This app confirms it only once its road has come whole,
   with five tries at most, as the Windows app does (`twin.rs`). On the wire the two are compatible.
2. **Which rows a device gives back.** Asked for rows, a device here gives back every row it holds under the keys asked,
   as the Windows app does. iOS 2305 gives back only rows it wrote, by their `mid:` names (`ChatStore.giveTwinRows` and
   `takeTwinRow`, 3212-3266).
3. **The author field on the live frame.** The live frame carries the author field. This is an Android extension: iOS's
   live frame has seven fields (`MontanaPhoneNode` 899-917 at iOS 2232) and reads them unchanged.
4. **Coins.** Writes to the live chains are off. The GENESIS record asks the person first, where iOS opens the chain
   without a question, and it waits for the coin vault's answer.
5. **Platform storage and background.** The words at rest are in Android Keystore (AES-256-GCM) rather than the iOS
   Keychain. The background work is a foreground service rather than APNs, PushKit and the Notification Service
   Extension.
6. **Holes in the archive's log (D27).** A hard power-off can leave holes of zeros in the archive's log, and this app reads
   across them. The core's own reader (`core/Code/crates/mt-messenger-e2e/src/archive.rs:345-364`) has no such step. That
   is a recommendation for the core: the core is not changed here.
7. **Cleartext to one address.** Cleartext HTTP is allowed to 10.0.2.2 only (`res/xml/network_security_config.xml`). It
   serves a check's own node, and only when a file that the emulator's root lays in the app's own folder names that node
   (`Doors.kt`, `testDoor`). Every other door is TLS.
8. **The VPN wall.** Each difference here is forced by the platform:
   - it is a VpnService in the app's own process, where iOS uses a Network Extension (`protect_android.go`);
   - the packet pump takes up to 128 sessions, where iOS takes 32 because of the extension's 50 MB limit;
   - TrafficStats is the witness of another VPN;
   - there is no witness of the system's «path not satisfied»;
   - the subscription headers say Android;
   - a row is renamed by its identity, because iOS `doRename` writes by an index of another list;
   - on Android 13 and later the local network is excluded with `excludeRoute`.
9. **Calls.** An incoming call is shown as a full-screen notification. There is no ConnectionService, the counterpart of
   iOS CallKit. iOS 2307 and 2308 are not ported.
10. **The native library.** `libmontana.so` is built from this repository's `core/` (tree `6aeb359d095b` since 2026-10-26;
    `4ce3d6705224` before). The project's
    Android build pins instead the private core commit `ae36d1f927a7` (`apps/messenger/android/native/montana-jni/Cargo.toml`
    names `../../../Montana Protocol`). The library is therefore not byte-identical to the one in the project's APK of
    build 411. Its tests compare every JNI function with the C function iOS calls.
11. **The application id.** Package `quest.montana.app.dev` with a debug key: see [Installing](#installing).
12. **The version.** `scripts/version` makes the build number the repository's commit count, so in this repository the
    app shows `1.0 (<commits> → 1277)`, for example `1.0 (336 → 1277)` in the build of `e3bc335`.

## Cryptography that is not Montana's own

Montana's own protection is ML-DSA, ML-KEM and SHA-256, through the core. Everything below is there because an
external standard or the platform demands it, and none of it is counted as Montana's protection:

- TLS on the node doors (inside it, the Noise_PQ XX channel is Montana's);
- WebRTC DTLS-SRTP for calls, as on iOS;
- the VPN's own protocols (VLESS and REALITY, TLS, WireGuard, Hysteria and the others Xray-core speaks);
- SHA-1 in the WebSocket handshake (RFC 6455, `Ws.kt`);
- HMAC-SHA-1 for one-time codes (RFC 6238, `Passwords.kt`);
- AES-256-GCM of Android Keystore for the vault at rest (`Identity.kt`);
- RSA-2048 for the APK signature, which is the platform's admission to install.

The backup frames are sealed with ChaCha20-Poly1305, as on iOS (`.mtbak` v2).

## Not run, open questions

- **No iPhone.** Nothing has been checked live with iOS.
- **No physical Android phone.** Only emulators (Android 14, x86-64) have run the app.
- **Coin writes.** The build with writes (`apk --coin-writes`) has never been launched.
- **The pipe secret's step.** It has not been checked on the real date, after 2026-10-29 00:00 UTC.
- **Later iOS builds.** iOS 2307 and 2308 (call echo, a dead ring's receipt) are left to the project's Android line.
  iOS 2309 to 2311 have not been compared yet.
- **Comments that cite other files.** Comments citing `docs/BUILD.md`, `docs/calls.md` or
  `docs/core-note-entropy-to-mnemonic.md` come from upstream's Android tree, which does not publish those files either.

## The VPN engine's delay measure

`MeasureDelay` in `native/montana-xray/montanaxray.go` used to say that it was ported from 2dust/AndroidLibXrayLite
(`libv2ray_utils.go`) under MPL-2.0, while that repository's licence is LGPL-3.0. On 2026-10-26 the code was replaced:

- `MeasureDelay` was written anew from its behaviour alone. It brings the outbound up in an engine that listens on
  nothing, fetches the 204-endpoint through it, takes the smaller of two attempts, and binds the probe's sockets to the
  interface it is given. Each attempt is a fresh connection with its own limit (5 s) inside the call's bound (8 s). A
  missing interface is refused before anything is dialled, and the error names what each attempt met. The "Ported from"
  lines are gone.
- `delayVia`, the batch path's measure, now rides the same helpers on the outbound its tag names.
- The two filters of a loaded config, `MeasureUDP`'s and `batchInstance`'s, are one helper of this file:
  `probeOutboundsOnly`.
- An independent comparison with that library (commit `76a6e2172210`) found the new `MeasureDelay` independent of it.
  It found `delayVia` and the two filters derived, so both were replaced too.
- A token comparison with the LGPL file finds only overlap at the level of the engine's API and Go idioms: 84 runs of 8
  tokens, against 217 in the old file.
- `native/montana-xray/measuredelay_test.go` drives `MeasureDelay` and `MeasureMany` through a real engine against local
  servers. Its results are under [Run for this publication](#run-for-this-publication-2026-10-25-utc).
- `go.mod`, `go.sum` and `protect_android.go` are unchanged. iOS's `apps/messenger/ios/scripts/xray-ios/montanaxray.go`
  still carries the earlier code, so this file no longer equals it.

## Third-party components and licences

| Component | Version | Licence |
|---|---|---|
| WebRTC (`io.github.webrtc-sdk:android`) | 144.7559.15 | BSD-3-Clause |
| Xray-core | v1.260327.0 | MPL-2.0 |
| gomobile (`golang.org/x/mobile`) and Go | Go 1.26.8 | BSD-3-Clause |
| hev-socks5-tunnel | 2.18.0 | MIT |
| Kotlin standard library | 2.0.21 | Apache-2.0 |
| The Rust crates of `native/montana-jni/Cargo.lock` | | their own licences |

- `setup.py` downloads WebRTC and pins it by SHA-256. Only WebRTC's classes and its arm64 library go into the APK.
- Xray-core is bound with gomobile and Go.
- `Lzfse.kt` follows the lzfse 1.0 reference step for step (Apple Inc., BSD-3-Clause).
- The core (`core/`) is MIT OR Apache-2.0.
- The repository names no licence for `apps/messenger/android`, from which this folder grew. The right to redistribute
  the application code rests with the project's author.

## Left out of this folder

| What | Why |
|---|---|
| The local repository's `core/` | This folder builds from `main`'s `core/` (tree `6aeb359d095b`, pinned in `scripts/toolchain.json`), and a platform branch does not change `core/` |
| The local repository's `docs/` (13 files) | Internal working notes (journal, parity table, test programme, coin notes, the iOS watch's state and reports). Their facts are in this README |
| The local repository's own `README.md` and `UPSTREAM.md` | Replaced by this README; the provenance is above |
| `tools/ios-watch/` and `.github/workflows/ios-watch.yml` | The watcher reads this repository from outside it, and it keeps its state in the internal notes that are not published. GitHub runs no workflow from a subfolder, and at the root this one would open issues and push to `main` |
| `out/` (APKs, logs, screenshots, test identities' words) | Build output and local test data, never committed (`.gitignore`) |
