// K7 of item 5 (issue #16), the whole network: every machine of a cohort stops at once and the
// network goes on from where it stood. Consensus, "The way back": "A loss of quorum halts the chain.
// Reconnection resumes the same open window against the same electorate and the same required share";
// "A restart does not create authority". Consensus, "The join": "A device that lived the network holds
// its own anchor — the last two proposals it verified — and needs nobody's". Canon, "The points a
// round stands at": what stands at a machine's points survives for `retained_windows` windows.
//
// **The world outside the rules, arranged by this test.** Two machines and a cohort of the two live
// the first three windows of a network and are both stopped: nothing of the network stands in any
// process. Both start again on their stores, reach each other again and live two windows more. The
// one-machine halt is K1 (`a_machine_started_again_continues_its_chain`); the restart of every holder
// serving a joiner is `a_window_outlives_the_restart_of_every_holder`. Here the cohort of more than one
// itself goes on.
//
// **The wrong implementations it refuses**, named before the assertions: a restart that keeps the
// proposals and not the plane they carry — there a restarted machine stands on tables that are not the
// decided state of the window it closed, and the next window credits over a state nobody else
// recomputes; points that lived in memory alone — there a restarted machine stands at no point and
// serves nothing of the windows it decided; a restart that opens the cohort's electorate again on the
// Genesis State Hash — there the first window after the stop names no proposal the network closed,
// and the chain across the stop is two chains; and a restart that draws a second secret — there the
// cohort after the stop is not the cohort before it.

use montana_node::pulse::{self, Cohort, Lived};
use montana_node::{Configuration, Machine};
use std::path::Path;

mod common;
use common::Scratch;

// The windows lived before the stop, and after the start.
const BEFORE: u64 = 3;
const AFTER: u64 = 2;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the proofs of a machine of this size.
const PATIENCE: u32 = 40_000;

fn id_of(held: &mt_state::layout::Proposal) -> [u8; 32] {
    held.id().expect("an identifier")
}

fn started(at: &Path) -> (Machine, bool) {
    Machine::start(&Configuration::at(at, "127.0.0.1:0")).expect("the machine starts")
}

// The machine `near` reaching `far`, which answers the one link.
fn reached(near: &Machine, far: Machine) -> Machine {
    let line = far.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("a link is answered");
        far
    });
    near.reach_and_hold(&line).expect("the far side answers");
    answering.join().expect("the thread stands")
}

// Both machines live the same windows of one cohort, each in its own thread of the network.
fn lived_together(
    far: Machine,
    near: &Machine,
    halves: &[[u8; 32]; 2],
    from: u64,
    windows: u64,
) -> (Machine, Vec<Lived>, Vec<Lived>) {
    let living = std::thread::spawn({
        let cohort = Cohort::of(halves).expect("the cohort");
        move || {
            let lived = pulse::live(&far, &cohort, from, windows, PATIENCE);
            (far, lived)
        }
    });
    let cohort = Cohort::of(halves).expect("the cohort");
    let mine = pulse::live(near, &cohort, from, windows, PATIENCE).expect("the dialler lives");
    let (far, theirs) = living.join().expect("the thread stands");
    (far, theirs.expect("the answerer lives"), mine)
}

// The seven tables a proposal carries, in the order a plane gives them.
fn tables_of(held: &mt_state::layout::Proposal) -> [[u8; 32]; 7] {
    [
        held.note_root,
        held.nullifier_root,
        held.record_root,
        held.machine_root,
        held.admitted_root,
        held.credited_root,
        held.operations_root,
    ]
}

#[test]
fn a_network_stopped_whole_resumes_on_what_its_machines_kept() {
    let far_at = Scratch::named("whole-answerer");
    let near_at = Scratch::named("whole-dialler");
    let (far, _) = started(&far_at.0);
    let (near, _) = started(&near_at.0);
    let halves = [
        far.naming_half().expect("a half of the answerer"),
        near.naming_half().expect("a half of the dialler"),
    ];
    let far = reached(&near, far);
    let (far, theirs, mine) = lived_together(far, &near, &halves, 0, BEFORE);
    assert_eq!(theirs.len(), BEFORE as usize);
    assert_eq!(mine.len(), BEFORE as usize);
    for machine in [&far, &near] {
        assert_eq!(
            machine.closed_window().expect("the store answers"),
            Some(BEFORE - 1)
        );
        assert_eq!(machine.head().expect("the store answers"), Some(BEFORE - 2));
    }
    let last_closed = near
        .proposal_of(BEFORE - 1)
        .expect("the store answers")
        .expect("the proposal of the last window closed");
    let zero = near
        .proposal_of(0)
        .expect("the store answers")
        .expect("the proposal of window zero");

    // **The whole network stops.** Nothing of it stands in any process.
    drop(far);
    drop(near);

    // Both start again on their stores, under the secrets they always had, each on the decided state
    // of the window it closed and at the points it kept.
    let (far, born) = started(&far_at.0);
    assert!(!born, "a restart drew a second secret");
    let (near, born) = started(&near_at.0);
    assert!(!born, "a restart drew a second secret");
    assert_eq!(
        [
            far.naming_half().expect("a half of the answerer"),
            near.naming_half().expect("a half of the dialler"),
        ],
        halves,
        "the cohort after the stop is not the cohort before it"
    );
    for machine in [&far, &near] {
        assert_eq!(
            machine
                .value()
                .expect("the plane")
                .tables_of(BEFORE - 1)
                .expect("the tables"),
            tables_of(&last_closed),
            "a restarted machine stands on a plane that is not the decided state of the window it closed"
        );
        assert!(
            machine.points_standing() > 0,
            "a restarted machine stands at no point: the points lived in memory alone"
        );
        assert_eq!(
            machine
                .proposal_of(BEFORE - 1)
                .expect("the store answers")
                .map(|held| id_of(&held)),
            Some(id_of(&last_closed))
        );
    }

    // They reach each other again and live on from the window after the last they closed.
    let far = reached(&near, far);
    let (far, theirs, mine) = lived_together(far, &near, &halves, BEFORE, AFTER);
    for lived in [&theirs, &mine] {
        assert_eq!(
            lived.iter().map(|one| one.window).collect::<Vec<_>>(),
            (BEFORE..BEFORE + AFTER).collect::<Vec<_>>()
        );
    }

    // **One chain across the stop, and the same one on both machines**: every window names the
    // proposal of the window before it, the first the Genesis State Hash; the census of window zero is
    // carried whole into every window after it; and both heads stand on the newest decided window.
    let genesis = mt_state::tables::genesis_state_hash().expect("the hash of the network");
    let mut previous = genesis;
    for window in 0..BEFORE + AFTER {
        let held = near
            .proposal_of(window)
            .expect("the store answers")
            .expect("a proposal kept for every window lived");
        assert_eq!(
            far.proposal_of(window)
                .expect("the store answers")
                .map(|other| id_of(&other)),
            Some(id_of(&held)),
            "the two machines closed window {window} on two names"
        );
        assert_eq!(
            held.previous, previous,
            "window {window} links to something else than the proposal before it"
        );
        assert_eq!(
            held.census, zero.census,
            "window {window} forgot the census"
        );
        previous = id_of(&held);
    }
    assert_eq!(
        mine[0].proposal,
        id_of(
            &near
                .proposal_of(BEFORE)
                .expect("the store answers")
                .expect("kept")
        )
    );
    for machine in [&far, &near] {
        assert_eq!(
            machine.head().expect("the store answers"),
            Some(BEFORE + AFTER - 2)
        );
    }
}
