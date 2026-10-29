// A machine away for longer than the retention comes back on a fresh anchor its operator hands it,
// takes the plane of the head from the network over the wire, and lives on from there.
//
// **What is measured.** Consensus, "The join": "a device away longer than that finds no certificate
// to walk and takes a fresh anchor from its operator, which is a change of trust and not a
// verification"; step 5: "It takes the state it needs against the roots of the head ... and it
// recomputes every root it takes rather than accepting one"; step 6: "It then follows the beacons of
// the open window as any machine does, and it is a machine of the network from that moment."
//
// **The world outside the rules, arranged by this test**, as the test of the way back from its own
// anchor arranges it: one machine and a cohort of itself lives the first three windows of a network,
// and what its disk holds then is kept aside twice — the disk of a machine away from that moment on.
// The network lives two windows more; the end of the retention is applied to its disk by the holders'
// own rule (`drop_points_before`), which lets go of the first window the machine away missed and of
// every window before it; and the network lives three windows more and then answers its door. The
// machine away starts under the secret it always had, is told that no certificate stands after its own
// anchor, and is handed the network's proposals of the first two windows past the end of the
// retention as a fresh anchor.
//
// **The wrong implementations it refuses**, named before the assertions: a walk that keeps the
// proposals alone for a machine that holds no state of the head — it holds no plane whose roots are
// the head's and would live a window on a state nobody else verifies; a walk that replays from a state
// of its own older than the anchor, across windows nobody holds any more — the second disk, walking
// with no cohort, is refused there, and the first, handed the cohort, takes the plane instead; a plane
// taken without its roots recomputed (V2 and V3 of the test of the plane of a head, which this one
// rests on); a walk that keeps the plane of the head and not the state of the window the network
// closed on after it — its roots are not those of the proposal awaiting its certificate; and a plane
// held for the life of the process alone — its roots are not the chain's after a restart.

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort};
use montana_node::state::State;
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::Proposal;
use std::path::Path;

mod common;
use common::Scratch;

// The windows lived before the disk is kept aside, those lived before the end of the retention, and
// those lived after it.
const BEFORE: u64 = 3;
const AWAY: u64 = 2;
const AFTER: u64 = 3;

// How many askings a machine spends at one round before giving it up, as the tests of the walk hold it.
const PATIENCE: u32 = 40_000;

const NO_CERTIFICATE: &str = "no certificate to walk; a fresh anchor is a change of trust";

fn refused(what: &'static str) -> NodeError {
    NodeError::Refused { what }
}

fn id_of(held: &Proposal) -> [u8; 32] {
    held.id().expect("an identifier")
}

// The seven roots a plane gives for `window` against `cohort`, in the order a proposal carries them.
fn roots_of(plane: &State, cohort: &Cohort, window: u64) -> [[u8; 32]; 7] {
    let roots = plane
        .roots(cohort, window, &[])
        .expect("the roots of a plane");
    [
        roots.note_root,
        roots.nullifier_root,
        roots.record_root,
        roots.machine_root,
        roots.admitted_root,
        roots.credited_root,
        roots.operations_root,
    ]
}

fn carried_by(proposal: &Proposal) -> [[u8; 32]; 7] {
    [
        proposal.note_root,
        proposal.nullifier_root,
        proposal.record_root,
        proposal.machine_root,
        proposal.admitted_root,
        proposal.credited_root,
        proposal.operations_root,
    ]
}

// A directory copied whole, files and directories, as a disk is copied.
fn copied(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).expect("a directory to copy into");
    for entry in std::fs::read_dir(from).expect("a directory to copy") {
        let entry = entry.expect("an entry");
        let at = to.join(entry.file_name());
        if entry.file_type().expect("a type").is_dir() {
            copied(&entry.path(), &at);
        } else {
            std::fs::copy(entry.path(), &at).expect("a file copied");
        }
    }
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

#[test]
fn a_machine_away_past_the_retention_comes_back_on_a_fresh_anchor_and_lives_on() {
    let at = Scratch::named("past-network");
    let aside = Scratch::named("past-disk");
    let aside_again = Scratch::named("past-disk-again");
    let (network, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[network.naming_half().expect("a half")]).expect("a cohort of itself");
    pulse::live(&network, &cohort, 0, BEFORE, PATIENCE).expect("the first windows");
    copied(&at.0, &aside.0.join("disk"));
    copied(&at.0, &aside_again.0.join("disk"));
    pulse::live(&network, &cohort, BEFORE, AWAY, PATIENCE).expect("the network goes on");

    // The end of the retention, by the holders' own rule: the points of the first window the machine
    // away missed, and of every window before it, go from the one holder.
    drop(network);
    mt_store::Store::open(&at.0)
        .expect("the network's store opens")
        .drop_points_before(BEFORE + 1)
        .expect("the points of the windows past the retention go");
    let (network, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the network starts again");
    let lived = pulse::live(&network, &cohort, BEFORE + AWAY, AFTER, PATIENCE)
        .expect("the network lives on past the retention");
    assert_eq!(lived.len(), AFTER as usize);
    let open = BEFORE + AWAY + AFTER;
    let head = open - 2;
    assert_eq!(network.head().expect("the store answers"), Some(head));
    assert_eq!(
        network.closed_window().expect("the store answers"),
        Some(head + 1)
    );
    let closed_on = network
        .proposal_of(head + 1)
        .expect("the store answers")
        .expect("the network's last proposal");
    let fresh = Anchor {
        earlier: network
            .proposal_of(BEFORE + 1)
            .expect("the store answers")
            .expect("kept"),
        later: network
            .proposal_of(BEFORE + 2)
            .expect("the store answers")
            .expect("kept"),
    };

    // **With no cohort the machine away does not come back.** Its own anchor finds no certificate; the
    // fresh one walks, but the state it holds stands on windows the retention let go of, and the walk
    // is refused with its head and its closed window where they were.
    let (late, born) = Machine::start(&Configuration::at(
        aside_again.0.join("disk"),
        "127.0.0.1:0",
    ))
    .expect("the second disk starts");
    assert!(!born, "the disk kept aside drew a second secret");
    let network = reached(&late, network);
    assert_eq!(
        pulse::come_back(&late, open, PATIENCE),
        Err(refused(NO_CERTIFICATE))
    );
    assert_eq!(
        pulse::join(&late, &fresh, PATIENCE).map(|_| ()),
        Err(refused(
            "a walked window whose proposal stands at none of its points"
        ))
    );
    assert_eq!(late.head().expect("the store answers"), Some(BEFORE - 2));
    assert_eq!(
        late.closed_window().expect("the store answers"),
        Some(BEFORE - 1)
    );
    drop(late);

    // **Handed the cohort, it walks the fresh anchor and takes the plane of the head over the wire.**
    let (back, born) = Machine::start(&Configuration::at(aside.0.join("disk"), "127.0.0.1:0"))
        .expect("the machine away starts");
    assert!(!born, "the disk kept aside drew a second secret");
    assert_eq!(back.head().expect("the store answers"), Some(BEFORE - 2));
    let network = reached(&back, network);
    assert_eq!(
        pulse::come_back(&back, open, PATIENCE),
        Err(refused(NO_CERTIFICATE))
    );
    let walked = pulse::join_under(&back, &fresh, &cohort, PATIENCE)
        .expect("the walk on a fresh anchor, with the plane of its head");
    assert_eq!(walked.later.window, head);
    assert_eq!(back.head().expect("the store answers"), Some(head));
    assert_eq!(
        back.closed_window().expect("the store answers"),
        Some(head + 1)
    );
    for window in [head - 1, head, head + 1] {
        assert_eq!(
            back.proposal_of(window)
                .expect("the store answers")
                .map(|held| id_of(&held)),
            network
                .proposal_of(window)
                .expect("the store answers")
                .map(|held| id_of(&held)),
            "the walk kept another proposal of window {window} than the network's"
        );
    }

    // What it holds is the state of the window the network closed on, the plane of the head taken and
    // the roll of the proposal after it replayed over it, and the plane of the head as the state before.
    let chain = carried_by(&closed_on);
    assert_eq!(
        roots_of(&back.value().expect("the plane"), &cohort, head + 1),
        chain
    );
    let of_the_head = network
        .proposal_of(head)
        .expect("the store answers")
        .expect("the network's head");
    assert_eq!(
        roots_of(
            &back
                .plane_of(head)
                .expect("the store answers")
                .expect("the state before"),
            &cohort,
            head
        ),
        carried_by(&of_the_head)
    );

    // It holds them after a restart.
    drop(back);
    let (back, born) = Machine::start(&Configuration::at(aside.0.join("disk"), "127.0.0.1:0"))
        .expect("the machine come back starts again");
    assert!(!born, "a restart drew a second secret");
    assert_eq!(
        roots_of(&back.value().expect("the plane"), &cohort, head + 1),
        chain
    );
    let _network = reached(&back, network);

    // **And it lives on from the window the network stands at**, on the proposal the network closed on.
    let again = pulse::live(&back, &cohort, open, 2, PATIENCE).expect("the machine lives on");
    assert_eq!(
        again.iter().map(|one| one.window).collect::<Vec<_>>(),
        vec![open, open + 1]
    );
    let own = back
        .proposal_of(open)
        .expect("the store answers")
        .expect("the window it lived on");
    assert_eq!(
        own.previous,
        id_of(&closed_on),
        "the machine come back stands on another proposal than the one the network closed on"
    );
    assert_eq!(back.head().expect("the store answers"), Some(open));
}
