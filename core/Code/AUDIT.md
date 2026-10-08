# Montana Reference Implementation — Audit Package

**Spec target:** Montana Protocol v35.26.2 + Montana Network v1.4.0 + Montana App v3.12.0 — see [VERSION.md](VERSION.md)
**Last verified:** 2026-06-18 (external re-audit GPT-5 Codex 02 fully closed — REAUDIT-01 monetary closed-form (× W), REAUDIT-02 dependency hygiene (cargo audit green), REAUDIT-03 FastSync exact-anchor (Network v1.4.0), REAUDIT-04 release-doc reconciliation, REAUDIT-05 legacy Noise XK deprecated, REAUDIT-06 conformance-gate expanded; spec at Protocol v35.26.2 + Network v1.4.0; conformance-gate GREEN 39/39)
**Audit-ready status:** **M1 + M2 + M3 + M4 + M5 + M6 + M7 + M9 layers + M8 consensus path — release-blocking findings closed.** The GPT-5 Codex 01 release-blockers (Genesis Decree consensus-binding, quorum/active determinism, FastSync anchor) are closed by construction; genesis active-set is hash-bound (no runtime injection), quorum is the deterministic 2τ₂ set (no wall-clock), FastSync persists the observed anchor root.

---

## TL;DR — what is ready for external audit

| Layer | Ready? | Crates | LOC | Tests + invariants | Open findings |
|-------|--------|--------|-----|---------------------|---------------|
| **M1 foundational** (cryptography + identity recovery) | ✅ **READY** | mt-codec, mt-crypto, mt-crypto-native, mt-mnemonic | ~2000 | 100+ unit + 13 security + 51 NIST KAT byte-exact | 0 (12/12 closed) |
| **M2 state foundation** (consensus state primitives) | ✅ **READY** | mt-merkle, mt-genesis, mt-state, mt-timechain | 1821 | 95+ unit + 60 determinism invariants | 0 (4/4 closed) |
| **M3 apply_proposal layer** (account operations + emission + state transition) | ✅ **READY** | mt-account | 2556 | 89 unit + 29 determinism invariants | 0 (3/3 internal closed: M3-1/M3-2/M3-3 + 10/10 external #3+VERIFIED closed: M3-A-1..M3-A-5 / F-5 / M3-A-3 / AUDIT-sync / P-C-1 F-19 reopen / P-C-2 history; M2-3/M2-13 superseded by v34 monetary refactor) |
| **M4 consensus mechanics** (lottery + proposal acceptance + node admission) | ✅ **READY** | mt-lottery, mt-consensus, mt-entry | 3858 | 187 unit + 85 determinism invariants | 0 (1/1 internal closed: M4-1; 7/7 external #4 closed: M4-MED-1/2 + M4-LOW-3..7 + M4-INFO-10) |
| **M5 persistence** (filesystem state + proposal archive + crash recovery) | ✅ **READY** | mt-store | 955 | 27 unit + 17 determinism invariants | 0 (manual scan clean; v34 monetary refactor removed MonetaryState persistence) |
| **Cross-implementation conformance** | ✅ **READY** | Domain registry sync (spec ↔ code, see VERSION.md) | — | NIST ACVP 66 byte-exact (KeyGen 50 + SigGen 15 + ctx-equivalence 1) + Recovery flow | 0 (F-1 spec patch closed) |
| **M6 network layer** (wire format + transport + IBT + Dandelion + mesh + SF) | ✅ **READY** | mt-net, mt-net-transport | ~3300 | 127 tests: mt-net 112 + mt-net-transport 15 (including 3 e2e two-node) | 0 (P-C1..P-C8 + MONT-002 nonce replay closure) |
| **M9 conformance suite** | ✅ **READY** | mt-conformance | ~150 | 2 unit byte-exact verify | 0 (envelope A1-A3 + PoW F1-F2 + IBT B1) |
| **M7 Fast Sync** | ✅ implemented | mt-sync, montana-node | — | snapshot request + chunk reassembly + anchor-root integrity verify | 0 (EXT-SYNC-01 anchor self-block closed) |
| **M8 Node binary** (montana-node production multi-node path) | ✅ consensus path hardened | montana-node | ~600 | three_peer multi-node e2e + state/quorum tests (cargo test --workspace green) | GPT-5 Codex 01 release-blockers closed: genesis hash-bound (EXT-GEN-02), deterministic 2τ₂ quorum (EXT-QRM-02), FastSync anchor (EXT-SYNC-01); DEV-013 closed |

**Audit firm engagement:** possible right now for the full scope **M1 + M2 + M3 + M4 + M5 + M6 + M9**. M7 Fast Sync + M8 production multi-node consensus path — GPT-5 Codex 01 release-blockers closed by construction; full cargo test --workspace green.

**iOS application audit:** see separate package `iOS/Apps/Montana/AUDIT.md` — Phase 2 in progress, requires Phase 2.1+ implementation (4-6 weeks) before external firm engagement.

---



---

## TL;DR — M6 Phase C closure (2026-05-02)

**mt-net-transport** (~470 LOC) — libp2p-based transport layer:
- `src/codec.rs` — MontanaCodec for libp2p request-response with MAX_PROTOCOL_PAYLOAD_BYTES enforcement (Genesis Decree authoritative bound)
- `src/behaviour.rs` — MontanaBehaviour wrapper (request-response for FastSync/PeerList/BatchLookup/RangeSubscribe; one-way gossip — Phase C.5+)
- `src/transport.rs` — build_swarm() helper with TCP → Noise_PQ XX (ML-KEM-768 + ML-DSA-65) → Yamux upgrade chain
- `src/ibt_upgrade.rs` — classify_proof() for access level determination (Node/Candidate/Account) with online_session_nonce + used_online_nonces replay tracking
- `tests/e2e_two_node_handshake.rs` — Manual Validation Gate scenario 6 PASS (Ping/Pong through full transport chain)
- `tests/e2e_proposal_exchange.rs` — scenario 7 PASS (synthetic Proposal payload + 512 KiB boundary test)

**mt-conformance** (~150 LOC) — M9 standalone test vectors crate for cross-implementation verification:
- VectorEnvelope (A1/A2/A3 byte-exact)
- VectorIbtSeed (B1 after P-C2 rename mt-tunnel→mt-tunnel-online; Network v1.1.0 adds online_session_nonce)
- VectorPow (F1/F2 target derivation)
- Public API: `all_envelope_vectors()`, `all_pow_vectors()`, `ibt_b1_online_proof()`

**Capability checklist [C-5] for libp2p 0.56.0:** 8/8 PASS. Components in the production auth and multiplex chain: TCP, `mt-noise-pq` Noise_PQ XX (`/montana/noise-pq-xx/1.0.0`), Yamux, Swarm primitives, `request_response`. Async runtime: tokio. Platform support: Linux, macOS, Windows. Adoption baseline: IPFS, Filecoin, Polkadot deployments at multi-year scale. License: MIT / Apache 2.0. Transitive dependency surface ≈120 crates, acceptable given isolation through the project's own `mt-net-transport` crate.

---

## 1. Audit Chain

Hybrid Rust + C architecture for cryptography (M1). Pure Rust for state foundation (M2). Three layers, each auditable independently.

### M1 — Foundational cryptography + identity recovery

#### Layer 1 — Rust shim (own audit responsibility)

| Crate | Path | Lines (exact) | Scope |
|-------|------|---------------|-------|
| `mt-codec` | [crates/mt-codec/src/lib.rs](crates/mt-codec/src/lib.rs) | ~290 | Canonical encoding traits + Domain separators registry (32 domains, byte-exact sync with current spec target per VERSION.md). All consensus hash compositions through explicit domain separator + NUL byte (`SHA-256(domain ‖ 0x00 ‖ parts)` self-delimiting per P1 external finding). |
| `mt-crypto` | [crates/mt-crypto/src/lib.rs](crates/mt-crypto/src/lib.rs) | **662** | Public API: `PublicKey`, `SecretKey`, `Signature`, `Mlkem*`, `keypair_from_seed`, `keypair_from_seed_mlkem`, `sign`, `verify`, `hash`, `sha256_raw`. `CryptoError` enum + `Result<_, CryptoError>` API. **Heap-allocated SK via `Box<[u8; N]>` + `mlock` against swap-out + `Drop+zeroize`** for secret types. All **7** `unsafe` blocks have `// SAFETY:` comments: 4 FFI sites (`keypair_from_seed`, `sign`, `verify`, `keypair_from_seed_mlkem`) + 3 mlock/munlock (`Drop for SecretKey`, `alloc_locked_secret_box`, `Drop for MlkemSecretKey`). Test-only `keypair()` via OS CSPRNG (`getrandom`). |
| `mt-crypto-native` (Rust binding) | [crates/mt-crypto-native/src/lib.rs](crates/mt-crypto-native/src/lib.rs) | 49 | `extern "C"` FFI declarations to Layer 2. Only `pub const` constants and FFI signatures, no logic. Includes `mt_sign_mldsa_ctx` for FIPS context support. |
| `mt-mnemonic` | [crates/mt-mnemonic/src](crates/mt-mnemonic/src) | 937 | 24-word mnemonic recovery flow: PBKDF2-HMAC-SHA-256 (iter=2²⁰), HKDF-Expand per-role derivation, ML-DSA seed (32B) + ML-KEM seed (64B) generation. Wordlist binding SHA-256 verified. |

#### Layer 2 — Own thin C wrapper (own audit responsibility)

| File | Lines (exact) | Scope |
|------|---------------|-------|
| [crates/mt-crypto-native/csrc/mt_crypto.c](crates/mt-crypto-native/csrc/mt_crypto.c) | 457 | Wrapping OpenSSL EVP_PKEY API: `mt_keypair_from_seed_mldsa`, `mt_keypair_from_seed_mlkem`, `mt_sign_mldsa`, `mt_sign_mldsa_ctx` (FIPS context support), `mt_verify_mldsa`, `mt_self_test`. Uses `OSSL_PKEY_PARAM_ML_DSA_SEED` (FIPS 204 §3.1 ξ ∈ B³²) and `OSSL_PKEY_PARAM_ML_KEM_SEED` (FIPS 203 §6.1 d ‖ z, 64B) for deterministic KeyGen. `OSSL_SIGNATURE_PARAM_DETERMINISTIC=1` for FIPS 204 Algorithm 2 deterministic Sign. |
| [crates/mt-crypto-native/csrc/mt_crypto.h](crates/mt-crypto-native/csrc/mt_crypto.h) | 67 | C API declarations + primitive sizes + 13 status codes (1 success + 12 errors). |
| [crates/mt-crypto-native/build.rs](crates/mt-crypto-native/build.rs) | 45 | Vendored OpenSSL build via `openssl-src`, `cc::Build` with `-Wall -Wextra -Wpedantic -Werror`, cross-compile correctness via `CARGO_CFG_TARGET_OS`. |

**Total own audit surface (Layer 1 + Layer 2): 1280 lines** (662 Rust shim + 49 FFI bindings + 457 C wrapper + 67 C header + 45 build script). Verify counts:
```
cd "<repo-root>" && wc -l crates/mt-crypto/src/lib.rs crates/mt-crypto-native/src/lib.rs crates/mt-crypto-native/csrc/mt_crypto.c crates/mt-crypto-native/csrc/mt_crypto.h crates/mt-crypto-native/build.rs
```

#### Layer 3 — Underlying production C library (vendor audit responsibility)

| Component | Version | Source | Audit history |
|-----------|---------|--------|---------------|
| OpenSSL | 3.5.5 LTS | [openssl-src 300.5.5+3.5.5](https://crates.io/crates/openssl-src) — vendored, byte-pinned exact version | OpenSSL Foundation governance, FIPS 140-3 validated, decades of production deployment in the TLS world (Apache HTTP, nginx, OpenSSH, Linux kernel, …), supported until **April 2030** (LTS) |

**Layer 3 is NOT in our audit scope** — the auditor reviews only our use of the OpenSSL EVP API (Layer 2), not the implementations of ML-DSA / ML-KEM / SHA-256 themselves.

### M2 — State foundation (audit-ready 2026-04-26)

| Crate | Path | Lines | Scope | Audit findings |
|-------|------|-------|-------|----------------|
| `mt-merkle` | [crates/mt-merkle/src/lib.rs](crates/mt-merkle/src/lib.rs) | 474 | Sparse Merkle Tree (depth 256), `empty_internal()` precomputed cache (OnceLock), `leaf_hash` / `internal_hash` (SHA-256 domain-separated via mt-codec::domain), `SparseMerkleTree::insert/root` via `BTreeMap` for canonical iteration order, `verify_proof` for inclusion and absence proofs. **0 unsafe blocks. 0 panic!. 0 f32/f64. 0 SystemTime/RNG. BTreeMap, not HashMap.** | Pass 1-12 clean (manual scan); 10 automated determinism invariants |
| `mt-genesis` | [crates/mt-genesis/src/lib.rs](crates/mt-genesis/src/lib.rs) | **353** | Genesis Decree + `ProtocolParams` SSOT (198B encoded, empty window 0), `genesis_app_id()` (SHA-256 domain-separated), `genesis_params()` via `OnceLock` (singleton, thread-safe), `compute_genesis_state_hash()`. Const `emission_moneta = 13 × 10⁹ nɈ` per spec v34+. **0 unsafe. 0 panic. Read-only constants + deterministic hash only.** | Pass 1-12 clean; automated determinism invariants |
| `mt-state` | [crates/mt-state/src/lib.rs](crates/mt-state/src/lib.rs) | **647** | AccountTable (2059B records) / NodeTable (2098B) / CandidatePool (2082B) via `BTreeMap<id, Record>` + `SparseMerkleTree`, `derive_account_id` / `derive_node_id` (SHA-256 domain-separated), `compute_state_root` (SHA-256 of node_root ‖ candidate_root ‖ account_root), `is_active` predicate. **0 unsafe. 0 panic! 0 HashMap (BTreeMap canonical sort). 0 f64.** | Pass 1-12 clean; automated determinism invariants |
| `mt-timechain` | [crates/mt-timechain/src/lib.rs](crates/mt-timechain/src/lib.rs) | 347 | TimeChain SSHA (`ssha_step` = SHA-256^d, `ssha_verify` re-computes), `next_d` Adaptive D via participation-ratio feedback (integer permille per [I-9]), `cemented_bundle_aggregate(W, node_ids)` per [I-8] Network-Bound Unpredictability (3 branches: genesis 0×32, empty marker, sorted node_ids hash). **0 unsafe. 0 panic. 0 HashMap. 0 f64. All integer arithmetic per [I-9].** | Pass 1-12 clean; 19 automated determinism invariants |

**Total M2 audit surface:** 1821 lines code + 60 automated determinism invariants.

### M3 — apply_proposal layer (audit-ready 2026-04-27)

| Crate | Path | Lines | Scope | Audit findings |
|-------|------|-------|-------|----------------|
| `mt-account` | [crates/mt-account/src/lib.rs](crates/mt-account/src/lib.rs) | **2556** | 4 user opcodes (`Transfer 0x02` / `ChangeKey 0x03` / `Anchor 0x04` / `TransferActivation 0x0A`) with byte-exact canonical encoding (TRANSFER_SIZE / CHANGE_KEY_SIZE / ANCHOR_SIZE / TRANSFER_ACTIVATION_SIZE). `validate_*` for each opcode (full validation per spec table). `apply_*` with **checked arithmetic** (`checked_sub` / `checked_add` + descriptive panic for protocol-invariant breach). `op_hash` via R2 SHA-256(`mt-op` ‖ signed_scope), signature excluded. `settle_window(cemented_ops)` sorts by `op_hash` lex asc. `apply_proposal` orchestrates Steps 2 / 3.5 / 3.6 / 4 (steps 1, 3a, 3b stubbed → M4 mt-entry). `apply_emission` credits `EMISSION_moneta` (const) to the winner node's operator. `reward_moneta(params) = params.emission_moneta`, `supply_moneta(W) = emission × W` closed-form. `build_genesis_state` + `genesis_state_root` for bootstrap. **0 unsafe. 0 panic! without `protocol invariant` justification. 0 HashMap. 0 f64. 0 SystemTime.** | Pass 1-12 clean; automated determinism invariants |

**Total M3 audit surface:** 2556 lines code + 29 automated determinism invariants.

### M4 — Consensus mechanics (audit-ready 2026-04-27)

| Crate | Path | Lines | Scope | Audit findings |
|-------|------|-------|-------|----------------|
| `mt-lottery` | [crates/mt-lottery/src/lib.rs](crates/mt-lottery/src/lib.rs) | **1715** | BundledConfirmation R1 / R2 (signed_scope + bundle_hash via `mt-bundle` domain), SshaReveal R1 / R2 (`mt-ssha-reveal` domain), `compute_endpoint` lottery formula (`mt-lottery` domain) with [I-8] cemented_bundle_aggregate(W-2) binding, validate_bundle / validate_reveal with full structural + signature verification, `log2_q64` (Q64.64 fixed-point integer log with degree-3 Remez minimax polynomial, max error 2^-10.62, binding coefficients B0..B3), `ln_q64`, `weighted_ticket_node` u128 integer division, `determine_winner` argmin canonical rule (ticket asc, class asc, id lex asc), `quorum` 67% ceiling integer formula `(67×X+99)/100`, `is_cemented`. **0 unsafe. 0 panic!. 2 controlled `expect()` (try_into on a slice of length 16 — protocol invariant). 0 HashMap. 0 f64. 0 SystemTime.** | M4-1 closure (Vec.len() as u16 silent truncation → BundleError::TooManyOps/TooManyReveals + validate cap + debug_assert defense-in-depth); 34 automated determinism invariants |
| `mt-consensus` | [crates/mt-consensus/src/lib.rs](crates/mt-consensus/src/lib.rs) | **1089** | ProposalHeader R1 / R2 (3722 B fixed-size, 17 fields, signed_scope without signature, `mt-proposal` domain), validate_header (a-f structural rules: fallback_depth ≥ 1, window_index = prev+1, protocol_version monotone + ≤ local_max, proposer registered + Mldsa65 suite, signature verify), canonical_proposer / fallback_proposer (Lookback Leadership: proposer_W = winner_{W-2}; genesis bootstrap; cascade by depth), compute_control_set (filter cemented_window > prev AND ≤ W, sort by (window asc, op_hash lex asc)), validate_proposer_is_canonical / validate_bundles_threshold / validate_included_reveals / validate_winner (Canonical acceptance), finalization_status (Cemented/Rejected per is_cemented), leader_penalty_excluded_node. **0 unsafe. 0 panic. 0 prod unwrap/expect. 0 HashMap. 0 f64. 0 SystemTime.** | Pass 1-12 clean (manual scan); 27 automated determinism invariants |
| `mt-entry` | [crates/mt-entry/src/lib.rs](crates/mt-entry/src/lib.rs) | **1054** | NodeRegistration R1 / R2 (5344 B, opcode 0x11, `mt-nodereg` domain), validate_noderegistration (3 structural rules: suite supported, signature verify, node_id unique in Node Table + Candidate Pool, operator account exists + not is_node_operator), `candidate_ssha_init` per [I-8] (`mt-candidate-ssha-init` domain composing T_r + cba(W-2) + node_id), `compute_expiry_window` 3τ₂, `apply_candidate_expiry` (apply_proposal Step 3a), selection_slots (1% cap via ADMISSION_DIVISOR=130), `selection_sort_key` (`mt-selection` domain), rank_candidates_for_selection (canonical sort), `apply_selection_event` (apply_proposal Step 3b: insert into Node Table + mark operator + remove from Candidate Pool), `required_ssha_length` (Adaptive SSHA integer permille per [I-9]), `nr_sort_key` (`mt-nodereg-sort` domain), `apply_noderegistrations_batch` (apply_proposal Step 1: incremental sort + apply with pending growth). **0 unsafe. 0 panic. 0 prod unwrap/expect. 0 HashMap. 0 f64.** | Pass 1-12 clean; 24 automated determinism invariants |

**Total M4 audit surface:** 3858 lines of code + 85 automated determinism invariants. Domain separators: `mt-bundle`, `mt-ssha-reveal`, `mt-lottery`, `mt-proposal`, `mt-nodereg`, `mt-candidate-ssha-init`, `mt-selection`, `mt-nodereg-sort` — all consensus-critical hash compositions go through canonical domains (per [I-8] + [I-10] SSOT).

### M5 — Persistence (audit-ready 2026-04-27)

| Crate | Path | Lines | Scope | Audit findings |
|-------|------|-------|-------|----------------|
| `mt-store` | [crates/mt-store/src/lib.rs](crates/mt-store/src/lib.rs) | **955** | Filesystem-backed state persistence (pure std::fs, no RocksDB / sled — minimum deps): `FsStore::open` (creates the `proposals/` subdirectory), save / load AccountTable / NodeTable / CandidatePool via canonical_encode / decode pair (round-trip byte-exact verified), Proposal archive (`proposals/{window:020}.bin`, `archive_proposal` + `get_proposal_by_window` byte-exact decode), Crash recovery (`meta_last_cemented.bin` u64 LE; `verify_consistency` checks that the meta-pointed proposal exists in the archive — otherwise StoreError::NotFound), Pruning (`prune_proposals_before` deletes files with window < threshold). All decode_X functions check `bytes.len() != EXPECTED_SIZE` before reading (StoreError::CorruptedLength). **0 unsafe. 0 panic. 0 prod unwrap/expect. 0 HashMap. 0 f64.** | Pass 1-12 clean; automated determinism invariants |

**Total M5 audit surface:** 955 lines code + 17 automated determinism invariants.

**M3 + M4 + M5 orchestration ordering** (important for the caller):
1. M3: `settle_window(account_table, cemented_user_ops, window_w)` — apply cemented user ops to state
2. M4: `apply_noderegistrations_batch` (Step 1) → `apply_candidate_expiry` (Step 3a) → `apply_selection_event` (Step 3b) — node admission flow
3. M3: `apply_proposal(account_table, node_table, candidate_pool, input, params)` — Steps 2 (emission) → 3.5 (chain_length++) → 3.6 (checkpoint rotation) → 4 (state_root)
4. M5: `archive_proposal(header)` → `save_meta_last_cemented(window)` → `save_account_table` / `save_node_table` / `save_candidate_pool` — persist to disk

Settle is separated from apply_proposal (M3 design choice); steps 1 / 3a / 3b are delegated to M4 mt-entry. M5 finalization atomicity is achieved through the meta-pointer pattern (if a crash happens between archive and meta — verify_consistency detects it).

**M3 apply_proposal orchestration ordering** (important invariant for the caller):
1. `settle_window(account_table, cemented_user_ops, window_w)` — apply cemented ops to state (Transfer / Anchor / ChangeKey / TransferActivation) **before** apply_proposal
2. `apply_proposal(account_table, node_table, candidate_pool, input, params)` — Steps 2 (emission) → 3.5 (chain_length++) → 3.6 (checkpoint rotation) → 4 (state_root)

Settle is separated from apply_proposal by design — the orchestration-ordering invariant is visible to the caller explicitly; hiding it inside one function risks a silent fork. Documented in the module-level comment above `pub fn apply_proposal`.

---

## 2. Conformance Proofs

### NIST FIPS 204/203 byte-exact conformance (M1)

**66 differential test cases** vs NIST CAVP ACVP-Server published vectors:

| Test | Source | Cases | Status |
|------|--------|-------|--------|
| ML-DSA-65 KeyGen byte-exact | [NIST ACVP-Server](https://github.com/usnistgov/ACVP-Server) `gen-val/json-files/ML-DSA-keyGen-FIPS204` | 25 | ✅ PASS |
| ML-KEM-768 KeyGen byte-exact | [NIST ACVP-Server](https://github.com/usnistgov/ACVP-Server) `gen-val/json-files/ML-KEM-keyGen-FIPS203` | 25 | ✅ PASS |
| ML-DSA-65 SigGen deterministic external pure (1 empty + 14 non-empty context, 0..255B) | [NIST ACVP-Server](https://github.com/usnistgov/ACVP-Server) `gen-val/json-files/ML-DSA-sigGen-FIPS204` tgId=3 | **15** | ✅ PASS |
| `mt_sign_mldsa` ≡ `mt_sign_mldsa_ctx` (empty ctx) equivalence | own correctness check | 1 | ✅ PASS |

**Reproduction:**
```
cd "<repo-root>" && cargo test -p mt-crypto-native --test nist_acvp_kat -- --nocapture
```

**Fixtures location:** [crates/mt-crypto-native/tests/fixtures/nist_acvp/](crates/mt-crypto-native/tests/fixtures/nist_acvp/)

### SHA-256 NIST FIPS 180-4 conformance (M1)

| Test | Source | Status |
|------|--------|--------|
| SHA-256("abc") == ba7816bf...15ad | FIPS 180-4 §B.1 | ✅ PASS (in `mt-crypto/src/lib.rs::tests::hash_nist_vector_abc`) |

### Internal correctness baselines (M1)

| Test | Path | Status |
|------|------|--------|
| ML-DSA-65 zero-seed deterministic baseline | [crates/mt-crypto-native/tests/regression_baselines.rs](crates/mt-crypto-native/tests/regression_baselines.rs) | ✅ PASS |
| ML-KEM-768 zero-seed + ones-seed deterministic baselines | same | ✅ PASS |
| ML-DSA-65 sign roundtrip + tamper detection | same | ✅ PASS |
| 5 mt-mnemonic KAT vectors (entropy → mnemonic → master_seed → per-role keypair) | [crates/mt-mnemonic/tests/keygen_vectors.rs](crates/mt-mnemonic/tests/keygen_vectors.rs) | ✅ PASS |
| End-to-end recovery flow (entropy → identity round-trip) | [crates/mt-mnemonic/tests/e2e_recovery.rs](crates/mt-mnemonic/tests/e2e_recovery.rs) | ✅ PASS |
| `mt_crypto::self_test()` (KeyGen determinism + Sign/Verify + KAT 1 byte-exact conformance check) | [crates/mt-crypto/src/lib.rs](crates/mt-crypto/src/lib.rs) | ✅ PASS |

### Security invariants (M1, Pass 17 enforcement via automated tests)

Regression detection for security-critical properties — if a future refactor breaks an invariant, the test fails in CI before merge.

| Invariant | Test | Status |
|-----------|------|--------|
| `SecretKey: !Clone` (no accidental copies) | [crates/mt-crypto/tests/security_invariants.rs](crates/mt-crypto/tests/security_invariants.rs)::secret_key_is_not_clone | ✅ |
| `MlkemSecretKey: !Clone` | same::mlkem_secret_key_is_not_clone | ✅ |
| `SecretKey: !PartialEq` (no timing leak via ==) | same::secret_key_no_partial_eq_to_prevent_timing_leak | ✅ |
| `MlkemSecretKey: !PartialEq` | same::mlkem_secret_key_no_partial_eq_to_prevent_timing_leak | ✅ |
| `SecretKey` heap-allocated (size = pointer) | same::secret_key_is_heap_allocated | ✅ |
| `MlkemSecretKey` heap-allocated | same::mlkem_secret_key_is_heap_allocated | ✅ |
| `SecretKey` has a Drop impl | same::secret_key_needs_drop | ✅ |
| `MlkemSecretKey` has a Drop impl | same::mlkem_secret_key_needs_drop | ✅ |
| FFI fills SK with non-zero bytes | same::secret_key_filled_by_ffi_keygen | ✅ |
| FFI fills MlkemSK with non-zero bytes | same::mlkem_secret_key_filled_by_ffi_keygen | ✅ |
| No `println!` / `log::*` macros on SK bytes in lib code | same::no_println_or_log_on_secret_bytes_in_lib_code | ✅ |
| `PublicKey: Clone` (sanity — public material clone-able) | same::public_key_can_be_cloned | ✅ |
| `Signature: Clone` (sanity) | same::signature_can_be_cloned | ✅ |

**13/13 security invariants PASS.**

### Determinism invariants (M2 — all 4 crates)

Automated regression detection per [I-3] determinism + [I-9] integer arithmetic + [I-10] SSOT + [I-8] Network-Bound Unpredictability.

| Crate | Test file | Cases | Status |
|-------|-----------|-------|--------|
| `mt-merkle` | [tests/determinism_invariants.rs](crates/mt-merkle/tests/determinism_invariants.rs) | 10 | ✅ PASS (empty_internal determinism + level uniqueness, leaf/internal hash determinism, internal_hash order-sensitivity, SMT empty root + insertion-order-independent root, root-changes-on-insert, type sizes) |
| `mt-genesis` | [tests/determinism_invariants.rs](crates/mt-genesis/tests/determinism_invariants.rs) | 7 | ✅ PASS (genesis_app_id determinism, genesis_params singleton stable pointer, ProtocolParams encoded size constant + encoding determinism, compute_genesis_state_hash determinism + dependence on state_root, SSOT singleton consistency) |
| `mt-state` | [tests/determinism_invariants.rs](crates/mt-state/tests/determinism_invariants.rs) | — | ✅ PASS (derive_account_id / derive_node_id determinism + dependence + cross-distinctness, ACCOUNT / NODE / CANDIDATE_RECORD_SIZE matches encoded, encoding determinism, AccountTable / NodeTable / CandidatePool insertion-order-independent root, compute_state_root determinism + order-sensitivity + dependence on each input root, is_active boundary at 2×τ₂ inclusive + saturating_sub safety, WINNER_CLASS_NODE SSOT, empty tables consistent root, insert / remove inverse) |
| `mt-timechain` | [tests/determinism_invariants.rs](crates/mt-timechain/tests/determinism_invariants.rs) | 19 | ✅ PASS (ssha_step zero=identity + determinism + dependence on iterations and prev, ssha_verify accept/reject correct/wrong claim/iteration count, ssha_chain composition associative, next_d dead-zone unchanged + above-high-increases + below-low-decreases + determinism, cemented_bundle_aggregate window<2 = genesis zero, empty marker distinct from non-empty, change-on-window / node_ids, **canonical sort input-order independence per [I-8]**) |

**60/60 M2 invariants PASS.**

### Spec ↔ Code byte-exact alignment (M0+M1+M2)

Verified per critic audit (commit `9387900`):

| Check | Spec value | Code value | Status |
|----------|-----------|-----------|--------|
| ML-DSA-65 pubkey size | 1952B | `PUBLIC_KEY_SIZE = 1952` | ✅ |
| ML-DSA-65 secretkey | 4032B | `SECRET_KEY_SIZE = 4032` | ✅ |
| ML-DSA-65 signature | 3309B | `SIGNATURE_SIZE = 3309` | ✅ |
| ML-DSA-65 seed | 32B | `KEYPAIR_SEED_SIZE = 32` | ✅ |
| ML-KEM-768 ek | 1184B | `MLKEM_PUBLIC_KEY_SIZE = 1184` | ✅ |
| ML-KEM-768 dk | 2400B | `MLKEM_SECRET_KEY_SIZE = 2400` | ✅ |
| ML-KEM-768 seed | 64B (d‖z) | `MLKEM_SEED_SIZE = 64` | ✅ |
| AccountRecord size | 2059B | `ACCOUNT_RECORD_SIZE = 2059` | ✅ |
| NodeRecord size | 2098B | `NODE_RECORD_SIZE = 2098` | ✅ |
| CandidateRecord size | 2082B | `CANDIDATE_RECORD_SIZE = 2082` | ✅ |
| ProposalHeader size | 3722B | `PROPOSAL_HEADER_SIZE = 3722` | ✅ |
| ProtocolParams size | 198B (empty window 0; no baked bootstrap operator / N_SEED / PoW) | `PARAMS_ENCODED_SIZE = 198` | ✅ |
| Sparse Merkle Tree depth | 256 | `TREE_DEPTH = 256` | ✅ |
| Emission pin | 13 Ɉ const per window | `emission_moneta = 13_000_000_000` | ✅ |
| Domain registry sync (32 domains) | spec list | code mt-codec const list | ✅ |

### Security Cards per crypto primitive (M1)

Each primitive with secret material has a detailed Security Card in [docs/security-cards.md](docs/security-cards.md). Cards covered:

| Primitive | Card | Status |
|-----------|------|--------|
| `SecretKey` (ML-DSA-65) | Card 1 — 8/8 Pass 17 checks closed | ✅ closed |
| `MlkemSecretKey` (ML-KEM-768) | Card 2 — 8/8 closed | ✅ closed |
| `keypair_from_seed` (ML-DSA KeyGen) | Card 3 — heap+mlock+stack hygiene closed | ✅ closed |
| `keypair_from_seed_mlkem` (ML-KEM KeyGen) | Card 4 — heap+mlock+stack hygiene closed | ✅ closed |
| `sign` (ML-DSA-65 deterministic) | Card 5 — 8/8 closed | ✅ closed |
| `verify` (ML-DSA-65) | Card 6 — no secret material, minimal card | ✅ closed |

---

## 3. Threat Model & Scope Boundaries

### In scope — what the auditor should review

**M1 — cryptography + identity:**
1. **FFI memory safety** — Layer 1 `unsafe` blocks (4 sites), buffer sizes, pointer validity
2. **OpenSSL EVP API misuse** — EVP_PKEY_CTX_set_params parameters, error handling, EVP_DigestSignInit determinism flag
3. **Secret hygiene** — `Drop + zeroize` for `SecretKey` / `MlkemSecretKey`, no `Clone` / `Copy` on secret types, no leakage in logs / dumps, **heap-allocated bytes (Box) with mlock** against swap-out, **stack hygiene** — FFI writes directly into a heap-allocated locked Box, with no stack temporary buffers holding secret bytes (see [docs/security-cards.md](docs/security-cards.md) Cards 1-6)
4. **Result API correctness** — `sign` / `keypair_from_seed` corruption resistance: malformed SK via `from_array(arbitrary_bytes)` → `Err(CryptoError::InvalidSecretKey)`, not a panic
5. **Deterministic semantics** — FIPS 204 Algorithm 2 deterministic Sign correctly invoked via `OSSL_SIGNATURE_PARAM_DETERMINISTIC=1` (consensus determinism per Montana [I-3])
6. **Recovery flow correctness** — mnemonic → master_seed (PBKDF2-HMAC-SHA-256) → per-role HKDF derivation → byte-exact reproducible identity (Montana spec sections "Keys → Mnemonic and seed", "Per-role key derivation")
7. **Cross-compile correctness** — build.rs uses the `CARGO_CFG_TARGET_OS` env var (not `cfg!(target_os)`)
8. **Reproducible builds** — Docker container with pinned base image (`debian:bookworm-slim@sha256:40b107342c492725bc7aacbe93a49945445191ae364184a6d24fedb28172f6f7`), byte-identical across independent runs (CI gate `reproducible_release`)

**M2 — state foundation:**
9. **Sparse Merkle Tree correctness** — empty_internal level uniqueness + cache consistency + verify_proof for inclusion and absence proofs
10. **Genesis Decree SSOT** — ProtocolParams singleton consistency, encoded size invariance under struct changes, frozen constants
11. **State table determinism** — BTreeMap canonical sort guarantee for AccountTable / NodeTable / CandidatePool, insertion-order-independent state_root
12. **Account / Node ID derivation** — SHA-256 domain-separated via mt-codec::ACCOUNT / ::NODE registry, cross-distinctness for the same pubkey
13. **Monetary policy correctness** — const emission `reward_moneta = EMISSION_moneta = 13 × 10⁹ nɈ` per spec «Emission», closed-form `supply_moneta(W) = EMISSION_moneta × W`
14. **TimeChain SSHA correctness** — ssha_step composition associativity, ssha_verify byte-exact against re-computed chain
15. **Adaptive D feedback** — next_d dead-zone semantics + integer permille arithmetic per [I-9]
16. **cemented_bundle_aggregate per [I-8]** — Network-Bound Unpredictability via canonical sort over node_ids + window binding, protection against input-order grinding

### Out of scope — NOT subject of this audit

1. **OpenSSL internal correctness** — out of scope; OpenSSL Foundation's responsibility. The auditor may assume the OpenSSL implementations of FIPS 204 / 203 Algorithms 1 / 2 / 16 are correct (audited and deployed at scale)
2. **Consensus protocol correctness M3-M5** — separate layers (mt-account, mt-consensus, mt-lottery, mt-entry, mt-store) — internal-tested with 255+ tests green, but not yet audit-prepared (TODO for subsequent audit phases)
3. **Network protocol** — M6+ (mt-net does not yet exist)
4. **Application layer** — a separate workspace in the future (Junona agent, messaging, file storage)
5. **Hardware side-channel attacks** — software-only assumption; embedded-deployment audit is separate

### Known limitations (deferred, with rationale)

0. **Genesis bootstrap ceremony pending** (M2-1 finding from external audit Claude Opus 4.7 #2) — 4 `ProtocolParams` fields hold placeholder zeros and are finalized only during the Genesis ceremony before mainnet:
   - `bootstrap_account_pubkey: [0u8; PUBLIC_KEY_SIZE]`
   - `bootstrap_node_pubkey: [0u8; PUBLIC_KEY_SIZE]`
   - `target_zero: [0u8; 32]` (initial SSHA target)
   - `genesis_content_data_hash: [0u8; 32]`

   **Severity:** mainnet blocker, **NOT a code-audit blocker**. Layout / encoding / SSOT / singleton are correct and audit-ready. Finalization = choosing seeds, generating keypairs via `mt_crypto::keypair_from_seed`, secure privkey storage (multi-party ceremony or a single trusted party — author's design decision).

   **Programmatic check:** `mt_genesis::is_genesis_bootstrap_finalized(params) -> bool` for operator deployment scripts. The `bootstrap_keypairs_finalized` test stays `#[ignore]` until the ceremony; the ignore is removed after the ceremony. The pre-ceremony test `is_genesis_bootstrap_finalized_pre_ceremony_returns_false` explicitly captures the current state.

   **Closure path:** Genesis ceremony plan — a separate milestone in `ROADMAP.md` before mainnet.

1. **Sign with non-empty context** — the current `mt_sign_mldsa` API does not accept a context parameter and uses an empty context (matches Montana's usage pattern but not the full FIPS 204 API surface). NIST ACVP cases with context bytes (14 / 15 in the external-pure deterministic group) are not exercised. Closure path: extend the FFI signature when FIPS context support is needed (M6+).

2. **Verify NIST KAT** — a dedicated test set for FIPS 204 SigVer has not been added in this session (sign-baseline + sign-NIST KAT byte-exact match indirectly confirms Verify correctness via round-trip, but a direct Verify NIST KAT remains as an enhancement).

3. **ML-KEM-768 Encapsulate/Decapsulate NIST KAT** — the current M1-F scope covers KeyGen only (Encapsulate/Decapsulate will be needed in M6+ application-layer encryption). NIST KAT for encapDecap is already present in the fixtures dir; tests are added when needed.

---

## 4. Build & Reproduction

### Toolchain

```
rustc 1.70+ (pinned via rust-toolchain.toml)
Cargo workspace
OpenSSL 3.5.5 LTS (vendored via openssl-src)
```

### Optional security audit tooling (for Step H verification)

```
cargo install cargo-audit --locked
```

Once per audit machine. After that, the `cargo audit` command is available.

### Build from source

```
cd "<repo-root>"
cargo build --all --release
```

All 4 mandatory CI checks:
```
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test --all
cargo build --all --release
```

### Reproducible release build (Docker)

**Prerequisites:** Docker ≥ 20.10 installed and running, ~30 minutes wall-clock for two clean builds, ~5 GB free disk.

```
docker build --file docker/release-build.dockerfile --tag montana-release:audit .
```

CI gate `reproducible_release` (see .github/workflows/ci.yml) performs two independent builds with `--no-cache` and asserts byte-identical hashes on every push to main. The auditor can verify via CI history without running locally (avoiding the Docker prerequisite).

### Run audit-relevant tests

**M1 NIST ACVP KAT (cross-implementation conformance):**
```
cd "<repo-root>" && cargo test -p mt-crypto-native --test nist_acvp_kat -- --nocapture
```

**M1 Internal correctness baselines:**
```
cd "<repo-root>" && cargo test -p mt-crypto-native --test kat_independent -- --nocapture
cd "<repo-root>" && cargo test -p mt-crypto -- --nocapture
cd "<repo-root>" && cargo test -p mt-mnemonic --test keygen_vectors -- --nocapture
cd "<repo-root>" && cargo test -p mt-mnemonic --test e2e_recovery -- --nocapture
```

**M1 Security invariants (Pass 17):**
```
cd "<repo-root>" && cargo test -p mt-crypto --test security_invariants -- --nocapture
```

**M2 Determinism invariants:**
```
cd "<repo-root>" && cargo test -p mt-merkle --test determinism_invariants -- --nocapture
cd "<repo-root>" && cargo test -p mt-genesis --test determinism_invariants -- --nocapture
cd "<repo-root>" && cargo test -p mt-state --test determinism_invariants -- --nocapture
cd "<repo-root>" && cargo test -p mt-timechain --test determinism_invariants -- --nocapture
```

**Full M1+M2 audit chain:**
```
cd "<repo-root>" && cargo test -p mt-codec -p mt-crypto-native -p mt-crypto -p mt-mnemonic -p mt-merkle -p mt-genesis -p mt-state -p mt-timechain
```

---

## 5. Audit History

| Date | Audit | Findings | Closure |
|------|-------|----------|---------|
| 2026-06-18 | **External re-audit GPT-5 Codex 02** — re-audit of the Codex 01 fixes (monetary, deps, FastSync, release docs, legacy Noise, conformance gate) | 6 findings (2 High, 3 Medium, 1 Low/Medium) | **All resolved.** REAUDIT-01 supply_moneta closed-form to EMISSION × W + spec self-consistency (line 2835) + DEV-027 closed; REAUDIT-02 dropped libp2p tls/noise, tokio 1.40→1.44.2, cargo-audit gate (.cargo/audit.toml, exit 0); REAUDIT-03 FastSync peer-head exact-anchor binding (single-anchor-per-session, recent_roots[anchor] byte-exact), Network spec bumped v1.3.1 → v1.4.0, DEV-044; REAUDIT-04 VERSION/AUDIT/scripts reconciled to singleton (n_seed=0, PARAMS 4108); REAUDIT-05 legacy XK Noise libp2p path #[deprecated] + non-production docs; REAUDIT-06 conformance-gate +6 behavioral oracle rows (monetary, active predicate, FastSync anchor, transport hygiene, audit gate, genesis consistency), GREEN 39/39. cargo test + fmt + clippy green. |
| 2026-06-17 | **External audit GPT-5 Codex 01** — delta audit (Genesis Decree, quorum/active predicate, FastSync, emission, VPN, FFI, transport) | 13 findings (2 Critical, 4 High, 6 Medium, 1 known-residual) | **All resolved.** 10 closed by construction: EXT-GEN-01/02, EXT-QRM-01/02, EXT-SYNC-01, EXT-MON-01, EXT-FFI-01, EXT-TEST-01, EXT-DOC-01, EXT-NOISE-RESIDUAL. 3 VPN-layer findings (EXT-VPN-01/02/03) moot via removal of the VPN application layer. Spec to Protocol v35.26.2 + Network v1.3.1; conformance-gate GREEN 33/33; cargo test --workspace + fmt + clippy --all-targets green. |
| 2026-04-27 | **Spec bump v33.1.6 → v34.0.0** — major monetary policy refactor (geometric step-up baseline → const linear emission) | Architectural simplification, not security audit findings | ProtocolParams: 4 fields removed (`r_genesis_moneta`, `monetary_epoch_windows`, `inflation_num`, `inflation_den`) + `emission_moneta: u128 = 13×10⁹ nɈ` added. PARAMS_ENCODED_SIZE 4118 → 4094. mt-state: `MonetaryState` struct + carry-recurrence machinery removed. mt-account `apply_emission` simplified: `reward = params.emission_moneta` const, `monetary_epoch_tick` removed. `supply_moneta(W) = E × (W+1)` closed-form O(1) — eliminates a class of bugs (epoch boundary off-by-one, carry overflow). 288/288 affected tests PASS. Driver: simplifying the audit surface for production firm engagement. |
| 2026-04-27 | **External audit #4 Claude Opus 4.7 (1M context)** — incremental M4+M5 scope (mt-lottery, mt-consensus, mt-entry, mt-store) — independent SHA-256 oracle (Python hashlib) cross-check 4 hash compositions + ad-hoc ln_q64 mathematical verification (T141253) | 10 findings (0 CRITICAL/HIGH, 2 MEDIUM, 5 LOW, 3 INFO); score **8.5/10**; 325/325 M4+M5 tests PASS under single-core / single-process | **All 10 findings closed by construction.** Commits: `cb81d4c` M4-MED-1 window_index u32→u64 unification (spec v33.1.4→v33.1.5), `f46d48a` M4-LOW-7 3 hardcoded const → ProtocolParams [C-1] SSOT (spec v33.1.5→v33.1.6 + admission_divisor field), `64cefca` M4-MED-2 validate_winner genesis-aware contract docs, `53ba832` M4-LOW-3 log2_q64 panic-free byte extraction, `e8450bb` M4-LOW-4 checked_add validate_header window monotone, `c41f043` M4-LOW-5 saturating_mul quorum, `845d74d` M4-LOW-6 positive functional tests TooManyOps/TooManyReveals, `bcf5e9b` M5-LOW-8 cleanup orphan .tmp at FsStore::open + anti-regression test, `022c5ff` M4-INFO-10 canonical_proposer degraded-mode docs. |
| 2026-04-27 | **External audit #3 VERIFIED Claude Opus 4.7 (1M context)** — incremental M3 mt-account scope + full zero-trust verification of M1 / M2 closures + fresh NIST CAVP source download (T124438; supersedes incomplete first pass T121239 in which the auditor by their own admission cut corners). 785/785 cargo test --all PASS. | 10 findings: 8 from the incomplete first pass (1 HIGH M3-A-4, 3 LOW M3-A-1 / M3-A-2 / F-5, 4 INFO M3-A-3 / M3-A-5 / M3-A-7 / M3-A-8) + 2 from the VERIFIED pass (P-C-1 F-19 reopen HIGH, P-C-2 audit history sync MEDIUM). Score **8.5/10**; expected 9/10 after P-C-1 + P-C-2. | **All 10 findings closed by construction.** Commits: `4c14685` M3-A-4 ValidationContext, `047cc45` M3-A-1 + M3-A-2 checked arithmetic, `66df1a1` M3-A-5 + F-5 docs / telemetry TODO, `e61c479` M3-A-3 binding test vector, `5d3506c` Cargo.lock sync, `b96085d` P-C-1 SAFETY convention for 4 const-cast sites + Rust shim cross-references, `<this>` P-C-2 audit history sync. **131 tests PASS** in mt-account (96 unit + 35 determinism); 4 anti-regression tests (validate_dispatcher cooldown enforcement, apply_chain_length overflow panic, apply_checkpoint_rotation underflow panic, genesis_candidate_root binding `empty_internal(256)`). |
| 2026-04-26 | **External audit #2 Claude Opus 4.7 (1M context)** — incremental M2 scope (mt-merkle, mt-genesis, mt-state, mt-timechain) | 17 findings (1 HIGH M2-1 Genesis bootstrap pubkeys placeholder, 5 MEDIUM, 11 LOW/INFO); score **8/10**; 60/60 determinism invariants verified | M2-3 + M2-13 originally closed in the M3 milestone (binding test pin 41/40 + MonetaryState in compute_state_root). **Superseded** by spec bump v33.1.6 → v34.0.0 monetary policy refactor (geometric step-up → const linear emission): pin 41/40 inflation_num / den and the MonetaryState carry-recurrence removed as artifacts of the old policy. New equivalent invariants: `reward_moneta(W) = EMISSION_moneta` const closed-form, `supply_moneta(W) = EMISSION × (W+1)` linear closed-form. M2-1 re-classified as a known limitation (mainnet deployment blocker, not a code-audit blocker). The remaining documentation-only findings were closed in audit-package iterations. |
| 2026-04-26 | **External audit #1 Claude Opus 4.7 (1M context)** — initial M1 layer (mt-crypto, mt-crypto-native, mt-mnemonic) — independent NIST CAVP source download + byte-exact verification | 19 findings (3 HIGH + 4 MEDIUM + 12 LOW/INFO); score **8/10**; 0 cryptographic vulnerabilities | **14/19 closed by construction** (commit `6ff26b3` + closure completed in `b96085d` for F-19): F-2 cargo fmt clean, F-3 stale RustCrypto refs cleanup, F-4 SAFETY comments on 3 mlock / munlock blocks, F-5 expanded SAFETY comment, F-6 keypair() migrated to OS CSPRNG (`getrandom`), F-7 zeroize intermediate PBKDF2 / HKDF / HMAC buffers, F-8 SigGen NIST KAT expanded 1 → 15 cases with the new `mt_sign_mldsa_ctx` API, F-9 rename kat_independent → regression_baselines, F-12 split_whitespace instead of split(' '), F-18 cc parallel feature removed, F-19 const-cast OpenSSL convention in SAFETY (initially incomplete; fully closed in `b96085d` after the VERIFIED audit reopen). **5 deferred** with explicit rationale (F-10 NIST in self_test, F-14 formal constant-time, F-15 cargo-fuzz infrastructure, F-16 threshold sigs M6+, F-17 serde_json dev-dep — the auditor themselves marked these as "not a priority"). Expected score after closure: 9/10. |
| 2026-04-26 | M0+M1+M2 critic spec-vs-code audit (`Montana-Protocol/Code/CRITIC.md` v1.6.0) — verification of full M0 / M1 / M2 code conformance with spec v33.1.2 | 4 findings (F-1 mt-recovery-fingerprint domain spec drift, F-2 stale VERSION.md Implementation field, F-3 false positive withdrawn by the critic, F-4 controlled halts documentation) | All 4 closed (commit `9387900`): F-1 spec patch v33.1.2 → v33.1.3 (Domain registry sync), F-2 VERSION.md updated to «M0..M5 closed», F-4 audit-checklist §K Controlled halts section |
| 2026-04-26 | M1-F audit-package critic review (`Montana-Protocol/Code/CRITIC.md` v1.4.0) — verification of AUDIT.md + reproduction commands + claims accuracy | 5 findings (F-A1..F-A5) — all documentation-only, not security | All 5 closed: F-A1 unsafe count 3→4 (verify added in list), F-A2 cargo audit verified+install instructions, F-A3 line counts exact (568/40/375/56/45=1084), F-A4 print_sk gate accurately described (env var M1_DUMP_SK=1), F-A5 Docker reproduction prerequisites added |
| 2026-04-26 | M1-F internal critic audit (`Montana-Protocol/Code/CRITIC.md` v1.4.0) | 7 findings (F-1..F-7) | 6 closed by construction, F-3 closed via NIST ACVP differential testing — **all 7 closed**. Commits: `9f2ba93` (F-4 cross-compile), `71896f6` (F-6 separate error codes), `3333738` (F-1 zeroize), `e1164ad` (F-2 Result API + F-5 cfg-gate keypair + F-7 implicit), `6b7ff30` (F-3 NIST KAT) |
| 2026-04-26 | M2 batch 2+3 audit prep — manual critic Pass 1-12 for mt-state + mt-timechain | 0 findings (manual scan clean) | 24 + 19 automated determinism invariants added |
| 2026-04-26 | M2 batch 1 audit prep — manual critic Pass 1-12 for mt-merkle + mt-genesis | 0 findings (manual scan clean) | 10 + 7 automated determinism invariants added |
| 2026-04-21 | External critic finding — domain separation prefix-collision | 5 findings (P1-P5) | All closed: NUL separator pattern, SK leak gate, label coherence, empty_internal binding, stale RECOVERY disclosure. Commit `d762cec`, spec v29.13.0. |

**Audit-ready status (2026-04-27):** **zero open code-side findings** in M1 + M2 + M3 layers across **3 independent external audits** (T201805 + T232707 + T124438 by Claude Opus 4.7 1M; T124438 — VERIFIED replacement of the incomplete first-pass T121239). Total cumulative **46 findings** across audits — all code-side closed by construction; deferred items explicitly classified (M2-1 Genesis bootstrap pubkeys = mainnet deployment, not code audit; F-14 / F-15 formal verification + fuzzing = post-MVP scope). M3 score 8.5/10 → 9/10 ready after P-C-1 + P-C-2 closures (commits `b96085d` + this). Documentation accuracy verified through 3 incremental audits, including the VERIFIED zero-trust pass. Cross-implementation conformance verified through spec ↔ code byte-exact alignment + independent NIST CAVP source download (65 KAT cases byte-exact against a fresh source 2026-04-27).

---

## 6. Spec & Documentation

| Document | Path | Scope |
|----------|------|-------|
| Protocol spec | see `VERSION.md` (Spec target / Spec path) — authoritative source | Full protocol specification, source of truth |
| App spec | `Montana-Protocol/Montana App v3.9.2.md` (current at the time; see the VERSION.md history) | Application layer specification |
| Architect role | [CLAUDE.md](CLAUDE.md) | Code architect role definition (v1.12.0) |
| Critic role | [CRITIC.md](CRITIC.md) | Code critic role definition (v1.6.0 — Pass 17 Security Card mandatory) |
| Roadmap | [ROADMAP.md](ROADMAP.md) | Implementation roadmap, milestones, status |
| Spec version SSOT | [VERSION.md](VERSION.md) | Single source of truth for the spec target version |
| Pre-audit checklist | [docs/audit-checklist.md](docs/audit-checklist.md) | 11 categories of self-attestation (A-K) + reproduction one-liners for the auditor + sign-off table |
| Security Cards | [docs/security-cards.md](docs/security-cards.md) | Pass 17 mandatory Security Cards for 6 crypto primitives |

---

## 7. Pre-audit self-attestation

Before starting an external audit — see [docs/audit-checklist.md](docs/audit-checklist.md) for the full 11-category checklist.

**M1 + M2 final closure self-attestation (2026-04-26):**

**Findings closure:**
- [x] All 7 M1-F audit findings closed by construction (F-1..F-7)
- [x] All 5 audit-package findings closed (F-A1..F-A5)
- [x] All 4 M0+M1+M2 critic spec-vs-code findings closed (F-1..F-4)
- [x] **Total: 16/16 findings closed, 0 open blockers**

**Conformance:**
- [x] NIST ACVP differential testing PASS (51/51 KAT byte-exact)
- [x] Spec ↔ code byte-exact alignment verified (16 key constants / sizes table)
- [x] Domain registry sync (current spec target ↔ mt-codec, see VERSION.md)

**Security:**
- [x] 13/13 security invariants PASS (Pass 17 enforcement)
- [x] 6/6 Security Cards filled in and closed (`docs/security-cards.md`)
- [x] Heap+mlock+zeroize for secret types verified

**Determinism:**
- [x] 60/60 M2 determinism invariants PASS
- [x] 0 HashMap (real usage) in consensus path; BTreeMap canonical sort
- [x] 0 SystemTime / Instant::now / RNG in consensus path
- [x] 0 f32 / f64 in consensus path

**Build & CI:**
- [x] `cargo audit` clean (verified 2026-04-26: 0 vulnerabilities, 0 warnings, 39 deps)
- [x] `cargo fmt --all -- --check` clean
- [x] `cargo clippy --all-targets -- -D warnings` clean
- [x] `cargo test --all` 564+ PASS / 0 FAIL
- [x] `cargo build --all --release` clean
- [x] Reproducible builds verified through CI gate `reproducible_release`

**Documentation:**
- [x] Public API stable (mt-crypto types / signatures unchanged through M1-E + M1-F migrations)
- [x] Audit chain documented (Layer 1/2/3 explicit, exact line counts)
- [x] Threat model documented (in/out of scope explicit)
- [x] Known limitations documented with closure path
- [x] Reproduction commands verified working (each one tested 2026-04-26)
- [x] Documentation accuracy verified through critic review of audit package itself

---

## Contact

Audit findings, questions, reports — fork the repository, open a PR with patch + reproduction instructions.

Architect role + critic role files in the repository — peer-reviewable methodology.
