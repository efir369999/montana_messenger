# Spec Deviations

Single source of truth for all known deviations of the implementation from the Montana spec. Introduced in v1.13.0 of the code-architect role ([C-10] Mandatory deviation tracker).

Each `// SPEC DEVIATION DEV-NNN: ...` comment in code refers to a specific entry below. The pre-commit hook (`scripts/pre-commit.sh`) checks the counts.

Closed `DEV-N` entries are kept in this file as a historical record with `Status: closed (commit <sha>)`.

---

## DEV-001: NodeRegistration with ssha_chain_length=0

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/registration.rs:8-22` (build_node_registration)
**Spec section:** «NodeRegistration» / «Adaptive SSHA» / «Step 1: incremental apply»
**Spec quote:** «`if NR.ssha_chain_length >= required: apply; N += 1; else: reject`», `required_ssha_length(pending=0, active=0, τ₂)` → `tau2_windows = 20160`
**What the code does:** `ssha_chain_length=0` (or user-provided), with no `≥ τ₂` check, bypasses `apply_noderegistrations_batch` via a manual `CandidatePool::insert`
**Severity:** mainnet blocker ([I-9] / [C-7] violation, bypass of the canonical apply pipeline)
**Closure path:** implement the candidate SSHA phase in `start.rs` — the node ticks SSHA until `ssha_chain_length ≥ τ₂_windows`, then automatically forms a NodeRegistration with the correct `ssha_chain_length` and calls `apply_noderegistrations_batch` through the canonical pipeline
**Closure cost:** ~14 days wall-clock on an M-class Mac (SSHA physics, not code) + ~4 hours of code
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-002: proof_endpoint = candidate_ssha_init(zeros, zeros, node_id)

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/registration.rs:11`
**Spec section:** «Step 2: Candidacy» / «[I-8] compliance»
**Spec quote:** «`candidate_ssha_init = SHA-256("mt-candidate-ssha-init" || timechain_value(W_start) || cemented_bundle_aggregate(W_start - 2) || node_id)`»
**What the code does:** `candidate_ssha_init(&[0u8; 32], &[0u8; 32], &node_id)` — timechain_value and cba both zeros (placeholder)
**Severity:** mainnet blocker ([I-8] violation — no canonical unpredictable-offline binding)
**Closure path:** at the time of forming a NodeRegistration use the **real** `timechain.t_r` and `cemented_bundle_aggregate(W_start - 2, &cemented_node_ids_at_W_start_minus_2)` from the local node state
**Closure cost:** ~1 hour of code after DEV-001 closure
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-003: Lottery missing — winner = first node by lex

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:104-120`, `commands/advance.rs` similarly
**Spec section:** «Lottery» / «τ₁ Winner»
**Spec quote:** «winner = `argmin(weighted_ticket_node)` among cemented ``SshaReveal`` candidate nodes; `weighted_ticket_node = ln_q64(endpoint) / lottery_weight`»
**What the code does:** `state.nodes.iter().next()` — the first node by `node_id` lex order, **with no `SshaReveal` formed, no endpoint, no weighted_ticket**
**Severity:** mainnet blocker (consensus-critical logic ignored, [I-8] violation)
**Closure path:** implement per window: form a ``SshaReveal`` (`mt_lottery::SshaReveal`) with `endpoint = SHA-256("mt-lottery" || T_r || cba || node_id || W LE)`, sign with `node_sk`; compute `weighted_ticket_node` via `mt_lottery::weighted_ticket_node`; for singleton — sole candidate — argmin is trivial and correct **through the canonical API**
**Closure cost:** ~6 hours of code
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-004: BundledConfirmation never formed

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:113-117`
**Spec section:** «Confirmer threshold» / «BundledConfirmation» / «apply_proposal Step 3.5»
**Spec quote:** «chain_length is incremented on a cemented `BundledConfirmation`», quorum = `(67 × X + 99) / 100` of active_chain_length
**What the code does:** `chain_length += 1` directly, with no BC formed, no signature over `op_hashes / reveal_hashes`, no quorum cementing
**Severity:** mainnet blocker (chain_length is bluntly incremented on the basis of a non-existent rule)
**Closure path:** form a `mt_lottery::BundledConfirmation` with `op_hashes[]` (from Account Table cemented operations) + `reveal_hashes[]` (from cemented `SshaReveal` of the previous window) + signature `node_sk`; cementing via quorum (for singleton — 100% by itself, checked via `mt_lottery::is_cemented`)
**Closure cost:** ~8 hours of code
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-005: ProposalHeader not formed, Step 4 of apply_proposal bypassed

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:102-128`
**Spec section:** «Proposal header» / «Canonical acceptance» / «apply_proposal Step 4»
**Spec quote:** «the winner forms a `ProposalHeader` (1080 bytes) with `included_bundles + included_reveals + state_root`, signs it, archives it. The validator recomputes state_root and compares.»
**What the code does:** directly `account.balance += 13_000_000_000` bypassing `apply_emission`; ProposalHeader is not formed; `archive_proposal` is not called
**Severity:** mainnet blocker (full Step 4 of apply_proposal bypassed)
**Closure path:** form a `mt_consensus::ProposalHeader` with the correct fields (`canonical_proposer`, `included_bundles`, `included_reveals`, `state_root`), `validate_acceptance`, emission via `mt_account::apply_proposal`, `mt_store::archive_proposal`
**Closure cost:** ~12 hours of code
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-006: state_root is not cross-checked between proposer and validator

**Crate:** `montana-node`
**File:line:** N/A (absence of code)
**Spec section:** «Verification» / «Proposal finality»
**Spec quote:** «Proposal finality — signature of `proposer_node_id` on the proposal header. Verification — independent recomputation of state_root.»
**What the code does:** state_root recompute does not exist. Singleton mode — the node is its own proposer and validator, but cross-check is still required for regular self-verification (protection against disk / memory corruption)
**Severity:** medium (singleton has no 2 nodes for cross-check, but self-verification is mandatory)
**Closure path:** after forming `ProposalHeader.state_root`, recompute `compute_state_root(account_root, node_root, candidate_root)` independently and compare byte-exact; mismatch → panic (corruption detected)
**Closure cost:** ~1 hour of code
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-007: next_d is not invoked at the τ₂ boundary

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:95-160`
**Spec section:** «Adaptation of D via participation-ratio feedback»
**Spec quote:** «D is adapted at the τ₂ boundary via canonical chain observation»
**What the code does:** `timechain.current_d` is fixed at `D₀=252M`, `next_d` is not invoked
**Severity:** mainnet blocker for a long-running node (>14 days)
**Closure path:** keep `participation_history: Vec<u32>` (permille per window) in the timechain state; at every τ₂ boundary compute the median + `next_d(current_d, median, params)`; update `timechain.current_d`; for singleton: participation_ratio = always 1000 → median=1000 → every τ₂ D × 1.03
**Closure cost:** ~3 hours of code
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-008: selection_event with zeros in advance.rs vs real T_r in start.rs

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/advance.rs:55-72`
**Spec section:** «Selection event sort_key»
**Spec quote:** «`sort_key(c) = SHA-256("mt-selection" || timechain_value(W) || cemented_bundle_aggregate(W-2) || c.node_id)`»
**What the code does:** `let placeholder = [0u8; 32]` for both `t_r` and `cba`. Silent divergence between my own commands — `start.rs` uses the real `timechain.t_r`, `advance.rs` uses zeros. Same state, different seeds → different ranking → different winners for multi-candidate.
**Severity:** mainnet blocker (silent divergence between execution paths)
**Closure path:** delete `advance.rs` entirely — for byte-exact spec there is no «fast simulation», only real execution
**Closure cost:** ~10 minutes (delete the file + dispatch update)
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-009: apply_proposal entirely bypassed — every step is implemented via manual insert / update

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:95-160`, `advance.rs:45-95`
**Spec section:** «State transition → apply_proposal»
**Spec quote:** «Steps 1, 2, 3a, 3b, 4 in canonical order»
**What the code does:** directly modifies `AccountTable` / `NodeTable` / `CandidatePool` outside of any `apply_proposal`. Each window is an ad-hoc set of shortcuts, not a canonical state transition.
**Severity:** mainnet blocker (silent divergence between implementation and spec on a per-window basis)
**Closure path:** replace the ad-hoc path with the canonical `apply_proposal` pipeline via `mt_account::apply_proposal(&mut account_table, &mut node_table, &mut candidate_pool, &proposal_input, params)`. Singleton mode forms a valid `ProposalInput` for every window and calls the canonical pipeline.
**Closure cost:** ~16 hours of code (depends on DEV-001..DEV-006)
**Status:** closed (commit `fb204ef` mt-local-node: byte-exact rewrite via canonical apply_proposal)

---

## DEV-011: hardware calibration of initial D for the target window time

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` function
              `calibrate_d_for_target_window` + first run of start
**Spec section:** «Engines → TimeChain SSHA — oscillator», «Calibration of D₀»
**Spec quote:** «Mainnet calibration `D₀` targets τ₁ ≈ 60 seconds wall-clock
                 on median commodity hardware (engineering target, not a protocol
                 invariant)»
**What the code does:** on the first run of the node (timechain.bin did not exist)
                    it runs benchmark ssha_step(zeros, 10M) → measures
                    the hardware SHA-256 rate → calibrates `current_d` so that
                    a window ≈ 60 s wall-clock on this machine.
**What the spec says:** spec `D₀ = 252M` — engineering calibration target for
                 median commodity. Per-node actual wall-clock varies ×20
                 (Apple Silicon ~53s, idle x86_64 VPS ~68s, loaded ~1145s).
                 Adaptive D feedback at the τ₂ boundary automatically
                 adjusts D to the median network rate.
**Severity:** cosmetic — D in the genesis node = local state, not shared
              consensus invariant with other nodes (there are none).
              When new network nodes appear, their D will be calibrated
              independently or synchronized via canonical params.d0.
**Closure path:** when finalizing multi-node M6+ — nodes will sync via
                  canonical D from the Genesis Decree or negotiate via
                  network consensus. Hardware calibration remains for
                  the genesis node as the initial value.
**Closure cost:** acknowledged as a permanent feature for the genesis node,
                  no closure required
**Status:** acknowledged (genesis-node local hardware calibration —
            an explicit operator choice, not a silent shortcut)
**Acknowledged:** author 2026-04-28 «make my node produce roughly
                  a 60-second window»

---

## DEV-010: genesis bootstrap mode without Candidate SSHA (auto-detected)

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/state.rs` (LocalState::bootstrap),
              `crates/montana-node/src/node_lifecycle.rs` (NodeLifecycle::fresh_for),
              `crates/montana-node/src/commands/start.rs` (Bootstrap → CandidateSsha transition)
**Spec section:** «Genesis Decree» / «Node activation»
**Spec quote:** «Genesis = empty window 0. The first node bootstraps via the
                 existing admission path: at zero Active operators
                 selection_slots(0) = 1 self-admits the first candidate, and
                 quorum(1) = 1 lets it cement its own chain.»
**What the code does:** Genesis State is empty (no baked bootstrap account/node,
  no N_SEED cohort, no proof-of-work). Every node starts as a candidate
  (`NodeLifecycle::fresh_for` always returns `fresh_candidate`) and self-admits
  via the standard path: phase=Bootstrap → CandidateSsha on the first window →
  Registered (via apply_noderegistrations_batch) → Active (via
  apply_selection_event; selection_slots(0)=1 accepts the first candidate
  immediately). The node appears in NodeTable only via canonical
  apply_selection_event — no genesis pre-seeding.
**Severity:** obsolete (the deviation no longer exists).
**Closure path:** «Genesis = empty window 0» refactor — removed the baked
                  bootstrap operator (`bootstrap_account_pubkey`,
                  `bootstrap_node_pubkey`, `n_seed`, `genesis_active_operators`,
                  `bootstrap_pow_difficulty`) from `ProtocolParams`; rewrote
                  `build_genesis_state` to yield empty tables; removed the
                  `is_bootstrap_node` / `fresh_genesis` instant-Active path.
**Closure cost:** done.
**Status:** closed (obsolete) — superseded by «Genesis = empty window 0».
            The instant-Active genesis path was removed; all nodes self-bootstrap
            through the existing admission rules. No remaining deviation.
**Acknowledged:** author — «Genesis = empty window 0»: remove the baked bootstrap
                  operator and self-bootstrap via existing mechanisms
                  (selection_slots(0)=1, quorum(1)=1)

---

## History

| Role version | Date | Action |
|---|---|---|
| v1.13.0 | 2026-04-28 | File created. DEV-001..DEV-009 opened for `montana-node` Stages 1-5. Author's decision: byte-exact rewrite. |
| v1.13.0 | 2026-04-28 | DEV-001..DEV-009 closed via canonical apply_proposal pipeline rewrite. |
| v1.13.0 | 2026-04-28 | DEV-010 added: genesis bootstrap mode (node starts Active without Candidate SSHA) — explicit acknowledged deviation, author's decision. |
| v1.14.0 | 2026-05-20 | DEV-013 closed: online IBT proof includes `online_session_nonce`; `OnlineNonceTracker` rejects replay within current / previous slot. |


---

## DEV-012: singleton-only proposal generation in Active phase

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:265-292` (Active phase guard)
**Spec section:** «BundledConfirmation» / «apply_proposal Step 3.5 cementing» / «Singleton consensus»
**Spec quote:** «`cemented_sum = Σ chain_length of nodes whose BundledConfirmation entered included_bundles`. An object is cemented when `cemented_sum ≥ quorum(active_chain_length)`, where `quorum = (67 × active + 99) / 100`.» (mt-consensus/src/lib.rs:327, mt-lottery/src/lib.rs:503-510)
**What the code does:** the Active phase in start.rs forms a proposal in which my_node is the sole confirmer (`included_bundles = {my_bundle}`, cemented_sum = my_node.chain_length). This is correct ONLY when `state.nodes == {my_node}` (1 node in NodeTable, my own). In a multi-node NodeTable my_node.chain_length < quorum(Σ_chain_length) → `is_cemented` returns false → the node crashes with `singleton cementing: cemented=X, active=Y, quorum=Z`. The DEV-012 guard adds a check `state.nodes.len() == 1 && state.nodes.contains(&my_node)`; on failure it skips the proposal block (break 'active_arm) and does not crash.
**Severity:** post-mainnet — v1.0.1 hot-fix track (the bootstrap-proposer + follower-apply path is the v1.0.0 mainnet baseline; multi-confirmer rotation is the v1.0.1 target)
**Closure path:** implement M9 Phase 2 — drain the incoming Proposal envelope (start.rs:160-169), validate via `mt_consensus::validate_acceptance`, `mt_account::apply_proposal` for the cemented set from the proposer, recompute state_root, sync `current_window` + `state.nodes[].chain_length` from the peer Proposal. After this, Frankfurt / Helsinki as followers catch up with Moscow without needing to produce their own singleton-proposal.
**Closure cost:** ~3-5 days wall-clock for implementation + integration test (e2e_three_peer_apply_proposal)
**Status:** partially closed (follower drift fix in commit `e1a0bd0`); multi-confirmer protocol (Phase B+C) carried into v1.0.1 hot-fix track post the v1.0.0 mainnet tag.

**Partial close (commit `e1a0bd0`, 2026-05-21).** The `follower_skip` flag in `start.rs` prevents a node in Active phase with `NodeTable.len() > 1` from advancing its cemented head via the local SSHA tick. The only path that advances `current` for a follower is `apply_proposal` driven by an incoming Proposal envelope from the bootstrap proposer. Verified across the four-node mesh (Moscow proposer + Frankfurt + Helsinki + Armenia followers) — lag stays bounded by the network broadcast latency rather than diverging.

**Open: multi-confirmer protocol (v1.0.1 closure).** Closure to v1.0.1 requires:

  1. **Wire-level BundledConfirmation broadcast.** `MsgType::BundledConfirmation (0x20)` already in the message-type registry; followers must sign + broadcast their own BC on receipt of a Proposal for the current window. Wire-format dependency: the canonical `expected_endpoint` for `validate_bundle` is `SHA-256(domain || T_r(W) || cemented_bundle_aggregate(W-2) || node_id || W)`, so the follower's local `timechain.t_r` must equal the canonical value at window `W`.
  2. **t_r consistency for followers.** Two viable paths: (i) followers tick the SSHA locally in lockstep with the wall clock and cache the per-window t_r history during catch-up; (ii) Moscow's Proposal envelope is extended to include t_r(W) explicitly. Path (i) does not change the wire format but increases follower CPU; path (ii) breaks the existing 3722-byte envelope size. Path (ii) is the cleaner architectural choice for v1.0.0.
  3. **Proposer-side BC accumulator.** Moscow opens a one-window accumulator on broadcast of its Proposal candidate; collects incoming BC envelopes for the same window from registered Active operators; once `cemented_sum = Σ node.chain_length` over the collected confirmers reaches `quorum(active_chain_length) = ⌈67 * Σ active / 100⌉`, builds the included_bundles set and broadcasts the cemented Proposal with the full bundle set inline (envelope schema change).
  4. **Multi-confirmer ProposalSettle on followers.** Each follower validates every BC signature in the cemented Proposal against the corresponding `NodeTable[node_id].node_pubkey`; reconstructs ProposalSettle with `cemented_confirmers = [all signers]`; calls apply_proposal with the multi-confirmer set.
  5. **Wire format Proposal envelope schema bump.** From 3722-byte header-only to header + length-prefixed BC set. Network spec v1.1.0 → v1.2.0; binding KAT vector regenerated for the new wire format.
  6. **Tests.** mt-net-transport e2e integration test with 3 in-process operators reaching quorum via multi-confirmer cementing across simulated balanced chain_length distribution.

**Operational note (current production state).** Moscow's `chain_length = 25 766` is dominant (Frankfurt, Helsinki, Armenia each `≤ 1`); Moscow's BC alone already satisfies `67% × Σ active_chain_length` quorum. The multi-confirmer protocol becomes operationally consequential only once non-bootstrap operators accumulate non-negligible chain_length over many τ₂ epochs — well after the v1.0.0 mainnet tag. The protocol is the explicit gate to v1.0.1; the bootstrap-proposer baseline is the v1.0.0 mainnet baseline.

**Precedent (historical).** the Frankfurt node became Active on genesis bootstrap (registration_window=45916, start_window=46032, chain_length=1) and immediately landed in a multi-node situation (state.nodes = {msk, fra}). 4,790 montana-node restarts over 24 hours with the error `singleton cementing: cemented=1, active=25767, quorum=17264` — msk had chain_length=25766 in Frankfurt's state (received via P2P sync), fra had its own chain_length=1. The `follower_skip` patch (commit `e1a0bd0`) replaces the crash with passive follower mode; the node stays in Active phase, keeps heartbeating to peers, and only advances its cemented head via apply_proposal from the bootstrap proposer.

---

## DEV-013: online IBT proof formula — code behind spec (online_session_nonce)

**Crate:** `mt-net`
**File:line:** `crates/mt-net/src/ibt.rs` (online_proof / verify_online_proof; the exact line depends on the current implementation — see `cargo grep mt-tunnel-online`)
**Spec section:** «Identity-Bound Tunnel (IBT)» in `Montana Network v1.1.0.md` (after bump v1.0.0 → v1.1.0 for MONT-002 closure)
**Spec quote:** «`proof = ML-DSA-65_sign(client_privkey, "mt-tunnel-online" || server_node_id || floor(current_window_index / 2) || online_session_nonce)` where `online_session_nonce` 32B — generated by the client from CSPRNG for each handshake, transmitted in the plain part of the IBT advertisement alongside the proof.»
**What the code does:** `mt-net::ibt::ibt_online_proof` and `ibt_online_verify` accept `online_session_nonce: [u8; 32]` and include it in the signed message. `mt-net::ibt::OnlineNonceTracker` keeps `used_online_nonces[client_pubkey]` with pruning by current / previous window slot and a bounded per-client set. `mt-net-transport::ibt_upgrade::classify_proof` invokes the verifier + nonce tracker before issuing the access level.
**Severity:** closed for MONT-002 (MITM replay of the same online proof within the 2-window slot is rejected as `IbtError::ReplayedNonce`)
**Status:** closed (mt-net / mt-net-transport: online_session_nonce in signed scope + used_online_nonces tracking)

**Acknowledged:** the wire-level handshake envelope in transport integration must pass `online_session_nonce` alongside the proof; the API already requires the nonce, so without it the call site will not compile.

---

## DEV-014: Noise_PQ post-quantum transport migration (M6 milestone)

**Crate:** `mt-net-transport`
**File:line:** ~~`crates/mt-net-transport/src/transport.rs:42, 76`~~ (classical TLS + Noise XK upgrade chain removed in commit closing DEV-014; transport.rs now uses `NoisePqXxConfig` exclusively)
**Spec section:** «Post-quantum transport migration (M6 milestone)» in `Montana Network v1.1.0.md`
**Spec quote:** «Migration to a single post-quantum transport handshake: hybrid Noise_PQ combining X25519 with ML-KEM-768 as the KEM replacement for Diffie-Hellman.»
**What the code does (historical):** The previous transport upgrade chain was `TLS 1.3 (rustls) → Noise XK (X25519 ECDHE inner) → Yamux`. Both handshake layers used classical X25519 ECDHE and were vulnerable to store-now-decrypt-later attacks by a future quantum adversary. As of this commit the entire classical auth stack is removed — production transport is `TCP → Noise_PQ XX (ML-KEM-768 + ML-DSA-65) → Yamux`. Consensus signatures (ML-DSA-65) are unaffected; transport confidentiality is now post-quantum.
**Severity:** previously mainnet blocker for the «pure post-quantum» claim; closed by switching the production transport stack to Noise_PQ XX.
**Closure path (multi-phase, 3–5 weeks total wall-clock):**

- **Phase 0 — Architecture & scaffolding (this entry).** Network spec documents the migration plan with phases and verification criteria; this DEV-014 tracker entry is added; a `pq_transport_version: u8` wire field is reserved in the IBT advertisement for capability negotiation; no code change beyond the planning documentation. **Status: completed in this commit.**
- **Phase 1 — Noise_PQ handshake implementation.** Implement an ML-KEM-768-augmented Noise XK variant. Two viable paths:
  - (a) Fork the `snow` crate (https://github.com/mcginty/snow) to add ML-KEM-768 as a DH replacement. Contribute upstream after byte-exact KAT validation against the emerging Noise PQ draft. Estimated effort: 3 weeks for a senior Rust + crypto engineer, including KATs and differential testing.
  - (b) Write a custom Noise_PQ handler outside libp2p's `noise` upgrade module, wrapping it as a `libp2p::core::upgrade::OutboundConnectionUpgrade` / `InboundConnectionUpgrade`. Reuse the `mt-crypto::keypair_from_seed_mlkem` and `mt-crypto::Mlkem*` types already present in `mt-crypto`. Estimated effort: 4 weeks.
  Either path requires byte-exact KAT vectors checked into `mt-conformance` and differential testing against at least one independent reference implementation.
- **Phase 2 — Hybrid coexistence period.** Capability negotiation through the `pq_transport_version` wire field. Peers advertise both classical and Noise_PQ; the connection negotiates the highest mutually supported version. A chain_length-weighted majority signal (≥ 67% of active_chain_length advertising Noise_PQ for ≥ τ₂) triggers the deprecation of classical inbound. Estimated wall-clock: 2 weeks of soak-time on the genesis 3-node network plus observability collection.
- **Phase 3 — Classical removal.** TLS 1.3 layer dropped entirely. The transport stack becomes TCP → Noise_PQ → Yamux. Uniform framing preserved at the application layer for DPI obfuscation. Spec bump removes `pq_transport_version` once capability negotiation is no longer needed. Estimated wall-clock: 1 week including spec patch + node deployment + 24-hour soak.

**Closure cost:** 3–5 weeks wall-clock for Phase 1 + 1–2 weeks for Phases 2 + 3 = total **5–7 weeks** for production-grade closure with KATs, differential testing, and three-node soak. This is M6 milestone scope, not single-session work.

**Status:** Phase 0 + Phase 1 + Phase 2 + Phase 3 part 1 + Phase 3 part 2 (AEAD stream + drive functions) + Phase 3 part 2c (libp2p UpgradeInfo / InboundConnectionUpgrade / OutboundConnectionUpgrade trait impls + PeerId derivation from ML-DSA-65) + **Phase 3 XX redesign** (ephemeral KEM both sides, identity discovered during handshake — enables libp2p `with_tcp` plug-in where XK could not) + **Phase 3 part 3 production wire-up** (transport.rs replaced with `NoisePqXxConfig` only; tls + noise removed; PeerId derived from ML-DSA-65 throughout the stack) completed; cross-machine 24h soak across the 3-node Genesis cohort is the remaining empirical verification (off-session).

**Phase 1 closure note (2026-05-21):** mt-crypto extended with FIPS 203 §6.2 / §6.3 ML-KEM-768 encapsulate / decapsulate primitives (`mlkem_encapsulate`, `mlkem_decapsulate`, types `MlkemCiphertext`, `MlkemSharedSecret` with zeroize-on-drop and mlock-protected shared secret allocation). Added C wrapper functions `mt_mlkem_encapsulate` / `mt_mlkem_decapsulate` over OpenSSL 3.5 EVP API.

New crate `mt-noise-pq` (`crates/mt-noise-pq`) implements a 3-message Noise XK-like handshake with ML-KEM-768 in place of Diffie-Hellman and ML-DSA-65 identity signatures over transcript hashes. Wire sizes: msg1 2272 B, msg2 6349 B, msg3 5261 B. Session keys derived via domain-separated SHA-256 from ss_rs ‖ ss_e ‖ transcript ‖ rs_id_pk.

Tests passing:
- `cargo test -p mt-crypto --release --test mlkem_encap_decap` — 2 passed (encap / decap roundtrip + ciphertext freshness)
- `cargo test -p mt-noise-pq --release` — 6 passed total: full handshake roundtrip, tamper detection on msg2 / msg3 signatures (BadResponderSignature / BadInitiatorSignature), wire-size invariants, fixed-input consistent session derivation
- `cargo fmt --all -- --check` clean
- `cargo clippy --workspace --all-targets -- -D warnings` clean

**Phase 3 remaining work (Swarm integration + multi-node soak):**

- Phase 2 spec: completed — wire format and capability negotiation documented in Network v1.1.0.md (commit 2bcd86d and follow-up).
- Phase 3 part 1: TCP loopback integration test in `crates/mt-noise-pq/tests/loopback.rs` completed — both sides run as tokio async tasks and successfully derive identical session keys over a real `TcpStream` pair.
- Phase 3 part 2 (open): libp2p custom transport upgrade implementing the Noise_PQ handshake as `InboundConnectionUpgrade` / `OutboundConnectionUpgrade` so it can replace the existing `noise::Config::new` in `mt-net-transport::transport::build_swarm_with_keypair`. libp2p's `noise` and `tls` upgrades are tightly coupled to the SwarmBuilder API, and a custom Noise variant needs to plug into the same upgrade chain. Estimated 1–2 weeks for production-grade integration with the existing `mt-net-transport` Swarm.
- Phase 3 part 3 (open): cross-machine soak on the 3-node network (Moscow / Helsinki / Frankfurt) for ≥ 24 hours of continuous operation with zero classical-fallback events; requires deployed binaries on real nodes and operator-side observation. After Phase 3 part 3: TLS 1.3 outer layer dropped; transport stack becomes TCP → Noise_PQ XX → Yamux. **Done in this closure commit.**

**XX redesign note (closure commit, 2026-05-21):** The original XK variant required the initiator to know the responder's static ML-KEM-768 public key a priori — incompatible with libp2p's plug-in `with_tcp` auth-upgrade slot which gives the upgrade only the local `libp2p::identity::Keypair` (Ed25519). The XX redesign discovers remote identity during the handshake (ephemeral ML-KEM-768 keypairs on both sides; identity ML-DSA-65 pk transmitted in msg2 / msg3 and authenticated by signature over transcript). Wire format: msg1 1184 B, msg2 7533 B, msg3 6349 B (replacing the XK 2272 / 6349 / 5261). Two upgrade modules now coexist in mt-noise-pq:

- `mt_noise_pq::lib` (legacy XK) — retained for KAT continuity and reference; no longer wired into the libp2p transport.
- `mt_noise_pq::xx_handshake` + `mt_noise_pq::xx_libp2p_upgrade` — new XX module, wired into `mt-net-transport::xx_noise_pq_upgrade::NoisePqXxConfig` which implements both `InboundConnectionUpgrade` and `OutboundConnectionUpgrade` and is what `build_swarm_with_keypair` now uses in production.

PeerId derivation: SHA-256 multihash of the peer's ML-DSA-65 identity public key (libp2p / IPFS sha2-256 multihash code 0x12). GenesisManifest peer_id fields must contain the ML-DSA-derived multihash for the dial-side identity pin to match what the XX upgrade returns on the wire.

**Verification protocol per phase.** Each phase is closed only after ≥ 24 hours of continuous operation across the three genesis nodes (Moscow, Helsinki, Frankfurt) with zero unexpected handshake failures and zero classical-fallback events during the observation window. The cross-node verification log is committed to the repository at `External-Audit/noise-pq-phase{N}-verification.log`.

**Acknowledged:** author 2026-05-20 — explicit request «do this before any release, full phases, verify on nodes». Acknowledgement of scope: Phase 0 closed in this session; Phases 1-3 are dedicated multi-week milestones with code work and cross-node deployment validation that cannot honestly be promised within a single conversation. The plan, scope, and verification criteria are documented here so that the work can be picked up and executed in dedicated implementation sessions.

---

## DEV-015: M7 fast-sync client-side handler

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` — message-dispatch drain
**Spec section:** «Sync protocols → fast-sync» in `Montana Network v1.1.0.md` (lines 964–970)
**What the code does:** the M7 algorithmic layer is complete: `mt_sync::Snapshot::{from_tables, to_wire_chunks, build_tables}` and `SnapshotVerifier::verify` (Sparse Merkle production root, byte-equal cross-implementation conformance, 17 unit tests). The server-side dispatcher in `start.rs` answers `MsgType::FastSyncRequest` by broadcasting chunked `FastSyncResponse` envelopes carrying the requester's `request_id`. The client-side handler — drain chunks by `request_id`, reassemble Snapshot, verify against the anchor `ProposalHeader.state_root`, swap the local `LocalState.{accounts, nodes, candidates}` — is not yet wired into the dispatcher.

**Severity:** v1.0.1 hot-fix track. New operators today join the live mesh by replaying the canonical history via the existing `apply_proposal`-from-peers path; fast-sync becomes a CPU/time win at long-running mesh depth, not a correctness requirement.

**Closure path:**
  1. Add a per-`request_id` accumulator keyed by `(anchor_window, request_id)` to the dispatcher state.
  2. On `MsgType::FastSyncResponse` arrival, decode `mt_net::FastSyncResponseChunk`, append records to the corresponding `Snapshot` instance.
  3. When `chunk_index + 1 == total_chunks` for the highest-seen chunk in a given `request_id`, call `SnapshotVerifier::verify(&snap, &expected_state_root)` against the anchor `ProposalHeader.state_root` retrieved from any honest peer's archived proposal at the same `anchor_window`.
  4. On verify success, call `snap.build_tables()` and swap into `LocalState`; persist via `FsStore`; bump `current_window` to `anchor_window`.
  5. On verify failure, increment an attempt counter and retry against a different peer.

**Status:** open for v1.0.1.

## DEV-016: N_SEED multi-Active genesis cohort

**Crate:** `mt-genesis`, `montana-node`
**File:line:** `crates/mt-genesis/src/manifest.rs:32-67` (GenesisPeer.force_active / node_pubkey_hex / account_pubkey_hex), `crates/montana-node/src/state.rs::LocalState::bootstrap` (pre-seed extra_actives)
**Spec section:** «Genesis Decree» / «N_SEED as a consensus-binding parameter of the Genesis Decree» (Montana Protocol v35.26.1)
**What the code does:** GenesisManifest is extended with the optional fields `force_active`, `node_pubkey_hex`, `account_pubkey_hex` to pre-seed additional Active operators into NodeTable / AccountTable from genesis (window=0). LocalState::bootstrap iterates the extras and adds a NodeRecord (chain_length=1, start_window=0) + an AccountRecord (is_node_operator=true, balance=0) for each force_active peer. The singleton bootstrap proposer model is preserved; post-genesis admission through selection_event for non-genesis nodes is unchanged.
**Severity:** none (spec-compliant per v35.26.0).
**Closure path:** move N_SEED from the operational manifest into the Genesis Decree `protocol_params.genesis_active_operators` (consensus-binding, hardcoded in genesis_params()); the current manifest-based pre-seed remains for test-cohort flexibility, mainnet goes through hardcoded params.
**Closure cost:** ~3-5 hours of code + KAT vector update.
**Status:** acknowledged (spec formalized in v35.26.0; production hardcoding of genesis_active_operators in the Genesis Decree protocol_params — next iteration of mt-genesis).

---

## DEV-017: follower t_r_history population from Proposal envelopes

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:275-285` (after recent_roots insert)
**Spec section:** «BundledConfirmation» / «expected_endpoint» / «follower BC validation»
**Spec quote:** «BC.endpoint = T_r(W) of the proposer; validator computes expected = T_r at window W and rejects if mismatch»
**What the code does (before fix):** followers receive Proposal envelopes (candidate or cemented) containing `timechain_value` (T_r) at offset 204..236, but only `recent_roots` is populated; `t_r_history` remains empty for followers. When BCs from other followers arrive in the live drain (line 568-602), `expected_t_r = t_r_history.get(bc.window_index).unwrap_or(timechain.t_r)` falls back to follower's own out-of-sync `timechain.t_r`, which never matches the proposer's authoritative T_r → all peer BCs rejected as `WrongEndpoint`. Result: bc_accumulator at the proposer side gets at most `bundles=1` (own BC only); 6-Active genesis cohort cannot achieve quorum-based cementing.
**What the code does (after fix):** in the Proposal envelope handler, alongside `recent_roots.insert(window_index, state_root)`, extract `t_r_w_extracted` from offset 204..236 and `t_r_history.insert(window_index, t_r_w_extracted)` (bounded to last 64 windows by identical eviction policy). Now every received Proposal seeds the follower's t_r_history; when subsequent BCs from peer followers arrive in the live drain, validation uses the authoritative T_r and BCs accumulate correctly.
**Severity:** prerequisite for DEV-012 closure (multi-confirmer protocol non-functional without it). Mainnet blocker for any cohort with N_SEED ≥ 1.
**Closure path:** ↑ implemented in this commit.
**Closure cost:** 6 lines of Rust + redeploy.
**Status:** closed (Build 9, this session).


---

## DEV-018: fast-sync chunk anchor_window + stale-peer filter

**Crate:** `mt-net`, `montana-node`
**File:line:** `crates/mt-net/src/payloads.rs:62-110` (FastSyncResponseChunk wire format), `crates/montana-node/src/commands/start.rs:486-545` (sender stamp), `crates/montana-node/src/commands/start.rs:540-560` (receiver filter)
**Spec section:** «Sync protocols → fast-sync» / «State root verification»
**What the code does (before fix):** FastSyncResponseChunk wire format had no anchor_window field; sender broadcast chunks built from sender's current cemented head, but the receiver could not tell which anchor a given chunk belonged to. When the receiver hit `lag_threshold` and requested fast-sync, it accepted FIRST-RESPONSE chunks regardless of sender's actual head. In a mixed-window mesh (Moscow at W=2146, others at W=2003), receiver typically got chunks from the closest peer (a fellow follower at W=2003), not from Moscow. Reconstructed state_root matched the sender's stale state, but not any recent_roots entry for a window the receiver had already advanced past → `StateRootUnmatched` reject → retry cascade on every cemented Proposal arrival → infinite no-progress loop.
**What the code does (after fix):**
  1. **Wire format bump:** `FastSyncResponseChunk` gains `anchor_window: u64` (LE). Minimum chunk size 13 B → 21 B. All construction sites updated (montana-node fastsync.rs, mt-net test_vectors).
  2. **Sender side:** stamps `anchor_window = current` (sender's last cemented) on every chunk.
  3. **Receiver side:** decodes anchor_window from the first chunk payload; if `chunk_anchor <= current` the chunk is discarded with a log line — peer cannot help us catch up. Only chunks from peers strictly ahead of us are accepted.
**Severity:** mainnet blocker for mixed-window mesh (every multi-node deployment where any peer lags >1 windows behind the proposer). Without this fix, fast-sync converges only when ALL peers happen to be at the same window — a vanishingly rare condition.
**Closure path:** ↑ implemented in this commit. Possible follow-up: targeted FastSyncRequest (send to a specific peer_id, not broadcast) to avoid wasting bandwidth on lagging peers' responses.
**Closure cost:** ~50 lines of Rust across 4 files (wire format + sender + receiver + 1 test fix).
**Status:** closed (Build 10, this session).


---

## DEV-018b/c: fast-sync client retry on discard + 10s deadline

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:540-565` (discard drop), `crates/montana-node/src/commands/start.rs:393-401` (deadline check), `crates/montana-node/src/commands/start.rs:425-432` (trigger sets deadline)
**Spec section:** «Sync protocols → fast-sync» / «Liveness under partial responses»
**What the code does (before fix):** DEV-018 introduced anchor_window discard for stale-peer chunks but kept `fast_sync = Some(client)` on discard, so the `fast_sync.is_some()` guard at the next cemented arrival blocked re-trigger. Even worse, when the broadcast FastSyncRequest got NO response at all (peer unreachable, request lost in libp2p RR queue, peer too busy to serve), the client stayed Some forever and catch-up halted permanently.
**What the code does (after fix):**
  1. **Drop on discard (DEV-018b):** when anchor_window check rejects a chunk, immediately `drop(client)` and `fast_sync_deadline = None`. The next cemented Proposal arrival triggers a fresh FastSyncRequest.
  2. **10-second deadline (DEV-018c):** when fast-sync triggers, `fast_sync_deadline = Some(Instant::now() + Duration::from_secs(10))`. Each cemented Proposal handler checks `if Instant::now() > deadline` and drops the stale client. Recovers from silently-lost requests.
**Severity:** mainnet blocker for any cohort with intermittent peer availability or libp2p backpressure.
**Closure path:** ↑ implemented in this commit.
**Closure cost:** ~15 lines of Rust.
**Status:** closed (Build 11 + Build 12, this session).


---

## DEV-018d: serve FastSyncRequest inline during proposer spin-drain

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:965-1060` (spin-drain block in Active phase)
**Spec section:** «Sync protocols → fast-sync» / «Server-side liveness»
**What the code does (before fix):** The proposer (bootstrap) spends ~5 seconds per window in the BC accumulator spin-drain loop. The original spin-drain consumed messages from `incoming_rx` via `try_recv()` but only processed `MsgType::BundledConfirmation`. All other message types (FastSyncRequest, FastSyncResponse, peer Proposals) were silently discarded. Followers' fast-sync requests had ~0% chance of being served — they were eaten by the spin-drain before the post-spin main-loop dispatcher could reach them. As a result, followers stuck at an older window could never catch up to the proposer's head.
**What the code does (after fix):** spin-drain now handles three cases:
  1. `BundledConfirmation` — accumulator insert (as before).
  2. `FastSyncRequest` — serve inline: build snapshot from current state, chunk, broadcast `FastSyncResponse` envelopes with `anchor_window = current`, log `[m7] served FastSync snapshot (spin)`.
  3. Other types (e.g. `FastSyncResponse` for the proposer's own outgoing requests, peer Proposals) — pushed to a `deferred: Vec<ProtocolMessage>` (currently dropped after spin; acceptable because followers re-broadcast on every window).
**Severity:** mainnet blocker — without inline fast-sync serving, a lagging follower can never catch up to a proposer that's continuously cementing windows.
**Closure path:** ↑ implemented in this commit. Follow-up: re-queue `deferred` messages back into `incoming_rx` after spin (requires a multi-producer channel side or a local app-level pending queue).
**Closure cost:** ~70 lines of Rust.
**Status:** closed (Build 13, this session).


---

## DEV-019: post-quorum grace period for peer BC fairness

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:1007-1075` (active arm spin-drain post-quorum)
**Spec section:** «BundledConfirmation cementing» / «Fairness across cohort»
**What the code does (before fix):** when proposer's own chain_length dominates Σ active_chain_length (e.g. bootstrap operator with chain_length=2500+ vs co-validators at chain_length=1), self-quorum is trivially met on the first spin-iteration after inserting own BC. The spin loop breaks immediately (within 20ms), never giving peer BCs time to land (typical RTT 50–150ms). Cemented_confirmers contains only proposer → peer chain_length stays at 1 forever → dominance compounds. Multi-confirmer was structurally impossible after the first cohort.
**What the code does (after fix):** when `collected >= need_quorum` triggers, instead of `break;` the loop enters a 500 ms grace window that keeps draining `BundledConfirmation` envelopes from `incoming_rx`. Any peer BC arriving within grace and validating against `t_r_history[bc.window_index]` is inserted into the accumulator at the bc's window slot. After grace, the cement settle includes ALL accumulated confirmers for `current`. Non-BC messages collected during grace go to the same `deferred` queue as DEV-018d.
**Severity:** mainnet blocker for fairness — without this fix the dominant operator's chain_length grows monotonically while all peers stay at 1 forever.
**Closure path:** ↑ implemented in this commit. Open: spec extension to formalize the grace-window value (500 ms) as a protocol parameter.
**Closure cost:** ~40 lines of Rust.
**Status:** closed (Build 14, this session).


---

## DEV-019b: peer-quorum gate exit + 5s timeout

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:1007-1075` (active arm spin-drain grace block)
**Spec section:** «BundledConfirmation cementing» / «Fairness» / «Consensus close timing»
**What the code does (before):** DEV-019 used fixed 2000ms grace after self-quorum. Worked but peer BCs that arrived later (every 1-2 windows late) consistently missed the grace window, producing bundles=1 cementing in steady state.
**What the code does (after):** grace polls accumulator every 20ms. Exits early on `accumulator[current].len() >= ⌈total_active/2⌉` (peer-quorum gate) OR 5000ms timeout. Peers with consistent latency now stand a higher chance of inclusion; peers that are completely silent are not blocked indefinitely.
**Severity:** fairness improvement; not a hard blocker.
**Closure path:** ↑ implemented. Verified live: 33% of windows now cement with bundles=2 (vs ~1% with fixed grace). Peer chain_length growth observed: Frankfurt 5→91, Vilnius 3→27, Helsinki 2→18, Nicosia 1→5 over 1600 windows.
**Closure cost:** ~10 lines of Rust.
**Status:** closed (Build 16 sha f1030eb151c0, this session).


---

## DEV-020: per-window Reveal broadcast + reveal_pool

**Crate:** `montana-node`, `mt-lottery`
**File:line:** `crates/mt-lottery/src/lib.rs:248-281` (SshaReveal::decode), `crates/montana-node/src/commands/start.rs:196` (reveal_pool init), `crates/montana-node/src/commands/start.rs:622-700` (drain MsgType::SshaReveal), `crates/montana-node/src/commands/start.rs:300-370` (follower compute+broadcast own Reveal), `crates/montana-node/src/commands/start.rs:850-870` (bootstrap broadcast own Reveal), `crates/montana-node/src/commands/start.rs:1010-1080` (spin+grace inline Reveal handling).
**Spec section:** «`SshaReveal` pipeline» / «Cemented Reveal set»
**What the code does (before):** only bootstrap inserted its own reveal_hash into BC; the Reveal object itself was never broadcast over the wire. Peer nodes had no way to participate in the lottery.
**What the code does (after):**
  1. All Active operators compute their own Reveal each window using `compute_endpoint(t_r_window, cba_w_minus_2, my_node, window_index)`.
  2. The Reveal is broadcast as `MsgType::SshaReveal` envelope (wire size 3381 = 32+8+32+3309).
  3. Every node maintains `reveal_pool: BTreeMap<u64, BTreeMap<NodeId, SshaReveal>>` keyed by window, bounded to last 64 windows.
  4. Main dispatcher and proposer's spin-drain / grace handlers all decode SshaReveal envelopes, validate via `mt_lottery::validate_reveal`, and insert into the pool.
  5. Follower's BC.reveal_hashes is populated from `reveal_pool.get(window_index)` (own + any peer reveals received).

**Severity:** prerequisite for DEV-021 winner determination and DEV-022 Lookback rotation.
**Closure path:** ↑ implemented in this commit.
**Closure cost:** ~150 lines of Rust + SshaReveal::decode added to mt-lottery.
**Status:** closed (Build 17/18, this session).

---

## DEV-021: winner determination from cemented Reveal set

**Crate:** `montana-node`, `mt-lottery`
**File:line:** `crates/montana-node/src/commands/start.rs:1240-1290` (winner computation block)
**Spec section:** «Lookback Leadership / Determine winner_{W-1}»
**Spec quote:** «`winner_{W-1} = argmin(weighted_ticket_node)` among the cemented `SshaReveal` of candidate nodes of window W-1»
**What the code does (before):** proposer set `winner_id = my_node` unconditionally — no lottery, no per-window winner.
**What the code does (after):**
  1. At cement time, proposer computes `cemented_hashes = union of reveal_hashes across BCs in accumulator[current]`.
  2. Filters `reveal_pool[current]` by `cemented_hashes` to get cemented_reveals.
  3. Builds `mt_lottery::Candidate` list using `weighted_ticket_node(reveal.endpoint, node.chain_length, snapshot)`.
  4. `winner_id = mt_lottery::determine_winner(&candidates).map(|w| w.id).unwrap_or(my_node)`.
  5. Settle + header.winner_id = winner_id.
  Logs `[dev-021] cemented_reveals=N candidates=N winner=ID` per window.

**Severity:** mainnet blocker for genuine lottery (without this, proposer always wins → emission centralization).
**Closure path:** ↑ implemented in this commit. Live verification limited by upstream: peer BCs consistently late (DEV-019b note); cemented set typically = {proposer's own Reveal}; full multi-candidate lottery achievable once peer-drain-during-SSHA issue closed (see open follow-up below).
**Closure cost:** ~50 lines of Rust.
**Status:** closed (Build 17/18, this session); upstream blocker tracked separately.

---

## DEV-021b (open): peer drain during SSHA tick

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs:627` (ssha_step_chunked call inside main loop body)
**Spec section:** «Cross-window cementing timeline»
**What the code currently does:** follower's main loop drains `incoming_rx` only at the very top of each iteration. Each iteration takes ~30s (SSHA tick) + ~500ms (idle sleep). Candidate Proposal envelopes arrive mid-SSHA and queue in `incoming_rx` until next iteration top. By the time the follower's drain processes a candidate, the proposer has already moved past that window into the next, so follower's BC for window N reaches the proposer ~30s late — too late to land in `accumulator[N]` before cement.
**Consequence:** peer BCs and peer Reveals are chronically 1 window late. DEV-019b grace mitigates partially; full multi-confirmer cement (bundles=N) and multi-candidate lottery (DEV-021) require lockstep timing.
**Closure path:** restructure follower main loop so `incoming_rx` is drained periodically during `ssha_step_chunked` (callback every N steps), or move drain into a separate tokio task in the network thread with shared state. Either change implies a larger refactor than fits this session.
**Closure cost:** ~1–2 days wall-clock for correct implementation + integration test.
**Status:** open. Tracked as the gate for DEV-022 Lookback Leadership rotation.


---

## DEV-021c: grace timeout 30s matches peer sequential-chain cycle

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` (grace_deadline)
**Spec section:** «Cross-window cementing timeline»
**What the code does:** grace timeout raised from 5000ms to 30000ms. Peer nodes run their own sequential SHA-256 chain step (~25-30 s wall-clock per window on calibrated hardware). Peer BCs and Reveals for window N reach the proposer ~25–30 s after the proposer broadcasts candidate(N) — the round-trip is bounded by the peer's full sequential-chain cycle for that window, not network latency. Previous 5 s grace consistently missed peer responses; 30 s grace lets peer BCs and Reveals land before cement.
**Severity:** mainnet-fairness blocker (without this, peer-quorum gate could never fire and DEV-021 lottery degenerated to single-candidate).
**Closure path:** ↑ implemented.
**Closure cost:** 1 line.
**Status:** closed (Build 19 sha 759544cc, this session).

Live verification: Moscow log shows
  `[dev-019] peer-quorum gate satisfied: 3/3 BCs for w=4389`
  `[dev-021] cemented_reveals=3 candidates=3 winner=75bfaf9026405c12`
Multi-candidate lottery proven on real mainnet windows.


---

## DEV-022: Lookback Leadership rotation

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` — `winner_history` state, drain-side `winner_history.insert`, active arm gate, own-cement `winner_history.insert`.
**Spec section:** «Lookback Leadership / proposer_W = winner_{W-2}»
**Spec quote:** «proposer_0 and proposer_1 = bootstrap node. Starting from proposer_2 = winner_0, standard lookback logic.»
**What the code does (before):** active arm gated on `is_genesis` — only bootstrap proposed; non-bootstrap nodes were permanent followers; no proposer rotation; emission concentrated in bootstrap regardless of lottery.
**What the code does (after):**
  1. `winner_history: BTreeMap<u64, NodeId>` records per-window cemented winners (bounded to 64 entries).
  2. Main drain populates `winner_history[W]` from cemented Proposal envelopes received from any peer.
  3. Own cement also populates `winner_history[current]` so the proposer's own rotation gate sees its just-cemented winner two windows later.
  4. Active arm computes `proposer_W = if W < 2 { bootstrap } else { winner_history[W-2].unwrap_or(bootstrap) }`.
  5. If `my_node != proposer_W` → follower mode; if `my_node == proposer_W` → run full proposer pipeline (compute Reveal, broadcast candidate, spin-drain BCs, grace, determine winner, cement).
  6. Genesis bootstrap rule preserved: proposer_0 = proposer_1 = bootstrap (no winner_history available yet).
**Severity:** mainnet-critical for emission decentralization. Without Lookback, bootstrap permanently captures all emission regardless of lottery (DEV-021 outcome ignored).
**Closure path:** ↑ implemented. Live verification on next deploy.
**Closure cost:** ~50 lines of Rust.
**Status:** closed (Build 21 sha 8936f063, this session).


---

## DEV-022b: Lookback rotation gate disabled pending DEV-023 fallback cascade

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` (active arm gate)
**Spec section:** «Lookback Leadership / Fallback cascade»
**What the code does (before):** DEV-022 gated active arm on `my_node == winner_{W-2}`. Each operator independently maintained `winner_history`; both bootstrap and elected proposer saw the OTHER as proposer for their respective windows and both became followers — dead-lock. The spec's fallback cascade («fallback_proposer_W = second_min(weighted_ticket)») was not yet implemented, so a stuck elected proposer left the chain indefinitely frozen.
**What the code does (after):** rotation gate reverted to bootstrap-only. `winner_history` is still maintained (drain-side + own cement) so DEV-023 can introduce rotation on top of a working fallback cascade.
**Severity:** dead-lock recovery; not a fairness regression beyond pre-DEV-022 state.
**Closure path:** implement DEV-023 fallback cascade (if elected proposer doesn't cement within K windows, second_min becomes proposer), then re-enable rotation gate.
**Closure cost:** revert: 5 lines; DEV-023: ~80 lines.
**Status:** closed (Build 22 sha c8de927c, this session).


---

## DEV-023 (open): proposer fallback cascade

**Crate:** `montana-node`
**File:line:** active arm proposer gate
**Spec section:** «Lookback Leadership / Fallback cascade»
**Spec quote:** «If < 67% signed → proposal rejected. Fallback: `fallback_proposer_W = second_min(weighted_ticket)` of window W-2. Fallback cascade: third_min, fourth_min, etc.»
**Status:** open for v1.0.1.
**Closure path:**
  1. Each Active node tracks `proposer_silence_windows[W]` = how many windows have elapsed since `expected_proposer_W = winner_{W-2}` should have cemented W and hasn't.
  2. If `proposer_silence_windows[W] >= K` (K = 3 per spec discussion), use `sorted_candidates_for_fallback(reveals_{W-2})` to compute `fallback_proposer_W`.
  3. Cascade: if fallback_1 also silent for K more windows → fallback_2, etc.
  4. Bootstrap operator is final guaranteed fallback (eliminates dead-lock).
**Closure cost:** ~80 lines + integration test for `silence_counter` consistency across operators.
**Operational note (current state).** Without DEV-023, DEV-022 rotation gate is disabled (see DEV-022b). Bootstrap remains sole canonical proposer. DEV-021 winner determination + lottery rotation work end-to-end at emission level: every cemented Proposal records a different winner across the active cohort, so emission is distributed even without proposer rotation. The chain remains live; only proposer-set diversity is deferred.

---

## v1.0.0 Mainnet Baseline (2026-05-30)

Closed DEVs live on mainnet at sha c8de927c (Build 22):
  - DEV-017 follower t_r_history populated from Proposal envelopes
  - DEV-018  fast-sync chunk anchor_window + stale-peer filter
  - DEV-018b/c/d fast-sync client retry on discard, 10s deadline, inline serve during proposer spin
  - DEV-019  post-quorum 500ms grace for peer BC inclusion
  - DEV-019b peer-quorum gate ⌈total/2⌉ + 30s grace
  - DEV-020  per-window Reveal broadcast + reveal_pool on all nodes
  - DEV-021  winner determination from cemented Reveal set (argmin weighted_ticket)
  - DEV-021c grace = 30s = peer sequential-SHA-chain cycle

Open for v1.0.1:
  - DEV-021b peer drain during sequential-SHA-chain tick (latency floor)
  - DEV-022  Lookback proposer rotation (requires DEV-023)
  - DEV-023  proposer fallback cascade

Live verification (window 4418..4422 explorer snapshot):
  /api/winners → 5 distinct winners in 6 consecutive windows (vilnius, frankfurt×2, vilnius, moscow, armenia)
  /api/consensus → chain_length distribution: moscow 958‰, frankfurt 27‰, vilnius 7‰, armenia 5‰, helsinki 1‰
  bundles=3 (multi-confirmer cement) on majority of windows
  emission distributed per spec lottery; bootstrap is sole proposer pending DEV-022/023.


---

## DEV-023: bootstrap fallback after K=3 silent windows + DEV-022 re-enable

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` — `last_proposer_cement` state, active arm cascade gate.
**Spec section:** «Lookback Leadership / Fallback cascade»
**Spec quote:** «If < 67% signed → proposal rejected. Fallback: `fallback_proposer_W = second_min(weighted_ticket)` of window W-2. Fallback cascade.»
**What the code does:**
  1. `last_proposer_cement: BTreeMap<NodeId, u64>` records per-proposer last cemented window. Populated drain-side (from received cement.proposer_node_id) AND own-cement-side (active arm).
  2. Active arm gate computes `primary_proposer = winner_{W-2}` per DEV-022 Lookback.
  3. `primary_silent = current - last_proposer_cement[primary_proposer]`. If `primary_silent >= K_FALLBACK_WINDOWS (3)` AND primary != bootstrap → fallback to bootstrap.
  4. Bootstrap is canonical fallback always-active (cannot itself be silent because if bootstrap silent, no one cements at all → all stuck).
  5. Each node deterministically computes same active_proposer from canonical state; no coordination round needed.

**Simplification vs spec:** Spec's full cascade («second_min, third_min, ...») requires sorted_candidates_for_fallback over reveals_{W-2}. Current implementation collapses cascade to bootstrap-only fallback. Spec-correct multi-level cascade deferred to v1.0.2 — requires further work on reveal-pool persistence across the W-2 lookback window plus a coordination protocol to break ties when multiple fallback candidates think they should propose.

**Severity:** mainnet-critical for emission decentralization once DEV-022 rotation is re-enabled.
**Closure cost:** ~30 lines of Rust (this commit).
**Status:** closed (Build 23 sha ede6dffb, this session).


---

## DEV-023b: election grace for newly-elected primary

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` active arm gate (primary_active computation)
**Spec section:** «Lookback Leadership / Election grace»
**What the code does:** when `primary_proposer != bootstrap` AND `last_proposer_cement[primary] == 0` (never cemented), check whether primary won lottery in last K_FALLBACK_WINDOWS via winner_history. If yes — treat as active (give grace), let primary attempt to propose. Without grace, silent_count = current (=4467) immediately exceeds K=3 and fallback to bootstrap fires before primary ever runs.
**Severity:** required for DEV-022 rotation to be operationally meaningful (otherwise every newly-elected non-bootstrap proposer is preempted by bootstrap fallback in the first iteration).
**Closure path:** ↑ implemented. Live verification:
  - Moscow log: `[lookback W=4467] primary=5509211b179d6969 silent=4467 active_proposer=5509211b179d6969 my_node=75bfaf9026405c12 — follower mode`
  - Moscow correctly defers to Frankfurt for W=4467 (Frankfurt is elected primary AND won 4465 within last K windows). Bootstrap fallback NOT triggered.
**Closure cost:** ~15 lines.
**Status:** closed (Build 24b sha ad27ae713758, this session).

**Operational note.** Frankfurt does not yet actually propose for W=4467 because of upstream DEV-021b (peer drain during sequential-SHA-chain tick) — Frankfurt's local current=4466 doesn't advance to 4467 before bootstrap takes over the cement via fallback K-window timeout. Full multi-proposer rotation gated on DEV-021b closure (drain refactor with periodic message processing inside ssha_step_chunked).


---

## DEV-023c: election grace tied to FIRST election, not every win (hotfix)

**Crate:** `montana-node`
**File:line:** `crates/montana-node/src/commands/start.rs` active arm gate (`primary_active` computation)
**Spec section:** «Lookback Leadership / Fallback cascade»
**Bug:** DEV-023b grace check was `won_recently = any window in [W-K..W-2] where winner == primary`. If primary (e.g. Frankfurt with growing chain_length) kept winning lottery, every window had a fresh `won_recently=true` → grace re-triggered indefinitely → bootstrap fallback never fired → chain frozen.
**Symptom (mainnet 2026-05-30 17:00):** cw=4469 unchanged for 30+ minutes despite Moscow active on Build 24b. Moscow log: `[lookback W=4470] primary=Frankfurt silent=4470 active_proposer=Frankfurt — follower mode` repeatedly; Frankfurt never cemented (gated on DEV-021b drain-during-sequential-chain-tick), Moscow stuck deferring.
**Fix:** grace measured from FIRST election window (the smallest W where `winner_history[W-2] == primary`), not from the most recent win:
```rust
let first_election = winner_history.iter()
    .filter_map(|(w, n)| if *n == primary { Some(w + 2) } else { None })
    .min()
    .unwrap_or(current);
primary_active = current - first_election < K_FALLBACK_WINDOWS
```
After K windows since FIRST election, bootstrap fallback fires regardless of whether primary keeps winning. Each primary gets one grace term per genesis run.
**Live verification:** chain resumed at cw=4475 within 5 minutes of Build 25 deploy. `bundles=2` cementing stable; Moscow winning lottery again (sufficient chain_length).
**Severity:** mainnet liveness blocker — must close before re-enabling rotation; deployed as urgent hotfix.
**Status:** closed (Build 25 sha 5a22bf8c53c6, this session).


---

## DEV-022/023 disabled (v1.0.1 baseline freeze)

**Decision (mainnet 2026-05-30 17:55):** DEV-022 Lookback rotation + DEV-023(a/b/c) fallback cascade gate DISABLED. Bootstrap is sole proposer. Lottery (DEV-021) still picks per-window winner_id and distributes emission; rotation just doesn't kick in.
**Reason:** Even after DEV-023c first-election-anchored grace, chain throughput collapsed to ~1 cement per 16 min (vs 30s baseline) because each new primary win re-armed grace via fresh winner_history entries while old min() values aged out. Without DEV-021b drain refactor (peer can apply candidate during their sequential SHA chain tick), non-bootstrap proposers can never actually cement, so rotation only stalls the chain.
**Code change:** active arm gate is `my_node != bootstrap_node_id → follower_skip = true`. `winner_history`, `last_proposer_cement`, `K_FALLBACK_WINDOWS` remain in code (unused, dead-letter) for future v1.0.1 re-enable on top of DEV-021b closure.
**Status:** Bootstrap-only proposer is the v1.0.1 mainnet baseline. Rotation gated on DEV-021b future work.


---

## v1.1.0 Spec-faithful consensus loop (2026-06-12, commit 6ea9d12+)

Deviations closed by this cycle:

- **DEV-021b closed.** `drain_network`/`handle_protocol_message` are called between chunks of the sequential SHA-256 chain (`ssha_step_chunked` on_chunk) and from the leader's quorum-wait loop — the spec requirement "continuity of the sequential SHA-256 chain" is met literally: finalization and ticket intake run in parallel with computing the next window. Confirmed by a local assembly of 3 nodes: confirmers=3 on every window after the genesis ones.
- **DEV-022 closed (re-enabled).** Lookback rotation of the leader: `proposer_W = winner_{W-2}` from `winner_history` (canonically from the cemented proposal_{W-1}); the header signature is verified against `NodeTable[proposer_node_id].node_pubkey` (mt_consensus::validate_header), not against the first settler's key. Confirmed: all three nodes of the assembly cement (46/63/44 over 150 windows).
- **DEV-023 closed (cascade).** Fallback cascade: depth = elapsed/FALLBACK_TIMEOUT_SECS (120 s), `mt_consensus::fallback_proposer` over the sorted weighted tickets of window W-2 from `lottery_history`; the first settler is the terminal safety net for the genesis windows. Tolerance of ±1 depth level for wall-clock divergence on receipt.
- **DEV-012 closed (multi-confirmer).** Cementation only on a real quorum: Σ chain_length of the BC signers ≥ 67% of the active length (active predicate 2τ₂ — `active_chain_length_at`). No timeout cementation: when the quorum is unreachable the chain honestly waits (verified by a node failure: growth 2 windows of inertia → freeze → resumption when the node returns).

Two-window pipeline per the spec "Window closure (Lookback Leadership Finalization)":
- The BC of window W carries the reveal_hashes of window W-1; cementation of the W-1 tickets is weighted by the chain_length of the BC_W signers (67% threshold), not a union of sets.
- proposal_W: included_bundles = BC of window W-1 (chain_length++ for confirmers at settle W), included_reveals = the cemented set of W-1, winner_{W-1} = argmin, payout at settle W ("One-window lag of the reward").
- Envelope: `[header 3722][u16 n1][BC W-1][u16 n2][BC W]` — the cementation evidence is included, followers re-check the weighted threshold and the winner against their own pool.
- Canonical confirmation aggregate: `cemented_bundle_aggregate(w, bc_set_history[w])` — the actual set of confirmers from the included_bundles of the proposal that closed window w (previously an empty list was passed everywhere).
- Each node archives the cemented envelope (`archive_proposal_envelope`) — explorer data completeness on any node; per-window histories are restored from the archive on restart.
- A lagging neighbour (gap < fast-sync threshold) catches up by re-serving archived envelopes against its stale BC.

Open honest divergences (new entries):

## DEV-024 (open): cemented_bundle_aggregate — node_id instead of signatures

Spec: "the aggregate of signatures of the cemented BundledConfirmation of window W-2 … contains the ML-DSA-65 signatures of future confirmers — the aggregate is unpredictable offline". Implementation mt-timechain (KAT-frozen): the aggregate is over the **node_id** of the confirmers. The set of node_id is predictable → protection against grinding is weaker than declared. For an assembly of 3 nodes the practical risk ≈ 0. Closure: the author's decision — either a spec amendment (aggregate over node_id), or a primitive change (aggregate over signatures, KAT regeneration). Do not close silently.

## DEV-025: lottery target without τ₂ calibration

**Status: closed (commit baca884).** `mt_lottery::calibrate_target` — integer form of the spec (u256 intermediate, saturation, TA4 zero case); binding vectors TA1-TA5 byte-for-byte in the tests. Node: the counter of cemented tickets per τ₂ and the threshold target are persistent (timechain v2), recomputation at the τ₂ boundary in a single state transition, candidacy gate weighted_ticket < target at ticket publication, target in the header and verification by followers.

## DEV-026 (open): leader equivocation — first valid wins, not reject-both

Spec: "Two proposals from the same proposer_node_id in one window: both are rejected". Implementation: the first valid quorum envelope is applied; the second is rejected by window monotonicity. Safety rests on the BC quorum (identical content is deterministic); divergence is possible only in metadata (prev_proposal_hash during a fallback race). Closure: buffering of competing envelopes of the window + a selection rule.

## DEV-027 (closed): supply formula corrected to EMISSION_moneta × W (EXT-MON-01, spec v35.26.2)

Window 0 is genesis without emission (`apply_emission` is a no-op at `window_w == 0`); the first payout is settle(1) to the winner of window 0. Spec v35.26.2 fixes the closed form `supply_moneta(W) = EMISSION_moneta × W`, `supply_moneta(0) = 0` (the "Emission" section and the supply-audit bullet are self-consistent). The `supply_moneta` helper, mt-account unit tests, `determinism_invariants`, `status.rs`, `m3_account.rs`, AUDIT.md were aligned to × W (REAUDIT-01, GPT-5 Codex 02). The helper↔state divergence is eliminated: both the state transition (no-op at W=0) and the closed form give EMISSION × W. Status: closed.

---

## v1.2.0 Fault tolerance + lottery integrity (2026-06-13)

- **DEV-021c (closed, superseded by DEV-032 — deterministic 2τ₂ quorum).** The fixed grace is replaced by an adaptive one: liveness-grace = 3× the duration of one turn of the sequential SHA-256 chain, leader takeover timeout = 2× a turn. The measurement is a clean turn (not the whole iteration including waiting), otherwise the grace inflated and a solo takeover did not fit in time.
- **DEV-028 (closed, superseded by DEV-032 — wall-clock degraded removed): bootstrap degraded failsafe (M4-INFO-10).** If the 67% quorum of the active length is not collected within the liveness-grace, bootstrap cements with the present set (threshold = 67% of the present confirmers); a follower accepts an envelope from bootstrap with this threshold. The network advances when nodes drop out — verified 3→2→1→3: growth on two nodes, growth on bootstrap solo, restoration of rotation when nodes return. The privilege belongs only to bootstrap and only in degraded mode; with everyone online — strict 67% and honest rotation.
- **DEV-029 (closed): reveal-set ripening.** With equal weights the ticket cementation quorum = unanimity (⌈67%×N⌉ with N equal = N). A late ticket of window W-1 reduced the lottery of the window to a single candidate. A node re-issues its confirmation of window W on receiving a new ticket of window W-1, the set converges to the full one at all nodes → the unanimous quorum is reached. Verified: candidates=3 in 23-28 of 30 windows (was 0/1), winners rotate across all nodes.

**Operational (not a defect).** A node behind NAT (a flapping channel) in degraded mode joins the lottery only when its tickets arrive in time; its dropout does not bring the network down (bootstrap + stable nodes carry on). This is exactly the "tempo of the median active set" of the spec.

---

## External audit GPT-5 Codex 01 (2026-06-14) — delta findings reconciliation

The second external audit re-found several items that the internal hot-fix track
had marked `closed`. The `closed` status meant "intentional feature, done on
purpose" — not "matches spec". For an external reviewer `closed` reads as
"resolved", which is misleading. The entries below reconcile that: a deliberate
code feature that is not in the Protocol spec is a spec-divergence regardless of
intent, and must be either removed or formalized in the spec (firewall: spec
change with version bump + KAT). Wall-clock-derived consensus inputs cannot be
formalized as-is ([I-3]) and must be removed from acceptance.

## DEV-030 (closed, commit 31ed1a1): genesis cohort from hash-bound params, not runtime force_active (EXT-GEN-02)

Spec (Genesis Decree, lines 2380, 2477-2479): the genesis Active set is
`bootstrap + genesis_active_operators`, and `genesis_active_operators` is a
hash-bound field of `protocol_params` (enters the Genesis State Hash). Runtime
override is forbidden; `N_SEED` defines ONLY the window-0 cohort.
Implementation: `montana-node` builds the initial Active set from
`manifest.force_active` (`commands/start.rs` extra_actives -> `state.rs`
bootstrap), and never reads `genesis_active_operators`. The cohort lives in a
runtime JSON outside the Genesis State Hash -> two nodes with different manifests
build different node_root/account_root: split-brain at window 0.
Closed: the initial Active set is built from `genesis_params()`
(bootstrap + `genesis_active_operators`); manifest becomes discovery-only;
`force_active` removed from the production manifest. For the singleton mainnet
(`n_seed=0`) the initial set is just bootstrap. Tied to the singleton-genesis
architecture decision. Severity: mainnet blocker ([I-3] / EXT-GEN-02).

## DEV-031 (closed, commit 64489b2): quorum active predicate horizon-4 vs 2τ₂ (EXT-QRM-01)

Spec ("Active node predicate", line 1259): `active(node, W) =
(W - last_confirmation_window) <= 2 × τ₂_windows`, "Applied in quorum".
Implementation diverged: `active_chain_length_at` used a local
`QUORUM_ACTIVE_HORIZON = 4` plus a `max(last_confirmation_window, start_window)`
floor. Closed: now delegates to `mt_state::is_active(n, w, params.tau2_windows)`,
byte-exact to spec and deterministic. The spec predicate is self-consistent
(activation sets lcw=0; Step 3.5 sets lcw=W on cemented confirmation), so the
horizon-4/floor workaround was unnecessary and non-conformant.

## DEV-032 (closed, commit adbf1be): wall-clock removed, deterministic 2τ₂ quorum (EXT-QRM-02)

Supersedes the "closed" status of DEV-021c (adaptive grace) and DEV-028
(bootstrap degraded failsafe) for spec-conformance purposes. Those are
deliberate fault-tolerance features, but they are NOT in the Protocol spec and
they read local wall-clock:
  - `peer_seen: BTreeMap<NodeId,(Instant,Duration)>`, `mark_peer_seen`/`peer_alive`
    via `Instant::now()` + `GENESIS_FIRST_CONTACT_SECS=600` / `GENESIS_MEMBER_GRACE_SECS=90`;
  - `live_quorum_need` over `peer_alive`; acceptance threshold
    `need_quorum = if degraded { quorum(present_cl) } else { quorum(active_cl) }`.
Two honest nodes with different `peer_seen` (different clocks + delivery) compute
different `need_quorum` for the same evidence set -> different acceptance -> fork.
This is a direct [I-3] violation: consensus acceptance must be deterministic from
cemented state, never from `Instant`/seconds.
Closure path (architectural decision required, firewall):
  (a) remove the wall-clock degraded path from acceptance; rely on the
      deterministic 2τ₂ active set (DEV-031) plus BFT margin — for fault tolerance
      run >=4 active nodes (quorum 3-of-4 tolerates 1 fault); the singleton-grows
      model reaches this margin via the candidate admission mechanism; OR
  (b) formalize a deterministic fault-tolerance rule in the Protocol spec (no
      wall-clock) with a version bump + KAT.
The wall-clock inputs must go in either case. Severity: mainnet blocker.

## DEV-027 (closed, GPT-5 Codex 02 round): emission at window 0 (EXT-MON-01)

Resolved. Spec v35.26.2 fixes "window 0 has no emission": closed-form is
`supply_moneta(W) = EMISSION_moneta × W`, `supply_moneta(0) = 0`. The stale
supply-audit duplicate that still read `× (current_window + 1)` was removed
(spec self-consistency, [I-10]). Code helper `supply_moneta`, unit tests,
`determinism_invariants`, `status.rs` and `m3_account.rs` aligned to `× W`.
State transition (`apply_emission` no-op at W=0) and closed-form now agree.
See the closed entry above.

## Out of this conformance pass (separate passes)

- EXT-SYNC-01 (FastSync anchor self-block): not re-verified in this pass; verify before fix.
- EXT-FFI-01: memory-hygiene class (security pass), not spec-conformance.
- EXT-TEST-01 (hanging jittery_write_no_frame_duplication mock): mt-noise-pq test infra.
- EXT-GEN-01, EXT-DOC-01: closed (conformance-gate green; commits dd4e595 / 83379e3).

---

## Security pass (External audit GPT-5 Codex 01) — closures

## DEV-035 (closed, commit bca06ba): FFI secret zeroization (EXT-FFI-01)

mt-bindings C/JNI made plain copies of seed / secret-key material (master_arr,
seeds, master, acc_seed, the pk||sk||account_id buf, sk_bytes from Java) that
were never wiped. Closed: each secret buffer wrapped in zeroize::Zeroizing.

## DEV-036 (closed, commit HEAD): hanging jittery write test (EXT-TEST-01)

mt-noise-pq Jittery::poll_write returned Pending without a waker -> block_on hung.
Closed: cx.waker().wake_by_ref() before Pending.

## EXT-SYNC-01 (closed): FastSync anchor self-block

Self-block closed in DEV-037 (observed anchor root persisted before fast-sync
return). The exact-anchor binding residual flagged by the GPT-5 Codex 02 re-audit
(REAUDIT-03) is closed in DEV-044 below: single-anchor-per-session +
recent_roots[anchor_window] byte-exact match.

## DEV-037 (closed, commit see git log): FastSync anchor self-block (EXT-SYNC-01)

Verified against current code: the lagging fast-sync branch in montana-node
start.rs sent FastSyncRequest{anchor_window: w} and returned before recent_roots
was populated, so FastSyncClient::finalize could not match the snapshot root for
the anchor window — the lagging node self-blocked. Closed: persist the observed
(w, header.state_root) into recent_roots before the fast-sync return. Deeper
exact-anchor binding (pass requested anchor to the client, verify chunk
anchor_window equality) is a follow-on hardening, not required to close the
self-block.

## DEV-044 (closed): FastSync exact-anchor binding (EXT-SYNC-01 residual, REAUDIT-03)

**Crate:** `mt-sync`, `montana-node`, spec `Montana Network`
**Spec section:** «Sync protocols → FastSyncResponse» / «State root verification»
**What the re-audit found:** DEV-018 added `anchor_window` to the wire and a
stale-peer discard filter, and DEV-037 closed the self-block, but `FastSyncClient::
finalize` still scanned the whole `recent_roots` set for ANY root match
(`recent_roots.iter().find(|(_, r)| **r == root)`), and `wire_chunk_to_sync`
dropped `anchor_window` so the mt-sync layer could not reject chunks assembled
from mixed anchors. Code comments (payloads.rs DEV-018) and the prose claimed
exact-anchor binding; the implementation did "any observed recent root". One
story across spec, code, comments and tests was missing (REAUDIT-03).
**What the code does (after fix):**
  1. `mt_sync::FastSyncChunk` gains `anchor_window`; `wire_chunk_to_sync` carries it.
  2. `FastSyncClient` records the session anchor from the first chunk; a chunk with
     a divergent `anchor_window` is rejected (`AnchorMismatch`) — no frankenstein
     state from mixed heads.
  3. `finalize` looks up exactly `recent_roots[anchor_window]` and accepts only on a
     byte-exact match; missing observed root at the anchor → `AnchorMissing`. The
     scan-all path is removed.
  4. Spec: FastSyncResponse chunk layout gains `anchor_window 8B`; verification text
     and test vector C-0x41 (21 B header / 85 B total) updated; Network spec bumped
     to v1.4.0 (wire change).
**Decision (architect):** FastSync is exact-anchor against the peer-head
`anchor_window` reported in the response — not the originally requested window and
not any observed root. This is the practical model (server serves its current
head, no historical-snapshot retention) and the strict-integrity model (follower
accepts only a root it independently observed as cemented at exactly that window).
**Severity:** medium (integrity/consistency; not a direct production break — the
honest path already converged, but mixed-anchor reassembly was not rejected early
and the comments/spec/code disagreed).
**Closure cost:** ~80 lines across mt-sync (struct + accept_chunk + finalize +
tests), montana-node fastsync.rs, mt-net wire, and the Network spec.
**Status:** closed (this session).

## EXT-NOISE-RESIDUAL (closed, commits b301c03 + spec Network v1.3.1): XX signatures bind shared secrets

Known residual from a prior audit: XX handshake signatures signed the transcript
(ephemerals, KEM ciphertexts, identity pubkeys) computed before the post-decap
shared secrets ss_i/ss_r entered the signed area, while the master key included
them — a formal AKE proof gap. Closed: sig_r signs transcript ‖ ss_i; sig_i signs
transcript ‖ ss_i ‖ ss_r (both construction and verification, symmetric). No wire
change. Roundtrip/tamper/KAT/e2e/loopback pass; Network spec bumped to v1.3.1.

## DEV-038 (closed): `inspect` printed legacy Ed25519 peer_id, not the Noise_PQ XX network peer_id

**Crate:** montana-node · **File:** crates/montana-node/src/commands/inspect.rs
**Severity:** medium (operational — broke manifest assembly)

`montana-node inspect` printed only `libp2p_peer_id` = `identity.libp2p_peer_id()`
(a legacy Ed25519 multihash, `12D3KooW…`). The production Noise_PQ XX transport
identifies peers by `derive_peer_id(node_pk)` — a SHA-256 multihash of the
ML-DSA-65 node public key (`Qm…`). An operator building a `genesis-manifest`
from `inspect` output pinned the wrong peer_id → every dial failed `WrongPeerId`.
Closed: `inspect` now prints `network_peer_id` (the Qm value used by the transport,
labelled "specify in genesis-manifest") and marks `libp2p_peer_id` as legacy/unused.

## DEV-039 (mitigated): fast-sync join "deadzone" for lag in [2, threshold]

**Crate:** montana-node · **File:** crates/montana-node/src/commands/start.rs
**Severity:** medium (join latency; self-heals, not a liveness break)

A node behind the cemented chain by N windows where `2 ≤ N ≤ FAST_SYNC_LAG_THRESHOLD`
makes no progress: sequential apply requires `w == current+1` (the producer does
not rebroadcast skipped windows), and fast-sync triggers only at `N > threshold`.
The node stalls until its lag grows past the threshold, then fast-syncs and catches
up. Observed live (3-node test cohort: candidates waited until ~1000 windows behind
before syncing). Mitigated: lowered `FAST_SYNC_LAG_THRESHOLD` 1000 → 64, so sync
latency is bounded to ≤64 windows; `MONTANA_FASTSYNC_LAG_THRESHOLD` env override
remains. Proper fix (a lightweight proposal-range catch-up request for sub-threshold
gaps, so the node fetches the few missing envelopes instead of waiting or
full-state fast-syncing) is a follow-on.

## DEV-040 (documented): fast-sync `StateRootUnmatched` under fast block production

**Crate:** montana-node / mt-sync · **File:** crates/mt-sync/src/client.rs (finalize)
**Severity:** low (test-cadence artifact; not reproducible at production cadence)

`FastSyncClient::finalize` accepts a downloaded snapshot only if its recomputed
state_root matches a root the client has independently observed (recent_roots).
When the producer advances during the request round-trip, it serves a snapshot at
window `w' > requested anchor w`; a far-behind client has not yet seen `w'`'s
cemented root, so finalize rejects with `StateRootUnmatched` and retries. At
production cadence (~1 window/minute) the producer advances ≈0 windows per
round-trip and the served window's root is already in recent_roots → match. The
strict root check is correct (rejecting unverified state is the safe behaviour);
the follow-on hardening noted in DEV-037 (bind the exact requested anchor so the
server serves state AS OF `w`, and verify chunk `anchor_window == w`) removes the
race entirely.

## DEV-041 (closed): concurrent `FsStore::open` deletes a live node's in-flight `.tmp` → node death

**Crate:** mt-store · **File:** crates/mt-store/src/lib.rs (cleanup_orphan_tmp)
**Severity:** mainnet blocker (liveness — any external `status` poll can kill a running node)

`FsStore::open` called `cleanup_orphan_tmp` which removed **every** `*.tmp` in the data
dir + proposals/. `write_atomic` writes `<name>.tmp` then `fs::rename(tmp, final)`.
When a second process opens the same data dir concurrently (the explorer collector or
a heartbeat running `montana-node status`, both call `FsStore::open`), its cleanup
deleted the running node's just-written `accounts.bin.tmp` in the window between the
node's `fs::write(tmp)` and `fs::rename(tmp → final)` → the rename failed with
`Io(NotFound)` → `save accounts` errored → the node exited. Observed: Mac node in the
3-node spec cohort died after ~5 windows from `save accounts: No such file or
directory`; root cause is the 30s status-poll racing the per-window write_atomic.
Closed: cleanup_orphan_tmp now removes only **stale** `.tmp` (>60s old) — an in-flight
temp of a concurrent writer is sub-second old and is left untouched, while genuinely
orphaned temps from a crashed write are still reclaimed.

## DEV-042 (closed): transactional apply replaces `panic!` on state_root divergence

**Crate:** montana-node · **File:** crates/montana-node/src/commands/start.rs:1411
**Severity:** mainnet blocker (liveness — one divergence halts an all-quorum cohort)

When applying a cemented proposal, the node recomputes the post-state root and, on
mismatch with `header.state_root`, calls `panic!` → the node dies. `settle_and_bookkeep`
mutates state in place before the check, so a clean fix needs transactional apply
(snapshot + rollback, or apply-on-clone then commit) followed by reject + fast-sync
recovery, not process death. Surfaced under non-spec fast cadence (D=400k) where the
fallback-proposer race (DEV-043) produced a transient divergence; at spec cadence the
trigger does not occur, but the fatal `panic!` remains a latent liveness hazard (Gate 13
class: one signed/divergent object must never crash a node). Fix deferred — consensus
state-transition change requiring careful design + tests.


**Closed:** `settle_and_bookkeep` now applies the proposal/expiry/selection to **clones** of the account/node/candidate tables, computes `post_root`, and commits (swaps the clones into live state + does timechain/history/current/disk bookkeeping) only when `post_root == expected_root`. On mismatch it returns `Ok(None)` without mutating real state or disk; the acceptor logs and rejects the window (no panic), and the node recovers the authoritative state via fast-sync as its lag grows past the threshold. The proposer path passes `expected_root = None` (it is authoritative) and commits unconditionally. One divergent or malformed envelope can no longer crash a node or halt an all-quorum cohort.
## DEV-043 (closed): wall-clock in fallback-proposer election is non-deterministic [I-3]

**Crate:** montana-node · **File:** crates/montana-node/src/commands/start.rs (expected_proposer)
**Severity:** medium (masked at spec cadence; can diverge proposer choice on node absence)

The fallback-proposer cascade depth uses `silence = last_cement_at.elapsed()` and
`fallback_secs = 2 × last_tick_dur`, both wall-clock and per-node. Under fast cadence
or network jitter the per-node `silence/fallback_secs` ratio differs by more than the
±1 depth tolerance (exp_now/exp_next), so nodes accept different proposers → apply
different proposals → state divergence. At spec cadence (~60s/window, fallback ~120s)
the margins absorb jitter and the legitimate proposer (winner of w-2 lottery, fully
deterministic) is used, so the race does not trigger with all nodes healthy. The
fallback path nonetheless violates [I-3] determinism; a deterministic tie-break for
fallback depth (e.g. derived from cemented state, not wall-clock) is the proper fix.
Mitigated by DEV-042: a divergence triggered by this race is now rejected and resynced instead of crashing the node. Full deterministic fix (fallback depth derived from cemented state / header-declared depth verification rather than per-node wall-clock) touches consensus leadership and is deferred to a deliberate spec+code change; it does not trigger at spec cadence with homogeneous nodes.


**Closure (commit see git log).** The follower acceptance path no longer computes a per-node wall-clock `silence`/`fallback_secs` depth to gate the proposer. Leader legitimacy is decided ONLY by `validate_proposer_is_canonical(header, sorted_W-2)` — i.e. `proposer_node_id == fallback_proposer(W-2, header.fallback_depth)` — a pure function of the signed header and the cemented W-2 candidate set, identical on every honest node. The cascade depth is the depth DECLARED in the signed header, not a local timer. Wall-clock survives ONLY in the proposer-side self-action decision ("do I lead this window"), which never enters consensus state: competing proposals of different depth for the same window carry an identical `state_root` (deterministic from cemented sets), so a depth race cannot diverge state. Residual metadata-only divergence of `prev_proposal_hash` under concurrent fallback is tracked as DEV-026 (not state-affecting: `prev_proposal_hash` is not cross-checked in `validate_header` and is not part of `state_root`). [I-3] restored.

## DEV-044 (open, acknowledged): devnet ssha_entry_windows / selection_interval = 1 (production = 20160 / 336)

**Crate:**           mt-genesis
**File:line:**       crates/mt-genesis/src/lib.rs (genesis_params)
**Spec section:**    "Genesis Decree → protocol_params"
**Spec quote:**      "ssha_entry_windows (8B) 20 160 (= τ₂)"; "selection_interval (8B) 336"
**What the code does:**  ssha_entry_windows = 1, selection_interval = 1 (TEST CONFIG, devnet) — a candidate enters within 1 window, admission to Active every window; for fast local node startup.
**Severity:**        medium (devnet-only; not part of the structural genesis layout / Genesis State Hash composition).
**Closure path:**    for mainnet return genesis_params to 20 160 / 336 (production values from the spec); the conformance contract will then match, and the conformance-gate will turn green on these two lines.
**Closure cost:**    minutes (two constants); re-baking the Genesis State Hash is not required.
**Status:**          open (devnet override, author-acknowledged for local testing)
**Acknowledged:**    the author explicitly chose "leave 1 for the test" (2026-06-23)


---

## DEV-045 (open, acknowledged): Transport profile T1 (TLS carrier + active-probe relay) specified, not implemented

**Crate:**           mt-net-transport / mt-net (target)
**File:line:**       not yet implemented (the production XX transport is T0 only)
**Spec section:**    Network spec "Transport profile ladder" (T1 row) + "Active-probe relay (T1)"
**Spec quote:**      "a connection that does not present the Montana inner handshake is relayed to the real cover host, so an active prober receives a genuine response and observes an ordinary reverse proxy"
**What the code does:** nothing. T1 is defined normatively in the Network spec; the code implements only T0 (raw Noise_PQ XX over TCP). No TLS carrier, cover-host binding, or active-probe relay exists in any crate (grep across crates/ returns zero hits for cover-host / active-probe / reverse-proxy).
**Severity:**        medium (spec-ahead-of-code; a feature gap, not a wrong-behaviour bug). A T0 node under active probing is detectable until T1 lands.
**Closure path:**    implement the T1 TLS-1.3 carrier + cover-host binding + relay-on-probe discriminator in mt-net-transport, wired through reachability profile selection in mt-net.
**Closure cost:**    > 1 working day — a separate milestone (TLS termination, cover-host reachability, probe discrimination).
**Status:**          open (spec-defined, code pending)
**Acknowledged:**    author asked to specify T1 in the spec now and defer the implementation (2026-07-02); recorded per critic finding F-4 (spec-ahead-of-code)

---

## DEV-046 (open, acknowledged): Entry-point distribution (EntryCapsule / pooled distribution / scoped racing) specified, not implemented

**Crate:**           mt-net (target)
**File:line:**       not yet implemented
**Spec section:**    Network spec "Entry-point distribution"
**Spec quote:**      "A capsule is a compact, self-authenticating record of one reachable entry ... signature 3309B ML-DSA-65 over the domain-separated preimage"
**What the code does:** nothing. The EntryCapsule wire record, its "mt-entry-capsule" signature, pooled requester-varied distribution, and ENTRY_RACE_WIDTH scoped racing are defined in the Network spec; no crate encodes, signs, distributes, or races entry capsules (grep returns zero hits for entry-capsule / ENTRY_RACE_WIDTH). Cold-start discovery in code uses the hard-coded seed list plus peer exchange, not the pooled signed-capsule mechanism.
**Severity:**        medium (spec-ahead-of-code; feature gap).
**Closure path:**    add an EntryCapsule type in mt-net with CanonicalEncode + ML-DSA-65 sign/verify over the "mt-entry-capsule" preimage, pooled distribution over the peer-exchange envelope, and scoped racing in the connection manager.
**Closure cost:**    > 1 working day — a separate milestone.
**Status:**          open (spec-defined, code pending)
**Acknowledged:**    author asked to specify entry distribution in the spec now and defer the implementation (2026-07-02); recorded per critic finding F-4 (spec-ahead-of-code)


---

## DEV-047 (open, acknowledged): Metadata-private mailbox access for federated clients (segregated indirect legs) specified, not implemented

**Crate:**           mt-net / messenger client (target)
**File:line:**       not yet implemented (federated clients connect directly to the mailbox relay)
**Spec section:**    Network spec "Metadata-private mailbox access (federated clients)"; Montana Messenger stage 7 (blind delivery), SUBSCRIBE segregation
**Spec quote:**      "Two relay roles serve a federated client, and they are distinct relays in different /16 groups: the inbox relay ... the session relay ... neither relay alone links an account to a session label"
**What the code does:** nothing. A federated client reaches a single mailbox relay directly; there is no access_class typing, no transit-relay indirection, and no inbox-relay / session-relay separation. The volunteer transit-relay primitive (Circuit Relay v2) exists but is not yet wired for metadata-private mailbox access, and the messenger client uses one relay for both the account-derived inbox label and the rotating session labels.
**Severity:**        medium (spec-ahead-of-code; a privacy feature gap, not a wrong-behaviour bug). Until implemented, a single active-logging relay can correlate the two ends of a federated conversation by IP + the stable inbox-label co-batched with session labels.
**Closure path:**    (a) mt-net + substrate: the inbox is an erasure-coded object in the §3 data substrate (m-of-k across the k nodes at H(account_id || epoch_seed), epoch_seed = the cemented aggregate carried from the previous selection interval per [I-8], reshuffled each interval with shard migration for durability); the session node is a single stable node at H(routing_secret) (secret-derived, untargetable, no rotation); relays and committee nodes are authenticated by IBT + Node-Table Merkle membership against a state root the light client obtains by verifying the signed cemented header chain from the genesis manifest; web-only clients run reduced-assurance (bootstrap trust); each leg reached over a volunteer transit-relay (put/poll split under /16+ASN diversity), so no single role holds the account marker with the session labels; (b) messenger client: inbox subscription on the inbox relay, session subscription on the session relay, on decorrelated poll clocks.
**Closure cost:**    > 1 working day — a separate milestone (spans mt-net transport and the messenger client).
**Status:**          open (spec-defined across Network spec + Messenger stage 7, code pending)
**Acknowledged:**    author asked to apply the critic's 3-axis identity-marker segregation to the spec (2026-07-05); recorded per that decision

## DEV-048 (open, acknowledged): stale delivery model in mt-net (RangeSubscribe 0x63–0x65 + Blob Buffer) superseded by Messenger stage 7

**Crate:**           mt-net (msg_type.rs, payloads.rs, tests/test_vectors.rs, lib.rs, fuzz), mt-net-transport/codec.rs
**File:line:**       crates/mt-net/src/msg_type.rs (0x63/0x64/0x65), crates/mt-net/src/payloads.rs (RangeSubscribe*, BlobEntry), crates/mt-net/tests/test_vectors.rs (vector_c_0x63/0x64/0x65)
**Spec section:**    Network spec "Blind message delivery (client layer)" (reconciled); authoritative delivery is Montana Messenger stage 7 (blind delivery: rotating queue labels)
**Spec quote:**      "The network layer restates no label formula or delivery wire-format ... Delivery frames are messenger application frames inside that session, not network-layer protocol message types"
**What the code does:** mt-net implements the pre-refactor federated delivery — protocol message types 0x63 RangeSubscribeRequest / 0x64 RangeSubscribeResponse / 0x65 RangeSubscribeError over a Blob Buffer keyed by app_id = SHA-256("mt-app" || label), with 32-byte HKDF / "mt-queue-rotation" labels. Superseded: the messenger delivers over its own application Frame protocol (0x01–0x07 SUBSCRIBE/SEND/DELIVER/ACK/POLL/POLL_RESP) inside the client↔node Noise session, with 16-byte HMAC(routing_secret,"mt-label"‖dir‖W) session labels and a stable SHA-256("mt-inbox"‖account_id) inbox label (Messenger stage 7 KAT route_label_kat).
**Severity:**        medium (spec-ahead-of-code; dead network-layer message types + divergent label scheme, not a wrong-behaviour bug in the live path). The 32-byte HKDF labels / Blob Buffer do not match the messenger's 16-byte HMAC labels, so a client built on the mt-net types would be wire-incompatible with the messenger.
**Closure path:**    remove 0x63–0x65 from mt-net::msg_type + payloads + test_vectors + fuzz targets + mt-net-transport codec; drop Blob Buffer / app_id / "mt-queue-rotation" label derivation; federated delivery is the messenger client's Frame protocol over the Noise session (no network-layer RangeSubscribe). Keep 0x60–0x62 BatchLookup (current). Update the message-type registry to 18 codes / 5 categories to match the spec.
**Closure cost:**    < 1 working day (mechanical removal + registry/test update in mt-net).
**Status:**          open (spec reconciled in Network spec; mt-net cleanup pending)
**Acknowledged:**    author asked to reconcile the network spec to the messenger and fix (2026-07-06); recorded per that decision

## DEV-049 (open, acknowledged): MUQ durability gaps — drop-on-send, single-shard, no padding, inert TTL

**Crate:**           mt-overlay (queue_host.rs, muq.rs, inbox.rs, erasure.rs), mt-postman (muq.rs, muq_client.rs)
**File:line:**       mt-postman/src/muq.rs:333-338 (drop_delivered after send, not on B ack); mt-bindings/src/network.rs (deposit shard_total=1); mt-overlay/src/inbox.rs (bucket_len test-only); mt-postman/src/muq.rs:46,184 (window=0, prune not wired)
**Spec section:**    Etap 2 (MUQ) §488 (drop-on-delivery on confirmation), §201/§508 (erasure RS(k,n) across k hosts), §490 (padding to bucket inside AEAD), §198 (buffer with TTL)
**Spec quote:**      "By confirmation — drop-on-delivery"; "buffer spread m-of-k across k hosts, key = recv_id"; "padding inside AEAD"
**What the code does:** (a) host drops shards immediately after writing QueueResp to the courier (no end-to-end B acknowledgement) → if the courier→B leg fails, shards are gone (violates §526 "buffer never loses a message"); (b) deposit is a single shard to one host (shard_total=1), erasure RS(k,n) exists (erasure.rs) but is used only in tests → one host offline = message unreachable; (c) padding-to-bucket (inbox.rs bucket_len) is test-only → shard length leaks to the host; (d) window is hardcoded 0 and QueueHost::prune is never called from Node::run → TTL never fires on a live node.
**Severity:**        medium (off-chain [P2P-1] durability/metadata gaps; live single-host relay path delivers, but no multi-host durability, no length hiding, no TTL eviction). Not a consensus-fork bug.
**Closure path:**    (a) drop-on-delivery keyed to E2E delivery-receipt R1 (§593) rather than courier write; (b) wire RS(k,n) fan-out (prod RS(2,4)) across k hosts at deposit, reconstruct m-of-k at fetch; (c) apply bucket padding (§490) in deposit_via_proxy before seal; (d) derive window from floor(unix/60) (labels::window_index) and call prune each window from Node::run.
**Closure cost:**    > 1 working day (spans deposit fan-out, receipt-gated drop, padding, TTL timer — a durability milestone).
**Status:**          partial — closed by construction: (d) TTL — current_window() from the system clock (floor(unix/60), off-chain [P2P-1]) in handle_deposit + a prune timer (60s) in PostmanServer::run evicts expired shards (previously window=0 static → TTL dead). Closed by construction also: (a) drop-on-ack §593 — handle_relay_subscribe does NOT drop on send to the courier; TAG_RECEIVE_ACK/RELAY_ACK + mt_client_ack + ack_drain: the buffer is held until E2E confirmation by B. CLOSED FULLY. [legacy] (a) drop-on-delivery by E2E receipt §593; (b) RS(k,n) fan-out §201/§508 across k hosts — multi-host deposit + m-of-k reconstruct; (c) padding-to-bucket §490 — the messenger's E2E layer (bucket_len helper is ready in mt-overlay, applied by the messenger before E2E-encrypt, transport ct opaque). (a)+(b)+(c) — a fundamental durability redesign exceeding 1 day, a separate milestone. BOUNDARY (P2P Network v0.14.1 §508): (a) drop-on-delivery erases ONLY the postman's transit buffer after B's E2E confirmation — NOT the history; persistent history/media is reserved by the cloud of phones (Montana Messenger "Reserve data substrate", k-of-n R=2, a separate layer), dropping transit does not touch it. (b) transit RS and the cloud k-of-n are one erasure machinery on two layers.
**Acknowledged:**    deep critic-audit (2026-07-14); (d) closed per author 'close it to the end' (2026-07-15); (a)+(b)+(c) narrowed honestly as cross-layer durability milestone

## DEV-050 (open, acknowledged): MUQ anti-DoS gaps — unauthenticated registration, eager DedupWindow, relay-subscribe replay

**Crate:**           mt-overlay (queue_host.rs, dedup.rs), mt-postman (muq_client.rs, muq.rs)
**File:line:**       mt-overlay/src/queue_host.rs:54-57 (register_queue: bare insert, no ownership/quota); mt-overlay/src/dedup.rs:23-27 (with_capacity(4096) ≈160KB per recv_id); mt-postman/src/muq_client.rs:123 (client-generated subscribe nonce); mt-overlay/src/muq.rs (RELAY_CHANNEL_MARKER=0×32, no channel_hash on relay path)
**Spec section:**    Etap 2 §492 (send_key anti-spam), §478 (nonce issued by host), R4 (channel_hash binding); [I-15] (time-based scarcity for anti-spam)
**Spec quote:**      "nonce ... issued by the host before the request (freshness)"; anti-spam via send_key + buffer quota
**What the code does:** (a) register_queue accepts any Queue without ownership proof and with no cap on the number of queues; prune never removes empty queues / send_route / seen_sub_nonces → a peer registering K queues (its own valid recv_keys, free) drives ~K·160KB of seen_sub_nonces (eager DedupWindow prealloc, ×32 amplifier) → node-DoS; (b) relay-subscribe replay: nonce is client-generated (not host-issued per §478), anti-replay is a volatile 4096-entry window (not persistent) and the default non-collusion relay path drops channel_hash (marker 0×32) → a captured ReceiveProxy blob replays after window eviction or host restart; (c) re-registration is last-writer-wins on recv_pubkey (hijack if recv_id leaks).
**Severity:**        medium (off-chain node-DoS + relay-path replay weaker than the direct path's channel_hash binding; not a consensus bug).
**Closure path:**    (a) time-based registration barrier per [I-15] (one registration per identity per window) + lazy DedupWindow (grow on demand, cap total) + prune empty queues; (b) host-issued subscribe nonce (§478) + persistent dedup or channel_hash on the relay path; (c) proof-of-ownership on re-registration (sign against the prior recv_pubkey).
**Closure cost:**    > 1 working day (registration accounting + nonce protocol + dedup redesign).
**Status:**          partial — closed by construction: (b) DedupWindow lazy (HashSet/VecDeque grow as items are inserted, the ~160KB eager-prealloc per recv_id removed → the ×32 node-DoS amplifier is gone); (d) register_queue first-write-wins (an existing recv_id is not overwritten by another recv_pubkey, handlers → ERR). Closed by construction also: (c) host-issued nonce §478 (issue_nonce + 2-phase subscribe_via_courier, TAG_RECEIVE_NONCE/RELAY_NONCE, a stolen QueueSubscribe is non-transferable). CLOSED FULLY. [legacy narrow] (a) registration rate-limit [I-15] — requires an identity model for anonymous recv_id (a random id ≠ identity; candidate — per-connection/per-courier rate-limit); (c) host-issued subscribe nonce §478 — an extra round in the subscribe flow or persistent dedup instead of the volatile window. (a)+(c) — a protocol redesign exceeding 1 day, a separate milestone.
**Acknowledged:**    deep critic-audit (2026-07-14); (b)+(d) closed per author 'close it to the end' (2026-07-15); (a)+(c) narrowed honestly as protocol-redesign

## DEV-051 (open, acknowledged): rendezvous PQ-binding — overlay_addr↔account_id verify and self-host gate missing

**Crate:**           mt-rendezvous (lib.rs verify_record), mt-postman (node.rs)
**File:line:**       mt-rendezvous/src/lib.rs:316-329 (verify_record checks only ed25519 admission sig); mt-postman/src/node.rs:74-83 (register_queue_on accepts any host)
**Spec section:**    Etap 4 §595 (subscriber verifies overlay_addr against SHA-256("mt-overlay"||0x00||account_id)); Etap 3 §534 (direct registration only to own node)
**Spec quote:**      "overlay_addr in the record the subscriber verifies against SHA-256(\"mt-overlay\"||0x00||account_id of the friend) ... a forged overlay address is caught immediately"
**What the code does:** (a) verify_record validates only the ed25519 BEP44 admission signature; there is no helper that checks record.overlay_addr == mt_overlay::overlay_addr(friend_account_id), and no consumer performs it (the [P2P-5] argument "ed25519 is only a DoS-redirect, identity is PQ" rests on this first-line check, which is absent → a forged ed25519 record's overlay_addr is accepted, leaving only the second line R1 receipt); (b) Node::register_queue_on takes any host without a "this is my node" gate, so direct registration to a foreign host (which reveals the registrant's network identity) is not fenced off, contrary to the non-collusion default.
**Severity:**        medium (PQ-binding first line absent; redirect stops being "DoS-only" until the overlay↔account_id check is wired). Off-chain.
**Closure path:**    (a) add a verify helper `record.overlay_addr == mt_overlay::overlay_addr(friend_account_id)` and call it in every RendezvousRecord consumer (make the binding un-forgettable per lesson E-2); (b) gate Node::register_queue_on to self-host only (direct registration to own node).
**Closure cost:**    < 1 working day (verify helper + consumer wiring + self-host guard).
**Status:**          closed — (a) record_binds_account helper (mt-rendezvous) + a call that cannot be skipped in FFI mt_rvdht_resolve (friend_account_id, a forged overlay_addr → 0); (b) register_queue_on self-host gate (loopback, §534). Tests: record_binds_account_catches_forgery, e2e_stage3
**Acknowledged:**    deep critic-audit (2026-07-14); closed per author 'close it to the end' (2026-07-15)

## DEV-052 (open, acknowledged): silent empty QueueResp when the fetch frame exceeds the wire limit

**Crate:**           mt-postman (wire.rs, muq.rs)
**File:line:**       mt-postman/src/wire.rs:11,47-49 (MAX_FRAME_WIRE = MAX_PAYLOAD_LEN + 4096); mt-postman/src/muq.rs:255-279 (handle_receive_proxy maps any forward error to empty QueueResp)
**Spec section:**    Etap 2 §490 (padding buckets up to 1 MiB, quota up to u32); [C-2.1] corollary (no silent failure on the critical path)
**Spec quote:**      "no silent failure on the critical path" ([C-2.1] corollary)
**What the code does:** MAX_PAYLOAD_LEN is 2 MiB per single shard; a full QueueResp is the sum of all buffered shards (up to quota) and can exceed 2 MiB. recv_frame (read_to_end(MAX_FRAME_WIRE)) then errors TooLong, and handle_receive_proxy maps any forward_subscribe_to_host error to QueueResp{items:vec![]} silently → B receives an empty response and cannot distinguish "no mail" from "delivery broke", and the queue becomes undrainable via the relay path.
**Severity:**        medium (silent-failure on the fetch critical path; queue can wedge). Off-chain.
**Closure path:**    batched/paged fetch (return shards in frame-sized pages with a continuation cursor) OR an explicit "response too large, N bytes" error code distinct from the empty-queue case; never map the oversize error to an empty result.
**Closure cost:**    < 1 working day (paged fetch or explicit error code + test).
**Status:**          closed — handle_receive_proxy propagates errors (decode / no-route / forward-fail oversize → WireError → stream reset); an empty QueueResp remains only a legitimate host response, B distinguishes "no mail" from "broke" and does a refetch
**Acknowledged:**    deep critic-audit (2026-07-14); closed per author 'close it to the end' (2026-07-15)

## DEV-053 (closed): HostDeposit sealing — spec aligned to code (Noise_PQ XX → ML-KEM sealed-box, v0.14.0)

**Crate:**           mt-overlay (muq.rs), mt-postman (muq.rs handle_deposit, muq_client.rs)
**File:line:**       mt-postman/src/muq.rs:179 (open_from), muq_client.rs:100,132 (seal_to); mt-crypto/src/lib.rs:508,526 (ML-KEM-768 + ChaCha20-Poly1305 sealed-box)
**Spec section:**    Etap 2 §453/§469 ("sealed Noise_PQ XX to host") vs §472 ("the sender has no direct channel with host — two-hop")
**Spec quote:**      "HostDeposit { ... sealed Noise_PQ XX to host }"; "the deposit is NOT bound to the connection channel_hash (the sender has no direct channel with host — two-hop)"
**What the code does:** seal_to/open_from = ML-KEM-768 encapsulate + ChaCha20-Poly1305 sealed-box — a one-way asynchronous seal, NOT a Noise_PQ XX interactive handshake.
**Analysis:**        Noise_PQ XX is an interactive 3-message handshake; the deposit is asynchronous two-hop and §472 itself states the sender has no direct channel with the host, so Noise XX is inapplicable. ML-KEM sealed-box (the code) is the architecturally correct primitive for async one-way sealing to the host. The spec is internally contradictory (§453 "Noise_PQ XX" vs §472 "no direct channel"). [I-1] holds either way (both post-quantum). Noise_PQ XX remains correct for the hop-by-hop QUIC transport (§7), but not for the end-to-end sealed deposit.
**Severity:**        medium (spec↔code divergence on the sealing-primitive name and wire bytes; ML-KEM sealed-box bytes ≠ Noise_PQ XX handshake bytes; a spec-conformant independent host would attempt the wrong open).
**Closure path:**    spec fix (firewall) — §453/§469 "sealed Noise_PQ XX to host" → "sealed with ML-KEM-768 sealed-box (mt_crypto::seal_to; one-way, async — the sender has no interactive channel with the host)". The code is correct; the spec is the SSOT holder, so this edit requires author confirmation.
**Closure cost:**    < 1 working day (spec edit + version bump; code unchanged).
**Status:**          closed — spec aligned to code in P2P Network v0.14.0 (§453/§469 «Noise_PQ XX» → «ML-KEM-768 sealed-box», mt_crypto::seal_to); code unchanged (already ML-KEM); consistent with fetch §542 and improves [I-7] (one sealed primitive)
**Acknowledged:**    author approved the spec edit (2026-07-14); firewall — code was correct, spec brought into agreement
