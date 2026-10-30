# Coin transfer record v1 (MTTX) -- the one source of its format

The author's words 11.10.2026 16:5x-17:2x UTC (No.63): «a person is their seed and everything is in it»; «so I can pay them in
any scenario»; «either the coins left or not -- there is no third»; «on the TimeChain page an Explorer button to open and check a
transaction, and on any transaction a link that confirms the sending»; «everything professional in the TimeChain, for auditors».

A transfer is one record, signed by the sender's seed, laid on the nodes' append-only log. The node's 200 is the moment the coins
left: the sender's book takes the debit in the same turn, and no answer means nothing moved. The receiver's book finds the record
by the pair's tag -- on any build that reads it, at any later moment, on any device of its seed after a restore -- and credits it
once, by its id. A chat letter only tells about it. Historical for new records (marked 2026-10-27 UTC): from TX_V1_CUT (12.10.2026 21:00 UTC) the node takes no new v1 record ([COIN-TX-V3.md](COIN-TX-V3.md):290); the current record is v3.

## Record (5330 bytes, little-endian integers)

- offset 0, 4 bytes, magic: ASCII `MTTX`
- offset 4, 1 byte, version: `0x01`
- offset 5, 8 bytes, amount: u64, coins, 1 or more
- offset 13, 8 bytes, birth: u64, milliseconds since 1970-01-01 UTC, the sender's clock
- offset 21, 16 bytes, nonce: random
- offset 37, 32 bytes, pair: HMAC-SHA-256(key = the pair's pipe secret, message = ASCII `mt-coin-pair-v1`)
- offset 69, 1952 bytes, pubkey: the sender's ML-DSA-65 public key
- offset 2021, 3309 bytes, sig: ML-DSA-65 signature

- The sender's key: `seed = HKDF-Expand(master_seed, "mt-coin-tx", 32)` (core `mt_mldsa_seed_for_role`), keypair by
  `mt_mldsa_keypair_from_seed(seed)` -- the same on every device of the seed, unrelated to the identity's account key.
- Signed message: ASCII `mt-coin-tx-v1` (13 bytes) followed by bytes 0..2021 of the record. `mt_sign` / `mt_verify`.
- `id = SHA-256(record)`, lowercase hex, 64 characters -- the transaction's name everywhere.
- `from = SHA-256(pubkey)`, lowercase hex -- the sender's coin address.
- `pair` is known to both ends of the pipe and to no one else: an observer sees that address `from` paid a pair, never who the
  pair is; the receiver finds its records by the tags of its own pipes.

## Node log (montana-node-store, behind `/pushwake/` of api.montana.quest and api.montana.xxx)

Append-only: a record is never replaced or deleted; the same record laid again answers with its first entry.

- `POST /tx-put` `{"rec": base64}` -- 200 `{"id", "at", "seq"}` (`at` the node's seconds, `seq` the node's log index);
  400 a record of another size, magic or version, or amount 0; 429 rate; 507 the log's budget is full.
- `POST /tx-get` `{"id": hex}` -- 200 `{"rec", "at", "seq"}`; 404 none.
- `POST /tx-pair` `{"tags": [hex, ...], "since": seq}` -- 200 `{"txs": [{"id", "rec", "at", "seq"}, ...], "last": seq}`, at most
  256 tags and 512 records a call, ordered by seq.
- `POST /tx-recent` `{"since": seq}` -- 200 `{"txs": [...], "last": seq}`, the public feed for the Explorer, at most 100.

The node does not verify the signature in v1 (no audited ML-DSA in the node's Python); every reader verifies with the core before
it believes a record -- the phone before a credit, the Explorer before it shows "valid". A record with a bad signature stands in
the log as noise and moves no coin.

## Phones

- Send: balance first; build and sign; `tx-put` to every node's door; the first 200 is final -- `book.send(amount, to: the pair's
  conversation, ref: "tx:" + id)`; the other doors get it as well. No 200 from any door: nothing debited, the screen says not sent.
- Tell: a chat letter `🪙 N $TCM` with the confirmation link `https://montana.xxx/explorer/#tx={id}`; it credits nothing and burns no
  bubble coin. An older build reads it as words with a link (its coin parser asks for `montana://coin/1/`), so it credits nothing there either.
- Receive: the wallet asks `tx-pair` with the tags of all its pipes (at launch, at the wallet's opening, when a telling letter
  lands), verifies each record, and credits `book.receive(amount, from: conversation, ref: "tx:" + id)` once. A record from its
  own coin address is its own send (another device of the seed): debited once under the same ref.
- Confirmation link: `https://montana.xxx/explorer/#tx={id}`.

## Explorer (montana.xxx/explorer/)

Reads a record by id from both nodes, checks `SHA-256(rec) == id`, parses the fields, verifies the signature with the core
(`/app/core.js`, `mt_verify`), and shows: valid or not, amount, from, pair, birth, each node's `at` and `seq`, and the record's
hex. A feed of recent transfers from `tx-recent`.

## What v1 does not close (named, not hidden)

- Two devices of one seed can each sign against the same balance before their books meet: the order of a seed's records needs the
  TimeChain transfer record of the spec (per-seed sequence, cohort windows).
- The node cannot check a balance: balances live in the seeds' books; the global TimeChain carries no transfers yet.
- The receiver's coin address is not public (only the pair tag): a public receipt record is v2.
