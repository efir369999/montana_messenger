1.0 (2306) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2306), from source commit `221bec73d642c6575dbfe25f2a0c403cd79ee7b8` of 2026-10-24. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- One person, many devices: a letter, a photo or a video is taken by each of your devices on its own, so the Mac fetching first no longer leaves the phone without it.

Security and anonymity
----------------------

- Security: the node marks a letter as taken per device under a per-label device name, so it links no two labels of one device; the sealed letter stays end-to-end encrypted and leaves the node at the box term. Anonymity is unchanged.
