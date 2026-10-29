// Measurement of source liveness on THIS machine. The thresholds of the liveness rule are derived from these numbers.
use mt_mnemonic::{survey, MIN_LIVE_SOURCES};

#[test]
fn liveness_probe() {
    let facts = survey();
    let mut alive = 0;
    for f in &facts {
        let share = if f.samples > 0 {
            100 * f.max_repeat / f.samples
        } else {
            100
        };
        println!(
            "{:<24} measurements {:>4}  distinct {:>4}  most frequent {:>3}%  alive {}",
            f.name, f.samples, f.distinct_chunks, share, f.alive
        );
        if f.alive {
            alive += 1;
        }
    }
    println!(
        "alive {alive} of {}, required {MIN_LIVE_SOURCES}",
        facts.len()
    );
    assert!(
        alive >= MIN_LIVE_SOURCES,
        "fewer live sources than the threshold on this machine"
    );
}
