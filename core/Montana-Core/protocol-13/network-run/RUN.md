# Protocol-13 item 13: the full network run, prepared (issue #24)

**Status: prepared, not run.** Only `run.py --dry-run` has been executed (exit 0, output in
[`dry-run.out`](dry-run.out)). The run itself waits for items 5-11 (#16-#22) to be merged into
`main`. Until then, this file describes what will run, what is expected, what evidence is kept,
and how a step fails.

**What this is.** This is our own reproduction, run with the author's permission on our own
servers, by the same council that writes the code. **It is not an independent external audit.** No
file it writes, and no report of it, may call it one (`Audit/Protocol-13/13-NETWORK-REPRODUCTION.md:5-7`,
`PROTOCOL-13.json:94`). The implementing session verifies itself, then the chairman reviews.

Read on `main` at `f1a5fad` (27.10.2026). Line numbers below are of that tree unless a branch or
pull request is named.

## 1. Gate -1: the map

### 1.1 Which generation runs the network

The network is run by **`core/Montana-Core`, binary `montana-node`**. It is the reference
implementation and its node binary (`core/README.md:12`). The live cohort net4 runs this binary:
`/opt/montana-core/bin/montana-node` with the flags of `main.rs` (read-only probe of Moscow,
`/opt/montana-core/net4.args`).

`core/Code` is "the client core ... and the earlier consensus line" (`core/README.md:13`). Its node
is another binary with another command line:
`montana-node start --data-dir --listen --genesis-manifest` over a libp2p multiaddress
(`core/Code/docker/runtime/node-entrypoint.sh:63-72`). Neither the requirement of item 13 (issue
#24, `PROTOCOL-13.json:90-95`) nor `13-NETWORK-REPRODUCTION.md` names a generation. Items 6 and 10
do name both explicitly (`PROTOCOL-13.json:45`, issue #21). **Whether `core/Code` must also run is
question Q5 for the author.** This run covers `core/Montana-Core` only.

### 1.2 How a machine starts

`USAGE`, `core/Montana-Core/crates/montana-node/src/main.rs:7-58`:

| Flag | Line | What it does |
|---|---|---|
| `--data <dir>` | `main.rs:13`, read `:465-468` | the store between starts |
| `--listen <addr:port>` | `:14`, `:469-472` | where it answers |
| `--acquaintance <addr:port@key>` | `:15-16`, `:473-476` | dialled at start (`:108-121`). One not reached is dialled again until it answers (`:171-173`, `pulse.rs:939-947`) |
| `--admitted <half>` | `:17-21`, `:477-480` | the opening cohort, this machine included. Without any, it serves and lives no window (`:133-136`) |
| `--open` | `:22-25`, `:482-485` | window 0 on an empty store; refused on a store holding a chain (`pulse.rs:963-977`) |
| `--windows <n>` | `:26-27`, `:494-501` | stop after n windows. The run does not use it |
| `--anchor <earlier> --anchor <later>` | **not in main** | added by PR #74 (`agent-608/issue-20-join`, `d2610af`): two consecutive final proposals; the machine walks to the head before anything else (`pulse::join`, `pulse.rs:2608`) |
| `--status --data <dir>` | **not in main** | added by PR #72 (`agent-609/issue-21`). Exits 0 for a close or a wait inside the patience, 1/2/4 for a stall or no diagnostics |

First start: the machine draws its secret and prints four lines (`main.rs:79-98`): "this machine
was born", "hand this to another operator: <acquaintance>", the digits to compare by voice, and
"hand this over too, to stand in one window: <half>".

Without `--open`, a machine on a store that holds a chain lives from `closed + 1`
(`pulse.rs:963-977`). On `main`, `live_doing` then refuses every window from 2 on, because the
proposal two windows back exists only in memory (`pulse.rs:1262-1267`; `README.md:146-149` says
#16 carries the fix). So **a restart past window 1 is refused on today's main**. This is
prerequisite P1.

### 1.3 How weight is distributed

Every machine of the electorate weighs alike. The quorum is a count of distinct parts against the
count of the electorate (`pulse.rs:98-100`). The share is `confirmation_quorum` = 67/100
(`mt-genesis/src/lib.rs:91`), compared by multiplying: `cement * 100 >= 67 * count`
(`mt-pulse/src/close.rs:12-31`). A close also needs its votes against the committee
(`pulse.rs:2350-2358`, `certificate.rs:209-240`).

| Electorate | Least cement that closes | Consequence |
|---|---|---|
| 3 (the live net4) | 3 (2 * 100 = 200 < 201) | every machine is needed; no majority partition can close |
| **4 (this run)** | **3** | a 3:1 split closes on the three; a 2:2 split closes on neither; two stopped lose the quorum |
| 5 | 4 | a 3:2 split closes on neither; 4:1 closes on the four |

**Weight in this run:** four admitted machines a, b, c, d of weight 1 each, quorum 3 of 4. No single
machine reaches the quorum alone, and the run checks this before anything starts. The fifth
machine e is not admitted; it joins in S7. This is the cohort of
`four_machines_decide_one_name.rs:1-2` and of `a_minority_waits_and_rejoins.rs` on
`agent-587/issue-16-k3`.

### 1.4 What a machine writes that proves a window, and who reads it

The store is `--data`, written by `mt-store` (`core/Montana-Core/crates/mt-store/src/lib.rs`):

| File | Line | What it is | Kept as evidence? |
|---|---|---|---|
| `identity` | `:495-497`, mode 0600 `:45` | the machine's secret | **never read** |
| `genesis` | `:455` | the network this store belongs to | no |
| `window` | `:18-21`, `:499-501`, `:639-658` | one record: head, last closed, and what the close keeps. Read as a secret (`:646`) because it carries the standing | **only its first 18 bytes**, the two marks (`:594-613`, `:934-958`) |
| `proposals/<window in 20 digits>` | `:503-507`, `:886-892` | the proposal of each window, the bytes of `Layout::bytes` (`montana-node/src/lib.rs:1151-1156`) | **yes, every one, byte for byte** |
| `agreement-<window>` | `:542-548` | the agreement record of an open window | names and sizes only |
| `points/<window>` | `:705-716` | the cells of a window's rounds: the certificate a device walks | count and bytes only (Q7) |

**The proposal is the evidence of a window.** Its layout is `mt-state/src/layout.rs:475-513`:
`window`, `protocol_version`, `previous`, seven roots (`note`, `nullifier`, `record`, `machine`,
`admitted`, `credited`, `operations`), `roll`, `admitted_count`, `cement_aggregate`,
`cement_count`, ten census entries, `suite_id`, then `final_beacon`, `runner_pubkey`,
`ticket_proof` (the proof), and the signature.

- Its name is `SHA-256("mt-proposal" || 0x00 || bytes[0..750])` (`mt-state/src/lib.rs:39`,
  `layout.rs:521-525`, `mt-codec/src/lib.rs:88-94`).
- `previous` is the name of the window before (`runner.rs:92`, refused otherwise at
  `pulse.rs:2083-2088`).
- A window is **final** on a machine once its head stands at it or past it. The head moves only when
  the cement of the window after reaches the quorum on it (`README.md:151-158`).

`run.py --parse` reads the window, name, link and roots out of these bytes with the standard
library. It was checked read-only against the live cohort on 27.10.2026 at about 18:2x UTC. For
windows 24, 25 and 26 of net4 on Moscow, the computed names `8301f2e4…`, `e6cb4df0…` and
`61bf2352…` equal the names the node logged ("window N is final under the proposal …"). The last of
them also equals the head the council's watch of net4 reads. `previous` linked 25 to 24 and 26 to 25, and
each cement counted 3 of 3.

The readers a machine offers:

- The log lines: `pulse.rs:1592` (decided), `:1902`/`:1906` ("window N is final under the
  proposal ID"), `:1933` ("window N closed after R rounds … the next links to the proposal ID"), and
  `main.rs:99-102`, `:151-154` (where it begins).
- `--status` after #21 (PR #72).
- The walk's line "walked from window W to the head at window H" after #20 (PR #74).

### 1.5 The in-process tests that already exercise each scenario

| Scenario of item 13 | On main | On a branch or PR, not merged |
|---|---|---|
| Window closure | `a_window_closes.rs:47`, `three_machines_live_a_window.rs:30`, `two_hosts_live_a_window.rs:34`, `four_machines_decide_one_name.rs:58` | |
| Quorum lost and recovered | at the quorum without a proposal: `a_quorum_without_a_verified_proposal_closes_nothing.rs:141`, `:226`. At the quorum, head and rights do not move: `a_count_at_the_quorum_moves_neither_head_nor_rights.rs:60`. An answer is required: `a_round_requires_an_answer.rs:9`. **No test stops machines and brings them back** | |
| Partition and reunion | `four_machines_decide_one_name.rs:58`: two halves parted while window 0 opens, healed after round 0 (`:5-13`) | `a_minority_waits_and_rejoins.rs:215` (`agent-587/issue-16-k3`, `8950b51`): 3:1, the minority waits, then rejoins by walking. **No green run** (#16, K4) |
| Restart | `a_window_outlives_the_restart_of_every_holder.rs:34`, `a_machine_keeps_what_it_holds.rs:88`, `a_network_opens_by_its_operator_alone.rs:165` | `a_machine_started_again_continues_its_chain.rs:51`, `a_machine_stopped_inside_a_window_resumes_it.rs:41` (both `8950b51`); `a_machine_alone_opens_a_network_and_lives_on_after_a_stop.rs:64` (PR #74) |
| A new machine joins | `a_walk_from_an_anchor.rs:46`, `a_device_joins_the_running_chain.rs:39` | `a_machine_away_walks_back_from_its_own_anchor.rs:84` (`8950b51`); `a_device_takes_the_plane_of_its_head.rs:76` and `mt-boundary/tests/a_device_joins_through_the_door.rs:77` (PR #74) |

All paths are under `core/Montana-Core/crates/montana-node/tests/` unless named otherwise. None of
these tests is a network of processes over real links. That is what this run adds.

### 1.6 Risks read from the tree

- **R1. A link lost after the start is never dialled again.** `reach_again` runs only for
  acquaintances not reached at the start (`main.rs:171-173`). It returns after the first success
  (`pulse.rs:939-947`). After a restart, the restarted machine dials the others, but they do not
  dial it back. In the in-process tests the test itself reaches both ways
  (`a_minority_waits_and_rejoins.rs`, "reach one another both ways"). A partition that drops packets
  longer than the kernel's retransmission bound (`tcp_retries2` 15, about 924 s) ends the links on
  both sides.
  The partition hold is therefore 600 s (Q3). Whether one-way links carry a window is what S3, S4
  and S6 will show.
- **R2.** A restart past window 1 is refused on main (§1.2). This is prerequisite P1.
- **R3. PR #74 does not fit main as it stands.**
  - Its `USAGE` says the last final window is `<data>/head`, eight bytes. Main's store has no such
    file: the head is the first mark of `window` (`mt-store/src/lib.rs:18-21`, `:594-613`), and
    opening refuses a store holding the earlier `head` file (`:395`).
  - Its `main.rs` context carries `[--from <window>]`, not main's `--open` (`main.rs:11`, `:22-25`).
    It must take main before it merges.
  - run.py reads `proposals/` and the marks of `window` only. It never reads `head`.
- **R4. Liveness (#65).** On net4, windows took attempt 7-8 and up to 1025 rounds (one window,
  ~14.5 min). The memory of a stalled window grew (#63). The window budget is set at 60 min (Q3).
- **R5.** A machine short of the quorum keeps turning rounds. A wait that is not answered gives up
  after `WAITS_UP_TO` askings, about one hour (`mt-pulse/src/lib.rs:34`, `pulse.rs:922`). The
  quorum-loss hold is 30 min, inside that.

## 2. Prerequisites: what main must carry before the run starts

| | What | Where it comes from | How run.py checks it |
|---|---|---|---|
| P1 | a restart lives on its own two stored proposals; a machine stopped inside a window resumes it | #16 K1, K2 (`agent-587/issue-16-k3`) | S3, S6 fail without it |
| P2 | a machine away walks back from an anchor; a minority rejoins by verifying | #16 K3, K4 | S4 fails without it |
| P3 | `--anchor` on the command line | #20, PR #74 | S0 refuses a binary whose `--help` lacks it |
| P4 | `--status` | #21, PR #72 | S0 refuses a binary whose `--help` lacks it |
| P5 | a window closes as one transition | #19 K1-K4 (in main) | invariants |
| P6 | liveness of a decided window (#65); memory (#63) | #65, #63 | window budgets |
| P7 | #17 (no clock or test bypass reaches the network), #18 (earlier core), #22 (anonymity) | #17, #18, #22 | not exercised here. #17 matters: the run uses the Decree as built, with no test override |

`topology.json` carries `required_commits`. The chairman fills it with the merge commits of #16-#22
once they exist, and S0 then requires each to be an ancestor of the commit built.

## 3. The hosts

Read-only probe, 27.10.2026 between 18:00 and 18:10 UTC (`uname`, `/proc/meminfo`, `nproc`,
`ss -ltn`, toolchains, `systemctl is-active`). Nothing was started or changed. Addresses, keys and
the production services of each host are left out, as this folder's rules require
(`protocol-13/README.md:13-15`). The chairman holds them in the agent's report.

| Host | Machine | Load at probe | What runs there | Role in this run |
|---|---|---|---|---|
| Lauterbourg-2 | Ubuntu 24.04.5, 16 CPU, 62.8 GiB (61.3 available), 218 GiB free | 1.04 / 1.77 / 4.11 | nothing listening but ssh; no montana unit; rustc 1.99.0 default (the tree pins 1.92.0); `ip`, `nft`, `tc`, `unshare` present | **topology A: all five machines** |
| Lauterbourg-3 | 18 CPU, 94.3 GiB (10.1 available), no swap | 43.9 (Kani) | Kani, by the author's word | **not used.** run.py refuses its alias |
| Lauterbourg (L1) | 4 CPU, 7.8 GiB, 16 GiB free | 0.68 | a node of net4, and production services | topology B only, with the author's permission |
| Moscow | 2 CPU, 3.8 GiB, 6.1 GiB free | 0.17 | a node of net4, and production services | topology B only, with the author's permission |
| Amsterdam | 1 CPU, 0.93 GiB (0.28 available), 1.3 GiB free, no Rust | 0.29 | a node of net4, and production services | too small for a second node |

The live cohort **net4** (Moscow, Amsterdam, L1) stood at window 26 at 17:57:40 UTC, named
`61bf2352…`. The run does not touch it: run.py refuses any store under `/opt/montana-core`. Its
cohort of three cannot show a majority partition anyway (§1.3).

### Topology A (in `topology.json`)

Five network namespaces `mt13-a` … `mt13-e` on Lauterbourg-2, each wired by a veth pair to a bridge
`mt13br` in a sixth namespace `mt13-hub`, addresses `10.13.0.1-5/24`, port 9635. Both ends of every
link are created inside namespaces. The host's own namespace gets no interface, listener, route or
firewall rule, and a machine's namespace has no default route (checked in S0). This is the
isolation `13-NETWORK-REPRODUCTION.md:9-12` asks for.

Each machine runs as a transient unit `systemd-run --unit mt13-<run>-<n> --collect`, with `Nice=10`,
`MemoryMax=6G` and its output appended to `<run>/<n>/node.log`. A stop is `systemctl stop` (SIGTERM).
A crash is `systemctl kill --signal=SIGKILL`.

A partition is an `nft` table `inet mt13`, made inside each machine's own namespace. It drops the run's
port to and from every machine outside the machine's group. A heal is `nft delete table inet mt13`.

### Topology B (not in `topology.json`; Q1)

Machines on separate hosts (L2 with L1 and Moscow), each in its host's own namespace on a new port.
run.py carries the per-host path: a node without `netns` runs its commands directly on its host, and
`cut` writes the same `inet mt13` table, limited to the run's port. It has not been exercised even
dry. A partition there means a firewall table on production hosts, which
`13-NETWORK-REPRODUCTION.md:11-12` rules out without the author's word.

## 4. The steps

Each step lists what is done, what is expected, and what evidence is kept. **Any expectation that
does not hold fails the step.** Every step ends with a snapshot, and the invariants below are
checked at every snapshot.

**Invariants (every snapshot):**

1. Every `proposals/<w>` carries window w.
2. On every machine, `proposal(w).previous = name(proposal(w-1))`.
3. **A final window has one name on every machine that holds it, and the same name across the whole
   run.**
4. Every final cement counts between 3 and 4 of 4.
5. Every "window N is final under the proposal ID" line in a log names the proposal that machine's
   store holds.

| Step | Done | Expected | Fails when |
|---|---|---|---|
| **S0 prepare** | refuse Lauterbourg-3 and `/opt/montana-core`; refuse a run directory that exists; clone or fetch, check out `--commit`, `cargo build --release --locked -p montana-node` in `core/Montana-Core` (its pinned 1.92.0); install the binary, keep its SHA-256; build the namespaces | HEAD = the commit; each `required_commits` is an ancestor; the build exits 0; `--help` names `--open --admitted --acquaintance --anchor --status`; ping a→b; no default route; quorum of 4 ≥ 2 | any of these. A missing prerequisite exits 2 |
| **S1 birth** | each of a…e started once with `--data --listen` under `timeout 30` | rc 124, "this machine was born", its acquaintance begins `10.13.0.x:9635@`, its half | any machine not born. Kept: `birth/<n>.out`, `born.json` |
| **S2 windows close** | a, b, c, d started with `--open`, the four halves, the other three acquaintances | every head ≥ 2 (windows 0-2 final) within 4 h | the budget runs out, a unit dies, or an invariant fails |
| **S3 quorum lost by a stop** | stop c and d; hold 30 min | a and b move neither head nor last closed; they keep their proposals; their status is present (rc ≠ 4) and reads no close past the last one. The text (`waiting: no quorum` or another) is kept | any change during the hold |
| **S3 recovered by a restart** | start c and d on their stores (no `--open`, no anchor) | every head ≥ head before + 2 within 3 h; earlier final proposals unchanged byte for byte | budget, a dead unit, a changed proposal |
| **S4 partition 3:1** | cut {a,b,c} \| {d} | a, b, c reach head + 2; d moves nothing and keeps no new proposal | the majority stalls, or the minority moves |
| **S4 reunion by verifying** | stop c (so no window closes without d); heal; stop d; restart d with `--anchor` = its own proposals (head-1, head) | d walks ("walked from window …" in its log) and a window closes on a, b, d. Its proposal counts cement 3 on all three, so d's presence counted. Then c restarts the same way and all four reach one more final window | budget, cement ≠ 3, no walk line, a second name |
| **S5 partition 2:2** | cut {a,b} \| {c,d}; hold 10 min | no machine moves head or last closed | any close |
| **S5 the parts meet** | heal, restart nothing | every head ≥ head before + 1 within 2 h; earlier finals unchanged | budget, a second name |
| **S6 restart of the whole network** | stop a, b, c (SIGTERM) and d (SIGKILL); start all four on their stores | all stopped; then every head ≥ before + 1 within 2 h; every proposal final before stands byte for byte | budget, a changed proposal |
| **S7 forged anchor** | e (born, empty store, not admitted) started with a's proposals (head-4, head-3), the later with byte 44 (`note_root[0]`) turned | refused: rc neither 0 nor 124 within 30 min; e's store holds no proposal and no marks | accepted, hung, or anything written |
| **S7 a new machine joins** | e started with the honest anchor and the four acquaintances | e's head ≥ a's head at the start of the step; e's proposals from the anchor to its head carry a's names; its log ends the walk at its head | budget, a different name, no walk line |
| **finish** | a last snapshot; every unit stopped; stores, logs and namespaces stay until `--teardown` | | |

When an expectation fails, the steps after it are not run (`--keep-going` runs them). The last
snapshot and the manifest are written either way.

## 5. The evidence

`evidence/<run-id>/` beside this file:

| Path | What |
|---|---|
| `manifest.json` | run id, commit, binary SHA-256, topology, finish time, exit code, the step that stopped the run, the name of every final window, and the sentence "not an independent external audit" |
| `commands.json` | every remote command as an argument list, with its host, UTC time and exit code |
| `checks.json` | every expectation: step, text, held or failed, detail, UTC time |
| `windows.json` | per final window: name, `previous`, the seven roots, `admitted_count`, `cement_count`, and for each machine holding it the SHA-256 of its bytes, its final beacon and size |
| `objects/<sha256>.proposal` | the bytes of every proposal any machine held: roots, `ticket_proof` and signature inside. Stored once per content |
| `snapshots/<nn>-<label>/<n>.json` | per machine: the two marks, unit state, window → proposal SHA-256 and parsed fields, agreement names and sizes, points count and bytes, `--status` exit code and text |
| `logs/<n>.log` | each machine's whole output |
| `birth/`, `join/` | the birth lines, the forged proposal and the refusal |
| `binary.sha256`, `SHA256SUMS` | the binary, and SHA-256 of every file of the directory |

Never kept: `identity`, the `window` record past its marks, the contents of `agreement-*` and
`points`.

A partial run is marked partial: `manifest.json` names the step that stopped it, and `checks.json`
holds only the expectations reached.

## 6. Commands

```
python3 core/Montana-Core/protocol-13/network-run/run.py --dry-run          # prints every command, exit 0
python3 core/Montana-Core/protocol-13/network-run/run.py --commit <40 hex of main> [--run-id ID]
python3 core/Montana-Core/protocol-13/network-run/run.py --teardown --run-id ID
python3 core/Montana-Core/protocol-13/network-run/run.py --parse evidence/<id>/objects/*.proposal
```

`run.py` runs on the operator's machine, which holds the ssh aliases. It uses the standard library
only. Every remote command is an argument list run by a small executor (`REMOTE` in run.py) that
ssh starts as `python3 -I -c <boot>`, so no shell parses a value of the run on either side.

Exit codes: 0 every expectation held; 1 one failed; 2 the run could not be carried out (refused
host or path, unreachable host, missing prerequisite, failed build).

## 7. Questions only the author can decide

Each question gives the options and a recommendation. None of them is decided here.

- **Q1. Which hosts.**
  (a) Topology A: five namespaces on Lauterbourg-2.
  (b) Topology B: L2, L1 and Moscow on a new port, with a firewall table on production hosts.
  (c) A, then a short B to show windows closing over real links.
  (d) Stop net4 and use its hosts.
  *Recommendation: (a).* It isolates the run (`13-NETWORK-REPRODUCTION.md:9-12`), controls the
  partitions, and touches no production host. Choose (c) only if the author wants cross-host
  closure, and (d) only after #65's six-hour watch has ended.
- **Q2. How many machines.**
  (a) Four admitted plus one joiner.
  (b) Five admitted (quorum 4) plus one joiner.
  (c) Seven.
  *Recommendation: (a).* With quorum 3 of 4, both a 3:1 and a 2:2 partition can be shown, and it is
  the cohort of the in-process tests (§1.3).
- **Q3. How long.**
  (a) Defaults: window budget 60 min, quorum-loss hold 30 min, partition hold 10 min; 6-12 hours in
  all.
  (b) Add a long partition (30 min or more, beyond the TCP bound) as its own step. On today's code,
  R1 predicts it fails.
  (c) Shorter.
  *Recommendation: (a), and (b) as a separate decision once R1 is answered.*
- **Q4. Which commit.**
  (a) The first main that carries all of #16-#22, as the chairman's order says.
  (b) The first main carrying #16, #20 and #21, the three the run needs in order to execute,
  recording the others as not carried.
  *Recommendation: (a).*
- **Q5. `core/Code`.**
  (a) Montana-Core only.
  (b) Both generations, with a second scenario script for `core/Code`'s node.
  *Recommendation: (a).* The requirement names no generation, items 6 and 10 name both where both
  are meant, and `core/Code` is the earlier line (§1.1).
- **Q6. What "a new node joining" means.**
  (a) A fresh machine that is not admitted walks from an anchor to the head. That is what the
  command line can do after PR #74.
  (b) A new machine admitted to the electorate and counted in a later quorum. That needs the
  admission path of item 4 reachable from the operator's command line, which main lacks.
  *Recommendation: (a) now, with (b) named as not shown.*
- **Q7. Evidence volume and where it is published.**
  (a) Every proposal (about 340 KB each, stored once per content), the logs and the statuses;
  points summarized.
  (b) Also the points of the retained windows, the certificates, which may be hundreds of MB
  (#65).
  Where: (i) committed under `evidence/<run-id>`; (ii) the small files committed and the objects as
  a release asset whose SHA-256 sums are committed.
  *Recommendation: (a) with (ii).*
- **Q8. Lauterbourg-2 during the run.**
  (a) Exclusive.
  (b) Shared with agents' test rings (load 4.11 at the probe).
  *Recommendation: (a).* The protocol reads no clock, but contention stretches windows against
  their budgets.

## 8. What was run here

| Command | Where | Exit code |
|---|---|---|
| `python3 -B run.py --dry-run --run-id DRYRUN` | the operator's Mac; prints 16 snapshots and every command (`dry-run.out`) | 0 |
| `python3 -B run.py --teardown --dry-run --run-id DRYRUN` | the same | 0 |
| `python3 -B run.py --run-id X` (no `--commit`) | the same; refused | 2 |
| offline check of `snapshot()` and the invariants, with `remote` stubbed and fed the three net4 proposals of §1.4 | the Mac, no server | honest bytes: 5 of 5 invariants held. One byte of `previous` of window 26 turned: "every chain links by identifier" and "the logs and the stores agree" failed |

## 9. What is not done

- **The run.** Nothing was started on any server. The only remote actions were the read-only probes
  of §3 and the read of three net4 proposals and their log lines in §1.4. Only the dry run was
  executed.
- No verifier independent of the node checks `ticket_proof` or the signatures. The node's own walk
  (S7) is the verifier the run uses. run.py recomputes names, links, roots and cement counts from
  the bytes.
- After a join, e is not checked to follow later heads (Q6). The four readings of #21 are recorded
  in each snapshot but not asserted one by one.
- Topology B is written but not exercised, even dry. `core/Code` is not covered (Q5).
- `13-NETWORK-REPRODUCTION.md` and `PROTOCOL-13.json` are unchanged: item 13 stays open.
