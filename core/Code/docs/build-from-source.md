# Reproducible Build from Source — Audit Reproduction Guide

Complete instructions for an external auditor / independent reviewer to reproduce the Montana reference implementation byte-identically from source.

See also: `AUDIT.md` (audit package overview), `docs/audit-checklist.md` (per-layer self-attestation), `docs/security-cards.md` (crypto primitives).

---

## 1. Prerequisites

### Toolchain

| Component | Version | Source | Verification |
|-----------|---------|--------|--------------|
| Rust toolchain | stable, ≥ 1.70 (pinned via `rust-toolchain.toml`) | rustup.rs | `rustc --version` |
| Cargo | bundled | bundled | `cargo --version` |
| Git | ≥ 2.30 | system | `git --version` |
| OpenSSL 3.5 LTS | =3.5.5 (pinned via `openssl-src` workspace dep) | vendored via the `openssl-src` crate | autobuilt by Cargo |
| C compiler | clang ≥ 13 or gcc ≥ 11 | system | for openssl-src vendored build |

### Hardware reference (for timing benchmark verification)

- Genesis hardware reference (per spec [I-18]): Apple iMac 24-inch M1 2021, 8 GB unified memory, macOS Sequoia 15.7.3, Rust 1.92.0 stable, sha2 crate 0.10.9 + ARM SHA-2 hardware extensions
- D₀ benchmark expected: median single-thread SHA-256 rate 5.097 MH/s
- Other hardware: D₀ value remains 325 000 000 (Genesis Decree authoritative); only the SSHA wall-clock varies

---

## 2. Clone & checkout

```bash
git clone https://github.com/efir369999/montana_messenger
cd montana_messenger/core/Code

# Verify HEAD matches expected commit (audit signature confirms specific revision)
git rev-parse HEAD
# Expected for the v35.25.1 audit cycle: use the audited commit hash or a later forward-compatible revision.
```

---

## 3. First build

```bash
# Single-core/single-process per .cargo/config.toml (anti-overheat policy for PBKDF2 tests)
cargo build --workspace --release
```

Expected duration:
- First build: 5-15 minutes (libp2p ~120 transitive deps)
- Subsequent builds: 30-60 seconds (incremental)

---

## 4. Mandatory checks (4 green requirement)

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
cargo build --workspace --release
```

All four must exit with code 0.

---

## 5. Conformance verification

```bash
# M9 standalone test vectors
cargo test -p mt-conformance
# Expected: 2 tests pass (envelope_vectors_byte_exact + pow_target_byte_exact)

# M6 network layer
cargo test -p mt-net --features testing
# Expected: 96 unit + 14 integration = 110 tests pass

# M6 transport layer
cargo test -p mt-net-transport --features testing
# Expected: 11 unit + 3 e2e = 14 tests pass (including two-node handshake +
#           proposal exchange + 512 KiB boundary)
```

---

## 6. NIST KAT verification (M1 cryptography)

```bash
cargo test -p mt-crypto-native --test nist_acvp_kat -- --nocapture
# Expected: NIST FIPS 204 ML-DSA-65 + FIPS 203 ML-KEM-768 byte-exact against
# ACVP-Server published vectors (50+ KAT cases pass)
```

---

## 7. Manual Validation Gate (interactive)

Each scenario prints every intermediate value, so two operators compare a run byte for byte.

Scenarios 0-7 are interactive verification of each mechanism through the example
binaries in `crates/mt-examples/`. A full pass requires about 2-3 hours
of manual operator time.

```bash
cargo run --release --example m1_mnemonic recovery-fingerprint
cargo run --release --example m1_mnemonic keypair
cargo run --release --example m1_crypto keypair
cargo run --release --example m1_crypto all
```

---

## 8. Reproducibility verification

Two independent builds on different machines must produce byte-identical
binaries:

```bash
# Build 1
cargo build --release -p montana-node
sha256sum target/release/montana-node > /tmp/build1.sha256

# Build 2 (another machine, same toolchain)
cargo build --release -p montana-node
sha256sum target/release/montana-node > /tmp/build2.sha256

# Compare
diff /tmp/build1.sha256 /tmp/build2.sha256
# Expected: empty output (byte-identical)
```

Note: at the time of M6 closure, `montana-node` is in the M8 SPEC_DEVIATIONS rewrite
phase (see `docs/SPEC_DEVIATIONS.md` DEV-001..009). Full reproducibility
verification is to be backed by CI matrix builds.

---

## 9. Audit firm engagement

Recommended firms (see the AUDIT.md "Audit firm engagement" section):

- **NCC Group** — strong PQ crypto + iOS wallet experience
- **Trail of Bits** — blockchain wallet specialty (Slither, Echidna)
- **Cure53** — Berlin, mobile + crypto + browser
- **Quarkslab** — French, hardware + iOS
- **Cryspen** — formal verification (HACL\* contributors), for the PQ crypto bottom layer

Estimated cost: $50k-$250k for a 4-8 week full-scope audit M1+M2+M3+M4+M5+M6+M9.

---

## 10. Contact / questions

- Spec issues: open an issue in the repository
- Code issues: open an issue in the repository
- Audit findings: open an issue in the repository or contact the author directly
