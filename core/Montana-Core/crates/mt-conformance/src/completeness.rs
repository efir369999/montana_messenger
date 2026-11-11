// The completeness of the denominator itself, and the one part of the gate that lives only in the
// build graph: it reads the recorder of domains, which the harness turns on for its build script
// and for nothing a node compiles.

pub fn check_every_domain_is_exercised() -> Result<(), String> {
    let taken: std::collections::BTreeSet<&str> =
        mt_codec::witness::taken().into_iter().collect();
    let awaiting: std::collections::BTreeSet<&str> =
        DOMAINS_AWAITING_A_VECTOR.iter().map(|(d, _)| *d).collect();
    let mut silent: Vec<&str> = Vec::new();
    let mut earned: Vec<&str> = Vec::new();
    for domain in mt_codec::domain::REGISTRY {
        let name = domain.as_str();
        match (taken.contains(name), awaiting.contains(name)) {
            (false, false) => silent.push(name),
            (true, true) => earned.push(name),
            _ => {}
        }
    }
    if !earned.is_empty() {
        return Err(format!(
            "the set and the code diverge — {} domains named as awaiting a vector are exercised: {}; a mark is dropped the day it is earned",
            earned.len(),
            earned.join(", ")
        ));
    }
    if !silent.is_empty() {
        return Err(format!(
            "the set and the code diverge — {} domains of the registry no run takes a preimage under, and none is named as awaiting one: {}; a rule nothing compares is a rule two implementations read two ways",
            silent.len(),
            silent.join(", ")
        ));
    }
    Ok(())
}

