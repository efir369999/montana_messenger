# Releases

Binaries are attached to the releases of this repository; on iPhone, iPad and Mac the applications install through
TestFlight. Each row names the folder that holds the source and the commit of the project's history that folder is.

## Sources

Each folder of this repository is the tree of one commit of the project's history, staged as it is built. The publisher writes this table in the same commit as the folder it names; the message of that commit names the source commit in full.

<!-- sources:start -->
| Folder | Build | Source commit | Staged |
|---|---|---|---|
| `apps/mesh/ios` | 3 | `9d9eaa61456d` | 2026-10-10 11:51 UTC |
| `apps/messenger/android` | 403 | `e84c0d431538` | 2026-10-10 19:41 UTC |
| `apps/messenger/ios` | 2179 | `270009b93c9d` | 2026-10-10 19:28 UTC |
| `apps/p2p/ios` | 2 | `9652b512bced` | 2026-10-10 11:51 UTC |
| `apps/vpn/ios` | 3 | `298b7dc88d0c` | 2026-10-10 11:51 UTC |
| `apps/wallet/ios` | 17 | `371e8c39c386` | 2026-10-10 13:15 UTC |
| `core` | core line | `3848245e308b` | 2026-10-10 11:51 UTC |
<!-- sources:end -->

## 2026-10-08: the Montana Time ecosystem

| File | Application | Version | SHA-256 | Source |
|---|---|---|---|---|
| `Montana-Messenger.ipa` | Montana (Messenger), iPhone, iPad, Mac | 1.0 (2165) | `72fb193070cb6f523811d015efbab12aa55f7a44013c61589b38e65d1e66bc14` | `apps/messenger/ios`, commit `7b405422`; the build is commit `862261a1`, which differs in the comments of `Code/Montana/nodes.txt` only |
| `Montana-Messenger.apk` | Montana (Messenger), Android | 1.0 (246) | `41de6e3eb8db810286629e36e1ded140f090d5885eff98af900f948c13b924bd` | `apps/messenger/android`, commit `67f144ec` |
| `Montana-Wallet.ipa` | MT Wallet, iPhone, iPad, Mac | 1.0 (5) | `14084ed4b55c78ab9545ee5f48daf6afb2960049f632e3c9ebb7c5bb55a18003` | `apps/wallet/ios`, commit `07047617` |

The protocol core of these builds is [`core/`](core/), commit `013806d2` of the core's history.

The IPA files are the exports uploaded to the App Store, signed for distribution there: they are published to be read,
compared with the source or re-signed. The APK is signed with the project's Android key and installs on Android 8 or
later.

## TestFlight

| Build | Date (UTC) |
|---|---|
| Montana 1.0 (2165) | 2026-10-08 |
| Montana 1.0 (2091) | 2026-10-04 |
| Montana 1.0 (2090) | 2026-10-03 |
| Montana 1.0 (2081) | 2026-10-03 |
