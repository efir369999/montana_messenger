// CNS-20: these reject a live pulse that conflates absent evidence and absent quorum, or lets a
// refused public deposit name the cause (issue #21, F1 and F1a).
use montana_node::{pulse, say::Verdict, NodeError};
use mt_state::Layout;
mod common;
use common::{stall, walk};

#[test]
fn no_quorum_is_named_when_closing_pledges_are_withheld() {
    let (_at, machine, cohort) = stall::machine("stall-quorum");
    let errand = |machine: &montana_node::Machine, _| stall::cut_closing_pledges(machine, &cohort);
    let error = pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&errand))
        .err()
        .expect("a stalled pulse");
    assert!(
        matches!(error, NodeError::Stalled { on: Verdict::NoQuorum, what } if what.contains("agreement undecided")),
        "{error:?}"
    );
    assert_eq!(
        machine.counts().status().unwrap().on(),
        Some(Verdict::NoQuorum)
    );
}

#[test]
fn no_data_is_named_when_no_beacon_can_be_collected() {
    let (_at, machine, cohort) = stall::machine("stall-data");
    let errand = |machine: &montana_node::Machine, _| stall::withhold(machine);
    let error = pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&errand))
        .err()
        .expect("a stalled pulse");
    assert!(
        matches!(
            error,
            NodeError::Stalled {
                on: Verdict::NoData,
                ..
            }
        ),
        "{error:?}"
    );
    assert_eq!(
        machine.counts().status().unwrap().on(),
        Some(Verdict::NoData)
    );
}

#[test]
fn a_mutated_attestation_does_not_replace_the_missing_data_verdict() {
    let (_at, machine, cohort) = stall::machine("stall-proof");
    let errand = |machine: &montana_node::Machine, _| {
        let previous = montana_node::certificate::Predecessor::Genesis.id()?;
        let mut beacon = walk::opening(0, previous);
        beacon.cement_count = 1; // No valid heavy leaf supplies the claimed cement.
        let (mut heavies, _, _) =
            walk::heavies(&stall::SECRETS[..1], &cohort, 0, &beacon, previous);
        heavies[0].signature[0] ^= 1; // An actual verifier refusal, not a fabricated counter.
        stall::put(machine, &beacon.bytes().unwrap())?;
        stall::put(machine, &heavies[0].bytes().unwrap())?;
        stall::withhold(machine)
    };
    let error = pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&errand))
        .err()
        .expect("a stalled pulse");
    assert!(
        matches!(
            error,
            NodeError::Stalled {
                on: Verdict::NoData,
                ..
            }
        ),
        "{error:?}"
    );
    assert!(machine.counts().refusals() > 0);
    assert_eq!(
        machine.counts().status().unwrap().on(),
        Some(Verdict::NoData)
    );
    assert!(machine.counts().status().unwrap().refused() > 0);
}

// CNS-20 / F1: real mutated deposits must not label absent closing pledges as a proof fault.
#[test]
fn a_mutated_attestation_does_not_replace_the_no_quorum_verdict() {
    let (_at, machine, cohort) = stall::machine("stall-quorum-junk");
    let errand = |machine: &montana_node::Machine, _| {
        let previous = montana_node::certificate::Predecessor::Genesis.id()?;
        let beacon = walk::opening(0, previous);
        let (mut heavies, _, _) =
            walk::heavies(&stall::SECRETS[..1], &cohort, 0, &beacon, previous);
        heavies[0].signature[0] ^= 1;
        stall::put(machine, &heavies[0].bytes().unwrap())?;
        stall::cut_closing_pledges(machine, &cohort)
    };
    let error = pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&errand))
        .err()
        .expect("a stalled pulse");
    assert!(
        matches!(error, NodeError::Stalled { on: Verdict::NoQuorum, what }
            if what.contains("agreement undecided")),
        "{error:?}"
    );
    let status = machine.counts().status().unwrap();
    assert_eq!(status.on(), Some(Verdict::NoQuorum));
    assert!(
        status.refused() > 0,
        "the actual verifier must refuse the mutated deposit"
    );
    assert!(status.to_string().contains("; refused "));
}
