# Montana Messenger

Montana Messenger is an end-to-end encrypted messenger for iOS built on post-quantum
cryptography. There is no phone number and no e-mail account: a person signs in with a
24-word recovery phrase, and a contact is added by their Montana address.

This repository is the public face of the release programme: the release history, how to
join the test track, what to test, and where to report what you find. Release 1.0 is build
1344; it goes to the App Store in the United States and stays on TestFlight for testers. The application is one implementation of the Montana
protocol; the reference client is developed at [montana.quest](https://montana.quest).

## Join the beta

| | |
|---|---|
| Platform | iPhone, iOS 17.2 or later |
| Distribution | TestFlight, public link |
| Link | https://testflight.apple.com/join/BHaSYWkz |
| Current release | 1.0 (build 1400) — App Store, in review; TestFlight 1.0 (build 1430), uploaded 2026-09-10 |
| Feedback | GitHub Issues in this repository, or contact@montana.quest |
| Privacy policy | https://montana.quest/privacy/ |

1. Install TestFlight from the App Store.
2. Open the link above on the iPhone and accept the invitation.
3. Install Montana and create an identity. Write the 24 words down: they are the only way
   back into the account, and nobody can restore them for you.
4. To talk to someone, exchange Montana addresses (Settings → your address) and add the
   contact by address.

A build appears on the public link after it has passed Apple's Beta App Review, which takes
from a few hours to a day after upload.

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
| Session between two phones | ML-KEM-768 sealed box (Noise_PQ XX to the holding node) |
| Message content | ChaCha20-Poly1305 under the session key |
| Hashing | SHA-256 |
| Call media | SFrame with a key derived from a call seed carried inside the encrypted envelope; DTLS-SRTP is transport admission only |

The nodes forward sealed envelopes and never hold a key that opens them. The cryptographic
core is a single Rust library shared by every Montana target; the client carries no
cryptography of its own.

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

- the build number (Settings → About), the iPhone model and iOS version;
- the network on each side (Wi-Fi, cellular, VPN on or off);
- the exact time of the event and what was expected instead;
- whether the message, file or call was affected on one side or on both.

Do not paste recovery phrases, Montana addresses of other people, or message content into
an issue.

## Known limits of this beta

- History lives on the device only and is never sent to a server or a platform backup.
  Deleting the application erases the history on that device. From build 1348, "Forget this
  device" keeps the sealed archive and the same 24 words bring the conversations back; a
  conversation whose key was lost before that build returns as readable history only.
- Groups exist on the device only; a group message is not yet carried to the other members.
- Two phones that are both behind carrier NAT, without IPv6 and without a forwarded port,
  cannot reach each other directly and talk through the nodes.
- Inside the application, tapping the system's green call indicator on the status bar does
  nothing; the green handset beside the contact's name returns to the call. From another
  application the indicator opens Montana as usual.

## Release history

See [CHANGELOG.md](CHANGELOG.md).
