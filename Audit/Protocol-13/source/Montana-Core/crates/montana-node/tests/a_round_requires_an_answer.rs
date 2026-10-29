use montana_node::pulse::{Cohort, Pulse};
use montana_node::{Configuration, Machine};
use mt_state::layout::{Confirmation, LightAttestation};
use mt_state::Layout;

mod common;

#[test]
fn only_a_verified_answer_to_this_beacon_moves_the_round() {
    let directory = common::Scratch::named("verified-round");
    let (machine, _) =
        Machine::start(&Configuration::at(&directory.0, "127.0.0.1:0")).expect("local machine");
    let secret = [0x73; 32];
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).unwrap();
    let branch = cohort.branch_of(&secret).unwrap();
    let previous = [0x42; 32];
    let two_before = [0x41; 32];
    let aggregate = [0x37; 32];
    let threshold = mt_pulse::U256::from_be_bytes(&[0xff; 32]);
    let electorate =
        montana_node::certificate::Electorate::opening(cohort.root(), cohort.count(), 12).unwrap();
    let mut pulse = Pulse::open(
        &machine,
        &secret,
        (12, 0, 0),
        &branch,
        previous,
        two_before,
        &electorate,
        &aggregate,
    )
    .unwrap();
    let beacon = pulse.beacon_of_this_round().unwrap();

    let mut fabricated = beacon.clone();
    fabricated.cement_aggregate[0] ^= 1;
    assert!(
        pulse
            .answer(&secret, &fabricated, &aggregate, &threshold)
            .is_err(),
        "a matching context must not authorize signing a fabricated cement"
    );

    // Repeating a local attempt, including after a scheduler delay, grants no
    // right to advance. A published beacon is not an answer to itself.
    for _ in 0..3 {
        assert!(pulse.advance(&machine, &beacon).is_err());
        assert_eq!(pulse.round, 0);
        assert_eq!(pulse.living(), 0);
        assert_eq!(machine.round_of_the_machine(), Some((12, 0, 0)));
    }
    let heavy = pulse
        .answer(&secret, &beacon, &aggregate, &threshold)
        .unwrap()
        .unwrap();
    let heavy = Confirmation::parse(&heavy).unwrap();
    assert!(
        pulse.advance(&machine, &beacon).is_err(),
        "signing is not verification"
    );
    let early_light = pulse
        .standing
        .light(&secret, beacon.id().unwrap(), previous)
        .unwrap();
    assert!(pulse
        .gather_light(&early_light, &aggregate, &beacon, &threshold)
        .is_err());

    let mut bad = heavy.clone();
    bad.signature[0] ^= 1;
    assert!(pulse
        .gather(&bad, &cohort.root(), &aggregate, &beacon, &threshold)
        .is_err());
    assert!(!pulse.can_advance(&beacon));

    assert!(pulse
        .gather(&heavy, &cohort.root(), &aggregate, &beacon, &threshold)
        .unwrap());
    assert!(pulse.can_advance(&beacon));
    assert!(!pulse
        .gather(&heavy, &cohort.root(), &aggregate, &beacon, &threshold)
        .unwrap());
    // A heavy attestation of the same part naming another proposal of the window before is the
    // first of the contradicting pairs the sanction reads: the first appearance stands and the
    // second is refused, and the cement moves by neither (Consensus, "The sanction of a double
    // answer"). A part of another machine naming another name enters the cement whatever it
    // pledges; the pulse tests of the agreement carry that case.
    // The presence binds the name it attests (record 309): the second name is a presence of its own.
    let unrelated = montana_node::attest::Standing::of_the_window(
        &secret,
        12,
        &[0x43; 32],
        &branch.siblings,
        branch.position,
    )
    .unwrap()
    .heavy(&secret, beacon.id().unwrap(), [0x43; 32])
    .unwrap();
    assert_eq!(
        pulse.gather(&unrelated, &cohort.root(), &aggregate, &beacon, &threshold),
        Err(montana_node::NodeError::Refused {
            what: "a second heavy attestation of one part naming another name"
        })
    );
    assert_eq!(
        pulse.living(),
        1,
        "a second name under one part moved the cement"
    );
    pulse.advance(&machine, &beacon).unwrap();
    assert_eq!(pulse.round, 1);
    let next = pulse.beacon_of_this_round().unwrap();
    assert!(
        !pulse.can_advance(&next),
        "the previous answer does not authorize a new round"
    );
    assert!(pulse
        .gather(&heavy, &cohort.root(), &aggregate, &next, &threshold)
        .is_err());
    let light = pulse
        .answer(&secret, &next, &aggregate, &threshold)
        .unwrap()
        .unwrap();
    let light = LightAttestation::parse(&light).unwrap();
    let mut bad = light.clone();
    bad.signature[0] ^= 1;
    assert!(pulse
        .gather_light(&bad, &aggregate, &next, &threshold)
        .is_err());
    assert!(pulse.advance(&machine, &next).is_err());
    assert!(pulse
        .gather_light(&light, &aggregate, &next, &threshold)
        .unwrap());
    assert_eq!(pulse.living(), 1, "light answers cannot add cement");
    assert!(!pulse
        .gather_light(&light, &aggregate, &next, &threshold)
        .unwrap());
    pulse.advance(&machine, &next).unwrap();
    assert_eq!(pulse.round, 2);

    // A real signature from a proven member is still no substitute for checking the cement: a
    // beacon whose pair this machine did not recompute is answered by nothing of this machine and
    // closed on never. It moves the round, since a verified attestation answered it (Consensus, "The
    // round": "A round advances only on a valid attestation") — a machine with one heavy more than the
    // runner held would otherwise stand in its round for ever. This answers the forged version
    // through the lower signing primitive, exactly as a malicious member can do.
    let mut forged = pulse.beacon_of_this_round().unwrap();
    forged.cement_aggregate[0] ^= 1;
    let signed = pulse
        .standing
        .light(&secret, forged.id().unwrap(), previous)
        .unwrap();
    assert!(pulse
        .gather_light(&signed, &aggregate, &forged, &threshold)
        .unwrap());
    assert!(!pulse.can_advance(&forged), "a forged pair reconciled");
    assert!(pulse
        .answer(&secret, &forged, &aggregate, &threshold)
        .is_err());
    assert!(pulse.is_answered(&forged));
    pulse.advance(&machine, &forged).unwrap();
    assert_eq!(pulse.round, 3);
    assert_eq!(pulse.living(), 1);
    assert!(
        pulse.parts_of(&forged).is_none(),
        "a forged pair names parts of this machine's cement"
    );

    assert!(
        Pulse::open(
            &machine,
            &secret,
            (12, 1, 0),
            &branch,
            [0x43; 32],
            two_before,
            &electorate,
            &aggregate
        )
        .is_err(),
        "one machine must not adopt a competing predecessor at the same height"
    );
}

#[test]
fn a_late_heavy_enters_the_windows_cement_without_closing_another_round() {
    let directory = common::Scratch::named("late-heavy");
    let (machine, _) = Machine::start(&Configuration::at(&directory.0, "127.0.0.1:0")).unwrap();
    let secrets = [[0x73; 32], [0x74; 32]];
    let cohort = Cohort::of(&secrets.map(|secret| Cohort::half_of(&secret))).unwrap();
    machine.admits(cohort.count()).unwrap();
    let branch = cohort.branch_of(&secrets[0]).unwrap();
    let previous = [0x42; 32];
    let two_before = [0x41; 32];
    let aggregate = [0x37; 32];
    let threshold = mt_pulse::U256::from_be_bytes(&[0xff; 32]);
    let electorate =
        montana_node::certificate::Electorate::opening(cohort.root(), cohort.count(), 12).unwrap();
    let mut pulse = Pulse::open(
        &machine,
        &secrets[0],
        (12, 0, 0),
        &branch,
        previous,
        two_before,
        &electorate,
        &aggregate,
    )
    .unwrap();
    let beacon = pulse.beacon_of_this_round().unwrap();
    let points = montana_node::round::points_of_round(12, 0, 0).unwrap();
    machine
        .publish_at_the_point(&points[0], 12, &beacon.bytes().unwrap())
        .unwrap();
    let own = pulse
        .standing
        .heavy(&secrets[0], beacon.id().unwrap(), previous)
        .unwrap();
    pulse
        .gather(&own, &cohort.root(), &aggregate, &beacon, &threshold)
        .unwrap();
    pulse.advance(&machine, &beacon).unwrap();
    let next = pulse.beacon_of_this_round().unwrap();

    // The other machine finishes its proof after the runner has moved. Delivery
    // still belongs to the open window, and the proof is checked at its own round.
    let branch = cohort.branch_of(&secrets[1]).unwrap();
    let late = montana_node::attest::Standing::of_the_window(
        &secrets[1],
        12,
        &previous,
        &branch.siblings,
        branch.position,
    )
    .unwrap()
    .heavy(&secrets[1], beacon.id().unwrap(), previous)
    .unwrap();
    let bytes = late.bytes().unwrap();
    let cells = mt_wire::publish::cells_of(&points[0], 12, &bytes).unwrap();
    for cell in &cells {
        assert!(
            machine.take_deposit(&points[0], cell).unwrap(),
            "late delivery was dropped"
        );
    }
    let objects = machine.objects_at_the_point(&points[0], 12).unwrap();
    assert!(objects.iter().any(|object| object.starts_with(&bytes)));
    assert!(pulse
        .gather(&late, &cohort.root(), &aggregate, &beacon, &threshold)
        .unwrap());
    assert_eq!(pulse.living(), 2);
    assert_eq!(pulse.round, 1);
    assert!(
        !pulse.can_advance(&next),
        "a historical answer cannot close the current round"
    );
    assert!(!pulse
        .gather(&late, &cohort.root(), &aggregate, &beacon, &threshold)
        .unwrap());

    machine.enter_round(13, 0, 0).unwrap();
    assert!(
        !machine.take_deposit(&points[0], &cells[0]).unwrap(),
        "retention is not permission to write a past window"
    );
}
