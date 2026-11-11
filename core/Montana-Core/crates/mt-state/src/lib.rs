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

// The lengths of the two proofs, and the width of the fields of a proposal the window decides. All
// stand in the set, all are frozen, and the gate recomputes the lengths from the parts the set fixes.
mt_codec::constants! {
    PROOF_AND_COMMITMENT:
    pub const PROOF_LEN: usize = 404_576, writes "| `PROOF_LEN` | 404 576 B |";
    /// The length of a proof of the presence, at the presence's own height: the one description a
    /// machine proves every window is priced by its own statement, not by the tallest. The ticket
    /// stands at the same height, so the proof a proposal carries is of this length as well.
    pub const PRESENCE_PROOF_LEN: usize = 333_888, writes "| `PRESENCE_PROOF_LEN` | 333 888 B |";
    /// The fields of a proposal the window decides: everything from the height through the suite,
    /// the census of the standing among them. The identifier of a proposal is taken over exactly
    /// these bytes, because the name is what an attestation attests — and a name over proof bytes
    /// is a name its maker redraws by reproving, while a name over the final beacon or the runner's
    /// key is one name per branch or per runner of a single decision.
    pub const PROPOSAL_DECIDED_LEN: usize = 750, writes "proposal_id = SHA-256(\"mt-proposal\" || 0x00 || serialize(proposal)[0 .. 750])";
}

// The one value of the agreement the set writes as a number: what the `since` of a pledge holds
// where it stands on no quorum. No attempt takes it, since a pledge made in an attempt of that
// number is refused where it is read.
mt_codec::constants! {
    AGREEMENT:
    pub const STANDS_ON_NONE: u32 = 0xFFFF_FFFF, writes "or 0xFFFFFFFF for none";
}

// The rules this tree implements. The Constitution has every machine publish the version its own
// software implements, so the set holds no value of it and the place of this one is the code.
mt_codec::constants! {
    RULES:
    pub const PROTOCOL_VERSION: u32 = 0x0001_0000, code "the rules this tree implements, major one in the upper sixteen bits and minor zero in the lower: the Constitution has every machine state its own version, so the set holds none";
}

// The major component of the rules this tree implements: a proposal under a larger one is refused.
pub fn implemented_major() -> u16 {
    (PROTOCOL_VERSION >> 16) as u16
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
}
