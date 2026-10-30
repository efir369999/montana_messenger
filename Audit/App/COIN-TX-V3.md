# Coin record v3 (MTTX, version 3) -- every move of a balance is a signed record of its key's chain

The author's words 11.10.2026 19:5x UTC (No.64): «balances must be proven; the core and the nodes are every device, our servers,
phones, tablets and so on; agreeing to keep a copy they keep a copy of the chain of time of the coins of the TimeChain, and the
Explorer shows the proof of it locally and globally across the network, a quorum, and the whole TimeChain is built for audit».
The constitution: article 0 «either the coins left or not -- there is no third», article 6 «the phone is a full node», article 11
«1 second -- 1 coin».

Version 2 ([COIN-TX-V2.md](COIN-TX-V2.md)) ordered a key's transfers in one chain on one node, but a balance stayed a claim of the sender's
book: the node took any amount, the Explorer said so («balances live in the senders' books»). Version 3 makes the balance the fold
of the key's chain: coins enter a key only by a record (MINT, RECV, REFUND), leave only by a record (SEND), and the chain's node
refuses a SEND above what the chain proves. Every node keeps a replica of every chain, every phone that agreed to keep a copy keeps
one too, and each signs the root of what it holds; the Explorer folds any key's whole chain in the browser and counts who signed
the same root.

## 1. Record (5443 bytes, little-endian integers)

- offset 0, 4 bytes, magic: ASCII MTTX
- offset 4, 1 byte, version: 0x03
- offset 5, 1 byte, kind: 1 SEND, 2 RECV, 3 MINT, 4 REFUND, 5 GENESIS, 6 BURN (fold-7); any other value is no record
- offset 6, 8 bytes, amount: u64, coins
- offset 14, 8 bytes, birth: u64, milliseconds since 1970-01-01 UTC, the signer's clock (shown, never counted)
- offset 22, 16 bytes, nonce: random
- offset 38, 32 bytes, prev: the id of the previous record of the same key's chain (a v2 or v3 record); 32 zero bytes for the first
- offset 70, 32 bytes, pair: SEND -- HMAC-SHA-256(key = the pair's pipe secret, message = ASCII mt-coin-pair-v1), as in v1 and v2;
  every other kind -- 32 zero bytes
- offset 102, 32 bytes, to: SEND -- SHA-256(ASCII mt-coin-to, 10 bytes, then from_receiver, 32 bytes, then blind, 32 bytes);
  RECV -- blind itself; every other kind -- 32 zero bytes
- offset 134, 32 bytes, ref: RECV and REFUND -- the id of the SEND they settle; every other kind -- 32 zero bytes
- offset 166, 8 bytes, t0: u64, MINT -- the first second of the minted interval (node seconds since 1970); SEND, RECV and BURN -- dec,
  the declared part of the amount (section 3); every other kind -- 0
- offset 174, 8 bytes, t1: u64, MINT -- the second after the last of the interval; every other kind -- 0
- offset 182, 1952 bytes, pubkey: the signer's ML-DSA-65 public key (the seed's mt-coin-tx key, as in v1 and v2)
- offset 2134, 3309 bytes, sig: ML-DSA-65 over ASCII mt-coin-tx-v3 (13 bytes) followed by bytes 0..2134

id = SHA-256(record); from = SHA-256(pubkey) -- as in v1 and v2. The id, from, prev, to and ref travel as lowercase hex.

blind = HMAC-SHA-256(key = K, message = ASCII mt-coin-blind, 13 bytes, followed by the SEND's nonce, 16 bytes), where K is the
pair's root, root = SHA-256(ASCII mt-conv-root, 12 bytes, 0x00, the secret the pair's first letter established), for a SEND laid on
a client day after the walk's anchor day (MTNodeWire.walkAnchorDay, 28.10.2026 UTC), and that established secret itself for a SEND
laid on or before it. The root lets the walk of the pipe secret erase the established secret: what a pair derives afresh for every
SEND no longer stands on it, and the root, one hash in a domain of its own, opens no letter. The sender's day is its own clock, so
the receiver tries the root first and the established secret second while it still holds that secret; no third party computes
either, and no node or Explorer computes a blind at all -- they check only the commitment below (the author's word 21.10.2026
12:2x UTC: «yes»).
Both ends of the pipe compute it, no one else can. Until the receiver lays its RECV, an observer of the SEND sees the pair tag and
the commitment to, and cannot test a candidate receiver against it without the blind. The RECV opens it: anyone then checks that
the SEND's to equals SHA-256(mt-coin-to, from of the chain the RECV stands on, the blind the RECV carries) -- so a RECV is
provably the receiver's own, and the sender, who knows the blind too, cannot lay it on its own chain (its from is another).

The receiver's from reaches the sender inside the pipe, in the about word every phone already sends its correspondents (the key
k beside b, l, c): a coin key's tag, never a name. A sender that does not yet know its correspondent's from sends no v3 record: until
TX_V2_CUT it lays a v2 record, which names the pair's tag and no receiver, and which spends on its chain exactly as a SEND (section 3).

## 2. The chains and their nodes

A key's chain lives on one node of the fixed table montana.quest (index 0, Moscow), montana.xxx (index 1, Amsterdam), at index
from[0] mod 2 -- unchanged from v2 (MTCoinTx.chainNodes in the app, TX.chain in the Explorer, TX_CHAIN in the node). That node
alone takes a record on top of the chain's head (prev = head, else 409 with the head); it is the one place a record of that key
is ordered. A v2 or v3 record laid at the other node is refused there (403 not this key's chain node, with the node's name).

Every node keeps a replica of every chain: it pulls what its sibling took (POST /tx-since by the sibling's log index), checks each
record exactly as if it were laid at its own door -- the core's signature, the chain node, prev on the replica's head, the kind's
rules below, the balance -- and keeps it with the sibling's index and the sibling's at. A record that fails is not kept, the
replica stops at it and the node's journal says ALARM: a faulty sibling halts the copy, never bends it.

A machine outside the table keeps the same replica in the node's replica-only mode (COIN_REPLICA: the chain nodes' doors): it pulls
both logs, checks every record as above, takes no record and no claim at its door (403 «replica only»), and signs the root of every
checkpoint as a holder (section 6) with its own coin key, whose chain it opens by a GENESIS of 0. A RECV pulled from one log before
the SEND it settles arrives from the other waits at its place; nothing is skipped. The same code runs hosted inside another store's
process (Lauterbourg) with a database of its own. The nodes' fold has a name (TX_FOLD): a change of its rules re-folds every chain,
the copies of the other node's chains included, from the node's own log at its next start.

The node's at of a record is the node's second when it took it, never less than the at of the record before it on the chain.

## 3. The balance is the fold of the chain

A key's state, folded over its chain from the first record to the head, every record already checked by the core:

- proven: the coins the chain proves, never below zero
- declared: what a GENESIS announced, and the announced part every SEND and RECV carries on; spent after proven, never called proven
- birth: the at of the chain's first record (any version)
- mint_end: the t1 of the last MINT, birth before the first
- minted: the sum of the key's MINTs, 0 before the first

Per record, in chain order -- first the key's time, then the record's kind:

- THE KEY'S TIME (fold-6, section 4): a v3 record whose at is TX_TIME_CUT or later first folds the seconds the key has lived. With
  x = min(at, TX_ONLINE_CUT) - birth and f = min(at, TX_ONLINE_CUT) - max(last_at, TX_TIME_CUT, birth), each at least 0, the
  credit is max(x - minted, f): proven += credit, minted += credit (fold-8 -- f, the seconds since the key's last record, never
  before the cut, so a key that minted above its life before the cut still gets every second after it). Then the record's kind is
  folded on that state. A record refused leaves the state as it stood; its seconds are folded by the next record taken, so no
  second is lost.
  From TX_ONLINE_CUT (fold-7) the key's life credits nothing more: the seconds up to the cut stay credited, every later one is minted
  only by a MINT of a present key (below).
- a v2 record (a SEND that names the pair's tag and no receiver -- laid by a build before v3, or by a v3 phone that does not yet know
  the receiver's from, section 1): before the key's first v3 record it is the book's own past, which the GENESIS announces as it
  stood after it, and it moves nothing; from the key's first v3 record on it is a SEND with D = max(0, A - proven): 1 at most A at
  most proven + declared, proven -= A - D, declared -= D. Its receiver is named on no chain: the receiver's book credits it by the
  pair's tag, and the receiver's chain carries those coins by a MINT within the time allowance (section 4). Such a record stands as
  its key's own SEND with to = 32 zero bytes and dec = D (fold-4, section 5): no RECV opens it, and its sender's REFUND after a day
  gives back the split it took. A v2 record of the book's past spent nothing and stands as no SEND. The author's words
  12.10.2026 09:1x UTC: «all transfers must be simply correct ... not versions» -- a v2 SEND at 08:59:58 UTC of 369 000 coins on top
  of its key's GENESIS had moved nothing, so the chain kept coins its book had already sent; every transfer now moves its balance.
- GENESIS (amount A, A may be 0): only as the key's first v3 record; A above 0 only before TX_V2_CUT and at most TX_GENESIS_CAP =
  A_2(TX_V2_CUT - TX_COIN_EPOCH) (section 4), what time could have minted to one key since the coins began (TX_COIN_EPOCH = 31.08.2026 21:00
  UTC); declared = A. A GENESIS of 0 is the birth of a key new to the network.
  THE BOOK'S PAST, NEVER A FRESH KEY'S WORD (18.10.2026, the critic's P-1, the author's word «put it in»): a GENESIS above 0 whose at is
  TX_GENESIS_GATE (1792354500, 18.10.2026 20:15 UTC) or later stands only on the key's own past on its chain -- height above 0, a v2
  record before it -- and A is at most A_2(at - birth), what time could have minted since that past began; else 409 «genesis
  past». Before the gate any key, a fresh one too, could announce TX_GENESIS_CAP = 110 040 864, and the node births 120 keys a minute.
  The gate lies after both chain nodes run the rule, so no record taken before it changes its fate at a re-fold.
  The chairman's correction 11.10.2026 21:0x UTC (the author's words 11.10.2026 17:2x: «so that I can pay in any scenario»): a book's
  balance from before v3 is spendable, never called proven. Declared coins are spent as declared and stay declared in every chain
  they reach.
- MINT (amount A, interval t0..t1): t0 at least mint_end, t1 - t0 at least 60, t1 at most the record's at, and A at most the
  allowance at t1 (section 4); proven += A, minted += A, mint_end = t1. From TX_TIME_CUT the key's time step above has already set
  minted to at least at - birth, which is at least t1 - birth, so the allowance is at most 0 and every MINT is refused «allowance» --
  until TX_ONLINE_CUT. From TX_ONLINE_CUT (fold-7, fold-8) A is at most the present seconds, t1 - max(t0, at - TX_MINT_FRESH,
  TX_ONLINE_CUT) with TX_MINT_FRESH = 120 (else «stale»), and the allowance is not asked: a MINT counts only what its interval holds
  of the last two minutes before its node took it and after the cut, and the intervals never overlap (t0 at least mint_end).
  From TX_MINT_STOP (fold-9, section 4) no MINT is taken at all, whatever its interval: 409 «minting stopped».
- BURN (amount A, dec D; fold-7): taken only when its at is TX_ONLINE_CUT or later (else «not yet»); spent exactly as a SEND -- 1 at
  most A at most proven + declared, D = max(0, A - proven), proven -= A - D, declared -= D -- and it names no one: pair, to, ref and
  t1 are zero, no RECV opens it and no REFUND takes it back (section 5). Its coins leave every chain: the Economy of Time's sink (I-13)
  -- a second of an ordinary call, a comment's coin a wall does not pass on.
- SEND (amount A, dec D): 1 at most A at most proven + declared; proven is spent first, so D must equal max(0, A - proven);
  proven -= A - D, declared -= D.
- RECV (amount A, dec D, ref S, to = blind): S a v3 SEND held by the node (own or replica); A equals S's amount and D its dec; S's to
  equals SHA-256(mt-coin-to, this chain's from, blind); S settled by no other key and not refunded (section 5); proven += A - D,
  declared += D.
- REFUND (amount A, ref S): S a SEND of this same chain -- a v3 SEND, or a v2 record that spent on the opened chain (fold-4) -- A
  equals S's amount, the record's at at least S's at + 86400, S not settled by a RECV (section 5); proven += A - D, declared += D, D
  being S's dec (for a v2 record, the D its fold step took).

The chain's node refuses (409 with a reason word) any record whose fold step fails: a SEND or a v2 record above proven + declared
(«overspend»), a MINT above its allowance («allowance»), a RECV on a SEND that is not this key's or settled («settled»), a REFUND
before its day or after a RECV («settled»), a second GENESIS («genesis»), a MINT above its present seconds («stale»), a BURN before
TX_ONLINE_CUT («not yet»), a MINT from TX_MINT_STOP («minting stopped»). The same fold runs in every replica, on every phone that keeps a copy and in the
Explorer, so a node that took a bad record is caught by everyone who folds after it.

POST /tx-head {"from"} -- 200 {"head", "height", "birth", "mint_end", "proven", "declared", "minted", "now"}, the amounts as decimal
strings (a u64 does not fit every reader's number); a v2 phone reads only head. From TX_TIME_CUT, proven and minted are the head's
state with the key's time step folded at now, the node's second of the answer (and never below the head's at): the balance a phone
shows is the chain's own fold at that second, and no record is laid for it.
POST /tx-chain {"from", "since": h} -- 200 {"recs": [{"id", "rec", "at", "h", "seq", "origin"}], "head", "height"}, at most 256
records in chain order, h the record's place in the chain (0 the first).

## 4. The allowance of a MINT -- 1 second, 1 coin

The constitution, article 11: «1 second -- 1 coin». The author's words 19.10.2026 12:3x UTC: «this is the ceiling, an invariant, the
constitution -- nothing else can mint or speed it up, no music, VPN and so on: VPN on, the app active, the person online -- 1 second,
1 coin»; 13:4x: «bring everything to one owner of the function 1 coin = 1 second, and that is all». The s-th second of a key's life
(s = 1 for the second that starts at birth) mints at most one coin:

  A(x) = x for x at least 0, A(0) = 0

  allowance(t1) = A(t1 - birth) - minted

for every MINT whose at is TX_SECOND_CUT (1792443600, 19.10.2026 21:00 UTC, the same second as TX_V2_CUT) or later. The rule is the
sum itself: a MINT is taken while all the key's MINTs together stay at most t1 - birth, so from the cut on no key's MINTs exceed the
seconds it has lived. The key's time not yet minted stays the key's: a MINT below what its own interval's seconds allow leaves the rest
to a later MINT (the author's words 17.10.2026 10:2x UTC: «what the balance showed must be available at once, in fact and in the
TimeChain»). MINT intervals of one key never overlap (t0 at least mint_end) and name time already passed (t1 at most the record's at).

The rule a MINT is weighed by is chosen by its at -- the node's second when it took it, kept with the record -- never by its interval:
a MINT taken from the cut on is weighed by A over the key's whole life, the seconds lived before the cut included, less everything the
key minted, the MINTs taken before the cut included. A MINT taken before the cut stands folded by the rule it was taken under, the
doubling rule

  A_2(x) = sum of 2 x min(13, max(1, bit_length(s) - 1)) for s = 1 .. x, A_2(0) = 0

(the level of the s-th second -- its whole doublings since birth, at least 1 and at most 13 -- times 2), so no record taken before the
cut changes its fate at a re-fold. A key whose MINTs before the cut exceed its seconds of life mints nothing more until its life covers
them: a key 7 days old (604 800 seconds) that minted 3 000 000 under A_2 mints again from its 3 000 000th second. A_2 also bounds
every GENESIS (section 3: TX_GENESIS_CAP = A_2(TX_V2_CUT - TX_COIN_EPOCH), and A_2(at - birth) from TX_GENESIS_GATE); a GENESIS above 0
is taken only before TX_V2_CUT, so only before the cut. The cut lies after both chain nodes run this rule.

Every source of coins the app mints (a letter, a second of a call, the wallet's pull, the seconds away, chess, music) is a claim of
the phone; the node cannot see a call or a letter. What the node can prove is that the sum stays under time. A phone lays one MINT
for what its book holds above its chain (proven + declared), at most the allowance at its t1; what the book holds above that stays
the book's until the key's time covers it.

Coins that reach a v3 phone by a v2 record (a sender that did not know its from, until TX_V2_CUT) are credited by its book under the
pair's tag and enter its chain the same way: as part of the next MINT, under the same time ceiling. They are never proven faster
than the receiver's own time, and no RECV can name them (a v2 record commits to no receiver).

THE CHAIN MINTS THE KEY'S TIME ITSELF (fold-6; the author's words 21.10.2026 13:5x-14:1x UTC: «the rule in Rust for the node, and
with us 1 coin = 1 second»; «only the core mints»; «1 coin -- 1 second, the client merely shows it, it does not mint»). From
TX_TIME_CUT (1792702800, 22.10.2026 21:00 UTC) the fold itself credits every second of a key's life once, at the key's first record
taken after it (section 3, the key's time): a key's minted at a record is max(minted before it, at - birth), and its proven grows by
the same step. No phone lays a MINT for its time, and no source of coins other than the seconds of a key's life enters a chain: a
letter, a call, music and the wallet's pull are a phone's own count and never a record. The cut lies after both chain nodes run
fold-6, so no record taken before it changes its fate at a re-fold.

THE PAST NEVER EATS THE PRESENT (fold-8; the author's words 23.10.2026 19:1x UTC: «Andrey writes that his coins are not credited --
fix it in the new build», 19:21: «straight into the new build with the minting problems fixed»). Under fold-6 a key whose MINTs
before TX_SECOND_CUT exceed its seconds of life gained nothing until its life covered them: measured 23.10.2026 on both chain nodes,
28 of 96 keys -- every key of a living phone among them -- minted by the doubling rule up to 26 a second and stood still for 6 to 133
days of their present seconds, against article 11. From fold-8 the time step credits max(x - minted, f) (section 3): a key's minted
at t is max(t' - birth, minted before the cut + t' - max(TX_TIME_CUT, birth)), t' = min(t, TX_ONLINE_CUT). The past minted under the
rules of its own second stays; every second from the cut credits one coin to every key, and never two. A key that did not mint above
its life folds byte for byte as under fold-6. The step only grows proven against fold-7, so a record taken before changes from taken
to refused at no re-fold, and the rule applies from TX_TIME_CUT itself. The fold of the key's time is one function of the core (the
crate mt-coin of Montana Core, its version the number of the reference iOS build), and the node, every replica, every phone that keeps
a copy and the Explorer fold by it.

MINTING IS ITS OWN ROAD (fold-7; the author's words 23.10.2026 00:27 UTC: «first separate: minting is a separate entity, and it happens
if the person is online or behind the VPN»; 00:37: «right, do it»). Fold-6 credited every second of a key's life, its seconds away from
the network too. From TX_ONLINE_CUT (1792962000, 25.10.2026 21:00 UTC) the life credits nothing by itself, and a coin is born only of a
present second: while the person is online (the app on the screen and the network up) or behind the VPN, the phone's minting -- its
own road, never the wallet's list of moves -- lays one MINT a window of τ1 from the chain's mint_end to the node's now, and the node
takes at most what of it lies in the last TX_MINT_FRESH = 120 seconds before its own second. Seconds away are never minted afterwards:
a phone back after an hour mints at most two minutes. A tap, a letter, a call, chess, music and the seconds away are no source of
coins and never a record. The 1 coin a second ceiling stands by the intervals (fold-8): every second the time step credited ends at
TX_ONLINE_CUT, a MINT counts its seconds from it on, and two MINTs never share a second (t0 at least mint_end), so a key's whole life
is not asked and a key that minted above it before TX_TIME_CUT mints its present seconds like any other.
Every rule of fold-7 is chosen by the record's at, so no record taken before the cut changes its fate at the re-fold to fold-7.

ONLY THE CORE MINTS (fold-9; the author's words 29.10.2026 13:53 and 14:48 UTC, links 11580 and 11639: no client can mint coins for
itself, physically, as no client can mint bitcoins -- issuance is the core's alone, whatever the client; decisions 362 a and 365 a).
A MINT is a claim of the phone: the node cannot see a person online, so under fold-7 any client minted 1 coin a second for every
key it made, and a key is free (GENESIS 0). From TX_MINT_STOP (1793361600, 30.10.2026 12:00 UTC) a node takes no MINT at all
(«minting stopped», the refusal code 18 of the core's door, after codes 1 .. 17, which keep their places). A GENESIS above 0 is refused
since TX_V2_CUT and the key's life credits nothing since TX_ONLINE_CUT, so from the stop no record mints: a chain's coins only move
(SEND, RECV, REFUND) or leave (BURN), and a GENESIS 0 still opens a key with nothing on it. A coin is born only by the right of a
window of the consensus core (Montana-Core `window_credit`, 60 for a window of 60 s). The rule is chosen by the record's at, so every
MINT taken before the stop keeps its fate at the re-fold to fold-9. The code is `mt-coin` of `core/Code` (`TX_MINT_STOP`,
`crates/mt-coin/src/lib.rs:30`; the refusal at `:528`), its test `v16_minting_stops_and_only_the_core_mints`
(`crates/mt-coin/tests/vectors.rs:850`).

## 5. Settling a SEND -- one RECV or one REFUND, never both

The SEND's chain node is the one authority on its fate: it keeps a claim per SEND, set once, either to the receiver's from or to
the sender's REFUND.

- A RECV is laid at the receiver's chain node. When that node is not the SEND's, it first asks the SEND's node to claim the SEND
  for it: POST /tx-claim {"rec": the RECV} at the sibling; the sibling verifies the RECV with the core, checks the commitment and
  sets the claim to the receiver's from when the SEND is unclaimed and its own clock is before S.at + 86400, or answers ok when the
  claim already names the same from. Only then is the RECV taken. A claim names a key, not a record, so a RECV refused for a moved
  head is laid again on the new head and claims the same SEND again.
- A REFUND is laid at the sender's chain node, the authority itself: taken only when its clock is at S.at + 86400 or later and the
  SEND is unclaimed; the claim becomes the REFUND.
- One clock decides: the authority's. A RECV that reaches it in time wins; after the day only the sender's REFUND can settle it.
- A BURN is no SEND: it stands in no claim, /tx-unsettled never lists it, and a REFUND naming it is refused «no send».

POST /tx-settle {"send"} -- 200 {"state": "open" or "recv" or "refund", "by", "at"} at the SEND's chain node.
POST /tx-unsettled {"from"} -- 200 {"sends": [{"id", "v", "amount", "at"}]} at the key's chain node: its v3 SENDs and its v2 records
that spent (fold-4), with no claim yet, oldest first, at most 256; any other node answers 403 with the chain node's name, for its
copy holds no claim. It grants nothing; the REFUND is checked again at the door.

A v2 RECORD THAT SPENT COMES BACK (fold-4, 19.10.2026; the critic's P-3 of Agent 95 and the author's word «put it in»): before fold-4 a v2
record laid on an opened chain spent and stood for no one -- it names no receiver, so no chain could take it, and the REFUND knew only
v3 SENDs. On 18.10.2026 T1 sent 1 369 000 and 2 000 000 coins that way to a phone of the Android build, which reads no chain; the
network held 17 such records since 12.10, 11 045 606 coins. The node keeps each such record's D beside it (the column dec, filled at
the door and at every re-fold), so its REFUND is the one road back, under the same one-claim rule. A receiver whose book credited a
v2 record by the pair's tag takes the credit back when its sender's REFUND settled it (the book's move «txgone:» and the record's
id): the coins are either with the sender or with the receiver, never with both.

Every record a node takes is first verified by the core -- the C door mt_verify of mt-bindings, the function the phone links --
loaded by the node from the library built out of the protocol's crates; a node without it takes no coin record (503). The rows laid
before this check are verified once at the node's start, and a forged one never stands on a chain.

## 6. The root and the holders

Checkpoints are the node seconds T that are multiples of 600. The root of T:

  root(T) = SHA-256(ASCII mt-coin-root-v1, 15 bytes, then for every key with a chain record of at at most T, in ascending order of
  from: from (32 bytes), the id of its last record with at at most T (32 bytes), the number of its chain records with at at most T,
  u64 little-endian)

POST /tx-root {"at": T} -- 200 {"at", "root", "keys", "records"}; without at, the newest checkpoint at least 300 seconds old (the
replicas' margin).

A holder -- a node or a phone that keeps a replica -- signs a root it computed itself with its seed's coin key:

  message = ASCII mt-coin-root-sig-v1 (19 bytes), then T as u64 little-endian, then root (32 bytes)

POST /tx-root-sign {"pk": base64, "at": T, "root": hex, "sig": base64} -- the node verifies with the core, keeps only the last
signature of each holder (one row a key, I-14), and only of a key that has a chain on the network.
POST /tx-quorum {"at": T} -- 200 {"at", "root", "holders": [{"from", "root", "pk", "sig", "at"}]}.

The Explorer reads both nodes' roots of the same T, verifies every holder's signature in the browser, and shows how many nodes and
how many phones signed the same root -- the global quorum -- and, for a key, the fold of its whole chain -- the local proof.

Phones keep a replica only with the person's consent to keep a copy (the keeping of MTKeeping, «a copy at the correspondents»), and
then the whole network's chains, not only their correspondents': a holder's signature must not say whose chains it cares about.

## 7. Limits (I-14, I-15)

- A record is taken only by a proven right: SEND on a positive proven balance, MINT on time already passed, RECV on an existing
  unclaimed SEND, REFUND on its own unclaimed SEND after a day, GENESIS once per key. A fresh key's only free record is its GENESIS
  of 0; births are counted node-wide (TX_BIRTHS_PM a minute).
- A key lays at most TX_KEY_PM records a minute and TX_KEY_PD a day at its chain node; a MINT covers at least 60 seconds.
- The node's pace table (by address, and the node's whole minute) never empties itself whole -- a fresh caller key once bought a
  clean slate -- and refuses a key never seen once four times its ceiling of live rows stands. A key's own pace is counted in the log
  itself, so no fresh name escapes it.
- The log's budget TX_BUDGET: births stop at three quarters of it, every other record at the whole (507). A transfer is never
  pruned (I-2): the chain is the proof.

## 8. Compatibility and the cut

- v1 (builds 2190 and older): the node takes no new v1 record from TX_V1_CUT (12.10.2026 21:00 UTC) -- 400 «retired». The older
  build's send then hears a refusal from every door and keeps the coins («not sent», nothing debited). A receiver on 2191 or later
  still finds every v1 record laid before the cut by its pair tag and credits it once, as before.
- v2 (build 2191, and a v3 phone that does not yet know its receiver's from): taken, chain-ordered and signature-checked until
  TX_V2_CUT (19.10.2026 21:00 UTC), then 400 «retired» and the coins stay with the sender. On a chain that holds a v3 record it spends
  as a SEND (section 3); its receiver's chain carries it by a MINT (section 4).
- v3 (build 2192 and later): a 2191 phone reads a v3 SEND as no record (its reader knows versions 1 and 2), so it credits nothing;
  no RECV comes, and after a day the sender's REFUND gives the coins back -- the coins did not leave.
- The head of a key may be a v2 record; the first v3 record of that key stands on it.
- The second's cut (section 4): a MINT taken from TX_SECOND_CUT (19.10.2026 21:00 UTC) on is weighed by A(x) = x; one taken before
  stands by A_2. A build before 2249, whose book minted up to 26 a second, lays MINTs the node then refuses above the key's seconds
  («allowance»); its book keeps them, unproven, and spends them as it could before only up to its chain.
- Montana Core v1.0 (the author's words 19.10.2026 19:2x UTC: «in the night of 20 October UTC the old builds must not be able to
  mint more than 1 coin a second -- you define the level of the Montana Core»; «our build is Montana Core v1.0»): the level of the
  core is the rule of section 4 as both chain nodes hold it from TX_SECOND_CUT -- 19.10.2026 21:00 UTC, before
  that night. A build below the level (before 2249, minting up to 26 a second) is held by the node alone: its MINTs above the key's
  seconds are refused, whatever its book says. From build 2252 the release document (the site's /updates/messenger-beta.json, the
  node's /release) names the least build the network admits (min, the build it publishes) and the core's level (core); a build below
  the least sees the update page over everything at every opening, with the update's link as its one way out.
- Minting by presence (fold-7, section 4): from TX_ONLINE_CUT (25.10.2026 21:00 UTC) a key mints only by its phone's MINTs while
  present. A build before fold-7 lays no MINT after TX_TIME_CUT, so its key mints nothing from the cut until it updates; its spends
  (reactions, chess, the wall) stay in its own book and are no record, and its SENDs spend what the chain holds. A node before fold-7
  refuses a BURN at parse (400) and refuses a fresh MINT «allowance»: the cut lies after both chain nodes and every replica run
  fold-7, and the Explorer folds BURN as a SEND to no one.
- The past never eats the present (fold-8, section 4): a node on fold-6 or fold-7 credits a key that minted above its life before
  the cut nothing; a node on fold-8 re-folds every chain at its start (the fold's name) and only grows proven, so both chain nodes take
  the core together and no record changes from taken to refused. A build before fold-8 shows /tx-head as the node folds it; its own
  copy of the fold answers less for such a key until it updates, and its spends are weighed by the node.
- The key's time (fold-6, section 4): from TX_TIME_CUT (22.10.2026 21:00 UTC) the chain mints a key's seconds itself. A build that
  still lays MINTs reads minted and proven from /tx-head folded at the node's now, so the room it computes for a MINT is at most 0
  and it lays none; a MINT it lays in any case is refused «allowance» and moves nothing. Its SENDs spend the seconds the chain has
  folded, exactly as a later build's do.

- Only the core mints (fold-9, section 4): from TX_MINT_STOP (30.10.2026 12:00 UTC) a node takes no MINT. A node on fold-9 re-folds
  every chain at its start (the fold's name), and no record taken before the stop changes its fate. A build that still lays MINTs
  hears «minting stopped» and its book keeps the claim, unproven; its SENDs spend what the chain holds. The stop lies after both
  chain nodes run fold-9; a node still on fold-8 after the stop would take MINTs the others refuse, and those who fold after it catch
  it (section 3).

## 9. Test vectors

Every vector below is checked by the node's own run (coin-node-check.mjs, kept with the node's code, which is not public) against the node's
code and the web core, and by tools/explorer-check.mjs against the Explorer's code (V1 and V3 against the page's own exported
functions). Each names the wrong implementation it refuses.

- V1 the receiver's commitment. from = the 32 bytes 0x00, 0x01 .. 0x1f; blind = the 32 bytes 0x20 .. 0x3f.
  to = SHA-256(mt-coin-to, from, blind) = b08fb9c67b693f0cfe394de25474d2b79ae990a87a2f6a24bb7727560a8d88a4.
  Refuses: the blind hashed before from (8d9016dfed6ea8b2c6c03daaf943afe73dfc25ed46a4bc9049bf5afe15de9c3f), or the hex text hashed
  instead of the bytes.
- V2 the blind. secret = the 32 bytes 0x40 .. 0x5f; nonce = the 16 bytes 0x60 .. 0x6f.
  blind = HMAC-SHA-256(key = secret, message = mt-coin-blind, nonce) = 530efcc186fe26cb48fb4023c7a7e884c94516d14e62feaa06e81c76f89d7be4.
  Refuses: the key and the message swapped (c9791acc18552bdd84114470faa6aa038af2f0ab245b4bfdb0ea9cd2e93ceb16).
- V2r the root a SEND is blinded under past the anchor. secret = the 32 bytes 0x40 .. 0x5f; root = SHA-256(mt-conv-root, 0x00, secret)
  = 191ebd35309f514aa4c9c26b9c7eacbb3398997ee055e2776f9c1c6f40463334; blind under it with V2's nonce
  = e276ac263988cf1c47f8786fa4c39b5e19a77f0e7682d078baad82498b162c34. Refuses: the root without the zero separator
  (secret 0x00 .. 0x1f: 3be774152000edefa3660fe4cb309a46cae72881bec79e34f6dd153d5beea92a against
  d9c3e7f533da2d0ed10b6729601c478ab29d1b0cafed60443113ee6a63824e11, MTPipe.selfTest), and a SEND past the anchor blinded under the
  established secret (V2's 530efcc1...).
- V3 the doubling rule A_2(x) (section 4: every GENESIS, and the MINTs taken before TX_SECOND_CUT): 1:2 2:4 3:6 4:10 7:22 8:28 15:70 16:78 8191:180230 8192:180256 8193:180282 86400:2213664.
  Refuses: a level of bit_length(s) without the minus one (A_2(2) would be 6), a level rounded up (A_2(3) would be 8), the music's factor
  left out (every value halved), seconds counted from 0 (A_2(1) would be 4), and a ceiling other than 13 at the 8192nd second.
- V4 the root. Three keys, from_c = SHA-256(ASCII «root key c») for c in a, b, c, laid in the order a, c, b; key a has 3 records,
  c has 2, b has 1; record i of key c is SHA-256(ASCII «root head c i»), at 100 + i; T = 1000.
  root = 4db30532f47a38696a81aa103cabea16ecf6034934cf26decbb9e78ad848b5e1.
  Refuses: the keys taken in the order laid with the count big-endian (b5cb0949009d6d9f9c34d20f5e719de913930ba61afd4e96835a1575efea07a6);
  the node's run also refuses the keys in descending order.
- V5 a SEND and its RECV, signed by the web core (deterministic ML-DSA-65). S = the key of seed SHA-256(ASCII «seed v3 vector S»), R =
  the key of seed SHA-256(ASCII «seed v3 vector R»). The SEND: amount 1234, birth 1760300000000, nonce = SHA-256(«nonce v3 S»)[0:16],
  prev zero, pair = SHA-256(«pair v3 S»), to = SHA-256(mt-coin-to, from of R, blind), blind = HMAC-SHA-256(SHA-256(«secret v3 S»),
  mt-coin-blind, nonce). Its signed message hashes to cf00d783cfb5364e6c00afdaaeb203b32635b31d6894650f3fb68d7b3c96e3e5 and its id is
  2dd4cf64695222b31d4cd0c799a1f21888aaacb83bab7febfce055f6b7da46fa. The RECV of R: amount 1234, nonce = SHA-256(«nonce v3 R»)[0:16],
  to = the blind, ref = the SEND's id; id ce5a492c063c71435ccb9582e3662c1d876310fe04d2846d73f7d07bd0236646.
  Refuses: a signature over v2's prefix or over bytes 0..2053 (neither verifies), any field at another offset (another id), and a
  RECV whose blind does not open the SEND's to for R's from.
- V6 a v2 record on an opened chain. Key S: GENESIS 1000 declared, MINT 500, SEND 1200 (dec 700), then a v2 record of 50 on S's
  head: taken, S's state proven 0, declared 250; a v2 record of 251 next: 409 «overspend». In the Explorer's run: GENESIS 0, MINT 1000,
  SEND 100, a v2 record of 50 -- balance 850. Refuses: a v2 record that moves nothing on an opened chain (the balance would stay 900,
  the 2193 send of 11:59:58), and a v2 record taken above the chain's balance.
- V7 the graph (section 10). Key S: GENESIS 0, MINT 1000 over 120 seconds, SEND 100 to R, the v2 record of V6; key R: GENESIS 0, the
  RECV of that SEND. R's graph: one edge, «received 100 from» S's address, and under it S's one source, its MINT of 1000 over 120
  seconds with no parent; S's graph: its MINT alone. Refuses: an edge drawn from a SEND before a RECV opened it (S's graph would list
  its sends or name R), a parent drawn for a MINT or a GENESIS, and the receiver of a v2 record named anywhere.
- V8 the sum of time, MINTs taken before TX_SECOND_CUT. Key K, GENESIS 0 at its birth b: a MINT of 120 over b .. b + 6800 -- taken (A_2(6800) = 146846); a MINT of 2000
  over b + 6800 .. b + 6870 -- taken: the interval's own seconds allow 1680 (A_2(6870) - A_2(6800)), the key's time less what it minted
  allows 148406 (A_2(6870) - 120); K's state proven 2120, minted 2120, mint_end b + 6870; then a MINT of 148087 (A_2(6940) - 2120 + 1)
  over b + 6870 .. b + 6940 -- 409 «allowance». Refuses: a fold that weighs a MINT by its own interval alone (the 2000 refused, the
  first MINT's unminted seconds burned), and a fold that forgets what the key minted (the 148087 taken).

- V10 a v2 record that spent comes back (fold-4). Key V: a v2 record of 1 (the book's past), GENESIS 1000, MINT 500, a v2 record of
  1200 -- proven 0, declared 300, the record unsettled with dec 700; a day later V's REFUND of 1200 -- proven 500, declared 1000. Refused
  at the door: a RECV naming the v2 record («not yours»), a REFUND of the book's past («no send»), of another amount («amount»), by
  another key, and a second REFUND («settled»); the re-fold to fold-4 keeps all of it. Refuses: a fold that keeps a spent v2 record's
  coins for no one, one that gives them back as proven (1200 proven), one that counts the book's past as a SEND, and a RECV of a record
  that commits to no receiver. In the Explorer's run: a key's v2 spend of 300 taken back a day later folds whole at 1000; taken back
  after 100 seconds the chain breaks at that record («a refund before its day»).
- V9 the book's past (section 3, TX_GENESIS_GATE). After the gate: a fresh key's GENESIS of 5 -- 409 «genesis past»; key P with a v2
  record 300 seconds old, a GENESIS of A_2(360) + 1 = 4759 on it -- 409 «genesis past», a GENESIS of A_2(300) = 3798 -- taken, declared 3798; key Q's
  GENESIS of 777 with no past laid 10 seconds before the gate -- still folded at the node's start, declared 777. Refuses: a node that
  takes a fresh key's announcement (any key could announce 110 040 864), one that forgets the time bound, and one that applies the
  rule to a record taken before the gate (Q's chain cut at the re-fold).
- V11 1 second, 1 coin (section 4, TX_SECOND_CUT = C). Key L, GENESIS 0 at C - 100 (its birth b): a MINT of 100 over b .. b + 300
  at C + 200 -- taken; a MINT of 250 over b + 300 .. b + 360 at C + 500 -- taken (the key's 360 seconds less its 100 allow 260, its
  interval alone 60); then at the door, at C + 500 (never less than the record before), a MINT of 71 over b + 360 .. b + 420 -- 409
  «allowance» (420 - 350 = 70), and a MINT of 70 there -- taken, L proven 420, minted 420: its seconds of life. Key K, GENESIS 0 at C - 7000 (its birth b): a MINT of 140000 over b .. b + 6800 at C - 150 --
  taken (before the cut, A_2(6800) = 146846); a MINT of 1 over b + 6800 .. b + 6870 at C + 10 -- 409 «allowance» (6870 - 140000 is
  below 0). Refuses: the doubling rule after the cut (L's 71 taken, A_2(420) - 350 = 5368), a fold that weighs a MINT by its interval
  alone (L's 250 refused), one that forgets what the key minted (L's 71 taken, A(420) = 420), one that applies A to a MINT taken before
  the cut (K's 140000 refused at the re-fold, its chain cut), one that chooses the rule by t1 instead of at (K's 1 taken: its t1 lies
  before the cut and A_2(6870) - 140000 = 8526), and one that keeps the doubling rule's unminted time past the cut (K's 1 taken).
- V12 the chain mints the key's time (section 4, fold-6; TX_TIME_CUT = D). Key T, GENESIS 0 at D - 1000 (its birth b): a MINT of 300
  over b .. b + 400 at D - 500 -- taken (fold-5, 400 - 0 allow 400), T proven 300, minted 300. At D + 100 a SEND of 1000, dec 0 --
  taken: the key's time step first folds 1100 - 300 = 800 (proven 1100, minted 1100), then the SEND spends 1000, T proven 100. At
  D + 200 a MINT of 1 over b + 400 .. b + 1060 -- 409 «allowance» (the time step sets minted to 1200, and 1060 - 1200 is below 0).
  /tx-head at now D + 300: proven 300, minted 1300, declared 0, the head the SEND (the refused MINT left the state as it stood).
  Key K of V11 (its MINTs 140000, birth C - 7000): its next record, at D, a SEND of 1 with dec 0, folds 266200 - 140000 = 126200
  first and leaves proven 266199. Refuses: a fold with no time step, or one that folds the time after the kind (T's SEND refused
  «overspend» on 300); one that credits the seconds of life without the key's MINTs (T proven 400 after the SEND, K 406199); one
  that applies the step to records before D (T's MINT of 300 at D - 500 refused «allowance»); and a /tx-head that answers the
  head's state alone (T proven 100, minted 1100 -- a build that lays MINTs then finds a room of 80 at t1 = now - 120).

- V13 a MINT counts the present seconds (section 4, fold-7; TX_ONLINE_CUT = E). Key Q, GENESIS 0 at E - 1000 (its birth b): at
  E + 500 a SEND of 1001 -- 409 «overspend» (the life credited only up to E, 1000); a SEND of 1000 -- taken, Q proven 0, minted 1000;
  /tx-head at E + 5000 -- proven 0. At E + 620 a MINT of 101 over b .. E + 600 -- 409 «stale» (present: E + 600 - (E + 500) = 100),
  a MINT of 100 there -- taken; at E + 670 a MINT of 61 over E + 600 .. E + 660 -- «stale», of 60 -- taken, Q proven 160, minted 1160,
  mint_end E + 660; at E + 900 a MINT of 1 over E + 660 .. E + 720 -- «stale». Refuses: a fold whose life mints past E (the 1001
  taken), one without the present seconds (the 101 taken, its allowance 600), and one that measures them from t1 (the last 1 taken).
- V14 a BURN spends and names no one (sections 3 and 5, fold-7). Key U, GENESIS 0 at E - 1000: a BURN of 10 at E - 1 -- 409 «not
  yet»; at E + 10 a BURN of 1001 -- «overspend», of 400 with dec 1 -- «split», of 400 with dec 0 -- taken, U proven 600, declared 0,
  minted 1000; a REFUND naming it a day later -- 409 «no send». Read: kind 6, dec at t0; a BURN with a pair, a to, a ref or a t1 is
  no record, nor one of amount 0 or with dec above its amount. Refuses: a BURN folded as a MINT or as nothing (proven 1400 or 1000),
  one taken before the cut, and one a REFUND can take back.
- V15 the past never eats the present (sections 3 and 4, fold-8). Key O, GENESIS 0 at C - 100000 (its birth b): a MINT of
  A_2(99999) = 2567238 over b .. C - 1 at C - 1 -- taken by the doubling rule, O proven and minted m = 2567238, above its life until
  after E. /tx-head at D + 300: proven m + 300, minted m + 300. At D + 300 a SEND of 1, dec 0 -- taken, O proven m + 299, minted
  m + 300; /tx-head at D + 500: proven m + 499, minted m + 500. At E + 60 a MINT of 61 over E - 60 .. E + 60 -- «stale», of 60 --
  taken: the time step credits E - (D + 300) first, so O proven m + 299 + (E - D - 300) + 60, mint_end E + 60. Refuses: fold-6 and
  fold-7 (proven m at D + 300, its life 359500 below m), a step that ignores last_at and counts from the cut at every record (m + 799
  at D + 500), and a MINT whose present seconds are not floored at E (the 61 taken, or refused «allowance» by the life's sum).
- V16 only the core mints (sections 3 and 4, fold-9; TX_MINT_STOP = S; checked by `mt-coin`
  `v16_minting_stops_and_only_the_core_mints`, `core/Code/crates/mt-coin/tests/vectors.rs:850`). Key K, GENESIS 0 at S - 1000: a MINT
  of 60 over S - 200 .. S - 140 at S - 130 -- taken; a MINT of 60 over S - 60 .. S at S -- 409 «minting stopped», a MINT of 1 over
  S + 60 .. S + 120 at S + 125 -- «minting stopped»; K's state stands as after the first MINT, /tx-head at S + 86400 answers the same,
  and the re-fold of K's chain gives the same. Key N: GENESIS 0 at S + 10 -- taken, N holds nothing; a GENESIS of 1 at S + 20 --
  «genesis»; a MINT of 60 over S + 10 .. S + 70 at S + 75 -- «minting stopped». Refuses: a fold that still mints from the stop (either
  MINT taken, or the life credited after it), and one that refuses a MINT taken before the stop (K's chain cut at the re-fold).

## 10. The graph of the coins' appearance -- the anonymous owner

The author's words 12.10.2026 08:5x UTC: «the fact of minting creates the graph of the coin's appearance, as said here of the
anonymous owner» (the financial layer's document, «Montana Financial Layer and Anonymous Owner» 1.0.0, sections 2.5, 3.2, 5).

The graph is read from the records alone, with no new field and no new door: the Explorer reads a key's chain (POST /tx-chain), folds
it, and draws its sources --

- a MINT: coins born of the key's own time (section 4), a source with no parent. No record of any kind names who made a key: a key's
  first record is its own GENESIS, signed by itself, and its first coins are minted, so a key has no funding trail and no lineage
  (the document's 2.5 and 5.2: «born with coins from emission -- no top-up, no trail back»);
- a GENESIS above 0: the wallet's balance announced when the chain opened, a source with no parent, labelled as announced;
- a RECV: an edge to the key of the SEND it opens (the SEND's from), with the amount and its announced part; the sender's own sources
  before that SEND are drawn under it in turn, a few keys deep;
- a REFUND: the key's own SEND come back.

A SEND is an edge only once its RECV opened the blind (section 1); before that the receiver is not drawn, and a v2 record, which
commits to no receiver, never draws one. Every key is shown only by its from tag: no name, no phone, no conversation stands in any
record (the pair's tag says that a pair paid, never who the pair is).

What of the document maps onto v3, and what does not:

- Mapped: birth without a parent and without a top-up (above); a payment from one key only -- a SEND is signed by one key and spends
  that key's chain, so no record co-spends two keys (the document's 6.4); a balance is a key's own -- the app keeps no summed balance
  across seeds, and a node or the Explorer never adds keys together (5.3 c); a transfer to one's own other account is never an
  ordinary act -- Montana and Business say under it that it links the two accounts publicly forever and ask before it leaves (5.3 a,
  b); the forbidden promises of 5.5 («anonymous payments», «untraceable transfers», «full anonymity») are said nowhere.
- Different in v3: a key's receiver stays hidden until the RECV opens the blind -- the document's Send names its destination at once;
  in v3 the edge appears when the receiver takes it, and then it is public forever (I-2). A seed has one coin key today, drawn by
  role (HKDF-Expand of the master seed under «mt-coin-tx»); the document's ladder of identities (5.1: HKDF-SHA-256 with 32 zero bytes
  of salt over entropy_32, info «mt-account-key» and i as u32 little-endian) is a separate set of keys. Moving a chain's coins from
  today's key to identity 0 would be a SEND between two identities of one owner -- the very link 5.3 forbids -- so today's key stays
  its owner's first identity, and the ladder opens only new ones.
- Not in v3, waiting for the protocol's new Genesis (named, not hidden): the block lattice with balance_after, Receivable and
  mint_source_hash (2, 3.2), the emission's equal share of the live set L(W) and dust_carry (3.1), PresenceWitness (3.3), the trust
  flow and its dilution (4). v3's MINT is bounded by a key's own time, not by witnessed presence (section 12).

## 11. The top shows a proven key's chain

The public top (POST /top-put, /top-get on every node) once showed the number each row's owner told; a build of one's own said a
billion and stood first, or said 0 and drew every «Level the top 13». From 19.10.2026 (the critic's P-4 of Agent 95) a row proves the
coin key its owner holds: pk (base64, 1952 bytes) and sig = ML-DSA-65 over ASCII mt-top-key-v1 followed by the row's token (32 bytes),
verified by the node's core. The node keeps frm = SHA-256(pk) beside the row, and /top-get shows each row at its key's chain as the node
folds it now (proven + declared), the rank counted the same way; a row with no proof is kept and shown nowhere. A signature over
another token, or another key's signature under a public half, proves nothing. A pair's word in the app likewise only says that the
pair shows its coins: the number every phone shows and levels by is the pair's chain (MTCoinBoard), never the number told.

## 12. What v3 does not close (named, not hidden)

- MINTING STANDS ON A KEY'S AGE, AND KEYS ARE FREE -- the critic's P-1 of Agent 95, 19.10.2026, open: a build of one's own opens
  keys by GENESIS 0 (TX_BIRTHS_PM, 120 a minute a node, 172 800 a day) and mints A(age) on each -- from TX_SECOND_CUT 3 600 coins
  after an hour and 86 400 after a day (A_2 gave 71 036 and 2 213 664) -- then sends them to one key. The closure is the protocol's new Genesis named in section 10 (PresenceWitness,
  the emission's equal share of the live set, the trust flow): a coin is born of witnessed time, not of a key's age.
- A v2 RECEIVER MAY HAVE MINTED ITS CREDIT ALREADY (fold-4, named): a receiver's book credited a v2 record by the pair's tag and its
  chain carried it by its own MINT (section 4); when the sender's REFUND takes the record back, the receiver's book gives the credit
  back (txgone:), but the MINT on its chain stands -- no record can undo a MINT. Those coins then stand twice on the chains, each
  side under its own time ceiling: at most the 17 v2 records since 12.10, 11 045 606 coins, and no new v2 record after TX_V2_CUT.
- Minting is a key's presence at its node, bounded by time, not a proof of a person: from fold-7 no letter, call, tap or second away
  mints, and a key mints only by MINTs its node takes within two minutes of their interval. A machine of one's own that stays
  connected is present to the node all the same. Two seeds of one person can each mint at the full rate; Sybil keys (many seeds)
  are many people to the node.
- GENESIS announces the books' balances from before v3 and proves none of them: they are spent as declared and stay declared in
  every chain they reach, so a proven balance is never mixed with them. From TX_GENESIS_GATE an announcement stands only on the key's
  own past on its chain and under the time since that past began (section 3); the GENESIS records above 0 taken before the gate by
  keys with no past stand as taken, and their count is measured on the nodes, not assumed.
- The time allowance cuts what a book mints above 1 a second averaged over the key's life since its birth: that part stays in the
  book and is not proven. From build 2249 the app's book mints at most 1 a second (MTCoinBook.price), so its MINTs meet the chain's rule.
- MINTS TAKEN BEFORE TX_SECOND_CUT STAND (named): a key's MINTs under A_2 up to 26 a second are proven and stay so -- no record
  undoes a MINT, and a re-fold must not change a record's fate. From the cut that key mints nothing until its seconds of life cover
  everything it minted; the excess above its seconds at the cut is measured on the nodes, not assumed.
- PRESENCE IS PUBLISHED AT THE GRAIN OF τ1 (fold-7, named, open): a key present mints by one MINT a minute, and every MINT stands on
  its public chain with its node's second -- the key's pattern of being online is readable from its chain (by its from tag, never a
  name). Fold-5 laid MINTs at the same grain until 23.10.2026; fold-6 hid it and minted the seconds away. The closure is a
  construction, not a norm: presence witnessed without a public timestamp per window (the protocol's PresenceWitness, section 10).
- THE VPN BEHIND A SLEEPING APP MINTS NOTHING YET (fold-7, named, open): the MINT is laid by the app; a tunnel that stands while the
  app sleeps in the background keeps its living seconds (MTTunnelAlive), and they are not minted afterwards. The closure is the
  tunnel's own MINT -- the packet tunnel signing with the seed's coin key -- which needs the key and the core inside the extension.
- Two chain nodes order the chains; if one is down, its keys' records wait (their coins stay), and a RECV of a SEND whose node is
  down waits for its claim. A node that loses its disk is restored from its sibling's replica.
- A holder's signature proves what that holder folded, not that it is independent: one person can run many holders. The quorum
  shows the count; the Explorer's own fold is the proof a visitor needs no one else for.
- The chain table (montana.quest, montana.xxx) stands in three places -- the app, the Explorer and the node -- each checked against
  this document by its own run.
