1.0 (2308) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2308), from source commit `2d8a183d860e33dc09d8737ca3e6fa8cc437f74c` of 2026-10-24. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- A call that has already ended no longer keeps waking your device: the stale invitation is now confirmed to its sender, so it stops being sent again.

Security and anonymity
----------------------

- Security: the confirmation is the same end-to-end sealed receipt as for any letter and carries nothing about the call. Anonymity is unchanged.
