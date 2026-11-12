//! Run of the frozen vectors of the names layer (checklist, stage B, steps 11-13).
//!
//! The vectors were computed by an INDEPENDENT implementation and live in fixtures/name_vectors.json.
//! Their purpose is to catch a foreign implementation diverging here, not on the live network.
//! The json is parsed by hand, without serializers: one dependency per test is not needed,
//! and the format is our own and simple.

use mt_names::*;

const RAW: &str = include_str!("fixtures/name_vectors.json");

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}
fn unhex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("hexadecimal string"))
        .collect()
}
fn arr32(s: &str) -> [u8; 32] {
    let v = unhex(s);
    let mut o = [0u8; 32];
    o.copy_from_slice(&v);
    o
}

/// Minimal parsing: values are looked up by key within a single object.
/// The file is ours and its shape is known -- building a dependency for this is not needed.
fn objects(section: &str) -> Vec<String> {
    let start = RAW
        .find(&format!("\"{section}\""))
        .unwrap_or_else(|| panic!("section {section} is missing"));
    let tail = &RAW[start..];
    let mut out = Vec::new();
    let mut depth = 0usize;
    let mut cur = String::new();
    // A section is either an array of objects or a single object. In the second case the parsing must
    // stop after the first object: otherwise it keeps counting brackets of the whole file and goes
    // negative in depth -- the test failed exactly that way.
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
        "too few normalisation vectors: {}",
        objs.len()
    );
    for o in objs {
        let input = field(&o, "in").expect("in");
        match (field(&o, "out"), field(&o, "err")) {
            (Some(want), None) => assert_eq!(
                normalize(&input).as_deref(),
                Ok(want.as_str()),
                "input {input:?}"
            ),
            (None, Some(err)) => {
                let got = normalize(&input).unwrap_err();
                assert_eq!(format!("{got:?}"), err, "input {input:?}");
            },
            _ => panic!("vector {o} has neither out nor err"),
        }
    }
}

#[test]
fn slot_vectors() {
    let objs = objects("slot");
    assert!(
        !objs.is_empty(),
        "section slot is empty -- the test would pass without checking anything"
    );
    for o in objs {
        let name = field(&o, "name").expect("name");
        let want = field(&o, "slot").expect("slot");
        assert_eq!(hex(&slot(&name)), want, "name {name}");
    }
}

#[test]
fn name_own_vectors() {
    let objs = objects("name_own");
    assert!(
        !objs.is_empty(),
        "section name_own is empty -- the test would pass without checking anything"
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
        "section commit is empty -- the test would pass without checking anything"
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
        let iter: u32 = field(&o, "iter").expect("iter").parse().expect("number");
        if iter != NAME_KDF_ITER {
            continue; // the public function computes only with the production iteration count
        }
        let name = field(&o, "name").expect("name");
        let eph = unhex(&field(&o, "eph").expect("eph"));
        let want = field(&o, "key").expect("key");
        assert_eq!(hex(&req_key(&name, &eph, &slot(&name))), want);
        checked += 1;
    }
    assert!(
        checked > 0,
        "no lookup-key vector was checked -- there was nothing to compare"
    );
}

#[test]
fn puzzle_vectors() {
    let objs = objects("puzzle");
    assert!(
        !objs.is_empty(),
        "section puzzle is empty -- the test would pass without checking anything"
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
        "section bucket_bits is empty -- the test would pass without checking anything"
    );
    for o in objs {
        let occ: u64 = field(&o, "occupied")
            .expect("occupied")
            .parse()
            .expect("number");
        let bits: u32 = field(&o, "bits").expect("bits").parse().expect("number");
        assert_eq!(bucket_bits(occ), bits, "occupied {occ}");
    }
}

/// Values recorded in the set itself. A divergence here means our implementation will not
/// converge with a foreign one: one name would give two slots, and instead of one network two similar ones would emerge.
#[test]
fn canon_vectors() {
    let o = &objects("canon")[0];
    let name = field(o, "name").expect("name");
    let own = arr32(&field(o, "name_own").expect("name_own"));
    let blind = arr32(&field(o, "blind").expect("blind"));
    let sl = slot(&name);
    assert_eq!(hex(&sl), field(o, "slot").expect("slot"), "slot");
    let c = chain(&own);
    assert_eq!(
        hex(&c[127]),
        field(o, "link_127").expect("link_127"),
        "link 127"
    );
    assert_eq!(hex(&anchor(&c)), field(o, "anchor").expect("anchor"), "tip");
    assert!(
        verify_link(&anchor(&c), &c[1]),
        "the tip is the hash of the first link"
    );
    assert_eq!(
        hex(&commit(&sl, &blind, &anchor(&c))),
        field(o, "commit").expect("commit"),
        "commitment"
    );
}

/// G-46: the names layer does not touch the network in a single line. The check is mechanical, over its own
/// source: a claim "there is no network" without a failing check is a claim, not a property.
/// The first-contact tag -- values of the set itself. It is the door to the name: a divergence here
/// means that a stranger following the set will knock where the holder is not listening.
#[test]
fn canon_first_contact_vectors() {
    let o = &objects("canon_first_contact")[0];
    let root = unhex(&field(o, "contact_root").expect("contact_root"));
    assert_eq!(root.len(), 1184, "ML-KEM-768 is 1184 bytes");
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
            "network access found in the names layer: {needle}"
        );
    }
}

/// G-45: section IX of the spec "What is publicly visible" lists exactly what goes to the chain.
/// Pinned here by number: the chain receives app_id and the batch root, and nothing else.
#[test]
fn chain_payload_is_two_hashes() {
    let objs = vec![NameCommit { commit: [1; 32] }.encode()];
    let v = chain_visible(&objs);
    assert_eq!(v.app_id.len() + v.batch_root.len(), 64);
}
