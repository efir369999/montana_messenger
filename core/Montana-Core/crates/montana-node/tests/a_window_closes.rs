// The closing condition of the stage of two hosts, in the part that was the wall: two machines
// answer a window, their attestations gather into a cement, the cement reaches the quorum share of
// the committed total, and the window closes — with the share of that window belonging to the
// machines the cement names and to no others.
//
// **Nothing here is a model of the rules.** Each machine draws its own eligibility, makes its own
// proof of presence, signs with its own one-time key, and every attestation is verified as a far
// side would verify it: the draw natively, the signature under the key it carries, and the proof
// against the root of admitted machines. What the test arranges is only the world outside — which
// machines stand in the tree, and what standing each answers with.
//
// **The opening cohort witnesses itself.** Two machines stand in the tree of admitted machines from
// the first window, which is what the set states of an opening cohort: it witnesses itself by the
// same quorum, and the rule takes no exception for it.

use montana_node::attest::{self, Standing};
use mt_pulse::fold::{Cement, Leaf};

const STANDING: u64 = 1_000;
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
    let mut leaves: Vec<Leaf> = Vec::new();
    for (secret, (siblings, position)) in secrets.iter().zip(branches.iter()) {
        let standing = Standing::of_the_window(secret, WINDOW, siblings, *position, STANDING)
            .expect("a machine of the cohort proves its presence");
        assert!(
            standing.eligible(&aggregate, 0, 7, &everything),
            "a threshold of everything admits every machine"
        );
        let heavy = standing
            .heavy(secret, beacon_id, previous_proposal)
            .expect("a heavy attestation stands");

        // Verified exactly as a far side verifies it, and never trusted for having been made here.
        attest::verify_heavy(&heavy, &root, &aggregate, 0, 7, &everything)
            .expect("the attestation of a machine of the cohort verifies");

        let leaf = attest::leaf_of(&heavy).expect("its commitment reads back");
        assert!(
            cement.add(&leaf).expect("the cement takes it"),
            "a first appearance enters"
        );
        assert!(
            !cement.add(&leaf).expect("the cement answers"),
            "a second appearance of one part-nullifier adds nothing"
        );
        leaves.push(leaf);
    }

    assert_eq!(cement.count(), 2, "both machines entered the cement");

    // The window closes when the standing that entered the cement reaches the share of the whole
    // active set the Decree names. Both machines of a cohort of two answered, so the cement carries
    // the whole of it.
    let total = u128::from(STANDING) * 2;
    let cemented = u128::from(STANDING) * cement.count() as u128;
    assert_eq!(
        mt_pulse::close::closes(cemented, total, 0),
        Ok(true),
        "a cement holding every machine of the cohort closes the window"
    );
    // And one machine alone does not: the share is a rule and not a count of who spoke.
    assert_eq!(
        mt_pulse::close::closes(u128::from(STANDING), total, 0),
        Ok(false),
        "half of the standing does not reach the quorum share"
    );

    // The leaves of the window, ascending by part-nullifier: the order the fold is built over and
    // the order every verifier reaches alone.
    let ordered = mt_pulse::fold::ordered(leaves).expect("no part-nullifier repeats");
    assert_eq!(ordered.len(), 2);
    assert!(ordered[0].part_nullifier < ordered[1].part_nullifier);
}

// What a closed window mints, and to whom. Minting creates no note: the window issues to each
// living machine a right to a share of it, one right per machine per window, and the count of the
// living is what the cement names — never a poll, never a count of who answered on the wire.
#[test]
fn a_closed_window_issues_one_equal_right_to_every_machine_its_cement_names() {
    let secrets = [[0x11u8; 32], [0x22u8; 32]];
    let living = secrets.len();
    let mint = attest::mint_of(WINDOW).expect("the Decree names the schedule");

    let mut rights = Vec::new();
    for secret in &secrets {
        let right = attest::right_of(secret, WINDOW, living).expect("a machine of the cement");
        // One equal part to every living machine, with the remainder that does not divide carried
        // forward rather than appropriated.
        assert_eq!(right.share, mint / living as u64);
        assert_eq!(right.carried_forward, mint % living as u64);
        // The window a right is accepted in is drawn from the machine's own secret: not early, not
        // late, and nothing about the choice is anyone's to make.
        let spread = mt_genesis::scalar("claim_spread").expect("the Decree names it");
        assert!(right.accepted_in >= WINDOW && right.accepted_in < WINDOW + spread);
        rights.push(right);
    }

    // Two machines, two rights, two nullifiers: no machine takes its share twice and none takes
    // another's.
    assert_ne!(rights[0].nullifier, rights[1].nullifier);
    // And the shares of the living, plus what does not divide, are the mint of that window exactly.
    let handed: u64 = rights.iter().map(|r| r.share).sum();
    assert_eq!(handed + rights[0].carried_forward, mint);

    // A window whose cement names nobody mints no share, and says so rather than dividing by it.
    assert!(attest::right_of(&secrets[0], WINDOW, 0).is_err());
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
    let standing = Standing::of_the_window(&secrets[0], WINDOW, siblings, *position, STANDING)
        .expect("a machine of the cohort proves its presence");
    let mut heavy = standing
        .heavy(&secrets[0], [0x44u8; 32], [0x55u8; 32])
        .expect("a heavy attestation stands");

    // The key of the second machine, under which this proof was never made.
    let (theirs, _) = branches[1].clone();
    let _ = theirs;
    let seed = mt_derive::pulse::part_key_seed(&secrets[1], WINDOW);
    let mut held = [0u8; mt_suite::sign::SEED_BYTES];
    held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (other_key, _) = mt_suite::sign::keypair_from_seed(&held);
    heavy.answering_key = other_key.as_bytes().to_vec();

    assert!(
        attest::verify_heavy(&heavy, &root, &aggregate, 0, 7, &everything).is_err(),
        "a proof standing against another key was accepted"
    );
}
