1.0 (2316) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2316), from source commit `f6484629d89af4a914026cd60ae1ab6fc7609700` of 2026-10-29. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- When the network does not answer at the moment you open the wallet, the balance shows the last amount the chain confirmed for your key, not a lower local estimate. Your coins on the chain did not change.

Security and anonymity
----------------------

- Security and anonymity are unchanged: the last amount the chain confirmed is kept sealed in your own folder on this phone, next to the key it belongs to, and never travels. When the road to the chain fails, the diary now records the reply code and which of the two chain nodes was asked, never the key.
