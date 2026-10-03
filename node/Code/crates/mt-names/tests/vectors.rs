//! Прогон замороженных векторов слоя имён (чек-лист, этап B, шаги 11-13).
//!
//! Векторы посчитаны НЕЗАВИСИМОЙ реализацией и лежат в fixtures/name_vectors.json.
//! Их назначение — ловить расхождение чужой реализации здесь, а не в живой сети.
//! Разбор json — вручную, без сериализаторов: одна зависимость на тест не нужна,
//! а формат наш собственный и простой.

use mt_names::*;

const RAW: &str = include_str!("fixtures/name_vectors.json");

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}
fn unhex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("шестнадцатеричная строка"))
        .collect()
}
fn arr32(s: &str) -> [u8; 32] {
    let v = unhex(s);
    let mut o = [0u8; 32];
    o.copy_from_slice(&v);
    o
}

/// Минимальный разбор: значения ищутся по ключу в пределах одного объекта.
/// Файл наш, форма его известна — городить зависимость ради этого не нужно.
fn objects(section: &str) -> Vec<String> {
    let start = RAW
        .find(&format!("\"{section}\""))
        .unwrap_or_else(|| panic!("раздел {section} отсутствует"));
    let tail = &RAW[start..];
    let mut out = Vec::new();
    let mut depth = 0usize;
    let mut cur = String::new();
    // Раздел бывает массивом объектов и одиночным объектом. Во втором случае разбор обязан
    // остановиться после первого объекта: иначе он продолжит считать скобки всего файла и уйдёт
    // в минус по глубине — тест падал именно так.
    let single = tail
        .chars()
        .find(|c| *c == '[' || *c == '{')
        .is_some_and(|c| c == '{');
    for ch in tail.chars().skip_while(|c| *c != '[' && *c != '{') {
        match ch {
            '{' => {
                depth += 1;
                if depth == 1 {
                    cur.clear();
                    continue;
                }
            },
            '}' => {
                depth -= 1;
                if depth == 0 {
                    out.push(cur.clone());
                    if single {
                        break;
                    }
                    continue;
                }
            },
            ']' if depth == 0 => break,
            _ => {},
        }
        if depth >= 1 {
            cur.push(ch);
        }
    }
    out
}
fn field(obj: &str, key: &str) -> Option<String> {
    let k = format!("\"{key}\"");
    let i = obj.find(&k)?;
    let rest = &obj[i + k.len()..];
    let colon = rest.find(':')?;
    let val = rest[colon + 1..].trim_start();
    if let Some(stripped) = val.strip_prefix('"') {
        let end = stripped.find('"')?;
        Some(stripped[..end].to_string())
    } else {
        let end = val.find([',', '\n', '}']).unwrap_or(val.len());
        Some(val[..end].trim().to_string())
    }
}

#[test]
fn normalize_vectors() {
    let objs = objects("normalize");
    assert!(
        objs.len() >= 10,
        "векторов нормализации мало: {}",
        objs.len()
    );
    for o in objs {
        let input = field(&o, "in").expect("in");
        match (field(&o, "out"), field(&o, "err")) {
            (Some(want), None) => assert_eq!(
                normalize(&input).as_deref(),
                Ok(want.as_str()),
                "вход {input:?}"
            ),
            (None, Some(err)) => {
                let got = normalize(&input).unwrap_err();
                assert_eq!(format!("{got:?}"), err, "вход {input:?}");
            },
            _ => panic!("вектор {o} не имеет ни out, ни err"),
        }
    }
}

#[test]
fn slot_vectors() {
    let objs = objects("slot");
    assert!(
        !objs.is_empty(),
        "раздел slot пуст — тест бы прошёл, ничего не проверив"
    );
    for o in objs {
        let name = field(&o, "name").expect("name");
        let want = field(&o, "slot").expect("slot");
        assert_eq!(hex(&slot(&name)), want, "имя {name}");
    }
}

#[test]
fn name_own_vectors() {
    let objs = objects("name_own");
    assert!(
        !objs.is_empty(),
        "раздел name_own пуст — тест бы прошёл, ничего не проверив"
    );
    for o in objs {
        let seed = unhex(&field(&o, "seed").expect("seed"));
        let sl = arr32(&field(&o, "slot").expect("slot"));
        let want = field(&o, "own").expect("own");
        assert_eq!(hex(&name_own(&seed, &sl)), want);
    }
}

#[test]
fn chain_vectors() {
    let o = &objects("chain")[0];
    let seed = unhex(&field(o, "seed").expect("seed"));
    let name = field(o, "name").expect("name");
    let c = chain(&name_own(&seed, &slot(&name)));
    assert_eq!(c.len().to_string(), field(o, "len").expect("len"));
    assert_eq!(hex(&anchor(&c)), field(o, "anchor").expect("anchor"));
    assert_eq!(hex(&c[1]), field(o, "link_1").expect("link_1"));
    assert_eq!(hex(&c[128]), field(o, "link_128").expect("link_128"));
}

#[test]
fn commit_vectors() {
    let objs = objects("commit");
    assert!(
        !objs.is_empty(),
        "раздел commit пуст — тест бы прошёл, ничего не проверив"
    );
    for o in objs {
        let s = arr32(&field(&o, "slot").expect("slot"));
        let b = arr32(&field(&o, "blind").expect("blind"));
        let t = arr32(&field(&o, "tip").expect("tip"));
        assert_eq!(
            hex(&commit(&s, &b, &t)),
            field(&o, "commit").expect("commit")
        );
    }
}

#[test]
fn req_key_vectors() {
    let mut checked = 0;
    for o in objects("req_key") {
        let iter: u32 = field(&o, "iter").expect("iter").parse().expect("число");
        if iter != NAME_KDF_ITER {
            continue; // открытая функция считает только с боевым числом итераций
        }
        let name = field(&o, "name").expect("name");
        let eph = unhex(&field(&o, "eph").expect("eph"));
        let want = field(&o, "key").expect("key");
        assert_eq!(hex(&req_key(&name, &eph, &slot(&name))), want);
        checked += 1;
    }
    assert!(
        checked > 0,
        "ни один вектор ключа обращения не проверен — сравнивать было нечего"
    );
}

#[test]
fn puzzle_vectors() {
    let objs = objects("puzzle");
    assert!(
        !objs.is_empty(),
        "раздел puzzle пуст — тест бы прошёл, ничего не проверив"
    );
    for o in objs {
        let s = arr32(&field(&o, "slot").expect("slot"));
        let eph = unhex(&field(&o, "eph").expect("eph"));
        let nonce = unhex(&field(&o, "nonce").expect("nonce"));
        assert_eq!(
            hex(&puzzle(&s, &eph, &nonce)),
            field(&o, "hash").expect("hash")
        );
    }
}

#[test]
fn bucket_vectors() {
    let objs = objects("bucket_bits");
    assert!(
        !objs.is_empty(),
        "раздел bucket_bits пуст — тест бы прошёл, ничего не проверив"
    );
    for o in objs {
        let occ: u64 = field(&o, "occupied")
            .expect("occupied")
            .parse()
            .expect("число");
        let bits: u32 = field(&o, "bits").expect("bits").parse().expect("число");
        assert_eq!(bucket_bits(occ), bits, "занято {occ}");
    }
}

/// Значения, записанные в самом наборе. Расхождение здесь означает, что наша реализация не
/// сойдётся с чужой: одно имя даст две ячейки, и вместо одной сети выйдут две похожие.
#[test]
fn canon_vectors() {
    let o = &objects("canon")[0];
    let name = field(o, "name").expect("name");
    let own = arr32(&field(o, "name_own").expect("name_own"));
    let blind = arr32(&field(o, "blind").expect("blind"));
    let sl = slot(&name);
    assert_eq!(hex(&sl), field(o, "slot").expect("slot"), "ячейка");
    let c = chain(&own);
    assert_eq!(
        hex(&c[127]),
        field(o, "link_127").expect("link_127"),
        "звено 127"
    );
    assert_eq!(hex(&anchor(&c)), field(o, "anchor").expect("anchor"), "вершина");
    assert!(
        verify_link(&anchor(&c), &c[1]),
        "вершина есть хеш первого звена"
    );
    assert_eq!(
        hex(&commit(&sl, &blind, &anchor(&c))),
        field(o, "commit").expect("commit"),
        "фиксация"
    );
}

/// G-46: слой имён не обращается к сети ни одной строкой. Проверка механическая, по своему же
/// исходнику: заявление «сети нет» без падающей проверки — это заявление, а не свойство.
/// Метка первого контакта — значения самого набора. Она и есть дверь к имени: расхождение здесь
/// означает, что незнакомец, идущий по набору, постучится не туда, куда слушает держатель.
#[test]
fn canon_first_contact_vectors() {
    let o = &objects("canon_first_contact")[0];
    let root = unhex(&field(o, "contact_root").expect("contact_root"));
    assert_eq!(root.len(), 1184, "ML-KEM-768 — 1184 байта");
    assert_eq!(
        hex(&first_tag(&root, 1000)),
        field(o, "first_tag_1000").expect("first_tag_1000")
    );
    assert_eq!(
        hex(&first_tag(&root, 1001)),
        field(o, "first_tag_1001").expect("first_tag_1001")
    );
}

#[test]
fn no_network_in_names_layer() {
    let src = include_str!("../src/lib.rs");
    for needle in [
        "reqwest",
        "TcpStream",
        "UdpSocket",
        "std::net",
        "http://",
        "https://",
    ] {
        assert!(
            !src.contains(needle),
            "в слое имён найдено обращение к сети: {needle}"
        );
    }
}

/// G-45: раздел IX спеки «Что публично видно» перечисляет ровно то, что уходит в цепь.
/// Здесь фиксируется числом: в цепь уходят app_id и корень пачки, и ничего больше.
#[test]
fn chain_payload_is_two_hashes() {
    let objs = vec![NameCommit { commit: [1; 32] }.encode()];
    let v = chain_visible(&objs);
    assert_eq!(v.app_id.len() + v.batch_root.len(), 64);
}
