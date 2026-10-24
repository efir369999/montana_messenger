// Two machines live four windows of a network they open, and a third that holds nothing walks to
// their head from an anchor its operator hands it.
//
// **What is measured.** That the running node closes every window through the one door of the
// certificate — it closes on a beacon carrying the quorum, takes the proposal under the identifier it
// recomputed and judges it whole, links the next window to that proposal, reads the electorate and the
// draw of each window off the proposal two before it, and moves its head only onto a proposal the
// next window's cement made final — and that the certificates those windows leave standing at their
// points are what a device that was not there walks from an anchor to the same head.
//
// **The wrong implementations it refuses**, named before the assertions: a machine that links a
// window to the beacon it closed on rather than to the proposal — the chain of `previous` read back
// from the store breaks; a machine whose head stands on a proposal no cement finalized — the head
// would stand at the last window lived rather than the one before it; two machines taking two
// proposals of one decision — their identifiers differ; a holder that lets the certificates of a
// window go with the window — the walk finds nothing to verify and stays at its anchor; and a walk
// trusting a forged anchor — refused at the first certificate; and a machine that closes a window
// without its closing pledge standing at the window's points — the agreement of every certificate
// the walk reads decides nothing, and the walk refuses the first.

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine};
use mt_state::Layout;

mod common;
use common::Scratch;

const FROM: u64 = 3_000;
const WINDOWS: u64 = 4;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the far side's proofs on a machine of this size.
const PATIENCE: u32 = 40_000;

#[test]
fn a_device_that_held_nothing_walks_to_the_head_two_machines_left() {
    let far_at = Scratch::named("chain-answerer");
    let near_at = Scratch::named("chain-dialler");
    let joining_at = Scratch::named("chain-joining");
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
    let theirs = theirs.expect("the answerer lives the windows");

    // Every window closed by both, on a cement naming both, under one identifier.
    assert_eq!(mine.len(), WINDOWS as usize);
    assert_eq!(theirs.len(), WINDOWS as usize);
    for (one, other) in mine.iter().zip(&theirs) {
        assert_eq!(one.window, other.window);
        assert_eq!(one.living, 2);
        assert_eq!(
            one.proposal, other.proposal,
            "two proposals of one decision at window {}",
            one.window
        );
    }

    // The chain each machine kept: the first window stands on the Genesis State Hash and every later
    // one on the proposal of the window before, by its identifier; every proposal carries the tree
    // the windows two on were electorated from, and the cement of both machines.
    let genesis = mt_state::tables::genesis_state_hash().expect("the hash of the network");
    for machine in [&near, &far] {
        let mut previous = genesis;
        for (at, lived) in mine.iter().enumerate() {
            let held = machine
                .proposal_of(FROM + at as u64)
                .expect("the store answers")
                .expect("a proposal kept for every window lived");
            assert_eq!(held.id().expect("an identifier"), lived.proposal);
            assert_eq!(
                held.previous, previous,
                "window {} links to something else than the proposal before it",
                held.window
            );
            assert_eq!(held.admitted_root, cohort.root().bytes());
            assert_eq!(held.admitted_count, 2);
            assert_eq!(held.cement_count, 2);
            previous = lived.proposal;
        }
        // The head stands on the proposal the last window's cement made final, and not on the last
        // proposal, which awaits the cement of a window nobody lived.
        assert_eq!(
            machine.head().expect("the store answers"),
            Some(FROM + WINDOWS - 2)
        );
    }

    // A device holding nothing reaches the answerer, and its operator hands it the proposals of the
    // first two windows as the anchor.
    let (joining, _) = Machine::start(&Configuration::at(&joining_at.0, "127.0.0.1:0"))
        .expect("the joining device starts");
    let line = far.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("the joining device is answered");
        far
    });
    joining
        .reach_and_hold(&line)
        .expect("the answerer answers the joining device");
    let far = answering.join().expect("the thread stands");
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
    let head = pulse::join(&joining, &anchor, PATIENCE).expect("the walk reaches the head");
    assert_eq!(head.later.window, FROM + WINDOWS - 2);
    assert_eq!(
        head.later.id().expect("an identifier"),
        mine[(WINDOWS - 2) as usize].proposal
    );
    assert_eq!(
        joining.head().expect("the store answers"),
        Some(FROM + WINDOWS - 2)
    );

    // Refused: a forged anchor, linked to itself and to nothing of the chain. Its attestations and its
    // pledges stand, since the forgery moved no root they answer to, but what they decide is the
    // chain's own proposal and not the forged one.
    let mut forged_earlier = anchor.earlier.clone();
    forged_earlier.cement_aggregate[0] ^= 1;
    let mut forged_later = anchor.later.clone();
    forged_later.previous = forged_earlier.id().expect("an identifier");
    let forged = Anchor {
        earlier: forged_earlier,
        later: forged_later,
    };
    assert_eq!(
        pulse::join(&joining, &forged, PATIENCE).map(|_| ()),
        Err(montana_node::NodeError::Refused {
            what: "a certificate whose agreement does not decide the proposal it finalizes"
        })
    );
    // Refused before any change: the head of the joining device stands where the honest walk left
    // it, and no proposal of the forged pair was kept in its place (Protocol-13 item 2).
    assert_eq!(
        joining.head().expect("the store answers"),
        Some(FROM + WINDOWS - 2)
    );
    assert_eq!(
        joining
            .proposal_of(FROM + WINDOWS - 2)
            .expect("the store answers")
            .map(|held| held.id().expect("an identifier")),
        Some(mine[(WINDOWS - 2) as usize].proposal),
        "a forged proposal took the place of the kept one"
    );
    drop(far);

    // **The verified Proposal, its identifier and the head survive a restart** (Protocol-13 item 2):
    // the dialler is started again on its store and holds every proposal it kept, byte for byte,
    // under the same head.
    let kept: Vec<Option<mt_state::layout::Proposal>> = (0..WINDOWS)
        .map(|at| near.proposal_of(FROM + at).expect("the store answers"))
        .collect();
    let head_before = near.head().expect("the store answers");
    drop(near);
    let (again, born) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
        .expect("the dialler starts again");
    assert!(!born, "a restart drew a second secret");
    assert_eq!(again.head().expect("the store answers"), head_before);
    for (at, was) in kept.iter().enumerate() {
        let now = again
            .proposal_of(FROM + at as u64)
            .expect("the store answers");
        assert_eq!(
            now.as_ref().map(|held| held.bytes().expect("bytes")),
            was.as_ref().map(|held| held.bytes().expect("bytes")),
            "a proposal kept for window {} changed across a restart",
            FROM + at as u64
        );
    }
    // And a window at or below the head is never pledged again by the restarted machine.
    assert_eq!(
        again.enter_round(FROM + WINDOWS - 1, 0, 0),
        Err(montana_node::NodeError::Refused {
            what: "a round of a window this machine already closed"
        })
    );
}
