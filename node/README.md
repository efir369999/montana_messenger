# Montana full node in Docker

This folder builds and runs a full Montana node on your own Linux server with one
command. The node keys are created on your server the first time it starts and
never leave it. Nothing is reported to anyone unless you decide so.

Status: this kit has **not yet been built or run on a live server** by the project.
Read [What is not ready](#what-is-not-ready) before you rely on it.

## What you need

- A Linux server (x86_64 or ARM) with at least 2 GB free memory, 50 GB free disk
  and a steady connection of 10 Mbit/s or more. These minimums come from the
  project operator guide, not from a measurement of this kit.
- `git`, Docker Engine and the Docker Compose plugin (`docker compose version`
  must print a version). Use a Linux host: the compose file uses host networking.
- Patience for the first build: the image compiles OpenSSL and the node from
  source with one job, which can take a long time on a small server.

## Run it

```bash
git clone https://github.com/efir369999/montana_messenger
cd montana_messenger/node
docker compose up -d --build
```

Without a manifest the node starts in **singleton mode**: it runs its own genesis
TimeChain and needs no other server. To join a network, see
[Join a network](#join-a-network).

## Write down your recovery words, once

On the first start the node creates its identity and writes the 24 recovery words
into `/var/lib/montana/mnemonic.txt` inside the data volume (mode 0600, readable
only by the `montana` user). They are never printed to the container log.

Read them once and write them on paper:

```bash
docker compose exec -u montana montana-node cat /var/lib/montana/mnemonic.txt
```

The file holds the whole report of `montana-node init`: the words in a grid,
your `account_id`, `node_id` and `network_peer_id`. Anyone who reads the words
becomes your node; if you lose the volume and the words, the node is gone.
Never paste them into a chat, an issue, a log or an AI agent.

## Check that it is alive

```bash
docker compose exec -u montana montana-node montana-node status --data-dir /var/lib/montana
```

`status` prints `current_window`, `phase`, the network `peer_id` and table sizes.
Run it twice a few minutes apart: a growing `current_window` means the node is
live. Also:

```bash
docker compose ps        # STATUS shows healthy after the first checks
docker compose logs -f   # entrypoint lines first, then the node
```

The first entrypoint lines say which mode started (`singleton mode` or
`cross-machine mode`) and `no report: MONTANA_REPORT_URL is not set`.

## Join a network

A node joins a network through a `genesis-manifest.json` that lists peers with
real, dialable addresses. **This kit ships no peer list.** Get the manifest from
operators you trust; each operator reads the values for their own entry from the
`mnemonic.txt` report of their node (`network_peer_id`, `account_id`, `node_id`).
The node accepts a manifest only with exactly one peer marked `"bootstrap": true`
and with `account_id_hex` and `node_id_hex` of 64 hex characters each, so the
sample file here is refused until it is filled in.

1. `cp genesis-manifest.example.json genesis-manifest.json` and fill it in.
2. In `docker-compose.yml`, uncomment the manifest volume line and
   `MONTANA_GENESIS_MANIFEST`.
3. Optional: pin it. Put the output of `sha256sum genesis-manifest.json` into
   `MONTANA_MANIFEST_SHA256`; the node then refuses to start if the file changes.
4. `docker compose up -d`

In this mode the node listens on TCP 8444 and dials the listed peers; those peers
see your server address, as with any peer-to-peer node.

## Compete for Active

By default the node syncs and follows the chain without competing. To make it a
candidate, set `MONTANA_ENABLE_CANDIDATE: "1"` in `docker-compose.yml` and run
`docker compose up -d`. The log then shows `candidate enabled (--enable-candidate)`.

## Update

From the `node` folder of your clone:

```bash
git pull --ff-only
docker compose up -d --build
```

The data volume survives a rebuild, so the identity and the chain stay. If
`git pull --ff-only` refuses, the published history changed: stop and check.

## Roll back

From the `node` folder of your clone:

```bash
git log --oneline -- .          # pick the commit you trusted
git checkout <commit>
docker compose up -d --build
```

Return to the newest version with `git checkout main`.

## Never

- `docker compose down -v` or `docker volume rm`: they delete the data volume,
  and with it `identity.bin` and `mnemonic.txt`, the keys of your node.
- `tty: true` in the compose file, or a recovery phrase in an environment
  variable or a command line.

## What the node tells others

- **No report by default.** The entrypoint sends a status report only when you
  set `MONTANA_REPORT_URL` yourself; unset or empty, no report is sent anywhere.
- **No lookups.** The entrypoint asks no third-party service about your server
  (no geo-IP, no address check).
- **Peers.** In singleton mode the node dials nobody. In network mode it talks
  to the peers of your manifest, which see your address.
- **Build.** `docker compose up --build` downloads the base images from Docker
  Hub and the Rust crates (OpenSSL source included) from crates.io; those
  registries see your server address. Your node identity does not exist yet at
  that moment: it is created on the first start.

## Where the source comes from

`Code/` holds `montana-node` and the 18 crates it depends on, copied unchanged
from commit `ae36d1f` of the Montana protocol repository, together with its
`Cargo.lock` and `Montana wordlist.txt`. Only `Code/Cargo.toml` differs: its
workspace lists just these 19 crates. Cargo drops the lock entries of the other
crates at build time. `montana-node --version` reports git `unknown`, because
the build has no git metadata.

## What is not ready

- Not yet built or run on a live server by the project.
- No restore of an existing identity from its 24 words in this kit.
- No published peer list for joining the network.
- The Rust crates are fetched at build time, not vendored into this folder.

## Follow the TimeChain

Every step of this kit is described in the student TimeChain:
[TimeChain_Student.md](../TimeChain_Student.md). Check the chain yourself with
`python3 ../verify.py ../TimeChain_Student.jsonl` from this folder.
