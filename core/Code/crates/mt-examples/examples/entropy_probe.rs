// Measures what can be measured: the source output and what our layer does with it.
// This does not prove unpredictability — it proves the absence of breakage and the absence of
// entropy loss on the way from block to identity.

use std::collections::HashSet;

use mt_codec::domain;
use mt_crypto::{keypair_from_seed, sha256_raw};
use mt_mnemonic::{
    entropy_to_mnemonic, generate_entropy, mldsa_seed_for_role, mnemonic_to_entropy,
    mnemonic_to_master_seed,
};
use mt_state::derive_account_id;

const BLOCKS: usize = 100_000;

fn main() {
    println!("=== 1. Source: {BLOCKS} blocks of 32 bytes ===");
    let mut counts = [0u64; 256];
    let mut seen: HashSet<[u8; 32]> = HashSet::with_capacity(BLOCKS);
    let mut dup = 0usize;
    let mut max_run = 1usize;
    let mut bit_ones = 0u64;

    for _ in 0..BLOCKS {
        let b = generate_entropy().expect("source is healthy");
        for (i, byte) in b.iter().enumerate() {
            counts[*byte as usize] += 1;
            bit_ones += byte.count_ones() as u64;
            if i > 0 && *byte == b[i - 1] {
                // runs within a block are measured by health_check; only a coarse check here
            }
        }
        let mut run = 1usize;
        for i in 1..32 {
            run = if b[i] == b[i - 1] { run + 1 } else { 1 };
            max_run = max_run.max(run);
        }
        if !seen.insert(*b) {
            dup += 1;
        }
    }

    let total: u64 = counts.iter().sum();
    let expected = total as f64 / 256.0;
    let chi2: f64 = counts
        .iter()
        .map(|c| {
            let d = *c as f64 - expected;
            d * d / expected
        })
        .sum();
    let pmax = *counts.iter().max().unwrap() as f64 / total as f64;
    let min_entropy_per_byte = -pmax.log2();
    let ones_share = bit_ones as f64 / (total as f64 * 8.0);

    println!("total bytes:                {total}");
    println!("chi-square (255 d.o.f.):    {chi2:.1}   expected 255 ± 22.6");
    println!("share of one bits:          {ones_share:.6}   expected 0.5");
    println!("most frequent value:        p = {pmax:.6}");
    println!("min-entropy (MCV, SP 800-90B): {min_entropy_per_byte:.4} bits/byte of 8");
    println!("   → per block:              {:.1} bits of 256", min_entropy_per_byte * 32.0);
    println!("repeated blocks:            {dup} of {BLOCKS}");
    println!("longest run in a block:     {max_run} bytes (rejection threshold 8)");

    println!();
    println!("=== 2. Our layer loses no entropy: 20 000 blocks through words ===");
    let mut roundtrip_ok = 0usize;
    let mut words_seen: HashSet<String> = HashSet::new();
    let mut idx_counts = [0u64; 2048];
    for _ in 0..20_000 {
        let e = generate_entropy().expect("source is healthy");
        let m = entropy_to_mnemonic(&e);
        let back = mnemonic_to_entropy(&m).expect("our own phrase is valid");
        if back == *e {
            roundtrip_ok += 1;
        }
        for w in m.split_whitespace() {
            idx_counts[mt_mnemonic::word_index(w).expect("word from the list") as usize] += 1;
        }
        words_seen.insert(m);
    }
    let idx_total: u64 = idx_counts.iter().sum();
    let idx_expected = idx_total as f64 / 2048.0;
    let idx_chi2: f64 = idx_counts
        .iter()
        .map(|c| {
            let d = *c as f64 - idx_expected;
            d * d / idx_expected
        })
        .sum();
    println!("exact recovery:            {roundtrip_ok} of 20000");
    println!("distinct phrases:          {} of 20000", words_seen.len());
    println!("chi-square over 2048 words: {idx_chi2:.1}   expected 2047 ± 64");

    println!();
    println!("=== 3. Avalanche: one entropy bit → key and address ===");
    let mut seed_diff = Vec::new();
    let mut id_diff = Vec::new();
    for trial in 0..8 {
        let mut a = *generate_entropy().expect("source is healthy");
        let mut b = a;
        b[trial % 32] ^= 1 << (trial % 8);

        let ma = mnemonic_to_master_seed(&entropy_to_mnemonic(&a)).unwrap();
        let mb = mnemonic_to_master_seed(&entropy_to_mnemonic(&b)).unwrap();
        seed_diff.push(bit_diff(&ma, &mb) as f64 / (ma.len() as f64 * 8.0));

        let ka = keypair_from_seed(&mldsa_seed_for_role(&ma, domain::ACCOUNT_KEY)).unwrap().0;
        let kb = keypair_from_seed(&mldsa_seed_for_role(&mb, domain::ACCOUNT_KEY)).unwrap().0;
        let ia = derive_account_id(1, ka.as_bytes());
        let ib = derive_account_id(1, kb.as_bytes());
        id_diff.push(bit_diff(&ia, &ib) as f64 / (ia.len() as f64 * 8.0));
        a.iter_mut().for_each(|x| *x = 0);
    }
    println!(
        "flipped master seed bits:   {:.4}   expected 0.5",
        seed_diff.iter().sum::<f64>() / seed_diff.len() as f64
    );
    println!(
        "flipped address bits:       {:.4}   expected 0.5",
        id_diff.iter().sum::<f64>() / id_diff.len() as f64
    );

    println!();
    println!("=== 4. Mixing survives a dead system source ===");
    let dead = [0u8; 32];
    let mut mixed = HashSet::new();
    for i in 0..1000u32 {
        let extra = sha256_raw(&i.to_le_bytes());
        mixed.insert(*mt_mnemonic::combine_entropy(&dead, &extra));
    }
    println!("distinct roots with a zero system block: {} of 1000", mixed.len());
}

fn bit_diff(a: &[u8], b: &[u8]) -> u32 {
    a.iter().zip(b).map(|(x, y)| (x ^ y).count_ones()).sum()
}
