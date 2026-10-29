// Two verifiers holding one set of heavy attestations in two arrival orders carry one cement: the
// aggregate sorts what it folds and the count is a count, so the beacon each publishes is one
// beacon. The named wrong implementation this refuses is the one this file once reproduced as an
// open finding — a cement that accumulated a running sum of blinded commitments, where two orders
// of arrival gave two states for one window and a verifier could not tell which was the window's.
//
// This scenario runs the real machines: each starts its transport on a loopback address of its own
// and holds a store of its own, exactly as two hosts would.

use montana_node::attest::Standing;
use montana_node::pulse::{Cohort, Pulse};
use montana_node::{Configuration, Machine};

mod common;
use common::Scratch;

#[test]
fn two_verifiers_reach_one_cement_from_two_arrival_orders() {
    let secrets = [[0x73u8; 32], [0x74u8; 32]];
    let window = 1_000;
    let parent = [0x22; 32];
    let two_before = [0x21; 32];
    let aggregate = [0x33; 32];
    let threshold = mt_pulse::U256::from_be_bytes(&[0xff; 32]);
    let cohort =
        Cohort::of(&secrets.map(|secret| Cohort::half_of(&secret))).expect("two admitted machines");
    let directory = Scratch::named("window-cement-order");
    let (machine, _) = Machine::start(&Configuration::at(&directory.0, "127.0.0.1:0"))
        .expect("a machine with a store of its own");
    let other_directory = Scratch::named("window-cement-order-other");
    let (other, _) = Machine::start(&Configuration::at(&other_directory.0, "127.0.0.1:0"))
        .expect("a second machine with a store of its own");
    let branch = cohort.branch_of(&secrets[0]).expect("membership");
    let electorate =
        montana_node::certificate::Electorate::opening(cohort.root(), cohort.count(), window)
            .expect("an opening electorate stands");
    let mut first = Pulse::open(
        &machine,
        &secrets[0],
        (window, 0, 0),
        &branch,
        parent,
        two_before,
        &electorate,
        &aggregate,
    )
    .expect("the first verifier opens the window");
    let mut second = Pulse::open(
        &other,
        &secrets[0],
        (window, 0, 0),
        &branch,
        parent,
        two_before,
        &electorate,
        &aggregate,
    )
    .expect("the second verifier opens the window");
    let beacon = first.beacon_of_this_round().expect("the opening beacon");
    assert_eq!(
        beacon,
        second.beacon_of_this_round().expect("the same opening")
    );
    assert_eq!(beacon.cement_count, 0);
    assert_eq!(
        beacon.cement_aggregate,
        mt_derive::aggregate::aggregate(&[], window).expect("the empty set"),
        "a window that cemented nothing carries the aggregate of the empty set"
    );
    let beacon_id = beacon.id().expect("an identifier");

    let heavies: Vec<_> = secrets
        .iter()
        .map(|secret| {
            let branch = cohort.branch_of(secret).expect("membership");
            Standing::of_the_window(secret, window, &parent, &branch.siblings, branch.position)
                .expect("a machine of the cohort proves its presence")
                .heavy(secret, beacon_id, parent)
                .expect("a heavy attestation stands")
        })
        .collect();

    // The first verifier sees them in one order and the second in the other.
    for heavy in &heavies {
        assert!(first
            .gather(heavy, &cohort.root(), &aggregate, &beacon, &threshold)
            .expect("a verified attestation enters"));
    }
    for heavy in heavies.iter().rev() {
        assert!(second
            .gather(heavy, &cohort.root(), &aggregate, &beacon, &threshold)
            .expect("a verified attestation enters"));
    }
    // A repeat adds nothing on either side and is lawful.
    assert!(!first
        .gather(&heavies[1], &cohort.root(), &aggregate, &beacon, &threshold)
        .expect("a repeat is answered"));
    assert_eq!(first.living(), 2);
    assert_eq!(second.living(), 2);

    let one = first.beacon_of_this_round().expect("a beacon");
    assert_eq!(one, second.beacon_of_this_round().expect("a beacon"));
    assert_eq!(one.cement_count, 2);
    let parts: Vec<[u8; 32]> = heavies.iter().map(|h| h.part_nullifier).collect();
    assert_eq!(
        one.cement_aggregate,
        mt_derive::aggregate::aggregate(&parts, window).expect("two distinct parts"),
        "the state a beacon carries is the aggregate over the parts with the window as context"
    );
    assert_ne!(one.cement_aggregate, beacon.cement_aggregate);

    // The close is a count against the count of the electorate, and it is the same count on both
    // sides: two of two reaches the share, one of two does not.
    assert!(first.closes(2, 2).expect("the Decree names the share"));
    assert!(!second.closes(1, 2).expect("the Decree names the share"));
    assert!(first
        .attempts_the_close(2)
        .expect("the Decree names the share"));
}
