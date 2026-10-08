# Montana client core

The Rust workspace the Montana applications link. `mt-bindings` exports it through one C ABI
([`crates/mt-bindings/include/montana_ffi.h`](crates/mt-bindings/include/montana_ffi.h)) to Swift on iPhone, iPad and
Mac, and through JNI to Kotlin on Android; nothing cryptographic is reimplemented in the applications.

## Crates

| Crate | What it holds |
|---|---|
| `mt-crypto`, `mt-crypto-native` | ML-DSA-65 signatures and ML-KEM-768 encapsulation (OpenSSL 3.5 built from source), SHA-256 with domain separation, ChaCha20-Poly1305; NIST ACVP known-answer tests |
| `mt-mnemonic` | 24 words: entropy gathered from several sources under health tests, the phrase, the master seed and the per-role key seeds |
| `mt-noise-pq` | The Noise XX handshake with ML-KEM-768 and ML-DSA-65 in place of classical Diffie-Hellman |
| `mt-messenger-e2e` | The sealed letter between two people |
| `mt-postman`, `mt-overlay`, `mt-rendezvous`, `mt-bootstrap`, `mt-wake` | Delivery: store-and-forward queues, the overlay, meeting points, first contact, waking a sleeping phone |
| `mt-names` | Names and their proofs |
| `mt-codec`, `mt-merkle`, `mt-genesis`, `mt-state`, `mt-timechain`, `mt-account`, `mt-lottery`, `mt-consensus`, `mt-entry`, `mt-store`, `mt-sync`, `mt-net`, `mt-net-transport`, `montana-node` | The earlier consensus line of the implementation (see [`VERSION.md`](VERSION.md)) |
| `mt-conformance`, `mt-examples` | Byte-exact conformance checks and runnable examples that print every intermediate value |
| `mt-bindings` | The C ABI the applications call |

## Build and test

```
cd core/Code
cargo test --workspace --release
cargo run --release -p mt-examples --example m1_crypto -- all
cargo run --release -p mt-examples --example m1_mnemonic -- all
```

The compiler is pinned in [`rust-toolchain.toml`](rust-toolchain.toml); `mt-crypto-native` builds OpenSSL from source,
so a C compiler and Perl are needed. The iOS framework is built by
[`crates/mt-bindings/build-ios-xcframework.sh`](crates/mt-bindings/build-ios-xcframework.sh).

## Documents

| File | What |
|---|---|
| [`AUDIT.md`](AUDIT.md) | The audit package |
| [`docs/audit-checklist.md`](docs/audit-checklist.md) | What the internal audit covered |
| [`docs/security-cards.md`](docs/security-cards.md) | Per-primitive security analysis |
| [`docs/SPEC_DEVIATIONS.md`](docs/SPEC_DEVIATIONS.md) | Known deviations from the specification, with their state |
| [`docs/build-from-source.md`](docs/build-from-source.md) | The reproducible build |
| [`docs/CONFORMANCE.md`](docs/CONFORMANCE.md) | Conformance |
| [`docker/runtime/QUICKSTART.md`](docker/runtime/QUICKSTART.md) | A node in a container |

The normative specification is [`../docs`](../docs).

## Licence

Dual-licensed under Apache-2.0 OR MIT, at your choice: [`LICENSE-APACHE`](LICENSE-APACHE), [`LICENSE-MIT`](LICENSE-MIT).
