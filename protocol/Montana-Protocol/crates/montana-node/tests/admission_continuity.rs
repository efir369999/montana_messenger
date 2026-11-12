// Issue #16, Protocol-13 item 5, box K5: a candidacy proves the continuity the gate of entry demands,
// and the gate is the verifier's own (Canon, "The candidacy of a machine"; constitution records 297,
// 300 and 370). Before the admission circuit read the record's bitmap, the node applied a candidacy
// of a record opened that very window, which had lived nothing: these vectors are red on that circuit.
//
// The named wrong implementations these refuse: a verifier applying a candidacy of a record that
// lived nothing; one taking the gate a claimant proved under rather than computing its own, so a
// claimant naming a share of nought passes with an empty bitmap; one computing the count in force
// from counts other than those of its proposal; and one choosing a count where nothing is admitted.

use montana_node::state::State;
use mt_proof::circuit::{admission, continuity::Gate};

mod common;
use common::{
    a_candidacy_of, a_lived_record_carrying, a_record_carrying, an_opening_of, the_gate_of, ACTIVE,
};

// A window of segment floor(21 160 / 1 440) = 14, the first from which a record can have lived the
// fourteen segments the gate of entry counts (Canon, "The rules of continuity", rule 1).
const WINDOW: u64 = 21_160;
const SEGMENT: u32 = 14;
const MACHINE: [u8; 32] = [0x5A; 32];
const RIGHT: [u8; 32] = [0x22; 32];

// A candidacy of `record` proven under `gate`, whatever gate that is: the claimant's own choice.
fn proven_under(state: &State, record: &[u8], gate: &Gate) -> mt_state::layout::Candidacy {
    let key = mt_proof::records::leaf(record).bytes();
    let siblings = state.path_of_a_record(&key).expect("the record stands");
    let (trace, digests) = admission::trace_of(record, &key, &siblings, &MACHINE, &RIGHT, gate)
        .expect("a claimant writes it");
    let node_commit =
        mt_derive::node_commit(&[0xA1; mt_codec::size::SIGNING_PUBLIC_KEY], 1, &[0xB2; 32]);
    let public = admission::public_of(
        WINDOW,
        &digests[0],
        &digests[1],
        &node_commit,
        &digests[2],
        gate,
        1,
    );
    let held = admission::description().expect("the description stands");
    let proof = mt_proof::scheme::prove(&held, &public, &trace).expect("it proves under its gate");
    mt_state::layout::Candidacy {
        window: WINDOW,
        naming_half: digests[1].bytes(),
        node_commit,
        operator_nullifier: digests[2].bytes(),
        suite_id: 1,
        proof,
    }
}

// Refused, and nothing of the plane moved: the right unspent, every table the same.
fn refused(state: &mut State, candidacy: &mt_state::layout::Candidacy, active: u64, what: &str) {
    let root = state.records_root();
    let before = state.encode().expect("the plane is written");
    assert!(
        state
            .apply_candidacy(candidacy, WINDOW, &root, active)
            .is_err(),
        "the node applied {what}"
    );
    assert!(
        !state.is_spent_right(&candidacy.operator_nullifier),
        "{what} spent the right"
    );
    assert_eq!(
        state.encode().expect("the plane is written"),
        before,
        "{what} moved the plane"
    );
}

// A record opened this window has lived nothing. Its claimant cannot prove it under the gate the
// verifier lays, and a proof under a gate of its own naming — the same count, a share of nought —
// stands under no public input the verifier lays.
#[test]
fn a_record_that_lived_nothing_raises_no_machine() {
    let mut state = State::new();
    let fresh = a_record_carrying(&RIGHT, WINDOW, SEGMENT);
    state
        .apply_opening(&an_opening_of(&[0x44; 32], &fresh, WINDOW, SEGMENT), WINDOW)
        .expect("the record opens");
    let gate = the_gate_of(WINDOW);
    assert_eq!(
        (gate.segment, gate.in_force, gate.required),
        (SEGMENT, 14, 10)
    );

    let key = mt_proof::records::leaf(&fresh).bytes();
    let siblings = state.path_of_a_record(&key).expect("the record stands");
    let (trace, _) = admission::trace_of(&fresh, &key, &siblings, &MACHINE, &RIGHT, &gate)
        .expect("a claimant writes it");
    let held = admission::description().expect("the description stands");
    let nothing_lived = Gate {
        required: 0,
        ..gate
    };
    let own = proven_under(&state, &fresh, &nothing_lived);
    let lifted = mt_proof::poseidon::limbs_of(&admission::public_of(
        WINDOW,
        &state.records_root(),
        &mt_proof::poseidon::Digest::of_bytes(&own.naming_half).expect("a digest"),
        &own.node_commit,
        &mt_proof::poseidon::Digest::of_bytes(&own.operator_nullifier).expect("a digest"),
        &gate,
        1,
    ));
    assert!(
        !held.satisfied_by(&trace, &lifted),
        "an empty bitmap met a share of ten"
    );
    refused(
        &mut state,
        &own,
        ACTIVE,
        "a candidacy of a record that lived nothing",
    );
}

// The count in force is the verifier's own. A claimant proving under twice the floor of the ramp —
// twenty-eight segments, nineteen demanded, which fourteen lived ones do not reach, so it proves
// only a record of the claimant's naming — presents a statement the verifier never lays: it lays
// fourteen, by the counts of its proposal and the author's decision 371. Where nothing is admitted
// the ramp gives no count and nothing applies. The honest candidacy then applies.
#[test]
fn the_gate_is_the_verifiers_own_count() {
    let mut state = State::new();
    let record = a_lived_record_carrying(&RIGHT, WINDOW);
    state.witness_record(&record);
    let honest = a_candidacy_of(&state, &record, &MACHINE, &RIGHT, WINDOW);

    let gate = the_gate_of(WINDOW);
    let doubled = Gate {
        in_force: 2 * gate.in_force,
        required: mt_pulse::entry::required_segments(2 * gate.in_force).expect("a share"),
        ..gate
    };
    assert_eq!((doubled.in_force, doubled.required), (28, 19));
    let wide = a_lived_record_of(&RIGHT, WINDOW, (1u64 << 28) - 1);
    let mut other = State::new();
    other.witness_record(&wide);
    let pressed = proven_under(&other, &wide, &doubled);
    refused(
        &mut other,
        &pressed,
        ACTIVE,
        "a candidacy proven under a count the verifier does not lay",
    );

    assert!(State::gate_of_a_candidacy(WINDOW, 0).is_err());
    refused(
        &mut state,
        &honest,
        0,
        "a candidacy where nothing is admitted",
    );

    let root = state.records_root();
    state
        .apply_candidacy(&honest, WINDOW, &root, ACTIVE)
        .expect("the honest candidacy applies");
    assert!(state.is_spent_right(&honest.operator_nullifier));
}

// A record of the layout that lived the segments `bitmap` marks, up to the one `window` stands in.
fn a_lived_record_of(operator_secret: &[u8; 32], window: u64, bitmap: u64) -> Vec<u8> {
    let segment = mt_pulse::standing::segment(window).expect("a window of the width");
    mt_state::Layout::bytes(&mt_state::layout::Record {
        segment_bitmap: bitmap,
        last_active_segment: segment,
        opened_window: 0,
        own_height: 27,
        operator_nf: mt_derive::nullifier::operator(operator_secret),
        fabric_root: [0x11; 32],
        suite_id: 1,
        current_pubkey: vec![0x22; mt_codec::size::SIGNING_PUBLIC_KEY],
        blind: [0x33; 32],
    })
    .expect("a record of the layout")
}
