// Protocol-13 item 2 (#10) on the live path: a count at the quorum authorizes only the attempt to
// take the canonical Proposal of the window, and the head, the last window closed, the proposals
// kept and the rights move only once a Proposal the machine verified is taken -- through the loop
// the binary runs, `pulse::live`, and not through its primitives alone
// (`a_count_at_the_quorum_moves_neither_head_nor_rights` reads those).
//
// **The world outside the rules, arranged by this test.** One machine and a cohort of itself, which
// is all a machine needs to live a chain of its own: its heavy attestation alone is the quorum of an
// electorate of one, its closing pledge alone decides. It lives windows 0, 1 and 2. In window 2 its
// cement reaches the quorum, it holds its final beacon and the agreement decides the name of window
// 1 -- everything a count gives -- and the proposal of window 2 it proves of its own is held back
// (`pulse::withhold`, a feature of the tests alone), so no proposal of window 2 it could verify
// ever stands. The draw admits every machine of the electorate, so no other world leaves a machine
// at the quorum without a proposal of its own.
//
// **The wrong implementation it refuses**, named before the assertions: a `live_doing` that closes
// on the count -- one that, holding no verified proposal, closes on a proposal it assembled from
// the decided cement and the roots it recomputed. There the window closes: the head moves onto the
// proposal of window 1, window 2 is the last closed, a proposal of window 2 is kept, and the right
// of window 1 is issued, since a right is issued for the window a close made final and for no other
// (pulse.rs, the close). Here the pulse refuses after its patience, nothing of the store moves, and
// nothing moves across a restart on the same store either.
//
// **And with what a machine that did not prove the decision stands at the points.** The same world,
// with substitutes of the held-back proposal standing at every point of window 2 while the machine
// waits. Under the identifier the decision makes, there are three: a proof of nothing, a proof of
// another runner's key, and a signature that does not verify. Under other identifiers, there are
// three more: the same decision with another cement, with another roll, and with another root. The
// wrong implementation refused here takes a proposal of the expected identifier without judging its
// signature and its proof, or takes one of another identifier; either closes the window on it.

use montana_node::attest::LivedCensus;
use montana_node::pulse::{self, withhold, Cohort};
use montana_node::round;
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::Proposal;
use mt_state::Layout;
use std::cell::RefCell;
use std::rc::Rc;

mod common;
use common::Scratch;

// The windows lived, from the first of a network, and the one whose own proposal is held back.
const WINDOWS: u64 = 3;
const HELD_BACK: u64 = 2;

// How many askings a machine spends before giving up. Proving is not counted in askings, so this
// bounds only the waiting: at a round for a beacon and the decision, and, at the close of the
// window held back, for a proposal standing at the points.
const PATIENCE: u32 = 2_000;

const NO_PROPOSAL: &str = "a window no proposal of its decision ever stood at";

// What the store of a machine says of its closes: the head, the last window closed, the identifier
// of the proposal kept for every window lived, and the census windows its standing counts.
#[derive(Debug, PartialEq, Eq)]
struct Stands {
    head: Option<u64>,
    closed: Option<u64>,
    kept: Vec<Option<[u8; 32]>>,
    census: Vec<LivedCensus>,
}

fn stands(machine: &Machine) -> Stands {
    Stands {
        head: machine.head().expect("the store answers"),
        closed: machine.closed_window().expect("the store answers"),
        kept: (0..WINDOWS)
            .map(|window| {
                machine
                    .proposal_of(window)
                    .expect("the store answers")
                    .map(|held| held.id().expect("an identifier"))
            })
            .collect(),
        census: machine.lived_census().expect("the census windows"),
    }
}

// The own proposal of window `HELD_BACK` is held back, and what the store said at that moment --
// the cement at the quorum, the final beacon held, the decision taken, and the proposal proved -- is
// written into `then`, with `forge` doing whatever else the test does there.
fn hold_back(
    then: &Rc<RefCell<Option<Stands>>>,
    mut forge: impl FnMut(&Machine, &Proposal) + 'static,
) -> withhold::Hook {
    let then = Rc::clone(then);
    Box::new(move |machine: &Machine, own: &Proposal| {
        if own.window != HELD_BACK {
            return false;
        }
        if then.borrow().is_none() {
            *then.borrow_mut() = Some(stands(machine));
            forge(machine, own);
        }
        true
    })
}

// Lives the windows with the own proposal of `HELD_BACK` held back, and answers what the pulse
// returned and what the store said when that proposal was proved.
fn live_held_back(
    machine: &Machine,
    forge: impl FnMut(&Machine, &Proposal) + 'static,
) -> (Result<(), NodeError>, Stands) {
    let cohort = Cohort::of(&[machine.naming_half().expect("a half")]).expect("a cohort of itself");
    let then = Rc::new(RefCell::new(None));
    withhold::own_proposals(Some(hold_back(&then, forge)));
    let lived = pulse::live(machine, &cohort, 0, WINDOWS, PATIENCE).map(|_| ());
    withhold::own_proposals(None);
    let then = then.borrow_mut().take().expect(
        "the machine never proved a proposal of the window held back: its count never reached the \
         quorum with a final beacon and a decision",
    );
    (lived, then)
}

// Where a machine stands with window 2 at the quorum and no proposal of it: windows 0 and 1 closed,
// the head on the proposal of window 0 that the decision of window 1 made final, and nothing of
// window 2 but the record of its agreement -- the attempt the count authorizes.
fn assert_at_the_attempt(machine: &Machine, then: &Stands, what: &str) {
    assert_eq!(then.head, Some(0));
    assert_eq!(then.closed, Some(1));
    assert!(then.kept[0].is_some() && then.kept[1].is_some());
    assert_eq!(then.kept[2], None);
    assert_eq!(
        &stands(machine),
        then,
        "{what} moved the head, the last window closed, a kept proposal or the census"
    );
    let record = machine
        .agreement_of(HELD_BACK)
        .expect("the store answers")
        .expect("the record of the agreement of the window stands");
    assert_eq!(Some(record.taken), then.kept[1]);
}

// Box 4 of #10: a count at the quorum, and no proposal stands at the points at all.
#[test]
fn a_count_at_the_quorum_with_no_proposal_standing_closes_nothing() {
    let at = Scratch::named("quorum-no-proposal");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let (lived, then) = live_held_back(&machine, |_, _| {});
    assert_eq!(lived, Err(NodeError::Refused { what: NO_PROPOSAL }));
    assert_at_the_attempt(&machine, &then, "a count at the quorum");

    // And across a restart on the same store: what stands is what stood.
    drop(machine);
    let (again, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts again");
    assert!(!born, "a restart drew a second secret");
    assert_at_the_attempt(&again, &then, "a restart after a count at the quorum");
}

// The substitutes of a proposal a machine that did not prove the decision can stand at the points,
// each named. The first three carry the identifier the decision makes, which no key, proof or
// signature enters; the last three carry another. A substitute signed anew is signed by a key of
// this test's own, under which no ticket was ever proven.
fn substitutes_of(own: &Proposal) -> Vec<(&'static str, Proposal)> {
    let expected = own.id().expect("an identifier");
    let (key, secret) = mt_suite::sign::keypair_from_seed(&[0x5A; mt_suite::sign::SEED_BYTES]);
    let signed = |mut held: Proposal| {
        held.runner_pubkey = key.as_bytes().to_vec();
        held.signature = mt_suite::sign::sign(&secret, &held.signed_scope().expect("scope"))
            .expect("the test owns its key")
            .as_bytes()
            .to_vec();
        held
    };
    let mut absent = own.clone();
    absent.ticket_proof.fill(0);
    let mut unsigned = own.clone();
    unsigned.signature[0] ^= 1;
    let mut recemented = own.clone();
    recemented.cement_count += 1;
    let mut rerolled = own.clone();
    rerolled.roll[0] ^= 1;
    let mut rerooted = own.clone();
    rerooted.note_root[0] ^= 1;
    let out = vec![
        ("a proof of nothing", signed(absent)),
        ("a proof of another runner's key", signed(own.clone())),
        ("a signature that does not verify", unsigned),
        ("another cement", signed(recemented)),
        ("another roll", signed(rerolled)),
        ("another root", signed(rerooted)),
    ];
    for (at, (what, held)) in out.iter().enumerate() {
        let id = held.id().expect("an identifier");
        assert_eq!(
            id == expected,
            at < 3,
            "{what} carries the wrong identifier"
        );
    }
    out
}

// The signatures of the proposals of the window held back standing at its points.
fn standing_at_the_window(machine: &Machine) -> Vec<Vec<u8>> {
    let width = Proposal::expected_len();
    let of_proposal = mt_wire::message::body_len(width).expect("the Decree names the cell");
    let mut out = Vec::new();
    for point in round::points_of_window(HELD_BACK).expect("the points of the window") {
        for body in machine
            .objects_at_the_point(&point, HELD_BACK)
            .expect("the point answers")
        {
            if body.len() != of_proposal {
                continue;
            }
            if let Ok(held) = Proposal::parse(&body[..width]) {
                if held.window == HELD_BACK && !out.contains(&held.signature) {
                    out.push(held.signature);
                }
            }
        }
    }
    out
}

// Box 3 of #10 on the live path: a count at the quorum, and only substitutes stand at the points.
#[test]
fn a_substituted_or_unproven_proposal_at_the_points_closes_nothing() {
    let at = Scratch::named("quorum-substitutes");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let stood: Rc<RefCell<Vec<(&'static str, Proposal)>>> = Rc::new(RefCell::new(Vec::new()));
    let (lived, then) = live_held_back(&machine, {
        let stood = Rc::clone(&stood);
        move |machine: &Machine, own: &Proposal| {
            for (what, held) in substitutes_of(own) {
                let bytes = held.bytes().expect("a proposal of its width");
                for point in round::points_of_window(HELD_BACK).expect("the points of the window") {
                    machine
                        .publish_at_the_point(&point, HELD_BACK, &bytes)
                        .expect("it stands at the point");
                }
                stood.borrow_mut().push((what, held));
            }
        }
    });
    assert_eq!(lived, Err(NodeError::Refused { what: NO_PROPOSAL }));

    // Every substitute stood at the points of the window the whole time the machine waited there,
    // and nothing else did.
    let standing = standing_at_the_window(&machine);
    let stood = stood.borrow();
    assert_eq!(stood.len(), 6);
    for (what, held) in stood.iter() {
        assert!(
            standing.contains(&held.signature),
            "{what} did not stand at the points"
        );
    }
    assert_eq!(standing.len(), stood.len());
    assert_at_the_attempt(&machine, &then, "a substitute at the points");

    drop(machine);
    let (again, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts again");
    assert!(!born, "a restart drew a second secret");
    assert_at_the_attempt(&again, &then, "a restart after substitutes at the points");
}
