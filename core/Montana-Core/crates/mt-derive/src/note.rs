// The derivations of a note. The set states them in `docs/Montana Canon.md`, "The derivations of
// a note": the payment key from the payment secret in SHA-256, and — of the proof hash family,
// because a frame proves every one of them inside its circuit — the public half of the nullifier
// key, the commitment over the amount, that key, that half and a fresh blinding factor, and the
// nullifier over the redemption branch, the commitment and the position of the leaf.
//
// **One key, one absorption, two halves.** The sponge takes the key once and is squeezed twice:
// the first block is the half that spends and the second the half that names. The commitment binds
// the naming half; the nullifier takes the spending half. Two derivations over one preimage would
// read the same secret twice, and a circuit reading a secret twice is a circuit where the two
// readings may differ — nothing in an arithmetic of rows ties a value at one row to a value forty
// blocks on unless a column carries it. Here there is one place the key enters and the second half
// is what the state became, so a spender cannot present a nullifier under a key the commitment
// does not name: one note has one nullifier, and a second spending collides with the first.

use mt_codec::{domain, hash, Part};
use mt_proof::poseidon;

pub fn note_pk(note_sk: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NOTE_PK, &[Part::of(note_sk)])
}

// The two halves of a nullifier key, from the one absorption of it: the half that spends and the
// half that names, in that order. Of the proof hash family, since a redemption proves both.
pub fn halves(nf_key: &[u8; 32]) -> ([u8; 32], [u8; 32]) {
    let (spending, naming) = poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, nf_key);
    (spending.bytes(), naming.bytes())
}

// The half a note binds, so that the key alone can spend it.
pub fn nf_pk(nf_key: &[u8; 32]) -> [u8; 32] {
    halves(nf_key).1
}

// The half a nullifier is taken under, which no one holding a note's commitment can derive.
pub fn nf_sk(nf_key: &[u8; 32]) -> [u8; 32] {
    halves(nf_key).0
}

// A digest of the family re-enters an absorption as its four words — `cells(x)` of the set —
// and bytes that are not one are refused here, at the door, rather than absorbed as limbs.
fn cells(bytes: &[u8; 32]) -> Option<[mt_proof::field::F; 4]> {
    Some(*poseidon::Digest::of_bytes(bytes)?.elements())
}

// `value` is an unsigned sixteen-byte little-endian amount and `rcm` a blinding factor drawn
// afresh for every note: a repeated one makes two commitments comparable. The answer is nothing
// where `nf_pk` is not a digest of the family, because no note binds such a half.
pub fn commitment(
    value: u128,
    note_pk: &[u8; 32],
    nf_pk: &[u8; 32],
    rcm: &[u8; 32],
) -> Option<[u8; 32]> {
    let mut elements = Vec::with_capacity(4 + 4 + 8 + 8);
    elements.extend_from_slice(&cells(nf_pk)?);
    elements.extend_from_slice(&poseidon::limbs_of(&value.to_le_bytes()));
    elements.extend_from_slice(&poseidon::limbs_of(note_pk));
    elements.extend_from_slice(&poseidon::limbs_of(rcm));
    Some(poseidon::hash_elements(domain::MT_NOTE_CM, &elements).bytes())
}

// The position of the leaf enters, and never a value the sender chose: one commitment at two
// positions yields two unrelated nullifiers, which is what keeps a sender from making a
// recipient's note unspendable.
pub fn nullifier(nf_key: &[u8; 32], commitment: &[u8; 32], position: u64) -> Option<[u8; 32]> {
    let mut elements = Vec::with_capacity(4 + 4 + 1);
    elements.extend_from_slice(&cells(commitment)?);
    elements.extend_from_slice(&cells(&nf_sk(nf_key))?);
    // The position as one element, for the reason the amount is one: one encoding, one nullifier.
    elements.push(mt_proof::field::F::try_from_u64(position)?);
    Some(poseidon::hash_elements(domain::MT_NOTE_NF, &elements).bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_codec::Part;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn the_vector_inputs() -> ([u8; 32], [u8; 32]) {
        (nf_pk(&[0x33u8; 32]), [0x88u8; 32])
    }

    #[test]
    fn the_derivations_of_a_note_are_the_frozen_values() {
        // Canon, "An empty note tree, and the same tree after one commitment" and "A nullifier,
        // and its independence from the commitment". Reproduced by an independent computation
        // outside this tree before they were written here. The named wrong implementations: one
        // still deriving in SHA-256 reproduces none of them; one absorbing big-endian limbs, or
        // limbs of another width, moves every value below; and one taking the naming half where
        // the set takes the spending one — the first squeeze where the second stands — reproduces
        // the commitment and parts from the tree at the nullifier, which is the whole of what the
        // two squeezes are for.
        let (pk_of_nf, rcm) = the_vector_inputs();
        assert_eq!(
            hex(&pk_of_nf),
            "011f0770c754d876439c2514399f5f19a82135825388b0aac90b3706b5ccfe14"
        );
        let cm = commitment(5_000_000_000, &[0x22u8; 32], &pk_of_nf, &rcm).expect("a real half");
        assert_eq!(
            hex(&cm),
            "8b3e18e90778fd34db944685f6a88427f98d5f416722152d6dae9418bf2ae94d"
        );
        assert_eq!(
            hex(&nullifier(&[0x33u8; 32], &cm, 0).expect("a real commitment")),
            "cab435f7a7c58a35181ef636557f3e44e18a0e757f05eed554b5b0744ebac73e"
        );
        assert_eq!(
            hex(&nullifier(&[0x33u8; 32], &cm, 7).expect("a real commitment")),
            "0c11b79ba4ee91b2686b63d266dd21ab36258f45954193d74f5f40dc79ab4b79"
        );
        // And the derivation that stayed SHA-256 answers nothing like the sponge: the two
        // families part on every value, which is what the boundary of the primitives buys.
        assert_ne!(
            pk_of_nf,
            mt_codec::hash(domain::MT_KEY_HALVES, &[Part::of(&[0x33u8; 32])])
        );
    }

    #[test]
    fn the_nullifier_takes_the_half_the_commitment_does_not_name() {
        // The two halves are two values, and which of them each derivation takes is the whole of
        // the closure: a commitment names the second, a nullifier takes the first. An
        // implementation that took the naming half for both would let anyone holding a note's
        // commitment and its half compute the nullifier — that is, let a payer burn what they
        // paid — and this vector refuses exactly that implementation.
        let key = [0x33u8; 32];
        let (spending, naming) = halves(&key);
        assert_ne!(spending, naming);
        assert_eq!(naming, nf_pk(&key));
        assert_eq!(spending, nf_sk(&key));

        let (pk_of_nf, rcm) = the_vector_inputs();
        let cm = commitment(5_000_000_000, &[0x22u8; 32], &pk_of_nf, &rcm).expect("a real half");
        let mut elements = Vec::new();
        elements.extend_from_slice(&cells(&cm).expect("a real commitment"));
        elements.extend_from_slice(&cells(&naming).expect("a real half"));
        elements.extend_from_slice(&poseidon::limbs_of(&0u64.to_le_bytes()));
        let under_the_naming_half = poseidon::hash_elements(domain::MT_NOTE_NF, &elements).bytes();
        assert_ne!(
            under_the_naming_half,
            nullifier(&key, &cm, 0).expect("a real commitment")
        );
    }

    #[test]
    fn one_commitment_at_two_positions_yields_two_unrelated_nullifiers() {
        let (pk_of_nf, rcm) = the_vector_inputs();
        let cm = commitment(5_000_000_000, &[0x22u8; 32], &pk_of_nf, &rcm).expect("a real half");
        let key = [0x33u8; 32];
        let mut seen: Vec<[u8; 32]> = (0..64)
            .map(|p| nullifier(&key, &cm, p).expect("a real commitment"))
            .collect();
        let before = seen.len();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(before, seen.len());
    }

    #[test]
    fn the_commitment_binds_the_half_of_the_nullifier_key() {
        // The double-spend closure: two halves give two commitments, so the note names the one
        // half whose secret can spend it, and a spender cannot substitute a half of their own.
        let (pk_of_nf, rcm) = the_vector_inputs();
        let other_half = nf_pk(&[0x34u8; 32]);
        assert_ne!(
            commitment(7, &[0x22u8; 32], &pk_of_nf, &rcm).expect("a real half"),
            commitment(7, &[0x22u8; 32], &other_half, &rcm).expect("a real half")
        );
        // And a half that is no digest of the family binds nothing: the door refuses it.
        assert_eq!(commitment(7, &[0x22u8; 32], &[0xFFu8; 32], &rcm), None);
        assert_eq!(nullifier(&[0x33u8; 32], &[0xFFu8; 32], 0), None);
    }

    #[test]
    fn the_widths_of_the_amount_and_the_position_are_exact() {
        // A differently sized amount yields a different digest: eight bytes absorbed where the
        // set says sixteen shifts every limb after it.
        let (pk_of_nf, rcm) = the_vector_inputs();
        let sixteen = commitment(1, &[0x22u8; 32], &pk_of_nf, &rcm).expect("a real half");
        let mut elements = Vec::new();
        elements.extend_from_slice(
            mt_proof::poseidon::Digest::of_bytes(&pk_of_nf)
                .expect("a real half")
                .elements(),
        );
        elements.extend_from_slice(&mt_proof::poseidon::limbs_of(&1u64.to_le_bytes()));
        elements.extend_from_slice(&mt_proof::poseidon::limbs_of(&[0x22u8; 32]));
        elements.extend_from_slice(&mt_proof::poseidon::limbs_of(&rcm));
        let eight = mt_proof::poseidon::hash_elements(domain::MT_NOTE_CM, &elements).bytes();
        assert_ne!(sixteen, eight);
    }

    #[test]
    fn a_fresh_blinding_factor_makes_two_notes_of_one_amount_incomparable() {
        let (pk_of_nf, _) = the_vector_inputs();
        let a = commitment(7, &[0x22u8; 32], &pk_of_nf, &[0x01u8; 32]).expect("a real half");
        let b = commitment(7, &[0x22u8; 32], &pk_of_nf, &[0x02u8; 32]).expect("a real half");
        assert_ne!(a, b);
    }

    #[test]
    fn the_payment_key_stands_apart_from_the_secret_it_comes_from() {
        let secret = [0x44u8; 32];
        assert_ne!(note_pk(&secret)[..], secret[..]);
    }
}
