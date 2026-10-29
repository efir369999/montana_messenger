// The windows after an anchor, as a vector makes them: the proposals an operator hands over, the
// beacons of a round, and the attestations and pledges of the machines of a tree answering them.

use montana_node::attest::Standing;
use montana_node::certificate::empty_census;
use montana_node::pulse::Cohort;
use mt_state::layout::{Beacon, Confirmation, LightAttestation, Pledge, Proposal};

// A final proposal the operator hands over: what the walk trusts, and nothing it verifies but the
// link between the two.
pub fn handed(window: u64, previous: [u8; 32], cohort: &Cohort, cement: [u8; 32]) -> Proposal {
    Proposal {
        window,
        protocol_version: mt_state::PROTOCOL_VERSION,
        previous,
        final_beacon: [0x22; 32],
        note_root: [0x33; 32],
        nullifier_root: [0x44; 32],
        record_root: [0x55; 32],
        machine_root: [0x66; 32],
        admitted_root: cohort.root().bytes(),
        credited_root: mt_proof::credited::empty_root().bytes(),
        operations_root: [0x88; 32],
        roll: [0xBB; 32],
        admitted_count: cohort.count(),
        cement_aggregate: cement,
        cement_count: cohort.count(),
        census: empty_census().expect("the Decree names the census"),
        suite_id: mt_net::SUITE,
        runner_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
        ticket_proof: vec![0x00; mt_state::PRESENCE_PROOF_LEN],
        signature: vec![0x5E; mt_codec::size::SIGNATURE],
    }
}

// The opening beacon of a window, standing on the proposal of the window two before.
pub fn opening(window: u64, previous: [u8; 32]) -> Beacon {
    Beacon {
        window,
        chain: 0,
        round: 0,
        previous,
        cement_aggregate: mt_derive::aggregate::aggregate(&[], window).expect("the empty set"),
        cement_count: 0,
        cement_votes: 0,
    }
}

// The beacon of round one, carrying the cement the heavies of round zero name.
pub fn closing(window: u64, first: &Beacon, heavies: &[Confirmation]) -> Beacon {
    let mut parts: Vec<[u8; 32]> = heavies.iter().map(|h| h.part_nullifier).collect();
    parts.sort_unstable();
    Beacon {
        window,
        chain: 0,
        round: 1,
        previous: first.id().expect("an identifier"),
        cement_aggregate: mt_derive::aggregate::aggregate(&parts, window).expect("distinct parts"),
        cement_count: parts.len() as u64,
        cement_votes: 0,
    }
}

// The heavy attestations of a window by the named machines of a tree, answering the opening beacon
// and attesting the proposal of the window before, beside the closing pledges of attempt zero that
// decide it, and the standings that made them, which answer the later rounds lightly.
pub fn heavies(
    secrets: &[[u8; 32]],
    cohort: &Cohort,
    window: u64,
    beacon: &Beacon,
    previous: [u8; 32],
) -> (Vec<Confirmation>, Vec<Pledge>, Vec<Standing>) {
    let mut heavy = Vec::new();
    let mut pledges = Vec::new();
    let mut standings = Vec::new();
    for secret in secrets {
        let branch = cohort.branch_of(secret).expect("its own leaf");
        let standing = Standing::of_the_window(secret, window, &previous, &branch.siblings, branch.position)
            .expect("a machine of the tree proves its presence");
        heavy.push(
            standing
                .heavy(secret, beacon.id().expect("an identifier"), previous)
                .expect("a heavy attestation stands"),
        );
        pledges.push(
            standing
                .pledge(secret, 0, previous, 0)
                .expect("a pledge stands"),
        );
        standings.push(standing);
    }
    (heavy, pledges, standings)
}

// The light attestations answering a later beacon of the window, by machines that already answered
// it heavily: every attestation of a window after a machine's first is light, so a final round is
// answered by these and by no heavy one.
pub fn lights(
    standings: &[Standing],
    secrets: &[[u8; 32]],
    beacon: &Beacon,
    name: [u8; 32],
) -> Vec<LightAttestation> {
    standings
        .iter()
        .zip(secrets)
        .map(|(standing, secret)| {
            standing
                .light(secret, beacon.id().expect("an identifier"), name)
                .expect("a light attestation stands")
        })
        .collect()
}
