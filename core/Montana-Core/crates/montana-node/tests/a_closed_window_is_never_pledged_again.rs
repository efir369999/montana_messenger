// A window this machine closed is never pledged again. Consensus, "What a machine holds of the
// agreement": the record of the agreement is kept "before it publishes anything they govern, and
// through a restart, because a machine that forgot a pledge could sign its contradiction; it lets
// them go when the window they govern closes"; the invariants of the agreement: a machine "never
// signs two open pledges or two closing pledges of one attempt on two names"; "The way back": "an
// honest machine preserves its attempt, its lock and every pledge it made across changes of round,
// process restart and crash". The record goes at the close, so what refuses the closed window
// afterwards is one number — the last window this machine closed — written before the record is
// let go, and read by the opening of a window and the entering of a round.
//
// **The wrong implementations it refuses**, named before the assertions: one that drops the record
// at the close and keeps nothing in its place, so a restart opens the closed window afresh with an
// empty record and pledges a second name for it; one that lets the head move back onto a window
// below a decided one, which "A decided window is never abandoned" (Consensus, "Finality") refuses.

use montana_node::certificate::empty_census;
use montana_node::pulse::{Cohort, Pulse};
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::Proposal;

mod common;
use common::Scratch;

const WINDOW: u64 = 2_700;

fn refused(what: &'static str) -> NodeError {
    NodeError::Refused { what }
}

// A proposal the store can hold under its window: what the head is moved onto here, and nothing
// the test verifies.
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
fn a_window_this_machine_closed_is_refused_running_and_after_a_restart() {
    let at = Scratch::named("closed-window");
    let secret = [0x73u8; 32];
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).expect("a cohort of one stands");
    let branch = cohort.branch_of(&secret).expect("its own leaf");
    let aggregate = [0x37u8; 32];
    let electorate = montana_node::certificate::Electorate::opening(cohort.root(), 1, WINDOW)
        .expect("an opening electorate stands");
    let taken = [0x42u8; 32];
    let other = [0x43u8; 32];
    let open = |machine: &Machine, window: u64, name: [u8; 32]| {
        Pulse::open(
            machine,
            &secret,
            (window, 0, 0),
            &branch,
            name,
            [0x41u8; 32],
            &electorate,
            &aggregate,
        )
    };

    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    assert_eq!(machine.closed_window().expect("the store answers"), None);
    let pulse = open(&machine, WINDOW, taken).expect("the window opens");
    assert_eq!(pulse.record.taken, taken);
    assert_eq!(
        machine
            .agreement_of(WINDOW)
            .expect("the store answers")
            .map(|record| record.taken),
        Some(taken),
        "the record was not written before anything it governs"
    );
    drop(pulse);

    // The window closes: the number first, then the record.
    machine.let_go_of(WINDOW).expect("the window is let go");
    assert_eq!(
        machine.closed_window().expect("the store answers"),
        Some(WINDOW)
    );
    assert_eq!(
        machine.agreement_of(WINDOW).expect("the store answers"),
        None
    );

    // Still running: the closed window is refused under another name, and so is a round of it.
    assert_eq!(
        open(&machine, WINDOW, other).err(),
        Some(refused("a window this machine already closed"))
    );
    assert_eq!(
        machine.enter_round(WINDOW, 0, 0),
        Err(refused("a round of a window this machine already closed"))
    );
    drop(machine);

    // After a restart: the same, with nothing of the window standing but the number.
    let (again, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts again");
    assert!(!born);
    assert_eq!(
        again.closed_window().expect("the store answers"),
        Some(WINDOW)
    );
    assert_eq!(again.agreement_of(WINDOW).expect("the store answers"), None);
    assert_eq!(
        open(&again, WINDOW, other).err(),
        Some(refused("a window this machine already closed"))
    );
    assert_eq!(
        open(&again, WINDOW - 1, other).err(),
        Some(refused("a window this machine already closed"))
    );
    let next = open(&again, WINDOW + 1, other).expect("the window after opens");
    assert_eq!(next.record.taken, other);
    assert_eq!(
        again.round_of_the_machine(),
        Some((WINDOW + 1, 0, 0)),
        "the window after was opened without entering its first round"
    );

    // The head never leaves a decided window.
    again
        .keep_proposal(&kept(WINDOW))
        .expect("a proposal is kept");
    again
        .keep_proposal(&kept(WINDOW + 1))
        .expect("a proposal is kept");
    again.finalize(WINDOW + 1).expect("the head moves forward");
    assert_eq!(
        again.finalize(WINDOW),
        Err(refused("a head that leaves a decided window"))
    );
    again
        .finalize(WINDOW + 1)
        .expect("the head stands where it is");
    assert_eq!(again.head().expect("the store answers"), Some(WINDOW + 1));
}
