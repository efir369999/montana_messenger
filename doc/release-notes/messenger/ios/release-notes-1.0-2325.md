1.0 (2325) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2325), from source commit `eea45ab8b3b47ad5a5d775a09a6db3f989910513` of 2026-10-30. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- The Time Balance rises again every second while you are in the network: the app is open or the Montana VPN is live. The available balance moves only when the core confirms the seconds at the close of a window.
- The core inside the app now carries the door through which a phone that holds nothing joins the running chain from two consecutive final proposals and checks every certificate itself. The app does not open this door yet.

Security and anonymity
----------------------

- Issue #20 (Protocol-13 item 9): the core framework of the client is built from montana_messenger main 2f5a1a2 and carries mtc_machine_join, the authenticated join that judges every certificate from an anchor and refuses a snapshot certified only by its own announced root. No new address, server, key kind or network road is added.
