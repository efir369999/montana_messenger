1.0 (2317) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2317), from source commit `3febd62ee04f499535f0b4962b4720e45ea166cd` of 2026-10-29. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Chess no longer credits or takes coins: no coins for moves, no stakes, no pot and no winnings. Coins are born only by the network's core, one coin a second.
- The captured pieces beside each player are all drawn at the same size, in the board's own artwork.
- A first message that arrives as a long letter is shown with its words, and a service message is never shown as a chat bubble.

Security and anonymity
----------------------

- Security and anonymity are unchanged. Chess letters no longer carry any coin field; a letter of an earlier build is read without its coin fields. No new address, key or network road is added.
