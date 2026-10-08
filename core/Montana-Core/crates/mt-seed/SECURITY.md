# The security cards of a birth

One card per bearer of secret material, filled before the bearer is called closed. What a card
states is what an auditor would otherwise have to derive by reading: where a secret is built,
where it is destroyed, how many copies exist on the way, what is shown of it, and what remains
open with the path that closes it.

This crate holds the root of a person. Everything below it — the ten branches, the keys they
seed, the notes they spend and the names they claim — is a function of the thirty-two bytes the
first card names, so a defect here is a defect of every one of them at once. The cards state the
code as it stands, read at the lines named.

---

## The entropy of a birth — the thirty-two bytes a person comes from

| | |
|---|---|
| Secret material | the mixed block, 32 B; the samples of six sources on the way to it |
| Who holds it | the device that drew it, in its own memory. Every source is read on that device and no byte of any of them is sent anywhere by this crate |
| Site of construction | `src/lib.rs`, `born_of` — the samples are drawn by `sources::draw`, measured, and mixed by `Draw::mix` |
| Site of destruction | `Zeroizing`, which wipes at the end of the scope holding it: the samples inside `Draw`, the block inside `Birth`, and every intermediate of the mixing |
| Construction copies | the samples of each source once, and the mixed block once. The mixing takes the samples by reference and the door that yields a block is of the crate |
| What a person is shown | the measure of every source and the count of the living. `Birth` carries the block itself in `Zeroizing` and no measure carries a byte of any source |
| Refusal rather than repair | four health tests and a self-test stand before a block becomes anyone: a run of eight, a value over twelve of thirty-two, fewer than eight distinct values, a block equal to the one this machine last bore, a degenerate mixing, or timings that repeat between two draws — each answers with `Err` and no block. A broken machine is answered by refusal because a root drawn on one looks ordinary and is guessable, and nothing later reveals that |
| The block last born | held in a `Mutex` of the module so the continuous test runs on the path a wallet takes, rather than only when a caller remembers to hand in the previous block — and held there **inside `Zeroizing`**, because a copy standing in a static for the life of a process is the one copy nothing else would ever wipe |
| Branching on secret bytes | the health tests read the block and branch on it. They run before it is anyone's root and their answer is a refusal, not a value, so what a timing of them would leak is whether a draw was refused — which the caller is told outright |
| Logging surface | a search of the crate returns no `println!` and no `Debug` over a block, a sample or a seed as of this commit |
| **Open** | the pages holding the block are not locked against swap |
| Closure path | as for the suite: `mlock` asks for either `unsafe`, which this crate forbids at its head, or a dependency that carries it. Until one of the two is taken the assumption is stated rather than implied: **a machine bearing a person is expected to hold an encrypted swap** (FileVault, LUKS or the equivalent), and a person born on a machine whose swap is in the clear has their root written to a disk they did not intend |

## The master seed and the ten branches

| | |
|---|---|
| Secret material | the master seed, 64 B; ten branch secrets, 32 B each and 64 B for the branch of encryption |
| Who holds them | the device that stretched them. The stretch takes the entropy and never the text of the words, so nothing about how a phrase is typed can move a derived byte, and the same words on another device answer with the same values |
| Site of construction | `src/lib.rs`, `master_seed` and `branch` |
| Site of destruction | `Zeroizing` on both returns, wiping at the end of the caller's scope |
| Construction copies | the stretch holds one accumulator and one block, both wiped by `mt-codec`'s own doors; the expansion holds one block per round and wipes the previous |
| Cost of the stretch | a million compressions of SHA-256, the count a row of the register holds and the gate compares |
| Separation of the branches | each branch is the expansion of its own domain of the registry, and the tests hold that the ten stand apart and at the lengths the set states. A machine's answering key stands on the machine's own secret and is no branch of any person |
| Branching on secret bytes | none in this crate: the stretch and the expansion are the compositions of `mt-codec`, and what this crate adds is the choice of domain and length |
| Logging surface | as above: a search of the crate returns nothing over a seed or a branch as of this commit |
| **Open** | the pages holding the seed and the branches are not locked against swap; and a caller who copies a branch out of its `Zeroizing` holds a copy this crate cannot wipe |
| Closure path | swap as above. The copy is the caller's to hold or to avoid: the doors answer with a wiping wrapper, and a caller who moves the bytes out of it takes the wiping with them |

---

## What no card here covers

The compositions themselves — HMAC, HKDF-Expand and PBKDF2 over SHA-256 — are `mt-codec`'s, and
their handling of what passes through them is stated where they are written. What these cards
state is how **this** code handles what a machine hands it and what those compositions return.
