// Generates candidate vectors of the relation of a window from the owning implementation: the
// ticket of the orders block, the two key digests, the beacon and the round nullifier of the pulse
// block, and the proposal of the layouts block. This does not approve them: mt-conformance compares
// the published Canon values on the subsequent test/build.
use mt_state::Layout;
use sha2::{Digest, Sha256};

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn main() {
    let window = 1_000u64;

    // The aggregate, the ticket and the two orders.
    let cemented = [[0x10u8; 32], [0x40u8; 32]];
    let aggregate =
        mt_derive::aggregate::aggregate(&cemented, window).expect("two distinct members");
    let ticket = mt_derive::aggregate::ticket(&[0x77u8; 32], &aggregate)
        .expect("the secret of the vector yields a half of the family");
    println!("ticket = {}", hex(&ticket));

    // The round, the beacon, and the chain of a sender.
    let vector_secret: [u8; 32] = Sha256::digest(b"mt-vector-machine").into();
    let vector_aggregate: [u8; 32] = Sha256::digest(b"mt-vector-aggregate").into();
    let previous: [u8; 32] = Sha256::digest(b"mt-vector-prev-beacon").into();
    let mut key = Vec::with_capacity(mt_codec::size::SIGNING_PUBLIC_KEY);
    for i in 0..61u32 {
        let mut block = Vec::from(&b"mt-vector-pk"[..]);
        block.extend_from_slice(&i.to_le_bytes());
        key.extend_from_slice(&Sha256::digest(&block));
    }
    key.truncate(mt_codec::size::SIGNING_PUBLIC_KEY);
    let key: [u8; mt_codec::size::SIGNING_PUBLIC_KEY] = key
        .try_into()
        .expect("the key of the vector is of its width");
    println!("key_digest = {}", hex(&mt_derive::pulse::key_digest(&key)));
    println!(
        "runner_digest = {}",
        hex(&mt_derive::pulse::runner_digest(&key))
    );
    let beacon = mt_state::layout::Beacon {
        window,
        chain: 0,
        round: 7,
        previous,
        cement_aggregate: vector_aggregate,
        cement_count: 2,
        cement_votes: 1,
    };
    let id = beacon.id().expect("a beacon of its own width");
    println!("beacon_id = {}", hex(&id));
    println!(
        "round_nf = {}",
        hex(&mt_derive::nullifier::round(&vector_secret, &id))
    );

    // A proposal, and its length.
    let proposal = mt_state::layout::Proposal {
        window,
        protocol_version: 0x0001_0000,
        previous: [0x11; 32],
        final_beacon: [0x22; 32],
        note_root: [0x33; 32],
        nullifier_root: [0x44; 32],
        record_root: [0x55; 32],
        machine_root: [0x66; 32],
        admitted_root: [0x77; 32],
        operations_root: [0x88; 32],
        roll: [0xBB; 32],
        admitted_count: 3,
        cement_aggregate: [0x99; 32],
        cement_count: 2,
        census: (0..mt_genesis::scalar("standing_censuses").expect("the Decree names it"))
            .map(|at| mt_state::layout::Census {
                root: [0xC0 + at as u8; 32],
                count: at,
            })
            .collect(),
        suite_id: 1,
        runner_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
        ticket_proof: vec![0x00; mt_state::PRESENCE_PROOF_LEN],
        signature: vec![0x5E; mt_codec::size::SIGNATURE],
    };
    let bytes = proposal.encode();
    println!("proposal_len = {}", bytes.len());
    println!("proposal sha256 = {}", hex(&Sha256::digest(&bytes)));
    println!(
        "proposal_id = {}",
        hex(&proposal
            .id()
            .expect("the identifier of the frozen proposal"))
    );
    println!(
        "confirmation_len = {}",
        mt_state::layout::Confirmation::expected_len()
    );
    println!("beacon_len = {}", mt_state::layout::Beacon::expected_len());
    println!("head_answer_len = {}", mt_wire::message::head_answer_len());
    for (name, width) in [
        ("proposal", mt_state::layout::Proposal::expected_len()),
        ("frame", mt_state::layout::Frame::expected_len()),
        (
            "confirmation",
            mt_state::layout::Confirmation::expected_len(),
        ),
        ("candidacy", mt_state::layout::Candidacy::expected_len()),
        (
            "channel publication",
            mt_state::layout::ChannelPublication::expected_len(),
        ),
        ("beacon", mt_state::layout::Beacon::expected_len()),
        (
            "light attestation",
            mt_state::layout::LightAttestation::expected_len(),
        ),
        ("ballot", mt_state::layout::Ballot::expected_len()),
    ] {
        println!(
            "cells of a {name} = {} of {width} B",
            mt_wire::message::cells_for(width).expect("the Decree names the widths")
        );
    }
    println!(
        "collect_answer_max = {}",
        mt_wire::message::collect_answer_max().expect("the Decree names the widths")
    );

    // The standing of an electorate, and the votes it draws.
    let depth = mt_proof::tree_depth();
    let part = |secret: [u8; 32]| mt_derive::nullifier::part(&secret, 4032).expect("a half");
    let (one, two) = (part([0x5A; 32]), part([0x7B; 32]));
    let mut both = vec![one, two];
    both.sort_unstable();
    println!("part 5a = {}", hex(&one));
    println!("part 7b = {}", hex(&two));
    println!(
        "cement_root (empty) = {}",
        hex(&mt_proof::cement::empty_root().bytes())
    );
    println!(
        "cement_root (5a alone) = {}",
        hex(&mt_proof::cement::root_of(&[one], depth)
            .expect("folds")
            .bytes())
    );
    println!(
        "cement_root (both) = {}",
        hex(&mt_proof::cement::root_of(&both, depth)
            .expect("folds")
            .bytes())
    );
    let spending =
        mt_proof::poseidon::Digest::of_bytes(&mt_derive::nullifier::machine_halves(&[0x5A; 32]).0)
            .expect("a half of the family");
    for census in [4032u64, 6048] {
        println!(
            "coin(5a, census {census}) = {}",
            hex(
                &mt_proof::circuit::ballot::coin_of(&spending, census, &[0x33; 32])
                    .expect("a census window of the field")
                    .bytes()
            )
        );
    }
    for standing in [64_989u64, 64_990, 1_000_000, 1_000_000_000_000] {
        let committee = mt_pulse::standing::committee(standing).expect("computes");
        println!(
            "threshold(standing {standing}) = {} expected {}",
            hex(&committee.threshold.to_be_bytes()),
            committee.expected
        );
    }
}
