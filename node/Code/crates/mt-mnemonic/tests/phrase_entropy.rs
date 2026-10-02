// Проверка по УЖЕ СФОРМИРОВАННОЙ фразе: не по замыслу, а по тому, что вышло. Меряется то,
// что поддаётся измерению — обратимость, отсутствие повторов, равномерность слов и лавина.
// Непредсказуемость этим не доказывается: генератор с известным зерном дал бы те же числа.
// Доказывается отсутствие поломки и отсутствие потери энтропии по дороге от корня к фразе.

use std::collections::HashSet;

use mt_mnemonic::{
    entropy_to_mnemonic, generate_mnemonic, mnemonic_to_entropy, mnemonic_to_master_seed,
    word_index, MNEMONIC_WORD_COUNT, WORDLIST_SIZE,
};

const PHRASES: usize = 3_000;

fn born_phrases(n: usize) -> Vec<String> {
    (0..n)
        .map(|_| generate_mnemonic().expect("источник жив").to_string())
        .collect()
}

fn word_histogram(phrases: &[String]) -> (Vec<u64>, u64) {
    let mut counts = vec![0u64; WORDLIST_SIZE];
    let mut total = 0u64;
    for p in phrases {
        // Последнее слово несёт контрольный байт и в счёт равномерности не идёт.
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
        let entropy = mnemonic_to_entropy(&phrase).expect("своя фраза валидна");
        assert_eq!(entropy_to_mnemonic(&entropy), phrase, "фраза не раскладывается в свой корень");
    }
}

#[test]
fn born_phrases_never_repeat() {
    let phrases = born_phrases(PHRASES);
    let unique: HashSet<&String> = phrases.iter().collect();
    assert_eq!(unique.len(), phrases.len(), "повтор корня среди {PHRASES}");

    let mut first = vec![0u32; WORDLIST_SIZE];
    for p in &phrases {
        first[word_index(p.split_whitespace().next().unwrap()).unwrap() as usize] += 1;
    }
    let top = *first.iter().max().unwrap();
    assert!(top < 12, "одно первое слово встретилось {top} раз из {PHRASES}");
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
        "хи-квадрат {chi2:.1} при ожидании {df} ± {sigma:.1}"
    );
}

#[test]
fn min_entropy_per_word_stays_high() {
    // Оценка наиболее частого значения (NIST SP 800-90B). На конечной выборке она всегда
    // занижает, поэтому порог с запасом: задача — поймать провал, а не подтвердить идеал.
    let (counts, total) = word_histogram(&born_phrases(PHRASES));
    let p_max = *counts.iter().max().unwrap() as f64 / total as f64;
    let min_entropy = -p_max.log2();
    assert!(
        min_entropy > 8.0,
        "min-entropy на слово {min_entropy:.2} бит из 11 — источник перекошен"
    );
}

#[test]
fn one_flipped_bit_of_the_root_changes_half_the_seed() {
    let mut diffs = Vec::new();
    for trial in 0..6 {
        let phrase = generate_mnemonic().expect("источник жив");
        let a = mnemonic_to_entropy(&phrase).unwrap();
        let mut b = a;
        b[trial % 32] ^= 1 << (trial % 8);

        let sa = mnemonic_to_master_seed(&entropy_to_mnemonic(&a)).unwrap();
        let sb = mnemonic_to_master_seed(&entropy_to_mnemonic(&b)).unwrap();
        let bits: u32 = sa.iter().zip(sb.iter()).map(|(x, y)| (x ^ y).count_ones()).sum();
        diffs.push(bits as f64 / (sa.len() as f64 * 8.0));
    }
    let mean = diffs.iter().sum::<f64>() / diffs.len() as f64;
    assert!((mean - 0.5).abs() < 0.06, "изменилось {mean:.4} бит вместо половины");
}
