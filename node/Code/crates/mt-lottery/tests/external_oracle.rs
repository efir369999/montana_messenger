// External SHA-256 oracle cross-check для mt-lottery composite hashes.
// Pass 25 (Independent Oracle / Differential Check) per CRITIC.md.
//
// Текущие unit tests cross-check `domain::X` constants против литералов
// `b"mt-X"` через SAME Rust SHA-256 implementation (sha2 crate via
// mt-crypto). Это circular validation — обе стороны равенства идут от
// одной реализации.
//
// Этот test cross-checks output mt-crypto::hash() против hardcoded hex
// digests computed via Python `hashlib.sha256` (CPython OpenSSL binding) —
// независимая reference implementation. Mismatch = либо Rust impl drift,
// либо Python impl drift (extremely unlikely для standard primitive),
// либо domain registry changed без oracle update.
//
// Reproduce oracle outputs:
//   python3 scripts/oracle_python_sha256.py
//
// При изменении доменов / formula / NUL pattern — обновить oracle script
// и эти hardcoded values в одном commit.

use mt_lottery::compute_endpoint;
use mt_state::NodeId;

fn fixed(byte: u8, len: usize) -> Vec<u8> {
    vec![byte; len]
}

#[test]
fn oracle_compute_endpoint_matches_python_hashlib() {
    // Inputs: t_r = [0x11; 32], cba = [0x22; 32], node_id = [0x33; 32], w = 7.
    let t_r: [u8; 32] = fixed(0x11, 32).try_into().unwrap();
    let cba: [u8; 32] = fixed(0x22, 32).try_into().unwrap();
    let node_id: NodeId = fixed(0x33, 32).try_into().unwrap();
    let w: u64 = 7;

    // Expected from python3 scripts/oracle_python_sha256.py (spec v33.1.5+
    // window_index u64 LE 8B, был u32 LE 4B до v33.1.5):
    //   compute_endpoint(t_r=11..,cba=22..,node_id=33..,w=7)
    //   = c9845c571dc52459c433aa6df1d16f9456ec526195105972a671eb172866751a
    let expected_hex = "c9845c571dc52459c433aa6df1d16f9456ec526195105972a671eb172866751a";
    let expected: [u8; 32] = hex_to_bytes(expected_hex);

    let actual = compute_endpoint(&t_r, &cba, &node_id, w);
    assert_eq!(
        actual,
        expected,
        "compute_endpoint output расходится с Python hashlib oracle.\n\
         Ожидалось: {}\n\
         Получено:  {}\n\
         Если изменения intentional — обновить oracle script и hex.",
        expected_hex,
        bytes_to_hex(&actual)
    );
}

fn hex_to_bytes(s: &str) -> [u8; 32] {
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).expect("invalid hex");
    }
    out
}

fn bytes_to_hex(b: &[u8; 32]) -> String {
    let mut s = String::with_capacity(64);
    for byte in b.iter() {
        s.push_str(&format!("{byte:02x}"));
    }
    s
}
