# The security cards of the wire

One card per bearer of secret material, filled before the bearer is called closed. What a card
states is what an auditor would otherwise have to derive by reading: where a secret is built,
where it is destroyed, how many copies exist on the way, what is shown of it, and what remains
open with the path that closes it.

The cards state the code as it stands, read at the lines named. A change to the handling of any
secret is a change to the card in the same commit.

---

## The channel of a handshake — the two directional keys of a session

| | |
|---|---|
| Secret material | two directional keys, 32 B each; the transcript, 32 B, which is public and stands beside them |
| Who holds them | the two devices that ran the four flights, each in its own memory. A carrier between them holds a sealed box and the keys of a session reach no third party at any point of the handshake |
| Site of construction | `src/handshake.rs`, `of_transcript` — a private function, reached through `initiator_channel` and `responder_channel` and through no other path this crate exports |
| Site of destruction | `src/handshake.rs`, `impl Drop for Channel` — all three fields `zeroize()` |
| Construction copies | one: the master is derived into a local and the two keys are written straight into the fields of the channel |
| Transfer | by reference through three accessors; the type carries neither `Clone` nor `Copy`, so a second copy has to be written by hand to exist |
| What holds the keys behind a verification | the three fields are private, the constructing function is private, and both exported doors call `verify` on the far side's signature over the transcript each computed itself before they build one. A caller who cannot verify receives `Err` and no channel: the prohibition is the privacy of the fields plus the order inside those two doors, and it is checkable at `src/handshake.rs` lines 277 and 328 |
| Branching on secret bytes | none in this crate; what a caller compares is the transcript, which is public |
| `PartialEq` on the bearer | written by hand as absent, so this crate exposes no comparison of key material to be timed |
| Logging surface | `Debug` is written by hand and prints a fixed string; a search of the crate for `println!` over a key returns nothing as of this commit |
| Upstream | the keys are derived by `mt-codec`, the encapsulations by `mt-suite`; this crate holds no primitive of its own |
| Published vectors | the handshake's four flights are frozen in the set and reproduced by the gate |
| **Open** | the pages holding the two keys are not locked against swap |
| Closure path | as for the suite: `mlock` asks for either `unsafe`, which this crate forbids at its head, or a dependency that carries it. Until one of the two is taken the assumption is stated rather than implied: **a machine running a node is expected to hold an encrypted swap** (FileVault, LUKS or the equivalent), and an operator whose swap is in the clear runs with the session keys exposed to a disk they did not intend |

## The sealing of a cell — the key of a pipe and the plaintext it covers

| | |
|---|---|
| Secret material | the key of a pipe, 32 B, held by the caller; the inner plaintext of a cell |
| Who holds them | the device sealing and the device opening. What the carrier moves is a sealed cell, and the key of a pipe is drawn on each end from what the two already share |
| Site of construction | `src/cell.rs`, `SealingKey::new(*pipe_key)` at each sealing and each opening |
| Site of destruction | the sealing key by `mt-suite`'s own `Drop`; the plaintext by `Zeroizing`, which wipes at the end of its scope |
| Construction copies | one per call, into the cipher the upstream constructs — counted on the suite's card, where the primitive lives |
| Transfer | the encoded inner cell is held in `Zeroizing` from the line it is built; a delivery wipes its chunk and its identifier on drop |
| Logging surface | a search of the crate returns no `println!` and no derived `Debug` over a key or a plaintext as of this commit |
| Nonce discipline | stated by the protocol above this crate, as the suite's card says; what keeps two cells apart is the pipe and the counter, and neither is decided here |
| **Open** | the key of a pipe belongs to the caller and its handling is stated on the suite's card; this crate holds it for the length of one call |

---

## What no card here covers

The primitives themselves — the AEAD, the encapsulation and the signature — are the suite's, and
their cards stand in `crates/mt-suite/SECURITY.md`. What these cards state is how **this** code
handles what those primitives hand it.
