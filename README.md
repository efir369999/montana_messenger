# Montana Messenger

Montana Messenger is an end-to-end encrypted messenger built on post-quantum cryptography. It runs
on iPhone, iPad and Apple silicon Macs. There is no phone number and no e-mail account: a person
signs in with a 24-word recovery phrase, and a contact is added by their Montana address.

This repository is the public face of the release programme: the release history, how to join the
test track, what to test, how to report what you find, the security policy, and the source of the
Montana full node. The application is one implementation of the Montana protocol; the reference
client is developed at [montana.quest](https://montana.quest).

## What is in this repository

| Path | What it is |
|---|---|
| [CHANGELOG.md](CHANGELOG.md) | Published builds and the timestamped development event log |
| [SECURITY.md](SECURITY.md) | How to report a weakness, and what is in scope |
| [node/](node/README.md) | The Montana full node in Docker, with its Rust source, including the post-quantum primitives and their NIST test vectors |
| [verify.py](verify.py) | Checks a TimeChain file link by link from genesis, with the Python standard library alone |
| [tools/readme-sync.py](tools/readme-sync.py) | Regenerates the *Latest changes* section below from CHANGELOG.md |
| [.github/](.github/ISSUE_TEMPLATE/bug_report.md) | The bug report template |

The source of the iOS application is not published here.

## Join the beta

| | |
|---|---|
| Platform | iPhone and iPad with iOS 17.2 or later; Apple silicon Mac |
| Distribution | TestFlight, public link; App Store (United States) |
| Link | https://testflight.apple.com/join/BHaSYWkz |
| App Store | 1.0; the most recent build submitted for review is 1666 (2026-09-17) |
| TestFlight | 1.0; the newest build uploaded is 2022 (recorded 2026-09-30) |
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

ML-DSA-65 and ML-KEM-768 come from the Montana core, a Rust library; their source and the NIST
test vectors they are checked against are in [node/Code/crates/mt-crypto-native](node/Code/crates/mt-crypto-native).
The nodes forward sealed envelopes and never hold a key that opens them.

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

## The TimeChain verifier

`verify.py` re-checks a TimeChain file record by record from genesis: every record names the one
before it by its SHA-256 hash, so a reworded, moved or inserted record breaks every hash after it.

```
python3 verify.py TimeChain_Master.jsonl
```

The TimeChain files themselves are no longer published in this repository (the author's decision
of 3 October 2026); run without a file, the script prints its usage.

<!-- latest changes: generated by tools/readme-sync.py from CHANGELOG.md, do not edit by hand -->
## Latest changes

Generated from [CHANGELOG.md](CHANGELOG.md) by `tools/readme-sync.py`, in the same commit as the log.

| | |
|---|---|
| Log updated | 2026-10-03 12:20 UTC |
| Newest build in the log | Debug 2070, 2026-10-03 11:51 UTC |
| Latest build in the published list | 1.0 (1963), 2026-09-26, TestFlight |

- **2026-10-03 12:20 UTC** — The masters', the student's and the Government's TimeChain pages stay on this Mac (commit pending)
- **2026-10-03 11:51 UTC** — Build number 2070 (commit `81c5071679cb`)
- **2026-10-03 11:50 UTC** — The build's ring-1 guards stand green again (commit `4390eb8b6bac`)
- **2026-10-03 11:46 UTC** — One coin book behind MTCoinLedger (commit `d0f4af6cf685`)
- **2026-10-03 11:14 UTC** — The turned ribbon is the normal chat mirrored (commit `80d5275bece7`)

The full record of every change, with its build, system and source tree, is in the log.
<!-- latest changes end -->
