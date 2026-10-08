// Every layout of Montana and the state its objects live in. The set states the layouts in
// `docs/Montana Canon.md`, "Layouts", the identifier of a signed object in "Rules for a signed
// object", and the six roots and the Genesis State Hash beside the parameters of the Decree.
//
// Two rules govern everything here and are worth stating once. **A length is a comparison, not a
// parse:** every object of a fixed width is refused by its length before a byte of it is read, so a
// malformed object costs one comparison and reaches no field. **An identifier is taken over signed
// scope and never over the wire bytes:** it does not move when an object is re-signed, and the
// signature is what signed scope leaves out.
//
// Nothing here awaits the artifact the set binds by `air_hash`. The slot of the out-of-domain
// evaluations of a proof covers the bound of the trace width rather than following the width, so
// the length of a proof is frozen and every total it enters is frozen with it.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod layout;
pub mod tables;

pub use layout::{Layout, ObjectError};

use mt_codec::{hash_of_one, Domain};

// The length of a proof, and the width of the commitment that carries standing. Both stand in the
// set, both are frozen, and the gate recomputes the first from the parts the set fixes.
mt_codec::constants! {
    PROOF_AND_COMMITMENT:
    pub const PROOF_LEN: usize = 210_968, writes "| `PROOF_LEN` | 210 968 B |";
    /// The length of a proof of the presence, at the presence's own height: the one description a
    /// machine proves every window is priced by its own statement, not by the tallest.
    pub const PRESENCE_PROOF_LEN: usize = 174_072, writes "| `PRESENCE_PROOF_LEN` | 174 072 B |";
    pub const WEIGHT_COMMIT_BYTES: usize = 6_144, writes "weight_commit_bytes        = n x d x 4 = 6 144 B";
    /// The deterministic fields of a proposal: everything before the ticket proof. The identifier
    /// of a proposal is taken over exactly these bytes, because the name is what an attestation
    /// attests and what separates two clearings of one height — and a name over proof bytes is a
    /// name its maker redraws by reproving.
    pub const PROPOSAL_DETERMINISTIC_LEN: usize = 2_222, writes "proposal_id = SHA-256(\"mt-proposal\" || 0x00 || serialize(proposal)[0 .. 2 222])";
}

// The identifier of a signed object: taken from signed scope under the class domain of the object,
// never from the wire bytes. It is of the crate and not of the world, and that is the whole point:
// a door taking a class and any bytes at all is a door through which an identifier can be computed
// over the wire form of an object, signature and all. Every identifier of this tree is therefore
// reached through the layout that states its own scope, and the class travels with the object
// rather than beside it.
pub(crate) fn identifier(class: Domain, signed_scope: &[u8]) -> [u8; 32] {
    hash_of_one(class, signed_scope)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    use mt_codec::domain;

    #[test]
    fn an_identifier_does_not_move_when_an_object_is_re_signed() {
        // Signed scope is every byte but the signature, so two signatures over one scope yield one
        // identifier — which is the whole reason the rule reads scope and not the wire.
        let scope = b"the bytes of an object without its signature";
        assert_eq!(
            identifier(domain::MT_PROPOSAL, scope),
            identifier(domain::MT_PROPOSAL, scope)
        );
        assert_ne!(
            identifier(domain::MT_PROPOSAL, scope),
            identifier(domain::MT_OP, scope)
        );
    }

    #[test]
    fn the_identifier_of_a_node_of_the_fold_is_the_frozen_value() {
        // Canon, "The vector of the node's identifier": there being no signature to exclude, the
        // identifier is taken over the whole of the canonical bytes.
        let mut bytes = Vec::with_capacity(32 + 32 + WEIGHT_COMMIT_BYTES + PROOF_LEN);
        bytes.extend_from_slice(&[0xABu8; 32]);
        bytes.extend_from_slice(&[0xCDu8; 32]);
        bytes.extend_from_slice(&[0x11u8; WEIGHT_COMMIT_BYTES]);
        bytes.extend_from_slice(&vec![0x00u8; PROOF_LEN]);
        // The value of this identifier lives in the set, and the gate compares the code against it
        // there. What is checked here is the rule the value stands on: the whole of the bytes goes
        // in, so moving the last of them moves the identifier.
        assert_eq!(
            identifier(domain::MT_FOLD_NODE, &bytes),
            hash_of_one(domain::MT_FOLD_NODE, &bytes)
        );
        let mut moved = bytes.clone();
        let last = moved.len() - 1;
        moved[last] ^= 0x01;
        assert_ne!(
            hex(&identifier(domain::MT_FOLD_NODE, &bytes)),
            hex(&identifier(domain::MT_FOLD_NODE, &moved)),
            "the last byte of a node stands outside its identifier"
        );
    }
}
