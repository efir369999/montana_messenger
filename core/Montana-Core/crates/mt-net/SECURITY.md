# The security cards of the socket under the wire

One card per bearer of secret material. This crate adds the socket underneath `mt-wire` and the
order of reading above it; the keys it holds are the pair a machine answers the wire with and the
two directional keys of a session.

---

## The pair a machine answers with

| | |
|---|---|
| Secret material | the ML-DSA secret key of this machine, derived from the machine own secret and from nothing else |
| Who holds it | the machine, in its own memory, for as long as it stands |
| Site of construction | `src/lib.rs`, `Answering::of_machine` — the expansion is `mt-seed`, and the seed it hands to the scheme stands in `Zeroizing` and never leaves the function |
| Site of destruction | the `Drop` of `mt_suite::sign::SecretKey`, which wipes |
| Construction copies | one seed, wiped at the end of the function; the key itself is moved into the pair and never copied |
| What is shown | the public half alone, through `public()`. There is no door to the secret half, and the type carries no `Debug` of it |
| Comparison | none: nothing of this crate compares key material |
| Logging surface | a search of the crate returns no `println!`; the errors it answers with name a socket, a length or a refusal and never a byte of a key |
| **Open** | the pages holding the key are not locked against swap |
| Closure path | as in the suite: `mlock` asks for `unsafe`, which this crate forbids at its head, or a dependency that carries it; until then **an encrypted swap is assumed and stated** |

## The two directional keys of a session

| | |
|---|---|
| Secret material | two 32 B keys and the transcript, held inside `mt_wire::handshake::Channel` |
| Who holds it | the two machines of that link, each in its own memory, for the life of the link |
| Site of construction | `mt-wire`, from the two shared secrets and the transcript; this crate holds the channel and never rebuilds it |
| Site of destruction | the `Drop` of `Channel`, which wipes both keys and the transcript |
| Construction copies | one copy of the sending or receiving key per message, on the stack of `send` or `receive`, for the length of one call |
| What is shown | the transcript alone, which is public by design and is what two sides compare to know they reached one channel |
| Comparison | none of key material |
| **Open** | the copy a message makes of its directional key is a plain array on the stack and is not wiped when the call returns; the pages are not locked against swap |
| Closure path | the copy exists because the sealing door takes a key by reference and the borrow of the channel would otherwise stand across the call; holding it in a wiping wrapper closes it and costs nothing, and it is written here so a reader does not discover it instead |
