1.0 (2321) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2321), from source commit `bf11ab0b1f5855c6f2eb4aa6bdc09d168f0a5cd8` of 2026-10-30. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- The app no longer counts coins of its own: letters in chats, taps on the wallet's coin, the VPN wall's seconds, the wallet's pull and the time away mint nothing on the device. Coins are born only by the network's core, one coin a second.
- The +1 that rose under a chat's field and at the finger on the wallet's coin is gone, since nothing is credited there.
- From 30.10.2026 12:00 UTC the app no longer asks the network to mint the seconds you are here, and the wallet no longer shows seconds on their way to such a minting: from that moment the network takes no such record.

Security and anonymity
----------------------

- Security and anonymity are unchanged. The device's coin book no longer writes earned lines; the lines written before are read as history. The VPN wall and the wallet's pull still tell the chain that the person is here, as before. From 30.10.2026 12:00 UTC the app lays no minting record on the coin chain. No new address, key or network road is added.
