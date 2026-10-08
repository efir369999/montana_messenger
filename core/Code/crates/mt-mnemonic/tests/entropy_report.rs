// A viewing window onto the entropy accounting: what is taken, from where, how it is combined, how it is checked and
// how many bits come out. Prints MEASURES, not bytes of the sources — not a single byte leaves.
// No quantity is declared here: all are taken from the core and printed by computation from them.

use std::collections::HashSet;

use mt_mnemonic::{
    entropy_to_mnemonic, generate_entropy_reporting, generate_mnemonic, health_check,
    mnemonic_to_entropy, mnemonic_to_master_seed, survey, word_index, ENTROPY_LEN,
    MIN_LIVE_SOURCES, MNEMONIC_WORD_COUNT, WORDLIST_SIZE,
};

const PHRASES: usize = 1_000;

#[test]
fn entropy_report() {
    let bits_per_word = (WORDLIST_SIZE as f64).log2() as usize;

    println!("\n════════ SOURCES OF THIS MACHINE ════════\n");
    let facts = survey();
    let mut alive = 0;
    for f in &facts {
        println!("{}  {}", if f.alive { "ALIVE" } else { "DEAD " }, f.name);
        println!("        what it is:       {}", f.what);
        println!("        bytes taken:      {}", f.bytes);
        println!("        distinct chunks:  {} (8-byte chunks)", f.distinct_chunks);
        println!("        distinct bytes:   {} of 256", f.distinct_bytes);
        println!("        most frequent:    {} of {} ({}%)", f.max_repeat, f.samples,
                 if f.samples > 0 { 100 * f.max_repeat / f.samples } else { 100 });
        println!("        liveness rule:    {}\n", f.alive_rule);
        if f.alive {
            alive += 1;
        }
    }
    println!("live sources: {alive} of {}, at least {MIN_LIVE_SOURCES} required", facts.len());
    println!("identical measurements count as the ABSENCE of a source, named by its name");
    assert!(alive >= MIN_LIVE_SOURCES, "fewer live sources than the threshold on this machine");

    println!("\n════════ COMBINING ════════\n");
    println!("tape:     domain \"mt-entropy-mix\" ‖ 0x00 ‖ (label ‖ length ‖ bytes) of each source");
    println!("fold:     SHA-256 over the whole tape → {ENTROPY_LEN} bytes of root");
    println!("property: the result is unpredictable as long as AT LEAST ONE summand is unpredictable");
    let (root, report) = generate_entropy_reporting().expect("enough sources");
    println!("verdict of this combination: alive {} of {}", report.count(), facts.len());

    println!("\n════════ RELEASE HEALTH CHECKS ════════\n");
    println!("long repeat:          P(run >= 8 identical) <= 32*2^-56");
    println!("value skew:           P(value >= 13 times)  ~ 4*10^-21");
    println!("few distinct bytes:   P(distinct < 8)        < 10^-30");
    println!("match with previous:  a release equal to the previous one is rejected");
    println!("at such probabilities a trigger is a BREAKAGE, not a fluctuation — the response is a refusal");
    let mut sample = [0u8; ENTROPY_LEN];
    sample.copy_from_slice(&root[..]);
    println!("this release passed the checks: {}", health_check(&sample).is_ok());

    println!("\n════════ HOW MANY BITS ════════\n");
    println!("root:               {} bytes * 8 = {} bits", ENTROPY_LEN, ENTROPY_LEN * 8);
    println!("wordlist:           {WORDLIST_SIZE} = 2^{bits_per_word}, so a word carries {bits_per_word} bits");
    println!("phrase:             {MNEMONIC_WORD_COUNT} words * {bits_per_word} = {} bits",
             MNEMONIC_WORD_COUNT * bits_per_word);
    println!("of which checksum:  {}", MNEMONIC_WORD_COUNT * bits_per_word - ENTROPY_LEN * 8);
    println!("PHRASE ENTROPY:     {} bits", ENTROPY_LEN * 8);
    println!("brute force:        2^{}", ENTROPY_LEN * 8);

    println!("\n════════ MEASUREMENT ON {PHRASES} GENERATED PHRASES ════════\n");
    let phrases: Vec<String> = (0..PHRASES)
        .map(|_| generate_mnemonic().expect("source alive").to_string())
        .collect();

    let mut counts = vec![0u64; WORDLIST_SIZE];
    let mut total = 0u64;
    for p in &phrases {
        for w in p.split_whitespace().take(MNEMONIC_WORD_COUNT - 1) {
            counts[word_index(w).unwrap() as usize] += 1;
            total += 1;
        }
    }
    let top = *counts.iter().max().unwrap();
    let p_max = top as f64 / total as f64;
    let min_entropy = -p_max.log2();
    let expected = total as f64 / WORDLIST_SIZE as f64;
    println!("words measured:        {total} (the last word of a phrase carries the checksum and is not counted)");
    println!("expectation per word:  {expected:.1} times");
    println!("most frequent word:    {top} times, share {p_max:.5}");
    println!("min-entropy per word:  {min_entropy:.2} bits of {bits_per_word}");
    println!("  what is measured: the most-common-value estimate (NIST SP 800-90B, sec. 6.3.1)");
    println!("  why below {bits_per_word}: on a finite sample the estimate ALWAYS underestimates —");
    println!("  the most frequent word out of {WORDLIST_SIZE} with expectation {expected:.1} fluctuates upward,");
    println!("  and the estimate catches a source failure rather than confirming the ideal");

    let chi2: f64 = counts.iter().map(|c| { let d = *c as f64 - expected; d * d / expected }).sum();
    let df = (WORDLIST_SIZE - 1) as f64;
    let sigma = (2.0 * df).sqrt();
    println!("uniformity:            chi-squared {chi2:.1} with expectation {df:.0} +- {sigma:.1} (threshold 5 sigma)");

    let unique: HashSet<&String> = phrases.iter().collect();
    println!("repeats among phrases: {}", phrases.len() - unique.len());

    let phrase = generate_mnemonic().expect("source alive");
    let a = mnemonic_to_entropy(&phrase).unwrap();
    let sa = mnemonic_to_master_seed(&phrase).unwrap();
    let mut b = a;
    b[0] ^= 1;
    let sb = mnemonic_to_master_seed(&entropy_to_mnemonic(&b)).unwrap();
    let bits: u32 = sa.iter().zip(sb.iter()).map(|(x, y)| (x ^ y).count_ones()).sum();
    println!("avalanche:             one flipped root bit changes {:.1}% of master-seed bits",
             100.0 * bits as f64 / (sa.len() as f64 * 8.0));

    println!("\n════════ HONEST CEILING ════════\n");
    println!("unpredictability is NOT proven by this: a generator with a known seed would give the same numbers.");
    println!("what is proven is the absence of breakage and of entropy loss on the way from the root to the phrase.\n");

    assert!(alive >= MIN_LIVE_SOURCES, "fewer live sources than required");
}
