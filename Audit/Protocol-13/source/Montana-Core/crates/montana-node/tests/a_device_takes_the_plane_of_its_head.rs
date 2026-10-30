// Two machines live five windows of a network they open, a third that holds nothing walks to their
// head from an anchor past the first window its operator hands it, and then takes the tables of the
// value plane of that head from one of them.
//
// **What is measured.** Consensus, "The join", step 5: the device "takes the state it needs against
// the roots of the head ... and it recomputes every root it takes rather than accepting one"; and
// its invariant, "Every leaf of state a joining device takes is checked against a root the verified
// head carries, by recomputation; a leaf accepted on the word of whoever answered is a defect". The
// roots are the seven and the count Canon names in "The roots of state", recomputed by the one fold
// of each table the pulse proposes with, and compared with the proposal the walk kept as the head.
//
// **The wrong implementations it refuses**, named before the assertions, each by the step it fails
// at: a device that judges the tables against the proposal before the head — the honest tables of the
// head are refused (V1); a device that takes the tables it is offered without recomputing them — a
// server's plane of its own making, whose roots are its own and not the head's, is taken (V2); a
// device that recomputes every root but the root of the tree of credited rights — one leaf of that
// tree altered under the honest roots is taken (V3); and a device that judges the honest tables and
// does not hold them, or holds them only for the life of its process — its roots are not the chain's
// after the take, or not after a restart (V4).

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort};
use montana_node::state::State;
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::Proposal;

mod common;
use common::Scratch;

// The window the network opens at, the windows it lives and the patience of a round. One window
// more than the test of the walk beside this one lives, so the anchor stands past the first window
// and the head is still followed by a window closed.
const FROM: u64 = 0;
const WINDOWS: u64 = 5;
const PATIENCE: u32 = 40_000;

fn refused(what: &'static str) -> Result<(), NodeError> {
    Err(NodeError::Refused { what })
}

// The seven roots and the count a plane gives for `window` against `cohort`, in the order a
// proposal carries them.
fn roots_of(plane: &State, cohort: &Cohort, window: u64) -> ([[u8; 32]; 7], u64) {
    let roots = plane
        .roots(cohort, window, &[])
        .expect("the roots of a plane");
    (
        [
            roots.note_root,
            roots.nullifier_root,
            roots.record_root,
            roots.machine_root,
            roots.admitted_root,
            roots.credited_root,
            roots.operations_root,
        ],
        roots.admitted_count,
    )
}

fn carried_by(proposal: &Proposal) -> ([[u8; 32]; 7], u64) {
    (
        [
            proposal.note_root,
            proposal.nullifier_root,
            proposal.record_root,
            proposal.machine_root,
            proposal.admitted_root,
            proposal.credited_root,
            proposal.operations_root,
        ],
        proposal.admitted_count,
    )
}

#[test]
fn a_device_that_walked_to_the_head_takes_its_tables_against_its_roots() {
    let far_at = Scratch::named("plane-answerer");
    let near_at = Scratch::named("plane-dialler");
    let joining_at = Scratch::named("plane-joining");
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
    pulse::live(&near, &cohort, FROM, WINDOWS, PATIENCE).expect("the dialler lives the windows");
    let (far, theirs) = living.join().expect("the thread stands");
    theirs.expect("the answerer lives the windows");

    // The device walks to the head, as the test of the walk measures it, from an anchor past the
    // first window. **An anchor naming the first window would hand it a state:** a device that
    // holds no chain and walked from the first window replays from the plane before any window
    // (pulse.rs, state_of_the_walk; bfc164f) and holds the chain's plane without taking one.
    // Anchored past it, it holds no state to replay from and was handed no cohort, so the walk
    // keeps the proposals alone.
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
            .proposal_of(FROM + 1)
            .expect("the store answers")
            .expect("the second proposal"),
        later: far
            .proposal_of(FROM + 2)
            .expect("the store answers")
            .expect("the third proposal"),
    };
    let head = pulse::join(&joining, &anchor, PATIENCE).expect("the walk reaches the head");
    let at = FROM + WINDOWS - 2;
    assert_eq!(head.later.window, at);

    // Walked and holding no plane: the roots of the device are not the chain's (b4802f0). Its plane
    // stands against no tree of admitted machines, and its tree of credited rights is empty.
    let chain = carried_by(&head.later);
    let held_nothing = |machine: &Machine| {
        let plane = machine.value().expect("the plane");
        plane.admitted() != cohort.root() && plane.credited().bytes() != head.later.credited_root
    };
    assert!(held_nothing(&joining));

    // What the answerer holds of the plane: the decided state of the head, and its plane of the last
    // window it closed, whose proposal awaits a certificate nobody lived.
    let honest = far
        .plane_of(at)
        .expect("the store answers")
        .expect("the plane of the head");
    assert_eq!(roots_of(&honest, &cohort, at), chain);
    let offered = honest.encode().expect("the plane encodes");

    // **V2. A server's plane of its own making is refused**, though its roots are its own: one note
    // more than the chain holds, so the plane answers for roots no certificate made final.
    let mut own = honest.clone();
    own.witness(&cohort.root().bytes())
        .expect("a note of the server's own");
    assert_ne!(roots_of(&own, &cohort, at), chain);
    assert_eq!(
        pulse::take_the_plane(&joining, &cohort, &own.encode().expect("the plane encodes")),
        refused("a tree of notes whose root is not the head's")
    );
    // **V3. One leaf altered under the honest roots is refused at its table.** The tree of credited
    // rights is the last table of the encoding (state.rs, State::encode), and the head holds the
    // parts of the cements credited up to it; its last leaf is replaced by another digest of the
    // family.
    let mut altered = offered.clone();
    let end = altered.len();
    assert_ne!(
        &altered[end - 32..],
        &cohort.root().bytes()[..],
        "the leaf stands altered"
    );
    altered[end - 32..].copy_from_slice(&cohort.root().bytes());
    assert_eq!(
        State::decode(&altered)
            .map(|plane| roots_of(&plane, &cohort, at).0[5] != chain.0[5])
            .ok(),
        Some(true),
        "the altered plane reads whole and its tree of credited rights moved"
    );
    assert_eq!(
        pulse::take_the_plane(&joining, &cohort, &altered),
        refused("a tree of credited rights whose root is not the head's")
    );

    // **V2, again.** The plane of the window after the head is refused, whose roots its own proposal
    // carries but no certificate made final: "a proposal awaiting its certificate is not final, and
    // nothing is taken against its roots" (Consensus, "The join", step 4).
    let after = far
        .plane_of(at + 1)
        .expect("the store answers")
        .expect("the plane of the last window closed");
    assert_eq!(
        roots_of(&after, &cohort, at + 1),
        carried_by(
            &far.proposal_of(at + 1)
                .expect("the store answers")
                .expect("the proposal of the last window closed")
        )
    );
    assert_eq!(
        pulse::take_the_plane(
            &joining,
            &cohort,
            &after.encode().expect("the plane encodes")
        ),
        refused("a tree of credited rights whose root is not the head's")
    );

    // Three refusals left the device as it was.
    assert!(held_nothing(&joining));

    // **V1. The honest tables of the head are taken**, every root recomputed against the head the
    // walk kept.
    assert_eq!(pulse::take_the_plane(&joining, &cohort, &offered), Ok(()));

    // **V4. The device that took them ends with the chain's roots**, and holds them after a restart.
    assert_eq!(
        roots_of(&joining.value().expect("the plane"), &cohort, at),
        chain
    );
    assert_eq!(
        roots_of(&joining.value().expect("the plane"), &cohort, at),
        roots_of(&honest, &cohort, at)
    );
    assert_eq!(joining.head().expect("the store answers"), Some(at));
    drop(joining);
    let (again, born) = Machine::start(&Configuration::at(&joining_at.0, "127.0.0.1:0"))
        .expect("the joined device starts again");
    assert!(!born, "a restart drew a second secret");
    assert_eq!(
        roots_of(&again.value().expect("the plane"), &cohort, at),
        chain
    );
    assert_eq!(again.head().expect("the store answers"), Some(at));
    drop(far);
}

// The bytes of a plane holding nothing but the tree of admitted machines `admitted` and the two
// lists of the one set of nullifiers, in the order State::encode writes a plane (state.rs): counts
// four bytes little-endian, values thirty-two, the opening window and count and the window of the
// operations eight. The empty case is held equal to State::encode below, so the layout is the
// tree's and not this test's.
fn a_plane_of_nullifiers(
    admitted: &[u8; 32],
    spent: &[[u8; 32]],
    nullifiers: &[[u8; 32]],
) -> Vec<u8> {
    let count = |out: &mut Vec<u8>, n: usize| out.extend_from_slice(&(n as u32).to_le_bytes());
    let mut out = Vec::new();
    count(&mut out, 0);
    count(&mut out, spent.len());
    for value in spent {
        out.extend_from_slice(value);
    }
    out.extend_from_slice(admitted);
    count(&mut out, 0);
    count(&mut out, nullifiers.len());
    for value in nullifiers {
        out.extend_from_slice(value);
    }
    out.extend_from_slice(&0u64.to_le_bytes());
    out.extend_from_slice(&0u64.to_le_bytes());
    count(&mut out, 0);
    out.extend_from_slice(&0u64.to_le_bytes());
    count(&mut out, 0);
    count(&mut out, 0);
    out
}

// **V5. The set of nullifiers is one** (Canon, "The roots of state", "What enters the two sets":
// the nullifiers of notes, rights, openings and candidacies, "which no reader tells apart"). The
// plane keeps it as two lists, `spent` and `nullifiers`, and one root folds them (state.rs, roots),
// so a server can offer the nullifier of a spent note in the other list under the head's own root.
// The device takes that plane, and the note stays spent on it: State::is_spent answers true, which
// is what refuses a frame redeeming it ("a frame repeating a spent note or rate right", state.rs,
// State::apply). And one nullifier standing in both lists: State::decode refuses a repeat inside one
// list only, and the fold inserts it twice into one sparse tree, where the second insertion replaces
// the first (mt-merkle, SparseTree::insert, a BTreeMap) -- so the root is the root of the set holding
// it once, the plane is taken, and both checks answer true.
//
// **The wrong implementation it refuses**, named before the assertions: an `is_spent` that reads the
// list of spent notes and the rate set alone -- the moved nullifier would redeem its note again on
// the device.
#[test]
fn a_nullifier_moved_between_the_lists_of_the_one_set_stays_spent() {
    let at = Scratch::named("plane-one-set");
    let (device, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the device starts");
    let cohort =
        Cohort::of(&[device.naming_half().expect("a half of the device")]).expect("a cohort");
    let admitted = cohort.root().bytes();
    assert_eq!(
        a_plane_of_nullifiers(&admitted, &[], &[]),
        State::new()
            .with_admitted(cohort.root())
            .encode()
            .expect("the plane encodes"),
        "the layout of a plane is State::encode's"
    );

    // The head: a proposal of window zero over a plane whose list of spent notes holds `spent`.
    let spent = [0x5Au8; 32];
    let honest = State::decode(&a_plane_of_nullifiers(&admitted, &[spent], &[]))
        .expect("the honest plane reads");
    assert!(honest.is_spent(&spent));
    let head = common::proposal_over(
        0,
        mt_state::tables::genesis_state_hash().expect("the hash of the network"),
        &honest,
        &cohort,
        1,
    );
    device.keep_proposal(&head).expect("the head is kept");
    device.finalize(0).expect("the head moves onto it");

    // Moved from the list of spent notes to the other list: taken, since the root is the head's, and
    // the note is still spent on the device.
    let moved = a_plane_of_nullifiers(&admitted, &[], &[spent]);
    assert_eq!(pulse::take_the_plane(&device, &cohort, &moved), Ok(()));
    assert!(
        device.value().expect("the plane").is_spent(&spent),
        "a nullifier moved to the other list of the one set redeems its note again"
    );
    assert!(device.value().expect("the plane").is_spent_right(&spent));

    // Standing in both lists: taken under the same root, and spent by both checks.
    let both = a_plane_of_nullifiers(&admitted, &[spent], &[spent]);
    assert_eq!(pulse::take_the_plane(&device, &cohort, &both), Ok(()));
    assert!(device.value().expect("the plane").is_spent(&spent));
    assert!(device.value().expect("the plane").is_spent_right(&spent));
}
