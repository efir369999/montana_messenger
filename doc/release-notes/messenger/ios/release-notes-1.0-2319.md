1.0 (2319) Release Notes
========================

Montana for iPhone, iPad and Mac, build 1.0 (2319), from source commit `5068b59c0575b39154bfbb0bf0fcf44ddbc2222b` of 2026-10-29. The folder `apps/messenger/ios` of this repository holds that tree as it is built.

Notable changes
---------------

- Calls no longer credit or take coins: a call's seconds mint nothing and burn nothing, and no coin receipt stands under a call. Coins are born only by the network's core, one coin a second.
- Chess no longer credits or takes coins: no coins for moves, no stakes, no pot and no winnings. Coins are born only by the network's core, one coin a second.
- The captured pieces beside each player are all drawn at the same size, in the board's own artwork.
- A first message that arrives as a long letter is shown with its words, and a service message is never shown as a chat bubble.

Security and anonymity
----------------------

- Security and anonymity are unchanged. Chess letters no longer carry any coin field; a letter of an earlier build is read without its coin fields. A call writes no coin and lays no burn on the coin chain; the call's row keeps only its name and seconds. No new address, key or network road is added.
