# The security cards of a wallet

One card per bearer of secret material. This crate is a person in a terminal: the words they write
down, the seed those words stretch to, the branches it gives, and the notes they hold. Everything
here is the person, so a defect in any row is a defect in all of them at once.

---

## The words, the entropy and the seed

| | |
|---|---|
| Secret material | 32 B of entropy; the twenty-four words that carry it; the 64 B master seed and the branches drawn from it |
| Who holds them | the device the wallet runs on. Nothing of them is written to a disk by this crate and nothing is sent anywhere |
| Site of construction | `src/lib.rs`, `Person::born` and `Person::of_words` — the draw and the stretch are `mt-seed`; this crate holds what they answer with |
| Site of destruction | `Zeroizing` on the entropy, on the words, on the seed and on every branch, each wiping at the end of the scope that holds it |
| Construction copies | one of the entropy, handed back to the caller in its wrapper; one of the seed, held by `Person`; one array per payment key, wrapped |
| What is shown | the words, printed once by the terminal because a person must write them down — and printed nowhere else; and the payment key, which is public |
| Never on the command line | the words are read from the standard input and refused as an argument: `argv` is readable by every other process on the machine and is written into the history of a shell, and a secret read from either has left |
| Logging surface | the terminal prints a balance, a commitment, a position and a nullifier — all public — and the words once, on the birth that made them |
| **Open** | the pages are not locked against swap; and the words, once printed, stand in whatever the terminal of the operator keeps |
| Closure path | swap as elsewhere in this tree; what a terminal keeps is the operator, and the help text says so where a person reads it |

## The notes a wallet holds

| | |
|---|---|
| Secret material | per note: the spending half of its nullifier key, its blinding factor and the key it was paid to |
| Who holds them | the device, in the file `mt-store` keeps under the permissions of its owner alone |
| Site of construction | `Note::of`, from values a payer or a person hands in |
| Site of destruction | the bytes written to and read from the disk stand in `Zeroizing`; the notes themselves live for the length of the call that reads them |
| What is shown | `Debug` is written by hand and shows the value, the position and the commitment — never the three secrets. A derived one would print the spending half into whatever a test, a log or the message of a panic goes to |
| Comparison | the type carries no derived comparison: what names a note is its commitment, which is public, and comparing key material would compare it in a time that depends on where the first difference stands |
| Refusal rather than repair | a note whose commitment is not what its own parts derive is refused when it is entered and when the ledger is read; a second spending of one note is refused at the door rather than in a frame |
| **Open** | the notes in memory are plain structures for the length of a call and are not wiped there; the pages are not locked against swap |
| Closure path | holding the ledger in a wiping wrapper for the whole of its life costs one type and is written here rather than left to be discovered |
