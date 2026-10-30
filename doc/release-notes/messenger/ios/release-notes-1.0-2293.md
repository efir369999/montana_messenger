1.0 (2293) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2293), from source commit `057f2d1ec42dc182f5080dc55a5e182eda6b90c9` of 2026-10-23. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Coins follow the new rule of the time chain: from 25 October 21:00 UTC a mint counts only the seconds you are present in Montana, and a burned coin is a record of the chain like any other spend.
- The gold page ground is gone; a page that used it now shows Montana's own dark ground with its pattern.

Security and anonymity
----------------------

- The phone folds its coin chains by the same rules as the nodes (fold-7), so the balance it shows is the one the nodes compute; a burn is a signed record the nodes read. Nothing new is sent.
