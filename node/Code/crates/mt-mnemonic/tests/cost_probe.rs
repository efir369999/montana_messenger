// Сколько стоит полный сбор источников и сколько — вывод корня из фразы. Числа нужны, чтобы
// решать, что можно звать на открытии приложения, а что только при рождении личности.
use std::time::Instant;
use mt_mnemonic::{generate_entropy, mnemonic_to_entropy, mnemonic_to_master_seed};

#[test]
fn cost_probe() {
    let t = Instant::now();
    let _ = generate_entropy().expect("сбор");
    println!("полный сбор семи источников: {:?}", t.elapsed());

    let phrase = std::iter::repeat("abandon").take(23).collect::<Vec<_>>().join(" ") + " art";
    let t = Instant::now();
    let _ = mnemonic_to_entropy(&phrase).expect("энтропия");
    println!("фраза -> энтропия:          {:?}", t.elapsed());

    let t = Instant::now();
    let _ = mnemonic_to_master_seed(&phrase).expect("корень");
    println!("фраза -> корень (PBKDF2):   {:?}", t.elapsed());
}
