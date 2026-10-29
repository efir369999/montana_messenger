1.0 (2318) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2318), from source commit `ac6dcd5d6ca3903c35d4be05dc76770a7f0eb5c7` of 2026-10-29. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Calls no longer credit or take coins: a call's seconds mint nothing and burn nothing, and no coin receipt stands under a call. Coins are born only by the network's core, one coin a second.

Security and anonymity
----------------------

- Security and anonymity are unchanged. A call writes no coin and lays no burn on the coin chain; the call's row keeps only its name and seconds. No new address, key or network road is added.
