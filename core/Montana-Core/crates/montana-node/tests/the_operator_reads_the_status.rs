#![cfg(unix)]
// CNS-20: rejects stale-file success, a second writer, and an operator verdict hidden by a prefix.
use montana_node::{pulse, status, Configuration, Machine};
use std::process::Command;
mod common;
use common::stall;

fn status_of(at: &std::path::Path) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["--status", "--data"])
        .arg(at)
        .output()
        .unwrap()
}

#[test]
fn the_status_is_from_the_live_process_and_disappears_with_its_lock() {
    let (at, machine, cohort) = stall::machine("operator-status");
    let machine = std::sync::Arc::new(machine);
    let server = status::Server::open(&at.0, std::sync::Arc::clone(&machine)).unwrap();
    let empty = status_of(&at.0);
    assert_eq!(empty.status.code(), Some(4));
    assert!(String::from_utf8(empty.stderr)
        .unwrap()
        .starts_with("no diagnostics"));

    let errand = |machine: &Machine, _| stall::withhold(machine);
    assert!(pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&errand)).is_err());
    let expected = machine.counts().status().unwrap().to_string();
    let read = status_of(&at.0);
    assert_eq!(
        read.status.code(),
        Some(montana_node::say::Verdict::NoData.exit_code().into())
    );
    assert_eq!(String::from_utf8(read.stderr).unwrap().trim(), expected);
    assert!(expected.starts_with("no data; asking "));

    let second = Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .arg("--data")
        .arg(&at.0)
        .args(["--listen", "127.0.0.1:0"])
        .output()
        .unwrap();
    assert!(
        !second.status.success(),
        "two processes held one data directory"
    );
    assert!(Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).is_err());
    drop(server);
    drop(machine);
    // Keep the locator and socket on disk: their existence must not imply a live process.
    assert!(at.0.join("pulse-status").exists());
    let stopped = status_of(&at.0);
    assert_eq!(stopped.status.code(), Some(4));
    assert!(String::from_utf8(stopped.stderr)
        .unwrap()
        .starts_with("no diagnostics"));
    let (restarted, _) = Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).unwrap();
    let server = status::Server::open(&at.0, std::sync::Arc::new(restarted)).unwrap();
    let new = status_of(&at.0);
    assert!(
        !new.status.success(),
        "a new process inherited an old verdict"
    );
    drop(server);
}

// CNS-20 / issue #21 F3: an operator polling the status while the node restarts never stops it from
// starting. The wrong implementation it refuses is a reader that takes the store's lock, even for
// the instant of a probe: in an instant no node holds it, the reader does, and the node starting
// then refuses its own store as held by another.
#[test]
fn a_status_read_in_a_loop_never_stops_a_node_from_starting() {
    const RESTARTS: usize = 50;
    let at = common::Scratch::named("status-restart");
    drop(Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine is born"));
    let done = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    // The restarts begin once the reader has read, so they never all pass before it ran at all.
    let reading = std::sync::Arc::new(std::sync::Barrier::new(2));
    let reader = {
        let (data, done, reading) = (
            at.0.clone(),
            std::sync::Arc::clone(&done),
            std::sync::Arc::clone(&reading),
        );
        std::thread::spawn(move || {
            let _ = status::read(&data);
            let mut reads = 1u64;
            reading.wait();
            while !done.load(std::sync::atomic::Ordering::Acquire) {
                let _ = status::read(&data);
                reads += 1;
            }
            reads
        })
    };
    reading.wait();
    let mut refused = Vec::new();
    for restart in 0..RESTARTS {
        match Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")) {
            Ok((machine, born)) => {
                assert!(!born, "a restart drew a second secret");
                let machine = std::sync::Arc::new(machine);
                let server = status::Server::open(&at.0, std::sync::Arc::clone(&machine)).unwrap();
                drop(server);
                drop(machine);
            }
            Err(error) => refused.push((restart, format!("{error:?}"))),
        }
    }
    done.store(true, std::sync::atomic::Ordering::Release);
    let reads = reader.join().unwrap();
    assert!(reads > 0, "the reader never read");
    assert!(
        refused.is_empty(),
        "{} of {RESTARTS} starts refused while the status was read {reads} times: {refused:?}",
        refused.len()
    );
}

#[test]
fn a_status_query_does_not_create_a_missing_directory() {
    let at = common::Scratch::named("missing-status");
    let missing = at.0.join("absent");
    let answer = status_of(&missing);
    assert!(!answer.status.success());
    assert!(String::from_utf8(answer.stderr)
        .unwrap()
        .starts_with("no diagnostics"));
    assert!(!missing.exists());
}
