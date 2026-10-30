1.0 (2307) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2307), from source commit `d2cd1db9a2830eccefc1479ff67c0ec3e543d97a` of 2026-10-24. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Calls connect when one of the nodes is down: every call signal also goes through the other node at once.
- On the Mac, closing the last window quits the app.
- A conversation you erased no longer comes back to the device's storage at every launch.

Security and anonymity
----------------------

- Security: a call signal sent through a second node is the same end-to-end sealed packet, and the receiver drops repeats by its id; an erased conversation leaves no folder on the device. Anonymity is unchanged.
