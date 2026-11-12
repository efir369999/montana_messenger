// PANIC-OK for the whole of this module: what it reads are the fixtures of the published
// standards, which travel with this tree and are no input anyone sends. A fixture that does not
// parse is a tree assembled wrongly, and the loudest possible answer is the right one.
//
// The published known-answer values, read out of the fixtures beside this code rather than
// restated here: a vector written twice is a vector that can drift, and what these check is
// precisely that the code has not drifted from its standard. Each fixture names its source in
// its own first lines.
//
// The parser is one for all of them: blocks opened by `[name]`, each holding `field = value`
// lines with values in hex.

fn parse_blocks(text: &str) -> Vec<(String, Vec<(String, String)>)> {
    let mut out: Vec<(String, Vec<(String, String)>)> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            out.push((name.to_string(), Vec::new()));
        } else if let Some((field, value)) = line.split_once('=') {
            let Some(block) = out.last_mut() else {
                continue;
            };
            block
                .1
                .push((field.trim().to_string(), value.trim().to_string()));
        }
    }
    out
}

fn field<'a>(rows: &'a [(String, String)], name: &str) -> &'a str {
    rows.iter()
        .find(|(f, _)| f == name)
        .map(|(_, v)| v.as_str())
        .unwrap_or_else(|| panic!("the fixture names no {name}"))
}

fn bytes(rows: &[(String, String)], name: &str) -> Vec<u8> {
    let text = field(rows, name);
    if text.is_empty() {
        return Vec::new();
    }
    assert!(
        text.len().is_multiple_of(2) && text.bytes().all(|b| b.is_ascii_hexdigit()),
        "the value of {name} is not hex"
    );
    (0..text.len() / 2)
        .map(|i| u8::from_str_radix(&text[2 * i..2 * i + 2], 16).expect("hex"))
        .collect()
}

fn id(rows: &[(String, String)]) -> u32 {
    field(rows, "tcId").parse().expect("a numeric tcId")
}

const MLDSA65: &str = include_str!("../tests/fixtures/mldsa65_acvp.txt");
const MLKEM768: &str = include_str!("../tests/fixtures/mlkem768_acvp.txt");
const RFC8439: &str = include_str!("../tests/fixtures/chacha20poly1305_rfc8439.txt");

pub struct DsaKeyGen {
    pub id: u32,
    pub seed: Vec<u8>,
    pub pk: Vec<u8>,
    pub sk: Vec<u8>,
}

pub struct DsaSigGen {
    pub id: u32,
    pub sk: Vec<u8>,
    pub message: Vec<u8>,
    // The standard's own domain separator for a signature. The protocol fixes it empty; the
    // fixture carries what the published case carries, so the primitive is checked as the
    // standard defines it and not only in the one shape we use.
    pub context: Vec<u8>,
    pub pk: Vec<u8>,
    pub signature: Vec<u8>,
}

pub struct KemKeyGen {
    pub id: u32,
    pub d: Vec<u8>,
    pub z: Vec<u8>,
    pub ek: Vec<u8>,
    pub dk: Vec<u8>,
}

pub struct KemEncaps {
    pub id: u32,
    pub ek: Vec<u8>,
    pub m: Vec<u8>,
    pub c: Vec<u8>,
    pub k: Vec<u8>,
}

pub struct KemDecaps {
    pub id: u32,
    pub dk: Vec<u8>,
    pub c: Vec<u8>,
    pub k: Vec<u8>,
}

pub struct AeadCase {
    pub key: [u8; 32],
    pub nonce: [u8; 12],
    pub associated: Vec<u8>,
    pub plaintext: Vec<u8>,
    pub ciphertext: Vec<u8>,
    pub tag: Vec<u8>,
}

fn blocks_named(text: &str, name: &str) -> Vec<Vec<(String, String)>> {
    parse_blocks(text)
        .into_iter()
        .filter(|(n, _)| n == name)
        .map(|(_, rows)| rows)
        .collect()
}

pub fn mldsa65_keygen() -> Vec<DsaKeyGen> {
    blocks_named(MLDSA65, "keygen")
        .iter()
        .map(|rows| DsaKeyGen {
            id: id(rows),
            seed: bytes(rows, "seed"),
            pk: bytes(rows, "pk"),
            sk: bytes(rows, "sk"),
        })
        .collect()
}

pub fn mldsa65_siggen() -> Vec<DsaSigGen> {
    blocks_named(MLDSA65, "siggen")
        .iter()
        .map(|rows| DsaSigGen {
            id: id(rows),
            sk: bytes(rows, "sk"),
            message: bytes(rows, "message"),
            context: bytes(rows, "context"),
            pk: bytes(rows, "pk"),
            signature: bytes(rows, "signature"),
        })
        .collect()
}

pub fn mlkem768_keygen() -> Vec<KemKeyGen> {
    blocks_named(MLKEM768, "keygen")
        .iter()
        .map(|rows| KemKeyGen {
            id: id(rows),
            d: bytes(rows, "d"),
            z: bytes(rows, "z"),
            ek: bytes(rows, "ek"),
            dk: bytes(rows, "dk"),
        })
        .collect()
}

pub fn mlkem768_encaps() -> Vec<KemEncaps> {
    blocks_named(MLKEM768, "encaps")
        .iter()
        .map(|rows| KemEncaps {
            id: id(rows),
            ek: bytes(rows, "ek"),
            m: bytes(rows, "m"),
            c: bytes(rows, "c"),
            k: bytes(rows, "k"),
        })
        .collect()
}

pub fn mlkem768_decaps() -> Vec<KemDecaps> {
    blocks_named(MLKEM768, "decaps")
        .iter()
        .map(|rows| KemDecaps {
            id: id(rows),
            dk: bytes(rows, "dk"),
            c: bytes(rows, "c"),
            k: bytes(rows, "k"),
        })
        .collect()
}

pub fn rfc8439_aead() -> AeadCase {
    let rows = blocks_named(RFC8439, "aead")
        .into_iter()
        .next()
        .expect("the fixture holds the worked example");
    AeadCase {
        key: bytes(&rows, "key").try_into().expect("a key of 32 bytes"),
        nonce: bytes(&rows, "nonce")
            .try_into()
            .expect("a nonce of 12 bytes"),
        associated: bytes(&rows, "aad"),
        plaintext: bytes(&rows, "plaintext"),
        ciphertext: bytes(&rows, "ciphertext"),
        tag: bytes(&rows, "tag"),
    }
}
