# Montana node — Docker quickstart

Run a Montana node from a clean GitHub clone with one command. No Rust
toolchain on the host — everything builds and runs inside Docker.

## Build and run from source (recommended)

```bash
git clone https://github.com/efir369999/montana_messenger.git
cd montana_messenger/core/Code/docker/runtime
docker compose up -d --build
```

`docker compose` builds `montana-node:local` from the current checkout (multi-
stage: `rust:1.95-bookworm` builder → `debian:trixie-slim` runtime, ~5–10 min on
first build) and starts the container with a persistent `montana-data` volume.

The node starts in **singleton bootstrap mode** — it works out of the box with
zero external dependencies: it runs its own genesis TimeChain and cements a
Proposal every window. On first launch it generates a 24-word recovery mnemonic
and writes it to `/var/lib/montana/mnemonic.txt` (mode `0400`). Save it offline:

```bash
docker exec montana-node cat /var/lib/montana/mnemonic.txt
```

## Verify

```bash
# current_window advances every ~30–60 seconds:
docker exec montana-node /usr/local/bin/montana-node status --data-dir /var/lib/montana

# follow the consensus log:
docker compose logs -f
```

`status` prints `current_window`, `phase`, the Noise_PQ XX network `peer_id`,
and table sizes. A climbing `current_window` confirms the node is live.

## Join an existing mesh

The container reaches singleton consensus on its own. To instead **join** a
running cohort, the node needs a `genesis-manifest.json` listing peers with
**real dialable addresses**. The manifest checked into the repository
(`Code/scripts/genesis-manifest.json`) is a schema example: its multiaddrs are
`<placeholder>` tokens, not routable endpoints.

Provide a manifest with real peers, then mount it:

1. Write your `genesis-manifest.json` next to `docker-compose.yml`.
2. In `docker-compose.yml`, uncomment the manifest volume line and the
   `MONTANA_GENESIS_MANIFEST` environment line.
3. Recreate: `docker compose up -d`.

When a manifest is present the entrypoint switches to cross-machine mode:
`start --listen /ip4/0.0.0.0/tcp/8444 --genesis-manifest <path>`, dials the
listed peers over Noise_PQ XX (ML-KEM-768 + ML-DSA-65 + ChaCha20-Poly1305), and
multiplexes streams with Yamux. Set `MONTANA_MANIFEST_SHA256` to a pinned hash
to refuse start on manifest drift.

## Lifecycle on a live mesh

- After cemented-Proposal sync the node appears as `Candidate` in the network's
  Node Table.
- After the required sequential SHA-256 chain length plus the next selection
  event it transitions to `Active` and participates in the lottery.

The genesis cohort starts as a singleton bootstrap proposer
(`protocol_params.n_seed = 0`, `genesis_active_operators` empty); additional
nodes are discovery peers that earn `Active` status through the protocol, not a
hardcoded active set.

## Environment reference (entrypoint)

| Variable | Default | Meaning |
|---|---|---|
| `MONTANA_LISTEN` | `/ip4/0.0.0.0/tcp/8444` | libp2p listen multiaddr |
| `MONTANA_GENESIS_MANIFEST` | `/etc/montana/genesis-manifest.json` | manifest path; absent ⇒ singleton |
| `MONTANA_MANIFEST_SHA256` | _(unset)_ | refuse start unless manifest sha matches |
| `MONTANA_MNEMONIC` | _(unset)_ | fixed identity; otherwise generated once per volume |

## Build the image directly (no compose)

```bash
git clone https://github.com/efir369999/montana_messenger.git
cd montana_messenger/core
docker build -t montana-node:local -f Code/docker/runtime/Dockerfile.node .
docker volume create montana-data
docker run -d --name montana-node --network host --restart unless-stopped \
  -v montana-data:/var/lib/montana montana-node:local
```

The build context is the `core/` folder (the BIP-39 wordlist is compiled in
from the top of the tree), so `-f Code/docker/runtime/Dockerfile.node .` must be
run from the `core/` folder of the clone.

## Support

Open an issue: https://github.com/efir369999/montana_messenger/issues
