// A machine stopped inside an open window, after it pledged, resumes that window under the name it
// pledged. Consensus, "The way back": "Reconnection resumes the same open window against the same
// electorate and the same required share"; "an honest machine preserves its attempt, its lock and
// every pledge it made across changes of round, process restart and crash"; its invariants: "Honest
// signing locks survive restart and never expire on a clock or a round count". Consensus, "What a
// machine holds of the agreement": the record is kept "before it publishes anything they govern, and
// through a restart, because a machine that forgot a pledge could sign its contradiction".
//
// **The world outside the rules, arranged by this test.** One machine and a cohort of itself lives
// the first two windows of a network and opens the third. Once its closing pledge of that window
// stands in its record, the directory its proposals are kept in is taken from under it — a disk that
// fails, which is what a crash is to a store — and the machine stops inside the window: its record
// stands, its window is not closed, its head is where it was. The directory is put back, the machine
// is started again on its store, refused the window under a record naming another proposal of the
// window before, and then lives the window it was stopped in and the one after it.
//
// **The wrong implementations it refuses**, named before the assertions: the pulse of e6c1d7bf, which
// starts every life with no proposal held — there the window the machine was stopped in, the third of
// the network, stands on no proposal two before and is refused, and before that commit it was opened
// on the Genesis State Hash, which the record names no more, and refused as "already pledged under
// another name" though the record is the machine's own; and a pulse that opens a fresh record over
// the one it finds, or compares nothing — there the record naming another proposal is opened too, and
// the machine pledges a second name for one window.

use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine, NodeError};
use std::time::Duration;

mod common;
use common::Scratch;

// The window the machine is stopped in: the third of the network, past the two the opening cohort
// stands for.
const STOPPED: u64 = 2;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the proofs of a machine of this size.
const PATIENCE: u32 = 40_000;

#[test]
fn a_machine_stopped_after_its_pledge_resumes_the_window_under_the_name_it_pledged() {
    let at = Scratch::named("stopped-inside");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[machine.naming_half().expect("a half")]).expect("a cohort of itself");
    pulse::live(&machine, &cohort, 0, STOPPED, PATIENCE).expect("the first windows");
    let before = machine
        .proposal_of(STOPPED - 1)
        .expect("the store answers")
        .expect("the proposal of the window before")
        .id()
        .expect("an identifier");

    // The machine lives the window it is stopped in, and is stopped once its closing pledge stands
    // in its record: the directory of its proposals becomes a file, so the next proposal it keeps,
    // or the head it moves onto one, fails as a disk fails.
    let proposals = at.0.join("proposals");
    let aside = at.0.join("proposals-aside");
    let stopped = std::thread::scope(|scope| {
        let living = scope.spawn(|| pulse::live(&machine, &cohort, STOPPED, 1, PATIENCE));
        loop {
            let pledged = machine
                .agreement_of(STOPPED)
                .expect("the store answers")
                .is_some_and(|record| record.lock.is_some());
            if pledged || living.is_finished() {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        std::fs::rename(&proposals, &aside).expect("the directory is taken");
        std::fs::write(&proposals, b"").expect("a file in its place");
        living.join().expect("the thread stands")
    });
    std::fs::remove_file(&proposals).expect("the file goes");
    std::fs::rename(&aside, &proposals).expect("the directory is put back");
    assert!(
        stopped.is_err(),
        "the machine closed the window before it could be stopped"
    );
    let record = machine
        .agreement_of(STOPPED)
        .expect("the store answers")
        .expect("the record of the window it was stopped in");
    assert_eq!(record.taken, before);
    let lock = record.lock.expect("its closing pledge");
    assert_eq!(lock.0, before);
    assert_eq!(
        machine.closed_window().expect("the store answers"),
        Some(STOPPED - 1)
    );
    drop(machine);

    // Started again: refused the window under a record naming another proposal of the window before,
    // with the record as it stood written nowhere over.
    let (machine, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts again");
    assert!(!born, "a restart drew a second secret");
    let mut astray = record.clone();
    astray.taken[0] ^= 1;
    machine.keep_agreement(&astray).expect("the store takes it");
    assert_eq!(
        pulse::live(&machine, &cohort, STOPPED, 1, PATIENCE).map(|_| ()),
        Err(NodeError::Refused {
            what: "a window this machine already pledged under another name"
        })
    );
    assert_eq!(
        machine.agreement_of(STOPPED).expect("the store answers"),
        Some(astray)
    );
    machine
        .keep_agreement(&record)
        .expect("the store takes it back");

    // The honest start: the window it was stopped in, under the name and the lock it pledged, and the
    // window after it.
    let lived = pulse::live(&machine, &cohort, STOPPED, 2, PATIENCE).expect("the window resumes");
    assert_eq!(
        lived.iter().map(|one| one.window).collect::<Vec<_>>(),
        vec![STOPPED, STOPPED + 1]
    );
    let resumed = machine
        .proposal_of(STOPPED)
        .expect("the store answers")
        .expect("the proposal of the window it was stopped in");
    assert_eq!(resumed.previous, before);
    assert_eq!(resumed.cement_count, 1, "its own part is not in the cement");
    assert_eq!(lived[0].living, 1);
    assert_eq!(
        lived[0].proposal,
        resumed.id().expect("an identifier"),
        "the window was reported final under another name than it keeps"
    );
    assert_eq!(
        machine
            .proposal_of(STOPPED + 1)
            .expect("the store answers")
            .expect("kept")
            .previous,
        lived[0].proposal
    );
    assert_eq!(machine.head().expect("the store answers"), Some(STOPPED));
    assert_eq!(
        machine.closed_window().expect("the store answers"),
        Some(STOPPED + 1)
    );
}
