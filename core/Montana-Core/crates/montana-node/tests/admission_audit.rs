// The counterexample of `Audit/Protocol-13/04-ADMISSION-ORIGIN.md`, through the verifying
// algorithm a node actually runs: "a foreign record combined with the claimant's secret and an
// unrelated membership path" is refused, and "the corresponding honest admission must still
// verify". The finding stands closed by these two together and by neither alone.
//
// The attacker holds the preimage of another person's record — lent, sold or leaked, since a record
// is never published — and its own machine and its own right, and walks the record in a tree of its
// own making. The honest prover will not prove that witness, so the attacker proves it under the
// statement with the limbs that bind the record's right taken out: the weak statement, which a
// verifier keeping it as a fallback would accept. The node refuses the candidacy and the right stays
// unspent.
//
// The second test holds the finding of a lifted candidacy closed (AUDIT.md, F-1): `node_commit` and
// `suite_id` stand in the public input of the proof (Canon, "The candidacy of a machine"), so a
// relay rewriting either presents a proof of another statement, the node refuses it with the right
// unspent, and the honest candidacy then applies.

use montana_node::state::State;
use mt_proof::air::BoundaryValue;
use mt_proof::circuit::admission;

mod common;
use common::{a_candidacy_of, a_record_carrying, an_opening_of};

const WINDOW: u64 = 1_000;
// The segment window 1 000 stands in, floor(1 000 / 1 440) = 0: the machine derives it from the
// window (Canon, "The rules of continuity", rule 1; constitution records 297 and 300).
const SEGMENT: u32 = 0;
const CLAIMANT_MACHINE: [u8; 32] = [0x5A; 32];
const CLAIMANT_RIGHT: [u8; 32] = [0x22; 32];
const FOREIGN_RIGHT: [u8; 32] = [0x23; 32];
const MIXED_MACHINE: [u8; 32] = [0x99; 32];
const SUITE: u16 = 1;

#[test]
fn audit_refuses_a_foreign_record_with_the_claimants_secret_and_an_unrelated_path() {
    let mut state = State::new();
    let claimants = a_record_carrying(&CLAIMANT_RIGHT, WINDOW, SEGMENT);
    let foreign = a_record_carrying(&FOREIGN_RIGHT, WINDOW, SEGMENT);
    for (open, record) in [([0x44; 32], &claimants), ([0x45; 32], &foreign)] {
        state
            .apply_opening(&an_opening_of(&open, record, WINDOW, SEGMENT), WINDOW)
            .expect("a record opens");
    }
    let root = state.records_root();

    // The unrelated membership path: the foreign record alone in a tree the attacker made.
    let leaf = mt_proof::records::leaf(&foreign);
    let made: std::collections::BTreeMap<[u8; 32], mt_proof::poseidon::Digest> =
        std::iter::once((leaf.bytes(), leaf)).collect();
    let unrelated = mt_proof::records::path_of_leaves(&made, &leaf.bytes()).expect("it stands");
    let (trace, digests) = admission::trace_of(
        &foreign,
        &leaf.bytes(),
        &unrelated,
        &CLAIMANT_MACHINE,
        &CLAIMANT_RIGHT,
    )
    .expect("an attacker writes it");
    assert_ne!(digests[0], root, "the made tree is the state's own");
    let public = admission::public_of(
        WINDOW,
        &digests[0],
        &digests[1],
        &MIXED_MACHINE,
        &digests[2],
        SUITE,
    );
    let held = admission::description().expect("the description stands");
    assert!(
        !held.satisfied_by(&trace, &mt_proof::poseidon::limbs_of(&public)),
        "the statement accepts a foreign record with the claimant's secret"
    );
    assert!(mt_proof::scheme::prove(&held, &public, &trace).is_err());

    let mut weak = admission::description().expect("the description stands");
    weak.boundaries
        .retain(|boundary| !matches!(boundary.value, BoundaryValue::Public(_)));
    let proof = mt_proof::scheme::prove(&weak, &public, &trace)
        .expect("the weak statement proves the mixed witness");
    assert_eq!(mt_proof::scheme::verify(&weak, &public, &proof), Ok(()));
    let mixed = mt_state::layout::Candidacy {
        window: WINDOW,
        naming_half: digests[1].bytes(),
        node_commit: MIXED_MACHINE,
        operator_nullifier: digests[2].bytes(),
        suite_id: SUITE,
        proof,
    };
    assert!(
        state.apply_candidacy(&mixed, WINDOW, &root).is_err(),
        "the node applied a foreign record with the claimant's secret and an unrelated path"
    );
    assert!(
        !state.is_spent_right(&mixed.operator_nullifier),
        "a refused candidacy spent the claimant's right"
    );

    // The corresponding honest admission: the claimant's own record, in the tree the node holds.
    let honest = a_candidacy_of(
        &state,
        &claimants,
        &CLAIMANT_MACHINE,
        &CLAIMANT_RIGHT,
        WINDOW,
    );
    assert_eq!(honest.operator_nullifier, mixed.operator_nullifier);
    state
        .apply_candidacy(&honest, WINDOW, &root)
        .expect("the honest admission verifies");
    assert!(state.is_spent_right(&honest.operator_nullifier));
}

// F-1, closed: a candidacy whose `node_commit` or `suite_id` a relay rewrote is refused by the node
// with the right unspent, since the proof stands under the public input of the honest one; the
// honest candidacy then applies. Before the binding, the lifted one applied and spent the right.
#[test]
fn audit_refuses_a_candidacy_lifted_onto_another_commitment() {
    let mut state = State::new();
    let record = a_record_carrying(&CLAIMANT_RIGHT, WINDOW, SEGMENT);
    state
        .apply_opening(
            &an_opening_of(&[0x44; 32], &record, WINDOW, SEGMENT),
            WINDOW,
        )
        .expect("the record opens");
    let root = state.records_root();
    let honest = a_candidacy_of(&state, &record, &CLAIMANT_MACHINE, &CLAIMANT_RIGHT, WINDOW);
    let mut lifted = honest.clone();
    lifted.node_commit = MIXED_MACHINE;
    assert_ne!(lifted.node_commit, honest.node_commit);
    let mut other_suite = honest.clone();
    other_suite.suite_id = honest.suite_id + 1;
    for (relayed, what) in [
        (&lifted, "a candidacy lifted onto another node_commit"),
        (&other_suite, "a candidacy relayed under another suite"),
    ] {
        assert!(
            state.apply_candidacy(relayed, WINDOW, &root).is_err(),
            "the node applied {what}"
        );
        assert!(
            !state.is_spent_right(&relayed.operator_nullifier),
            "{what} spent the claimant's right"
        );
    }
    state
        .apply_candidacy(&honest, WINDOW, &root)
        .expect("the honest candidacy applies");
    assert!(state.is_spent_right(&honest.operator_nullifier));
}
