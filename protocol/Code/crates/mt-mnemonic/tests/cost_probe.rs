// What a full gather of the sources costs and what deriving the root from a phrase costs. The numbers are needed to
// decide what may be called on app open and what only at identity birth.
use mt_mnemonic::{generate_entropy, mnemonic_to_entropy, mnemonic_to_master_seed};
use std::time::Instant;

#[test]
fn cost_probe() {
    let t = Instant::now();
    let _ = generate_entropy().expect("gather");
    println!("full gather of seven sources: {:?}", t.elapsed());

    let phrase = std::iter::repeat("abandon")
        .take(23)
        .collect::<Vec<_>>()
        .join(" ")
        + " art";
    let t = Instant::now();
    let _ = mnemonic_to_entropy(&phrase).expect("entropy");
    println!("phrase -> entropy:          {:?}", t.elapsed());

    let t = Instant::now();
    let _ = mnemonic_to_master_seed(&phrase).expect("root");
    println!("phrase -> root (PBKDF2):   {:?}", t.elapsed());
}
