# The security cards of what a machine keeps

One card per bearer of secret material, filled before the bearer is called closed. This crate puts
bytes on a disk and takes them back, so what its cards state is the one thing a reader cannot check
by reading the protocol: what stands on the disk, who may read it, and what the bytes pass through
on the way.

---

## The secret a machine draws for itself

| | |
|---|---|
| Secret material | 32 B, the root every key of this machine is derived from |
| Who holds it | the device that drew it, in a file of its own directory. Nothing of it is sent anywhere by this crate |
| Site of construction | not here: the crate is handed a block already drawn, and it refuses a second drawing rather than overwriting the first |
| Site of destruction | `Zeroizing` on the way in and on the way out — the bytes of the file land in one allocation and that allocation is the wrapper that wipes |
| Construction copies | one: the allocation the file is read into, moved into the wrapper before anything else sees it, and one array of the width the caller asked for |
| Permissions | the file is created with the permissions of its owner alone **before a byte of it is written**, and the permissions are given to the path again so a temporary left by an earlier run cannot carry wider ones into this one. Closing a file after the write would leave a window in which the secret stands readable to everyone on that machine, and a window of that kind is not smaller for being brief |
| Refusal rather than repair | a second drawing is refused with `SecretStands`; a file of the wrong width is refused before it is read |
| Logging surface | a search of the crate returns no `println!` and no `Debug` over a secret; the errors it answers with carry a path and a length and never a byte of a value |
| **Open** | the pages holding the secret are not locked against swap, and the file itself stands on whatever the disk of the machine is |
| Closure path | `mlock` asks for either `unsafe`, which this crate forbids at its head, or a dependency that carries it; until one of the two is taken the assumption is stated rather than implied: **a machine bearing a secret is expected to hold an encrypted disk and an encrypted swap** |

## What a person holds — the ledger of notes

| | |
|---|---|
| Secret material | the bytes of a wallet ledger: every note it holds with the half of the key that spends it |
| Who holds it | the device the wallet runs on, in a file of the same directory and under the same permissions as the secret above — a note names its owner to whoever reads it |
| Site of construction | not here: the crate is handed bytes and hands them back |
| Site of destruction | `Zeroizing` on the way out; the caller hands in what it wrote and wipes it on its own side |
| Construction copies | one allocation, wiped when the wrapper it stands in drops |
| Logging surface | as above |
| **Open** | as above: swap and disk |
| Closure path | as above |

---

## What no card here covers

What the bytes **mean** is not this crate's: a secret is a secret because the crate that drew it
says so, and a ledger is secret because the wallet that wrote it says so. What these cards state is
that this crate treats both as what they are on the way to a disk and back.
