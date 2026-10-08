// A check on an ALREADY FORMED phrase: not on the design, but on what came out. What is measured is what
// can be measured — reversibility, absence of repeats, uniformity of words and avalanche.
// Unpredictability is not proven by this: a generator with a known seed would give the same numbers.
// What is proven is the absence of breakage and of entropy loss on the way from the root to the phrase.

use std::collections::HashSet;

use mt_mnemonic::{
    entropy_to_mnemonic, generate_mnemonic, mnemonic_to_entropy, mnemonic_to_master_seed,
    word_index, MNEMONIC_WORD_COUNT, WORDLIST_SIZE,
};

const PHRASES: usize = 3_000;

fn born_phrases(n: usize) -> Vec<String> {
    (0..n)
        .map(|_| generate_mnemonic().expect("source alive").to_string())
        .collect()
}

fn word_histogram(phrases: &[String]) -> (Vec<u64>, u64) {
    let mut counts = vec![0u64; WORDLIST_SIZE];
    let mut total = 0u64;
    for p in phrases {
        // The last word carries the check byte and does not count toward uniformity.
        for w in p.split_whitespace().take(MNEMONIC_WORD_COUNT - 1) {
            counts[word_index(w).unwrap() as usize] += 1;
            total += 1;
        }
    }
    (counts, total)
}

#[test]
fn every_born_phrase_carries_the_full_width() {
    for phrase in born_phrases(200) {
        assert_eq!(phrase.split_whitespace().count(), MNEMONIC_WORD_COUNT);
        let entropy = mnemonic_to_entropy(&phrase).expect("own phrase is valid");
        assert_eq!(entropy_to_mnemonic(&entropy), phrase, "phrase does not decompose into its own root");
    }
}

#[test]
fn born_phrases_never_repeat() {
    let phrases = born_phrases(PHRASES);
    let unique: HashSet<&String> = phrases.iter().collect();
    assert_eq!(unique.len(), phrases.len(), "root repeat among {PHRASES}");

    let mut first = vec![0u32; WORDLIST_SIZE];
    for p in &phrases {
        first[word_index(p.split_whitespace().next().unwrap()).unwrap() as usize] += 1;
    }
    let top = *first.iter().max().unwrap();
    assert!(top < 12, "one first word occurred {top} times out of {PHRASES}");
}

#[test]
fn words_spread_across_the_whole_list() {
    let (counts, total) = word_histogram(&born_phrases(PHRASES));
    let expected = total as f64 / WORDLIST_SIZE as f64;
    let chi2: f64 = counts
        .iter()
        .map(|c| {
            let d = *c as f64 - expected;
            d * d / expected
        })
        .sum();
    let df = (WORDLIST_SIZE - 1) as f64;
    let sigma = (2.0 * df).sqrt();
    assert!(
        (chi2 - df).abs() < 5.0 * sigma,
        "chi-squared {chi2:.1} with expectation {df} ± {sigma:.1}"
    );
}

#[test]
fn min_entropy_per_word_stays_high() {
    // Estimate of the most common value (NIST SP 800-90B). On a finite sample it always
    // underestimates, so the threshold has a margin: the task is to catch a failure, not to confirm the ideal.
    let (counts, total) = word_histogram(&born_phrases(PHRASES));
    let p_max = *counts.iter().max().unwrap() as f64 / total as f64;
    let min_entropy = -p_max.log2();
    assert!(
        min_entropy > 8.0,
        "min-entropy per word {min_entropy:.2} bits of 11 — source is skewed"
    );
}

#[test]
fn one_flipped_bit_of_the_root_changes_half_the_seed() {
    let mut diffs = Vec::new();
    for trial in 0..6 {
        let phrase = generate_mnemonic().expect("source alive");
        let a = mnemonic_to_entropy(&phrase).unwrap();
        let mut b = a;
        b[trial % 32] ^= 1 << (trial % 8);

        let sa = mnemonic_to_master_seed(&entropy_to_mnemonic(&a)).unwrap();
        let sb = mnemonic_to_master_seed(&entropy_to_mnemonic(&b)).unwrap();
        let bits: u32 = sa.iter().zip(sb.iter()).map(|(x, y)| (x ^ y).count_ones()).sum();
        diffs.push(bits as f64 / (sa.len() as f64 * 8.0));
    }
    let mean = diffs.iter().sum::<f64>() / diffs.len() as f64;
    assert!((mean - 0.5).abs() < 0.06, "changed {mean:.4} bits instead of half");
}
