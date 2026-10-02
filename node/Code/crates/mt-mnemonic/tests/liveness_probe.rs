// Замер живости источников на ЭТОЙ машине. Пороги правила живости выведены из этих чисел.
use mt_mnemonic::{survey, MIN_LIVE_SOURCES};

#[test]
fn liveness_probe() {
    let facts = survey();
    let mut alive = 0;
    for f in &facts {
        let share = if f.samples > 0 { 100 * f.max_repeat / f.samples } else { 100 };
        println!(
            "{:<24} замеров {:>4}  различных {:>4}  самое частое {:>3}%  жив {}",
            f.name, f.samples, f.distinct_chunks, share, f.alive
        );
        if f.alive { alive += 1; }
    }
    println!("живых {alive} из {}, требуется {MIN_LIVE_SOURCES}", facts.len());
    assert!(alive >= MIN_LIVE_SOURCES, "на этой машине живых источников меньше порога");
}
