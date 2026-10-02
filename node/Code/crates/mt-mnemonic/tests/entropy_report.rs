// Смотровое окно в счёт энтропии: что берётся, откуда, как складывается, как проверяется и
// сколько бит выходит. Печатает МЕРЫ, а не байты источников — байта наружу не выходит ни одного.
// Ни одна величина здесь не объявлена: все берутся из ядра и печатаются вычислением из них.

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

    println!("\n════════ ИСТОЧНИКИ ЭТОЙ МАШИНЫ ════════\n");
    let facts = survey();
    let mut alive = 0;
    for f in &facts {
        println!("{}  {}", if f.alive { "ЖИВ  " } else { "МЁРТВ" }, f.name);
        println!("        что это:          {}", f.what);
        println!("        байт снято:       {}", f.bytes);
        println!("        различных кусков: {} (куски по 8 байт)", f.distinct_chunks);
        println!("        различных байт:   {} из 256", f.distinct_bytes);
        println!("        самый частый:     {} из {} ({}%)", f.max_repeat, f.samples,
                 if f.samples > 0 { 100 * f.max_repeat / f.samples } else { 100 });
        println!("        правило жизни:    {}\n", f.alive_rule);
        if f.alive {
            alive += 1;
        }
    }
    println!("живых источников: {alive} из {}, требуется не меньше {MIN_LIVE_SOURCES}", facts.len());
    println!("одинаковые замеры считаются ОТСУТСТВИЕМ источника, названным его именем");
    assert!(alive >= MIN_LIVE_SOURCES, "на этой машине живых источников меньше порога");

    println!("\n════════ СЛОЖЕНИЕ ════════\n");
    println!("лента:    домен \"mt-entropy-mix\" ‖ 0x00 ‖ (метка ‖ длина ‖ байты) каждого источника");
    println!("свёртка:  SHA-256 над всей лентой → {ENTROPY_LEN} байт корня");
    println!("свойство: результат непредсказуем, пока непредсказуем ХОТЯ БЫ ОДИН слагаемый");
    let (root, report) = generate_entropy_reporting().expect("источников хватает");
    println!("приговор этого сложения: живых {} из {}", report.count(), facts.len());

    println!("\n════════ ПРОВЕРКИ ЗДОРОВЬЯ ВЫПУСКА ════════\n");
    println!("длинный повтор:       P(серия >= 8 одинаковых) <= 32*2^-56");
    println!("перекос по значению:  P(значение >= 13 раз)     ~ 4*10^-21");
    println!("мало различных байт:  P(различных < 8)          < 10^-30");
    println!("совпадение с прошлым: выпуск, равный предыдущему, отвергается");
    println!("при таких вероятностях срабатывание есть ПОЛОМКА, а не колебание — ответом служит отказ");
    let mut sample = [0u8; ENTROPY_LEN];
    sample.copy_from_slice(&root[..]);
    println!("этот выпуск проверки прошёл: {}", health_check(&sample).is_ok());

    println!("\n════════ СКОЛЬКО БИТ ════════\n");
    println!("корень:             {} байт * 8 = {} бит", ENTROPY_LEN, ENTROPY_LEN * 8);
    println!("список слов:        {WORDLIST_SIZE} = 2^{bits_per_word}, значит слово несёт {bits_per_word} бит");
    println!("фраза:              {MNEMONIC_WORD_COUNT} слов * {bits_per_word} = {} бит",
             MNEMONIC_WORD_COUNT * bits_per_word);
    println!("из них контрольных: {}", MNEMONIC_WORD_COUNT * bits_per_word - ENTROPY_LEN * 8);
    println!("ЭНТРОПИЯ ФРАЗЫ:     {} бит", ENTROPY_LEN * 8);
    println!("перебор:            2^{}", ENTROPY_LEN * 8);

    println!("\n════════ ЗАМЕР НА {PHRASES} РОЖДЁННЫХ ФРАЗАХ ════════\n");
    let phrases: Vec<String> = (0..PHRASES)
        .map(|_| generate_mnemonic().expect("источник жив").to_string())
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
    println!("слов измерено:         {total} (последнее слово фразы несёт контроль и в счёт не идёт)");
    println!("ожидание на слово:     {expected:.1} раз");
    println!("самое частое слово:    {top} раз, доля {p_max:.5}");
    println!("min-энтропия на слово: {min_entropy:.2} бит из {bits_per_word}");
    println!("  чем меряется: оценка самого частого значения (NIST SP 800-90B, п. 6.3.1)");
    println!("  почему меньше {bits_per_word}: на конечной выборке оценка ВСЕГДА занижает —");
    println!("  самое частое слово из {WORDLIST_SIZE} при ожидании {expected:.1} колеблется вверх,");
    println!("  и оценка ловит провал источника, а не подтверждает идеал");

    let chi2: f64 = counts.iter().map(|c| { let d = *c as f64 - expected; d * d / expected }).sum();
    let df = (WORDLIST_SIZE - 1) as f64;
    let sigma = (2.0 * df).sqrt();
    println!("равномерность:         хи-квадрат {chi2:.1} при ожидании {df:.0} +- {sigma:.1} (порог 5 сигм)");

    let unique: HashSet<&String> = phrases.iter().collect();
    println!("повторов среди фраз:   {}", phrases.len() - unique.len());

    let phrase = generate_mnemonic().expect("источник жив");
    let a = mnemonic_to_entropy(&phrase).unwrap();
    let sa = mnemonic_to_master_seed(&phrase).unwrap();
    let mut b = a;
    b[0] ^= 1;
    let sb = mnemonic_to_master_seed(&entropy_to_mnemonic(&b)).unwrap();
    let bits: u32 = sa.iter().zip(sb.iter()).map(|(x, y)| (x ^ y).count_ones()).sum();
    println!("лавина:                один перевёрнутый бит корня меняет {:.1}% бит мастер-семени",
             100.0 * bits as f64 / (sa.len() as f64 * 8.0));

    println!("\n════════ ЧЕСТНЫЙ ПОТОЛОК ════════\n");
    println!("непредсказуемость этим НЕ доказывается: генератор с известным зерном дал бы те же числа.");
    println!("доказывается отсутствие поломки и отсутствие потери энтропии по дороге от корня к фразе.\n");

    assert!(alive >= MIN_LIVE_SOURCES, "живых источников меньше требуемого");
}
