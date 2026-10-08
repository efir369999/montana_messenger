// The condition of the stage of two hosts, in the part that was never driven from a terminal: two
// machines start, reach each other by an acquaintance handed over out of band, and then **live** —
// they stand at the points of their rounds, publish beacons, answer them, gather what verifies into
// their cements, close the window on the cement and take the right it mints.
//
// **Nothing here is a model of the pulse.** What runs is the same loop the binary runs: every
// object crosses as cells at the points of its round, every attestation is verified as a far side
// verifies it, and the window closes on the cement rather than on a count kept by the test.
//
// **One machine dialled the other and that is enough.** A link a machine opened is its way of
// asking and a link it answered is its way of being asked, so the dialler writes its objects into
// the answerer and reads the answerer's back. The two converge without either being told anything
// beyond the line the operators exchanged.

use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine};

mod common;
use common::Scratch;

const WINDOW: u64 = 1_000;

// How many askings a machine spends at one round before giving it up. It is of the operator and of
// nothing else: what a machine waits for here is the far side's proof of presence, which is minutes
// of arithmetic on a machine of this size, and a machine that gave up sooner would be giving up on
// a neighbour that is working rather than on one that is silent.
const PATIENCE: u32 = 40_000;

#[test]
fn two_machines_live_a_window_from_end_to_end_and_each_takes_one_share() {
    let far_at = Scratch::named("living-answerer");
    let near_at = Scratch::named("living-dialler");

    let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
        .expect("the answering machine starts");
    let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
        .expect("the dialling machine starts");

    // The cohort of an opening window: the naming half of each machine, which each reads off its
    // own secret and hands to the other exactly as it hands an acquaintance. Neither is told the
    // root — both reach the same one from the two halves alone.
    let halves = [
        far.naming_half().expect("a half of the answerer"),
        near.naming_half().expect("a half of the dialler"),
    ];
    let cohort = Cohort::of(&halves).expect("two machines stand in the tree of the admitted");
    assert_eq!(cohort.count(), 2);
    let other = Cohort::of(&[halves[1], halves[0]]).expect("the same two in the other order");
    assert_eq!(
        other.root().bytes(),
        cohort.root().bytes(),
        "the order the halves were handed over in moved the tree"
    );

    // The answerer stands at its door; the dialler reaches it by the line and keeps the link.
    let line = far.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("a link is answered");
        far
    });
    near.reach_and_hold(&line).expect("the answerer answers");
    let far = answering.join().expect("the thread stands");
    assert_eq!(
        near.reached(),
        1,
        "the dialler did not keep the link it opened"
    );
    assert_eq!(far.holding().0, 1, "the answerer did not count the link");

    // And both live the window. Each runs its own loop, as each does on its own host.
    let living = std::thread::spawn({
        let cohort = Cohort::of(&halves).expect("the same cohort");
        move || {
            let lived = pulse::live(&far, &cohort, WINDOW, 1, PATIENCE);
            (far, lived)
        }
    });
    let mine =
        pulse::live(&near, &cohort, WINDOW, 1, PATIENCE).expect("the dialler lives the window");
    let (_far, theirs) = living.join().expect("the thread stands");
    let theirs = theirs.expect("the answerer lives the window");

    // One window, closed by both, on a cement naming both machines.
    assert_eq!(mine.len(), 1);
    assert_eq!(theirs.len(), 1);
    assert_eq!(mine[0].window, WINDOW);
    assert_eq!(theirs[0].window, WINDOW);
    assert_eq!(
        mine[0].living, 2,
        "the cement of the dialler does not name both machines"
    );
    assert_eq!(
        theirs[0].living, 2,
        "the cement of the answerer does not name both machines"
    );

    // And each takes one share of that window and no more: two machines, two rights, two
    // nullifiers, and the shares plus what does not divide are the mint of the window exactly.
    let mint = montana_node::attest::mint_of(WINDOW).expect("the Decree names the schedule");
    assert_eq!(mine[0].right.share, mint / 2);
    assert_eq!(theirs[0].right.share, mint / 2);
    assert_ne!(
        mine[0].right.nullifier, theirs[0].right.nullifier,
        "two machines took one right"
    );
    assert_eq!(
        mine[0].right.share + theirs[0].right.share + mine[0].right.carried_forward,
        mint,
        "the shares of the living and what does not divide are not the mint of the window"
    );
}
