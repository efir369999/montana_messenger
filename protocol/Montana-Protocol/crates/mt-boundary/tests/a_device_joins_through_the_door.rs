// Two machines live four windows of a network they open, and a telephone that holds nothing walks
// to their head through the door of the join, handed the anchor its operator read off one of them.
//
// **What is under test is the door, not the walk.** The walk is judged in `montana-node`; here a
// client stands on the boundary the way a telephone does, opens its device, reaches a machine of the
// chain and hands the bytes of two proposals across, and the head it reads back is the one the
// living machines hold.
//
// **The wrong implementations it refuses**, named before the assertions: a door that writes the
// window of the anchor it was handed rather than of the head the walk reached — it would answer the
// second window lived, not the third; a door that takes the anchor on the operator's word and walks
// nothing — the forged anchor would stand as a head; a door that reads the two proposals in the
// other order than the header states — the honest anchor would be refused; a door that moves the
// head of the device before the walk refused — the device would hold a head after a refusal; and a
// door that reads a proposal at a length other than the one handed beside it — the short buffer
// would be read past its end rather than refused.

use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine};
use mt_state::Layout;
use std::ffi::{c_char, CString};

// The window the network opens at: zero, the one window the Genesis State Hash stands under
// (Consensus, "Invariants of the TimeChain").
const FROM: u64 = 0;
const WINDOWS: u64 = 4;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the far side's proofs on a machine of this size.
const PATIENCE: u32 = 40_000;

fn last_said() -> String {
    let mut out = [0 as c_char; 512];
    let mut len = 0usize;
    let answer = mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len);
    assert_eq!(answer, 0, "the word this boundary keeps is readable");
    let bytes: Vec<u8> = out[..len].iter().map(|c| *c as u8).collect();
    String::from_utf8(bytes).expect("text of the boundary")
}

fn scratch(what: &str) -> std::path::PathBuf {
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("a test timestamp")
        .as_nanos();
    let at = std::env::temp_dir().join(format!(
        "mt-join-door-{what}-{}-{unique}",
        std::process::id()
    ));
    std::fs::create_dir(&at).expect("a fresh retained test directory");
    at
}

fn head_of_the_device() -> Option<u64> {
    let mut window = 0u64;
    let mut present = -1i32;
    assert_eq!(
        mt_boundary::mtc_machine_head(&mut window, &mut present),
        0,
        "the head is readable: {}",
        last_said()
    );
    (present == 1).then_some(window)
}

fn join(earlier: &[u8], later: &[u8], window: &mut u64) -> i32 {
    mt_boundary::mtc_machine_join(
        earlier.as_ptr(),
        earlier.len(),
        later.as_ptr(),
        later.len(),
        window,
    )
}

#[test]
fn a_telephone_that_held_nothing_walks_to_the_head_through_the_door() {
    let far_at = scratch("answerer");
    let near_at = scratch("dialler");
    let (far, _) = Machine::start(&Configuration::at(&far_at, "127.0.0.1:0"))
        .expect("the answering machine starts");
    let (near, _) = Machine::start(&Configuration::at(&near_at, "127.0.0.1:0"))
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
    assert_eq!(mine.len(), WINDOWS as usize);
    let (far, theirs) = living.join().expect("the thread stands");
    theirs.expect("the answerer lives the windows");
    assert_eq!(
        near.head().expect("the store answers"),
        Some(FROM + WINDOWS - 2)
    );

    // The telephone opens and reaches the answerer, which is all it knows of the network.
    let dir = scratch("telephone");
    let dir = CString::new(dir.to_str().expect("a path of text")).expect("a path without a nul");
    let listen = CString::new("127.0.0.1:0").expect("an address without a nul");
    let mut born = -1i32;
    assert_eq!(
        mt_boundary::mtc_device_open(dir.as_ptr(), listen.as_ptr(), &mut born),
        0,
        "the device opens: {}",
        last_said()
    );
    let line = CString::new(far.acquaintance().expect("an acquaintance is written"))
        .expect("a line without a nul");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("the telephone is answered");
        far
    });
    assert_eq!(
        mt_boundary::mtc_machine_reach(line.as_ptr()),
        0,
        "the answerer is reached: {}",
        last_said()
    );
    let far = answering.join().expect("the thread stands");
    assert_eq!(head_of_the_device(), None, "a telephone holding nothing");

    // The anchor its operator reads off the answerer: the proposals of the first two windows.
    let proposal_of = |window: u64| {
        let held = far
            .proposal_of(window)
            .expect("the store answers")
            .expect("a proposal kept for every window lived");
        Layout::bytes(&held).expect("the bytes of a proposal")
    };
    let earlier = proposal_of(FROM);
    let later = proposal_of(FROM + 1);

    // Refused before anything is read: nowhere to write the head, and a proposal shorter than its
    // layout, read at the length handed beside it.
    assert_eq!(
        mt_boundary::mtc_machine_join(
            earlier.as_ptr(),
            earlier.len(),
            later.as_ptr(),
            later.len(),
            std::ptr::null_mut(),
        ),
        -1,
        "a walk with nowhere to write its head"
    );
    let mut window = u64::MAX;
    assert_eq!(join(&earlier[..earlier.len() - 1], &later, &mut window), -1);
    assert!(
        last_said().contains("Length"),
        "a short proposal is refused by its length: {}",
        last_said()
    );

    // Refused by the walk: the two proposals in the other order, and a forged pair linked to itself
    // and to nothing of the chain. Neither moves the head of the telephone, and neither writes one.
    assert_eq!(join(&later, &earlier, &mut window), -1);
    assert!(
        last_said().contains("not consecutive"),
        "a pair in the other order is no anchor: {}",
        last_said()
    );
    let mut forged_earlier =
        <mt_state::layout::Proposal as Layout>::parse(&earlier).expect("the earlier proposal");
    forged_earlier.cement_aggregate[0] ^= 1;
    let mut forged_later =
        <mt_state::layout::Proposal as Layout>::parse(&later).expect("the later proposal");
    forged_later.previous = forged_earlier.id().expect("an identifier");
    let forged_earlier = Layout::bytes(&forged_earlier).expect("bytes");
    let forged_later = Layout::bytes(&forged_later).expect("bytes");
    assert_eq!(join(&forged_earlier, &forged_later, &mut window), -1);
    assert!(
        last_said().contains("does not decide the proposal it finalizes"),
        "a forged anchor is refused at its first certificate: {}",
        last_said()
    );
    assert_eq!(window, u64::MAX, "a refused walk wrote a head");
    assert_eq!(head_of_the_device(), None, "a refused walk moved the head");

    // The honest anchor: the head the telephone reaches is the head the living machines hold, and
    // not the later window of the anchor it was handed.
    assert_eq!(
        join(&earlier, &later, &mut window),
        0,
        "the walk reaches the head: {}",
        last_said()
    );
    assert_eq!(window, FROM + WINDOWS - 2);
    assert_ne!(window, FROM + 1, "the door answered with its anchor");
    assert_eq!(head_of_the_device(), Some(FROM + WINDOWS - 2));
    drop(far);
}
