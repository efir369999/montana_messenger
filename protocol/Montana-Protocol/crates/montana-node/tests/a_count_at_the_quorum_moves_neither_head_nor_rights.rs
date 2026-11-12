// Protocol-13 item 2 (#10): a count of participants at the quorum authorizes only an attempt to
// build the proof; the head and the issuance rights move only on a verified canonical Proposal.
//
// **What is measured.** A machine whose cement reaches the quorum of its electorate and whose final
// beacon it can close on holds everything a count can give it — and nothing of the store moves: the
// head stands where it stood, no proposal of the window is kept, the number of the last window
// closed stands, and the only thing written is the record of the agreement, which is the attempt the
// count authorizes. The head has one door, Machine::finalize into the store's set_head, and the
// store refuses a head naming a proposal it does not hold; the right of a window is issued at the
// close of the window after, from the decided roll (pulse.rs, the close), and never from a count.
//
// **The wrong implementation it refuses**, named before the assertions and for what this test
// measures: a primitive of the count — `attempts_the_close`, `can_advance`, the open quorum of the
// book, `Pulse::open` — that writes the head, a proposal or the last window closed; and a store that
// lets the head move onto a window whose proposal it does not hold. It does not run live_doing: a
// live_doing that moved the head on the count would pass it untouched. That refusal is measured on
// the loop itself by a_quorum_without_a_verified_proposal_closes_nothing.rs, which fails on a
// live_doing that closes on the count. The right is held by the same order (issued after the close,
// from the decided roll) and is observed here through the door alone.

use montana_node::certificate::empty_census;
use montana_node::pulse::{Cohort, Pulse};
use montana_node::{Configuration, Machine};
use mt_state::layout::Proposal;
use mt_state::Layout;

mod common;
use common::Scratch;

const WINDOW: u64 = 2_900;

// A proposal the store can hold under a window below the one lived here: where the head stands
// before, and must stand after, a count at the quorum.
fn kept(window: u64) -> Proposal {
    Proposal {
        window,
        protocol_version: mt_state::PROTOCOL_VERSION,
        previous: [0x10; 32],
        final_beacon: [0x22; 32],
        note_root: [0x33; 32],
        nullifier_root: [0x44; 32],
        record_root: [0x55; 32],
        machine_root: [0x66; 32],
        admitted_root: [0x77; 32],
        credited_root: [0xAA; 32],
        operations_root: [0x88; 32],
        roll: [0xBB; 32],
        admitted_count: 1,
        cement_aggregate: [0x99; 32],
        cement_count: 1,
        census: empty_census().expect("the Decree names the census"),
        suite_id: mt_net::SUITE,
        runner_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
        ticket_proof: vec![0x00; mt_state::PRESENCE_PROOF_LEN],
        signature: vec![0x5E; mt_codec::size::SIGNATURE],
    }
}

#[test]
fn a_cement_at_the_quorum_and_a_beacon_to_close_on_move_neither_the_head_nor_a_right() {
    let at = Scratch::named("count-not-close");
    let secret = [0x75u8; 32];
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).expect("a cohort of one stands");
    let branch = cohort.branch_of(&secret).expect("its own leaf");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    machine
        .admits(cohort.count())
        .expect("the count of the window");
    // The head stands on a window well before: what a count must not move.
    machine
        .keep_proposal(&kept(WINDOW - 5))
        .expect("a proposal is kept");
    machine
        .finalize(WINDOW - 5)
        .expect("the head moves onto it");
    assert_eq!(machine.head().expect("the store answers"), Some(WINDOW - 5));
    machine.let_go_of(WINDOW - 5).expect("the window is let go");

    let aggregate = [0x37u8; 32];
    let previous = [0x42u8; 32];
    let everything = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);
    let electorate =
        montana_node::certificate::Electorate::opening(cohort.root(), cohort.count(), WINDOW)
            .expect("an opening electorate stands");
    let mut pulse = Pulse::open(
        &machine,
        &secret,
        (WINDOW, 0, 0),
        &branch,
        previous,
        [0x41u8; 32],
        &electorate,
        &aggregate,
    )
    .expect("the window opens");
    let beacon = pulse.beacon_of_this_round().expect("the opening beacon");
    let heavy = pulse
        .answer(&secret, &beacon, &aggregate, &everything)
        .expect("an answer is drawn")
        .expect("drawn");
    let heavy = mt_state::layout::Confirmation::parse(&heavy).expect("a heavy attestation");
    assert!(pulse
        .gather(&heavy, &cohort.root(), &aggregate, &beacon, &everything)
        .expect("a verified attestation enters"));

    // The count: the cement of one reaches the quorum of an electorate of one, the beacon of the
    // round carries that cement and a verified attestation answered it — a beacon this machine could
    // close on. The agreement's open pledges of attempt zero even reach the quorum on the name.
    assert_eq!(pulse.attempts_the_close(cohort.count()), Ok(true));
    assert!(pulse.can_advance(&beacon));
    assert_eq!(
        pulse.book.open_quorum_of(
            0,
            &montana_node::agreement::Electorate {
                count: 1,
                committee: 0,
                votes: &std::collections::BTreeMap::new(),
            }
        ),
        Some(previous)
    );

    // And nothing of the store moved on it: the head, the proposals, the last window closed. What
    // stands written is the record of the agreement — the attempt the count authorizes — at attempt
    // zero, with nothing made.
    assert_eq!(
        machine.head().expect("the store answers"),
        Some(WINDOW - 5),
        "a count at the quorum moved the head"
    );
    assert_eq!(
        machine.proposal_of(WINDOW).expect("the store answers"),
        None,
        "a count at the quorum kept a proposal"
    );
    assert_eq!(
        machine.closed_window().expect("the store answers"),
        Some(WINDOW - 5)
    );
    let record = machine
        .agreement_of(WINDOW)
        .expect("the store answers")
        .expect("the record of the agreement stands");
    assert_eq!(record.attempt, 0);
    assert_eq!(record.taken, previous);
    assert!(record.made.is_empty());
    assert_eq!(record.lock, None);
    // No right: a right is issued from the decided roll at the close of the window after, and the
    // store refuses a head onto a window whose proposal it does not hold — the one door.
    assert_eq!(
        machine.finalize(WINDOW),
        Err(montana_node::NodeError::Store(
            mt_store::StoreError::HeadWithoutItsProposal { window: WINDOW }
        )),
        "the head moved onto a window without its proposal"
    );
    assert_eq!(machine.head().expect("the store answers"), Some(WINDOW - 5));
}
