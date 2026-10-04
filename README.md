<p align="center">
  <img src="https://montana.quest/download/icon.png" width="132" alt="Montana">
</p>
<h1 align="center">Montana</h1>
<p align="center">Letters, calls, chess and coins of time, sealed end to end. No phone number, no e-mail: 24 words are your account.</p>
<p align="center">
  <a href="https://testflight.apple.com/join/BHaSYWkz"><img alt="iPhone and iPad on TestFlight" src="https://img.shields.io/badge/iPhone%20·%20iPad-TestFlight-D4AF37?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://testflight.apple.com/join/BHaSYWkz"><img alt="Mac with Apple silicon on TestFlight" src="https://img.shields.io/badge/Mac-Apple%20silicon-C9A227?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>
<p align="center"><a href="https://montana.quest">montana.quest</a> is the main site · mirrors <a href="https://montana.xxx">montana.xxx</a> and <a href="https://efir.org">efir.org</a></p>

## Download

| Where | How |
|---|---|
| iPhone, iPad (iOS 17.2 or later) | [TestFlight public link](https://testflight.apple.com/join/BHaSYWkz): the recommended way |
| Mac with Apple silicon | The same [TestFlight link](https://testflight.apple.com/join/BHaSYWkz), opened on the Mac |

## About

Montana is an end-to-end encrypted messenger built on post-quantum cryptography. It runs on iPhone, iPad and Apple
silicon Macs. There is no phone number and no e-mail account: a person signs in with a 24-word recovery phrase, and a
contact is added by their Montana address.

This repository is the public face of the release programme: the downloads, the release history, how to join the test
track, what to test, how to report what you find, the security policy. The
application is one implementation of the Montana protocol; the reference client is developed at
[montana.quest](https://montana.quest).

## What is in this repository

| Path | What it is |
|---|---|
| [RELEASES.md](RELEASES.md) | Every build published on TestFlight |
| [CHANGELOG.md](CHANGELOG.md) | Published builds and the timestamped development event log |
| [SECURITY.md](SECURITY.md) | How to report a weakness, and what is in scope |
| [.github/](.github/ISSUE_TEMPLATE/bug_report.md) | The bug report template |

Montana's source code is not published; this repository carries the public record of its releases and changes.

## Join the beta

| | |
|---|---|
| Platform | iPhone and iPad with iOS 17.2 or later; Apple silicon Mac |
| Distribution | TestFlight, public link; App Store (United States) |
| Link | https://testflight.apple.com/join/BHaSYWkz |
| App Store | 1.0; the most recent build submitted for review is 1666 (2026-09-17) |
| TestFlight | 1.0; the newest build is 2090 (2026-10-03) |
| Feedback | GitHub Issues in this repository, or contact@montana.quest |
| Privacy policy | https://montana.quest/privacy/ |

1. Install TestFlight from the App Store.
2. Open the link above on the device and accept the invitation.
3. Install Montana and create an identity. Write the 24 words down: they are the only way
   back into the account, and nobody can restore them for you.
4. To talk to someone, exchange Montana addresses (Settings → your address) and add the
   contact by address.

A build appears on the public link after it has passed Apple's Beta App Review, which takes
from a few hours to a day after upload. Development builds newer than the TestFlight build
run on the project's own test devices only; see *Latest changes*.

## What the application does

- Text, photos, video, files and voice messages.
- Voice and video calls, including screen sharing.
- Live typing: the other side sees the text as it is typed.
- Delivery and read receipts, replies, reactions, editing, forwarding, deletion for everyone.
- Groups (local on the device in this beta; see *Known limits*).
- Direct delivery between two phones on one local network, over IPv6, or through a port
  the router forwards; otherwise through the Montana nodes.

## What protects a conversation

| Layer | Primitive |
|---|---|
| Identity and signatures | ML-DSA-65 |
| Key agreement | ML-KEM-768 |
| Message content | ChaCha20-Poly1305 under the session key |
| Hashing | SHA-256 |
| Call media | SFrame with a key derived from a call seed carried inside the encrypted envelope; DTLS-SRTP is transport admission only |

ML-DSA-65 and ML-KEM-768 come from the Montana core, a Rust library checked against the NIST test vectors.
The nodes forward sealed envelopes and never hold a key that opens them.

## Coins and the Economy of Time

Montana counts coins of time on the phone. Every source of coins keeps its own time chain: one link per move of coins,
numbered, stamped in milliseconds and sealed by SHA-256 over the link and the seal before it, so a changed or moved link
breaks every seal after it. The wallet shows every chain, its length, its head and whether every seal holds, and every
move in the history says where it came from and where it went.

| Source | How it mints or burns |
|---|---|
| Pantheon on Fire | Every touch and every swipe over the wallet's coin mints one coin, up to thirteen a second |
| Chess | Every move pays one coin to each player; the winner takes the whole sum of the game |
| Timer | Chess at one board on one phone: the player who waits mints a coin a second |
| VPN Wall | While your own VPN stands on your wall, every second mints a coin |
| Chats | With the coin on, every letter of the pair mints a coin |
| Calls and letters | A call burns a coin a second and a letter a coin while it rides Montana's nodes, never more than the balance holds |
| Levels of π | The balance reveals π digit by digit; every new level joins its own chain |

In this beta the coins are a local tally on the phone, not a note of the Montana core's wallet.

## Diagnostics

The application sends its diagnostic journals (event records, timings, error codes, crash and
hang reports, the device model, the iOS version and the application build) to the Montana
diagnostics node, where they are kept for seven days and then deleted. [SECURITY.md](SECURITY.md)
is the place for the details.

## What to test

Please exercise the everyday paths and report anything that deviates from the expected
observation:

1. **Delivery.** A message sent while the other phone is online arrives within seconds
   and shows two ticks on the sender's side. A message sent while the other phone is offline
   arrives when it comes back.
2. **Network changes.** Switch Wi-Fi off and on, move to cellular, turn a VPN on and off.
   Messages keep flowing and the typing indicator keeps working without a restart.
3. **Media.** Photos, videos (including long ones), voice messages and documents arrive
   whole and open. A forwarded photo or video arrives at the new recipient.
4. **Calls.** A voice call stays a voice call (the chat records it as voice, not video);
   a minimised call shows a green and a red handset beside the contact's name and never
   covers the name.
5. **Presence.** "Online", "last seen" and "on a call" reflect what the other person is
   actually doing.
6. **Recovery.** Delete the application, reinstall, enter the 24 words: the identity and
   the address are the same.

## How to report

Open an issue with the *Bug report* template. The report is most useful when it names:

- the build number (Settings → About), the device model and iOS version;
- the network on each side (Wi-Fi, cellular, VPN on or off);
- the exact time of the event and what was expected instead;
- whether the message, file or call was affected on one side or on both.

Do not paste recovery phrases, Montana addresses of other people, or message content into
an issue. Weaknesses go by e-mail, not into an issue: see [SECURITY.md](SECURITY.md).

## Known limits of this beta

- History lives on the device; the Montana nodes never hold it. Deleting the application
  erases the history on that device. Two copies can be turned on in the application, and both
  are off until you turn them on: a copy in the application's own iCloud container, and a copy
  on a node you run yourself. Both are sealed under a key that only your 24 words open.
- Groups exist on the device only; a group message is not yet carried to the other members.
- Two phones that are both behind carrier NAT, without IPv6 and without a forwarded port,
  cannot reach each other directly and talk through the nodes.
- Inside the application, tapping the system's green call indicator on the status bar does
  nothing; the green handset beside the contact's name returns to the call. From another
  application the indicator opens Montana as usual.

## Latest changes

From [CHANGELOG.md](CHANGELOG.md).

| | |
|---|---|
| Log updated | 2026-10-03 12:20 UTC |
| Newest build in the log | Debug 2070, 2026-10-03 11:51 UTC |
| Latest build in the published list | 1.0 (2090), 2026-10-03, TestFlight |

- **2026-10-03 12:20 UTC** — The masters', the student's and the Government's TimeChain pages stay on this Mac (commit pending)
- **2026-10-03 11:51 UTC** — Build number 2070 (commit `81c5071679cb`)
- **2026-10-03 11:50 UTC** — The build's ring-1 guards stand green again (commit `4390eb8b6bac`)
- **2026-10-03 11:46 UTC** — One coin book behind MTCoinLedger (commit `d0f4af6cf685`)
- **2026-10-03 11:14 UTC** — The turned ribbon is the normal chat mirrored (commit `80d5275bece7`)

The full record of every change, with its build, system and source tree, is in the log.
