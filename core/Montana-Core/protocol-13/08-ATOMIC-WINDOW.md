# 8. Apply and persist a complete window atomically

**Status: open; native value-state and storage prerequisites were repaired.**

In the unpublished candidate, note append validates the entire batch before
mutation. `State::apply` reserves and validates fallible operations before
publishing notes and spent/rate nullifiers. The node persists a candidate value
state before exposing it in memory. Checked encoding rejects invalid counts
and overflow; decoding rejects duplicate and noncanonical stored sets.

The store uses exclusive private temporary files, durable publication and
exclusive identity creation. A directory-sync failure after rename is reported
as an uncertain commit, with the complete newly visible state retained; it is
not falsely described as rollback. Selected server tests cover malformed state,
failed persistence, symlink refusal and concurrent identity/signing choices.
Test data was retained.

These repairs do not form a complete window transaction. Proposal, proof,
transition tables and closed head still need one authenticated, crash-consistent
commit in both generations. The native live path has no canonical Proposal to
include in that transaction yet.

Closure requires deliberate failure at each persistence boundary followed by
restart: recover exactly the previous or complete next window, never mixed
tables/head/archive. Reapplying the same window must not issue twice. Historical
state migration must itself be authenticated and may not import balances simply
because their bytes decode under a new network identifier.
