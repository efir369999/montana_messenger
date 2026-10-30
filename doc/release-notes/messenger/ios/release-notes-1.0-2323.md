1.0 (2323) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2323), from source commit `829d29f2d5a45b7a3b076324c2e92f3d8e1f4c90` of 2026-10-30. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- When your contact's phone renews the secret of your private conversation, yours follows: it takes the renewal letters, checks them and opens the messages sealed under the new key. This phone does not start a renewal of its own yet.

Security and anonymity
----------------------

- The heal of a pipe (issue #75, Montana Network) is received and opened as the Canon defines it: the phone checks its computation of the renewed keys against the Canon's frozen vectors at start and opens nothing under a computation that disagrees. It sends no heal of its own until the devices of one seed carry one heal between them (the Author's decision 416 a). No new address, server, key kind or network road is added.
