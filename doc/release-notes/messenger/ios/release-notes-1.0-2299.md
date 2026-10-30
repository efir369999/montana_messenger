1.0 (2299) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2299), from source commit `4d8b7da44672a158efcb9354a4d97e70d1bfb8cb` of 2026-10-23. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- From 26 October a call that is not recorded is paid on the time chain itself: its seconds are burned as one record at the head of your chain, once a window and at the end of the call.

Security and anonymity
----------------------

- The burn of a call waits on disk until the node accepts it, and the debt falls only by an accepted BURN; before the online cut of 25 October 21:00 UTC nothing is laid, since the node refuses a BURN until then.
