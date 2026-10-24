# Your own node

A machine you own becomes the storage of your Montana: the sealed copies of your whole phone, and every photo, video, voice and
file of your chats in sealed pieces. With it the app can clear its cache and weigh almost nothing; on a new phone your 24 words
and the address of your machine bring everything back.

Two files, one source -- the app carries these very bytes and puts them on your machine itself:

- `montana-home-node.py` -- the door. Python 3 standard library only.
- `install.sh` -- the set-up: a user `montana`, its folders, the unit `montana-node-store`, a certificate the machine makes for
  itself on port 8463, and the certificate's SHA-256 fingerprint printed at the end.

## Set it up

**From the app.** Settings, Your node: the machine's address, its login and password, then *Set up your node*. The app writes the
door over SSH, runs `install.sh`, and keeps only the fingerprint of the certificate; the password is used once and kept nowhere.
The machine needs SSH password login for that one run.

**By hand**, on a clean Debian or Ubuntu machine, as root:

```sh
git clone https://github.com/efir369999/montana_messenger
sudo bash montana_messenger/apps/messenger/ios/Code/Node/install.sh <the address or name of this machine>
```

A machine behind a name with a certificate of a public authority (nginx in front) needs no
fingerprint: proxy `/pushwake/` to `http://127.0.0.1:8462/`, give `/pushwake/vault-` an unbuffered body without a ceiling and
`/pushwake/home-` a ceiling of 16 MB, and enter the name in the app.

## What the machine sees

A shelf is named `sha256(token)`, and the token is derived from your 24 words alone (HKDF-SHA-256, then HMAC-SHA-256); the door
stores no seed, no key and no list of tokens. Whoever holds the token opens that one shelf and nothing else; a stranger's token
sees an empty shelf. On the shelf lie sealed bytes under names the phone checks itself when it opens them. The book of which
file is which pieces lies there too, sealed under a key your words derive, under a name your words derive.

## The rooms

| Room | What it does |
|---|---|
| `GET /health` | what this machine offers: `vault` (copies), `home` (files) |
| `GET /vault-have` | the copies a shelf holds, newest first, and the room left |
| `PUT /vault-put?name=&sha256=` | a copy, streamed; held only when the digest matches; the newest two stay |
| `GET /vault-get?name=` | a copy back |
| `POST /home-put` `{bid, data, over?}` | one sealed piece; `held` is the node's word |
| `POST /home-have` `{bids}` | which of these pieces the shelf holds -- the phone clears its cache only on this word |
| `POST /home-get` `{bid}` | a piece back |
| `POST /home-drop` `{bids}` | the owner takes pieces away |

Every room but `/health` asks the header `X-Montana-Vault: <token>`. A shelf holds at most `VAULT_SHELF_GB` (64) of copies and
pieces together, and the disk keeps `VAULT_FLOOR_GB` (10) free; past that the node answers `507 no room`.

## As a node of the network

The same door serves more of what a node owes the network when its unit names it: `MONTANA_CAPS=vault,blob,box,signal,stun`
(attachments in transit, letters for sleeping phones, call signalling, the address reflector). Today the app uses your node for
your copies and your files; letters and calls ride the network's doors.

## Check it

```sh
curl -s http://127.0.0.1:8462/health
systemctl status montana-node-store
```
