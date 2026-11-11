// The derivations of Montana: what a person and a machine compute from a secret and publish
// instead of it. The set states every one of them in `docs/Montana Canon.md` — the note, the
// nullifiers, the naming of a slot, the slot of a channel and its head, the tags and the points,
// the commitment standing for a machine, the fingerprint compared out of band, the identifier of
// an application — and this is their one transcription.
//
// Two families of hash stand behind these: the domain-separated primitive and the auxiliary
// compositions over it, both in `mt-codec`. Nothing here invents a domain, a length or a
// parameter: domains come from the registry, lengths from the sizes of the set, parameters from
// `mt-genesis`.
//
// Inputs remain borrowed. Most outputs are public derivations; private key seeds
// and the weight blind must stay on the machine. The latter is returned in a
// wiping wrapper, since publishing it would open the commitment it masks.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod aggregate;
pub mod delivery;
pub mod fingerprint;
pub mod name;
pub mod note;
pub mod nullifier;
pub mod pulse;
pub mod tag;

use mt_codec::{domain, hash, hash_of_one, size, Part};

// The commitment standing for a machine: what a signer set aggregates over and what the ordering
// of known machines runs on. It names neither an owner, an address nor a person.
// Every part of this preimage is of a width the set fixes, so the concatenation is
// self-delimiting by its types: no two different triples share one preimage, and no caller can
// make them share one by handing a key of another length.
pub fn node_commit(
    answering_pk: &[u8; size::SIGNING_PUBLIC_KEY],
    suite_id: u16,
    blind: &[u8; 32],
) -> [u8; 32] {
    hash(
        domain::MT_NODE_COMMIT,
        &[
            Part::of(answering_pk),
            Part::of(&suite_id.to_le_bytes()),
            Part::of(blind),
        ],
    )
}

// The identifier of an application, over the bytes of its name as its author writes them.
pub fn app_id(name: &[u8]) -> [u8; 32] {
    hash_of_one(domain::MT_APP, name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn the_commitment_standing_for_a_machine_is_the_frozen_value() {
        // Canon, "The commitment standing for a machine".
        assert_eq!(
            hex(&node_commit(
                &[0xA1u8; size::SIGNING_PUBLIC_KEY],
                1,
                &[0xB2u8; 32]
            )),
            "08e640011db3702bb5ea5f1a3ea6aa62d7aa274b4acfcada27346e093d60fdc5"
        );
    }

    #[test]
    fn the_three_inputs_of_that_commitment_appear_in_one_order_and_no_other() {
        // The set: a commitment computed from any other order is a different value.
        let straight = node_commit(&[0xA1u8; size::SIGNING_PUBLIC_KEY], 1, &[0xB2u8; 32]);
        let swapped = hash(
            domain::MT_NODE_COMMIT,
            &[
                Part::of(&[0xB2u8; 32]),
                Part::of(&1u16.to_le_bytes()),
                Part::of(&[0xA1u8; size::SIGNING_PUBLIC_KEY]),
            ],
        );
        assert_ne!(straight, swapped);
    }

    #[test]
    fn the_identifier_of_an_application_is_the_frozen_value() {
        // Canon, "The nullifier of a part, and the identifier of an application".
        assert_eq!(
            hex(&app_id(b"montana")),
            "a3ededc374700026f1f872bebf3ba0199103f4082ea609688f82e69e64fa8a82"
        );
    }
}
