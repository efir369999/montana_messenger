// A machine stopped and started again holds the value plane it held.
//
// **What is measured.** A note takes a position in the tree of notes, and a path is proven against
// that tree — so a plane that lived in memory alone made every note die with the run that created
// it: a person paid in one run held a note their own machine could no longer prove a path for in
// the next, and the machine refused the payment naming a note its tree does not hold. That is the
// defect this vector stands against, and it was found on three hosts rather than here.
//
// **The wrong implementations it refuses**, named before the assertions: one writing the counts
// from the other end, which reads a plane of a hundred thousand leaves where three stand; one
// taking the leaves for commitments, which rebuilds a tree of another root entirely; one reading a
// plane in part rather than whole; and one that keeps nothing at all, which answers the empty
// plane and fails at the last assertion below.

use montana_node::pulse::Cohort;
use montana_node::state::State;
use montana_node::{Closing, Configuration, Machine};

mod common;
use common::{proposal_over, Scratch};

// A digest of the family, standing on neither end of its own bytes.
fn digest(mark: u8) -> mt_proof::poseidon::Digest {
    let mut out = [0u8; 32];
    out[0] = mark;
    out[7] = 0x5C;
    out[31] = (mark ^ 0xEE) & 0x7F;
    mt_proof::poseidon::Digest::of_bytes(&out).expect("a digest of the family")
}

#[test]
fn a_plane_written_reads_back_as_the_plane_it_was() {
    let mut held = State::new();
    // Leaves that differ at both ends, so an implementation reading a commitment from the low end
    // or the high one reproduces neither the count nor the root.
    for mark in [0x01u8, 0x40, 0x7E] {
        let mut commitment = [0u8; 32];
        commitment[0] = mark;
        commitment[31] = (mark ^ 0x33) & 0x7F;
        held.witness(&commitment).expect("the tree takes it");
    }
    held.admits(digest(0x22));
    let before = held.notes_root();
    let held_notes = held.notes_held();

    let bytes = held.encode().unwrap();
    let back = State::decode(&bytes).expect("a plane this machine wrote reads back");
    assert_eq!(back.notes_held(), held_notes, "the count of notes moved");
    assert_eq!(
        back.notes_root().bytes(),
        before.bytes(),
        "the tree rebuilt from the leaves is not the tree that was written"
    );
    assert_eq!(
        back.admitted().bytes(),
        digest(0x22).bytes(),
        "the tree of admitted machines did not survive the writing"
    );
    assert_eq!(
        back.path_of(1).map(|p| p.len()),
        held.path_of(1).map(|p| p.len()),
        "a path this plane could walk cannot be walked after it was written"
    );

    // A plane longer or shorter than it declares is refused whole rather than read in part.
    let mut clipped = bytes.clone();
    clipped.pop();
    assert!(
        State::decode(&clipped).is_err(),
        "a plane shorter than it declares was read as if it were whole"
    );
    let mut over = bytes.clone();
    over.push(0);
    assert!(
        State::decode(&over).is_err(),
        "a plane longer than it declares was read as if it were whole"
    );
}

// **What stands across a stop is the plane of the last window closed.** The plane a machine holds
// is kept in the record of the close of a window (issue #19: the tables, the proposal, the state and
// the record of a window survive a crash together), and what the plane took after that close — the
// part of a window still open — is not on the disk until its own close. The wrong implementations
// refused besides those above: one keeping nothing, which starts on the empty plane; and one
// keeping the plane of the open window as it moves, which starts on a plane no close of this machine
// ever named.
#[test]
fn a_machine_started_again_stands_on_the_plane_of_its_last_close() {
    let at = Scratch::named("keeping");
    let secret = [0x5Eu8; 32];
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).expect("a cohort of one stands");
    let closed_on = {
        let (machine, born) =
            Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("a machine starts");
        assert!(born, "a first start draws a secret");
        machine
            .admits_the_tree(cohort.root())
            .expect("the plane takes the tree of admitted machines");
        machine
            .value()
            .expect("the plane")
            .witness(&digest(0x41).bytes())
            .expect("the tree takes it");
        let plane = machine.value().expect("the plane").clone();
        machine
            .close(Closing {
                head: None,
                taken: proposal_over(4_000, [0x10; 32], &plane, &cohort, 0xA1),
                plane: plane.clone(),
                before: None,
                census: None,
            })
            .expect("the window closes");
        // The open window after it moves the plane; no close keeps that.
        machine
            .admits_the_tree(digest(0x51))
            .expect("the plane takes another tree");
        plane.encode().expect("a plane encodes")
    };
    // The machine is gone; nothing of it stands but what it wrote.
    let (again, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("a machine starts again");
    assert!(!born, "a later start takes the secret that stands");
    let plane = again.value().expect("the plane");
    assert_eq!(
        plane.admitted().bytes(),
        cohort.root().bytes(),
        "a machine started again stands on a plane no close of it named"
    );
    assert_eq!(
        plane.encode().expect("a plane encodes"),
        closed_on,
        "a machine started again stands on another plane than its last close, so every note it held is unprovable"
    );
}
