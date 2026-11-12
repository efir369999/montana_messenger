// CNS-20: rejects a live timeout that commits a window, moves the head, or grants issuance.
// The valid heavy evidence is retained; every foreign closing pledge is withheld.
use montana_node::{pulse, say::Verdict, Configuration, Machine, NodeError};
mod common;
use common::stall;

#[test]
fn a_timeout_with_a_final_beacon_closes_nothing_even_after_restart() {
    let (at, machine, cohort) = stall::machine("timeout-not-close");
    let head = machine.head().unwrap();
    let closed = machine.closed_window().unwrap();
    let notes = machine.value().unwrap().notes_root();
    let census = machine.lived_census().unwrap().len();
    let errand = |machine: &Machine, _| stall::cut_closing_pledges(machine, &cohort);
    let error = pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&errand))
        .err()
        .expect("withheld closing pledges cannot decide");
    assert!(
        matches!(error, NodeError::Stalled { on: Verdict::NoQuorum, what }
        if what.contains("agreement undecided")),
        "{error:?}"
    );
    assert_eq!(machine.head().unwrap(), head, "the timeout moved the head");
    assert_eq!(
        machine.closed_window().unwrap(),
        closed,
        "the timeout closed a window"
    );
    assert!(machine.proposal_of(0).unwrap().is_none());
    assert_eq!(
        machine.value().unwrap().notes_root(),
        notes,
        "timeout issued notes"
    );
    assert_eq!(
        machine.lived_census().unwrap().len(),
        census,
        "timeout granted standing"
    );
    let agreement = machine
        .agreement_of(0)
        .unwrap()
        .expect("the unfinished attempt is retained");
    assert!(
        !agreement.made.is_empty(),
        "the live path made its own closing pledge"
    );
    drop(machine);

    let (restarted, born) = Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).unwrap();
    assert!(!born);
    assert_eq!(restarted.head().unwrap(), head);
    assert_eq!(restarted.closed_window().unwrap(), closed);
    assert!(restarted.proposal_of(0).unwrap().is_none());
    assert_eq!(restarted.value().unwrap().notes_root(), notes);
    assert_eq!(restarted.lived_census().unwrap().len(), census);
    assert_eq!(restarted.agreement_of(0).unwrap(), Some(agreement));
}
