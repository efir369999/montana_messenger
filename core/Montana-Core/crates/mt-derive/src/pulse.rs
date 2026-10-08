// The round of a chain: the seeds a machine's one-time keys are generated from, and the
// eligibility of a machine for a round. The set states them in `docs/Montana Canon.md`,
// "The round of a chain, in integers".
//
// Both key seeds stand under domains of their own, so the key that runs a window and the key
// that answers for a part never join; eligibility takes the answering key, the aggregate, the
// chain and the round, and nothing in that preimage is anyone's to choose.

use mt_codec::{domain, hash, size, Part};

pub fn runner_key_seed(machine_secret: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_RUNNER_KEY,
        &[Part::of(machine_secret), Part::of(&window.to_le_bytes())],
    )
}

pub fn part_key_seed(machine_secret: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_PART_KEY,
        &[Part::of(machine_secret), Part::of(&window.to_le_bytes())],
    )
}

// The chain index is one byte and the round four, little-endian: the widths are exact, and a
// wider one would make two rounds share a preimage.
//
// What the draw reads is the nullifier of the machine's part and never its one-time key. Both are
// fixed by the secret and the window rather than chosen, so neither can be ground; but only the
// nullifier is a value a circuit can speak, and the attestation of presence must assert the value
// the draw reads or a fabricator draws secrets until one clears. A key comes of a lattice key
// generation, and asserting that generation inside a proof costs orders more than the statement
// around it.
pub fn round_eligibility(
    part_nullifier: &[u8; 32],
    aggregate: &[u8; 32],
    chain: u8,
    round: u32,
) -> [u8; 32] {
    hash(
        domain::MT_ROUND_ATT,
        &[
            Part::of(part_nullifier),
            Part::of(aggregate),
            Part::of(&[chain]),
            Part::of(&round.to_le_bytes()),
        ],
    )
}

// What a proof of presence binds a one-time key by. The key enters no proof — its generation is
// the thing no circuit asserts — so what the public input carries is this digest, computed by a
// verifier from the key the attestation carries: a proof lifted from one attestation onto another
// fails at the boundary that names it.
pub fn key_digest(one_time_pk: &[u8; size::SIGNING_PUBLIC_KEY]) -> [u8; 32] {
    mt_proof::poseidon::hash_bytes(domain::MT_PART_KEY, one_time_pk).bytes()
}

// The machine standing at a point: the least commitment of the living set whose first sixteen
// bytes stand above the tag, and the least of the whole set when none does. The wrap is what makes
// the set a ring rather than a line — without it the tags above the highest commitment would have
// no holder at all.
//
// The result is a function of the tag and the cemented set alone: nothing about proximity,
// preference, load or history enters, so two sides reading one set compute one holder and a
// disagreement about the holder is a disagreement about the chain.
pub fn holder(tag: &[u8; 16], living: &[[u8; 32]]) -> Option<[u8; 32]> {
    let above = living
        .iter()
        .filter(|commitment| commitment[..16] > tag[..])
        .min();
    match above {
        Some(commitment) => Some(*commitment),
        None => living.iter().min().copied(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    const W: u64 = 1000;

    // The inputs of the vectors, each derived from a stated string. They separate nothing and
    // take no row of the registry, so they are plain SHA-256 of the literal, without the NUL.
    fn of_literal(text: &[u8]) -> [u8; 32] {
        Sha256::digest(text).into()
    }

    fn test_answering_key() -> [u8; size::SIGNING_PUBLIC_KEY] {
        let mut out = Vec::with_capacity(size::SIGNING_PUBLIC_KEY);
        for i in 0..61u32 {
            let mut block = Vec::from(&b"mt-vector-pk"[..]);
            block.extend_from_slice(&i.to_le_bytes());
            out.extend_from_slice(&Sha256::digest(&block));
        }
        out.truncate(size::SIGNING_PUBLIC_KEY);
        // PANIC-OK: the loop above writes sixty-one digests of thirty-two bytes and the width is
        // the set's own; a length other than it would mean the size of the set has moved.
        out.try_into()
            .expect("the key of the vector is of its width")
    }

    #[test]
    fn the_two_key_seeds_are_the_frozen_values_and_stand_apart() {
        // Canon, "The round, the beacon, and the chain of a sender".
        let secret = [0x77u8; 32];
        assert_eq!(
            hex(&runner_key_seed(&secret, W)),
            "2c7b73b5b598bf841cc5d6a389e78657ce7ace1b3c9b4eab3debb920854e101e"
        );
        assert_eq!(
            hex(&part_key_seed(&secret, W)),
            "23eb0952bd165b4cb0f8bb6b0e549a4e7d2d4e301802f35734b1a32eb15aaf57"
        );
        // One secret and one window: the separation is the two domains and nothing else.
        assert_ne!(runner_key_seed(&secret, W), part_key_seed(&secret, W));
        assert_ne!(runner_key_seed(&secret, W), runner_key_seed(&secret, W + 1));
    }

    #[test]
    fn the_inputs_of_the_vectors_are_the_frozen_ones() {
        // The strings separate nothing, so they are hashed bare — an implementation applying
        // the NUL of the primitive to them reproduces none of the table.
        assert_eq!(
            hex(&of_literal(b"mt-vector-machine")),
            "569c721ea193dc9fbffa78d938a8eac29af86dcc6c1f40e6fe5c450120a308fd"
        );
        assert_eq!(
            hex(&of_literal(b"mt-vector-aggregate")),
            "5794ec157270d5c8364ca9aead3d4cbef0fbd714297077ea029111b127781dca"
        );
        assert_eq!(
            hex(&of_literal(b"mt-vector-prev-beacon")),
            "e7b1b25222707aca10af6a07b6adceb4c6fc7580bdbe965cddf82ad8133f5c7f"
        );
        let key = test_answering_key();
        assert_eq!(key.len(), 1_952);
        assert_eq!(
            hex(&Sha256::digest(key)),
            "53d0417583a05cfdced15d3dcfbfa0657fddc860ed59c2c86638c38cda1be245"
        );
    }

    #[test]
    fn the_eligibility_of_a_round_is_the_frozen_value() {
        // Canon, "The round, the beacon, and the chain of a sender". What the draw reads is the
        // nullifier of the machine's part. The named wrong implementation: one reading the one-time
        // key, which no circuit can assert — so the value the draw reads would stand bound to no
        // admitted machine, and a fabricator would draw secrets until one of them clears.
        let part = crate::nullifier::part(&of_literal(b"mt-vector-machine"), W)
            .expect("a half of the family");
        assert_eq!(
            hex(&round_eligibility(
                &part,
                &of_literal(b"mt-vector-aggregate"),
                0,
                7
            )),
            "0a1509175bb9075e37f0b7d0f06620240ef424ef8c6f60f8a18a624424b3bc05"
        );
    }

    #[test]
    fn the_digest_a_proof_binds_a_one_time_key_by_is_the_frozen_value() {
        // Canon, "The round of a chain, in integers": the key enters no proof, and this is what the
        // public input of a presence carries in its place.
        assert_eq!(
            hex(&key_digest(&test_answering_key())),
            "720e87ab3f36f6812351e148fb55999e5049f6f8250982b3e27431699b9014c6"
        );
        // One byte of the key moved yields another digest, which is what stops a proof of presence
        // from being lifted from one attestation onto another.
        let mut moved = test_answering_key();
        moved[0] ^= 1;
        assert_ne!(key_digest(&moved), key_digest(&test_answering_key()));
    }

    #[test]
    fn the_widths_of_the_chain_and_the_round_are_exact() {
        let key = crate::nullifier::part(&of_literal(b"mt-vector-machine"), W)
            .expect("a half of the family");
        let agg = of_literal(b"mt-vector-aggregate");
        let held = round_eligibility(&key, &agg, 0, 7);
        // The named wrong implementation: the round written in eight bytes, or the chain in
        // four. Each yields a value the set does not hold.
        let wide_round = mt_codec::hash(
            domain::MT_ROUND_ATT,
            &[
                Part::of(&key),
                Part::of(&agg),
                Part::of(&[0u8]),
                Part::of(&(7u64).to_le_bytes()),
            ],
        );
        let wide_chain = mt_codec::hash(
            domain::MT_ROUND_ATT,
            &[
                Part::of(&key),
                Part::of(&agg),
                Part::of(&(0u32).to_le_bytes()),
                Part::of(&(7u32).to_le_bytes()),
            ],
        );
        assert_ne!(wide_round, held);
        assert_ne!(wide_chain, held);
        // And two rounds of one chain never agree.
        assert_ne!(held, round_eligibility(&key, &agg, 0, 8));
        assert_ne!(held, round_eligibility(&key, &agg, 1, 7));
    }

    #[test]
    fn the_holder_of_a_tag_is_the_frozen_one_and_the_ring_wraps() {
        // Canon, "The holder of a tag".
        let living = [[0x10u8; 32], [0x40u8; 32], [0x90u8; 32], [0xf0u8; 32]];
        let tag: [u8; 16] = {
            let mut out = [0u8; 16];
            for (slot, byte) in out.iter_mut().zip(
                [
                    0x45, 0x46, 0x8c, 0xdd, 0x9b, 0xcd, 0xeb, 0xe6, 0xf6, 0x22, 0xc4, 0x62, 0x57,
                    0xc2, 0x7f, 0xe3,
                ]
                .iter(),
            ) {
                *slot = *byte;
            }
            out
        };
        assert_eq!(super::holder(&tag, &living), Some([0x90u8; 32]));
        // The wrap: above the highest commitment the ring closes onto the least.
        assert_eq!(super::holder(&[0xffu8; 16], &living), Some([0x10u8; 32]));
        // An empty set holds nobody, and the answer is nothing rather than a choice.
        assert_eq!(super::holder(&tag, &[]), None);
        // The order the set was seen in carries nothing.
        let reversed = [[0xf0u8; 32], [0x90u8; 32], [0x40u8; 32], [0x10u8; 32]];
        assert_eq!(super::holder(&tag, &living), super::holder(&tag, &reversed));
    }
}
