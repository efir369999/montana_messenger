// A person raises a machine on a running machine's state: the record they opened carries the right
// to raise one, the candidacy proves that record a member of the tree of records under the root the
// verifier holds, the right it spends the one the record carries and the half it publishes of the
// claimant's own secret — and the right is spent, once.
//
// **The named wrong implementations these refuse**: a verifier taking the root a candidacy was
// proven against rather than the one it holds itself, which lets a claimant walk a tree no proposal
// carries; a verifier applying a candidacy of another window than its own; one record raising a
// second machine under a fresh secret, which is the fleet a lived continuity must not buy; and a
// right forgotten across a stop, which spends it a second time after a restart.

use montana_node::state::State;
use mt_state::Layout;

mod common;
use common::{a_candidacy_of, a_record_carrying, an_opening_of};

const WINDOW: u64 = 1_000;
// The segment window 1 000 stands in, floor(1 000 / 1 440) = 0: the machine derives it from the
// window (Canon, "The rules of continuity", rule 1; constitution records 297 and 300).
const SEGMENT: u32 = 0;
const MACHINE: [u8; 32] = [0x5A; 32];
const RIGHT: [u8; 32] = [0x22; 32];

#[test]
fn a_record_raises_one_machine_and_its_right_is_spent_once() {
    let mut state = State::new();
    let record = a_record_carrying(&RIGHT, WINDOW, SEGMENT);
    state
        .apply_opening(
            &an_opening_of(&[0x44; 32], &record, WINDOW, SEGMENT),
            WINDOW,
        )
        .expect("the claimant's record opens");
    // The tree as it stood before another person's record entered it: a root of a state this
    // machine no longer holds.
    let before = state.clone();
    let other = a_record_carrying(&[0x23; 32], WINDOW, SEGMENT);
    state
        .apply_opening(&an_opening_of(&[0x45; 32], &other, WINDOW, SEGMENT), WINDOW)
        .expect("another person's record opens");
    let root = state.records_root();
    assert_ne!(root, before.records_root());

    // A candidacy proven against the earlier tree does not stand against the root held now.
    let stale = a_candidacy_of(&before, &record, &MACHINE, &RIGHT, WINDOW);
    assert!(
        state.apply_candidacy(&stale, WINDOW, &root).is_err(),
        "a candidacy proven against a root the verifier does not hold was applied"
    );
    assert!(!state.is_spent_right(&stale.operator_nullifier));

    let honest = a_candidacy_of(&state, &record, &MACHINE, &RIGHT, WINDOW);
    assert_eq!(
        honest.operator_nullifier,
        mt_derive::nullifier::operator(&RIGHT),
        "the candidacy spends a right of another derivation"
    );
    assert_eq!(
        honest.naming_half,
        mt_derive::nullifier::machine_halves(&MACHINE).1,
        "the candidacy publishes a half of another derivation"
    );
    // The object crosses the wire at the one width the set gives it.
    let bytes = honest.bytes().expect("a candidacy is written");
    let read = mt_state::layout::Candidacy::parse(&bytes).expect("and reads back");
    assert!(
        state.apply_candidacy(&read, WINDOW + 1, &root).is_err(),
        "a candidacy of another window was applied"
    );
    state
        .apply_candidacy(&read, WINDOW, &root)
        .expect("a true candidacy applies");
    assert!(state.is_spent_right(&read.operator_nullifier));
    assert!(
        state.apply_candidacy(&read, WINDOW, &root).is_err(),
        "a right already spent raised a machine twice"
    );

    // One record raises one machine: the same record under a fresh machine presents its right
    // again, and the right is spent.
    let second = a_candidacy_of(&state, &record, &[0x5B; 32], &RIGHT, WINDOW);
    assert_ne!(second.naming_half, read.naming_half);
    assert_eq!(second.operator_nullifier, read.operator_nullifier);
    assert!(
        state.apply_candidacy(&second, WINDOW, &root).is_err(),
        "one record raised a second machine"
    );

    // And the right outlives a stop of the machine that holds it.
    let mut restored =
        State::decode(&state.encode().expect("the plane is written")).expect("and reads back");
    assert!(restored.is_spent_right(&read.operator_nullifier));
    assert!(
        restored.apply_candidacy(&second, WINDOW, &root).is_err(),
        "a right spent before a restart was spent again after it"
    );
}

// The root a candidacy is verified against is the record root of the last window of the stride
// standing for its window, and nothing stands before the first stride does.
#[test]
fn the_root_of_a_candidacy_is_of_the_last_window_of_its_standing_stride() {
    let reach = mt_genesis::scalar("proving_horizon").expect("the Decree names it");
    let lag = mt_genesis::scalar("proving_lag").expect("the Decree names it");
    assert_eq!(State::window_of_the_root_of_a_candidacy(0), None);
    assert_eq!(
        State::window_of_the_root_of_a_candidacy(reach + lag - 2),
        None,
        "a root stood before the first stride did"
    );
    assert_eq!(
        State::window_of_the_root_of_a_candidacy(reach + lag - 1),
        Some(reach - 1)
    );
    assert_eq!(
        State::window_of_the_root_of_a_candidacy(2 * reach + lag - 2),
        Some(reach - 1)
    );
    assert_eq!(
        State::window_of_the_root_of_a_candidacy(2 * reach + lag - 1),
        Some(2 * reach - 1)
    );
}
