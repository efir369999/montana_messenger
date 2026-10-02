# Montana full node in Docker

This folder builds and runs a full Montana node on your own Linux server with one
command. The node keys are created on your server the first time it starts and
never leave it. Nothing is reported to anyone unless you decide so.

Status: this kit has **not yet been built or run on a live server** by the project.
Read [What is not ready](#what-is-not-ready) before you rely on it.

## The server

This chapter is written so that you, or the AI agent working for you, can rent and
prepare a server from this page alone. Every figure about the node comes from its
source code or the project operator guide. Where nothing has been measured, the text
says **not measured yet**.

### What to rent

| Item | What to ask for | Where the figure comes from |
|---|---|---|
| Architecture | x86_64 (amd64) or 64-bit ARM (arm64), a CPU from 2017 or newer | operator guide |
| CPU | 1 vCPU runs the node: it is single-threaded. 2 vCPU leave room for the system. The image build compiles with one job, so more cores do not shorten it | project service unit; `Dockerfile` |
| CPU features | A CPU with SHA extensions (SHA-NI; the guide names Intel 11th generation or newer and AMD Ryzen) is recommended: the operator guide states 10 to 20 seconds of work per window on such a CPU, then idle | operator guide |
| Memory | At least 2 GB free. Memory of the running node: **not measured yet**. Memory needed by the first build: **not measured yet** (add swap if the build is killed, see the checklist) | operator guide |
| Disk | At least 50 GB free. Growth per day: **not measured yet** | operator guide |
| Network | A steady 10 Mbit/s or more. Traffic per month: **not measured yet** | operator guide |
| Electricity (home servers) | One loaded core 5 to 15 W | operator guide |

### Which operating system

A plain 64-bit image of a current Ubuntu LTS (24.04 or 22.04) or Debian (12 or 13),
on a version that Docker Engine lists as supported at
https://docs.docker.com/engine/install/ . The node itself runs inside the
container (Debian 13 runtime, Debian 12 builder), so the host only needs Docker.

### Checkboxes when ordering

- **Public IPv4: yes, dedicated.** Not a shared or "NAT VPS" address with a port
  range. In network mode the node listens on TCP 8444. Behind NAT it still works
  through outbound connections, but worse (operator guide).
- **IPv6: optional.** This kit listens on IPv4 only (`/ip4/0.0.0.0/tcp/8444`).
- **SSH key: yes, password: no.** Upload your public SSH key with the order.
- **Control panel, one-click apps, preinstalled stacks: no.** Take the plain OS image.
- **Snapshots or backups: your choice.** A snapshot contains the data volume, so
  it contains your node keys: treat it as a secret.
- **Billing: monthly**, no long contract.

### How to choose a provider (criteria only)

This page names no provider. Check each criterion in its offer and terms:

1. A dedicated public IPv4 address, not behind provider NAT.
2. Inbound and outbound TCP are not filtered, including port 8444. The node uses
   **TCP only**: its network stack is built with the TCP transport and no UDP
   transport, so UDP filtering does not affect it.
3. A full virtual machine (KVM or similar) with its own kernel, so Docker Engine
   runs; not a container-based VPS.
4. At least 2 GB memory and 50 GB disk in the plan.
5. Monthly billing, no minimum term.
6. A country and jurisdiction you are comfortable with; the protocol needs none in
   particular.
7. Terms of service that allow peer-to-peer software running all the time.

### Ports

| Port | Open? | Why |
|---|---|---|
| TCP 22 (SSH) | Yes, ideally only from your own address | to administer the server |
| TCP 8444 inbound | Only in network mode (with a manifest) | the node listens here only when a manifest is given; in singleton mode it starts no network at all |
| Outbound TCP | Yes, all | the node dials its peers; the build downloads images and crates |
| UDP | Not needed | the node uses no UDP |
| TCP 2375 / 2376 (Docker API) | **Never** | whoever reaches it controls the server |
| Anything else | No | nothing else in this kit listens |

Set the same rules in the firewall of the provider (if it has one) and on the
server. With `ufw`:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 8444/tcp      # only if you join a network
sudo ufw enable
```

### Install Docker the official way

Follow https://docs.docker.com/engine/install/ for your distribution (the apt
repository of Docker), or use the official convenience script, which the project
installer also uses:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
docker --version
docker compose version
```

Both version commands must print a version.

### Checklist for the first hour

1. **Update the system:** `sudo apt update` then `sudo apt full-upgrade -y`; reboot
   if a new kernel was installed.
2. **Close password login.** Create a user with sudo and your SSH key, then in
   `/etc/ssh/sshd_config` set `PasswordAuthentication no`,
   `KbdInteractiveAuthentication no` and `PermitRootLogin prohibit-password`.
   Check with `sudo sshd -t`, reload with `sudo systemctl reload ssh`, and test a
   new login in a second terminal before you close the first one.
3. **Firewall:** the `ufw` rules above.
4. **Time by NTP:** `timedatectl` must show `System clock synchronized: yes` and
   `NTP service: active`; if not, `sudo timedatectl set-ntp true`. HTTPS downloads
   and readable logs depend on a correct clock.
5. **Security updates:** `sudo apt install -y unattended-upgrades` (often already
   present on Ubuntu).
6. **Swap, if the server has 2 GB:** the memory of the first build is not measured
   yet. If the build stops with `killed` or exit code 137, add swap and build again:
   `sudo fallocate -l 4G /swapfile`, `sudo chmod 600 /swapfile`, `sudo mkswap /swapfile`,
   `sudo swapon /swapfile`.

### For your AI agent

Do these steps in order. Stop and ask the owner at every step marked OWNER.

1. **OWNER: rent the server** by the criteria above; note its public IPv4 address
   and give the agent SSH access with a key.
2. **Log in:** `ssh USER@SERVER_IPV4`.
3. **Update and harden:** checklist steps 1 to 5.
4. **Install Docker** as above and check both version commands.
5. **Fetch and start the node:**
   `git clone https://github.com/efir369999/montana_messenger`,
   `cd montana_messenger/node`, `docker compose up -d --build`.
   If the build is killed for lack of memory: checklist step 6, then build again.
6. **OWNER: the recovery words.** Do not read `mnemonic.txt` yourself and never put
   it into your context, a log or a message. Ask the owner to run the command of
   [Write down your recovery words](#write-down-your-recovery-words-once) in their
   own terminal.
7. **Check that it is alive:** run the `status` command of
   [Check that it is alive](#check-that-it-is-alive) twice, a few minutes apart;
   `current_window` must grow; `docker compose ps` must show `healthy`.
8. **Optional, OWNER decides:** join a network ([Join a network](#join-a-network))
   or compete for Active ([Compete for Active](#compete-for-active)).
9. **Keep it current:** check for new changes with
   `git -C montana_messenger fetch` and
   `git -C montana_messenger log --oneline HEAD..origin/main -- node`. Read the newest
   records of [TimeChain_Student.md](../TimeChain_Student.md) and check the chain
   with `python3 montana_messenger/verify.py`. Then update as in [Update](#update)
   and repeat step 7.
10. **If an update breaks the node:** [Roll back](#roll-back) and repeat step 7.

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

## Restore a node from its 24 words

This works only on a **fresh volume** (no `identity.bin` yet). On a volume that
already holds an identity, the file is ignored with a log line.

1. Write the 24 words, separated by spaces, into a file **outside the clone**, for
   example `~/restore-words.txt`, and run `chmod 600 ~/restore-words.txt`.
2. From the `node` folder: `docker compose build`, then `docker compose create`.
3. `docker compose cp ~/restore-words.txt montana-node:/var/lib/montana/restore-words.txt`
4. `docker compose start`

The entrypoint passes the words to `montana-node init --mnemonic-stdin` through
standard input, never on a command line and never into the log. The log then shows
`identity restored; restore-words.txt renamed to restore-words.used`. The renamed
file stays on the volume and still holds the words; remove it, and the copy in
your home folder, once the node runs with the right `node_id`. If the words are
wrong, the log shows the error (a word count or a word position, never a word), the
file is kept and the container stops.

This path is **not yet tested** on a live server.

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

`Code/` holds `montana-node` and the 18 crates it depends on, copied from commit
`ae36d1f` of the Montana protocol repository, together with its `Cargo.lock` and
`Montana wordlist.txt`. The copy differs from that commit in two places only: the
workspace of `Code/Cargo.toml` lists just these 19 crates, and the test fixture and
one comment of `mt-genesis/src/manifest.rs` use neutral peer labels and example ids. Cargo drops the lock entries of the other
crates at build time. `montana-node --version` reports git `unknown`, because
the build has no git metadata.

## What is not ready

- Not yet built or run on a live server by the project.
- The restore path from 24 words is not yet tested.
- Memory, disk growth and traffic of a running node are not measured yet.
- No published peer list for joining the network.
- The Rust crates are fetched at build time, not vendored into this folder.

## Follow the TimeChain

Every step of this kit is described in the student TimeChain:
[TimeChain_Student.md](../TimeChain_Student.md). Check the chain yourself with
`python3 ../verify.py ../TimeChain_Student.jsonl` from this folder.
