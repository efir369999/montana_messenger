// A machine that took the plane of its head from the network stakes and proposes nothing until the
// stride of the horizon changes, and follows the decided rolls meanwhile.
//
// **What is measured.** The author's decision 332 (b), constitution record 339: "a machine that took
// its plan from the network does not put up a stake or a proposal until the stride of the horizon
// changes; it only follows decided rolls -- no new wire and no genesis change; price: up to 128
// windows without its vote." Consensus, "The join"; Canon, "The nullifier of the rate of payment": a
// rate nullifier already presented against the standing stride is refused, and a walk reads the frames
// of the windows it walked alone, so the rate set of a plane taken from the network lacks every value
// presented before its anchor in the stride standing for its head.
//
// **The world outside the rules, arranged by this test**, as the test of a machine away past the
// retention arranges it: one machine and a cohort of itself lives the first three windows of a network,
// and what its disk holds then is kept aside — the disk of a machine away from that moment on. The
// network lives two windows more, the end of the retention is applied to its disk by the holders' own
// rule, and the network lives three windows more. The machine away walks a fresh anchor handed by its
// operator and takes the plane of the head over the wire, in the middle of a stride: the head is window
// 6, and the standing stride first changes at window 129.
//
// **The wrong implementations it refuses**, named before the assertions: a machine on a plane of the
// network that lives the window the network stands at — it pledges, attests and proposes on a rate set
// with a hole in it (the mutant that removes the wait, and the code of b56f306, where it lives on); a
// wait one window shorter — it stakes in the last window of the stride it took its plane in; a mark
// held for the life of the process alone — a restart stakes at once; a mark lost by the close of a
// walk that follows — the machine stakes as soon as it followed the chain once; and a wait that stops
// following — its head stays where the walk left it while the network decides on.

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort};
use montana_node::state::State;
use montana_node::{Configuration, Machine, NodeError};
use mt_proof::horizon::standing_stride;
use mt_state::layout::Proposal;
use std::path::Path;

mod common;
use common::Scratch;

// The windows lived before the disk is kept aside, those lived before the end of the retention, those
// lived after it, and those the network lives while the machine follows it.
const BEFORE: u64 = 3;
const AWAY: u64 = 2;
const AFTER: u64 = 3;
const FOLLOWED: u64 = 2;

// How many askings a machine spends at one round before giving it up, as the tests of the walk hold it.
const PATIENCE: u32 = 40_000;

const WAITS: &str =
    "a machine on a plane of the network stakes and proposes nothing before the stride of the horizon changes";

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

// The first window after `head` whose standing stride is another, read off the integer form of the
// horizon window by window, and not off the arithmetic the node computes it by.
fn next_stride_by_the_horizon(head: u64) -> u64 {
    (head + 1..)
        .find(|window| standing_stride(*window) != standing_stride(head))
        .expect("a stride after every head")
}

// What a machine asked to live `window` before its stride changed has written of it: nothing.
fn wrote_nothing_of(machine: &Machine, window: u64, head: u64) {
    assert_eq!(machine.head().expect("the store answers"), Some(head));
    assert_eq!(
        machine.closed_window().expect("the store answers"),
        Some(window - 1)
    );
    assert!(
        machine
            .agreement_of(window)
            .expect("the store answers")
            .is_none(),
        "the machine pledged in window {window}"
    );
    assert!(
        machine
            .proposal_of(window)
            .expect("the store answers")
            .is_none(),
        "the machine proposed in window {window}"
    );
}

#[test]
fn a_machine_on_a_plane_of_the_network_stakes_and_proposes_nothing_before_the_next_stride_and_follows(
) {
    let at = Scratch::named("stride-network");
    let aside = Scratch::named("stride-disk");
    let (network, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[network.naming_half().expect("a half")]).expect("a cohort of itself");
    pulse::live(&network, &cohort, 0, BEFORE, PATIENCE).expect("the first windows");
    copied(&at.0, &aside.0.join("disk"));
    pulse::live(&network, &cohort, BEFORE, AWAY, PATIENCE).expect("the network goes on");

    // The end of the retention, by the holders' own rule.
    drop(network);
    mt_store::Store::open(&at.0)
        .expect("the network's store opens")
        .drop_points_before(BEFORE + 1)
        .expect("the points of the windows past the retention go");
    let (network, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the network starts again");
    pulse::live(&network, &cohort, BEFORE + AWAY, AFTER, PATIENCE)
        .expect("the network lives on past the retention");
    let open = BEFORE + AWAY + AFTER;
    let head = open - 2;
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

    // **The machine away takes the plane of the head from the network**, in the middle of a stride.
    let (back, born) = Machine::start(&Configuration::at(aside.0.join("disk"), "127.0.0.1:0"))
        .expect("the machine away starts");
    assert!(!born, "the disk kept aside drew a second secret");
    let network = reached(&back, network);
    let walked = pulse::join_under(&back, &fresh, &cohort, PATIENCE)
        .expect("the walk on a fresh anchor, with the plane of its head");
    assert_eq!(walked.later.window, head);
    assert_eq!(back.head().expect("the store answers"), Some(head));
    assert_eq!(
        back.closed_window().expect("the store answers"),
        Some(open - 1)
    );

    // It stakes first where the standing stride changes after the head it took the plane at: not one
    // window sooner, and that window is within a stride of the head.
    let stakes = next_stride_by_the_horizon(head);
    assert_eq!(
        stakes, 129,
        "the Decree moved the horizon this test is written for"
    );
    assert_eq!(pulse::stakes_from(&back), Ok(Some(stakes)));
    assert_eq!(
        standing_stride(stakes - 1),
        standing_stride(head),
        "a window before the one the machine stakes in stands in another stride"
    );

    // **It lives no window of the stride before then**: asked to live the window the network stands
    // at, it is refused before it writes anything of it — no pledge, no proposal, no close.
    assert_eq!(
        pulse::live(&back, &cohort, open, 1, PATIENCE).map(|_| ()),
        Err(refused(WAITS))
    );
    wrote_nothing_of(&back, open, head);

    // And not after a restart: the mark stands in the record of the window it closed.
    drop(back);
    let (back, born) = Machine::start(&Configuration::at(aside.0.join("disk"), "127.0.0.1:0"))
        .expect("the machine come back starts again");
    assert!(!born, "a restart drew a second secret");
    assert_eq!(pulse::stakes_from(&back), Ok(Some(stakes)));
    assert_eq!(
        pulse::live(&back, &cohort, open, 1, PATIENCE).map(|_| ()),
        Err(refused(WAITS))
    );
    wrote_nothing_of(&back, open, head);
    drop(back);

    // **It follows the decided rolls meanwhile.** The network decides two windows more; the machine
    // walks from its own anchor to the new head, replays the decided roll of every window it walked,
    // and holds the network's proposals and the plane whose roots are those of the proposal the
    // network closed on.
    pulse::live(&network, &cohort, open, FOLLOWED, PATIENCE).expect("the network decides on");
    let now = open + FOLLOWED;
    let closed_on = network
        .proposal_of(now - 1)
        .expect("the store answers")
        .expect("the network's last proposal");
    let (back, _) = Machine::start(&Configuration::at(aside.0.join("disk"), "127.0.0.1:0"))
        .expect("the machine starts to follow");
    let network = reached(&back, network);
    assert_eq!(pulse::come_back(&back, now, PATIENCE), Ok(now));
    assert_eq!(back.head().expect("the store answers"), Some(now - 2));
    for window in [now - 3, now - 2, now - 1] {
        assert_eq!(
            back.proposal_of(window)
                .expect("the store answers")
                .map(|held| id_of(&held)),
            network
                .proposal_of(window)
                .expect("the store answers")
                .map(|held| id_of(&held)),
            "the machine following kept another proposal of window {window} than the network's"
        );
    }
    assert_eq!(
        roots_of(&back.value().expect("the plane"), &cohort, now - 1),
        carried_by(&closed_on)
    );

    // Following is no staking: the close of the walk carried the mark, and the window the network
    // stands at now is refused as the one before it was.
    assert_eq!(pulse::stakes_from(&back), Ok(Some(stakes)));
    assert_eq!(
        pulse::live(&back, &cohort, now, 1, PATIENCE).map(|_| ()),
        Err(refused(WAITS))
    );
    wrote_nothing_of(&back, now, now - 2);
    drop(network);
}
