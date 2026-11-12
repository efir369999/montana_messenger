// A window applied again after a crash issues nothing more. Issue #19, step K4; Protocol-13 report
// 08: "Reapplying the same window must not issue twice." What a window issues is the note a right
// is redeemed into and the rights the close credits out of the cement of the window before (Canon,
// "The right of a machine to its coin of a window, and what redeems it"). A window already closed
// is not closed again (`Machine::close`), and a frame applied once is refused by the nullifiers the
// plane holds (`State::apply`) — and by its own proof as well, which stands against the roots of
// the plane before it.
//
// **What is measured.** A machine closes the window before over a plane whose tree of credited
// rights holds its own part of a window it lived. In the window, a frame redeeming that right
// applies, and the close credits the cement of the window before; the window is then closed. That
// close is run again and again with the process dying at its first file operation, then its
// second, and so on to the last. After every death the machine starts again on what its disk holds
// and applies the same window again — the same frame, the same credit, the same close — as a pulse
// that lost its memory does. What stands at the end, on the disk and in memory, is the plane of one
// application: one note of the redemption, the right spent once, the part credited once. Then the
// frame is applied to the plane it was proved against with its right marked spent and no root
// moved, where the nullifier is the one thing that refuses it.

use montana_node::attest;
use montana_node::pulse::Cohort;
use montana_node::state::State;
use montana_node::{Closing, Configuration, Machine, NodeError};
use mt_state::layout::{Frame, Proposal};
use mt_state::Layout;
use mt_store::fault;
use std::path::Path;

mod common;
use common::{of, payee_of, proposal_over, Scratch};

fn start(root: &Path) -> Machine {
    Machine::start(&Configuration::at(root, "127.0.0.1:0"))
        .expect("a machine starts on what its disk holds")
        .0
}

fn encoded(plane: &State) -> Vec<u8> {
    plane.encode().expect("a plane encodes")
}

fn id(proposal: &Proposal) -> [u8; 32] {
    proposal.id().expect("an identifier")
}

// `plane` with `nullifier` among its spent values and nothing else changed, so the roots a frame
// proves against — the tree of notes and the tree of credited rights — stand as they stood. It is
// written through the encoding a stopped machine reads back: the count of the notes, the notes,
// then the count of the spent values and the values, every count four bytes little-endian.
fn spent_in(plane: &State, nullifier: &[u8; 32]) -> State {
    let bytes = encoded(plane);
    let mut four = [0u8; 4];
    four.copy_from_slice(&bytes[..4]);
    let spent_at = 4 + 32 * u32::from_le_bytes(four) as usize;
    four.copy_from_slice(&bytes[spent_at..spent_at + 4]);
    let held = u32::from_le_bytes(four);
    let end = spent_at + 4 + 32 * held as usize;
    let mut out = bytes[..spent_at].to_vec();
    out.extend_from_slice(&(held + 1).to_le_bytes());
    out.extend_from_slice(&bytes[spent_at + 4..end]);
    out.extend_from_slice(nullifier);
    out.extend_from_slice(&bytes[end..]);
    State::decode(&out).expect("a plane with one value more spent reads back")
}

// One machine of a cohort of one, the right it earned in a window it lived, and the frame redeeming
// that right in the window the right is accepted in.
struct World {
    cohort: Cohort,
    // The window the right is accepted in: the window applied again.
    window: u64,
    // The part of this machine in the cement of the window before, which the close of the window
    // credits.
    part_before: [u8; 32],
    plane_before: State,
    taken_before: Proposal,
    frame: Frame,
    // The plane of one application of the window.
    once: State,
    _wallet: Scratch,
}

impl World {
    fn new() -> Self {
        let secret = of(0x77, 0);
        let lived = 1_000;
        let cohort = Cohort::of(&[Cohort::half_of(&secret)]).expect("a cohort of one stands");
        let right = attest::right_of(&secret, lived).expect("the right of a window lived");
        let window = right.accepted_in;
        let part = mt_derive::nullifier::part(&secret, lived).expect("a part");
        let mut plane_before = State::new();
        plane_before.admits(cohort.root());
        plane_before.credit(&[part]).expect("the part is credited");
        let taken_before = proposal_over(window - 1, [0x10; 32], &plane_before, &cohort, 0xA2);
        let wallet = Scratch::named("issues-nothing-wallet");
        let (siblings, position) = plane_before
            .credited_branch(&part)
            .expect("the part stands in the tree of credited rights");
        let (payee, _) = payee_of(0xA1);
        let payment = montana_wallet::Wallet::open(&wallet.0)
            .expect("a wallet opens")
            .redeem(
                &secret,
                right.window,
                u128::from(right.worth),
                &siblings,
                position,
                &payee,
                window,
                &of(0xD5, 0),
                &plane_before.notes_root(),
                &plane_before.credited(),
            )
            .expect("the right redeems at its credit");
        let frame = Frame::parse(&payment.frame).expect("a frame");
        let part_before = mt_derive::nullifier::part(&secret, window - 1).expect("a part");
        let once = Self::applied(&plane_before, &frame, window, &part_before)
            .expect("the window applies once");
        assert!(once.notes_held() > plane_before.notes_held());
        Self {
            cohort,
            window,
            part_before,
            plane_before,
            taken_before,
            frame,
            once,
            _wallet: wallet,
        }
    }

    // The window applied over `plane` as the pulse applies it: the frames of its rounds, each
    // refused one passed over (`Machine::apply_what_stands`), then the cement of the window before
    // credited by its close.
    fn applied(
        plane: &State,
        frame: &Frame,
        window: u64,
        part_before: &[u8; 32],
    ) -> Result<State, NodeError> {
        let mut plane = plane.clone();
        let _ = plane.apply(frame, window);
        plane.credit(&[*part_before])?;
        Ok(plane)
    }

    // A machine that closed the window before.
    fn before_the_window(&self, root: &Path) -> Machine {
        let machine = start(root);
        machine
            .close(Closing {
                head: None,
                taken: self.taken_before.clone(),
                plane: self.plane_before.clone(),
                before: None,
                census: None,
            })
            .expect("the window before closes");
        machine
    }

    // The window applied by `machine` over the plane it holds and closed, as the pulse does.
    fn live_the_window(&self, machine: &Machine) -> Result<(), NodeError> {
        let held = machine.value()?.clone();
        let plane = Self::applied(&held, &self.frame, self.window, &self.part_before)?;
        let previous = id(&self.taken_before);
        let taken = proposal_over(self.window, previous, &plane, &self.cohort, 0xA3);
        machine.close(Closing {
            head: Some(self.taken_before.clone()),
            taken,
            plane,
            before: Some(self.plane_before.clone()),
            census: None,
        })
    }

    // What one application leaves, on the disk and in memory: the plane of one application, its
    // notes counted, and every nullifier of the frame spent.
    fn issued_once(&self, held: &State, what: &str) {
        assert_eq!(
            held.notes_held(),
            self.once.notes_held(),
            "{what}: a window applied again issued notes again"
        );
        assert_eq!(
            held.credited(),
            self.once.credited(),
            "{what}: a window applied again credited its cement again"
        );
        assert_eq!(encoded(held), encoded(&self.once), "{what}: another plane");
        for spend in &self.frame.spends {
            for nullifier in &spend.nullifiers {
                assert!(held.is_spent(nullifier), "{what}: a right left unspent");
            }
        }
    }
}

// The wrong implementation it rejects: any one under which a window applied again after a crash
// issues again — a close writing a window it already closed, a start reading a plane other than the
// one its last record closed on, or a state accepting a frame whose nullifier it holds — since each
// leaves more notes or more credited rights than one application does.
#[test]
fn a_window_applied_again_after_a_crash_issues_nothing() {
    let world = World::new();

    // The close counted where nothing dies.
    let clean = Scratch::named("issues-nothing-clean");
    let machine = world.before_the_window(&clean.0);
    fault::fails_at(None, false);
    world.live_the_window(&machine).expect("the window closes");
    let operations = fault::counted();
    world.issued_once(&machine.value().expect("the plane"), "clean");
    assert!(operations > 0);

    let mut seen = (false, false);
    for at in 1..=operations {
        let scratch = Scratch::named(&format!("issues-nothing-dies-at-{at}"));
        let root = scratch.0.clone();
        let machine = world.before_the_window(&root);
        fault::fails_at(Some(at), true);
        let lived = world.live_the_window(&machine);
        fault::fails_at(None, false);
        assert!(lived.is_err(), "a close dying at {at} succeeded");
        drop(machine);

        // Started again on what the disk holds, the machine applies the same window again.
        let machine = start(&root);
        let closed = machine
            .closed_window()
            .expect("the number of the window closed");
        let held = machine.value().expect("the plane").clone();
        if closed == Some(world.window) {
            seen.1 = true;
            // The record of the close stands: the frame is refused, and the close by the number of
            // the window closed.
            let mut again = held.clone();
            assert!(
                again.apply(&world.frame, world.window).is_err(),
                "a frame applied once applied again (death at {at})"
            );
            assert_eq!(again.notes_held(), held.notes_held());
            assert_eq!(
                world.live_the_window(&machine),
                Err(NodeError::Refused {
                    what: "a close of a window this machine already closed"
                }),
                "a window closed once closed again (death at {at})"
            );
        } else {
            seen.0 = true;
            assert_eq!(encoded(&held), encoded(&world.plane_before));
            world
                .live_the_window(&machine)
                .expect("the window, never closed, closes");
        }
        world.issued_once(&machine.value().expect("the plane"), "in memory");
        drop(machine);
        let machine = start(&root);
        world.issued_once(&machine.value().expect("the plane"), "on the disk");
    }
    assert!(
        seen.0 && seen.1,
        "the deaths never left one of the two closes"
    );

    // **What the nullifier alone refuses.** The plane the frame was proved against, with the right
    // it redeems marked spent — the first value its first spend publishes, the right standing first
    // among what a redemption consumes — and no root moved: the proof stands, and only the
    // nullifier stands between the frame and a second note.
    let right = world.frame.spends[0].nullifiers[0];
    let spent = spent_in(&world.plane_before, &right);
    assert_eq!(spent.notes_root(), world.plane_before.notes_root());
    assert_eq!(spent.credited(), world.plane_before.credited());
    let mut again = spent.clone();
    assert_eq!(
        again.apply(&world.frame, world.window),
        Err(NodeError::Refused {
            what: "a frame repeating a spent note or rate right"
        }),
        "a right spent redeemed again"
    );
    assert_eq!(again.notes_held(), spent.notes_held());
}
