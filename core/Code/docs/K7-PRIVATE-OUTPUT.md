# Item 11 K7: private initialization and default node diagnostics

Base: `4c6430a6feb54527606e3e93023ec71219c2c352`. Refs #22.
Status: proposed code; Rust compilation/runtime checks are pending. No anonymity closure.

## Cause and ownership

At the base, `commands/init.rs:46-68,99-115` sends the recovery phrase to a
controlling terminal or stdout, and prints identity-derived identifiers. The
container had protected only its own invocation. The CLI now owns recovery:
exclusive creation of `mnemonic.txt` in the data directory (or the explicit
`--recovery-file`), Unix mode 0400 before writing, file and parent-directory
sync before saving identity.bin. An existing recovery file or symlink is
refused even with `--force`. The phrase has no terminal/stream fallback.

A failed write retains its private partial artifact for operator inspection;
there is no automatic cleanup or retry that overwrites it. If identity saving
fails after recovery was saved, the recovery file remains and the command
fails. Non-Unix initialization refuses until an owner-only filesystem
implementation exists; no permissive cross-platform fallback is claimed.
`--force` may use a fresh explicit recovery path; it cannot overwrite the old
recovery. The entropy parser rejects non-ASCII before byte slicing, so malformed
input cannot trigger that UTF-8 slice panic. Invalid phrase and CLI errors do
not echo supplied input in the init command's stderr.

The container keeps diagnostics in a separate exclusive 0400 `init.log`, invokes
the same recovery writer, keeps stdin-based recovery input and detaches from
its controlling terminal. Existing recovery or diagnostic files stop bootstrap.
A failed init still prevents start. This requires the entrypoint and node binary
from the same source version. The shell fixture is not a real-container test.

## Default diagnostics

The `private_diagnostic!` boundary evaluates detailed formatting only when the
local operator explicitly sets `MONTANA_PRIVATE_DIAGNOSTICS=1`. Every other
value, including an absent or empty variable, selects a fixed public event
category. Default records retain success/failure categories; unaffected progress
records retain counts and windows. Nested errors cannot bypass the boundary at
the migrated sites. The raw request-response event dump is replaced by a fixed
category, including in detailed mode: arbitrary event payloads are not dumped.

The opt-in is for local diagnosis only. It exposes own/peer identifiers,
addresses and diagnostic error details to stderr; do not enable it in shared
logs or a public service configuration. It is not an anonymizing log mode.
The init command never enables recovery-phrase output through this switch.
The main `start` failure path also uses the boundary, covering errors returned
by argument parsing, manifest parsing and network setup.

`inspect`, `status` and `time` are deliberate operator queries, not the default
long-running node log. Their outputs remain as listed below; `inspect
--reveal-master-seed` remains an explicit secret-export operation. The benchmark
binary is unchanged. No subscriber is installed here for dependency tracing;
this source inventory is not a proof of every possible dependency/OS output.

## Checks and counterexamples

- `python3 -I -B core/Code/docker/runtime/tests/bootstrap.py`: 0, seven cases.
  They exercise the real shell entrypoint with a real controlling terminal and
  fixture commands. On the base entrypoint, these updated contract tests exit
  1: it does not separate init.log from the CLI-owned recovery file. This does
  not represent a before/after run of the actual Rust node.
- `bash -n core/Code/docker/runtime/node-entrypoint.sh`: 0.
- `rustfmt --edition 2021 --config-path core/Code/rustfmt.toml` on the seven
  changed/new Rust source/test files: 0. Formatter only; no Rust compilation.
- `git diff --check`: 0.
- Written but **not run**: `cargo test -p montana-node --test private_init`
  (five cases: private usable recovery, existing-file/force refusal, symlink
  refusal, error redaction, explicit-path exclusivity).
- Written but **not run**: `cargo test -p montana-node --lib diagnostics::tests`
  (default never invokes the detailed formatter; only exact opt-in enables it).
- Existing `e2e_init` constructors now name the recovery option; its forced
  replacement uses a new recovery file. Its test execution is **pending**.
- **Not run:** Cargo workspace fmt check, Clippy, full tests, doctests, doc,
  release build, real Docker ownership tests and live transport captures.
  No new server workload was launched for this patch. The current L2 audit
  tests its original source pin and supplies no evidence for this branch.

A before/after executable regression run is still required by the chair's
assignment. The draft is not ready for acceptance until the Rust checks and
real caller behavior have been checked. Keep the new core untouched until PR
#50 settles; its logging work is separate. Wire keys, source-address anonymity,
DNS, historical exposure, rotation and the other Gate 0 choices stay open.

## Separate self-review

Operator perspective: recovery refusal precedes identity replacement; partial
private files survive failures; the container starts only after successful init.
Privacy perspective: default logging does not invoke migrated private
formatters; explicit debug mode remains revealing, and logging hygiene cannot
hide identities carried on the network. No independent external review is claimed.

## Output-site inventory

Lines below refer to this proposed tree. `gated` means changed to a fixed public
category plus explicit local detail opt-in. `kept` means unchanged public
progress/counter/static text in start/network, or the explicit operator commands
identified above. `init` records are new non-secret status text. The old init
phrase/identifier output and `/dev/tty` writer are replaced, not redirected.

| File:line | Policy | Output format (first literal) |
|---|---|---|
| `commands/init.rs:52` | init | identity initialized; recovery phrase saved to the private recovery file |
| `commands/init.rs:53` | init | file size: {IDENTITY_FILE_SIZE} bytes; identity mode: {IDENTITY_FILE_MODE:o} |
| `network.rs:58` | gated | [network] network configured |
| `network.rs:84` | gated | [network] dialing peer |
| `network.rs:107` | gated | [network] listening |
| `network.rs:114` | gated | [network] connection established |
| `network.rs:130` | gated | [network] connection closed |
| `network.rs:136` | gated | [network] outgoing connection failed |
| `network.rs:147` | kept | [network] RR Request msg_type={:?} request_id={} payload_len={} |
| `network.rs:155` | gated | [network] heartbeat response failed |
| `network.rs:160` | gated | [network] incoming message forwarding failed |
| `network.rs:173` | gated | [network] heartbeat acknowledged |
| `network.rs:178` | fixed category; raw event dump replaced | [network] request-response event |
| `network.rs:186` | gated | [network] redialing peer |
| `network.rs:208` | kept | [network] broadcast {msg_type_dbg:?} request_id={rid} to {peer_count} peer(s) |
| `network.rs:214` | kept | [network] Ctrl-C, exiting |
| `commands/start.rs:85` | kept | [names] name layer ENABLED |
| `commands/start.rs:116` | kept | WARNING: --d-test-override={d} is active. This is a test-only mode. \ In production D = params.d0 = {} iterations (Genesis Decree). |
| `commands/start.rs:168` | kept | === montana-node start — Montana node === |
| `commands/start.rs:169` | kept | (empty line) |
| `commands/start.rs:170` | gated | [node] data directory selected |
| `commands/start.rs:175` | gated | [node] account identity loaded |
| `commands/start.rs:180` | gated | [node] node identity loaded |
| `commands/start.rs:185` | kept | phase : {:?} |
| `commands/start.rs:186` | kept | current_window : {current} |
| `commands/start.rs:187` | kept | D : {} SHA-256 iterations / window |
| `commands/start.rs:191` | gated | [node] timechain value loaded |
| `commands/start.rs:196` | kept | balance start : {} nɈ ({} Ɉ) |
| `commands/start.rs:202` | kept | stop_at : window {stop} (in {} windows) |
| `commands/start.rs:207` | kept | stop_at : Ctrl-C |
| `commands/start.rs:213` | kept | candidate SSHA : progress {}/{}, {} windows left to registration |
| `commands/start.rs:218` | kept | (empty line) |
| `commands/start.rs:219` | kept | --- SSHA ticking --- |
| `commands/start.rs:220` | kept | (empty line) |
| `commands/start.rs:261` | kept | fast-sync lag : threshold {fast_sync_lag_threshold} windows |
| `commands/start.rs:285` | kept | [consensus] replaying archived envelope w={current} after restart |
| `commands/start.rs:360` | kept | (empty line) |
| `commands/start.rs:361` | kept | [shutdown] received SIGINT/SIGTERM, saving state... |
| `commands/start.rs:366` | kept | (empty line) |
| `commands/start.rs:367` | kept | [stop_at] reached target window {stop} |
| `commands/start.rs:390` | gated | [node] incoming message processing failed |
| `commands/start.rs:517` | gated | [node] registration recorded |
| `commands/start.rs:554` | kept | [cold-start W={next_window}] self-admit \u{2192} Active (admitted={}) |
| `commands/start.rs:577` | kept | [lookback W={propose_w}] acting as fallback leader (depth {my_depth}) |
| `commands/start.rs:715` | gated | [node] lottery evaluated |
| `commands/start.rs:788` | gated | [node] archive write failed |
| `commands/start.rs:801` | gated | [node] broadcast failed |
| `commands/start.rs:806` | kept | [consensus] broadcast CEMENTED Proposal window={propose_w} → peers (bundles={}, evidence={}) |
| `commands/start.rs:827` | kept | (empty line) |
| `commands/start.rs:828` | kept | --- session ended --- |
| `commands/start.rs:829` | kept | phase : {:?} |
| `commands/start.rs:830` | kept | candidate SSHA : {}/{} |
| `commands/start.rs:834` | kept | windows processed : {session_windows} (Active phase only) |
| `commands/start.rs:835` | kept | emitted : {} nɈ ({} Ɉ) |
| `commands/start.rs:840` | kept | session wall : {:.1}s |
| `commands/start.rs:846` | kept | balance final : {} nɈ ({} Ɉ) |
| `commands/start.rs:1233` | kept | [selection W={settled_w}] activated {activated_count} node(s) |
| `commands/start.rs:1243` | kept | [next_d W={settled_w}] D: {} → {} |
| `commands/start.rs:1257` | kept | [target W={settled_w}] {:#x} → {:#x} (tickets in τ₂: {}) |
| `commands/start.rs:1296` | kept | [consensus] Proposal envelope wrong size {} — skip |
| `commands/start.rs:1307` | kept | [consensus] TIMECHAIN DIVERGENCE w={w}: envelope != local — skip |
| `commands/start.rs:1336` | kept | [consensus] behind (head {}, network at {w}) — signaling with own envelope |
| `commands/start.rs:1349` | kept | [m7] fast-sync deadline exceeded — drop client, retry |
| `commands/start.rs:1377` | kept | [m7] {} windows behind (> {}) → fast-sync anchored at window {w} |
| `commands/start.rs:1386` | gated | [node] broadcast failed |
| `commands/start.rs:1405` | kept | [consensus] cemented w={w} gap (current={}) — awaiting sequential cementing or fast-sync |
| `commands/start.rs:1426` | kept | [consensus] peer on stale window {w} — re-served {served} envelope(s) up to {upto} |
| `commands/start.rs:1438` | gated | [node] proposal header refused |
| `commands/start.rs:1464` | gated | [node] node identity loaded |
| `commands/start.rs:1472` | kept | [consensus] w={w}: envelope target != local — calibration divergence, skip |
| `commands/start.rs:1478` | kept | [consensus] cemented w={w}: envelope tail not parsed — skip |
| `commands/start.rs:1509` | kept | [consensus] w={w}: included_bundles {sum} < quorum {} — skip |
| `commands/start.rs:1516` | kept | [consensus] w={w}: endpoint disagreement in included_bundles — skip |
| `commands/start.rs:1539` | kept | [consensus] w={w}: cementing evidence {ev_sum} < quorum {need_quorum} — skip |
| `commands/start.rs:1564` | kept | [consensus] w={w}: included_reveals_root mismatch — skip |
| `commands/start.rs:1569` | gated | [node] winner refused |
| `commands/start.rs:1577` | kept | [consensus] w={w}: ticket pool incomplete ({}/{}) — winner accepted by quorum |
| `commands/start.rs:1595` | kept | [consensus] w={w}: state_root divergence — window rejected, recovery via fast-sync |
| `commands/start.rs:1612` | gated | [node] archive write failed |
| `commands/start.rs:1621` | gated | [node] proposal applied |
| `commands/start.rs:1665` | kept | [m7] served FastSync snapshot: anchor_window={} req={} chunks={total} |
| `commands/start.rs:1671` | gated | [node] message decode failed |
| `commands/start.rs:1684` | kept | [m7] discard FastSyncResponse anchor={chunk_anchor} <= current={} — drop client, retry on next cemented |
| `commands/start.rs:1714` | kept | [m7] fast-sync complete → state replaced, current_window={window} |
| `commands/start.rs:1718` | gated | [node] fast-sync finalization refused |
| `commands/start.rs:1725` | kept | [m7] fast-sync chunk {received}/{total} |
| `commands/start.rs:1728` | gated | [node] fast-sync chunk refused |
| `commands/start.rs:1734` | gated | [node] fast-sync response refused |
| `commands/start.rs:1766` | gated | [node] ticket accepted |
| `commands/start.rs:1819` | gated | [node] node identity loaded |
| `commands/start.rs:1847` | gated | [node] node identity loaded |
| `commands/start.rs:1867` | gated | [node] node identity loaded |
| `commands/start.rs:1875` | gated | [node] node identity loaded |
| `commands/start.rs:1882` | gated | [node] message decode failed |
| `commands/start.rs:1945` | kept | [lottery] window {w}: weighted ticket above target — not a candidate |
| `commands/start.rs:2043` | kept | \r{line} |
| `commands/start.rs:2045` | kept | \r{line} |
| `commands/start.rs:2112` | gated | [node] starting network thread |
| `commands/start.rs:2127` | gated | [node] network runtime initialization failed |
| `commands/start.rs:2144` | gated | [node] network event loop failed |
| `main.rs:10` | kept | {} |
| `main.rs:21` | kept | {} |
| `main.rs:25` | kept | Montana Core 0.1 — montana-node {} (git {} {}) |
| `main.rs:34` | kept | unknown command: {other} |
| `main.rs:35` | kept | (empty line) |
| `main.rs:36` | kept | {} |
| `main.rs:46` | fixed init error | initialization failed; check inputs and private output permissions; existing recovery files are never overwritten |
| `main.rs:48` | gated | node start failed |
| `main.rs:50` | kept | error: {e} |
| `commands/inspect.rs:15` | kept | === montana-node inspect === |
| `commands/inspect.rs:16` | kept | (empty line) |
| `commands/inspect.rs:17` | kept | data-dir : {} |
| `commands/inspect.rs:18` | kept | identity : {} |
| `commands/inspect.rs:19` | kept | suite : ML-DSA-65 (suite_id = {}) |
| `commands/inspect.rs:23` | kept | (empty line) |
| `commands/inspect.rs:24` | kept | account_id : {} |
| `commands/inspect.rs:25` | kept | node_id : {} |
| `commands/inspect.rs:26` | kept | master_seed_fp : {} |
| `commands/inspect.rs:30` | kept | (empty line) |
| `commands/inspect.rs:31` | kept | account_pk : {} bytes |
| `commands/inspect.rs:35` | kept | account_pk[..16] : {} |
| `commands/inspect.rs:39` | kept | node_pk : {} bytes |
| `commands/inspect.rs:43` | kept | node_pk[..16] : {} |
| `commands/inspect.rs:47` | kept | mlkem_pk : {} bytes |
| `commands/inspect.rs:51` | kept | mlkem_pk[..16] : {} |
| `commands/inspect.rs:55` | kept | (empty line) |
| `commands/inspect.rs:56` | kept | --- libp2p transport identity (M8 cross-machine) --- |
| `commands/inspect.rs:58` | kept | network_peer_id : {pid} (Noise_PQ XX — set in genesis-manifest) |
| `commands/inspect.rs:59` | kept | network_peer_id : <output error: {e}> |
| `commands/inspect.rs:61` | kept | libp2p_peer_id : {} (legacy Ed25519, not used by Noise_PQ XX transport) |
| `commands/inspect.rs:69` | kept | (empty line) |
| `commands/inspect.rs:70` | kept | account_pk_hex : {} |
| `commands/inspect.rs:74` | kept | node_pk_hex : {} |
| `commands/inspect.rs:81` | kept | (empty line) |
| `commands/inspect.rs:82` | kept | --- master_seed (full, 64 bytes) --- |
| `commands/inspect.rs:83` | kept | {} |
| `commands/status.rs:28` | kept | === montana-node status === |
| `commands/status.rs:29` | kept | (empty line) |
| `commands/status.rs:30` | kept | data-dir : {} |
| `commands/status.rs:31` | kept | current_window : {current_window} |
| `commands/status.rs:32` | kept | phase : {:?} |
| `commands/status.rs:33` | kept | D (current) : {} |
| `commands/status.rs:38` | kept | candidate SSHA : {}/{} ({} windows left) |
| `commands/status.rs:51` | kept | registration_window : {} |
| `commands/status.rs:53` | kept | (empty line) |
| `commands/status.rs:54` | kept | --- your identity --- |
| `commands/status.rs:55` | kept | account_id : {} |
| `commands/status.rs:56` | kept | node_id : {} |
| `commands/status.rs:57` | kept | node_pubkey_hex : {} |
| `commands/status.rs:61` | kept | account_pubkey_hex : {} |
| `commands/status.rs:65` | kept | (empty line) |
| `commands/status.rs:66` | kept | --- local state table sizes --- |
| `commands/status.rs:67` | kept | AccountTable : {} records |
| `commands/status.rs:68` | kept | NodeTable : {} records (active nodes) |
| `commands/status.rs:72` | kept | CandidatePool : {} records (awaiting selection event) |
| `commands/status.rs:76` | kept | (empty line) |
| `commands/status.rs:82` | kept | --- your status --- |
| `commands/status.rs:84` | kept | operator account : found in AccountTable |
| `commands/status.rs:85` | kept | balance : {} nɈ |
| `commands/status.rs:86` | kept | is_node_operator : {} |
| `commands/status.rs:87` | kept | account_chain_length : {} |
| `commands/status.rs:89` | kept | operator account : NOT FOUND (state not bootstrapped) |
| `commands/status.rs:93` | kept | node in Node Table : YES — active |
| `commands/status.rs:95` | kept | start_window : {} |
| `commands/status.rs:96` | kept | chain_length : {} |
| `commands/status.rs:98` | kept | node in Candidate Pool: YES — awaiting selection event |
| `commands/status.rs:100` | kept | w_start : {} |
| `commands/status.rs:101` | kept | ssha_chain_length : {} |
| `commands/status.rs:102` | kept | registration_window : {} |
| `commands/status.rs:103` | kept | expires (window) : {} |
| `commands/status.rs:104` | kept | proof_endpoint : {} |
| `commands/status.rs:106` | kept | node : NOT REGISTERED |
| `commands/status.rs:107` | kept | run 'start' — the node will go through |
| `commands/status.rs:108` | kept | candidate SSHA (τ₂ windows) → registered → active |
| `commands/status.rs:110` | kept | (empty line) |
| `commands/status.rs:112` | kept | --- protocol parameters --- |
| `commands/status.rs:113` | kept | τ₂ (windows per epoch): {} |
| `commands/status.rs:114` | kept | selection interval : every {} windows |
| `commands/status.rs:118` | kept | admission divisor : {} (1/{} active nodes / selection) |
| `commands/status.rs:122` | kept | candidate expiry : {} windows from registration |
| `commands/status.rs:126` | kept | emission per window : {} nɈ ({} Ɉ) |
| `commands/status.rs:132` | kept | supply (closed-form) : {} nɈ ({} Ɉ) = emission × W |
| `commands/status.rs:139` | kept | (empty line) |
| `commands/status.rs:140` | kept | --- AccountTable balances --- |
| `commands/status.rs:141` | kept | Σ balances : {} nɈ ({} Ɉ) |
| `commands/time.rs:20` | kept | === montana-node time === |
| `commands/time.rs:21` | kept | (empty line) |
| `commands/time.rs:22` | kept | data-dir : {} |
| `commands/time.rs:23` | kept | current_window file : {} |
| `commands/time.rs:27` | kept | (empty line) |
| `commands/time.rs:28` | kept | current_window : {window} |
| `commands/time.rs:29` | kept | epoch τ₂ : {epoch} (window {in_epoch} of {}) |
| `commands/time.rs:33` | kept | next selection : window {next_selection} (in {} windows) |
| `commands/time.rs:37` | kept | selection_interval : every {} windows |
| `bin/calibrate-d.rs:20` | kept | === Calibrating D for target window {TARGET_WINDOW_SECONDS:.1} sec === |
| `bin/calibrate-d.rs:21` | kept | Running {RUNS} benchmarks of {BENCH_ITERS} SHA-256 iterations. |
| `bin/calibrate-d.rs:22` | kept | (empty line) |
| `bin/calibrate-d.rs:33` | kept | run {run_idx}/{RUNS}: {BENCH_ITERS} in {:.3}s = {:.3} MH/s |
| `bin/calibrate-d.rs:44` | kept | (empty line) |
| `bin/calibrate-d.rs:45` | kept | Median rate: {:.6} MH/s (single-thread) |
| `bin/calibrate-d.rs:49` | kept | Exact D: {exact_d} (for exactly 60.0 sec on this machine) |
| `bin/calibrate-d.rs:50` | kept | Estimated window at D = {exact_d}: {:.4} seconds |
| `bin/calibrate-d.rs:54` | kept | (empty line) |
| `bin/calibrate-d.rs:55` | kept | Set in crates/mt-genesis/src/lib.rs (genesis_params().d0): |
| `bin/calibrate-d.rs:56` | kept | d0: {exact_d}, |
| `bin/calibrate-d.rs:58` | kept | {exact_d} |
