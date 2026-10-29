// The closing condition of the stage of two hosts, in the part that was the wall: two machines
// answer a window, their attestations gather into a cement, the count of the cement reaches the
// quorum share of the electorate's count, and the window closes — with the share of that window
// belonging to the machines the cement names and to no others.
//
// **Nothing here is a model of the rules.** Each machine draws its own eligibility, makes its own
// proof of presence, signs with its own one-time key, and every attestation is verified as a far
// side would verify it: the draw natively, the signature under the key it carries, and the proof
// against the root of admitted machines. What the test arranges is only the world outside — which
// machines stand in the tree.
//
// **The opening cohort witnesses itself.** Two machines stand in the tree of admitted machines from
// the first window, which is what the set states of an opening cohort: it witnesses itself by the
// same quorum, and the rule takes no exception for it.

use montana_node::attest::{self, Standing};
use mt_pulse::cement::Cement;
use mt_state::Layout;

const WINDOW: u64 = 1_000;

// The tree of admitted machines over a cohort, and the branch each machine walks. Both come of the
// one construction the tree carries: the halves alone, in their ascending order, which every
// machine reaches without asking anybody.
fn cohort(
    secrets: &[[u8; 32]],
) -> (
    mt_proof::poseidon::Digest,
    Vec<(Vec<mt_proof::poseidon::Digest>, u64)>,
) {
    let halves: Vec<[u8; 32]> = secrets
        .iter()
        .map(montana_node::pulse::Cohort::half_of)
        .collect();
    let held = montana_node::pulse::Cohort::of(&halves).expect("the cohort stands in the tree");
    let branches = secrets
        .iter()
        .map(|secret| {
            let branch = held.branch_of(secret).expect("its own leaf");
            (branch.siblings, branch.position)
        })
        .collect();
    (held.root(), branches)
}

#[test]
fn two_machines_answer_a_window_and_its_cement_closes_it() {
    let secrets = [[0x11u8; 32], [0x22u8; 32]];
    let (root, branches) = cohort(&secrets);
    let aggregate = [0x33u8; 32];
    // A threshold of everything: what this scenario is about is the cement and the close, and a
    // draw that admitted nobody would be testing the draw instead.
    let everything = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);
    let beacon_id = [0x44u8; 32];
    let previous_proposal = [0x55u8; 32];

    let mut cement = Cement::new();
    let mut parts: Vec<[u8; 32]> = Vec::new();
    for (secret, (siblings, position)) in secrets.iter().zip(branches.iter()) {
        let standing =
            Standing::of_the_window(secret, WINDOW, &previous_proposal, siblings, *position)
                .expect("a machine of the cohort proves its presence");
        assert!(
            standing.eligible(&aggregate, 0, 7, &everything),
            "a threshold of everything admits every machine"
        );
        let heavy = standing
            .heavy(secret, beacon_id, previous_proposal)
            .expect("a heavy attestation stands");

        // Verified exactly as a far side verifies it, and never trusted for having been made here.
        attest::verify_heavy(
            &heavy,
            &previous_proposal,
            &root,
            &aggregate,
            0,
            7,
            &everything,
        )
        .expect("the attestation of a machine of the cohort verifies");

        assert!(
            cement.add(heavy.part_nullifier),
            "a first appearance enters"
        );
        assert!(
            !cement.add(heavy.part_nullifier),
            "a second appearance of one part-nullifier adds nothing"
        );
        parts.push(heavy.part_nullifier);
    }

    assert_eq!(cement.count(), 2, "both machines entered the cement");

    // The window closes when the count of distinct machines of the electorate in the cement reaches
    // the share of the electorate's count the Decree names. Both machines of a cohort of two
    // answered, so the cement carries the whole of it.
    let electorate = u128::from(secrets.len() as u64);
    let cemented = u128::from(cement.count());
    assert_eq!(
        mt_pulse::close::closes(cemented, electorate, 0),
        Ok(true),
        "a cement holding every machine of the cohort closes the window"
    );
    // And one machine alone does not: the share is a rule and not a count of who spoke.
    assert_eq!(
        mt_pulse::close::closes(1, electorate, 0),
        Ok(false),
        "half of the electorate does not reach the quorum share"
    );

    // The state a beacon carries is the aggregate over the parts with the window as context, and
    // every verifier reaches it whatever order it saw the parts in.
    let mut reversed = Cement::new();
    for part in parts.iter().rev() {
        reversed.add(*part);
    }
    assert_eq!(cement.aggregate(WINDOW), reversed.aggregate(WINDOW));
    assert_eq!(
        cement.aggregate(WINDOW),
        Ok(mt_derive::aggregate::aggregate(&parts, WINDOW).expect("two distinct parts"))
    );
}

// What a closed window credits, and to whom. Minting creates no note: the window issues to each
// living machine a right to its coin, one right per machine per window, and the count of the
// living is what the cement names — never a poll, never a count of who answered on the wire.
#[test]
fn a_closed_window_issues_its_credit_to_every_machine_its_cement_names() {
    let secrets = [[0x11u8; 32], [0x22u8; 32]];
    let living = secrets.len();

    let mut rights = Vec::new();
    for secret in &secrets {
        let right = attest::right_of(secret, WINDOW).expect("a machine of the cement");
        // The window's credit, one coin for every second of it, to every living machine: nothing
        // is divided, so nothing is carried.
        assert_eq!(
            right.worth,
            attest::window_credit().expect("the Decree names it")
        );
        // The window a right is accepted in is drawn from the machine's own secret: not early, not
        // late, and nothing about the choice is anyone's to make.
        let spread = mt_genesis::scalar("claim_spread").expect("the Decree names it");
        assert!(right.accepted_in >= WINDOW && right.accepted_in < WINDOW + spread);
        rights.push(right);
    }

    // Two machines, two rights, two nullifiers: no machine takes its coin twice and none takes
    // another's.
    assert_ne!(rights[0].nullifier, rights[1].nullifier);
    // And the coins of the living are what the window adds to the supply exactly: its credit
    // times the count of its cement.
    let handed: u64 = rights.iter().map(|r| r.worth).sum();
    assert_eq!(
        handed,
        living as u64 * attest::window_credit().expect("the Decree names it")
    );
    assert_eq!(attest::supply_added(living), Ok(handed));

    // A window whose cement names nobody adds nothing.
    assert_eq!(attest::supply_added(0), Ok(0));
}

// The named wrong implementation this refuses: a machine answering with a proof made for another
// key. The digest of the key stands in the public input of a presence, so a proof lifted from one
// attestation onto another fails where that digest is bound.
#[test]
fn a_proof_lifted_onto_another_key_is_refused() {
    let secrets = [[0x11u8; 32], [0x22u8; 32]];
    let (root, branches) = cohort(&secrets);
    let aggregate = [0x33u8; 32];
    let everything = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);

    let (siblings, position) = &branches[0];
    let standing = Standing::of_the_window(&secrets[0], WINDOW, &[0x55u8; 32], siblings, *position)
        .expect("a machine of the cohort proves its presence");
    let mut heavy = standing
        .heavy(&secrets[0], [0x44u8; 32], [0x55u8; 32])
        .expect("a heavy attestation stands");

    // The key of the second machine, under which this proof was never made.
    let seed = mt_derive::pulse::part_key_seed(&secrets[1], WINDOW);
    let mut held = [0u8; mt_suite::sign::SEED_BYTES];
    held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (other_key, other_secret) = mt_suite::sign::keypair_from_seed(&held);
    heavy.answering_key = other_key.as_bytes().to_vec();
    heavy.signature = mt_suite::sign::sign(&other_secret, &heavy.signed_scope().expect("scope"))
        .expect("the attacker owns the replacement key")
        .as_bytes()
        .to_vec();

    assert_eq!(
        attest::verify_heavy(&heavy, &[0x55u8; 32], &root, &aggregate, 0, 7, &everything),
        Err(montana_node::NodeError::Refused {
            what: "an attestation whose proof of presence does not verify",
        }),
        "the proof itself must reject the replacement, even with a valid signature"
    );
}

#[test]
fn an_admitted_machine_cannot_resign_an_old_presence_into_another_window() {
    let secret = [0x11u8; 32];
    let (root, branches) = cohort(&[secret]);
    let (siblings, position) = &branches[0];
    let standing = Standing::of_the_window(&secret, WINDOW, &[0x55; 32], siblings, *position)
        .expect("the admitted machine proves its presence");
    let mut forged = standing
        .heavy(&secret, [0x44; 32], [0x55; 32])
        .expect("attestation");
    forged.window = WINDOW + 1;
    let seed = mt_derive::pulse::part_key_seed(&secret, WINDOW);
    let mut signing_seed = [0u8; mt_suite::sign::SEED_BYTES];
    signing_seed.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (_, key) = mt_suite::sign::keypair_from_seed(&signing_seed);
    forged.signature = mt_suite::sign::sign(&key, &forged.signed_scope().expect("scope"))
        .expect("the attacker can sign again")
        .as_bytes()
        .to_vec();
    let everything = mt_pulse::U256::from_be_bytes(&[0xFF; 32]);
    assert_eq!(
        attest::verify_heavy(&forged, &[0x55; 32], &root, &[0x33; 32], 0, 7, &everything),
        Err(montana_node::NodeError::Refused {
            what: "an attestation whose proof of presence does not verify",
        }),
    );
}

// K6 of item 5 (issue #16): a machine that replays another machine's heavy attestation takes no
// part of its own by it. The wrong implementations it refuses, named before the assertions: a
// cement that counts the machine carrying an attestation rather than the part the attestation
// proves, and a verifier that lets a carrier write its own part-nullifier over a proof made for
// another — there the carrier would stand in the cement, and so in the roll the next window
// credits (`credited_by`, pulse.rs), for a window it never answered.
#[test]
fn a_replayed_heavy_gives_the_replayer_no_part_of_its_own() {
    let secrets = [[0x11u8; 32], [0x22u8; 32]];
    let (root, branches) = cohort(&secrets);
    let aggregate = [0x33u8; 32];
    let everything = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);
    let (beacon_id, previous_proposal) = ([0x44u8; 32], [0x55u8; 32]);

    // The machine that answered, and the one that only carries its answer on.
    let (siblings, position) = &branches[0];
    let answering =
        Standing::of_the_window(&secrets[0], WINDOW, &previous_proposal, siblings, *position)
            .expect("a machine of the cohort proves its presence");
    let replayer = mt_derive::nullifier::part(&secrets[1], WINDOW).expect("the replayer's part");
    assert_ne!(replayer, answering.part_nullifier);

    // Replayed as it is, the attestation verifies as the original and enters the part that made
    // it, once, however often it is carried; the carrier's part never enters.
    let mut cement = Cement::new();
    for _ in 0..3 {
        let carried = answering
            .heavy(&secrets[0], beacon_id, previous_proposal)
            .expect("a heavy attestation stands");
        attest::verify_heavy(
            &carried,
            &previous_proposal,
            &root,
            &aggregate,
            0,
            7,
            &everything,
        )
        .expect("a replay of a valid attestation verifies as the original");
        cement.add(carried.part_nullifier);
    }
    assert_eq!(cement.count(), 1, "a replay adds no part");
    assert!(cement.holds(&answering.part_nullifier));
    assert!(
        !cement.holds(&replayer),
        "the carrier of another machine's attestation took a part of its own"
    );

    // Claimed as its own: the carrier writes its part-nullifier over the proof and signs under its
    // own key of the window. The public input binds the part and the digest of the key, so the
    // proof made for the other machine refuses both.
    let mut claimed = answering
        .heavy(&secrets[0], beacon_id, previous_proposal)
        .expect("a heavy attestation stands");
    claimed.part_nullifier = replayer;
    let seed = mt_derive::pulse::part_key_seed(&secrets[1], WINDOW);
    let mut held = [0u8; mt_suite::sign::SEED_BYTES];
    held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (key, secret_of_the_key) = mt_suite::sign::keypair_from_seed(&held);
    claimed.answering_key = key.as_bytes().to_vec();
    claimed.signature =
        mt_suite::sign::sign(&secret_of_the_key, &claimed.signed_scope().expect("scope"))
            .expect("the carrier owns its own key")
            .as_bytes()
            .to_vec();
    assert_eq!(
        attest::verify_heavy(
            &claimed,
            &previous_proposal,
            &root,
            &aggregate,
            0,
            7,
            &everything
        ),
        Err(montana_node::NodeError::Refused {
            what: "an attestation whose proof of presence does not verify",
        }),
        "a carrier took another machine's proof for a part of its own"
    );
}
