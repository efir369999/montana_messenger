// CNS-20 fixtures: only deposited bytes are changed; live_doing and all verifiers are real.
use super::{walk, Scratch};
use montana_node::{pulse::Cohort, Configuration, Machine, NodeError};
use mt_state::Layout;

pub const SECRETS: [[u8; 32]; 4] = [[0x81; 32], [0x82; 32], [0x83; 32], [0x84; 32]];

pub fn machine(label: &str) -> (Scratch, Machine, Cohort) {
    let at = Scratch::named(label);
    mt_store::Store::open(&at.0)
        .unwrap()
        .bear_secret(&SECRETS[0])
        .unwrap();
    let machine = Machine::start(&Configuration::at(&at.0, "127.0.0.1:0"))
        .unwrap()
        .0;
    let cohort = Cohort::of(&SECRETS.map(|secret| Cohort::half_of(&secret))).unwrap();
    (at, machine, cohort)
}

pub fn put(machine: &Machine, bytes: &[u8]) -> Result<(), NodeError> {
    for point in montana_node::round::points_of_round(0, 0, 0).unwrap() {
        machine.publish_at_the_point(&point, 0, bytes)?;
    }
    Ok(())
}

// Keep the valid heavy attestations but withhold every foreign closing pledge.
pub fn cut_closing_pledges(machine: &Machine, cohort: &Cohort) -> Result<(), NodeError> {
    let previous = montana_node::certificate::Predecessor::Genesis.id()?;
    let beacon = walk::opening(0, previous);
    let (heavies, _withheld, _) = walk::heavies(&SECRETS, cohort, 0, &beacon, previous);
    put(machine, &beacon.bytes().unwrap())?;
    for heavy in heavies {
        put(machine, &heavy.bytes().unwrap())?;
    }
    Ok(())
}

// Move the deposit owner to another window: the live pulse can collect retained data,
// but its round-zero publications no longer stand. This changes a real public input,
// not the verifier or the observation counters.
pub fn withhold(machine: &Machine) -> Result<(), NodeError> {
    machine.enter_round(1, 0, 0)
}
