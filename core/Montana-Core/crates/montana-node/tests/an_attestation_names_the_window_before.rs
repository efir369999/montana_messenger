// What an attestation attests, at the first round and at every round after it.
//
// **One signature serves two duties** — the pulse of its round and, once, the cement of the window
// before — so an attestation carries exactly two identifiers: the beacon of its round, which moves
// with the rounds, and the identifier of the window before, which does not. The first is a fact
// about the round; the second is a fact about the window, and a machine that let it move would
// confirm, from the first round on, the beacon it had just come from instead of the window whose
// cement its answer is entering.
//
// **The named wrong implementation is the one this tree carried**: a single field standing for
// both, advanced with the rounds because a beacon links to its predecessor by hash. At round nought
// the two values coincide, so every vector that ran one round agreed with it. This one runs two.

use montana_node::pulse::{Branch, Cohort, Pulse};
use montana_node::{Configuration, Machine};
use mt_state::layout::{Confirmation, LightAttestation};
use mt_state::Layout;

mod common;
use common::Scratch;

const WINDOW: u64 = 2_600;
const CHAIN: u8 = 0;
const STANDING: u64 = 1_000;
// The window before, as this vector hands it in. No beacon of this window can equal it, which is
// what lets the assertions below tell the two apart by value.
const OF_THE_WINDOW_BEFORE: [u8; 32] = [0x5A; 32];

#[test]
fn every_attestation_of_a_window_names_the_window_before_and_never_the_beacon_it_came_from() {
    let at = Scratch::named("attests-the-window-before");
    let secret = [0xC3u8; 32];
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).expect("a cohort of one stands");
    let branch = cohort.branch_of(&secret).expect("its own leaf");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let mut pulse = Pulse::open(
        &machine,
        &secret,
        (WINDOW, CHAIN, 0),
        &Branch {
            siblings: branch.siblings,
            position: branch.position,
            standing: STANDING,
        },
        OF_THE_WINDOW_BEFORE,
    )
    .expect("the machine enters the window");

    // A threshold of everything: what this vector is about is what an answer names, and a draw that
    // admitted nobody would be measuring the draw instead.
    let everything = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);
    let aggregate = [0x11u8; 32];

    // Round nought. Its beacon stands on the window before, and so does the answer — at this round
    // the two duties name one value, which is why one round proves nothing here.
    let first = pulse
        .beacon_of_this_round()
        .expect("a beacon of this round");
    let first_id = first.id().expect("a beacon carries its identifier");
    assert_eq!(first.previous, OF_THE_WINDOW_BEFORE);
    let heavy = pulse
        .answer(&secret, &first, &aggregate, &everything)
        .expect("an answer is drawn")
        .expect("the machine was eligible");
    let heavy = Confirmation::parse(&heavy).expect("an answer of its own width");
    assert!(heavy.attested.contains(&OF_THE_WINDOW_BEFORE));
    assert!(heavy.attested.contains(&first_id));

    // Round one. The beacon moves on to link to the beacon before it — that is the beacon's own
    // rule — while what the answer attests beside it must not move with it.
    pulse.advance(&machine, &first).expect("the machine moves");
    let second = pulse
        .beacon_of_this_round()
        .expect("a beacon of this round");
    let second_id = second.id().expect("a beacon carries its identifier");
    assert_eq!(
        second.previous, first_id,
        "a beacon of round one linked to something other than the beacon of round nought"
    );
    let light = pulse
        .answer(&secret, &second, &aggregate, &everything)
        .expect("an answer is drawn")
        .expect("the machine was eligible");
    let light = LightAttestation::parse(&light).expect("an answer of its own width");
    assert!(
        light.attested.contains(&second_id),
        "an answer of round one did not attest the beacon of round one"
    );
    assert!(
        light.attested.contains(&OF_THE_WINDOW_BEFORE),
        "an answer of round one did not attest the window before"
    );
    assert!(
        !light.attested.contains(&first_id),
        "an answer of round one attested the beacon it came from, which closes no window"
    );
}
