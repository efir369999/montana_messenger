#![cfg(unix)]
// CNS-20 / issue #21 F2: a window closed, a wait inside the patience of that wait and a patience run
// out are three readings, and only the last is a stall. A healthy node -- one that closes, or one
// that waits inside its budget -- reads exit 0 through the operator's `--status`.
//
// **The wrong implementations it refuses**, named before the assertions: a pulse that clears its
// reading at a close, under which a closing node reads `no diagnostics` and exits 4; a pulse that
// writes every wait as its verdict, under which a node waiting inside its budget exits 1 or 2 exactly
// as an exhausted one does; and one that leaves an exhausted wait reading as a wait, under which a
// stalled node exits 0.
use montana_node::say::{PulseStatus, Verdict};
use montana_node::{pulse, status, Configuration, Machine, NodeError};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
mod common;
use common::{stall, Scratch};

// How many askings the closing machine may wait at a round: past what a cohort of itself spends.
const PATIENCE: u32 = 2_000;

// How many askings the withheld round is waited: long enough for a status process to start and read
// while the pulse still waits, and short enough that it then runs out.
const PATIENCE_OF_THE_WAIT: u32 = 800;

fn status_of(at: &std::path::Path) -> Output {
    Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["--status", "--data"])
        .arg(at)
        .output()
        .unwrap()
}

fn text(bytes: Vec<u8>) -> String {
    String::from_utf8(bytes).unwrap().trim().to_string()
}

#[test]
fn a_window_that_closes_reads_exit_zero() {
    let at = Scratch::named("status-closed");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let machine = Arc::new(machine);
    let _server = status::Server::open(&at.0, Arc::clone(&machine)).unwrap();
    let cohort = pulse::Cohort::of(&[machine.naming_half().unwrap()]).expect("a cohort of itself");
    let lived = pulse::live(&machine, &cohort, 0, 1, PATIENCE).expect("window 0 closes");
    assert_eq!(lived.len(), 1);

    let reading = machine
        .counts()
        .status()
        .expect("a reading after the close");
    assert!(
        matches!(reading, PulseStatus::Closed { window: 0, .. }),
        "{reading:?}"
    );
    assert_eq!(reading.on(), None);
    assert_eq!(reading.exit_code(), 0);
    assert_eq!(PulseStatus::parse(&reading.to_string()), Some(reading));
    let read = status_of(&at.0);
    assert_eq!(read.status.code(), Some(0), "{}", text(read.stderr));
    assert_eq!(text(read.stdout), reading.to_string());
    assert!(reading.to_string().starts_with("closed window 0; refused "));
}

#[test]
fn a_wait_inside_the_patience_is_not_an_exhausted_stall() {
    let (at, machine, cohort) = stall::machine("status-waiting");
    let machine = Arc::new(machine);
    let _server = status::Server::open(&at.0, Arc::clone(&machine)).unwrap();
    let counts = machine.counts();
    let done = Arc::new(AtomicBool::new(false));
    // The first wait, read from the counts and through the binary while the pulse still waits.
    let watcher = {
        let (counts, done, data) = (Arc::clone(&counts), Arc::clone(&done), at.0.clone());
        std::thread::spawn(move || {
            while !done.load(Ordering::Acquire) {
                if let Some(reading @ PulseStatus::Waiting { .. }) = counts.status() {
                    return Some((reading, status_of(&data)));
                }
                std::thread::yield_now();
            }
            None
        })
    };
    let errand = |machine: &Machine, _| stall::withhold(machine);
    let error = pulse::live_doing(&machine, &cohort, 0, 1, PATIENCE_OF_THE_WAIT, Some(&errand))
        .err()
        .expect("a withheld round runs out of patience");
    done.store(true, Ordering::Release);
    let (waiting, read) = watcher
        .join()
        .unwrap()
        .expect("the pulse was read while it waited");

    // Inside the patience: the shortfall it waits on, how far the patience has gone, and exit 0.
    match waiting {
        PulseStatus::Waiting {
            on,
            waited,
            patience,
            ..
        } => {
            assert_eq!(on, Verdict::NoData);
            assert_eq!(patience, PATIENCE_OF_THE_WAIT);
            assert!(waited < patience, "{waiting:?}");
        }
        other => panic!("{other:?}"),
    }
    assert_eq!(waiting.exit_code(), 0);
    assert_eq!(PulseStatus::parse(&waiting.to_string()), Some(waiting));
    assert_eq!(read.status.code(), Some(0), "{}", text(read.stderr));
    let shown = text(read.stdout);
    assert!(shown.starts_with("waiting: no data; asking "), "{shown}");
    assert!(
        shown.contains(&format!(" of {PATIENCE_OF_THE_WAIT}; refused ")),
        "{shown}"
    );

    // The patience ran out: the stall, its code, and the same through the binary.
    assert_eq!(
        error,
        NodeError::Stalled {
            on: Verdict::NoData,
            what: "a round no beacon ever stood at",
        }
    );
    let stalled = counts.status().expect("a reading after the stall");
    assert!(
        matches!(
            stalled,
            PulseStatus::Stalled {
                on: Verdict::NoData,
                ..
            }
        ),
        "{stalled:?}"
    );
    assert_eq!(stalled.exit_code(), Verdict::NoData.exit_code());
    assert_eq!(PulseStatus::parse(&stalled.to_string()), Some(stalled));
    let read = status_of(&at.0);
    assert_eq!(read.status.code(), Some(Verdict::NoData.exit_code().into()));
    assert_eq!(text(read.stderr), stalled.to_string());
}
