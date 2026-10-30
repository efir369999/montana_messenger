// A machine stopped lets its store go at once. Every link a machine answers is carried by a thread
// of its own, and every such thread holds the machine's store; a far side that keeps its link open
// keeps that thread reading, since silence between two messages is never bounded. The store is
// locked for the life of the handle that holds it ("one store, one process"), so a machine dropped
// while its carriers still read held the lock of its root, and a start on that store in the same
// process was refused as held by another — the red of a_window_outlives_the_restart_of_every_holder
// whenever the answerer's thread outlived the drop (F-427-1).
//
// **The wrong implementation it refuses**, named before the assertion: a machine whose drop leaves
// the threads carrying its links running, under which the dialler still holding its link keeps the
// answerer's thread reading for as long as the dialler stands, and the second start is refused with
// HeldByAnother every time, not by a race.

use montana_node::{Configuration, Machine};

mod common;
use common::Scratch;

#[test]
fn a_machine_stopped_lets_its_store_go_while_the_far_side_still_holds_the_link() {
    let far_at = Scratch::named("stop-answerer");
    let near_at = Scratch::named("stop-dialler");
    let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
        .expect("the answering machine starts");
    let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
        .expect("the dialling machine starts");
    let line = far.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("a link is answered");
        far
    });
    near.reach_and_hold(&line).expect("the answerer answers");
    let far = answering.join().expect("the thread stands");

    // The dialler stands and holds its link: the thread reading it at the answerer has no end of its
    // own. Only the machine stopping can end it.
    drop(far);
    let (far, born) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
        .expect("the answerer starts again while the dialler still holds its link");
    assert!(!born);
    drop(far);
    drop(near);
}
