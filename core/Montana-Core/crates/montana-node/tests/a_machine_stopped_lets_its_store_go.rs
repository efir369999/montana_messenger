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

// **A child spawned beside a machine keeps nothing of its store.** A process spawned by any thread of
// this one — an operator's `--status` beside the node, another test of the same binary — is forked
// with a copy of every descriptor this process holds, the locked root of a store among them, and
// keeps that copy until it becomes its own program. The lock of the root belongs to its open
// description, which every copy shares, so a store that only closed its handle left its root locked
// for as long as such a child stood between its fork and its program, and a start in that instant
// was refused as held by another. A refusal answers at once, so every start after it in that instant
// was refused too: the run of refused restarts of a_status_read_in_a_loop_never_stops_a_node_from_starting
// in the ring a623-p72 (issue #21).
//
// **The wrong implementation it refuses**, named before the assertion: a store whose drop closes its
// handle and leaves the lock to the last copy of it. The child here is held between its fork and its
// program until the second start was tried, so that start is refused with HeldByAnother every time,
// not by a race.
#[cfg(unix)]
#[test]
fn a_machine_stopped_lets_its_store_go_while_a_child_forked_beside_it_holds_a_copy_of_its_handle() {
    use std::io::{Read, Write};
    use std::os::unix::process::CommandExt;

    let at = Scratch::named("stop-forked");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let (mut forked, forking) = std::io::pipe().expect("a pipe");
    let (released, mut release) = std::io::pipe().expect("a pipe");
    let mut child = std::process::Command::new(env!("CARGO_BIN_EXE_montana-node"));
    child
        .args(["--status", "--data"])
        .arg(at.0.join("absent"))
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    // SAFETY: between its fork and its program the child writes one byte and reads one: two system
    // calls that allocate nothing and take no lock.
    unsafe {
        child.pre_exec(move || {
            (&forking).write_all(&[1])?;
            (&released).read_exact(&mut [0u8; 1])
        });
    }
    // A spawn returns once the child became its program, so it stands on a thread of its own.
    let spawning = std::thread::spawn(move || child.status());
    forked
        .read_exact(&mut [0u8; 1])
        .expect("the child is forked and holds a copy of every descriptor");

    drop(machine);
    let again = Machine::start(&Configuration::at(&at.0, "127.0.0.1:0"));
    release.write_all(&[1]).expect("the child is let go");
    spawning
        .join()
        .expect("the thread stands")
        .expect("the child ran");
    let (again, born) =
        again.expect("the machine starts again while the child still holds a copy of its handle");
    assert!(!born);
    drop(again);
}
