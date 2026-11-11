// CNS-20 / issue #21 F4: a patience that runs out closes nothing. At a patience exit of the live
// pulse the head, the last window closed, the proposals kept, the note root and the census windows
// stand as they stood before the wait; the record of the agreement the wait made survives a restart
// unchanged; the reading is the stall; and the restarted machine opens the same store and goes on
// as the cold start lets it: its store holds the record of the agreement on window 0 and closed no
// window, so it holds a chain and no anchor, living window 0 again is refused before anything is
// written, and it enters the network only from an anchor by "The join" (Consensus, "The cold
// start"). CNS-20 is the anchor: Consensus, "The liveness price" -- monitoring reports these
// conditions and authorizes no transition.
//
// The patience exits of pulse.rs, and the test of each here:
//   1. `a round no beacon ever stood at` -- exit_one_...;
//   2. `waiting budget exhausted`, with the final beacon held and the agreement undecided --
//      exit_two_...;
//   3. `a decided proposal that never stood at the points with its roll` -- not reached here: its
//      world is a window after a close whose agreement decides another name, and a machine of this
//      tree neither starts a pulse at a window past the first nor takes a deposit at a round it has
//      left, so a fixture of one process cannot arrange it;
//   4. `a window no proposal of its decision ever stood at` -- exit_four_....
//
// **The wrong implementation it refuses**, named before the assertions: a pulse whose patience,
// running out, closes the window anyway -- on the name it took (exit 2) or on a proposal it
// assembled itself (exit 4). On it the pulse returns no stall and the last window closed moves.

use montana_node::attempt::Record;
use montana_node::attest::LivedCensus;
use montana_node::pulse::{self, withhold, Cohort};
use montana_node::say::{PulseStatus, Verdict};
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::Proposal;

mod common;
use common::{stall, Scratch};

// The cap on every wait of the restarted machine asked to live again.
const PATIENCE: u32 = 24_000;

// What only a close moves.
#[derive(Debug, PartialEq)]
struct Closes {
    head: Option<u64>,
    closed: Option<u64>,
    kept: Option<[u8; 32]>,
    notes: [u8; 32],
    census: Vec<LivedCensus>,
}

fn closes(machine: &Machine) -> Closes {
    Closes {
        head: machine.head().unwrap(),
        closed: machine.closed_window().unwrap(),
        kept: machine
            .proposal_of(0)
            .unwrap()
            .map(|held| held.id().unwrap()),
        notes: machine.value().unwrap().notes_root().bytes(),
        census: machine.lived_census().unwrap(),
    }
}

fn agreement(machine: &Machine) -> Option<Record> {
    machine.agreement_of(0).unwrap()
}

fn start(at: &Scratch) -> Machine {
    let (machine, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the store opens");
    assert!(!born, "a restart drew a second secret");
    machine
}

// The stall the pulse returned and the reading of it; nothing of a close moved; then the same store
// opened again, where nothing of a close moved either and the record of the agreement is the one
// the wait made.
fn stalled_then_restarted(
    at: &Scratch,
    machine: Machine,
    before: &Closes,
    lived: Result<Vec<pulse::Lived>, NodeError>,
    on: Verdict,
    what: &'static str,
) -> Machine {
    assert_eq!(
        lived.map(|_| ()),
        Err(NodeError::Stalled { on, what }),
        "the patience did not end in its stall"
    );
    let reading = machine.counts().status().expect("a reading of the stall");
    assert_eq!(reading.on(), Some(on), "{reading:?}");
    assert!(
        matches!(reading, PulseStatus::Stalled { .. }),
        "{reading:?}"
    );
    assert_eq!(reading.exit_code(), on.exit_code());
    assert_eq!(
        &closes(&machine),
        before,
        "the timeout moved what a close moves"
    );
    let made = agreement(&machine);
    assert!(
        made.is_some(),
        "the window the wait stood in kept no record"
    );
    drop(machine);
    let again = start(at);
    assert_eq!(
        &closes(&again),
        before,
        "a restart moved what a close moves"
    );
    assert_eq!(
        agreement(&again),
        made,
        "a restart lost the record of the agreement"
    );
    again
}

// The restarted machine goes on as the cold start lets it: asked to live window 0 again, it is
// refused as a store that holds a chain, and the refusal writes nothing of a close or of the
// agreement.
fn goes_on(again: &Machine, cohort: &Cohort) {
    let closed = closes(again);
    let made = agreement(again);
    assert_eq!(
        pulse::live(again, cohort, 0, 1, PATIENCE).map(|_| ()),
        Err(NodeError::Refused {
            what: "a network opened on a store that holds a chain"
        })
    );
    assert_eq!(
        closes(again),
        closed,
        "a refused start moved what a close moves"
    );
    assert_eq!(
        agreement(again),
        made,
        "a refused start moved the record of the agreement"
    );
}

#[test]
fn exit_one_a_round_no_beacon_stood_at_closes_nothing_and_a_restart_goes_on() {
    let at = Scratch::named("patience-no-beacon");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[machine.naming_half().unwrap()]).expect("a cohort of itself");
    let before = closes(&machine);
    // One round ahead of the round it opens, so its own beacon falls at points it does not hold.
    let ahead =
        |machine: &Machine, window: u64| machine.enter_round(window, pulse::opening_chain(), 1);
    let lived = pulse::live_doing(&machine, &cohort, 0, 1, 4, Some(&ahead));
    let again = stalled_then_restarted(
        &at,
        machine,
        &before,
        lived,
        Verdict::NoData,
        "a round no beacon ever stood at",
    );
    goes_on(&again, &cohort);
}

#[test]
fn exit_two_an_agreement_undecided_at_the_final_beacon_closes_nothing_and_a_restart_goes_on() {
    let (at, machine, cohort) = stall::machine("patience-undecided");
    let before = closes(&machine);
    let withheld = |machine: &Machine, _| stall::cut_closing_pledges(machine, &cohort);
    let lived = pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&withheld));
    let again = stalled_then_restarted(
        &at,
        machine,
        &before,
        lived,
        Verdict::NoQuorum,
        "waiting budget exhausted: agreement undecided; window unchanged",
    );
    assert!(
        agreement(&again).is_some_and(|record| !record.made.is_empty()),
        "the wait made no closing pledge of its own"
    );
    goes_on(&again, &cohort);
}

#[test]
fn exit_four_a_window_no_proposal_stood_at_closes_nothing_and_a_restart_goes_on() {
    let at = Scratch::named("patience-no-proposal");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[machine.naming_half().unwrap()]).expect("a cohort of itself");
    let before = closes(&machine);
    // The proposal of window 0 it proves of its own is held back: no proposal of its decision ever
    // stands at the points.
    withhold::own_proposals(Some(Box::new(|_: &Machine, own: &Proposal| {
        own.window == 0
    })));
    let lived = pulse::live(&machine, &cohort, 0, 1, 400);
    withhold::own_proposals(None);
    let again = stalled_then_restarted(
        &at,
        machine,
        &before,
        lived,
        Verdict::NoData,
        "a window no proposal of its decision ever stood at",
    );
    goes_on(&again, &cohort);
}
