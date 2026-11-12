# The security cards of the suite

One card per primitive holding secret material, filled before the primitive is called closed.
What a card states is what an auditor would otherwise have to derive by reading: where a secret
is built, where it is destroyed, how many copies exist on the way, what is shown of it, and
what remains open with the path that closes it.

The cards state the code as it stands. A change to the handling of any secret is a change to
the card in the same commit.

---

## ML-DSA-65 — the signature of consensus and of a person's actions

| | |
|---|---|
| Secret material | signing key, 4 032 B |
| Site of construction | `src/sign.rs`, `keypair_from_seed` |
| Site of destruction | `src/sign.rs`, `impl Drop for SecretKey` — `as_ref_mut().zeroize()` |
| Construction copies | one: the generation writes into a `Zeroizing` buffer this crate owns, and `SecretKey::of` moves it into the heap and wipes the buffer |
| Copies per signature | none: the key is held in the form the primitive signs from, and signing borrows it |
| Transfer | by reference; the type is neither `Clone` nor `Copy` |
| Branching on secret bytes | none in this crate; the primitive is the upstream implementation |
| `PartialEq` on the secret type | absent, so no comparison of a secret exists to be timed |
| Logging surface | `Debug` is written by hand and prints a fixed string; no `println!` of a secret exists in the crate |
| Randomness | none: the variant is deterministic, `RND = 0x00 x 32` |
| Upstream | `libcrux-ml-dsa`, a formally verified implementation extracted from F\* |
| Published vectors | NIST ACVP FIPS 204 keyGen and sigGen, in `tests/fixtures` |
| Second implementation | OpenSSL 3.6 verifies what this tree signs and refuses a doctored signature |
| **Open** | the pages holding the key are not locked against swap |
| Closure path | `mlock` requires either `unsafe` — which this crate forbids — or a dependency that carries it; until then the assumption is stated rather than implied: **a machine running a node is expected to hold an encrypted swap** (FileVault, LUKS or the equivalent), and an operator whose swap is in the clear runs with the key exposed to a disk they did not intend |

## ML-KEM-768 — the encapsulation of the application plane and of a handshake

| | |
|---|---|
| Secret material | decapsulation key, 2 400 B; shared secret, 32 B |
| Site of construction | `src/kem.rs`, `keypair_from_seed` and `encapsulate` / `decapsulate` |
| Site of destruction | `impl Drop for SecretKey` and `impl Drop for SharedSecret`, both `zeroize()` |
| Construction copies | one intermediate, wiped by `SecretKey::of` |
| Copies per decapsulation | **one, on a stack frame nobody wipes** |
| Transfer | by reference; neither type is `Clone` or `Copy` |
| Logging surface | both `Debug` impls print a fixed string |
| Upstream | `libcrux-ml-kem`, a formally verified implementation extracted from F\* |
| Published vectors | NIST ACVP FIPS 203 keyGen, encapsulation and decapsulation |
| Second implementation | OpenSSL 3.6 draws a pair, this tree encapsulates to it, OpenSSL decapsulates and the secret agrees |
| **Open** | the copy per decapsulation, and the pages not locked against swap |
| Closure path | the type the primitive takes exposes no mutable access, so a key held in it could not be wiped at all — between a key living on in freed memory and one copy per call, the wipe is what must hold. The copy closes upstream, with a borrowing entry point or a mutable accessor, and not by choosing the worse of the two here. Swap: as above |

## ChaCha20-Poly1305 — the sealing of a cell and of stored content

| | |
|---|---|
| Secret material | sealing key, 32 B |
| Site of construction | `src/aead.rs`, `SealingKey::new` |
| Site of destruction | `impl Drop for SealingKey`, `zeroize()` |
| Copies per call | one, into the cipher the upstream constructs |
| Nonce discipline | stated by the caller; **a nonce repeated under one key reveals the difference of two plaintexts**, and what keeps nonces apart is the protocol above this crate, not this crate |
| Logging surface | `Debug` prints a fixed string |
| Upstream | `chacha20poly1305` of the RustCrypto family, audited |
| Published vectors | RFC 8439 §2.8.2 |
| Second implementation | the Python cryptography library seals and opens the same values |
| **Open** | the key is 32 B and lives on the stack of its holder; swap as above |

## The commitment that carries standing

| | |
|---|---|
| Secret material | the randomness of a commitment, `r1` and `r2`, `[-eta, eta]` per coefficient |
| Site of construction | the caller's; `commit` takes it by reference and holds nothing |
| Site of destruction | the caller's |
| Branching on secret bytes | the bound is checked before any arithmetic and a value outside it is refused rather than reduced; the refusal names the value, which is the caller's own |
| Published vectors | the three of the set, reproduced by an independent implementation before this code was written |
| **Open** | none of this crate's making |

---

## What no card here covers

The internals of the upstream primitives: whether the constant-time claims of
`libcrux-ml-dsa`, `libcrux-ml-kem` and `chacha20poly1305` hold at the instruction level is a
question for the people who verify those implementations, and this tree stands on their work
rather than repeating it. What these cards state is how **this** code handles what those
primitives hand it.
