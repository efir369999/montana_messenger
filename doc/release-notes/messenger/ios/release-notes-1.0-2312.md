1.0 (2312) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2312), from source commit `4c768afb86ebbd2c3f7f694005ea867c1fb6103d` of 2026-10-25. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Several files can now be chosen at once: they wait above the message field numbered 1, 2, 3 in the order you chose them, a cross takes one out and the numbers close up, and they are sent one after another in that order to a chat, a channel or a group, so a small file never overtakes a larger one. Messages, calls and coins work as before.

Security and anonymity
----------------------

- This build changes neither security nor anonymity: the chosen files are sent by the same encrypted road as before, only one after another in the chosen order; in a group with slow mode, a set of files sent together now counts as one message.
