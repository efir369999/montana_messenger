# Montana core: the protocol, its specification and its cryptography

This folder is the protocol core of the Montana Time ecosystem. Every application in this repository links it, and
everything that is normative about Montana is written here: the specification set, the reference implementation of
that set, and the client core the iPhone, iPad, Mac and Android applications are built on.

## What is here

| Path | What it is |
|---|---|
| [`docs/`](docs/) | The normative set: Constitution, Canon, Consensus, Value, Identity, Network, App, and the Registry index. Read [`docs/README.md`](docs/README.md) first; it gives the order. |
| [`Montana-Core/`](Montana-Core/) | The reference implementation of the set (Rust workspace): primitives, encodings, trees, derivations, the wire, the pulse of the clock, the proof, a node binary (`montana-node`) and a terminal wallet (`montana-wallet`). The build parses the values, domain separators and frozen vectors of the set and fails on any divergence. |
| [`Code/`](Code/) | The client core (Rust workspace) the applications link through the C ABI of `mt-bindings`: keys from 24 words (`mt-mnemonic`), signatures and key encapsulation (`mt-crypto`, `mt-crypto-native`), the post-quantum Noise XX handshake (`mt-noise-pq`), sealed letters (`mt-messenger-e2e`), store-and-forward delivery (`mt-postman`), names (`mt-names`), and the earlier consensus line of the implementation. |
| [`Montana wordlist.txt`](Montana%20wordlist.txt) | The 2048-word list of the 24-word recovery phrase; `Code/` compiles it in and checks its SHA-256 fingerprint, `Montana-Core` carries the same list in `crates/mt-seed/wordlist.txt`. |

## Primitives

| Purpose | Primitive | Standard | Implementation |
|---|---|---|---|
| Signatures | ML-DSA-65 | NIST FIPS 204 | `libcrux-ml-dsa` 0.0.10 in Montana-Core; OpenSSL 3.5 built from source (`openssl-src` 300.5.5) in Code |
| Key encapsulation | ML-KEM-768 | NIST FIPS 203 | `libcrux-ml-kem` 0.0.10 in Montana-Core; OpenSSL 3.5 in Code |
| Authenticated encryption | ChaCha20-Poly1305 | RFC 8439 | RustCrypto `chacha20poly1305` 0.10.1 |
| Hashing | SHA-256; SHA-3 | NIST FIPS 180-4; FIPS 202 | RustCrypto `sha2`, `sha3` |

The protocol layer carries no classical public-key primitive: identities sign with ML-DSA-65, sessions agree keys
with ML-KEM-768, and a link between two machines is sealed under keys that post-quantum handshake established. Every
dependency is pinned to an exact version in the workspace manifests.

## Build and test

Each workspace pins its compiler in `rust-toolchain.toml` (Rust 1.92.0). `Code/` builds OpenSSL from source for
its native layer, so it needs a C compiler and Perl as well.

```
cd core/Montana-Core
cargo test --workspace --release

cd ../Code
cargo test --workspace --release
```

Two machines and a payment from a terminal are walked through in [`Montana-Core/README.md`](Montana-Core/README.md).
A node can also be built and run in a container from this folder: see
[`Code/docker/runtime/QUICKSTART.md`](Code/docker/runtime/QUICKSTART.md).

## Where to read critically

- [`Montana-Core/AUDIT.md`](Montana-Core/AUDIT.md): what the green build does not hold, found by reading, with what closes each item.
- [`Code/AUDIT.md`](Code/AUDIT.md) and [`Code/docs/audit-checklist.md`](Code/docs/audit-checklist.md): the audit package of the client core.
- [`Code/docs/SPEC_DEVIATIONS.md`](Code/docs/SPEC_DEVIATIONS.md): every known deviation of the client core from its specification, with its state.
- [`Code/docs/security-cards.md`](Code/docs/security-cards.md): the security cards of the client core.

`Code/` predates the current set: its [`VERSION.md`](Code/VERSION.md) records the specification generation it was
written against. Where `Code/` and `docs/` disagree, `docs/` is normative.

## Licence

Both workspaces are dual-licensed MIT OR Apache-2.0 (the `license` field of their manifests;
[`Code/LICENSE-MIT`](Code/LICENSE-MIT), [`Code/LICENSE-APACHE`](Code/LICENSE-APACHE)).

## Reporting

Findings go to the issues of this repository; a weakness that should not be public first goes by e-mail as
[`SECURITY.md`](../SECURITY.md) describes.
