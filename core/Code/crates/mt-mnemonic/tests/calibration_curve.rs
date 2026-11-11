// The noise-versus-work curve of THIS machine: how many distinct samples and how large the mode
// share are for a fixed amount of work, from 1024 units upward. Read with --nocapture.
use mt_mnemonic::{clock_step_ns, jitter_probe};

#[test]
fn calibration_curve() {
    println!("clock step {} ns", clock_step_ns());
    let mut units = 1_024u64;
    while units <= (1u64 << 22) {
        let (distinct, mode, avg) = jitter_probe(units, 256);
        println!("units {units:>8}  avg {avg:>8} ns  ({:>6} steps)  distinct {distinct:>3}  mode {mode:>3}%", avg / clock_step_ns().max(1));
        units *= 2;
    }
}
