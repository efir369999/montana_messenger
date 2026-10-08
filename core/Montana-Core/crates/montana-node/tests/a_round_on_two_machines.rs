// A round on two machines, over the wire they reach each other by: the runner publishes a beacon at
// the points of the round, the other machine collects it, answers it with an attestation of its
// own, and the runner gathers that answer into the cement of the window.
//
// **Nothing is arranged between them.** The points are a function of the window, the chain, the
// round and the index alone, so both arrive at the same sixteen bytes without exchanging them; the
// beacon and the attestation cross as deposits and collections the wire already carries; and every
// object is verified as a far side verifies it — the draw natively, the signature under the key it
// carries, and the proof of presence against the root of admitted machines.
//
// **A beacon is larger than a cell and crosses anyway.** Six thousand one hundred and eighty-nine
// bytes against one thousand two hundred and thirty-two, so it travels as a delivery: cut into
// blocks, every block riding one cell, every cell sealed under the two keys of the point it stands
// at — which both machines derive from the point and neither is told. The far side collects the
// cells and reads the beacon back whole.

use montana_node::pulse::{self, Branch, Pulse};
use montana_node::{round, Configuration, Machine};
use mt_state::layout::Confirmation;
use mt_state::Layout;

mod common;
use common::Scratch;

const WINDOW: u64 = 1_000;
const CHAIN: u8 = 0;
const STANDING: u64 = 1_000;

// The tree of admitted machines over a cohort, and the branch each machine walks. Both come of the
// one construction the tree carries: the halves alone, in their ascending order, which every
// machine reaches without asking anybody.
fn cohort(
    secrets: &[[u8; 32]],
) -> (
    mt_proof::poseidon::Digest,
    Vec<(Vec<mt_proof::poseidon::Digest>, u64)>,
) {
    let halves: Vec<[u8; 32]> = secrets
        .iter()
        .map(montana_node::pulse::Cohort::half_of)
        .collect();
    let held = montana_node::pulse::Cohort::of(&halves).expect("the cohort stands in the tree");
    let branches = secrets
        .iter()
        .map(|secret| {
            let branch = held.branch_of(secret).expect("its own leaf");
            (branch.siblings, branch.position)
        })
        .collect();
    (held.root(), branches)
}

#[test]
fn a_beacon_crosses_to_the_other_machine_and_its_answer_comes_back() {
    let far_at = Scratch::named("pulse-runner");
    let near_at = Scratch::named("pulse-attester");
    let secrets = [[0xA1u8; 32], [0xB2u8; 32]];
    let (root, branches) = cohort(&secrets);
    let aggregate = [0x33u8; 32];
    // A threshold of everything: what this scenario is about is the crossing, and a draw that
    // admitted nobody would be testing the draw instead.
    let everything = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);

    // The runner: it holds the window, so it stands at the points of it and of the round it enters.
    let (runner, _) =
        Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0")).expect("the runner starts");
    let mut running = Pulse::open(
        &runner,
        &secrets[0],
        (WINDOW, CHAIN, 0),
        &Branch {
            siblings: branches[0].0.clone(),
            position: branches[0].1,
            standing: STANDING,
        },
        [0x55u8; 32],
    )
    .expect("the runner enters the window");

    let line = runner.acquaintance().expect("an acquaintance is written");
    let waiting = std::thread::spawn(move || {
        runner.answer_one().expect("a link is answered");
        runner
    });

    // The attester reaches it and carries the link, exactly as a machine started with an
    // acquaintance does.
    let (attester, _) =
        Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0")).expect("the attester starts");
    let mut link = attester.reach(&line).expect("the runner answers");
    let mut answering = Pulse::open(
        &attester,
        &secrets[1],
        (WINDOW, CHAIN, 0),
        &Branch {
            siblings: branches[1].0.clone(),
            position: branches[1].1,
            standing: STANDING,
        },
        [0x55u8; 32],
    )
    .expect("the attester enters the window");
    let runner = waiting.join().expect("the thread stands");

    // The runner stands at the points of its round, which is what a beacon and the attestations
    // answering it stand at. That much crosses: the attester collects from a point of the round and
    // is answered, without either machine being told where those sixteen bytes are.
    let beacon = running
        .beacon_of_this_round()
        .expect("a beacon of this round stands");
    let beacon_bytes = beacon.bytes().expect("a beacon of its own width");
    let points = round::points_of_round(WINDOW, CHAIN, 0).expect("the Decree names the replicas");
    assert!(
        pulse::take_from(&mut link, &points[0], WINDOW, beacon_bytes.len())
            .expect("a collection is answered")
            .is_none(),
        "a point of a round nothing was deposited at answered with something"
    );

    // The runner publishes the beacon at the first point of its round. A beacon does not fit a
    // cell, so what crosses is a delivery of cells and not one deposit.
    assert!(
        beacon_bytes.len() > mt_wire::cell_bytes().expect("the Decree names it"),
        "a beacon that fitted a cell would take no delivery, and this would measure nothing"
    );
    let cells = pulse::publish_at(&mut link, &points[0], WINDOW, &beacon_bytes)
        .expect("the beacon stands at the point");
    assert!(cells > 1, "an object larger than a cell rode in one cell");

    // And the far side takes it back whole, having been told neither the point nor the keys: it
    // computes the point from the window, the chain, the round and the index, and both keys from
    // the point.
    let taken = pulse::take_from(&mut link, &points[0], WINDOW, beacon_bytes.len())
        .expect("a collection is answered")
        .expect("the delivery is whole");
    assert_eq!(
        taken, beacon_bytes,
        "what stood at the point is not the beacon that was published"
    );
    let read = mt_state::layout::Beacon::parse(&taken).expect("a beacon reads back from the wire");
    assert_eq!(
        read.id().expect("an identifier"),
        beacon.id().expect("an identifier"),
        "a beacon that crossed the wire is another beacon"
    );

    // A point of another round holds nothing: the keys of one point open at that point alone.
    let elsewhere =
        round::points_of_round(WINDOW, CHAIN, 1).expect("the Decree names the replicas");
    assert!(
        pulse::take_from(&mut link, &elsewhere[0], WINDOW, beacon_bytes.len())
            .expect("a collection is answered")
            .is_none(),
        "a point of another round answered with this round's beacon"
    );

    // The pulse itself stands whatever carries it: the attester answers the beacon the runner made
    // — heavily, since this is its first answer of the window.
    let answer = answering
        .answer(&secrets[1], &beacon, &aggregate, &everything)
        .expect("the attester answers")
        .expect("a threshold of everything draws it");
    let answered = Confirmation::parse(&answer).expect("an attestation reads back");

    // And the runner gathers it: verified as any far side verifies it, and folded into the cement
    // at its first appearance.
    assert!(
        running
            .gather(&answered, &root, &aggregate, 0, &everything)
            .expect("the attestation verifies"),
        "a first appearance did not enter the cement"
    );
    assert_eq!(
        running.living(),
        1,
        "the cement names the machine that answered"
    );
    // A second appearance of one part-nullifier adds nothing and is lawful.
    assert!(!running
        .gather(&answered, &root, &aggregate, 0, &everything)
        .expect("the attestation verifies"));

    // Whether the runner attempts to close is read off two public counts and nothing else: how many
    // part-nullifiers its cement holds, and how many machines the tree of the admitted carries. One
    // of two is below the share, so no attempt is made and no proof is built for a statement known
    // to be false; one of one is at it, so the attempt is made and the circuit decides.
    assert!(
        !running
            .attempts_the_close(2)
            .expect("the Decree names the share"),
        "a runner attempted a close it knows cannot stand"
    );
    assert!(
        running
            .attempts_the_close(1)
            .expect("the Decree names the share"),
        "a runner holding every admitted machine did not attempt the close"
    );

    // The named wrong implementation this refuses: a holder that keeps the points of every window
    // it ever answered. A sender may deposit into the current window, wait for it to turn and
    // repeat, and every rule is kept at every step — so a holder with no moment of release holds
    // one window's worth of cells per window forever. A window turning drops what belonged to the
    // windows before the last one. And the second wrong implementation, the one two hosts stood
    // still on (06.10.2026): a holder that drops its window the moment the next one opens leaves a
    // machine one window behind nothing to collect, so the last window stays one window longer.
    let of_this_round = round::points_of_round(WINDOW, CHAIN, 0).expect("named");
    assert!(
        !runner.standing_at(&of_this_round[0]).is_empty(),
        "what was deposited this window does not stand"
    );
    runner
        .enter_round(WINDOW + 1, CHAIN, 0)
        .expect("the machine stands in the next window");
    let of_the_next = round::points_of_round(WINDOW + 1, CHAIN, 0).expect("named");
    // The cell is cut afresh for the point and the window it is deposited into. A cell carries the
    // point and the window of the delivery it belongs to, so one cut for a point of a window
    // already past is refused whole at a point of the window now open — a delivery of another
    // place is not the head of a delivery here — and depositing it would measure that refusal
    // rather than the release this asserts.
    let of_the_next_cells = mt_wire::publish::cells_of(&of_the_next[0], WINDOW + 1, &beacon_bytes)
        .expect("a beacon cuts");
    runner
        .take_deposit(&of_the_next[0], &of_the_next_cells[0])
        .expect("a deposit of the current window");
    assert!(
        !runner.standing_at(&of_this_round[0]).is_empty(),
        "the window just past was dropped, so a machine one window behind has nothing to collect"
    );
    assert!(
        !runner.standing_at(&of_the_next[0]).is_empty(),
        "the deposit of the current window did not stand"
    );
    runner
        .enter_round(WINDOW + 2, CHAIN, 0)
        .expect("the machine stands in the window after the next");
    let of_the_one_after = round::points_of_round(WINDOW + 2, CHAIN, 0).expect("named");
    let of_the_one_after_cells =
        mt_wire::publish::cells_of(&of_the_one_after[0], WINDOW + 2, &beacon_bytes)
            .expect("a beacon cuts");
    runner
        .take_deposit(&of_the_one_after[0], &of_the_one_after_cells[0])
        .expect("a deposit of the current window");
    assert!(
        runner.standing_at(&of_this_round[0]).is_empty(),
        "a point two windows past still holds what was deposited in it"
    );
    assert!(
        !runner.standing_at(&of_the_next[0]).is_empty(),
        "the window just past was dropped with the one before it"
    );

    // The round moves on: the beacon of this one becomes the predecessor of the next, and the
    // machine stands at the points of the round it moves into.
    running
        .advance(&runner, &beacon)
        .expect("the round advances");
    assert_eq!(runner.round_of_the_machine(), Some((WINDOW, CHAIN, 1)));
    let next = running
        .beacon_of_this_round()
        .expect("the next beacon stands");
    assert_eq!(next.round, 1);
    assert_eq!(
        next.previous,
        beacon.id().expect("an identifier"),
        "a beacon links to its predecessor by the identifier a verifier recomputes"
    );
}
