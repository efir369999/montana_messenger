// A machine stopped and started again continues the chain it kept. Consensus, "The way back": "A
// loss of quorum halts the chain. Reconnection resumes the same open window against the same
// electorate and the same required share"; "A restart does not create authority ... no identity,
// balance, finalized height or right is silently inherited as a verified transition of the old
// network"; its invariants: "The electorate and the threshold are those of the proposal of the window
// two before, for all rounds of the window", "No silence, locally counted population, missing
// diagnostic or restart supplies authority". Consensus, "The join": "A device that lived the network
// holds its own anchor — the last two proposals it verified — and needs nobody's".
//
// **The world outside the rules, arranged by this test.** One machine and a cohort of itself — its
// heavy attestation alone is the quorum of an electorate of one, its closing pledge alone decides, and
// its ticket clears a threshold of everything — lives the first three windows of a network and is
// stopped: the whole network halts at once. It is started again on its store, refused every window but
// the one after the last it closed and refused a store a byte of which turned, and then lives two
// windows more. A device holding nothing walks from the anchor of the first two windows.
//
// **The wrong implementations it refuses**, named before the assertions: the pulse of e6c1d7bf, which
// starts every life with no proposal held, so a machine started again past the first two windows of
// a network lives nothing — and before that commit opened the cohort's electorate on the Genesis State
// Hash, a chain of its own beside the one it kept: there window three names no proposal of window two,
// carries the census of nothing where window zero's stood, and the device walking from the first two
// windows stops at the old head; a pulse that opens whatever window it is told on what it holds — there
// window two is opened again, or window four is opened on the proposals of windows one and two; and a
// pulse that stands on what it reads back unjudged — there a proposal one byte of which turned on the
// disk, or one that no longer names the proposal before it, is the name its next window pledges.

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine, NodeError};

mod common;
use common::Scratch;

// The windows lived before the stop, and after the start.
const BEFORE: u64 = 3;
const AFTER: u64 = 2;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the proofs of a machine of this size.
const PATIENCE: u32 = 40_000;

fn refused(what: &'static str) -> NodeError {
    NodeError::Refused { what }
}

fn id_of(held: &mt_state::layout::Proposal) -> [u8; 32] {
    held.id().expect("an identifier")
}

#[test]
fn a_machine_started_again_lives_the_window_after_the_last_it_closed_on_what_it_kept() {
    let at = Scratch::named("started-again");
    let joining_at = Scratch::named("started-again-joining");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let half = machine.naming_half().expect("a half");
    let cohort = Cohort::of(&[half]).expect("a cohort of itself");
    let first = pulse::live(&machine, &cohort, 0, BEFORE, PATIENCE).expect("the first windows");
    assert_eq!(first.len(), BEFORE as usize);
    assert_eq!(
        machine.closed_window().expect("the store answers"),
        Some(BEFORE - 1)
    );
    assert_eq!(machine.head().expect("the store answers"), Some(BEFORE - 2));
    // Window zero is a census window, and its cement names this machine: the census every later
    // proposal carries is not the census of nothing, so a chain that forgot it is told apart.
    let zero = machine
        .proposal_of(0)
        .expect("the store answers")
        .expect("the proposal of window zero");
    assert_eq!(zero.census[0].count, 1);
    drop(machine);

    // Started again, and told windows it may not open: the one it closed, one past the window after
    // it, and the first of the network — a second window zero of a network it already stands in
    // (Consensus, "The cold start"). Each refused before it stands at a round, with nothing of the
    // window written.
    let (machine, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts again");
    assert!(!born, "a restart drew a second secret");
    for (from, what) in [
        (
            BEFORE - 1,
            "a window other than the one after the last this machine closed",
        ),
        (
            BEFORE + 1,
            "a window other than the one after the last this machine closed",
        ),
        (0, "a network opened on a store that holds a chain"),
    ] {
        assert_eq!(
            pulse::live(&machine, &cohort, from, 1, PATIENCE).map(|_| ()),
            Err(refused(what)),
            "a machine that closed window {} lived window {from}",
            BEFORE - 1
        );
        assert!(machine
            .agreement_of(from)
            .expect("the store answers")
            .is_none());
    }

    // A store a byte of which turned: the proposal of the last window closed, one root of it changed
    // on the disk, and then the same proposal naming another predecessor and signed by nobody. The
    // machine refuses to stand on either, and writes nothing of the window it was asked to open.
    let kept = machine
        .proposal_of(BEFORE - 1)
        .expect("the store answers")
        .expect("the proposal of the last window closed");
    let mut turned = kept.clone();
    turned.note_root[0] ^= 1;
    let mut relinked = kept.clone();
    relinked.previous[0] ^= 1;
    for (corrupt, what) in [
        (turned, "a proposal under a signature that does not verify"),
        (
            relinked,
            "a kept proposal that does not stand on the one kept before it",
        ),
    ] {
        machine.keep_proposal(&corrupt).expect("the store takes it");
        assert_eq!(
            pulse::live(&machine, &cohort, BEFORE, 1, PATIENCE).map(|_| ()),
            Err(refused(what))
        );
        assert!(machine
            .agreement_of(BEFORE)
            .expect("the store answers")
            .is_none());
        assert!(machine
            .proposal_of(BEFORE)
            .expect("the store answers")
            .is_none());
        assert_eq!(machine.head().expect("the store answers"), Some(BEFORE - 2));
    }
    machine
        .keep_proposal(&kept)
        .expect("the store takes it back");

    // The honest start: the window after the last closed, on the proposals it kept.
    let after = pulse::live(&machine, &cohort, BEFORE, AFTER, PATIENCE).expect("the later windows");
    assert_eq!(
        after.iter().map(|one| one.window).collect::<Vec<_>>(),
        (BEFORE..BEFORE + AFTER).collect::<Vec<_>>()
    );
    // **One chain across the stop**: every window names the proposal of the window before it, the
    // first the Genesis State Hash; the census of window zero is carried whole into every window after
    // it; and the head stands on the newest decided window.
    let genesis = mt_state::tables::genesis_state_hash().expect("the hash of the network");
    let mut previous = genesis;
    for window in 0..BEFORE + AFTER {
        let held = machine
            .proposal_of(window)
            .expect("the store answers")
            .expect("a proposal kept for every window lived");
        assert_eq!(
            held.previous, previous,
            "window {window} links to something else than the proposal before it"
        );
        assert_eq!(
            held.census, zero.census,
            "window {window} forgot the census"
        );
        assert_eq!(held.cement_count, 1);
        previous = id_of(&held);
    }
    assert_eq!(
        after[0].proposal,
        id_of(
            &machine
                .proposal_of(BEFORE)
                .expect("the store answers")
                .expect("kept")
        )
    );
    assert_eq!(
        machine.head().expect("the store answers"),
        Some(BEFORE + AFTER - 2)
    );

    // A device holding nothing, handed the first two windows, walks across the stop to the same head.
    let (joining, _) = Machine::start(&Configuration::at(&joining_at.0, "127.0.0.1:0"))
        .expect("the joining device starts");
    let line = machine.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        machine
            .answer_one()
            .expect("the joining device is answered");
        machine
    });
    joining
        .reach_and_hold(&line)
        .expect("the machine answers the joining device");
    let machine = answering.join().expect("the thread stands");
    let anchor = Anchor {
        earlier: zero,
        later: machine
            .proposal_of(1)
            .expect("the store answers")
            .expect("the second proposal"),
    };
    let head = pulse::join(&joining, &anchor, PATIENCE).expect("the walk reaches the head");
    assert_eq!(head.later.window, BEFORE + AFTER - 2);
    assert_eq!(
        id_of(&head.later),
        id_of(
            &machine
                .proposal_of(BEFORE + AFTER - 2)
                .expect("the store answers")
                .expect("kept")
        )
    );
}
