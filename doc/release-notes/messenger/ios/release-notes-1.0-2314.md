1.0 (2314) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2314), from source commit `df26a92dd9fe81fc4f79784960254c6a5c1e42ee` of 2026-10-26. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- The Time Coins page shows the minting as it happens: while you are in the app, your Time Balance rises every second with the seconds on their way to the network, before the window that confirms them is finalized; when the network confirms them the number moves on without a jump. The line Available beneath it, and what you can send, stay exactly what the network has confirmed.

Security and anonymity
----------------------

- Security and anonymity are unchanged: the rising seconds are shown and never spent, a transfer is weighed by the confirmed balance alone, and a minting record now counts only from the moment the person came into the app, so no second before their presence is claimed. Nothing new leaves the phone.
