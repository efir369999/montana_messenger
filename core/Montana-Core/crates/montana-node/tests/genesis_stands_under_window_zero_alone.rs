// The Genesis State Hash stands under window zero and under no other. Consensus, "Invariants of the
// TimeChain": "Every window but the first names its predecessor by the identifier of that
// predecessor's proposal, and the first names the Genesis State Hash; a proposal naming anything else
// belongs to another chain". Consensus, "The pulse and the close of a window": the opening cohort is
// the electorate "for the first two windows of a network", "which the proposal of window zero must
// carry". Canon, "The proposal that closes a window": "The first window of a network has no proposal
// before it, and its `previous` is the Genesis State Hash".
//
// **The world outside the rules, arranged by this test.** One machine and a cohort of itself, which
// is all a machine needs to open a chain of its own: its heavy attestation alone is the quorum of an
// electorate of one, its closing pledge alone decides, and its ticket clears a threshold of
// everything. The same machine, the same bytes but for the window, at window zero, at window one and
// at window three thousand; and the same machine handed the same cohort and told to live from a
// window past the first on a store that holds nothing.
//
// **The wrong implementations it refuses**, named before the assertions: the door of 4df361ca, under
// which the Genesis State Hash stands under any window a cohort opens at — there the certificate and
// the proposal of window three thousand both stand, and one machine holds a chain of its own at a
// height the network gives another meaning; a door that lets it stand under the first two windows,
// since the opening cohort does — there window one stands on it; the pulse of 4df361ca, which opens
// the cohort's electorate and the Genesis State Hash under whatever window it is told to live from —
// there the machine lives a window on nothing; and a door that refuses the Genesis State Hash under
// window zero too — there no network opens at all.

use montana_node::attest::Standing;
use montana_node::certificate::{
    decided_of, empty_census, verify_certificate, verify_proposal, Closure, Decided, Electorate,
    Held, Predecessor, Roots, Round,
};
use montana_node::pulse::{self, Cohort};
use montana_node::runner::Runner;
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::{Beacon, Proposal};
use mt_state::Layout;

mod common;
use common::Scratch;

const VERSION: u32 = 0x0001_0000;
const PATIENCE: u32 = 4;

const AFTER_ANOTHER: &str =
    "a certificate of a window other than the one after the proposal it finalizes";
const OF_ANOTHER_WINDOW: &str = "a proposal of another window than the one its certificate closes";

fn refused(what: &'static str) -> NodeError {
    NodeError::Refused { what }
}

// What one machine and a cohort of itself make of `window` standing on the Genesis State Hash, every
// object honestly proven and signed: the certificate of the window as the door judges it, the
// decision its final beacon carries, and the proposal of the window naming the Genesis State Hash
// with its judgment.
struct Opened {
    certificate: Result<Closure, NodeError>,
    decided: Decided,
    proposal: Proposal,
    judged: Result<(), NodeError>,
}

fn opened_at(window: u64) -> Opened {
    let secret = [0x11u8; 32];
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).expect("a cohort of one");
    let branch = cohort.branch_of(&secret).expect("its own leaf");
    let standing = Standing::of_the_window(&secret, window, &branch.siblings, branch.position)
        .expect("the machine proves its presence");
    let electorate = Electorate::opening(cohort.root(), cohort.count(), window)
        .expect("an opening electorate stands");
    let aggregate = mt_derive::aggregate::aggregate(&[], window).expect("the empty set");
    let genesis = mt_state::tables::genesis_state_hash().expect("the hash of the network");

    // Round zero stands on the Genesis State Hash; the machine answers it pledging the Genesis State
    // Hash as the name of the window before, and the beacon of round one carries its cement.
    let opening = Beacon {
        window,
        chain: 0,
        round: 0,
        previous: genesis,
        cement_aggregate: aggregate,
        cement_count: 0,
        cement_votes: 0,
    };
    let heavy = standing
        .heavy(&secret, opening.id().expect("an identifier"), genesis)
        .expect("a heavy attestation stands");
    let last = Beacon {
        window,
        chain: 0,
        round: 1,
        previous: opening.id().expect("an identifier"),
        cement_aggregate: mt_derive::aggregate::aggregate(&[heavy.part_nullifier], window)
            .expect("one part"),
        cement_count: 1,
        cement_votes: 0,
    };
    let light = standing
        .light(&secret, last.id().expect("an identifier"), genesis)
        .expect("a light attestation stands");
    let pledge = standing
        .pledge(&secret, 0, genesis, 0)
        .expect("a pledge stands");
    let heavies = [heavy];
    let lights = [light];
    let rounds = [
        Round {
            beacon: &opening,
            heavy: &heavies,
            light: &[],
            ballots: &[],
        },
        Round {
            beacon: &last,
            heavy: &[],
            light: &lights,
            ballots: &[],
        },
    ];
    let certificate = verify_certificate(
        window,
        &electorate,
        Predecessor::Genesis,
        &aggregate,
        1,
        &rounds,
        std::slice::from_ref(&pledge),
    );
    let decided = Decided::of_beacon(&last, &electorate).expect("a beacon at the quorum");

    // The proposal of the window, naming the Genesis State Hash, under the key and the ticket of the
    // runner the window draws, signed by that key.
    let draw = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);
    let runner = Runner::of_the_window(
        &secret,
        window,
        &branch.siblings,
        branch.position,
        &aggregate,
        &draw,
    )
    .expect("the ticket proves")
    .expect("a threshold of everything draws the machine");
    let roots = Roots {
        note_root: [0x33; 32],
        nullifier_root: [0x44; 32],
        record_root: [0x55; 32],
        machine_root: [0x66; 32],
        admitted_root: cohort.root().bytes(),
        credited_root: mt_proof::credited::empty_root().bytes(),
        operations_root: [0x88; 32],
        roll: [0xBB; 32],
        admitted_count: cohort.count(),
        census: empty_census().expect("the Decree names the census"),
    };
    let mut proposal = Proposal {
        window,
        protocol_version: VERSION,
        previous: genesis,
        final_beacon: decided.final_beacon,
        note_root: roots.note_root,
        nullifier_root: roots.nullifier_root,
        record_root: roots.record_root,
        machine_root: roots.machine_root,
        admitted_root: roots.admitted_root,
        credited_root: roots.credited_root,
        operations_root: roots.operations_root,
        roll: roots.roll,
        admitted_count: roots.admitted_count,
        cement_aggregate: decided.cement_aggregate,
        cement_count: decided.cement_count,
        census: roots.census.clone(),
        suite_id: mt_net::SUITE,
        runner_pubkey: runner.key.as_bytes().to_vec(),
        ticket_proof: runner.ticket_proof.clone(),
        signature: vec![0u8; mt_codec::size::SIGNATURE],
    };
    let seed = mt_derive::pulse::runner_key_seed(&secret, window);
    let mut held = [0u8; mt_suite::sign::SEED_BYTES];
    held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (_, key) = mt_suite::sign::keypair_from_seed(&held);
    proposal.signature = mt_suite::sign::sign(&key, &proposal.signed_scope().expect("scope"))
        .expect("the runner owns its key")
        .as_bytes()
        .to_vec();
    let judged = verify_proposal(
        &proposal,
        &Held {
            predecessor: Predecessor::Genesis,
            decided: &decided,
            electorate: &electorate,
            aggregate_two_before: &aggregate,
            draw_threshold: &draw,
            implemented_major: 1,
        },
        &roots,
    );
    // The runner itself writes this proposal where the Genesis State Hash stands under the window,
    // and refuses to write it where it does not.
    let written = runner.propose(VERSION, Predecessor::Genesis, &roots, &decided);
    if window == 0 {
        assert_eq!(
            written.expect("the runner proposes window zero").id(),
            proposal.id(),
            "the proposal of this test is not the one the runner writes"
        );
        let closure = certificate.as_ref().expect("window zero closes");
        assert_eq!(
            decided_of(
                &decided.final_beacon,
                &genesis,
                &rounds,
                closure,
                &electorate
            ),
            Ok(decided)
        );
    } else {
        assert_eq!(
            written.map(|_| ()),
            Err(refused(
                "a proposal of another window than the one this runner drew"
            ))
        );
    }
    Opened {
        certificate,
        decided,
        proposal,
        judged,
    }
}

#[test]
fn the_genesis_state_hash_stands_under_window_zero_and_under_no_other() {
    // Accepted: window zero, its certificate deciding the Genesis State Hash and its proposal naming
    // it.
    let zero = opened_at(0);
    let closure = zero
        .certificate
        .expect("the certificate of window zero stands");
    assert_eq!(closure.cement_count, 1);
    assert_eq!(zero.judged, Ok(()));
    assert_eq!(zero.decided.window, 0);

    // Refused: the same, at window one, which the opening cohort electorates but which stands on the
    // proposal of window zero.
    let one = opened_at(1);
    assert_eq!(one.certificate, Err(refused(AFTER_ANOTHER)));
    assert_eq!(one.judged, Err(refused(OF_ANOTHER_WINDOW)));

    // Refused: the same, at window three thousand — a chain of one machine at a height of the
    // network, every object of it honestly proven and signed.
    let far = opened_at(3_000);
    assert_eq!(far.proposal.previous, zero.proposal.previous);
    assert_eq!(far.certificate, Err(refused(AFTER_ANOTHER)));
    assert_eq!(far.judged, Err(refused(OF_ANOTHER_WINDOW)));
}

// A machine told to live from a window past the first, holding nothing and handed a cohort of itself,
// lives none: it refuses before it stands at any round, and its head, its closed window, its kept
// proposals and its record of the agreement stand as they stood.
#[test]
fn a_machine_holding_nothing_opens_no_window_but_the_first() {
    let at = Scratch::named("genesis-alone");
    let (machine, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    assert!(born);
    let cohort = Cohort::of(&[machine.naming_half().expect("a half")]).expect("a cohort of itself");
    for (from, what) in [
        (
            5,
            "a window past the first two of a network standing on no proposal two before",
        ),
        (
            1,
            "a window past the first of a network standing on no proposal before it",
        ),
    ] {
        assert_eq!(
            pulse::live(&machine, &cohort, from, 1, PATIENCE).map(|_| ()),
            Err(refused(what)),
            "a machine holding nothing lived window {from}"
        );
        assert_eq!(machine.head().expect("the store answers"), None);
        assert_eq!(machine.closed_window().expect("the store answers"), None);
        assert!(machine
            .proposal_of(from)
            .expect("the store answers")
            .is_none());
        assert!(machine
            .agreement_of(from)
            .expect("the store answers")
            .is_none());
        assert_eq!(machine.round_of_the_machine(), None);
    }
}
