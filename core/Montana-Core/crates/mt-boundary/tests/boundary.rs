// The boundary walked the way a client walks it: through the doors themselves, in the order a
// telephone walks them, and never through the crates behind them. A test that called the library
// would be testing the library again; what is under test here is the line between the two.

use std::ffi::{c_char, CString};

// Every door of this boundary stands in the header a client compiles against, and every line of
// that header names a door. The wrong implementation this refuses is a door added to the library
// and forgotten in the header: a client would then link against a symbol its compiler never saw,
// and the mismatch would be found by whoever ran it rather than by whoever wrote it.
#[test]
fn every_door_stands_in_the_header_and_every_line_of_the_header_is_a_door() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let library =
        std::fs::read_to_string(root.join("src/lib.rs")).expect("the library is readable");
    let header = std::fs::read_to_string(root.join("include/montana_core.h"))
        .expect("the header is readable");

    let mut doors: Vec<String> = Vec::new();
    for line in library.lines() {
        let Some(after) = line.trim_start().strip_prefix("pub extern \"C\" fn ") else {
            continue;
        };
        let Some((name, _)) = after.split_once('(') else {
            continue;
        };
        doors.push(name.to_string());
    }
    assert!(!doors.is_empty(), "a boundary declaring no door at all");

    let mut declared: Vec<String> = Vec::new();
    for line in header.lines() {
        let Some(at) = line.find("mtc_") else {
            continue;
        };
        let rest = &line[at..];
        let Some((name, _)) = rest.split_once('(') else {
            continue;
        };
        declared.push(name.to_string());
    }

    for door in &doors {
        assert!(
            declared.contains(door),
            "a door of the library the header does not declare: {door}"
        );
    }
    for one in &declared {
        assert!(
            doors.contains(one),
            "a door the header declares and the library does not carry: {one}"
        );
    }
}

fn text_of(out: &[c_char], len: usize) -> String {
    let bytes: Vec<u8> = out[..len].iter().map(|c| *c as u8).collect();
    String::from_utf8(bytes).expect("text of the boundary")
}

fn last_said() -> String {
    let mut out = [0 as c_char; 512];
    let mut len = 0usize;
    let answer = mt_boundary::mtc_last_said(out.as_mut_ptr(), out.len(), &mut len);
    assert_eq!(answer, 0, "the word this boundary keeps is readable");
    text_of(&out, len)
}

// The journey of a telephone, in one run because one device is one machine: a door before the
// device stands refuses, the device opens, a person is born, the wallet answers what a payer needs
// of them, the machine answers what an operator hands over, and the frame that mints is proven at
// the width the set derives.
#[test]
fn a_telephone_opens_bears_a_person_and_proves_the_frame_that_mints() {
    let mut stands = -1i32;
    assert_eq!(
        mt_boundary::mtc_person_stands(&mut stands),
        -1,
        "a door of value refuses while no device stands"
    );
    assert!(
        last_said().contains("no device stands"),
        "and the word it keeps says which: {}",
        last_said()
    );

    let at = std::env::temp_dir().join(format!("mt-bindings-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&at);
    let dir = CString::new(at.to_str().expect("a path of text")).expect("a path without a nul");
    let listen = CString::new("127.0.0.1:0").expect("an address without a nul");
    let mut born = -1i32;
    assert_eq!(
        mt_boundary::mtc_device_open(dir.as_ptr(), listen.as_ptr(), &mut born),
        0,
        "the device opens: {}",
        last_said()
    );
    assert_eq!(born, 1, "the first start drew this machine's secret");

    let mut standing = 0i32;
    assert_eq!(mt_boundary::mtc_device_standing(&mut standing), 0);
    assert_eq!(standing, 1);
    assert_eq!(
        mt_boundary::mtc_device_open(dir.as_ptr(), listen.as_ptr(), &mut born),
        -1,
        "a second device is refused rather than shadowing the first"
    );

    // Which network this core is of, answered by the boundary and by the library alike.
    let mut hash = [0u8; 32];
    assert_eq!(mt_boundary::mtc_genesis_state_hash(hash.as_mut_ptr()), 0);
    assert_eq!(
        Some(hash),
        mt_state::tables::genesis_state_hash(),
        "the boundary answers the value the library holds and never one of its own"
    );

    assert_eq!(mt_boundary::mtc_self_test(), 0, "{}", last_said());
    let mut alive = 0usize;
    assert_eq!(mt_boundary::mtc_sources_alive(&mut alive), 0);
    assert!(alive >= 3, "a device drawing from fewer sources than three");

    // The person: none stands, one is born, the words come back once.
    assert_eq!(mt_boundary::mtc_person_stands(&mut stands), 0);
    assert_eq!(stands, 0);
    let mut words = [0 as c_char; 1024];
    let mut len = 0usize;
    assert_eq!(
        mt_boundary::mtc_person_bear(words.as_mut_ptr(), words.len(), &mut len),
        0,
        "{}",
        last_said()
    );
    let spoken = text_of(&words, len);
    assert_eq!(spoken.split_whitespace().count(), 24);
    assert_eq!(mt_boundary::mtc_person_stands(&mut stands), 0);
    assert_eq!(stands, 1);
    assert_eq!(
        mt_boundary::mtc_person_bear(words.as_mut_ptr(), words.len(), &mut len),
        -1,
        "a second person is refused where one already stands"
    );

    // A buffer too small is answered with the length it must hold, and a place that is nothing is
    // answered rather than written to.
    let mut narrow = [0 as c_char; 4];
    let mut needed = 0usize;
    assert_eq!(
        mt_boundary::mtc_person_bear(narrow.as_mut_ptr(), narrow.len(), &mut needed),
        -1,
        "the door refuses for the person that already stands before it looks at the buffer"
    );
    assert_eq!(
        mt_boundary::mtc_machine_account(narrow.as_mut_ptr(), narrow.len(), &mut needed),
        -3,
        "a buffer smaller than the account is answered with the width it must hold"
    );
    assert!(needed > narrow.len());
    assert_eq!(
        mt_boundary::mtc_machine_account(std::ptr::null_mut(), 0, &mut needed),
        -2,
        "a place that is nothing is answered rather than written to"
    );

    // What a payer needs of this person, and what the wallet holds before anything is minted.
    let mut half = [0u8; 32];
    let mut note_pk = [0u8; 32];
    assert_eq!(
        mt_boundary::mtc_person_payee(half.as_mut_ptr(), note_pk.as_mut_ptr()),
        0
    );
    assert_ne!(half, [0u8; 32]);
    assert_ne!(note_pk, [0u8; 32]);
    assert_ne!(half, note_pk);
    let mut balance = [0u8; 16];
    assert_eq!(mt_boundary::mtc_wallet_balance(balance.as_mut_ptr()), 0);
    assert_eq!(
        balance, [0u8; 16],
        "a wallet holding nothing before it mints"
    );
    let mut notes = 1usize;
    assert_eq!(mt_boundary::mtc_wallet_notes(&mut notes), 0);
    assert_eq!(notes, 0);

    // The machine: its half, the line an operator hands over, and the account it keeps of itself.
    let mut naming = [0u8; 32];
    assert_eq!(mt_boundary::mtc_machine_naming_half(naming.as_mut_ptr()), 0);
    assert_ne!(naming, [0u8; 32]);
    // The line carries the key this machine answers with, which is a public key of the
    // signing scheme in hexadecimal: a buffer of a few hundred bytes is answered with the
    // width it must hold rather than with the line.
    let mut line = vec![0 as c_char; 8192];
    assert_eq!(
        mt_boundary::mtc_machine_acquaintance(line.as_mut_ptr(), line.len(), &mut len),
        0,
        "{}",
        last_said()
    );
    assert!(text_of(&line, len).contains("127.0.0.1:"));
    let mut account = [0 as c_char; 1024];
    assert_eq!(
        mt_boundary::mtc_machine_account(account.as_mut_ptr(), account.len(), &mut len),
        0
    );
    assert!(text_of(&account, len).contains("arrived"));

    let mut window = 1u64;
    let mut present = 1i32;
    assert_eq!(mt_boundary::mtc_machine_head(&mut window, &mut present), 0);
    assert_eq!(present, 0, "a machine holding no proposal yet");

    let (mut held, mut ceiling, mut reached) = (1usize, 0usize, 1usize);
    assert_eq!(
        mt_boundary::mtc_machine_links(&mut held, &mut ceiling, &mut reached),
        0
    );
    assert_eq!(held, 0);
    assert_eq!(reached, 0);
    assert!(ceiling > 0, "a machine answering no link at all");

    // The pulse has lived nothing and runs nothing, and the errands are taken before it begins.
    let mut lived = 1usize;
    assert_eq!(mt_boundary::mtc_pulse_lived(&mut lived), 0);
    assert_eq!(lived, 0);
    let mut running = 1i32;
    assert_eq!(mt_boundary::mtc_pulse_running(&mut running), 0);
    assert_eq!(running, 0);
    assert_eq!(mt_boundary::mtc_errand_redeem(0, 1), 0);
    let amount = 1u128.to_le_bytes();
    assert_eq!(
        mt_boundary::mtc_errand_pay(half.as_ptr(), note_pk.as_ptr(), amount.as_ptr()),
        0
    );
    assert_eq!(
        mt_boundary::mtc_pulse_begin(std::ptr::null(), 0, 0, 1),
        -1,
        "a cohort of nobody is refused"
    );

    // And what proving costs on the machine running this test, measured on the frame that turns the
    // right of a window into a note. The width is the one the set derives, so a boundary that
    // proved something else would be caught here rather than on a telephone.
    let mut milliseconds = 0u64;
    let mut width = 0usize;
    assert_eq!(
        mt_boundary::mtc_measure_redemption(&mut milliseconds, &mut width),
        0,
        "{}",
        last_said()
    );
    assert_eq!(
        width,
        montana_node::state::State::width_of_a_frame(),
        "the frame this boundary proves is the one the set derives"
    );
    assert!(milliseconds > 0, "a proof that took no time at all");

    // Nothing of the measurement entered the ledger: a device that showed a person what proving
    // costs and paid them for it would be a device minting out of a measurement.
    assert_eq!(mt_boundary::mtc_wallet_balance(balance.as_mut_ptr()), 0);
    assert_eq!(balance, [0u8; 16]);

    let _ = std::fs::remove_dir_all(&at);
}
