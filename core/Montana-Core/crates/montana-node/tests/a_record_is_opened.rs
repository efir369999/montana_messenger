// A person brings a record into being on a running machine: the one-time right is spent, the proof
// stands against what the object publishes and against the window the machine is applying, and the
// record enters the tree of records at the key its own commitment gives.
//
// **The machine never sees the record.** What reaches it is a commitment and a nullifier, and the
// commitment is the leaf itself — so a machine holds the tree of records without holding one
// record, which is the whole reason the plane publishes a commitment rather than the thing.
//
// **The named wrong implementations these refuse**: a claimant spending one right twice, and a
// claimant opening a record into a window the machine is not applying. The first collides on a
// value nothing but that seed produces; the second fails at the boundary that binds the window.

use montana_node::state::State;
use mt_state::Layout;

const WINDOW: u64 = 1_000;
const SEGMENT: u32 = 7;

// A record as a claimant brings it into being. The bytes are the serialization the set fixes.
fn a_new_record(window: u64, segment: u32) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&0u64.to_le_bytes());
    out.extend_from_slice(&segment.to_le_bytes());
    out.extend_from_slice(&window.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&[0x11u8; 32]);
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&[0x22u8; mt_codec::size::SIGNING_PUBLIC_KEY]);
    out.extend_from_slice(&[0x33u8; 32]);
    out
}

fn an_opening(open_secret: &[u8; 32], window: u64, segment: u32) -> mt_state::layout::Opening {
    let record = a_new_record(window, segment);
    let (trace, digests) =
        mt_proof::circuit::opening::trace_of(open_secret, &record).expect("a claimant writes it");
    let public = mt_proof::circuit::opening::public_of(&digests, window, segment);
    let held = mt_proof::circuit::opening::description().expect("the description stands");
    let proof = mt_proof::scheme::prove(&held, &public, &trace).expect("a true opening proves");
    mt_state::layout::Opening {
        open_nullifier: digests[0].bytes(),
        record_commit: digests[1].bytes(),
        proof,
    }
}

#[test]
fn a_record_enters_the_tree_and_a_right_is_spent_once() {
    let mut state = State::new();
    assert_eq!(state.records_held(), 0);
    let empty = state.records_root();

    let open_secret = [0x44u8; 32];
    let opening = an_opening(&open_secret, WINDOW, SEGMENT);
    assert_eq!(
        opening.open_nullifier,
        mt_derive::nullifier::open(&open_secret),
        "an opening publishes a nullifier of another derivation"
    );
    // The object crosses the wire at the one width the set gives it.
    let bytes = Layout::bytes(&opening).expect("an opening is written");
    let read = mt_state::layout::Opening::parse(&bytes).expect("and reads back");

    state
        .apply_opening(&read, WINDOW, SEGMENT)
        .expect("a true opening applies");
    assert_eq!(state.records_held(), 1, "the record did not enter the tree");
    assert_ne!(
        state.records_root(),
        empty,
        "the root of the tree of records did not move"
    );
    assert!(
        state.is_spent_right(&read.open_nullifier),
        "the right was not recorded as spent"
    );
    assert!(
        state.path_of_a_record(&read.record_commit).is_some(),
        "the record stands at no key a walk reaches"
    );

    // One seed opens one record: a second opening under it presents the identical value.
    let again = an_opening(&open_secret, WINDOW, SEGMENT);
    assert_eq!(again.open_nullifier, read.open_nullifier);
    assert!(
        state.apply_opening(&again, WINDOW, SEGMENT).is_err(),
        "a right already spent opened a second record"
    );
    assert_eq!(state.records_held(), 1);

    // And a record claiming another window does not stand in this one.
    let elsewhere = an_opening(&[0x45u8; 32], WINDOW + 1, SEGMENT);
    assert!(
        state.apply_opening(&elsewhere, WINDOW, SEGMENT).is_err(),
        "a record opened into another window was applied to this one"
    );
    assert_eq!(state.records_held(), 1);
}
