# The security cards of a machine

One card per bearer of secret material. This crate is the machine an operator runs: it draws the
secret on its first start, derives the pair it answers the wire with, and holds the links it did
not open. Every secret it touches belongs to a crate below it, and what these cards state is how
**this** one handles what those crates hand it.

---

## The secret of this machine

| | |
|---|---|
| Secret material | 32 B, drawn on the first start and never again |
| Who holds it | this device: the file `mt-store` keeps, and the memory of the process while it runs |
| Site of construction | `src/lib.rs`, `Machine::start` — drawn by `mt_seed::birth` from six sources with the health tests of the set over them, and refused rather than warned about when a source is not alive |
| Site of destruction | `Zeroizing` at every step: the block inside `Birth`, the array this crate copies it into, and the array the store answers with |
| Construction copies | two, both wrapped — the array handed to the store, and the array read back from it to seed the answering pair |
| What is shown | the fingerprint of the **public** key, six groups of five digits, which is what two operators compare by voice; and the acquaintance, which carries the public key alone |
| Refusal rather than repair | a machine that already drew a secret cannot draw a second: the store refuses, so a machine cannot become a second machine wearing its name |
| Logging surface | what the terminal prints is an address, an acquaintance, a fingerprint and a count of links. No byte of a secret reaches it, and the errors carry a path, a length or a refusal |
| **Open** | the pages are not locked against swap, and the file stands on whatever disk the machine has |
| Closure path | as in `mt-store`: an encrypted disk and an encrypted swap are assumed and stated rather than implied |

## The pair this machine answers the wire with

| | |
|---|---|
| Secret material | the ML-DSA secret key, derived from the secret above under the node domain |
| Who holds it | this machine, in memory, for as long as it stands |
| Site of construction | `mt-net`, `Answering::of_machine`; its card states the handling |
| Site of destruction | the `Drop` of the key type, which wipes |
| What is shown | the public half, in the acquaintance an operator hands over and in the fingerprint |
| **Open** | as in `mt-net` |

---

## What no card here covers

The links this machine holds carry the keys of their sessions, and those stand in `mt-wire` and
`mt-net` with cards of their own. What the count of links states — how many stand and what the
ceiling is — names no peer, no address and no person, and leaves the machine only to its own
operator.
