use sha2::{Sha256, Digest};
use std::io::Write;
use std::time::{Duration, Instant};

fn measure_one_minute() -> u64 {
    let mut hash = [0u8; 32];
    let duration = Duration::from_secs(60);
    let start = Instant::now();
    let mut count: u64 = 0;

    loop {
        for _ in 0..10_000 {
            hash = Sha256::digest(&hash).into();
            count += 1;
        }
        if start.elapsed() >= duration {
            break;
        }
    }

    std::hint::black_box(hash);
    count
}

fn main() {
    println!("Montana D_0 calibration benchmark");
    println!("Single-threaded SHA-256 iteration, 3 runs of 60 seconds each");
    println!();

    let mut results = Vec::new();
    for i in 1..=3 {
        print!("Run {}/3 (~60s)... ", i);
        std::io::stdout().flush().ok();
        let count = measure_one_minute();
        println!("{} hashes ({:.2} MH/s)", count, count as f64 / 60_000_000.0);
        results.push(count);
    }

    let total: u64 = results.iter().sum();
    let avg = total / results.len() as u64;
    let min = *results.iter().min().unwrap();
    let max = *results.iter().max().unwrap();

    println!();
    println!("=== Results ===");
    println!("Min:     {} ({:.2} MH/s)", min, min as f64 / 60_000_000.0);
    println!("Max:     {} ({:.2} MH/s)", max, max as f64 / 60_000_000.0);
    println!("Average: {} ({:.2} MH/s)", avg, avg as f64 / 60_000_000.0);
    println!();
    println!("Recommended D_0 = {}", avg);
}
