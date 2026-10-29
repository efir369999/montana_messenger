// A network opens by an act of its operator on an empty store, and in no other way. Consensus, "The
// cold start": "A machine opens window zero only when its operator asks it to open and only while it
// holds nothing of a chain — no head, no window it closed, no proposal and no record of the
// agreement. A machine that holds a chain and is asked to open is refused [...] A machine that holds
// nothing and is not asked to open opens no window; it enters a network only from an anchor". The
// opening cohort is the electorate of window zero, "which the proposal of window zero must carry"
// (Consensus, "The pulse and the close of a window").
//
// **The world outside the rules, arranged by this test.** The machine is the binary an operator
// runs, started on a store whose secret the test bore beforehand, so the half the operator hands
// over is known before the first start. A cohort of itself is all one machine needs to close window
// zero alone: its heavy attestation is the quorum of an electorate of one. Every start names one
// window to live, so a machine that should have been refused and was not stops after it rather than
// living until it is killed.
//
// **The wrong implementations it refuses**, one beside each test.

use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine, NodeError};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

mod common;
use common::Scratch;

const NO_ANCHOR: &str = "refused: a machine with no anchor opens no window";
const OPENED_OVER_A_CHAIN: &str = "refused: a network opened on a store that holds a chain";

// **Every test of this file runs alone.** A test that starts the binary forks, and until the child
// execs it holds a duplicate of every descriptor of this process. One of them can be the lock of the
// root of a store another test has just dropped: `mt-store`, `Store::open`, where the lock goes with
// the handle. The next opening of that store is then refused `HeldByAnother` for the instant between
// the fork and the exec. Seen on Lauterbourg-2 (a640-open3): one run in three parallel, at "the store
// opens again"; green under --test-threads=1. The lock is right to refuse. What shares one process
// is the tests, not the machines.
static ALONE: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn alone() -> std::sync::MutexGuard<'static, ()> {
    ALONE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

// A store with a secret borne and nothing else, and the naming half of the machine it is. A secret
// is written once and its temporary is kept beside it, which the next opening of the store sweeps;
// the store is opened once more here, so what a test compares is the store as every start leaves
// it and not the sweep of a temporary.
fn borne(at: &Path, secret: [u8; 32]) -> [u8; 32] {
    mt_store::Store::open(at)
        .expect("a fresh store opens")
        .bear_secret(&secret)
        .expect("the secret is borne");
    drop(mt_store::Store::open(at).expect("the store opens again"));
    Cohort::half_of(&secret)
}

// The binary as an operator starts it, handed a cohort of itself and one window to live.
fn started(at: &Path, half: &[u8; 32], open: bool) -> Output {
    let shown: String = half.iter().map(|b| format!("{b:02x}")).collect();
    let mut command = Command::new(env!("CARGO_BIN_EXE_montana-node"));
    command.arg("--data").arg(at).args([
        "--listen",
        "127.0.0.1:0",
        "--admitted",
        &shown,
        "--windows",
        "1",
    ]);
    if open {
        command.arg("--open");
    }
    command.output().expect("the binary runs")
}

// Every directory and every file under `at` with its bytes: what a store holds, compared whole.
fn everything_under(at: &Path) -> BTreeMap<PathBuf, Option<Vec<u8>>> {
    let mut out = BTreeMap::new();
    let mut pending = vec![at.to_path_buf()];
    while let Some(dir) = pending.pop() {
        for entry in std::fs::read_dir(&dir).expect("the directory reads") {
            let path = entry.expect("an entry reads").path();
            let named = path.strip_prefix(at).expect("under the root").to_path_buf();
            if path.is_dir() {
                out.insert(named, None);
                pending.push(path);
            } else {
                out.insert(named, Some(std::fs::read(&path).expect("the file reads")));
            }
        }
    }
    out
}

// A store that pledged in window zero and closed nothing: the machine opened window zero, stood one
// round ahead of it so no beacon ever stood where it read, and gave the round up — its record of the
// agreement on window zero stands, and nothing else of a chain.
fn stopped_inside_window_zero(at: &Path, secret: [u8; 32]) -> [u8; 32] {
    let half = borne(at, secret);
    let (machine, _) =
        Machine::start(&Configuration::at(at, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[half]).expect("a cohort of itself");
    let ahead =
        |machine: &Machine, window: u64| machine.enter_round(window, pulse::opening_chain(), 1);
    let errand: pulse::Errand<'_> = &ahead;
    assert_eq!(
        pulse::live_doing(&machine, &cohort, 0, 1, 4, Some(errand)).map(|_| ()),
        Err(NodeError::Stalled {
            on: montana_node::say::Verdict::NoData,
            what: "a round no beacon ever stood at"
        })
    );
    assert!(machine
        .agreement_of(0)
        .expect("the store answers")
        .is_some());
    assert_eq!(machine.closed_window().expect("the store answers"), None);
    assert_eq!(machine.head().expect("the store answers"), None);
    half
}

// Refuses the start of fa8ec28, under which a machine handed a cohort and no window opens window
// zero on the Genesis State Hash of its own accord — there it lives the window and exits in success,
// and its store holds a chain it opened alone.
#[test]
fn a_machine_holding_nothing_and_not_asked_to_open_is_refused_and_writes_nothing() {
    let _alone = alone();
    let at = Scratch::named("open-neither");
    let half = borne(&at.0, [0x71; 32]);
    let before = everything_under(&at.0);
    let ran = started(&at.0, &half, false);
    let said = String::from_utf8_lossy(&ran.stderr);
    assert!(!ran.status.success(), "a machine with no anchor lived");
    assert!(said.contains(NO_ANCHOR), "{said}");
    assert_eq!(
        everything_under(&at.0),
        before,
        "a refused machine wrote to its store"
    );
}

// Refuses the start of ced7d83f, whose refusal of a machine left out of the cohort printed the half
// it is named by on the terminal (#22, K1): the refusal names the file the half stands in, and the
// store is left as it was found.
#[test]
fn a_machine_left_out_of_the_cohort_is_refused_without_its_half() {
    let _alone = alone();
    let at = Scratch::named("open-outside");
    let half = borne(&at.0, [0x75; 32]);
    let other = Cohort::half_of(&[0x76; 32]);
    let before = everything_under(&at.0);
    let ran = started(&at.0, &other, false);
    let said = String::from_utf8_lossy(&ran.stderr);
    assert!(!ran.status.success(), "a machine outside its cohort lived");
    assert!(
        said.contains("is not among the 1 named as admitted"),
        "{said}"
    );
    assert!(said.contains(montana_node::private::FILE), "{said}");
    let shown: String = half.iter().map(|b| format!("{b:02x}")).collect();
    let printed = format!("{said}{}", String::from_utf8_lossy(&ran.stdout));
    assert!(
        !printed.contains(&shown),
        "the half on a default line: {printed}"
    );
    assert_eq!(
        everything_under(&at.0),
        before,
        "a machine refused outside its cohort wrote to its store"
    );
}

// Refuses an --open that is not window zero on the cohort handed: the binary of fa8ec28, which does
// not know the flag and refuses it, and an opening that waits for an anchor, opens another window or
// carries another tree of admitted machines than the halves the operator named.
#[test]
fn an_operator_opens_window_zero_on_the_cohort_handed_over() {
    let _alone = alone();
    let at = Scratch::named("open-empty");
    let half = borne(&at.0, [0x72; 32]);
    let ran = started(&at.0, &half, true);
    let said = String::from_utf8_lossy(&ran.stdout);
    assert!(
        ran.status.success(),
        "{said}\n{}",
        String::from_utf8_lossy(&ran.stderr)
    );
    assert!(
        said.contains("living from window 0 in a cohort of 1"),
        "{said}"
    );
    // **The default lines name nobody** (#22, K1): no address of this machine, no half it is named
    // by, no part of a nullifier and no amount reach the terminal; they stand in the owner-only file
    // of the data directory. Refuses the start of 7e2ac1b's parent, which printed all four.
    let shown: String = half.iter().map(|b| format!("{b:02x}")).collect();
    for line in said.lines() {
        assert!(
            !line.contains("127.0.0.1"),
            "an address on a default line: {line}"
        );
        assert!(!line.contains(&shown), "the half on a default line: {line}");
        assert!(!line.contains(" part "), "a part on a default line: {line}");
        assert!(
            !line.contains("coin"),
            "an amount on a default line: {line}"
        );
    }
    let details = at.0.join(montana_node::private::FILE);
    let mode = std::os::unix::fs::PermissionsExt::mode(
        &std::fs::metadata(&details)
            .expect("the owner-only file stands")
            .permissions(),
    );
    assert_eq!(mode & 0o777, 0o600);
    let kept = std::fs::read_to_string(&details).expect("the file of details reads");
    assert!(kept.contains("answering at 127.0.0.1:"), "{kept}");
    assert!(kept.contains(&shown), "{kept}");
    assert!(kept.contains(" -- part "), "{kept}");
    let (machine, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    assert!(!born);
    assert_eq!(machine.closed_window().expect("the store answers"), Some(0));
    let opened = machine
        .proposal_of(0)
        .expect("the store answers")
        .expect("the proposal of window zero is kept");
    let cohort = Cohort::of(&[half]).expect("the cohort handed over");
    assert_eq!(opened.window, 0);
    assert_eq!(
        opened.previous,
        mt_state::tables::genesis_state_hash().expect("the hash of the network")
    );
    assert_eq!(opened.admitted_root, cohort.root().bytes());
    assert_eq!(opened.admitted_count, cohort.count());
}

// Refuses an --open that asks only whether a window was closed — the refusal `enter_round` already
// makes — and so opens window zero afresh over a store that holds its record of the agreement on it;
// and a start without --open that takes that record for an anchor and lives window zero again.
#[test]
fn an_open_on_a_store_holding_a_chain_is_refused_and_writes_nothing() {
    let _alone = alone();
    let at = Scratch::named("open-held");
    let half = stopped_inside_window_zero(&at.0, [0x73; 32]);
    let before = everything_under(&at.0);
    let ran = started(&at.0, &half, true);
    let said = String::from_utf8_lossy(&ran.stderr);
    assert!(!ran.status.success(), "a network opened over a chain");
    assert!(said.contains(OPENED_OVER_A_CHAIN), "{said}");
    assert_eq!(
        everything_under(&at.0),
        before,
        "a refused opening wrote to its store"
    );
    // The record of window zero is no anchor: a machine stopped inside the first window holds no
    // final proposal to live from.
    let ran = started(&at.0, &half, false);
    let said = String::from_utf8_lossy(&ran.stderr);
    assert!(
        !ran.status.success(),
        "a record of the agreement was an anchor"
    );
    assert!(said.contains(NO_ANCHOR), "{said}");
    assert_eq!(
        everything_under(&at.0),
        before,
        "a machine with no anchor wrote to its store"
    );
}

// Refuses a pulse that leaves the rule to the terminal: a caller of the library — the boundary an
// application stands on — handing window zero to a machine that holds a chain, which the pulse of
// fa8ec28 lives again on the Genesis State Hash.
#[test]
fn the_pulse_opens_window_zero_on_an_empty_store_alone() {
    let _alone = alone();
    let at = Scratch::named("open-pulse");
    let half = stopped_inside_window_zero(&at.0, [0x74; 32]);
    let before = everything_under(&at.0);
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[half]).expect("a cohort of itself");
    assert_eq!(
        pulse::live(&machine, &cohort, 0, 1, 4).map(|_| ()),
        Err(NodeError::Refused {
            what: "a network opened on a store that holds a chain"
        })
    );
    drop(machine);
    assert_eq!(everything_under(&at.0), before);
}
