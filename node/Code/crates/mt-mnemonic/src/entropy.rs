// The root of a Montana identity is born here and nowhere else: every client
// obtains its 32 bytes through this module, so the quality of the source is a
// property of the protocol rather than of each application.

use std::sync::{Mutex, OnceLock};

use zeroize::{Zeroize, Zeroizing};

use mt_codec::domain;

use crate::mnemonic::entropy_to_mnemonic;
use crate::{sha256_raw, Hash32};

pub const ENTROPY_LEN: usize = 32;

// Меньше трёх живых источников — отказ. Один источник означает, что вся личность стоит на
// честности одной реализации, а это ровно то состояние, ради ухода из которого источники и
// складываются. Отказ здесь дешевле, чем угадываемый корень, обнаруженный когда-нибудь потом.
pub const MIN_LIVE_SOURCES: usize = 3;

// Health-test thresholds (NIST SP 800-90B §4.4, adapted to a 32-byte block).
// Chosen so that a healthy source never trips them: P(run ≥ 8) ≤ 32·2⁻⁵⁶,
// P(any byte value ≥ 13 times) ≈ 4·10⁻²¹, P(distinct < 8) < 10⁻³⁰. A trip is
// therefore a broken source, never a fluctuation — the answer is refusal.
const RCT_MAX_RUN: usize = 8;
const APT_MAX_COUNT: usize = 12;
const MIN_DISTINCT_BYTES: usize = 8;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum EntropyError {
    Csprng,
    RepetitionCount,
    AdaptiveProportion,
    LowDistinctness,
    RepeatOfPrevious,
    TooFewSources(usize),
    SelfTestFailed,
    WrongLength(usize),
}

impl core::fmt::Display for EntropyError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Csprng => write!(f, "OS CSPRNG unavailable"),
            Self::RepetitionCount => {
                write!(f, "entropy health test failed: repetition count (RCT)")
            },
            Self::AdaptiveProportion => {
                write!(f, "entropy health test failed: adaptive proportion (APT)")
            },
            Self::LowDistinctness => {
                write!(f, "entropy health test failed: too few distinct bytes")
            },
            Self::TooFewSources(n) => write!(
                f,
                "only {n} live entropy sources, {MIN_LIVE_SOURCES} required"
            ),
            Self::SelfTestFailed => write!(f, "entropy self-test failed; no identity is born here"),
            Self::RepeatOfPrevious => {
                write!(
                    f,
                    "entropy health test failed: block repeats the previous one"
                )
            },
            Self::WrongLength(n) => write!(f, "expected {ENTROPY_LEN} bytes of entropy, got {n}"),
        }
    }
}

impl std::error::Error for EntropyError {}

pub fn generate_entropy() -> Result<Zeroizing<[u8; ENTROPY_LEN]>, EntropyError> {
    let (entropy, _) = generate_entropy_reporting()?;
    Ok(entropy)
}

// Самотест стоит до первого рождения и до первого выпуска быстрого источника. Провал не пишется
// в журнал и не обходится: пока он стоит, личность не рождается и ничего не запечатывается.
//
// Но провал НЕ запоминается (19.09.2026). Прежде вердикт лежал в OnceLock на всю жизнь процесса, а
// снимался он в первую секунду запуска — самую занятую в жизни процесса; одно ложное «мертва» по
// вине момента приговаривало весь прогон, и первое длинное письмо или входящий звонок роняли
// приложение. Свойство «мертва» доказывается каждым сбором заново (три окна, sources::gather);
// запоминается только успех — свойство машины, которое не отменяется занятым мгновением.
pub fn self_test() -> Result<(), EntropyError> {
    static PASSED: OnceLock<()> = OnceLock::new();
    if PASSED.get().is_some() {
        return Ok(());
    }
    // Вырожденные блоки обязаны отвергаться — иначе проверки здоровья мертвы.
    if health_check(&[0u8; ENTROPY_LEN]).is_ok() || health_check(&[0xFFu8; ENTROPY_LEN]).is_ok() {
        return Err(EntropyError::SelfTestFailed);
    }
    // Смешивание обязано зависеть от каждого слагаемого.
    if combine_entropy(b"a-source", b"b-source")[..] == combine_entropy(b"b-source", b"a-source")[..] {
        return Err(EntropyError::SelfTestFailed);
    }
    // Источники машины обязаны давать разный выход при одном и том же системном блоке:
    // если они мертвы, разницы не будет.
    let (x, report) = crate::sources::gather(&[0x5Au8; ENTROPY_LEN]);
    let (y, _) = crate::sources::gather(&[0x5Au8; ENTROPY_LEN]);
    if x[..] != y[..] && report.count() >= MIN_LIVE_SOURCES {
        let _ = PASSED.set(());
        Ok(())
    } else {
        Err(EntropyError::SelfTestFailed)
    }
}

/// Тот же корень и отчёт о том, какие источники живы на этой машине.
pub fn generate_entropy_reporting(
) -> Result<(Zeroizing<[u8; ENTROPY_LEN]>, crate::SourceReport), EntropyError> {
    self_test()?;
    let mut block = Zeroizing::new([0u8; ENTROPY_LEN]);
    getrandom::getrandom(block.as_mut()).map_err(|_| EntropyError::Csprng)?;
    health_check(&block[..])?;
    remember_block(&block[..])?;
    let (mixed, report) = crate::sources::gather(&block[..]);
    if report.count() < MIN_LIVE_SOURCES {
        return Err(EntropyError::TooFewSources(report.count()));
    }
    Ok((mixed, report))
}



// Смешивание независимых источников. Ни один вход не обязан быть хорошим: результат
// непредсказуем, пока непредсказуем ХОТЯ БЫ ОДИН из них, и это единственный способ
// не держать всю личность на доверии к одной чужой реализации генератора.
//
//   entropy = SHA-256("mt-entropy-mix" || 0x00 || len(a) || a || len(b) || b)
//
// Длины входят в состав явно: без них склейка двух разных пар давала бы один вход.
pub fn combine_entropy(primary: &[u8], extra: &[u8]) -> Zeroizing<[u8; ENTROPY_LEN]> {
    let mut buf: Vec<u8> =
        Vec::with_capacity(domain::ENTROPY_MIX.len() + 9 + primary.len() + extra.len());
    buf.extend_from_slice(domain::ENTROPY_MIX);
    buf.push(0x00);
    buf.extend_from_slice(&(primary.len() as u32).to_le_bytes());
    buf.extend_from_slice(primary);
    buf.extend_from_slice(&(extra.len() as u32).to_le_bytes());
    buf.extend_from_slice(extra);
    let mixed = sha256_raw(&buf);
    buf.zeroize();
    Zeroizing::new(mixed)
}

pub fn generate_mnemonic() -> Result<Zeroizing<String>, EntropyError> {
    let entropy = generate_entropy()?;
    Ok(Zeroizing::new(entropy_to_mnemonic(&entropy)))
}

// Also applied to entropy that arrives from outside (operator-supplied hex,
// imported material): a degenerate block must not become an identity whatever
// its origin.
pub fn health_check(block: &[u8]) -> Result<(), EntropyError> {
    if block.len() != ENTROPY_LEN {
        return Err(EntropyError::WrongLength(block.len()));
    }

    let mut run = 1usize;
    let mut max_run = 1usize;
    for i in 1..block.len() {
        run = if block[i] == block[i - 1] { run + 1 } else { 1 };
        if run > max_run {
            max_run = run;
        }
    }
    if max_run >= RCT_MAX_RUN {
        return Err(EntropyError::RepetitionCount);
    }

    let mut counts = [0u16; 256];
    for b in block {
        counts[*b as usize] += 1;
    }
    let distinct = counts.iter().filter(|c| **c > 0).count();
    if counts.iter().any(|c| *c as usize > APT_MAX_COUNT) {
        return Err(EntropyError::AdaptiveProportion);
    }
    if distinct < MIN_DISTINCT_BYTES {
        return Err(EntropyError::LowDistinctness);
    }

    Ok(())
}

// The continuous test of SP 800-90B compares each block with its predecessor.
// Only the digest of the previous block is retained: a repeat is caught, and
// the process holds no second copy of a root that has already been handed out.
fn remember_block(block: &[u8]) -> Result<(), EntropyError> {
    static PREVIOUS: OnceLock<Mutex<Option<Hash32>>> = OnceLock::new();
    let cell = PREVIOUS.get_or_init(|| Mutex::new(None));
    let digest = sha256_raw(block);
    let mut guard = cell.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.as_ref() == Some(&digest) {
        return Err(EntropyError::RepeatOfPrevious);
    }
    *guard = Some(digest);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mnemonic::{mnemonic_to_entropy, MNEMONIC_WORD_COUNT};

    #[test]
    fn generated_entropy_is_32_bytes_and_passes_its_own_health_check() {
        let e = generate_entropy().expect("healthy CSPRNG");
        assert_eq!(e.len(), ENTROPY_LEN);
        assert_eq!(health_check(&e[..]), Ok(()));
    }

    #[test]
    fn generated_mnemonic_roundtrips_to_its_entropy() {
        let m = generate_mnemonic().expect("healthy CSPRNG");
        assert_eq!(m.split_whitespace().count(), MNEMONIC_WORD_COUNT);
        let back = mnemonic_to_entropy(&m).expect("self-produced mnemonic is valid");
        assert_eq!(back.len(), ENTROPY_LEN);
    }

    #[test]
    fn two_generations_differ() {
        let a = generate_entropy().expect("healthy CSPRNG");
        let b = generate_entropy().expect("healthy CSPRNG");
        assert_ne!(a[..], b[..]);
    }

    #[test]
    fn all_zero_block_is_refused() {
        assert_eq!(health_check(&[0u8; 32]), Err(EntropyError::RepetitionCount));
    }

    #[test]
    fn all_ff_block_is_refused() {
        assert_eq!(
            health_check(&[0xFFu8; 32]),
            Err(EntropyError::RepetitionCount)
        );
    }

    #[test]
    fn repeating_two_byte_pattern_is_refused() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = if i % 2 == 0 { 0xAA } else { 0x55 };
        }
        assert_eq!(health_check(&block), Err(EntropyError::AdaptiveProportion));
    }

    #[test]
    fn eight_repeats_trip_the_repetition_test() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = i as u8;
        }
        for b in block.iter_mut().take(8) {
            *b = 0x11;
        }
        assert_eq!(health_check(&block), Err(EntropyError::RepetitionCount));
    }

    #[test]
    fn seven_repeats_pass() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = i as u8;
        }
        for b in block.iter_mut().take(7) {
            *b = 0x11;
        }
        assert_eq!(health_check(&block), Ok(()));
    }

    #[test]
    fn thirteen_copies_of_one_value_trip_the_proportion_test() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = i as u8;
        }
        // 13 копий значения 0x77, разнесённых так, что RCT не срабатывает.
        for i in 0..13 {
            block[i * 2] = 0x77;
        }
        assert_eq!(health_check(&block), Err(EntropyError::AdaptiveProportion));
    }

    #[test]
    fn twelve_copies_of_one_value_pass() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = i as u8;
        }
        for i in 0..12 {
            block[i * 2] = 0x77;
        }
        assert_eq!(health_check(&block), Ok(()));
    }

    #[test]
    fn low_distinctness_is_refused() {
        // Семь значений, каждое ≤ 12 раз, ни одного длинного повтора.
        let values = [0x01u8, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07];
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = values[i % values.len()];
        }
        assert_eq!(health_check(&block), Err(EntropyError::LowDistinctness));
    }

    #[test]
    fn wrong_length_is_refused() {
        assert_eq!(health_check(&[0u8; 31]), Err(EntropyError::WrongLength(31)));
        assert_eq!(health_check(&[0u8; 33]), Err(EntropyError::WrongLength(33)));
    }

    #[test]
    fn mixing_is_deterministic_and_input_sensitive() {
        let a = [0x11u8; 32];
        let b = [0x22u8; 32];
        assert_eq!(combine_entropy(&a, &b)[..], combine_entropy(&a, &b)[..]);
        assert_ne!(combine_entropy(&a, &b)[..], combine_entropy(&b, &a)[..]);
        assert_ne!(
            combine_entropy(&a, &b)[..],
            combine_entropy(&a, &[0x22u8; 31])[..]
        );
    }

    #[test]
    fn mixing_has_no_length_ambiguity() {
        // Без явных длин пара ("ab", "c") и ("a", "bc") дала бы один вход.
        assert_ne!(
            combine_entropy(b"ab", b"c")[..],
            combine_entropy(b"a", b"bc")[..]
        );
    }






    #[test]
    fn repeat_of_previous_block_is_refused() {
        let block = [
            0x9a, 0x1f, 0x03, 0xb7, 0x2c, 0xd4, 0x55, 0xe8, 0x11, 0x7f, 0xa0, 0x36, 0x48, 0xc2,
            0x5d, 0xe1, 0x0b, 0x93, 0x71, 0x2a, 0xbc, 0x4e, 0x68, 0xd7, 0x15, 0x39, 0x82, 0xf4,
            0x6a, 0x0c, 0xd3, 0x57,
        ];
        assert_eq!(remember_block(&block), Ok(()));
        assert_eq!(remember_block(&block), Err(EntropyError::RepeatOfPrevious));
    }
}
