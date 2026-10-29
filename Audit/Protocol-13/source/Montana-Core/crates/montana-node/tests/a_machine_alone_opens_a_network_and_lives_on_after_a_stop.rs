// The cold start, and the start of a machine that already holds a chain. Consensus, "The cold
// start": a chain "finalizes its own chain while the committee consists of itself alone"; "The
// TimeChain": "Every window but the first names its predecessor by the identifier of that
// predecessor's proposal, and the first names the Genesis State Hash; a proposal naming anything
// else belongs to another chain."
//
// **What is measured.** A machine started on an empty directory, with a cohort of itself, opens a
// network at its first window and finalizes it alone; and a machine that lived windows of a chain,
// stopped and started again on its store, lives the next window on that chain rather than on a new
// one.
//
// **The wrong implementations it refuses**, named before the assertions: a pulse that enters its
// first window of a run with nothing to stand on — the window after a restart names the Genesis
// State Hash rather than the proposal of the window before, and the head stays where the stop left
// it; a pulse that opens a window past one it holds no proposal of — it would live that window on
// the Genesis State Hash rather than refuse it; and a cold start whose first window names anything
// but the Genesis State Hash, or whose machine alone finalizes nothing.

use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine, NodeError};

mod common;
use common::Scratch;

// How many askings a machine spends at one round before giving it up: of the operator alone.
const PATIENCE: u32 = 40_000;

fn alone(machine: &Machine) -> Cohort {
    Cohort::of(&[machine.naming_half().expect("a half of the machine")]).expect("a cohort of one")
}

#[test]
fn a_machine_holding_nothing_opens_the_network_at_its_first_window_alone() {
    let at = Scratch::named("cold-start");
    let (machine, born) = Machine::start(&Configuration::at(&at.0, "127.0.0.1:0"))
        .expect("the machine starts on an empty directory");
    assert!(born, "a machine holding nothing draws its secret");
    assert_eq!(machine.head().expect("the store answers"), None);

    let cohort = alone(&machine);
    let lived = pulse::live(&machine, &cohort, 0, 3, PATIENCE).expect("the machine lives alone");
    assert_eq!(lived.len(), 3);
    let genesis = mt_state::tables::genesis_state_hash().expect("the hash of the network");
    let mut previous = genesis;
    for (at, one) in lived.iter().enumerate() {
        assert_eq!(one.window, at as u64);
        assert_eq!(one.living, 1, "a committee of the machine alone");
        let held = machine
            .proposal_of(one.window)
            .expect("the store answers")
            .expect("a proposal kept for every window lived");
        assert_eq!(
            held.previous, previous,
            "window {} links elsewhere",
            one.window
        );
        previous = one.proposal;
    }
    // The first two windows are final, each by the cement of the window after it.
    assert_eq!(machine.head().expect("the store answers"), Some(1));
}

#[test]
fn a_machine_started_again_on_its_store_lives_on_its_own_chain() {
    // Window zero, the one window a cohort opens a network at (Consensus, "Invariants of the
    // TimeChain"): a machine holding nothing refuses to open one anywhere else.
    const FROM: u64 = 0;
    let at = Scratch::named("lives-on");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = alone(&machine);
    let first = pulse::live(&machine, &cohort, FROM, 3, PATIENCE).expect("the first run lives");
    assert_eq!(first.len(), 3);
    assert_eq!(machine.head().expect("the store answers"), Some(FROM + 1));
    drop(machine);

    let (again, born) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts again");
    assert!(!born, "a restart drew a second secret");

    // Refused: a window past one it holds no proposal of.
    assert_eq!(
        pulse::live(&again, &cohort, FROM + 7, 1, PATIENCE).map(|_| ()),
        Err(NodeError::Refused {
            what: "a window after one this machine holds no proposal of"
        })
    );

    let second = pulse::live(&again, &cohort, FROM + 3, 2, PATIENCE)
        .expect("the restarted machine lives on its chain");
    assert_eq!(second.len(), 2);
    let next = again
        .proposal_of(FROM + 3)
        .expect("the store answers")
        .expect("the proposal of the first window after the stop");
    assert_eq!(
        next.previous, first[2].proposal,
        "the window after the stop links to something else than the proposal before it"
    );
    assert_ne!(
        next.previous,
        mt_state::tables::genesis_state_hash().expect("the hash of the network"),
        "a restart began a new chain"
    );
    // The window lived last before the stop is final now, by the cement of the first one after it,
    // and the head moved past it.
    assert_eq!(again.head().expect("the store answers"), Some(FROM + 3));
}
