// Two frames spending one note meet at one point, and the point tells them apart without deciding
// between them.
//
// **What is measured.** The point a notice stands at follows from the nullifier, so two frames
// spending one note reach one point whatever slot carried either of them. That is the whole of the
// mechanism, and it is measured here rather than argued.
//
// **The wrong implementation this vector refuses**, named before the assertions: one deriving the
// point of a notice from the sender — from its slot, its ephemeral identity or the round its frame
// stands at. Under it the two frames below stand where nothing obliges one machine to hold both,
// and a race stays invisible until the window closes. The vector shows both sides: the points of
// two different rounds differ, and no notice of this frame stands at either.

use montana_node::pay::notices_of;
use mt_state::layout::{Frame, Notice, Spend};
use mt_state::Layout;

mod common;

const WINDOW: u64 = 1_000;

type AtItsPoint = ([u8; 32], ([u8; 16], Vec<u8>));

// A frame of the fixed shape, differing from another only where this vector needs it to.
fn frame_of(mark: u8, shared: [u8; 32]) -> Vec<u8> {
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it") as usize;
    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it") as usize;
    let outputs = mt_genesis::scalar("spend_outputs").expect("the Decree names it") as usize;
    let frame = Frame {
        spends: (0..count)
            .map(|s| Spend {
                nullifiers: (0..inputs)
                    .map(|which| {
                        if s == 0 && which == 0 {
                            shared
                        } else {
                            let mut out = [0x10 + s as u8; 32];
                            out[0] = mark;
                            out[31] = which as u8;
                            out
                        }
                    })
                    .collect(),
                commitments: vec![[0x30 + s as u8; 32]; outputs],
                rate_nullifier: [0x40 + s as u8; 32],
            })
            .collect(),
        proof: vec![mark; mt_state::PROOF_LEN],
    };
    frame.encode()
}

fn points_of(held: &[AtItsPoint], nullifier: &[u8; 32]) -> Vec<[u8; 16]> {
    held.iter()
        .filter(|(of, _)| of == nullifier)
        .map(|(_, (point, _))| *point)
        .collect()
}

fn body_of(held: &[AtItsPoint], nullifier: &[u8; 32]) -> Vec<u8> {
    held.iter()
        .find(|(of, _)| of == nullifier)
        .map(|(_, (_, body))| body.clone())
        .expect("the shared nullifier owes a notice")
}

#[test]
fn two_frames_spending_one_note_stand_at_one_point_and_name_themselves_apart() {
    let mut shared = [0u8; 32];
    shared[0] = 0xB4;
    shared[17] = 0x5C;
    shared[31] = 0xEE;
    let first = frame_of(0xA1, shared);
    let second = frame_of(0xB2, shared);
    assert_ne!(
        first, second,
        "two frames that do not differ measure nothing"
    );

    let of_the_first = notices_of(&first, WINDOW).expect("a frame yields its notices");
    let of_the_second = notices_of(&second, WINDOW).expect("a frame yields its notices");

    // The count is a constant of the shape and not of what was paid: every frame owes one notice
    // per nullifier per replica, whatever it means to pay.
    let count = mt_genesis::scalar("spends_per_frame").expect("named") as usize;
    let inputs = mt_genesis::scalar("spend_inputs").expect("named") as usize;
    let replicas = mt_genesis::scalar("consensus_replicas").expect("named") as usize;
    assert_eq!(of_the_first.len(), count * inputs * replicas);
    assert_eq!(of_the_second.len(), of_the_first.len());

    // The points of the shared nullifier are the same for both frames, to the byte.
    let first_points = points_of(&of_the_first, &shared);
    let second_points = points_of(&of_the_second, &shared);
    assert_eq!(
        first_points.len(),
        replicas,
        "a nullifier owes one notice per replica"
    );
    assert_eq!(
        first_points, second_points,
        "two frames spending one note did not meet at one point"
    );

    // And the points of a nullifier are not one point repeated: the index enters the derivation.
    let mut distinct = first_points.clone();
    distinct.sort_unstable();
    distinct.dedup();
    assert_eq!(
        distinct.len(),
        replicas,
        "the replicas of a point collapsed into one"
    );

    // What stands there tells the two frames apart by their names — the identifier every object of
    // this set is named by — and by nothing an author draws afterwards.
    let one = Notice::parse(&body_of(&of_the_first, &shared)).expect("a notice reads back");
    let other = Notice::parse(&body_of(&of_the_second, &shared)).expect("a notice reads back");
    assert_eq!(one.nullifier, shared);
    assert_eq!(other.nullifier, shared);
    assert_ne!(
        one.frame, other.frame,
        "two frames of one nullifier named themselves the same, so the point cannot tell them apart"
    );
    assert_eq!(
        one.frame,
        Frame::parse(&first)
            .expect("a frame reads back")
            .id()
            .expect("a frame is named"),
        "a notice named its frame by something other than the frame's own identifier"
    );

    // The named wrong implementation, refuted by measurement: had the point followed the sender
    // rather than the note, a notice would stand at a point of a round, and the rounds of two
    // senders differ in every byte.
    let of_one_round = montana_node::round::points_of_round(WINDOW, 0, 3).expect("named");
    let of_another = montana_node::round::points_of_round(WINDOW, 1, 9).expect("named");
    assert_ne!(
        of_one_round[0], of_another[0],
        "two slots that do not differ cannot show what deriving a point from the sender costs"
    );
    assert!(
        !first_points.contains(&of_one_round[0]) && !first_points.contains(&of_another[0]),
        "a notice stood at a point of a round, which is the derivation this vector refuses"
    );
}
