1.0 (2320) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2320), from source commit `c632039306e61ab0c71ece13a5e46dd3d2ed7331` of 2026-10-30. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- The app no longer counts coins of its own: letters in chats, taps on the wallet's coin, the VPN wall's seconds, the wallet's pull and the time away mint nothing on the device. Coins are born only by the network's core, one coin a second.
- The +1 that rose under a chat's field and at the finger on the wallet's coin is gone, since nothing is credited there.

Security and anonymity
----------------------

- Security and anonymity are unchanged. The device's coin book no longer writes earned lines; the lines written before are read as history. The VPN wall and the wallet's pull still tell the chain that the person is here, as before. No new address, key or network road is added.
