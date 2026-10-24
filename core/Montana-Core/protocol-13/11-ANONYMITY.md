# 11. Protect operator identity and origin

**Status: open. Total anonymity is required and has not been established.**

At public baseline `6303fa5fbbb5ad93e4d7dd3dcc699693fb10e002`,
`core/Montana-Core/crates/mt-wire/src/handshake.rs` includes an answering public
key in `Hello` and `HelloAnswer`. The node derives its answering identity from
its machine secret and its acquaintance contains a dialable address and key.
Separating a device key from a person's seed does not make the device unlinkable.
Transport encryption does not by itself conceal the network origin from peers.

No complete anonymity proof or externally observed anonymous joining/minting
run is available. DNS, protected entry points, direct origin reachability,
traffic correlation, persistent identities, logs, public history and resource/
replay limits still require a coherent transport construction and verification.
Removing a current address does not undo historical disclosure.

Closure must specify and satisfy the adversary model without weakening the
author's required property. It needs evidence for bootstrap, node traffic,
client operation, synchronization, minting and restart. Application-controlled
disclosures and transport origins must both be addressed. Unsupported absolute
anonymity claims must not be published as achieved facts.

No private endpoint, key, credential, recovery material or user traffic is
included in these reports. A public reproducibility package must preserve that
boundary while providing synthetic cases and exact source revisions.
