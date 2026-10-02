//! Montana Names — слой имён. Чистые функции: ни сети, ни состояния, ни времени.
//! Источник правил: «Montana Names», разделы IV (объекты), VII (нормализация), VIII (константы).

#![forbid(unsafe_code)]

use caseless::default_case_fold_str;
use unicode_normalization::UnicodeNormalization;

pub const NAME_MIN_LEN: usize = 4;
pub const NAME_MAX_LEN: usize = 32;

/// Почему имя не принято. Отказ называет причину: человеку показывают её дословно.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum NameError {
    TooShort,
    TooLong,
    NotStartingWithLetter,
    EndsWithSign,
    DoubleSign,
    Empty,
    /// Знак вне набора `[a-z0-9_-]` после NFKC и casefold.
    Charset,
}

/// Нормализация (раздел VII), восемь шагов подряд:
/// 1. NFKC; 2. полный casefold; 3. срез ведущего `@`; 4. набор `[a-z0-9_-]`;
/// 5. длина NAME_MIN_LEN..NAME_MAX_LEN; 6. начинается с буквы;
/// 7. не заканчивается на `_` либо `-`; 8. два знака подряд запрещены.
///
/// Шаги 1-2 существуют затем, чтобы один и тот же ввод давал один и тот же результат на любой
/// платформе: «Ａ» и «A» — одно имя, «straße» и «strasse» — одно имя. Без этого слой раскалывается.
pub fn normalize(input: &str) -> Result<String, NameError> {
    // Ровно восемь шагов спеки и ни одного своего. Обрезка пробелов СЮДА НЕ ВХОДИТ: её нет в
    // разделе VII, и чужая реализация отвергла бы «  alice  », который приняли бы мы, — это раскол
    // слоя. Пробелы обрезает клиент до вызова.
    let folded = default_case_fold_str(&input.nfkc().collect::<String>());
    let stripped = folded.strip_prefix('@').unwrap_or(&folded);
    // Знак вне набора — ОТКАЗ, а не выбрасывание. Молчаливое выбрасывание давало бы человеку
    // ИНОЕ имя, чем он ввёл: «alicé» превратилось бы в «alic», и он бы этого не заметил.
    if stripped.is_empty() {
        return Err(NameError::Empty);
    }
    if !stripped
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
    {
        return Err(NameError::Charset);
    }
    let kept = stripped.to_string();

    // Длина — в нормализованных БАЙТАХ (раздел VII, шаг 5). Набор уже проверен, все знаки ASCII,
    // поэтому байты и знаки совпадают по построению.
    if kept.len() < NAME_MIN_LEN {
        return Err(NameError::TooShort);
    }
    if kept.len() > NAME_MAX_LEN {
        return Err(NameError::TooLong);
    }
    if !kept.chars().next().is_some_and(|c| c.is_ascii_lowercase()) {
        return Err(NameError::NotStartingWithLetter);
    }
    if kept.ends_with('_') || kept.ends_with('-') {
        return Err(NameError::EndsWithSign);
    }
    for pair in ["__", "--", "_-", "-_"] {
        if kept.contains(pair) {
            return Err(NameError::DoubleSign);
        }
    }
    Ok(kept)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Таблица приёмки шага A-1: вход → ожидаемый исход. Каждая строка защищает одно правило.
    #[test]
    fn normalization_table() {
        let max_name = "a".repeat(NAME_MAX_LEN);
        let too_long = "a".repeat(NAME_MAX_LEN + 1);
        let ok: &[(&str, &str)] = &[
            ("alice", "alice"),
            ("@alice", "alice"),
            ("Alice", "alice"),
            ("ALICEMONTANA", "alicemontana"),
            ("alice_montana", "alice_montana"),
            ("alice-montana", "alice-montana"),
            ("a1ice", "a1ice"),
            ("ａｌｉｃｅ", "alice"), // fullwidth → NFKC
            ("ＡＬＩＣＥ", "alice"), // fullwidth + casefold
            ("straße", "strasse"),   // полный casefold: ß → ss
            (max_name.as_str(), max_name.as_str()),
            ("ab_cd", "ab_cd"),
            ("ab-cd", "ab-cd"),
            ("a1_b2-c3", "a1_b2-c3"),
        ];
        for (input, want) in ok {
            assert_eq!(normalize(input).as_deref(), Ok(*want), "вход {input:?}");
        }

        let bad: &[(&str, NameError)] = &[
            ("", NameError::Empty),
            ("🙂🙂", NameError::Charset),
            ("ALIÇE", NameError::Charset), // ç вне набора — отказ, не подмена имени
            ("alice🙂", NameError::Charset),
            ("алиса-alice", NameError::Charset),
            ("alice montana", NameError::Charset), // пробел внутри
            ("  alice  ", NameError::Charset),     // обрезка — работа клиента, не слоя
            ("alice.montana", NameError::Charset),
            ("alice@montana", NameError::Charset), // @ срезается только ведущий
            ("abc", NameError::TooShort),
            ("@abc", NameError::TooShort),
            (too_long.as_str(), NameError::TooLong),
            ("1alice", NameError::NotStartingWithLetter),
            ("_alice", NameError::NotStartingWithLetter),
            ("-alice", NameError::NotStartingWithLetter),
            ("alice_", NameError::EndsWithSign),
            ("alice-", NameError::EndsWithSign),
            ("al__ice", NameError::DoubleSign),
            ("al--ice", NameError::DoubleSign),
            ("al_-ice", NameError::DoubleSign),
            ("al-_ice", NameError::DoubleSign),
        ];
        for (input, want) in bad {
            assert_eq!(normalize(input), Err(*want), "вход {input:?}");
        }
    }

    /// Нормализация идемпотентна: результат, поданный снова, не меняется.
    #[test]
    fn normalization_is_idempotent() {
        for input in ["Alice", "ａｌｉｃｅ", "straße", "@ALICE_montana"] {
            let once = normalize(input).unwrap();
            assert_eq!(normalize(&once).unwrap(), once, "вход {input:?}");
        }
    }
}

/// Ячейка имени (раздел IV): `slot = SHA-256("mt-name-slot" || 0x00 || normalized_name)`.
/// Имя в цепь не попадает никогда — в цепи только ячейка.
pub fn slot(normalized: &str) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-slot");
    h.update([0x00u8]);
    h.update(normalized.as_bytes());
    h.finalize().into()
}

#[cfg(test)]
mod slot_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// Замороженные векторы шага A-2. Значения вычислены этой же композицией и зафиксированы:
    /// расхождение у чужой реализации ловится здесь, а не в живой сети.
    #[test]
    fn slot_vectors() {
        // Значения посчитаны НЕЗАВИСИМОЙ реализацией (python hashlib), а не списаны с нашей:
        // вектор, снятый с собственного кода, подтверждает лишь сам себя.
        for (name, want) in [
            (
                "alice",
                "b5793a0d4f7f0737ebffb1374d24d3eed05efef5bd63eb1e4b03d81652c2575e",
            ),
            (
                "alicemontana",
                "0d09230abe3641df7434050a5b99329b05c1f4c387dd9cd738843d4ac4672547",
            ),
            (
                "a1_b2-c3",
                "37bfee292d7a237a2c9d0f58448ca7df8a36476280ff91bd9f4ce5da32e7b406",
            ),
        ] {
            assert_eq!(hex(&slot(name)), want, "имя {name:?}");
        }
    }

    /// Ячейка зависит ТОЛЬКО от нормализованного имени: разные записи одного имени дают одну ячейку.
    #[test]
    fn slot_is_stable_across_writings() {
        let a = slot(&normalize("Alice").unwrap());
        let b = slot(&normalize("ａｌｉｃｅ").unwrap());
        let c = slot(&normalize("@ALICE").unwrap());
        assert_eq!(a, b);
        assert_eq!(a, c);
    }

    /// Разные имена — разные ячейки (иначе слой склеивал бы людей).
    #[test]
    fn different_names_differ() {
        assert_ne!(slot("alice"), slot("alicf"));
    }
}

/// Длина цепи продлений (раздел VIII): 128 звеньев по 6τ₂ ≈ 29 лет.
pub const NAME_CHAIN_LEN: usize = 128;

/// Дальний конец цепи (набор): `HKDF-Expand(master_seed, "mt-name-own" || 0x00 || slot, 32)`.
/// Ветвь берёт ЯЧЕЙКУ, поэтому два имени одного держателя дают две цепи, которые не сводятся
/// друг к другу. Хранить его негде и незачем: он выводится из сид-фразы в любой момент.
pub fn name_own(master_seed: &[u8], slot: &[u8; 32]) -> [u8; 32] {
    let mut info = Vec::with_capacity(11 + 1 + 32);
    info.extend_from_slice(b"mt-name-own");
    info.push(0x00);
    info.extend_from_slice(slot);
    let v = mt_mnemonic::hkdf_expand(master_seed, &info, 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&v);
    out
}

/// Цепь продлений (набор). `link[N]` ЕСТЬ ветвь семени, каждое предыдущее звено — хеш
/// следующего под доменом `mt-name-chain`, `anchor = link[0]`. Публикуется якорь, а звенья открываются по одному:
/// знание звена шага k не даёт звена шага k+1, поэтому продление можно делегировать, не отдавая
/// власть над именем.
pub fn chain(name_own: &[u8; 32]) -> Vec<[u8; 32]> {
    use sha2::{Digest, Sha256};
    let mut links = vec![[0u8; 32]; NAME_CHAIN_LEN + 1];
    links[NAME_CHAIN_LEN] = *name_own;
    for i in (0..NAME_CHAIN_LEN).rev() {
        let mut h = Sha256::new();
        h.update(b"mt-name-chain");
        h.update([0x00u8]);
        h.update(links[i + 1]);
        links[i] = h.finalize().into();
    }
    links
}

/// Якорь цепи — её нулевое звено.
pub fn anchor(chain: &[[u8; 32]]) -> [u8; 32] {
    chain[0]
}

/// Фиксация (набор): `SHA-256("mt-name-commit" || 0x00 || slot || blind || tip)`.
/// Собирающий пачку видит 32 непрозрачных байта: ни имени, ни ячейки, ни якоря.
pub fn commit(slot: &[u8; 32], blind: &[u8; 32], tip: &[u8; 32]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-commit");
    h.update([0x00u8]);
    h.update(slot);
    h.update(blind);
    h.update(tip);
    h.finalize().into()
}

/// Проверка звена (набор): `SHA-256("mt-name-chain" || 0x00 || link) == prev_link`.
pub fn verify_link(prev_link: &[u8; 32], link: &[u8; 32]) -> bool {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-chain");
    h.update([0x00u8]);
    h.update(link);
    let got: [u8; 32] = h.finalize().into();
    got == *prev_link
}

#[cfg(test)]
mod chain_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// Вектор посчитан независимой реализацией HKDF-Expand (python hmac), не снят с нашей.
    #[test]
    fn name_own_vector() {
        let sl = slot("alicemontana");
        assert_eq!(
            hex(&name_own(&[0u8; 64], &sl)),
            "5fb0d57f205793cfce5517939cf30ed0562aba86f5d5adc81f2bd7ddb5b12ba4"
        );
    }

    #[test]
    fn chain_length_and_anchor() {
        let c = chain(&name_own(&[0u8; 64], &slot("alicemontana")));
        assert_eq!(c.len(), NAME_CHAIN_LEN + 1);
        assert_eq!(anchor(&c), c[0]);
    }

    /// Каждое предыдущее звено — хеш следующего. Это и делает цепь односторонней.
    #[test]
    fn every_link_verifies_against_previous() {
        let c = chain(&name_own(&[7u8; 64], &slot("alicemontana")));
        for i in 0..NAME_CHAIN_LEN {
            assert!(verify_link(&c[i], &c[i + 1]), "звено {i}");
        }
    }

    /// Обратный ход невозможен: звено не проверяется против чужого предыдущего.
    #[test]
    fn wrong_link_rejected() {
        let c = chain(&name_own(&[7u8; 64], &slot("alicemontana")));
        assert!(!verify_link(&c[0], &c[2]));
        assert!(!verify_link(&c[5], &c[5]));
    }

    /// Цепь детерминирована: тот же сид и то же имя дают ту же цепь.
    #[test]
    fn chain_is_deterministic() {
        let a = chain(&name_own(&[1u8; 64], &slot("alice")));
        let b = chain(&name_own(&[1u8; 64], &slot("alice")));
        assert_eq!(a, b);
    }

    /// Разные имена при одном сиде дают разные цепи: ячейка входит в ветвь семени.
    #[test]
    fn chain_binds_the_slot() {
        let seed = [1u8; 64];
        assert_ne!(
            chain(&name_own(&seed, &slot("alice"))),
            chain(&name_own(&seed, &slot("alicf")))
        );
    }

    #[test]
    fn commit_hides_everything() {
        let sl = slot("alice");
        let c = chain(&name_own(&[2u8; 64], &sl));
        let cm = commit(&sl, &[9u8; 32], &anchor(&c));
        // фиксация не равна ни одному из своих входов
        assert_ne!(cm, sl);
        assert_ne!(cm, anchor(&c));
        // и меняется от любого из них
        assert_ne!(cm, commit(&slot("alicf"), &anchor(&c), &[9u8; 32]));
        assert_ne!(cm, commit(&sl, &anchor(&c), &[8u8; 32]));
    }
}

/// Итераций растяжки ключа обращения (раздел VIII). Столько же, сколько в деривации из мнемоники.
/// Семя контактного ключа имени (набор): `HKDF-Expand(master_seed, "mt-name-contact-key" || 0x00 || slot, 64)`.
/// Из него строится пара ML-KEM-768, чей открытый ключ и публикует ячейка имени. Секретная
/// половина не покидает устройство, а пара строится вызывающим: ML-KEM у него уже есть.
pub fn contact_seed(master_seed: &[u8], slot: &[u8; 32]) -> [u8; 64] {
    let mut info = Vec::with_capacity(19 + 1 + 32);
    info.extend_from_slice(b"mt-name-contact-key");
    info.push(0x00);
    info.extend_from_slice(slot);
    let v = mt_mnemonic::hkdf_expand(master_seed, &info, 64);
    let mut out = [0u8; 64];
    out.copy_from_slice(&v);
    out
}

/// Метка первого контакта (набор): `SHA-256("mt-name-tag" || 0x00 || contact_root || W_8B_LE)[0..16]`.
/// Она имеет ту же форму, что и метка обычной трубы, и свой домен — поэтому не сталкивается с
/// меткой, стоящей на секрете, который держат двое.
pub fn first_tag(contact_root: &[u8], window: u64) -> [u8; 16] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-tag");
    h.update([0x00u8]);
    h.update(contact_root);
    h.update(window.to_le_bytes());
    let full: [u8; 32] = h.finalize().into();
    let mut out = [0u8; 16];
    out.copy_from_slice(&full[..16]);
    out
}

/// Секрет первого письма (набор): `SHA-256("mt-name-first" || 0x00 || ss || contact_root || ct)`.
/// Первый контакт есть ОДНО инкапсулирование: незнакомец инкапсулирует к контактному корню,
/// держатель раскрывает, и дальше переписка идёт под обычной меткой. Корень входит в вывод,
/// чтобы двое пишущих на одно имя не сошлись на одном секрете, а шифротекст — чтобы не сошлись
/// и два письма одного незнакомца.
pub fn first_secret(ss: &[u8], contact_root: &[u8], ct: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-first");
    h.update([0x00u8]);
    h.update(ss);
    h.update(contact_root);
    h.update(ct);
    h.finalize().into()
}

pub const NAME_KDF_ITER: u32 = 1 << 20;
/// Нулевых бит в задаче отправителя (раздел VIII).
pub const NAME_PUZZLE_BITS: u32 = 20;

/// Ключ обращения (раздел VI): `PBKDF2-HMAC-SHA-256(пароль = normalized_name || eph_pk,
/// соль = slot, итераций = NAME_KDF_ITER, 32 B)`.
///
/// Растяжка защищает не хранилище — его нет вовсе, — а обращение: почтальон, видящий
/// запечатанный запрос, не может перебором узнать, какое имя спрашивали.
pub fn req_key(normalized: &str, eph_pk: &[u8], slot: &[u8; 32]) -> [u8; 32] {
    req_key_iter(normalized, eph_pk, slot, NAME_KDF_ITER)
}

/// То же с явным числом итераций — ТОЛЬКО для тестов внутри крейта. Наружу не выходит:
/// открытый параметр итераций рано или поздно вызвали бы со слабым значением, и растяжка,
/// стоящая здесь ради защиты обращения, перестала бы защищать.
fn req_key_iter(normalized: &str, eph_pk: &[u8], slot: &[u8; 32], iterations: u32) -> [u8; 32] {
    let mut password = normalized.as_bytes().to_vec();
    password.extend_from_slice(eph_pk);
    let v = mt_mnemonic::pbkdf2_hmac_sha256(&password, slot, iterations, 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&v);
    out
}

/// Задача отправителя (раздел V): `SHA-256("mt-name-puzzle" || 0x00 || slot || eph_pk || nonce)`.
pub fn puzzle(slot: &[u8; 32], eph_pk: &[u8], nonce: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-name-puzzle");
    h.update([0x00u8]);
    h.update(slot);
    h.update(eph_pk);
    h.update(nonce);
    h.finalize().into()
}

/// Задача решена, если старшие `bits` бит хеша — нули. Владелец проверяет это ОДНИМ хешем и
/// только потом тратит растяжку: иначе поток пустых обращений сжигал бы его процессор.
pub fn puzzle_ok(hash: &[u8; 32], bits: u32) -> bool {
    if bits > 256 {
        return false; // требовать больше бит, чем в хеше, нельзя: это не «строже», это ошибка вызова
    }
    let full = (bits / 8) as usize;
    let rest = bits % 8;
    if hash[..full].iter().any(|b| *b != 0) {
        return false;
    }
    if rest == 0 || full == hash.len() {
        return true;
    }
    hash[full] >> (8 - rest) == 0
}

#[cfg(test)]
mod request_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// Векторы посчитаны python hashlib.pbkdf2_hmac — независимой реализацией.
    #[test]
    fn req_key_vectors() {
        let eph: Vec<u8> = (0u8..32).collect();
        let sl = slot("alice");
        assert_eq!(
            hex(&req_key_iter("alice", &eph, &sl, 1024)),
            "e6374321d120fb63999005f1d4651eb7ce9399c7d1796c1ec1d2c47dddd0385b"
        );
    }

    /// Полная растяжка 2²⁰ — отдельным прогоном: она медленная по построению, и это её работа.
    #[test]
    fn req_key_full_iterations() {
        let eph: Vec<u8> = (0u8..32).collect();
        let sl = slot("alice");
        assert_eq!(
            hex(&req_key("alice", &eph, &sl)),
            "bb4b9c5906f55733826cf47381cfa3907aa1c510b677dcff6a85095c7fd427a6"
        );
    }

    /// Ключ обращения связан с ИМЕНЕМ, эфемерным ключом и ячейкой: меняется любой — меняется ключ.
    #[test]
    fn req_key_binds_all_three() {
        let eph: Vec<u8> = (0u8..32).collect();
        let other: Vec<u8> = (1u8..33).collect();
        let a = req_key_iter("alice", &eph, &slot("alice"), 64);
        assert_ne!(a, req_key_iter("alicf", &eph, &slot("alice"), 64));
        assert_ne!(a, req_key_iter("alice", &other, &slot("alice"), 64));
        assert_ne!(a, req_key_iter("alice", &eph, &slot("alicf"), 64));
    }

    #[test]
    fn puzzle_bits_check() {
        // ровно 20 нулевых бит: первые два байта нули, третий < 0x10
        let mut h = [0u8; 32];
        h[2] = 0x0f;
        assert!(puzzle_ok(&h, 20));
        h[2] = 0x10;
        assert!(!puzzle_ok(&h, 20), "19 бит — не решение");
        let zero = [0u8; 32];
        assert!(puzzle_ok(&zero, 20));
        assert!(puzzle_ok(&zero, 256));
        assert!(
            !puzzle_ok(&zero, 257),
            "больше бит, чем в хеше — ошибка вызова, не строгость"
        );
        let mut one = [0u8; 32];
        one[0] = 0x80;
        assert!(!puzzle_ok(&one, 1));
        assert!(puzzle_ok(&one, 0));
    }

    /// Задача действительно решается перебором и решение проверяется: маленькая сложность,
    /// чтобы тест был быстрым, механизм тот же.
    #[test]
    fn puzzle_is_solvable_and_verifiable() {
        let sl = slot("alice");
        let eph: Vec<u8> = (0u8..32).collect();
        let bits = 12;
        let mut nonce = 0u64;
        let found = loop {
            let h = puzzle(&sl, &eph, &nonce.to_le_bytes());
            if puzzle_ok(&h, bits) {
                break nonce;
            }
            nonce += 1;
            assert!(nonce < 1 << 24, "решение не найдено — задача сломана");
        };
        assert!(puzzle_ok(&puzzle(&sl, &eph, &found.to_le_bytes()), bits));
        // чужая ячейка тем же nonce не решается
        assert!(!puzzle_ok(
            &puzzle(&slot("alicf"), &eph, &found.to_le_bytes()),
            bits
        ));
    }
}

/// Сколько ячеек приходится на корзину (раздел VIII). Снизу держит укрытие, сверху — вес.
pub const NAME_BUCKET_TARGET: u64 = 256;

/// Корзина ячейки (раздел VI): спрашивают КОРЗИНУ целиком, а не ячейку, иначе узел узнаёт,
/// кем интересуется спрашивающий.
///
/// `bits = max(0, ⌊log₂(занятых / NAME_BUCKET_TARGET)⌋)`, `bucket` — старшие `bits` бит ячейки.
/// Число занятых берётся из якорённого корня индекса, поэтому у всех оно одно и выбора нет.
pub fn bucket_bits(occupied: u64) -> u32 {
    if occupied < NAME_BUCKET_TARGET {
        return 0;
    }
    (occupied / NAME_BUCKET_TARGET).ilog2()
}

/// Корзина как число: старшие `bits` бит ячейки, big-endian. При нуле бит корзина одна.
pub fn bucket(slot: &[u8; 32], occupied: u64) -> u64 {
    let bits = bucket_bits(occupied);
    if bits == 0 {
        return 0;
    }
    let mut top = 0u64;
    for b in &slot[..8] {
        top = (top << 8) | u64::from(*b);
    }
    top >> (64 - bits)
}

#[cfg(test)]
mod bucket_tests {
    use super::*;

    /// Таблица приёмки шага A-10: сколько занято → сколько бит корзины.
    #[test]
    fn bucket_bits_table() {
        for (occupied, bits) in [
            (0u64, 0u32),
            (1, 0),
            (255, 0),
            (256, 0), // 256/256 = 1 → log2 = 0: корзина всё ещё одна
            (511, 0),
            (512, 1), // две корзины
            (1023, 1),
            (1024, 2),
            (10_000, 5), // 10000/256 = 39 → log2 = 5
            (1_000_000, 11),
        ] {
            assert_eq!(bucket_bits(occupied), bits, "занято {occupied}");
        }
    }

    /// Размер корзины держится в пределах [цель, 2×цель): это и есть смысл формулы.
    #[test]
    fn bucket_size_stays_in_band() {
        for occupied in [512u64, 1000, 4096, 100_000, 1_000_000, 10_000_000] {
            let buckets = 1u64 << bucket_bits(occupied);
            let per = occupied / buckets;
            assert!(
                (NAME_BUCKET_TARGET..2 * NAME_BUCKET_TARGET).contains(&per),
                "занято {occupied}: в корзине {per}"
            );
        }
    }

    /// Корзина — функция ТОЛЬКО ячейки и числа занятых: выбора у спрашивающего нет.
    #[test]
    fn bucket_is_deterministic() {
        let s = slot("alice");
        assert_eq!(bucket(&s, 1_000_000), bucket(&s, 1_000_000));
    }

    /// Корзина умещается в число корзин.
    #[test]
    fn bucket_within_range() {
        for occupied in [0u64, 512, 10_000, 1_000_000] {
            let n = 1u64 << bucket_bits(occupied);
            for name in ["alice", "alicemontana", "bobmontana", "carolmontana"] {
                assert!(
                    bucket(&slot(name), occupied) < n,
                    "имя {name}, занято {occupied}"
                );
            }
        }
    }
}

/// Записей в ответе — не больше (раздел VIII): человек публикует под именем почту и мессенджер.
pub const NAME_ENTRY_MAX: usize = 2;
/// Потолок ответа в байтах (раздел VIII).
pub const NAME_ANSWER_MAX: usize = 8 * 1024;
/// Длина подписи ML-DSA-65.
pub const SIG_LEN: usize = 3309;

/// Разбор не удался. Причина названа: молчаливый отказ прячет поломку формата.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ParseError {
    Truncated,
    BadVersion,
    TooManyEntries,
    BadLength,
    TooLarge,
}

/// Фиксация (0x03): 32 непрозрачных байта и ничего больше.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameCommit {
    pub commit: [u8; 32],
}

/// Раскрытие (0x03).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameReveal {
    pub slot: [u8; 32],
    pub anchor: [u8; 32],
    pub nonce: [u8; 32],
    pub commit_win: u32,
}

/// Продление (0x03): очередное звено цепи и его номер.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameRenew {
    pub slot: [u8; 32],
    pub step: u32,
    pub link: [u8; 32],
}

/// Одна запись ответа: вид и значение. Платёжный ключ здесь запрещён ([I-2]).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameEntry {
    pub kind: u16,
    pub value: Vec<u8>,
    pub sig: Vec<u8>,
}

/// Ответ владельца (0x04). Нигде не хранится: составляется на каждый запрос.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameAnswer {
    pub entries: Vec<NameEntry>,
}

const V3: u8 = 0x03;
const V4: u8 = 0x04;

fn take<'a>(b: &mut &'a [u8], n: usize) -> Result<&'a [u8], ParseError> {
    if b.len() < n {
        return Err(ParseError::Truncated);
    }
    let (head, rest) = b.split_at(n);
    *b = rest;
    Ok(head)
}
fn take32(b: &mut &[u8]) -> Result<[u8; 32], ParseError> {
    let mut out = [0u8; 32];
    out.copy_from_slice(take(b, 32)?);
    Ok(out)
}
fn take_u32_le(b: &mut &[u8]) -> Result<u32, ParseError> {
    let mut out = [0u8; 4];
    out.copy_from_slice(take(b, 4)?);
    Ok(u32::from_le_bytes(out))
}
fn take_u16_le(b: &mut &[u8]) -> Result<u16, ParseError> {
    let mut out = [0u8; 2];
    out.copy_from_slice(take(b, 2)?);
    Ok(u16::from_le_bytes(out))
}

impl NameCommit {
    pub fn encode(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.commit);
        v
    }
    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let commit = take32(&mut b)?;
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self { commit })
    }
}

impl NameReveal {
    pub fn encode(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.slot);
        v.extend_from_slice(&self.anchor);
        v.extend_from_slice(&self.nonce);
        v.extend_from_slice(&self.commit_win.to_le_bytes());
        v
    }
    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let slot = take32(&mut b)?;
        let anchor = take32(&mut b)?;
        let nonce = take32(&mut b)?;
        let commit_win = take_u32_le(&mut b)?;
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self {
            slot,
            anchor,
            nonce,
            commit_win,
        })
    }
}

impl NameRenew {
    pub fn encode(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.slot);
        v.extend_from_slice(&self.step.to_le_bytes());
        v.extend_from_slice(&self.link);
        v
    }
    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let slot = take32(&mut b)?;
        let step = take_u32_le(&mut b)?;
        let link = take32(&mut b)?;
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self { slot, step, link })
    }
}

impl NameAnswer {
    pub fn encode(&self) -> Result<Vec<u8>, ParseError> {
        if self.entries.len() > NAME_ENTRY_MAX {
            return Err(ParseError::TooManyEntries);
        }
        let mut v = vec![V4, self.entries.len() as u8];
        for e in &self.entries {
            v.extend_from_slice(&e.kind.to_le_bytes());
            let len = u16::try_from(e.value.len()).map_err(|_| ParseError::BadLength)?;
            v.extend_from_slice(&len.to_le_bytes());
            v.extend_from_slice(&e.value);
        }
        for e in &self.entries {
            if e.sig.len() != SIG_LEN {
                return Err(ParseError::BadLength);
            }
            v.extend_from_slice(&e.sig);
        }
        if v.len() > NAME_ANSWER_MAX {
            return Err(ParseError::TooLarge);
        }
        Ok(v)
    }

    pub fn decode(mut b: &[u8]) -> Result<Self, ParseError> {
        if b.len() > NAME_ANSWER_MAX {
            return Err(ParseError::TooLarge); // потолок — отказ, не усечение
        }
        if take(&mut b, 1)?[0] != V4 {
            return Err(ParseError::BadVersion);
        }
        let count = take(&mut b, 1)?[0] as usize;
        if count > NAME_ENTRY_MAX {
            return Err(ParseError::TooManyEntries);
        }
        let mut kinds = Vec::with_capacity(count);
        let mut values = Vec::with_capacity(count);
        for _ in 0..count {
            let kind = take_u16_le(&mut b)?;
            let len = take_u16_le(&mut b)? as usize;
            let value = take(&mut b, len)?.to_vec();
            kinds.push(kind);
            values.push(value);
        }
        let mut sigs = Vec::with_capacity(count);
        for _ in 0..count {
            sigs.push(take(&mut b, SIG_LEN)?.to_vec());
        }
        if !b.is_empty() {
            return Err(ParseError::BadLength);
        }
        Ok(Self {
            entries: (0..count)
                .map(|i| NameEntry {
                    kind: kinds[i],
                    value: values[i].clone(),
                    sig: sigs[i].clone(),
                })
                .collect(),
        })
    }
}

#[cfg(test)]
mod wire_tests {
    use super::*;

    fn answer(n: usize) -> NameAnswer {
        NameAnswer {
            entries: (0..n)
                .map(|i| NameEntry {
                    kind: 0x0001 + i as u16,
                    value: vec![0xAB; 40 + i],
                    sig: vec![0xCD; SIG_LEN],
                })
                .collect(),
        }
    }

    /// Круговой прогон: закодировали — разобрали — то же самое.
    #[test]
    fn round_trip_all_objects() {
        let c = NameCommit { commit: [1u8; 32] };
        assert_eq!(NameCommit::decode(&c.encode()), Ok(c.clone()));

        let r = NameReveal {
            slot: [2u8; 32],
            anchor: [3u8; 32],
            nonce: [4u8; 32],
            commit_win: 123_456,
        };
        assert_eq!(NameReveal::decode(&r.encode()), Ok(r.clone()));

        let n = NameRenew {
            slot: [5u8; 32],
            step: 7,
            link: [6u8; 32],
        };
        assert_eq!(NameRenew::decode(&n.encode()), Ok(n.clone()));

        for k in 0..=NAME_ENTRY_MAX {
            let a = answer(k);
            assert_eq!(
                NameAnswer::decode(&a.encode().unwrap()),
                Ok(a.clone()),
                "записей {k}"
            );
        }
    }

    /// Длины полей — ровно по спеке.
    #[test]
    fn exact_lengths() {
        assert_eq!(NameCommit { commit: [0; 32] }.encode().len(), 1 + 32);
        assert_eq!(
            NameReveal {
                slot: [0; 32],
                anchor: [0; 32],
                nonce: [0; 32],
                commit_win: 0
            }
            .encode()
            .len(),
            1 + 32 + 32 + 32 + 4
        );
        assert_eq!(
            NameRenew {
                slot: [0; 32],
                step: 0,
                link: [0; 32]
            }
            .encode()
            .len(),
            1 + 32 + 4 + 32
        );
    }

    /// Обрезанный байт — отказ, а не догадка. Проверяется на КАЖДОЙ длине.
    #[test]
    fn truncation_is_rejected_at_every_length() {
        let objs: Vec<Vec<u8>> = vec![
            NameCommit { commit: [1; 32] }.encode(),
            NameReveal {
                slot: [2; 32],
                anchor: [3; 32],
                nonce: [4; 32],
                commit_win: 9,
            }
            .encode(),
            NameRenew {
                slot: [5; 32],
                step: 1,
                link: [6; 32],
            }
            .encode(),
            answer(2).encode().unwrap(),
        ];
        for (i, full) in objs.iter().enumerate() {
            for cut in 0..full.len() {
                let part = &full[..cut];
                let ok = match i {
                    0 => NameCommit::decode(part).is_ok(),
                    1 => NameReveal::decode(part).is_ok(),
                    2 => NameRenew::decode(part).is_ok(),
                    _ => NameAnswer::decode(part).is_ok(),
                };
                assert!(!ok, "объект {i}, обрезка до {cut} принята");
            }
        }
    }

    /// Лишний байт в конце — тоже отказ: иначе в объект можно тайком дописать.
    #[test]
    fn trailing_bytes_rejected() {
        let mut c = NameCommit { commit: [1; 32] }.encode();
        c.push(0);
        assert_eq!(NameCommit::decode(&c), Err(ParseError::BadLength));
    }

    /// Чужая версия — отказ.
    #[test]
    fn bad_version_rejected() {
        let mut c = NameCommit { commit: [1; 32] }.encode();
        c[0] = 0x02;
        assert_eq!(NameCommit::decode(&c), Err(ParseError::BadVersion));
    }

    /// Больше NAME_ENTRY_MAX записей — отказ и при сборке, и при разборе.
    #[test]
    fn entry_cap_enforced() {
        assert_eq!(answer(3).encode(), Err(ParseError::TooManyEntries));
        let mut a = answer(2).encode().unwrap();
        a[1] = 3; // объявлено больше, чем разрешено
        assert_eq!(NameAnswer::decode(&a), Err(ParseError::TooManyEntries));
    }

    /// Потолок ответа — отказ, не усечение.
    #[test]
    fn answer_cap_is_refusal_not_truncation() {
        let big = NameAnswer {
            entries: vec![NameEntry {
                kind: 1,
                value: vec![0; 5000], // 5000 + 3309 подписи > NAME_ANSWER_MAX
                sig: vec![0xCD; SIG_LEN],
            }],
        };
        assert_eq!(big.encode(), Err(ParseError::TooLarge));
        assert_eq!(
            NameAnswer::decode(&vec![0u8; NAME_ANSWER_MAX + 1]),
            Err(ParseError::TooLarge)
        );
    }

    /// Подпись не той длины — отказ: 3309 байт ML-DSA-65 и ничего иного.
    #[test]
    fn signature_length_enforced() {
        let a = NameAnswer {
            entries: vec![NameEntry {
                kind: 1,
                value: vec![1, 2, 3],
                sig: vec![0; SIG_LEN - 1],
            }],
        };
        assert_eq!(a.encode(), Err(ParseError::BadLength));
    }
}

// ── Узел: пачка, индекс, корзина, приём обращения (чек-лист, этап C) ─────────────

/// Идентификатор приложения слоя (раздел IV): `SHA-256("mt-app" || 0x00 || "montana-names")`.
pub fn app_id() -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(b"mt-app");
    h.update([0x00u8]);
    h.update(b"montana-names");
    h.finalize().into()
}

/// Корень пачки объектов слоя (раздел IV): разрежённое дерево по каноническому ключу.
/// Дерево берётся ОДНО на проект (`mt_merkle`), второго не пишется.
///
/// Ключ листа — сам объект в хешированном виде: пачка есть множество, а не последовательность,
/// поэтому порядок сборки на корень не влияет и собирающий не может переставить объекты.
pub fn batch_root(objects: &[Vec<u8>]) -> [u8; 32] {
    let mut tree = mt_merkle::SparseMerkleTree::new();
    for obj in objects {
        use sha2::{Digest, Sha256};
        let key: [u8; 32] = Sha256::digest(obj).into();
        tree.insert(key, obj);
    }
    tree.root()
}

/// Индекс занятости — ПРОИЗВОДНЫЙ: строится сканом раскрытий, авторитетом не является.
/// Пересборка с нуля обязана давать то же самое, иначе индекс стал бы вторым источником истины.
pub fn occupancy_index(reveals: &[NameReveal]) -> Vec<[u8; 32]> {
    let mut slots: Vec<[u8; 32]> = reveals.iter().map(|r| r.slot).collect();
    slots.sort_unstable();
    slots.dedup();
    slots
}

/// Отдаётся КОРЗИНА целиком. Запрос одной ячейки отвергается: узел, у которого спросили ячейку,
/// узнаёт, кем интересуется спрашивающий, — а он не должен узнавать.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ServeError {
    SingleSlotRequested,
    PuzzleUnsolved,
}

/// Что узел отдаёт по запросу корзины: все занятые ячейки этой корзины.
pub fn serve_bucket(index: &[[u8; 32]], wanted_bucket: u64, occupied: u64) -> Vec<[u8; 32]> {
    index
        .iter()
        .copied()
        .filter(|s| bucket(s, occupied) == wanted_bucket)
        .collect()
}

/// Приём обращения на узле. Задача проверяется ОДНИМ хешем и до любой растяжки: иначе поток
/// пустых обращений сжигал бы процессор владельца, а именно на это и рассчитан спам.
pub fn accept_request(
    slot: &[u8; 32],
    eph_pk: &[u8],
    nonce: &[u8],
    single_slot_request: bool,
) -> Result<(), ServeError> {
    if single_slot_request {
        return Err(ServeError::SingleSlotRequested);
    }
    if !puzzle_ok(&puzzle(slot, eph_pk, nonce), NAME_PUZZLE_BITS) {
        return Err(ServeError::PuzzleUnsolved);
    }
    Ok(())
}

#[cfg(test)]
mod node_tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// Значение из раздела XI спеки.
    #[test]
    fn app_id_matches_spec() {
        assert_eq!(
            hex(&app_id()),
            "350ee2a847cd651df34d0bc6c90b71f75a0485b763503a2ee292ea5b69cc8eb8"
        );
    }

    /// Пачка есть МНОЖЕСТВО: порядок сборки на корень не влияет, переставить объекты нельзя.
    #[test]
    fn batch_root_is_order_independent() {
        let a = NameCommit { commit: [1; 32] }.encode();
        let b = NameCommit { commit: [2; 32] }.encode();
        let c = NameCommit { commit: [3; 32] }.encode();
        let r1 = batch_root(&[a.clone(), b.clone(), c.clone()]);
        let r2 = batch_root(&[c, a, b]);
        assert_eq!(r1, r2);
    }

    /// Любое изменение объекта меняет корень: придержать пачку можно, подделать нельзя.
    #[test]
    fn batch_root_binds_every_object() {
        let a = NameCommit { commit: [1; 32] }.encode();
        let b = NameCommit { commit: [2; 32] }.encode();
        let b2 = NameCommit { commit: [9; 32] }.encode();
        assert_ne!(batch_root(&[a.clone(), b]), batch_root(&[a, b2]));
    }

    /// Из фиксации не выводится ни имя, ни ячейка, ни якорь: собирающий видит 32 байта шума.
    #[test]
    fn commit_reveals_nothing() {
        let s = slot("anna");
        let c = chain(&[0xCD; 32]);
        let cm = commit(&s, &anchor(&c), &[7; 32]);
        let wire = NameCommit { commit: cm }.encode();
        // ни ячейка, ни якорь не встречаются в байтах объекта
        assert!(!wire.windows(32).any(|w| w == s));
        assert!(!wire.windows(32).any(|w| w == anchor(&c)));
        assert_eq!(
            wire.len(),
            33,
            "версия и 32 байта — больше в объекте ничего нет"
        );
    }

    /// Индекс производный: пересобранный с нуля и в другом порядке — тот же.
    #[test]
    fn index_is_reproducible() {
        let mk = |n: &str| NameReveal {
            slot: slot(n),
            anchor: [0; 32],
            nonce: [0; 32],
            commit_win: 1,
        };
        let a = occupancy_index(&[mk("alice"), mk("bob1"), mk("alice")]);
        let b = occupancy_index(&[mk("bob1"), mk("alice")]);
        assert_eq!(a, b, "повтор и порядок не меняют индекс");
        assert_eq!(a.len(), 2, "повторное раскрытие не удваивает ячейку");
    }

    /// Корзина отдаётся целиком: в ответе все ячейки корзины, а не одна запрошенная.
    #[test]
    fn bucket_served_whole() {
        let names: Vec<String> = (0..2000).map(|i| format!("user{i:05}")).collect();
        let index: Vec<[u8; 32]> = names.iter().map(|n| slot(n)).collect();
        let occupied = index.len() as u64;
        let target = slot(&names[0]);
        let b = bucket(&target, occupied);
        let served = serve_bucket(&index, b, occupied);
        assert!(served.contains(&target));
        assert!(
            served.len() >= 2,
            "в корзине одна ячейка — укрытия нет: занято {occupied}, корзина {b}"
        );
    }

    /// Запрос одной ячейки отвергается, нерешённая задача отвергается — и до растяжки.
    #[test]
    fn request_rules() {
        let s = slot("anna");
        let eph = vec![0x5A; 1184];
        assert_eq!(
            accept_request(&s, &eph, &[0; 8], true),
            Err(ServeError::SingleSlotRequested)
        );
        assert_eq!(
            accept_request(&s, &eph, &[0; 8], false),
            Err(ServeError::PuzzleUnsolved)
        );
        let nonce = 810_487u64.to_le_bytes();
        assert_eq!(accept_request(&s, &eph, &nonce, false), Ok(()));
    }
}

// ── Владение именем во времени (чек-лист, этап D) ───────────────────────────────

/// Длина τ₂ в окнах — из протокола.
pub const TAU2_WINDOWS: u32 = 20_160;
/// Период продления (раздел VIII): 6τ₂.
pub const NAME_RENEW_WINDOWS: u32 = 6 * TAU2_WINDOWS;
/// Срок раскрытия после фиксации (раздел VIII): 2τ₂.
pub const NAME_REVEAL_MAX_WINDOWS: u32 = 2 * TAU2_WINDOWS;

/// Почему шаг владения не принят.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum LifecycleError {
    RevealTooLate,
    RevealBeforeCommit,
    RenewTooLate,
    RenewNotMonotonic,
    ChainExhausted,
    SecondNameForOneSecret,
}

/// Раскрытие обязано лечь в цепь не позже `NAME_REVEAL_MAX` после фиксации, иначе фиксация мертва.
/// Мёртвые фиксации не копятся — в этом и смысл срока.
pub fn check_reveal(commit_win: u32, reveal_win: u32) -> Result<(), LifecycleError> {
    if reveal_win <= commit_win {
        return Err(LifecycleError::RevealBeforeCommit);
    }
    if reveal_win - commit_win > NAME_REVEAL_MAX_WINDOWS {
        return Err(LifecycleError::RevealTooLate);
    }
    Ok(())
}

/// Начало периода `step`. Продление выставляется СЮДА, а не на момент, когда человек открыл
/// приложение: иначе момент публикации становится признаком его жизни, а не свойством расписания.
pub fn renew_period_start(reveal_win: u32, step: u32) -> u32 {
    reveal_win + step * NAME_RENEW_WINDOWS
}

/// Продление принято, если звено монотонно, цепь не исчерпана и период не пропущен.
pub fn check_renew(
    prev_step: u32,
    prev_win: u32,
    step: u32,
    win: u32,
) -> Result<(), LifecycleError> {
    if step != prev_step + 1 {
        return Err(LifecycleError::RenewNotMonotonic);
    }
    if step as usize > NAME_CHAIN_LEN {
        return Err(LifecycleError::ChainExhausted);
    }
    if win <= prev_win || win - prev_win > NAME_RENEW_WINDOWS {
        return Err(LifecycleError::RenewTooLate);
    }
    Ok(())
}

/// Ячейка свободна: пропущено больше `NAME_RENEW`. Прежний владелец преимущества не имеет —
/// следующий берёт её на общих правах.
pub fn is_free(last_win: u32, now: u32) -> bool {
    now > last_win.saturating_add(NAME_RENEW_WINDOWS)
}

/// Одно имя на секрет (правило 2 раздела II). Второе имя требует второй ветки сида, а не второй
/// ячейки на ту же ветку: иначе одна утечка секрета забирала бы сразу все имена человека.
pub fn check_single_name(
    existing: Option<&[u8; 32]>,
    new_slot: &[u8; 32],
) -> Result<(), LifecycleError> {
    match existing {
        Some(s) if s != new_slot => Err(LifecycleError::SecondNameForOneSecret),
        _ => Ok(()),
    }
}

/// Владение подтверждено: цепь от якоря до текущего звена сходится шаг за шагом.
/// Проверяющему не нужно ни имя, ни секрет — только якорь и предъявленные звенья.
pub fn verify_ownership(anchor: &[u8; 32], links_in_order: &[[u8; 32]]) -> bool {
    let mut prev = *anchor;
    for l in links_in_order {
        if !verify_link(&prev, l) {
            return false;
        }
        prev = *l;
    }
    true
}

#[cfg(test)]
mod lifecycle_tests {
    use super::*;

    #[test]
    fn reveal_window_rules() {
        assert_eq!(check_reveal(100, 101), Ok(()));
        assert_eq!(check_reveal(100, 100 + NAME_REVEAL_MAX_WINDOWS), Ok(()));
        assert_eq!(
            check_reveal(100, 100 + NAME_REVEAL_MAX_WINDOWS + 1),
            Err(LifecycleError::RevealTooLate)
        );
        assert_eq!(
            check_reveal(100, 100),
            Err(LifecycleError::RevealBeforeCommit)
        );
        assert_eq!(
            check_reveal(100, 99),
            Err(LifecycleError::RevealBeforeCommit)
        );
    }

    /// Продление стоит в начале периода: момент публикации — свойство расписания, а не жизни.
    #[test]
    fn renew_is_scheduled_at_period_start() {
        let reveal = 1_000u32;
        assert_eq!(renew_period_start(reveal, 1), reveal + NAME_RENEW_WINDOWS);
        assert_eq!(
            renew_period_start(reveal, 2),
            reveal + 2 * NAME_RENEW_WINDOWS
        );
        // и каждое продление попадает в свой срок
        let mut prev_win = reveal;
        for step in 1..=5u32 {
            let win = renew_period_start(reveal, step);
            assert_eq!(check_renew(step - 1, prev_win, step, win), Ok(()));
            prev_win = win;
        }
    }

    #[test]
    fn renew_rules() {
        assert_eq!(
            check_renew(3, 1000, 5, 2000),
            Err(LifecycleError::RenewNotMonotonic)
        );
        assert_eq!(
            check_renew(3, 1000, 3, 2000),
            Err(LifecycleError::RenewNotMonotonic)
        );
        assert_eq!(
            check_renew(3, 1000, 4, 1000 + NAME_RENEW_WINDOWS + 1),
            Err(LifecycleError::RenewTooLate)
        );
        assert_eq!(
            check_renew(3, 1000, 4, 1000),
            Err(LifecycleError::RenewTooLate)
        );
        assert_eq!(
            check_renew(NAME_CHAIN_LEN as u32, 1000, NAME_CHAIN_LEN as u32 + 1, 1001),
            Err(LifecycleError::ChainExhausted)
        );
    }

    /// Пропущено больше периода — ячейка свободна, и прежний владелец не в привилегии.
    #[test]
    fn release_after_missed_period() {
        let last = 10_000u32;
        assert!(!is_free(last, last + NAME_RENEW_WINDOWS));
        assert!(is_free(last, last + NAME_RENEW_WINDOWS + 1));
    }

    #[test]
    fn one_name_per_secret() {
        let a = slot("alice");
        let b = slot("bobbb");
        assert_eq!(check_single_name(None, &a), Ok(()));
        assert_eq!(
            check_single_name(Some(&a), &a),
            Ok(()),
            "продление своего же имени"
        );
        assert_eq!(
            check_single_name(Some(&a), &b),
            Err(LifecycleError::SecondNameForOneSecret)
        );
    }

    /// Владение проверяется без имени и без секрета: только якорь и звенья.
    #[test]
    fn ownership_verifies_from_anchor_only() {
        let c = chain(&name_own(&[3u8; 64], &slot("alicemontana")));
        let a = anchor(&c);
        assert!(verify_ownership(&a, &c[1..6]));
        assert!(
            !verify_ownership(&a, &c[2..6]),
            "пропущенное звено рвёт цепь"
        );
        let mut broken = c[1..6].to_vec();
        broken[2] = [0xEE; 32];
        assert!(
            !verify_ownership(&a, &broken),
            "подменённое звено рвёт цепь"
        );
    }

    /// Восстановление из сида: цепь и якорь те же, состояние переносить не нужно.
    #[test]
    fn recovery_from_seed_reproduces_everything() {
        let seed = [0x5Au8; 64];
        let s = slot("alicemontana");
        let c1 = chain(&name_own(&seed, &s));
        // «другое устройство»: только сид-фраза и имя
        let c2 = chain(&name_own(&seed, &slot("alicemontana")));
        assert_eq!(anchor(&c1), anchor(&c2));
        assert_eq!(c1, c2);
    }
}

// ── Обращение и ответ (чек-лист, этап E) ────────────────────────────────────────

/// Виды записей ответа (раздел IV). Платёжный ключ и любая величина стоимостной
/// плоскости запрещены — это [I-2], а не предпочтение.
pub const ENTRY_KIND_MAIL: u16 = 0x0001;
pub const ENTRY_KIND_OVERLAY: u16 = 0x0002;
pub const ENTRY_KIND_OPAQUE: u16 = 0xFFFF;
/// Запрещённый вид: платёжный ключ.
pub const ENTRY_KIND_FORBIDDEN_NOTE_PK: u16 = 0x0100;

/// Почему резолв не состоялся. Каждый шаг раздела VI имеет свой отказ: молчаливый провал
/// прячет подмену.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum ResolveError {
    BadName,
    RecordNotInBucket,
    RecordHashMismatch,
    NotOwned,
    EntrySignatureInvalid,
    ForbiddenEntryKind,
}

/// Что проверяющий знает о записи, найденной в корзине.
pub struct ResolveInput<'a> {
    pub raw_name: &'a str,
    pub bucket_slots: &'a [[u8; 32]],
    pub occupied: u64,
    pub record_bytes: &'a [u8],
    pub record_hash_claimed: [u8; 32],
    pub anchor: [u8; 32],
    pub links_in_order: &'a [[u8; 32]],
    pub answer: &'a NameAnswer,
    /// Проверка подписи записи-адреса ключом, ВЛАДЕЮЩИМ этим адресом. Подпись проверяет
    /// вызывающий (у него ключи), сюда приходит результат: слой имён не знает о ML-DSA.
    pub entry_signatures_ok: bool,
}

/// Резолв пятью шагами раздела VI. Каждый шаг со своим отказом; порядок шагов важен:
/// проверка владения идёт ДО проверки записей, иначе чужая запись успевает быть прочитанной.
pub fn resolve(input: &ResolveInput) -> Result<Vec<NameEntry>, ResolveError> {
    let normalized = normalize(input.raw_name).map_err(|_| ResolveError::BadName)?;
    let s = slot(&normalized);

    if !input.bucket_slots.contains(&s) {
        return Err(ResolveError::RecordNotInBucket);
    }
    use sha2::{Digest, Sha256};
    let h: [u8; 32] = Sha256::digest(input.record_bytes).into();
    if h != input.record_hash_claimed {
        return Err(ResolveError::RecordHashMismatch);
    }
    if !verify_ownership(&input.anchor, input.links_in_order) {
        return Err(ResolveError::NotOwned);
    }
    for e in &input.answer.entries {
        if e.kind == ENTRY_KIND_FORBIDDEN_NOTE_PK {
            return Err(ResolveError::ForbiddenEntryKind);
        }
    }
    if !input.entry_signatures_ok {
        return Err(ResolveError::EntrySignatureInvalid);
    }
    Ok(input.answer.entries.clone())
}

#[cfg(test)]
mod resolve_tests {
    use super::*;

    fn entry(kind: u16) -> NameEntry {
        NameEntry {
            kind,
            value: b"mt-overlay-address".to_vec(),
            sig: vec![0xCD; SIG_LEN],
        }
    }

    /// Стенд резолва: имена полей понятнее кортежа из пяти значений.
    struct Stand {
        bucket_slots: Vec<[u8; 32]>,
        links: Vec<[u8; 32]>,
        anchor: [u8; 32],
        record: Vec<u8>,
        record_hash: [u8; 32],
    }

    fn setup() -> Stand {
        let s = slot("alicemontana");
        let c = chain(&name_own(&[4u8; 64], &s));
        let record = b"record-bytes".to_vec();
        use sha2::{Digest, Sha256};
        let h: [u8; 32] = Sha256::digest(&record).into();
        Stand {
            bucket_slots: vec![s, slot("bobbbb")],
            links: c[1..4].to_vec(),
            anchor: anchor(&c),
            record,
            record_hash: h,
        }
    }

    #[test]
    fn resolve_happy_path() {
        let st = setup();
        let (bucket_slots, links, a, record, h) = (
            st.bucket_slots.clone(),
            st.links.clone(),
            st.anchor,
            st.record.clone(),
            st.record_hash,
        );
        let answer = NameAnswer {
            entries: vec![entry(ENTRY_KIND_OVERLAY)],
        };
        let out = resolve(&ResolveInput {
            raw_name: "AliceMontana",
            bucket_slots: &bucket_slots,
            occupied: 2,
            record_bytes: &record,
            record_hash_claimed: h,
            anchor: a,
            links_in_order: &links,
            answer: &answer,
            entry_signatures_ok: true,
        });
        assert_eq!(out.map(|v| v.len()), Ok(1));
    }

    /// Каждый шаг имеет СВОЙ отказ: провал не бывает молчаливым и не бывает общим.
    #[test]
    fn every_step_has_its_own_refusal() {
        let st = setup();
        let (bucket_slots, links, a, record, h) = (
            st.bucket_slots.clone(),
            st.links.clone(),
            st.anchor,
            st.record.clone(),
            st.record_hash,
        );
        let answer = NameAnswer {
            entries: vec![entry(ENTRY_KIND_OVERLAY)],
        };
        let base = |raw, bs: &[[u8; 32]], rh, an, lk: &[[u8; 32]], ans, sig| {
            resolve(&ResolveInput {
                raw_name: raw,
                bucket_slots: bs,
                occupied: 2,
                record_bytes: &record,
                record_hash_claimed: rh,
                anchor: an,
                links_in_order: lk,
                answer: ans,
                entry_signatures_ok: sig,
            })
        };
        assert_eq!(
            base("!!", &bucket_slots, h, a, &links, &answer, true),
            Err(ResolveError::BadName)
        );
        assert_eq!(
            base("carolmontana", &bucket_slots, h, a, &links, &answer, true),
            Err(ResolveError::RecordNotInBucket)
        );
        assert_eq!(
            base(
                "alicemontana",
                &bucket_slots,
                [0; 32],
                a,
                &links,
                &answer,
                true
            ),
            Err(ResolveError::RecordHashMismatch)
        );
        assert_eq!(
            base(
                "alicemontana",
                &bucket_slots,
                h,
                [9; 32],
                &links,
                &answer,
                true
            ),
            Err(ResolveError::NotOwned)
        );
        let forbidden = NameAnswer {
            entries: vec![entry(ENTRY_KIND_FORBIDDEN_NOTE_PK)],
        };
        assert_eq!(
            base(
                "alicemontana",
                &bucket_slots,
                h,
                a,
                &links,
                &forbidden,
                true
            ),
            Err(ResolveError::ForbiddenEntryKind)
        );
        assert_eq!(
            base("alicemontana", &bucket_slots, h, a, &links, &answer, false),
            Err(ResolveError::EntrySignatureInvalid)
        );
    }

    /// Платёжный ключ в ответе отвергается раньше, чем проверяются подписи: [I-2] не обсуждается.
    #[test]
    fn note_key_refused_before_signatures() {
        let st = setup();
        let (bucket_slots, links, a, record, h) = (
            st.bucket_slots.clone(),
            st.links.clone(),
            st.anchor,
            st.record.clone(),
            st.record_hash,
        );
        let forbidden = NameAnswer {
            entries: vec![entry(ENTRY_KIND_FORBIDDEN_NOTE_PK)],
        };
        let r = resolve(&ResolveInput {
            raw_name: "alicemontana",
            bucket_slots: &bucket_slots,
            occupied: 2,
            record_bytes: &record,
            record_hash_claimed: h,
            anchor: a,
            links_in_order: &links,
            answer: &forbidden,
            entry_signatures_ok: false, // подписи заведомо плохи
        });
        assert_eq!(
            r,
            Err(ResolveError::ForbiddenEntryKind),
            "вид записи важнее подписи"
        );
    }

    /// Ответ нигде не хранится: два ответа на один запрос — разные байты, потому что
    /// запечатываются на разные эфемерные ключи. Здесь проверяется само свойство сборки:
    /// один и тот же набор записей кодируется в одни и те же байты, а различие вносит
    /// запечатывание — оно живёт слоем выше и не входит в слой имён.
    #[test]
    fn answer_is_assembled_not_stored() {
        let a1 = NameAnswer {
            entries: vec![entry(ENTRY_KIND_MAIL)],
        };
        let a2 = NameAnswer {
            entries: vec![entry(ENTRY_KIND_MAIL)],
        };
        assert_eq!(a1.encode(), a2.encode());
    }
}

/// Обращение к владельцу (раздел V). Запечатанная часть несёт `slot` и номер окна: перехваченное
/// обращение нельзя предъявить снова — на обращении стоит окно, и чужое окно отвергается.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct NameRequest {
    pub slot: [u8; 32],
    pub window: u32,
    pub eph_pk: Vec<u8>,
    pub nonce: [u8; 8],
}

impl NameRequest {
    /// Байты, которые запечатываются на `req_key`. Версия объекта та же, что у прочих (0x03).
    pub fn sealed_body(&self) -> Vec<u8> {
        let mut v = vec![V3];
        v.extend_from_slice(&self.slot);
        v.extend_from_slice(&self.window.to_le_bytes());
        v.extend_from_slice(&self.nonce);
        v.extend_from_slice(&self.eph_pk);
        v
    }
    pub fn parse_sealed(mut b: &[u8]) -> Result<Self, ParseError> {
        if take(&mut b, 1)?[0] != V3 {
            return Err(ParseError::BadVersion);
        }
        let slot = take32(&mut b)?;
        let window = take_u32_le(&mut b)?;
        let mut nonce = [0u8; 8];
        nonce.copy_from_slice(take(&mut b, 8)?);
        let eph_pk = b.to_vec();
        if eph_pk.is_empty() {
            return Err(ParseError::Truncated);
        }
        Ok(Self {
            slot,
            window,
            eph_pk,
            nonce,
        })
    }
}

/// Почему обращение не принято.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum RequestError {
    WrongSlot,
    StaleWindow,
    PuzzleUnsolved,
}

/// Обращение принимается только в СВОЁ окно и только на СВОЮ ячейку, и только с решённой
/// задачей. Окно на обращении и есть защита от повтора: записанное вчера сегодня не годится.
pub fn check_request(
    req: &NameRequest,
    my_slot: &[u8; 32],
    now_window: u32,
) -> Result<(), RequestError> {
    if req.slot != *my_slot {
        return Err(RequestError::WrongSlot);
    }
    if req.window != now_window {
        return Err(RequestError::StaleWindow);
    }
    if !puzzle_ok(
        &puzzle(&req.slot, &req.eph_pk, &req.nonce),
        NAME_PUZZLE_BITS,
    ) {
        return Err(RequestError::PuzzleUnsolved);
    }
    Ok(())
}

#[cfg(test)]
mod request_object_tests {
    use super::*;

    fn req(window: u32) -> NameRequest {
        NameRequest {
            slot: slot("anna"),
            window,
            eph_pk: vec![0x5A; 1184],
            nonce: 810_487u64.to_le_bytes(),
        }
    }

    #[test]
    fn sealed_body_round_trip() {
        let r = req(42);
        assert_eq!(NameRequest::parse_sealed(&r.sealed_body()), Ok(r));
    }

    /// Повтор перехваченного обращения отвергается: на нём стоит чужое окно.
    #[test]
    fn replay_is_refused() {
        let s = slot("anna");
        assert_eq!(check_request(&req(42), &s, 42), Ok(()));
        assert_eq!(
            check_request(&req(42), &s, 43),
            Err(RequestError::StaleWindow)
        );
        assert_eq!(
            check_request(&req(42), &s, 41),
            Err(RequestError::StaleWindow)
        );
    }

    /// Чужая ячейка отвергается прежде задачи: считать хеш ради чужого обращения незачем.
    #[test]
    fn wrong_slot_refused_first() {
        let mut r = req(42);
        r.nonce = [0; 8]; // задача заведомо не решена
        assert_eq!(
            check_request(&r, &slot("bobbbb"), 42),
            Err(RequestError::WrongSlot)
        );
    }

    #[test]
    fn unsolved_puzzle_refused() {
        let mut r = req(42);
        r.nonce = [0; 8];
        assert_eq!(
            check_request(&r, &slot("anna"), 42),
            Err(RequestError::PuzzleUnsolved)
        );
    }

    /// Обрезанное обращение не разбирается — эфемерный ключ обязателен.
    #[test]
    fn truncated_request_refused() {
        let full = req(1).sealed_body();
        for cut in 0..=45 {
            assert!(
                NameRequest::parse_sealed(&full[..cut.min(full.len())]).is_err(),
                "обрезка {cut}"
            );
        }
    }
}

// ── Приёмка слоя (чек-лист, этап G) ─────────────────────────────────────────────

/// Что наблюдатель цепи видит от слоя имён: ТОЛЬКО факт якорения пачки.
/// Функция существует затем, чтобы это утверждение было проверяемым, а не декларативным.
pub struct ChainVisible {
    pub app_id: [u8; 32],
    pub batch_root: [u8; 32],
}

/// Собрать то, что уходит в цепь. Ни имени, ни ячейки, ни якоря здесь нет — и тест ниже
/// проверяет это перебором по байтам, а не доверием к формулировке.
pub fn chain_visible(objects: &[Vec<u8>]) -> ChainVisible {
    ChainVisible {
        app_id: app_id(),
        batch_root: batch_root(objects),
    }
}

#[cfg(test)]
mod acceptance_tests {
    use super::*;

    /// G-42: два устройства из одной сид-фразы дают одинаковые ячейку, цепь и якорь.
    #[test]
    fn two_devices_from_one_seed_agree() {
        let seed = [0x11u8; 64];
        let name = "alicemontana";
        let (s1, c1) = {
            let s = slot(&normalize(name).unwrap());
            (s, chain(&name_own(&seed, &s)))
        };
        let (s2, c2) = {
            let s = slot(&normalize("AliceMontana").unwrap()); // другая запись того же имени
            (s, chain(&name_own(&seed, &s)))
        };
        assert_eq!(s1, s2);
        assert_eq!(anchor(&c1), anchor(&c2));
        assert_eq!(c1, c2);
    }

    /// G-43: освобождённое имя берёт следующий, и его цепь ДРУГАЯ — прежний владелец
    /// не сохраняет над ячейкой никакой власти.
    #[test]
    fn released_name_taken_by_next_owner() {
        let s = slot("alicemontana");
        let first = chain(&name_own(&[1u8; 64], &s));
        let second = chain(&name_own(&[2u8; 64], &s));
        assert_ne!(anchor(&first), anchor(&second));
        // звенья прежнего владельца не проходят проверку против нового якоря
        assert!(!verify_ownership(&anchor(&second), &first[1..3]));
        // и ячейка свободна по времени
        let last = 5_000u32;
        assert!(is_free(last, last + NAME_RENEW_WINDOWS + 1));
    }

    /// G-44: наблюдатель цепи видит только факт якорения. Проверяется ПЕРЕБОРОМ: ни ячейка,
    /// ни якорь, ни имя не встречаются в том, что уходит в цепь.
    #[test]
    fn chain_observer_sees_only_the_fact() {
        let s = slot("anna");
        let c = chain(&[0xCD; 32]);
        let objs = vec![
            NameCommit {
                commit: commit(&s, &anchor(&c), &[7; 32]),
            }
            .encode(),
            NameRenew {
                slot: s,
                step: 1,
                link: c[1],
            }
            .encode(),
        ];
        let v = chain_visible(&objs);
        let mut wire = v.app_id.to_vec();
        wire.extend_from_slice(&v.batch_root);
        assert!(!wire.windows(32).any(|w| w == s), "ячейка видна в цепи");
        assert!(
            !wire.windows(32).any(|w| w == anchor(&c)),
            "якорь виден в цепи"
        );
        assert!(!wire.windows(4).any(|w| w == b"anna"), "имя видно в цепи");
        assert_eq!(wire.len(), 64, "в цепь уходят ровно app_id и корень пачки");
    }

    /// G-44 продолжение: раскрытие СОДЕРЖИТ ячейку и якорь — и это правильно, потому что
    /// раскрытие идёт в цепь именно затем, чтобы владение стало проверяемым. Тест фиксирует
    /// границу: непрозрачна фиксация, а не раскрытие, и путать их нельзя.
    #[test]
    fn reveal_is_open_by_design() {
        let s = slot("anna");
        let c = chain(&[0xCD; 32]);
        let r = NameReveal {
            slot: s,
            anchor: anchor(&c),
            nonce: [7; 32],
            commit_win: 5,
        };
        let wire = r.encode();
        assert!(wire.windows(32).any(|w| w == s));
        assert!(wire.windows(32).any(|w| w == anchor(&c)));
        // но ИМЕНИ нет и в раскрытии — в цепь имя не попадает никогда
        assert!(!wire.windows(4).any(|w| w == b"anna"));
    }
}
