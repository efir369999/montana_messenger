1.0 (2324) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2324), from source commit `d20b2d66826d1e03508be864b9f9e4b29a6dd574` of 2026-10-30. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- When your contact's phone renews the secret of your private conversation, yours follows: it takes the renewal letters, checks them and opens the messages sealed under the new key. This phone does not start a renewal of its own yet.
- The offer to update is now a small notice over the screen instead of a full page: it hides by itself after nine seconds, or close it with the cross in its top right corner. A touch on it opens the update.

Security and anonymity
----------------------

- The heal of a pipe (issue #75, Montana Network) is received and opened as the Canon defines it: the phone checks its computation of the renewed keys against the Canon's frozen vectors at start and opens nothing under a computation that disagrees. It sends no heal of its own until the devices of one seed carry one heal between them (the Author's decision 416 a). No new address, server, key kind or network road is added.
