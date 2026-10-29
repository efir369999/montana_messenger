// A machine holding one heavy attestation more than a beacon at the quorum cannot reconcile that
// beacon and closes on a later one. Consensus, "The agreement on what a window decided": "A machine
// holding one heavy attestation more than a beacon at the quorum cannot reconcile that beacon and
// closes on a later one"; "The round": "A round advances only on a valid attestation; no count, no
// measure and no clock closes it"; Canon, "The round of a chain, in integers": "a beacon whose state
// is not that pair is refused". So the three rules of one beacon are kept apart here: a verified
// attestation answering it moves the round; its pair, where it is not the pair this machine
// recomputed, is answered by nothing of this machine and closed on by nothing; and the next beacon of
// this machine's own version carries the fuller cement and is the one it can close on.
//
// **The wrong implementations it refuses**, named before the assertions: one reconciling a beacon by
// its count alone, which would close on the three-part beacon while holding four parts and write a
// proposal whose cement is not that beacon's pair; and one refusing to advance past a beacon whose
// pair it cannot reconcile, under which a machine with one heavy more stands in its round for ever —
// two of the six machines of the run of 2026-10-16 stood so in round zero (AGREEMENT.md, section 6).

use montana_node::attest::Standing;
use montana_node::pulse::{Cohort, Pulse};
use montana_node::{Configuration, Machine};
use mt_state::layout::Beacon;
use mt_state::Layout;

mod common;
use common::Scratch;

const WINDOW: u64 = 2_800;
const CHAIN: u8 = 0;

#[test]
fn a_machine_holding_one_heavy_more_advances_past_the_quorum_beacon_and_closes_on_its_own() {
    let at = Scratch::named("fuller-cement");
    let secrets = [[0x61u8; 32], [0x62u8; 32], [0x63u8; 32], [0x64u8; 32]];
    let cohort = Cohort::of(&secrets.map(|secret| Cohort::half_of(&secret)))
        .expect("four machines stand in the tree");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    machine
        .admits(cohort.count())
        .expect("the count of the window");
    let aggregate = [0x37u8; 32];
    let previous = [0x42u8; 32];
    let two_before = [0x41u8; 32];
    let everything = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);
    let electorate =
        montana_node::certificate::Electorate::opening(cohort.root(), cohort.count(), WINDOW)
            .expect("an opening electorate stands");
    let branch = cohort.branch_of(&secrets[0]).expect("its own leaf");
    let mut pulse = Pulse::open(
        &machine,
        &secrets[0],
        (WINDOW, CHAIN, 0),
        &branch,
        previous,
        two_before,
        &electorate,
        &aggregate,
    )
    .expect("the window opens");

    // Round nought: every machine of the four answers the opening beacon heavily, and this machine
    // gathers all four, its own among them.
    let first = pulse.beacon_of_this_round().expect("the opening beacon");
    let first_id = first.id().expect("an identifier");
    let standings: Vec<Standing> = secrets
        .iter()
        .map(|secret| {
            let branch = cohort.branch_of(secret).expect("its own leaf");
            Standing::of_the_window(secret, WINDOW, &previous, &branch.siblings, branch.position)
                .expect("a machine of the cohort proves its presence")
        })
        .collect();
    let heavies: Vec<_> = secrets
        .iter()
        .zip(&standings)
        .map(|(secret, standing)| {
            standing
                .heavy(secret, first_id, previous)
                .expect("a heavy attestation stands")
        })
        .collect();
    let mut parts: Vec<[u8; 32]> = Vec::new();
    for heavy in &heavies {
        assert!(pulse
            .gather(heavy, &cohort.root(), &aggregate, &first, &everything)
            .expect("a verified attestation enters"));
        parts.push(heavy.part_nullifier);
    }
    assert_eq!(pulse.living(), 4);
    pulse.advance(&machine, &first).expect("the round moves");
    assert_eq!(pulse.round, 1);

    // Round one, another runner's version: it gathered three of the four when it published, so its
    // beacon carries three parts — the quorum of four — and the second machine answers it lightly.
    let mut three = parts[..3].to_vec();
    three.sort_unstable();
    let quorum_beacon = Beacon {
        window: WINDOW,
        chain: CHAIN,
        round: 1,
        previous: first_id,
        cement_aggregate: mt_derive::aggregate::aggregate(&three, WINDOW).expect("three parts"),
        cement_count: 3,
        cement_votes: 0,
    };
    assert_eq!(
        mt_pulse::close::closes(3, 4, 0),
        Ok(true),
        "three of four is the quorum"
    );
    let light = standings[1]
        .light(
            &secrets[1],
            quorum_beacon.id().expect("an identifier"),
            previous,
        )
        .expect("a light attestation stands");
    assert!(pulse
        .gather_light(&light, &aggregate, &quorum_beacon, &everything)
        .expect("a verified light attestation answers the beacon"));

    // This machine holds four: the three-part pair is not its pair. It answers that beacon with
    // nothing and closes on it never — but a verified attestation answered it, so the round moves.
    assert_eq!(
        pulse.answer(&secrets[0], &quorum_beacon, &aggregate, &everything),
        Err(montana_node::NodeError::UnreconciledCement),
        "a beacon whose pair is not the one this machine recomputed was answered"
    );
    assert!(
        !pulse.can_advance(&quorum_beacon),
        "a beacon reconciled by its count alone"
    );
    assert!(pulse.is_answered(&quorum_beacon));
    pulse
        .advance(&machine, &quorum_beacon)
        .expect("a round advances on a valid attestation, whatever pair its beacon carries");
    assert_eq!(pulse.round, 2);

    // Round two, this machine's own version: its beacon carries the four it holds, it answers it,
    // and that is the beacon at the quorum it can close on.
    let own = pulse
        .beacon_of_this_round()
        .expect("the beacon of this round");
    assert_eq!(own.cement_count, 4);
    assert_eq!(own.previous, quorum_beacon.id().expect("an identifier"));
    let answer = pulse
        .answer(&secrets[0], &own, &aggregate, &everything)
        .expect("its own beacon is its own pair")
        .expect("drawn");
    // The first answer of this pulse is heavy, since its own heavy above was made beside it; its
    // part already stands in the cement, so the repetition adds nothing and is lawful — and it is
    // the verified answer to this beacon all the same.
    let answer = mt_state::layout::Confirmation::parse(&answer)
        .expect("the first answer of a pulse is heavy");
    assert!(
        !pulse
            .gather(&answer, &cohort.root(), &aggregate, &own, &everything)
            .expect("its own answer verifies"),
        "a repeated part entered the cement"
    );
    assert!(
        pulse.can_advance(&own),
        "the later beacon is the one to close on"
    );
    assert_eq!(mt_pulse::close::closes(4, 4, 0), Ok(true));
    assert_eq!(
        pulse.parts_of(&own).map(|parts| parts.len()),
        Some(4),
        "the parts of the final beacon are the four this machine holds"
    );
    assert_eq!(pulse.parts_of(&quorum_beacon), None);
}
