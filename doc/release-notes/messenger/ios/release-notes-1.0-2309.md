1.0 (2309) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2309), from source commit `8439bb0f4306124b0f2d6e8c3ae24323b2c6a605` of 2026-10-25. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- The secret of each conversation now lives in one place inside the app and is never handed out: every part of the app, the notification extension and the share sheet ask that one place for what they need. Messages, calls and coins work exactly as before.

Security and anonymity
----------------------

- Security: one owner holds the conversation secret and exposes only derived values; a build check refuses any read of the raw secret elsewhere. The wire is unchanged byte for byte. Erasing the original secret by day is the next step and is not in this build.
