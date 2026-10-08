# Pre-audit self-attestation checklist — M1+M2+M3+M4+M5+M6+M9 layers

Completed by the architect before every external audit engagement. Every item must be `[x]` or carry an explicit justification for why it is `[ ]`.

---

## A. Conformance proofs

- [x] **NIST FIPS 204 ML-DSA-65 KeyGen byte-exact** vs ACVP-Server published vectors (25 cases)
- [x] **NIST FIPS 203 ML-KEM-768 KeyGen byte-exact** vs ACVP-Server published vectors (25 cases)
- [x] **NIST FIPS 204 ML-DSA-65 SigGen deterministic byte-exact** for empty context (1 case)
- [x] **NIST FIPS 180-4 SHA-256** vector "abc" → ba7816bf...15ad
- [ ] **NIST FIPS 204 ML-DSA-65 SigVer** (deferred — confirmed indirectly through round-trip; a direct NIST KAT was not added in M1-F)
- [ ] **NIST FIPS 203 ML-KEM-768 Encapsulate/Decapsulate** (deferred — the Montana M1-F scope is KeyGen only, encapDecap is needed in M6+)

## B. Code surface

- [x] **Layer 1 Rust shim** **662 lines** (`crates/mt-crypto/src/lib.rs`), all **7** `unsafe` blocks carry `// SAFETY:` comments: 4 FFI sites (`fn keypair_from_seed`, `fn sign`, `fn verify`, `fn keypair_from_seed_mlkem`) + 3 mlock/munlock (`impl Drop for SecretKey`, `fn alloc_locked_secret_box`, `impl Drop for MlkemSecretKey`). Check exact lines via `grep -n "unsafe " crates/mt-crypto/src/lib.rs` (line refs are not fixed — they drift as the code grows).
- [x] **Layer 2 own C wrapper** **457 lines** (`mt_crypto.c`) + **67 lines** (`mt_crypto.h`), focused EVP API wrapping, `-Wall -Wextra -Wpedantic -Werror`
- [x] **Layer 3 vendored OpenSSL 3.5.5 LTS** via `openssl-src = "=300.5.5+3.5.5"` byte-pinned
- [x] Total own audit surface (Layer 1 + Layer 2) **1280 lines** (662 Rust shim + 49 FFI bindings + 457 C wrapper + 67 C header + 45 build script) — small enough for thorough review. Exact numbers: `wc -l crates/mt-crypto/src/lib.rs crates/mt-crypto-native/src/lib.rs crates/mt-crypto-native/csrc/mt_crypto.{c,h} crates/mt-crypto-native/build.rs`.
- [x] No `serde` auto-derive in consensus-critical types (custom `CanonicalEncode` trait)

## C. Memory safety + secret hygiene (Pass 17 enforcement)

- [x] **Drop+zeroize** for `SecretKey` (4032B) and `MlkemSecretKey` (2400B)
- [x] **Heap-allocated via Box** — secret bytes live on the heap, not inline on the stack (verified by the `secret_key_is_heap_allocated` test: `size_of::<SecretKey>() == 8` pointer)
- [x] **mlock applied** to heap pages holding secret bytes (best-effort via `alloc_locked_secret_box`); fallback assumption: encrypted swap (FileVault macOS / LUKS Linux)
- [x] **Stack hygiene during FFI** — `keypair_from_seed*` writes directly into the heap-locked Box; no stack temporary buffers with secret bytes (verified in [crates/mt-crypto/src/lib.rs](../crates/mt-crypto/src/lib.rs) — functions `keypair_from_seed` and `keypair_from_seed_mlkem`, search by name)
- [x] **munlock in Drop** before heap dealloc (best-effort, errno ignored)
- [x] No `Clone`/`Copy` derive on secret types (compile-time enforced via the security_invariants test)
- [x] No `PartialEq`/`Eq` on secret types (prevents a timing leak through ==)
- [x] No secret bytes in logs / stdout / stderr (file-content scan via the `no_println_or_log_on_secret_bytes_in_lib_code` test)
- [x] `mt-examples/m1_crypto.rs::print_sk` gated by an env var (`M1_DUMP_SK=1` opt-in; by default SK bytes are redacted; mechanism: the `dump_sk_enabled()` function in [m1_crypto.rs](../crates/mt-examples/examples/m1_crypto.rs#L39-L41) is checked in `print_sk` at line 76)
- [x] FFI buffer sizes match contract (PUBLIC_KEY_SIZE / SECRET_KEY_SIZE / SIGNATURE_SIZE constants used consistently)
- [x] **13 security invariants automated** in [crates/mt-crypto/tests/security_invariants.rs](../crates/mt-crypto/tests/security_invariants.rs) — regression detection
- [x] **6 Security Cards completed** in [docs/security-cards.md](security-cards.md) — Pass 17 mandatory enforcement

## D. Error surface

- [x] **`sign` / `keypair_from_seed` / `keypair_from_seed_mlkem`** return `Result<_, CryptoError>` (no panic)
- [x] **CryptoError enum** with 11 variants (Display + std::error::Error impls)
- [x] No `unwrap()` / `expect()` in lib code except an explicit internal invariant with a comment
- [x] No silent error swallowing (`.ok()`, `let _ = ...`)

## E. Determinism (consensus path)

- [x] **FIPS 204 Algorithm 2 deterministic Sign** via `OSSL_SIGNATURE_PARAM_DETERMINISTIC=1`
- [x] No `f32`/`f64` in the crypto path (consensus determinism per Montana [I-3] + [I-9])
- [x] No `HashMap`/`HashSet` iteration order dependency
- [x] No `SystemTime::now`/`Instant::now` in the consensus path (only in the test/tool helper `keypair()`, which is gated by `#[cfg(any(test, feature = "testing"))]`)

## F. Misuse resistance

- [x] **`SecretKey::from_array(arbitrary_bytes)`** on a subsequent `sign()` returns `Err(CryptoError::InvalidSecretKey)`, not a panic (F-7 closure through the F-2 Result API)
- [x] `keypair()` (weak-entropy test helper) is **not available** in the production binary (cfg-gate)
- [x] Public type fields are private (no struct literal construction that bypasses validation)
- [x] No `Default` impl for types requiring real crypto material

## G. Build & reproducibility

- [x] **`Cargo.lock`** committed
- [x] **Exact versions of all dependencies** (`=X.Y.Z`)
- [x] **`rust-toolchain.toml`** pinned
- [x] **Docker reproducible build** with a pinned base image digest
- [x] **CI gate `reproducible_release`** checks byte-identity between two independent runs
- [x] **Cross-compile correctness** via the `CARGO_CFG_TARGET_OS` env var

## H. Dependencies

- [x] **Crypto deps** are all production-grade (OpenSSL 3.5.5 LTS, sha2 0.10.9, no pre-1.0 in the consensus path)
- [x] **No "USE AT YOUR OWN RISK" libraries** in production paths
- [x] **`cargo audit`** clean (verified 2026-04-26: 0 vulnerabilities, 0 warnings, 39 dependencies scanned). Prerequisite: `cargo install cargo-audit --locked` (once). Verify: `cd "<repo-root>" && cargo audit`
- [x] **`cargo tree -p mt-crypto | grep -iE "ml-dsa|ml-kem|hybrid-array"`** → 0 hits (RustCrypto pre-1.0 deps removed entirely per the M1-F migration)
- [x] **License compatibility** — all deps MIT / Apache-2.0 / BSD / ISC

## I. Documentation

- [x] **`AUDIT.md`** at the repository root with audit chain + threat model + reproduction commands
- [x] **Threat model** explicit: in scope / out of scope / known limitations with closure paths
- [x] **Spec references** in code via `// spec, section "<name>"` without a version (single source of truth — `VERSION.md`)
- [x] **Manual Validation Gate scenarios** documented in `ROADMAP.md`
- [x] **Architect + critic roles** ([CLAUDE.md](../CLAUDE.md), [CRITIC.md](../CRITIC.md)) in the repository — peer-reviewable methodology

## J. Open findings

- [x] **Zero open audit findings** in the M1 foundational layer (per AUDIT.md §5)
- [x] All 7 M1-F audit findings (F-1..F-7) closed by construction
- [x] All 5 audit-package findings (F-A1..F-A5) closed by construction
- [x] All 4 M0+M1+M2 critic findings (F-1..F-4 from the `b4a00b1` audit) closed:
      F-1 (mt-recovery-fingerprint domain spec drift) → spec patch v33.1.2 → v33.1.3;
      F-2 (VERSION.md stale Implementation field) → updated to M0..M5 closed;
      F-3 (false positive withdrawn by the critic within the audit itself);
      F-4 (controlled halts documentation) → section K below
- [x] Manual Validation Gate scenarios 0/1 status: ✅ Ready (green for external audit)

## K. Controlled halts (documented panic sites)

List of all `panic!`/`assert!` in Montana lib code with justification. All of them are **controlled halts on protocol-invariant violation**, NOT attacker-triggered, NOT silent failures. The auditor should verify that each panic site is:
- (a) reachable only on invariant violation from a trusted source (Genesis params, frozen const)
- (b) accompanied by an explicit comment with the justification
- (c) not open to attacker-controlled input

| Site | File:line | Trigger | Justification |
|------|-------------|---------|-------------|
| `apply_transfer*` balance underflow | [crates/mt-account/src/lib.rs](../crates/mt-account/src/lib.rs) `fn apply_transfer{,_activation}` | `sender.balance.checked_sub(amount)` returns None | Protocol invariant breach: `validate_transfer*` guarantees `balance >= amount` BEFORE apply. A halt means the caller invoked apply without validate (programmer error or memory corruption). Not attacker-triggered: the validate-then-apply pattern is enforced. |
| `apply_transfer*` receiver/operator balance overflow | [crates/mt-account/src/lib.rs](../crates/mt-account/src/lib.rs) `fn apply_transfer/apply_emission` | `balance.checked_add(amount)` returns None at u128::MAX | Encoded arithmetic horizon — the total per-account balance reached u128::MAX (~3.4×10³⁸ nɈ). Not reachable under the constant emission `EMISSION_moneta = 13 × 10⁹ nɈ` per window. Documented halt. |
| `apply_*` op_height/account_chain_length overflow | [crates/mt-account/src/lib.rs](../crates/mt-account/src/lib.rs) `fn apply_*` | `u32` field counters reached u32::MAX (~4.29 billion operations per account) | Encoded arithmetic horizon: 4.29 billion operations per account, not reachable in a realistic timeframe. Documented halt. |
| `window_w_to_u32` cast overflow | [crates/mt-account/src/lib.rs](../crates/mt-account/src/lib.rs) `fn window_w_to_u32` | `window_w: u64 > u32::MAX` on cast into an AccountRecord field | AccountRecord uses u32 for window fields (encoded size optimization 4B vs 8B). Horizon = ~4.29 billion windows ≈ 8000 years at 60 sec/window. Documented halt. |

**All sites:**
- ✅ Have an explicit panic message with the justification
- ✅ Reachable only when an arithmetic horizon is reached or a protocol invariant is breached
- ✅ Not attacker-triggered
- ✅ Halt = correct behavior per spec — a protocol upgrade is required or validate-then-apply was violated (programmer error)

`mt-crypto` panics gated through `assert_eq!(r, MT_OK, ...)` were already converted to `Result<_, CryptoError>` in the M1-F closure (commit `e1164ad`) — there is no panic in lib code there any more.

`mt-examples` test helpers may panic through `.expect("...")` — this is test scaffolding, outside the production audit scope (per the critic role Scope §"NOT in scope: mt-examples test helpers"). Production binary calls from mt-examples (m1_crypto demo) panic through `.expect("HKDF-derived seed cannot fail KeyGen")` — an internal invariant, not attacker-triggered.

## L0. Test strength augmentations (Pass 22)

**Mutation testing (recommended, not a blocker for the audit):**

```
cargo install cargo-mutants --locked
cargo mutants --package mt-lottery --package mt-consensus --package mt-entry --package mt-account --package mt-store
```

Mutation testing introduces synthetic `mutations` (changes of arithmetic,
boundary conditions, removed function calls) into production code and checks
whether a test catches each mutation. **Surviving mutations** = weak
tests (which may pass on broken code).

**Current status:** not run automatically in CI. Recommended pre-mainnet
benchmark: ≥80% mutation kill rate for the consensus path (M3-M4 crates).

**Applicability to the external audit:** the auditor may request a mutation
report as evidence of test strength. Closure requires:
1. Run cargo-mutants
2. Analyze surviving mutations
3. Add test cases or strengthen assertions

Closure cost ~1-2 working days (run + analyze + augment tests). Not a blocker
for the current external audit engagement — this is a test quality improvement
metric, not a correctness gap.

## L. M3 Storage Cards (per persistent state table)

Per the parent project's Storage Card invariant: every
persistent state table must have a Storage Card before the status "closed".
Closes Gate 14 ([I-14] state lifecycle) for the apply_proposal layer.

### AccountTable Storage Card

```
Table:                            AccountTable (mt_state::AccountTable)
Operation creating a record:      TransferActivation (opcode 0x0A)
Pays the creation cost:           sender (existing account, sponsor pattern)
Record size (bytes):              2059 (ACCOUNT_RECORD_SIZE)
Secondary resources per record:   SMT leaf hash 32B + potential merkle path

Cost per record:                  amount > 0 (sender chooses) — no fixed
                                   creation fee, the sender sends any
                                   amount to the receiver, who thereby receives
                                   AccountRecord
Cost barrier for anti-spam:       NOT through a monetary barrier (would violate
                                   [I-15] time-based scarcity); protection through
                                   cooldown 1 TransferActivation per sender
                                   per τ₂ (see validate_transfer_activation
                                   spec rule (e) [I-15] cooldown enforcement)

Lifecycle condition:              no explicit removal in M3 scope
                                   (CloseAccount opcode 0x0B — M11 milestone,
                                   pending spec finalization payload format)
Lifecycle threshold:              N/A in the current version
[I-14] path:                      3 (rate-limit through [I-15] time scarcity);
                                   barriers through time, not money

Existing pruning consistent:      yes (no pruning, by design until M11)
[I-14] compliance status:         pending M11 — closure path in ROADMAP §M11
                                   "CloseAccount finalization". The rate-limit
                                   through the cooldown currently limits the attacker's
                                   account creation rate; explicit deletion
                                   awaits spec finalization of opcode 0x0B.

Conservation invariant (per-op):  Σ delta_balance == 0 for Transfer/
                                   TransferActivation (sender -= amount,
                                   receiver += amount, atomic)
Storage growth invariant per τ₂:  ≤ active_chain_length / τ₂ × max_accounts_
                                   per_τ₂ (rate-limited through [I-15])
Storage cap:                      no explicit hard cap — relies on
                                   [I-15] time-based + future M11 deletion
```

**Sabotage budget analysis:** an attacker with $1M / $100k / $10k and no profit motive,
maximizing state bytes:
- Stake-protected: TransferActivation requires a sender with balance > 0 + cooldown;
  the attacker creates `N` accounts with an initial balance, waits τ₂ windows, repeats
  the activation of each with a separate sponsor. Real cost = TC required for
  bootstrapping N senders × cooldown overhead.
- Per-τ₂ limit: 1 activation per existing account → max N accounts for the
  attacker = `existing_accounts × (windows / τ₂)`. Linear, not
  exponential growth.
- To bloat 1 GB of AccountTable: 1 GB / 2059 B ≈ 487K accounts. At 1
  activation per account per τ₂ = 487K windows ≈ 6.7 days (at τ₂ = 20160 ×
  60sec). This estimate assumes the attacker already owns ≈ 487K sender
  accounts — which by itself requires bootstrapping.
- M11 CloseAccount will allow deletion, which gives a smaller surface for accumulated
  bloat but will not prevent a short-term spike.

[I-15] time-based + cooldown is the current primary mitigation. M11 is the secondary
explicit cleanup path after spec finalization.

### NodeTable + CandidatePool Storage Cards

Access through mt-state types (NODE_RECORD_SIZE = 2098, CANDIDATE_RECORD_SIZE
= 2082). Lifecycle / cost analysis for these tables belongs to the mt-entry domain (M4
audit scope, a separate milestone).

---

## Reproduction one-liners for the auditor

**NIST KAT cross-implementation conformance proof:**
```
cd "<repo-root>" && cargo test -p mt-crypto-native --test nist_acvp_kat -- --nocapture
```

**Internal correctness baselines:**
```
cd "<repo-root>" && cargo test -p mt-crypto-native -p mt-crypto -p mt-mnemonic
```

**Recovery flow end-to-end:**
```
cd "<repo-root>" && cargo test -p mt-mnemonic --test e2e_recovery -- --nocapture
```

**M2 Determinism invariants (mt-merkle / mt-genesis / mt-state / mt-timechain):**
```
cd "<repo-root>" && cargo test -p mt-merkle -p mt-genesis -p mt-state -p mt-timechain --test determinism_invariants -- --nocapture
```

Expected: SMT root determinism, Genesis singleton stability,
state table BTreeMap canonical sort,
SSHA + cemented_bundle_aggregate per [I-8].

**M3 Determinism invariants (mt-account):**
```
cd "<repo-root>" && cargo test -p mt-account --test determinism_invariants -- --nocapture
```

Expected: Transfer/ChangeKey/Anchor/TransferActivation encoded
sizes, op_hash determinism (R2 invariant), apply_* determinism, validate
rejection patterns, settle_window order independence, genesis state
determinism, reward/supply consistency, apply_proposal determinism,
controlled panic on protocol breach (checked arithmetic).

**M4 Determinism invariants (mt-lottery / mt-consensus / mt-entry):**
```
cd "<repo-root>" && cargo test -p mt-lottery -p mt-consensus -p mt-entry --test determinism_invariants -- --nocapture
```

Expected: 32 + 27 + 24 = **83 PASS** — bundle_hash/reveal_hash R2 stability,
compute_endpoint [I-8] binding, log2_q64 / ln_q64 / weighted_ticket_node
monotonicity, determine_winner argmin canonical (M4-1 closure: TooManyOps
validation barrier), proposal_hash R2, canonical_proposer / fallback_proposer
Lookback Leadership cascade, compute_control_set canonical sort, validate_*
acceptance, finalization_status, NodeRegistration R2, candidate_ssha_init
[I-8], selection_slots / selection_sort_key, required_ssha_length Adaptive
SSHA, distinct domain separators between three sort_key compositions.

**M5 Determinism invariants (mt-store):**
```
cd "<repo-root>" && cargo test -p mt-store --test determinism_invariants -- --nocapture
```

Expected: AccountTable / NodeTable / CandidatePool
save/load roundtrip (root byte-equal), CorruptedLength detection, crash
recovery (meta + verify_consistency), prune_proposals, byte-exact equality
for identical input, BTreeMap canonical sort persistence-stable, full state
cycle (open → populate → save → close → reopen → load), R5 atomic rename
verification (no `<name>.tmp` after save, atomic overwrite).

**M5 Pseudo-fuzz harness (mt-store wire decoders):**
```
cd "<repo-root>" && cargo test -p mt-store --test fuzz_decoders -- --nocapture
```

Expected: 5 PASS — `decode_account_record` / `decode_node_record` /
`decode_candidate_record` / `decode_proposal_header` /
`load_meta_last_cemented` are run on 7500+ pseudo-random byte arrays
of various lengths (deterministic Xorshift64). Invariant: never panic,
always returns Result; valid length → Ok, mismatch → StoreError::CorruptedLength.

Pseudo-fuzz is used instead of libfuzzer-sys / cargo-fuzz because of the nightly
toolchain dependency (workspace pinned to stable). When a nightly
target appears — replace with coverage-guided fuzzing in crates/mt-store/fuzz/
fuzz_targets/.

**M4 External SHA-256 oracle (Pass 25 Independent Oracle):**
```
cd "<repo-root>" && python3 scripts/oracle_python_sha256.py
cd "<repo-root>" && cargo test -p mt-lottery --test external_oracle -p mt-entry --test external_oracle
```

Expected (Python): 4 hardcoded hex digests + distinct domains PASS +
input sensitivity PASS.

Expected (Rust tests): 4 PASS — `compute_endpoint`, `candidate_ssha_init`,
`selection_sort_key`, `nr_sort_key` byte-exact match Python `hashlib.sha256`
output. Cross-impl conformance verified — an independent reference, not based on
Rust SHA-256 (the sha2 crate) → protection against drift between the Rust impl and the spec
formula.

**Reproducible release build verification:**

*Prerequisites:* Docker ≥ 20.10 installed and running, bash (for process substitution), ~30 minutes wall-clock for two clean builds, ~5 GB free disk.

```
cd "<repo-root>" && docker build --no-cache --file docker/release-build.dockerfile --tag mt-audit-1 . && docker build --no-cache --file docker/release-build.dockerfile --tag mt-audit-2 . && diff <(docker run --rm mt-audit-1 sha256sum /usr/local/bin/*) <(docker run --rm mt-audit-2 sha256sum /usr/local/bin/*)
```

*Alternative without the Docker prerequisite:* verify through CI history — every push to `main` runs the CI job `reproducible_release` (see .github/workflows/ci.yml), which performs the same double build with a byte-identity assertion. The auditor can check green CI runs over a period as evidence.

**Build sanity:**
```
cd "<repo-root>" && cargo fmt --all -- --check && cargo clippy --all-targets -- -D warnings && cargo build --all --release
```

---


---

## H. M6 Network layer (mt-net + mt-net-transport)

- [x] **mt-net wire format byte-exact** — ProtocolMessage envelope (14 B header + payload), 18 message types in registry, IBT online + mesh proof, Bootstrap PoW, Uniform Framing (1024 B fixed), 12 structured payloads (FastSync*, PeerList*, BatchLookup*, RangeSubscribe*, Bye)
- [x] **mt-net 110 unit + integration tests pass** — `cargo test -p mt-net --features testing`
- [x] **mt-net-transport libp2p TCP+TLS 1.3+Noise+Yamux upgrade chain** — verified through `cargo test -p mt-net-transport --features testing` (14 tests pass)
- [x] **Manual Validation Gate scenario 6 PASS** — two-node handshake e2e (commit `9a15f49`); `tests/e2e_two_node_handshake.rs::two_node_request_response_ping_pong`
- [x] **Manual Validation Gate scenario 7 PASS** — proposal exchange e2e + 512 KiB boundary (commit `04f8d29`); `tests/e2e_proposal_exchange.rs::{proposal_envelope_round_trip, large_payload_near_max_limit}`
- [x] **[C-5] libp2p capability checklist 8/8 PASS** — TCP+TLS 1.3+Noise+Yamux+Swarm primitives, async tokio, rustls + snow constant-time, Linux+macOS+Windows, IPFS+Filecoin+Polkadot 5+ years production, MIT/Apache 2.0
- [x] **Backpressure rules B1-B6 enforced** — max_protocol_payload_bytes (1 MiB) + max_sf_ciphertext_bytes (64 KiB) reject before allocation per spec
- [x] **Critic-fix bundle P-C1..P-C8 closed** — domain registry SSOT in mt-codec, prefix-free rename mt-tunnel→mt-tunnel-online, 5 fuzz harnesses scaffolded, try_new constructors, Bye forward-compat, ibt_mesh_verify O(1) path, no unwrap/expect in lib code
- [x] **5 fuzz harnesses scaffolded** in `crates/mt-net/fuzz/fuzz_targets/` — fuzz_decode_envelope/frame/mesh_frame/sf_envelope/payloads (run via `cargo +nightly fuzz run`)

## I. M9 Conformance suite (mt-conformance)

- [x] **mt-conformance crate created** — public binding test vectors for cross-implementation byte-exact verification
- [x] **2 unit tests pass** — `envelope_vectors_byte_exact` + `pow_target_byte_exact`
- [x] **Initial vectors covered** — envelope A1/A2/A3 + IBT B1 (after P-C2 rename) + Bootstrap PoW F1/F2 target derivation
- [x] **iOS port mirrored** — `iOS/Apps/Montana/MontanaTests/MTConformanceVectors.swift` byte-exact mirror of the Rust crate
- [ ] **Expansion** (12 TBD-A markers) — defer until app-layer payload format finalization (BatchLookupRequest/Response, RangeSubscribeResponse query/result/blob entry types)

## Sign-off

| Role | Name | Date | Status |
|------|------|------|--------|
| Architect | (architect role per CLAUDE.md v1.15.0) | 2026-05-02 | ✅ Self-attested ready (M6 + M9 added) |
| Critic | (critic role per CRITIC.md v1.7.0) | 2026-05-02 | ✅ All findings closed (8 P-C1..P-C8 + 5 P-S1..P-S5 critic-fix bundle) |
| Author | (project owner) | — | Awaiting the decision on audit firm engagement |
| External auditor | (TBD) | — | Pending engagement |

---

**Status:** READY FOR EXTERNAL AUDIT (M1 + M2 + M3 + M4 + M5 + M6 + M9 layers scope, 19 crates, 127 focused mt-net/mt-net-transport tests passed on 2026-05-20, MONT-001/MONT-002 sync applied; protocol spec v35.25.1 + network spec v1.1.0 + app spec v3.12.0).
