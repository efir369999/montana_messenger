// The closing condition of the stage: a simulated population of machines closes windows at the
// derived count of rounds, with the cement recomputed by every one of them.
//
// Nothing here is a model of the rules — every machine runs the rules themselves. A machine draws
// its one-time key for the window from its own secret under the domain the set names, asks the
// eligibility of every round with it, publishes a heavy attestation the first time it is eligible,
// and every machine accumulates the cement from what it has seen. The window closes when the
// standing of the cement reaches the quorum by the comparison of the set.

use mt_pulse::close::quorum_reached;
use mt_pulse::fold::{Cement, Leaf};
use mt_pulse::{clears, retarget, U256};
use mt_suite::standing::weight_commit;

const STANDING: u64 = 1_000;

// The population the running tests of this file stand at: the count of admitted machines at which
// the crowd of a round is the admitted through the divisor exactly, which is where a window takes
// the derived count of rounds. Below it the floor of the crowd binds and a window closes sooner —
// the rule is one line and the two regimes are its two sides.
fn population() -> u64 {
    let floor = mt_genesis::scalar("round_floor").expect("the Decree names it");
    let divisor = mt_genesis::scalar("committee_divisor").expect("the Decree names it");
    floor * divisor
}

// The threshold the rule of the set gives at a population, on one chain. Nothing here is a share
// somebody chose: it reads the count of admitted machines through the Decree's own numbers.
fn threshold_at(admitted: u64) -> U256 {
    retarget::round_threshold(admitted, 1).expect("the Decree names what it reads")
}

// The share the set aimed a retarget at before the rule above replaced it: one machine in
// `committee_divisor`, whatever the population. It stands here because what it does at a small
// population is the whole reason the rule changed, and a measurement of that has to be able to
// build it.
fn the_share_a_retarget_aimed_at() -> U256 {
    let divisor = mt_genesis::scalar("committee_divisor").expect("the Decree names it");
    assert!(divisor.is_power_of_two());
    let exponent = 256 - divisor.trailing_zeros() as usize;
    let mut bytes = [0u8; 32];
    bytes[31 - exponent / 8] = 1 << (exponent % 8);
    U256::from_be_bytes(&bytes)
}

// A machine of the simulation holds what a window turns on: its secret, and the nullifier of its
// part, which is what the draw of a round reads. Its one-time key signs and draws nothing, so
// nothing here holds one — what a signature adds is checked where signatures are checked.
struct Machine {
    secret: [u8; 32],
    part: [u8; 32],
    attested: bool,
}

impl Machine {
    fn of(run: u64, index: u64, window: u64) -> Self {
        let mut secret = [0u8; 32];
        secret[..8].copy_from_slice(&run.to_le_bytes());
        secret[8..16].copy_from_slice(&index.to_le_bytes());
        secret[16] = 0xA7;
        // What the draw of a round reads is the nullifier of the machine's part, which is the value
        // the attestation of presence asserts; the one-time key of the window signs and draws
        // nothing, so this simulation derives none.
        let part = mt_derive::nullifier::part(&secret, window).expect("a half of the family");
        Machine {
            secret,
            part,
            attested: false,
        }
    }

    fn eligible(&self, aggregate: &[u8; 32], chain: u8, round: u32, threshold: &U256) -> bool {
        let value = mt_derive::pulse::round_eligibility(&self.part, aggregate, chain, round);
        clears(&value, threshold)
    }

    fn leaf(&self, window: u64) -> Leaf {
        Leaf {
            part_nullifier: self.part,
            commitment: weight_commit(
                STANDING,
                0,
                window,
                mt_suite::standing::Blind::of(self.secret, window),
            )
            .expect("bounded"),
        }
    }
}

// What a window did. **A round closes on an attestation and on nothing else**, so a round in which
// no machine of the whole living set is drawn does not pass slowly: the chain stands at it. A run
// therefore ends one of two ways, and a simulation that knew only the first would be counting
// rounds the protocol cannot reach.
#[derive(Debug, PartialEq, Eq)]
enum Window {
    Closed(u32),
    Stalled(u32),
}

// One window, run to its close: the count of rounds it took, or the round it stood at. What decides
// a round is eligibility and nothing else, so this carries no commitment — the cement is a property
// of the sum and is put to a population of its own below, where every leaf is a real commitment.
//
// **Every machine is asked, and not only the ones that have not attested.** A machine already in
// the cement answers a later round it is drawn for with a light attestation, and that answer closes
// the round exactly as a heavy one does; what the cement takes is the first appearance alone. So
// the crowd of a round is the whole living set through the threshold, while what enters the cement
// is that crowd less those already in it.
fn run_window(run: u64, population: u64, window: u64, threshold: &U256) -> Window {
    run_window_of(run, population, window, threshold, true)
}

// The same run with the stall made optional, so the wrong implementation this file replaced can be
// stood beside the right one instead of described. `honest` false is that wrong one: it advances a
// round no machine answered.
fn run_window_of(run: u64, population: u64, window: u64, threshold: &U256, honest: bool) -> Window {
    let mut machines: Vec<Machine> = (0..population)
        .map(|index| Machine::of(run, index, window))
        .collect();
    let aggregate =
        mt_derive::aggregate::aggregate(&[], window).expect("an empty set holds no repeat");
    let total = u128::from(population) * u128::from(STANDING);

    let mut cemented: u128 = 0;
    let mut round: u32 = 0;
    while !quorum_reached(cemented, total).expect("the Decree names the quorum") {
        let mut answered = false;
        for machine in machines.iter_mut() {
            if !machine.eligible(&aggregate, 0, round, threshold) {
                continue;
            }
            answered = true;
            if !machine.attested {
                machine.attested = true;
                cemented += u128::from(STANDING);
            }
        }
        if honest && !answered {
            return Window::Stalled(round);
        }
        round += 1;
        assert!(round < 20_000, "the window never closed");
    }
    Window::Closed(round)
}

// The count of rounds a window closed in, where a run that stands still is the failure of the test
// that asked for it.
fn closed_in(ran: Window) -> u32 {
    match ran {
        Window::Closed(rounds) => rounds,
        Window::Stalled(at) => panic!("the chain stood at round {at}: no machine was drawn for it"),
    }
}

#[test]
fn a_population_closes_its_windows_at_the_derived_count_of_rounds() {
    let target = mt_genesis::scalar("target_rounds").expect("the Decree names it");
    let population = population();
    let threshold = threshold_at(population);
    let runs = 3u64;

    let mut counts = Vec::new();
    for run in 0..runs {
        counts.push(u64::from(closed_in(run_window(
            run,
            population,
            1_000 + run,
            &threshold,
        ))));
    }

    let mean: u64 = counts.iter().sum::<u64>() / runs;
    // The target is an expectation and a window is a draw, so what stands here is the mean over
    // runs against the derived count, and every single run inside a band the derivation itself
    // gives: the expected uncovered share is (255/256)^R, and a run that closed at half or at
    // twice the target would mean the rate of eligibility is not the one the Decree names.
    assert!(
        mean * 10 > target * 8 && mean * 10 < target * 13,
        "the mean of {counts:?} is {mean}, and the derived count is {target}"
    );
    for count in &counts {
        assert!(
            *count > target / 2 && *count < target * 2,
            "a window closed at {count} rounds where the derived count is {target}"
        );
    }
}

// The two sides of the one rule: where the divisor binds a window takes the derived count, and
// where the floor of the crowd binds it takes fewer. Nothing is driven anywhere — the rule is read
// twice at two populations, and the windows answer.
#[test]
fn the_rule_gives_the_derived_count_where_the_divisor_binds_and_fewer_below_it() {
    let target = mt_genesis::scalar("target_rounds").expect("named");
    let at_the_boundary = population();
    let below = at_the_boundary / 8;

    let boundary = closed_in(run_window(
        100,
        at_the_boundary,
        2_000,
        &threshold_at(at_the_boundary),
    ));
    assert!(
        u64::from(boundary) * 2 > target && u64::from(boundary) < target * 2,
        "a window at the boundary closed at {boundary} where the derived count is {target}"
    );

    let sooner = closed_in(run_window(101, below, 2_100, &threshold_at(below)));
    assert!(
        sooner < boundary,
        "a smaller network did not close sooner: {sooner} against {boundary}"
    );
    // And neither of them stood still, which is the whole of what the rule buys.
    for admitted in [1u64, 2, 3, 49, 50, 51, 500] {
        let ran = run_window(
            200 + admitted,
            admitted,
            2_200 + admitted,
            &threshold_at(admitted),
        );
        assert!(
            matches!(ran, Window::Closed(_)),
            "a network of {admitted} stood still under the rule: {ran:?}"
        );
    }
}

#[test]
fn a_window_that_cemented_nothing_closes_nothing() {
    // The quorum is a comparison and not a count: a total that nobody answered for is not closed
    // by an empty cement, whatever the population.
    let total = u128::from(population()) * u128::from(STANDING);
    assert_eq!(quorum_reached(0, total), Ok(false));
    // And a cement that reached the share closes it exactly there.
    let (num, den) = mt_genesis::ratio("confirmation_quorum").expect("named");
    let exactly = total * u128::from(num) / u128::from(den);
    assert_eq!(quorum_reached(exactly + 1, total), Ok(true));
}

// The other half of the closing condition: the cement every verifier recomputes from what it
// holds. What decides it is the sum and the one-entry-per-part-nullifier rule, not the size of
// the population, so this runs over a set small enough that every leaf is a real commitment.
#[test]
fn every_verifier_recomputes_one_cement_from_what_it_holds() {
    let window = 3_000u64;
    let machines: Vec<Machine> = (0..24u64).map(|i| Machine::of(7, i, window)).collect();
    let published: Vec<Leaf> = machines.iter().map(|m| m.leaf(window)).collect();

    let mut forward = Cement::new();
    for leaf in &published {
        forward.add(leaf).expect("within the population");
    }
    let mut backward = Cement::new();
    for leaf in published.iter().rev() {
        backward.add(leaf).expect("within the population");
    }
    // A verifier that saw a delivery twice: the repetition is lawful and adds nothing.
    let mut doubled = Cement::new();
    for leaf in published.iter().chain(published.iter()) {
        doubled.add(leaf).expect("within the population");
    }
    // And one that saw them shuffled by a stride no machine chose.
    let mut shuffled = Cement::new();
    for step in [7usize, 5, 3, 1] {
        for leaf in published.iter().step_by(step) {
            shuffled.add(leaf).expect("within the population");
        }
    }

    assert_eq!(forward.count(), published.len());
    assert_eq!(doubled.count(), published.len());
    assert_eq!(shuffled.count(), published.len());
    assert_eq!(forward.state(), backward.state());
    assert_eq!(forward.state(), doubled.state());
    assert_eq!(forward.state(), shuffled.state());
    // A cement missing one attestation is a different cement: the sum is not a count.
    let mut short = Cement::new();
    for leaf in published.iter().skip(1) {
        short.add(leaf).expect("within the population");
    }
    assert_ne!(forward.state(), short.state());
}

// **A round nobody is drawn for stalls the chain, and that is why the share this set aimed a
// retarget at was replaced.** A round advances on a valid attestation and on nothing else, so a
// round in which no machine of the whole living set clears the threshold is not a slow round — the
// chain stands at it, no cement completes, and no window closes. The chance of such a round under a
// share of one in `committee_divisor` is that share against the whole population, and a window is
// `target_rounds` of them, so a population of a few hundred met a dead round inside its first
// window.
//
// This measures both halves: the share that was replaced stands still, and the rule that replaced
// it does not — at the same populations, in the same runs.
#[test]
fn the_share_that_was_replaced_stands_still_where_the_rule_that_replaced_it_does_not() {
    let replaced = the_share_a_retarget_aimed_at();
    let divisor = mt_genesis::scalar("committee_divisor").expect("the Decree names it");

    for admitted in [divisor / 4, divisor, divisor * 2] {
        let stood = run_window(11 + admitted, admitted, 4_000 + admitted, &replaced);
        assert!(
            matches!(stood, Window::Stalled(_)),
            "a population of {admitted} closed a window at the replaced share: {stood:?}"
        );
        let ran = run_window(
            11 + admitted,
            admitted,
            4_000 + admitted,
            &threshold_at(admitted),
        );
        assert!(
            matches!(ran, Window::Closed(_)),
            "a population of {admitted} stood still under the rule: {ran:?}"
        );
    }

    // **The named wrong simulation is the one this file carried**: a run that advances a round no
    // machine answered closes every window above at a count near the derived target, and reports a
    // network that works at a population where the chain stands still. Both the set and this file
    // held that assumption, which is why neither caught the other.
    for admitted in [divisor / 4, divisor] {
        let ran = run_window_of(11 + admitted, admitted, 4_000 + admitted, &replaced, false);
        assert!(
            matches!(ran, Window::Closed(_)),
            "the wrong simulation stood still too, so this vector separates nothing"
        );
    }
}

// And the rule holds where nothing else could reach: a network of one machine, which is where a
// cold start begins and where a share of one in the divisor leaves the chain standing at its first
// round with the probability that the one machine was not drawn.
#[test]
fn a_network_of_one_machine_closes_its_window_under_the_rule_and_stands_still_under_the_share() {
    assert!(matches!(
        run_window(9_001, 1, 6_000, &threshold_at(1)),
        Window::Closed(_)
    ));
    let replaced = the_share_a_retarget_aimed_at();
    let mut stood = 0;
    for run in 0..8u64 {
        if matches!(
            run_window(9_100 + run, 1, 6_100 + run, &replaced),
            Window::Stalled(_)
        ) {
            stood += 1;
        }
    }
    assert_eq!(
        stood, 8,
        "a single machine cleared a share of one in the divisor in some run, which it does once in that many"
    );
}
