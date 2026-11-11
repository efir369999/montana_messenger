// A window closes whole or not at all. Issue #19: the tables, the proposal, the state and the
// record of a window survive a crash together; after a restart a machine stands on exactly the last
// close or refuses. Consensus, "The agreement": "The decision makes the proposal of the window before
// final, and it is the event the pulse names as the close of the window"; a machine whose name was
// not decided "replays the roll over the decided state of the window two before, and holds what
// results as the decided state of the window before"; "What a machine holds of the agreement": it
// lets the record go "when the window they govern closes, so what it keeps is one record per open
// window and never a history". Canon, "The roots of state": every verifier recomputes the roots
// "from the state it holds once the frames of the window have applied".
//
// **What is measured.** Two machines close one window over one close before it: one whose own name
// for the window before was decided, and one that took another name and closes over the decided
// state it replayed. The close is run again and again with the process dying at its first file
// operation, then its second, and so on to the last, and the machine is started again on the same
// directory after every death. What stands is byte for byte the record of the close before or the
// record of this close: the plane the machine starts on, its standing, the record of the agreement
// and the proposals all of one of the two, and the roots of the plane it closed on are the roots of
// the proposal it took for that window. Then the same with a refusal the process lives through, and
// a second close of a window already closed.
//
// **The wrong implementations it refuses**, named before the assertions: the close of five to eight
// writings, under which a death between two of them starts a machine on a head of one close and a
// plane or a number of the other; a record of the close that names the proposal of its window only
// through the archive of proposals, which the close of a machine that took another name rewrites
// before its record stands, so a death between the two leaves a plane beside a proposal whose roots
// are not its own; a machine changing its memory before the record stands, under which a refused
// writing leaves the machine living on a close its disk does not hold; and a close of a window
// already closed that writes anything at all.

use montana_node::attempt::Record;
use montana_node::attest::LivedCensus;
use montana_node::pulse::Cohort;
use montana_node::state::State;
use montana_node::{Closing, Configuration, Kept, Machine, NodeError};
use mt_state::layout::Proposal;
use mt_state::Layout;
use mt_store::fault;
use std::path::Path;

mod common;
use common::{proposal_over, Scratch};

const WINDOW: u64 = 3_300;

// A commitment of the family the tree of notes takes, one for each mark.
fn commitment(mark: u8) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[0] = mark;
    out[31] = (mark ^ 0x33) & 0x7F;
    out
}

fn over(base: &State, marks: &[u8]) -> State {
    let mut plane = base.clone();
    for mark in marks {
        plane
            .witness(&commitment(*mark))
            .expect("the tree takes it");
    }
    plane
}

// Whether the roots a plane gives for the window of a proposal are the roots the proposal carries.
fn roots_agree(plane: &State, proposal: &Proposal, cohort: &Cohort) -> bool {
    let roots = plane
        .roots(cohort, proposal.window, &[])
        .expect("the roots of a plane");
    roots.note_root == proposal.note_root
        && roots.nullifier_root == proposal.nullifier_root
        && roots.record_root == proposal.record_root
        && roots.admitted_root == proposal.admitted_root
        && roots.operations_root == proposal.operations_root
        && roots.roll == proposal.roll
}

fn id(proposal: &Proposal) -> [u8; 32] {
    proposal.id().expect("an identifier")
}

fn bytes(proposal: &Proposal) -> Vec<u8> {
    proposal.bytes().expect("the bytes of a proposal")
}

fn encoded(plane: &State) -> Vec<u8> {
    plane.encode().expect("a plane encodes")
}

fn read(at: &Path) -> Option<Vec<u8>> {
    std::fs::read(at).ok()
}

fn proposal_at(root: &Path, window: u64) -> Option<Vec<u8>> {
    read(&root.join("proposals").join(format!("{window:020}")))
}

fn agreement_at(root: &Path, window: u64) -> Option<Vec<u8>> {
    read(&root.join(format!("agreement-{window:020}")))
}

// The world both closes stand in: one cohort, the close of the window before as this machine
// made it, and the close of the window as each of the two machines makes it.
struct World {
    cohort: Cohort,
    two_before: Proposal,
    decided_two_before: State,
    taken_before: Proposal,
    plane_before: State,
    census: LivedCensus,
}

impl World {
    fn new() -> Self {
        let secret = [0x5Du8; 32];
        let cohort = Cohort::of(&[Cohort::half_of(&secret)]).expect("a cohort of one stands");
        let mut genesis = State::new();
        genesis.admits(cohort.root());
        let decided_two_before = over(&genesis, &[0x01, 0x02]);
        let two_before = proposal_over(WINDOW - 2, [0x10; 32], &decided_two_before, &cohort, 0xA1);
        let plane_before = over(&decided_two_before, &[0x03]);
        let taken_before = proposal_over(WINDOW - 1, id(&two_before), &plane_before, &cohort, 0xA2);
        let sibling = mt_proof::cement::empty_root();
        let census = LivedCensus {
            window: WINDOW,
            root: [0x4C; 32],
            siblings: vec![sibling; mt_proof::tree_depth()],
            position: 0,
        };
        Self {
            cohort,
            two_before,
            decided_two_before,
            taken_before,
            plane_before,
            census,
        }
    }

    // A machine that closed the window before and opened the record of the agreement of this one.
    fn before_the_close(&self, at: &Path) -> Machine {
        let (machine, _) =
            Machine::start(&Configuration::at(at, "127.0.0.1:0")).expect("the machine starts");
        machine
            .close(Closing {
                head: Some(self.two_before.clone()),
                taken: self.taken_before.clone(),
                plane: self.plane_before.clone(),
                before: Some(self.decided_two_before.clone()),
                census: None,
            })
            .expect("the window before closes");
        machine
            .open_agreement(&Record {
                window: WINDOW,
                taken: id(&self.taken_before),
                attempt: 0,
                lock: None,
                valid: None,
                made: Vec::new(),
            })
            .expect("the record of the agreement opens");
        machine
    }

    // The close of the window by a machine whose own name was decided: the head moves onto the
    // proposal it took, and its plane stands over the plane it closed the window before on.
    fn own_name(&self) -> Closing {
        let plane = over(&self.plane_before, &[0x05]);
        Closing {
            head: Some(self.taken_before.clone()),
            taken: proposal_over(WINDOW, id(&self.taken_before), &plane, &self.cohort, 0xA3),
            plane,
            before: Some(self.plane_before.clone()),
            census: Some(self.census.clone()),
        }
    }

    // The close by a machine that took another name: the decided proposal of the window before is
    // another runner's over other frames, the machine replayed its roll, and its plane stands over
    // the decided state that resulted.
    fn another_name(&self) -> Closing {
        let decided_before = over(&self.decided_two_before, &[0x04]);
        let decided = proposal_over(
            WINDOW - 1,
            id(&self.two_before),
            &decided_before,
            &self.cohort,
            0xB2,
        );
        assert!(
            !roots_agree(&self.plane_before, &decided, &self.cohort),
            "the decided proposal must carry other roots than the one taken"
        );
        let plane = over(&decided_before, &[0x05]);
        Closing {
            head: Some(decided.clone()),
            taken: proposal_over(WINDOW, id(&decided), &plane, &self.cohort, 0xA3),
            plane,
            before: Some(decided_before),
            census: Some(self.census.clone()),
        }
    }
}

// The bytes of the record of a window, read off the disk as a reader of the directory reads them.
fn record_at(root: &Path) -> Vec<u8> {
    read(&root.join("window")).expect("a record of a window stands")
}

// What the machine started on a directory holds: its plane and its standing.
fn started_on(root: &Path) -> (Vec<u8>, Vec<LivedCensus>) {
    let (machine, _) = Machine::start(&Configuration::at(root, "127.0.0.1:0"))
        .expect("a machine starts again on what it left");
    let plane = encoded(&machine.value().expect("the plane"));
    let census = machine.lived_census().expect("its standing");
    (plane, census)
}

// What the record standing keeps of its close, read through the store once no machine holds it.
fn kept_at(root: &Path) -> Kept {
    let store = mt_store::Store::open(root).expect("the store opens");
    let record = store.window().expect("a record reads");
    Kept::decode(&record.kept).expect("what a close keeps reads back")
}

#[test]
fn a_window_closes_whole_or_not_at_all_wherever_the_process_dies() {
    let world = World::new();
    for (case, closing) in [("own", world.own_name()), ("another", world.another_name())] {
        // The close counted where nothing dies, and the record it leaves.
        let clean = Scratch::named(&format!("close-{case}-clean"));
        let machine = world.before_the_close(&clean.0);
        let old = record_at(&clean.0);
        fault::fails_at(None, false);
        machine.close(closing.clone()).expect("the window closes");
        let operations = fault::counted();
        drop(machine);
        let new = record_at(&clean.0);
        assert_ne!(old, new);
        assert!(operations > 0);

        let mut seen = (false, false);
        for at in 1..=operations {
            let scratch = Scratch::named(&format!("close-{case}-dies-at-{at}"));
            let root = scratch.0.clone();
            let machine = world.before_the_close(&root);
            assert_eq!(record_at(&root), old);
            fault::fails_at(Some(at), true);
            let closed = machine.close(closing.clone());
            fault::fails_at(None, false);
            assert!(closed.is_err(), "{case}: a close dying at {at} succeeded");
            drop(machine);

            let (plane, census) = started_on(&root);
            let record = record_at(&root);
            let kept = kept_at(&root);
            // The roots of the plane a record holds are the roots of the proposal that record took
            // its window under, whichever record stands.
            assert!(
                roots_agree(&kept.plane, &kept.taken, &world.cohort),
                "{case}: a plane beside a proposal whose roots are not its own (death at {at})"
            );
            assert_eq!(
                plane,
                encoded(&kept.plane),
                "{case}: started on another plane"
            );
            if record == new {
                seen.1 = true;
                assert_eq!(kept.taken, closing.taken);
                assert_eq!(plane, encoded(&closing.plane));
                assert_eq!(census, vec![world.census.clone()]);
                assert_eq!(
                    agreement_at(&root, WINDOW),
                    None,
                    "{case}: a history (death at {at})"
                );
                assert_eq!(proposal_at(&root, WINDOW), Some(bytes(&closing.taken)));
                let head = closing.head.as_ref().expect("a head");
                assert_eq!(proposal_at(&root, WINDOW - 1), Some(bytes(head)));
                // The roots of the plane closed on are the roots of the proposal standing for the
                // window closed.
                assert!(roots_agree(&kept.plane, &closing.taken, &world.cohort));
            } else {
                seen.0 = true;
                assert_eq!(record, old, "{case}: a third record stands (death at {at})");
                assert_eq!(kept.taken, world.taken_before);
                assert_eq!(plane, encoded(&world.plane_before));
                assert!(
                    census.is_empty(),
                    "{case}: the standing of a close that never stood"
                );
                assert!(agreement_at(&root, WINDOW).is_some());
                // Where the archive already holds the decided proposal of the window before, the
                // record still holds the one its plane was taken under, and the archive's roots are
                // not that plane's: the record carries what authenticates its own plane.
                let archived = proposal_at(&root, WINDOW - 1).expect("the proposal of the window");
                if archived != bytes(&world.taken_before) {
                    assert_eq!(case, "another");
                    let archived = Proposal::parse(&archived).expect("a proposal");
                    assert!(!roots_agree(&kept.plane, &archived, &world.cohort));
                }
            }
            let left: Vec<String> = std::fs::read_dir(&root)
                .expect("the root reads")
                .chain(std::fs::read_dir(root.join("proposals")).expect("the proposals read"))
                .map(|entry| {
                    entry
                        .expect("an entry")
                        .file_name()
                        .to_string_lossy()
                        .to_string()
                })
                .filter(|name| name.contains(".writing-"))
                .collect();
            assert!(
                left.is_empty(),
                "{case}: temporaries left (death at {at}): {left:?}"
            );
        }
        assert!(
            seen.0 && seen.1,
            "{case}: the deaths never left one of the two closes"
        );

        // **A refusal the process lives through.** The same operations each refused once, the
        // machine running on: what it holds in memory is the close its disk holds.
        for at in 1..=operations {
            let scratch = Scratch::named(&format!("close-{case}-refused-at-{at}"));
            let root = scratch.0.clone();
            let machine = world.before_the_close(&root);
            fault::fails_at(Some(at), false);
            let closed = machine.close(closing.clone());
            fault::fails_at(None, false);
            assert!(closed.is_err(), "{case}: a close refused at {at} succeeded");
            let plane = encoded(&machine.value().expect("the plane"));
            let census = machine.lived_census().expect("its standing");
            let record = record_at(&root);
            if record == new {
                assert_eq!(
                    plane,
                    encoded(&closing.plane),
                    "{case}: memory behind its disk"
                );
                assert_eq!(census, vec![world.census.clone()]);
            } else {
                assert_eq!(record, old);
                assert_eq!(
                    plane,
                    encoded(&world.plane_before),
                    "{case}: memory moved on a close its disk does not hold (refused at {at})"
                );
                assert!(census.is_empty());
            }
        }
    }
}

// **A window closed once is not closed again.** The close of the window before, run a second time
// over the record that holds it, is refused before anything is written: no file operation is done,
// and the record, the plane and the standing are the ones that stood. The wrong implementation
// refused: a close that writes the record again — a second application of a window, which the
// number of the last window closed exists to refuse.
#[test]
fn a_window_already_closed_is_not_closed_again() {
    let world = World::new();
    let scratch = Scratch::named("closed-again");
    let machine = world.before_the_close(&scratch.0);
    let old = record_at(&scratch.0);
    let plane = encoded(&machine.value().expect("the plane"));
    fault::fails_at(None, false);
    assert_eq!(
        machine.close(Closing {
            head: Some(world.two_before.clone()),
            taken: world.taken_before.clone(),
            plane: over(&world.plane_before, &[0x06]),
            before: Some(world.decided_two_before.clone()),
            census: Some(world.census.clone()),
        }),
        Err(NodeError::Refused {
            what: "a close of a window this machine already closed"
        })
    );
    assert_eq!(fault::counted(), 0, "a refused close touched the disk");
    assert_eq!(record_at(&scratch.0), old);
    assert_eq!(encoded(&machine.value().expect("the plane")), plane);
    assert!(machine.lived_census().expect("its standing").is_empty());
}
