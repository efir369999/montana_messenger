# Coin transfer record v2 (MTTX, version 2) -- the seed's own chain on one node

The author's words 11.10.2026 18:2x-18:5x UTC (No.63): «the whole TimeChain must be impenetrable»; «either the coins left or not
-- there is no third, let this rule be the zero sign of the constitution» (article 0 since); «carry out all 13».

Version 1 ([COIN-TX-V1.md](COIN-TX-V1.md)) made one transfer binary by a node's word, but two devices of one seed could each sign against
the same balance before their books met, and a dishonest client could sign two records of the same coins. Version 2 orders every
record of a coin key in one chain, on one node, and that node takes a record only on top of the chain's head: of two records that
stand on the same predecessor, one is taken and the other is refused -- its coins never left. Historical for new records (marked 2026-10-27 UTC): from TX_V2_CUT (19.10.2026 21:00 UTC) a v2 record is answered 400 «retired» ([COIN-TX-V3.md](COIN-TX-V3.md):293-294; `apps/messenger/ios/Code/Montana/MTWalletCore.swift:3886`); the current record is v3.

## Record (5362 bytes, little-endian integers)

- offset 0, 4 bytes, magic: ASCII `MTTX`
- offset 4, 1 byte, version: `0x02`
- offset 5, 8 bytes, amount: u64, coins, 1 or more
- offset 13, 8 bytes, birth: u64, milliseconds since 1970-01-01 UTC, the sender's clock
- offset 21, 16 bytes, nonce: random
- offset 37, 32 bytes, pair: HMAC-SHA-256(key = the pair's pipe secret, message = ASCII `mt-coin-pair-v1`) -- as in v1
- offset 69, 32 bytes, prev: the id (SHA-256) of the previous record of the same coin key on its chain; 32 zero bytes for the first
- offset 101, 1952 bytes, pubkey: the sender's ML-DSA-65 public key (the seed's "mt-coin-tx" key, as in v1)
- offset 2053, 3309 bytes, sig: ML-DSA-65 signature over ASCII `mt-coin-tx-v2` (13 bytes) followed by bytes 0..2053

`id = SHA-256(record)`; `from = SHA-256(pubkey)` -- as in v1.

## The chain's node

A key's chain lives on one node of a fixed table, sorted by name -- index 0 `montana.quest` (door `https://api.montana.quest/pushwake`,
Moscow), index 1 `montana.xxx` (door `https://montana.xxx/pushwake`, Amsterdam) -- the one at index `from[0] mod 2` (the first
byte of `from`). The table is one place in the app (`MTCoinTx.chainNodes`) and the same in the Explorer; a door not in it
(Lauterbourg keeps no transfers, the phone's other doors) is no chain node, and a v2 record read there moves nothing. The sender asks that node for the head (`POST /tx-head {"from": hex}` -- 200
`{"head": hex}`, 64 zeros when the key has no record) and lays the record there only. The node takes a v2 record when its prev
equals the head and answers 200 `{"id","at","seq"}`; otherwise 409 `{"head": hex}` and nothing is written. The 200 of the chain's
node is the one moment the coins left; no other node's word counts for a v2 record. A receiver credits a v2 record only as read
from the chain's node of its `from`.

The nodes keep taking v1 records (builds 2190 and older send them) under the v1 rules.

## Phones (v2)

- Send: balance first; the head from the chain's node; build, sign, lay; 200 -- the debit stands ("tx:" + id); 409 -- the seed's
  own records are read first (another device sent meanwhile: its debit joins the book), the balance asked again, and one more try
  on the new head; a refusal or a request that never reached the node -- the coins come back ("txback:" + id); no answer -- the
  record waits on disk for the node's word.
- Receive: as in v1, every pipe's tag asked on every node; a v2 record is believed only from the chain's node of its key.

## What v2 does not close (named, not hidden)

- The node does not check a balance: the coins are minted in the seeds' books by the app's rules; a supply audit needs the minting
  recorded in the global TimeChain (the spec).
- A chain's node that is down stops that key's transfers until it answers: the coins stay with the sender (not left).
- A chain's node that loses its disk loses the records of its keys: a replica on the other node is the next step.
