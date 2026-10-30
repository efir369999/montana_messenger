# Releases

This file names what each folder of this repository is and which binaries were published from it. The table Sources is
written by the publisher in the same commit as the folder it names; the rest is written by hand.

## Sources

Each folder of this repository is the tree of one commit of the project's private history, staged as it is built. The
publisher writes this table in the same commit as the folder it names, and the message of that commit names the source
commit in full. The column Folder tree is the git tree of the folder in the commit that carries the table:
`git rev-parse HEAD:FOLDER` answers it, so a reader pins the exact bytes under review without the private history. What that
does and does not establish is in [`AUDIT.md`](AUDIT.md), section 3.

<!-- sources:start -->
| Folder | Build | Source commit | Folder tree | Staged |
|---|---|---|---|---|
| `apps/messenger/android` | 552 | `e8e25d01c77e` | `af8316a93370d0a6bdafc3b74e58f2578e832839` | 2026-10-26 10:03 UTC |
| `apps/messenger/ios` | 1.0 (2322) | `186237067ba2` | `a7809823eca6241a9be4c904e7d5ed4c64214732` | 2026-10-30 00:02 UTC |
| `core` | not built (branch agent-742/issue-22-k2-silent-door with main 98d381b) | `a44b4e6455f4` | `d592442ec469fdc2cdc965348488009c6e9243c6` | 2026-10-30 06:53 UTC |
<!-- sources:end -->

## Binaries

Each GitHub release of this repository carries `Montana-Messenger.ipa` (Montana for iPhone, iPad and Mac) and
`SHA256SUMS.txt`, and its notes name the build of the IPA, its SHA-256 and the folder tree of its source; the tag of the
release is the commit of this repository whose trees those are. No release carries `Montana-Messenger.apk`: the 75
releases, `v1.0-2221` (2026-10-16) to `v1.0-2315` (2026-10-27), hold those two files and no other (GitHub API, read
2026-10-27 UTC). Montana for Android is served by the site: `https://montana.quest/download/android/latest.json` names its
build, commit and SHA-256.
The IPA is the export uploaded to the App Store, signed for distribution there: it is published to be read, compared with the
source or re-signed, and it installs through TestFlight. The APK is signed with the project's Android key and installs on
Android 8 or later; the key is RSA-4096, the platform's admission for installing a package and not a security property of
Montana, and its certificate (CN=Montana, O=Montana Network) has the SHA-256 fingerprint
`CE:95:D6:81:D0:D0:DE:4C:10:84:B1:D1:98:5D:E7:9A:79:CC:16:C3:DB:2B:11:04:D2:33:7C:FA:2C:14:08:A7`, read from the APK of build 411
(`keytool -printcert -jarfile Montana-Messenger.apk`).

A release of 2026-10-08 was prepared and not created. Its files are listed here with their digests for whoever holds them:

| File | Application | Version | SHA-256 | Source |
|---|---|---|---|---|
| `Montana-Messenger.ipa` | Montana, iPhone, iPad, Mac | 1.0 (2165) | `72fb193070cb6f523811d015efbab12aa55f7a44013c61589b38e65d1e66bc14` | `apps/messenger/ios`, commit `7b405422`; the build is commit `862261a1`, which differs in the comments of `Code/Montana/nodes.txt` only |
| `Montana-Messenger.apk` | Montana, Android | 1.0 (246) | `41de6e3eb8db810286629e36e1ded140f090d5885eff98af900f948c13b924bd` | `apps/messenger/android`, commit `67f144ec`; historical (marked 2026-10-27 UTC): build 246 of the release of 2026-10-08 that was not created, an asset no GitHub release of this repository carries; the current Android build is the `apps/messenger/android` row of Sources above |
| `Montana-Wallet.ipa` | MT Wallet, iPhone, iPad, Mac | 1.0 (5) | `14084ed4b55c78ab9545ee5f48daf6afb2960049f632e3c9ebb7c5bb55a18003` | `apps/wallet/ios`, commit `07047617`; MT Wallet is retired from this repository |

## Retired folders

On 2026-10-11 the repository was narrowed to the protocol core and Montana for iOS and Android. The folders below left the
tree; each stays in the history of this repository, and its last tree is the tree of the folder at commit `f10268c`.

| Folder | Application | Last build | Last source commit | Last folder tree |
|---|---|---|---|---|
| `apps/wallet/ios` | MT Wallet, the coins of time; retired | 18 | `d1352a88ba64` | `19fb59d10be1af5a510b92cfce836d9b6be09ff7` |
| `apps/mesh/ios` | MT Mesh, rooms over Bluetooth Low Energy; retired | 3 | `9d9eaa61456d` | `fc9030b76d411262686b2b0726c796c17ff8f0f2` |
| `apps/p2p/ios` | MT P2P, delivery from phone to phone; retired | 2 | `9652b512bced` | `5d9a01282c81898803d9986b13af75dce75b3299` |
| `apps/vpn/ios` | MT VPN, a VPN client; retired, its client is part of Montana for iOS from build 2180 | 3 | `298b7dc88d0c` | `5d84618b3297051369a310c91c733ea3f9dd711f` |
