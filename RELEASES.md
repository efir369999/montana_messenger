# Releases

Binaries are attached to the releases of this repository; on iPhone, iPad and Mac the applications install through
TestFlight. Each row names the folder that holds the source and the commit of the project's history that folder is.

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
