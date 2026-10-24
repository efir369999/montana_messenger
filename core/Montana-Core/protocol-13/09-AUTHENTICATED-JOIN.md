# 9. Authenticate first connection and fast sync

**Status: open. No verified fresh-node-to-public-network run is claimed.**

The earlier core has snapshot handling and strengthened anchor/session binding.
The missing premise is obtaining the first trusted state. A peer cannot
authenticate its own snapshot by supplying the root against which that snapshot
is checked. Discovery, an authenticated transport peer and an authenticated
chain checkpoint are separate properties.

The native candidate binds a newly persisted directory to its exact Genesis
and refuses an unbound existing directory or one marked for another network.
Those store checks passed. They prevent accidental local cross-network reuse;
they do not authenticate remote history, establish an admitted population or
migrate existing balances.

Closure requires a clean joining node to verify history from the trusted network
beginning or an explicitly authenticated checkpoint, including the window proof
from item 1. A malicious seed must fail to substitute a private chain, invented
population, fabricated snapshot or self-declared anchor. The valid join must
produce the same canonical head and roots and remain valid after restart.

Starting an isolated container or passing a local genesis-marker test does not
meet this criterion. Kaito cannot yet be given a verified complete joining and
minting procedure on the basis of this evidence.
