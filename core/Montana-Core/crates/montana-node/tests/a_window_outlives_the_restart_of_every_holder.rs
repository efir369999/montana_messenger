// What stands at a machine's points stands across a stop. Canon, "The points a round stands at": the
// heavy attestations, the ballots and the pledges of a window, the frames of its rounds and its
// proposals with their rolls "survive at their points for `retained_windows` windows after the window
// closes — they are the certificate a device behind walks to the head". Consensus, "The join": a
// device asks the machines it reaches for what stands at the points of the windows after its anchor.
// A point that lived in memory alone went with the process, and every holder of a window restarting
// inside the retention took the window's certificate out of the network (the chairman's finding
// R-2 on #10).
//
// **What is measured.** Two machines live four windows and are both stopped and started again on
// their stores; a device that held nothing reaches one of them and walks from the anchor of the first
// two windows to the head the two machines reached before the stop, verifying the certificates off
// the points the restarted machine serves.
//
// **The wrong implementation it refuses**, named before the assertion: points kept in memory alone,
// under which the restarted machine answers every collection with nothing, the walk finds no round
// of the window after the anchor and stays at the anchor — the head of the walk is the anchor's later
// proposal, not the one the machines decided.

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine};

mod common;
use common::Scratch;

// The window the network opens at: zero, the one window the Genesis State Hash stands under
// (Consensus, "Invariants of the TimeChain").
const FROM: u64 = 0;
const WINDOWS: u64 = 4;
const PATIENCE: u32 = 40_000;

#[test]
fn a_joiner_walks_a_window_whose_every_holder_restarted() {
    let far_at = Scratch::named("restart-answerer");
    let near_at = Scratch::named("restart-dialler");
    let joining_at = Scratch::named("restart-joining");
    let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
        .expect("the answering machine starts");
    let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
        .expect("the dialling machine starts");
    let halves = [
        far.naming_half().expect("a half of the answerer"),
        near.naming_half().expect("a half of the dialler"),
    ];
    let line = far.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("a link is answered");
        far
    });
    near.reach_and_hold(&line).expect("the answerer answers");
    let far = answering.join().expect("the thread stands");

    let living = std::thread::spawn({
        let cohort = Cohort::of(&halves).expect("the cohort");
        move || {
            let lived = pulse::live(&far, &cohort, FROM, WINDOWS, PATIENCE);
            (far, lived)
        }
    });
    let cohort = Cohort::of(&halves).expect("the cohort");
    let mine = pulse::live(&near, &cohort, FROM, WINDOWS, PATIENCE)
        .expect("the dialler lives the windows");
    let (far, theirs) = living.join().expect("the thread stands");
    theirs.expect("the answerer lives the windows");
    assert_eq!(mine.len(), WINDOWS as usize);
    let decided_head = mine[(WINDOWS - 2) as usize].proposal;
    let anchor = Anchor {
        earlier: far
            .proposal_of(FROM)
            .expect("the store answers")
            .expect("the first proposal"),
        later: far
            .proposal_of(FROM + 1)
            .expect("the store answers")
            .expect("the second proposal"),
    };

    // **Every holder of the windows stops.** Nothing of the points stands in any process.
    drop(near);
    drop(far);

    // And starts again on its store. The restarted answerer is the only machine the joining device
    // reaches; what it serves at the points is what it kept.
    let (far, born) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
        .expect("the answerer starts again");
    assert!(!born);
    let (near, born) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
        .expect("the dialler starts again");
    assert!(!born);
    assert!(
        far.points_standing() > 0,
        "a restarted machine stands at no point: the points lived in memory alone"
    );
    assert_eq!(
        far.head().expect("the store answers"),
        Some(FROM + WINDOWS - 2)
    );

    let (joining, _) = Machine::start(&Configuration::at(&joining_at.0, "127.0.0.1:0"))
        .expect("the joining device starts");
    let line = far.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("the joining device is answered");
        far
    });
    joining
        .reach_and_hold(&line)
        .expect("the restarted answerer answers the joining device");
    let far = answering.join().expect("the thread stands");
    let head = pulse::join(&joining, &anchor, PATIENCE).expect("the walk reaches the head");
    assert_eq!(
        head.later.window,
        FROM + WINDOWS - 2,
        "the walk stayed at its anchor: the restarted holder served nothing of the window"
    );
    assert_eq!(head.later.id().expect("an identifier"), decided_head);
    assert_eq!(
        joining.head().expect("the store answers"),
        Some(FROM + WINDOWS - 2)
    );
    drop(far);
    drop(near);
}
