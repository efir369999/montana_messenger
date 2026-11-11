// A machine starts only on a plane the proposal kept beside it carries. Issue #19, step K3: what a
// machine reads back of the record of its last close is held to the proposal that record keeps for
// the window it closed, before the machine lives on it. Canon, "The roots of state": every verifier
// recomputes the roots "from the state it holds once the frames of the window have applied", so a
// plane whose roots are not those of its proposal is a state no proposal of the network names.
//
// **What is measured.** A machine closes one window over a plane of three notes and stops. Its
// record is then changed on the disk in one place — one note of the plane, or one root of the
// proposal kept beside it — every byte still reading back whole, and the machine is started on it.
// The start is refused, with the record, the proposal and the lock as they were: the same machine
// starts again on the bytes its close wrote, on the roots it closed on. The wrong implementation
// each test refuses is named above it.

use montana_node::pulse::Cohort;
use montana_node::state::State;
use montana_node::{Closing, Configuration, Kept, Machine, NodeError};
use mt_state::Layout;
use std::path::Path;

mod common;
use common::{proposal_over, Scratch};

const WINDOW: u64 = 4_400;

const REFUSED: NodeError = NodeError::Refused {
    what: "a kept plane whose roots are not those of the proposal kept beside it",
};

// A commitment of the family the tree of notes takes, one for each mark.
fn commitment(mark: u8) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[0] = mark;
    out[31] = (mark ^ 0x33) & 0x7F;
    out
}

fn start(root: &Path) -> Result<Machine, NodeError> {
    Machine::start(&Configuration::at(root, "127.0.0.1:0")).map(|(machine, _)| machine)
}

fn record_at(root: &Path) -> Vec<u8> {
    std::fs::read(root.join("window")).expect("a record of a window stands")
}

fn proposal_at(root: &Path) -> Vec<u8> {
    std::fs::read(root.join("proposals").join(format!("{WINDOW:020}")))
        .expect("the proposal of the window closed stands")
}

// A machine that closed one window over a plane of three notes and stopped, and the plane.
fn closed(name: &str) -> (Scratch, State) {
    let at = Scratch::named(name);
    let cohort = Cohort::of(&[Cohort::half_of(&[0x5Fu8; 32])]).expect("a cohort of one stands");
    let machine = start(&at.0).expect("a machine starts");
    let mut plane = State::new();
    plane.admits(cohort.root());
    for mark in [0x01u8, 0x40, 0x7E] {
        plane.witness(&commitment(mark)).expect("the tree takes it");
    }
    machine
        .close(Closing {
            head: None,
            taken: proposal_over(WINDOW, [0x10; 32], &plane, &cohort, 0xA1),
            plane: plane.clone(),
            before: None,
            census: None,
        })
        .expect("the window closes");
    (at, plane)
}

// The record of the window rewritten on the disk with `kept` in place of what the close kept, its
// head and its number as they stand. No machine holds the root while it is rewritten.
fn rewrite(root: &Path, kept: &[u8]) {
    let store = mt_store::Store::open(root).expect("the store opens");
    let mut record = store.window().expect("a record reads");
    drop(store);
    record.kept = zeroize::Zeroizing::new(kept.to_vec());
    std::fs::write(root.join("window"), record.encode()).expect("the record is rewritten");
}

fn kept_at(root: &Path) -> Vec<u8> {
    let store = mt_store::Store::open(root).expect("the store opens");
    let record = store.window().expect("a record reads");
    record.kept.to_vec()
}

// A changed record is refused at the start and changes nothing: the record and the proposal stand
// byte for byte, and the machine starts again once the bytes of its close are back.
fn refused_and_untouched(root: &Path, written: &[u8], changed: &[u8]) {
    rewrite(root, changed);
    let record = record_at(root);
    let proposal = proposal_at(root);
    assert_eq!(start(root).err(), Some(REFUSED));
    assert_eq!(
        record_at(root),
        record,
        "a refused start rewrote the record"
    );
    assert_eq!(
        proposal_at(root),
        proposal,
        "a refused start rewrote the proposal"
    );
    rewrite(root, written);
    drop(start(root).expect("the machine starts again on what its close wrote"));
}

// The wrong implementation it rejects: a start that takes the plane it reads back for its value
// state as soon as it decodes, under which a note changed on the disk becomes a note this machine
// proves paths for and no proposal names.
#[test]
fn a_plane_with_one_note_changed_on_the_disk_is_refused_at_start() {
    let (at, _) = closed("start-note-changed");
    let written = kept_at(&at.0);
    // The plane stands after the proposal and the length of each; its first note four bytes after
    // the count of the notes. One bit of its low end moves, so the note stays of the family.
    let mut width = [0u8; 8];
    width.copy_from_slice(&written[..8]);
    let first_note = 8 + u64::from_le_bytes(width) as usize + 8 + 4;
    let mut changed = written.clone();
    changed[first_note] ^= 0x01;
    let read = Kept::decode(&changed).expect("the changed record still reads back whole");
    let held = Kept::decode(&written).expect("the record reads back");
    assert_ne!(read.plane.notes_root(), held.plane.notes_root());
    assert_eq!(read.plane.notes_held(), held.plane.notes_held());
    refused_and_untouched(&at.0, &written, &changed);
}

// The wrong implementation it rejects: a start that holds the plane to nothing but its own shape,
// under which a record whose proposal changed on the disk starts a machine whose plane that
// proposal does not carry.
#[test]
fn a_kept_proposal_with_one_root_changed_on_the_disk_is_refused_at_start() {
    let (at, _) = closed("start-root-changed");
    let written = kept_at(&at.0);
    let mut kept = Kept::decode(&written).expect("the record reads back");
    kept.taken.nullifier_root[0] ^= 0x01;
    let changed = kept.encode().expect("the changed record encodes");
    Kept::decode(&changed).expect("the changed record still reads back whole");
    refused_and_untouched(&at.0, &written, &changed);
}

// The wrong implementation it rejects: a check that refuses what a close of this machine wrote —
// one comparing the plane with the archived proposal, or with a roll and a count it cannot
// recompute — under which no machine starts again on its own close.
#[test]
fn a_record_its_close_wrote_starts_on_the_roots_it_closed_on() {
    let (at, plane) = closed("start-good");
    let roots = plane.tables_of(WINDOW).expect("the roots of a plane");
    let machine = start(&at.0).expect("the machine starts again on what its close wrote");
    let held = machine.value().expect("the plane");
    assert_eq!(held.tables_of(WINDOW).expect("the roots of a plane"), roots);
    assert_eq!(
        held.encode().expect("a plane encodes"),
        plane.encode().expect("a plane encodes")
    );
    let taken = mt_state::layout::Proposal::parse(&proposal_at(&at.0)).expect("a proposal");
    assert_eq!(
        roots,
        [
            taken.note_root,
            taken.nullifier_root,
            taken.record_root,
            taken.machine_root,
            taken.admitted_root,
            taken.credited_root,
            taken.operations_root,
        ]
    );
}
