// External SHA-256 oracle cross-check для mt-entry composite hashes.
// Pass 25 (Independent Oracle / Differential Check) per CRITIC.md.
//
// Cross-checks output mt-crypto::hash() (через mt-codec::domain) против
// hardcoded hex digests computed via Python `hashlib.sha256` —
// независимая reference implementation. См. scripts/oracle_python_sha256.py.

use mt_crypto::PUBLIC_KEY_SIZE;
use mt_entry::{candidate_ssha_init, nr_sort_key, selection_sort_key};
use mt_state::NodeId;

fn fixed(byte: u8, len: usize) -> Vec<u8> {
    vec![byte; len]
}

#[test]
fn oracle_candidate_ssha_init_matches_python_hashlib() {
    // Inputs: t_r = [0x11; 32], cba = [0x22; 32], node_id = [0x33; 32]
    let t_r: [u8; 32] = fixed(0x11, 32).try_into().unwrap();
    let cba: [u8; 32] = fixed(0x22, 32).try_into().unwrap();
    let node_id: NodeId = fixed(0x33, 32).try_into().unwrap();

    // Expected from python3 scripts/oracle_python_sha256.py:
    //   candidate_ssha_init(t_r=11..,cba=22..,node_id=33..)
    //   = c4d3e9758eb3f4fb4d9438495377f514b37600b75eee2be1d77baafa0f2f2915
    let expected_hex = "c4d3e9758eb3f4fb4d9438495377f514b37600b75eee2be1d77baafa0f2f2915";
    let expected = hex_to_bytes(expected_hex);

    let actual = candidate_ssha_init(&t_r, &cba, &node_id);
    assert_eq!(
        actual, expected,
        "candidate_ssha_init output расходится с Python hashlib oracle"
    );
}

#[test]
fn oracle_selection_sort_key_matches_python_hashlib() {
    let t_r: [u8; 32] = fixed(0x11, 32).try_into().unwrap();
    let cba: [u8; 32] = fixed(0x22, 32).try_into().unwrap();
    let node_id: NodeId = fixed(0x33, 32).try_into().unwrap();

    // Expected: 05f1da48cd21230d56a1c39b0fdf95d26d0f888f317a21ceab4a1bf320d287e6
    let expected_hex = "05f1da48cd21230d56a1c39b0fdf95d26d0f888f317a21ceab4a1bf320d287e6";
    let expected = hex_to_bytes(expected_hex);

    let actual = selection_sort_key(&t_r, &cba, &node_id);
    assert_eq!(
        actual, expected,
        "selection_sort_key output расходится с Python hashlib oracle"
    );
}

#[test]
fn oracle_nr_sort_key_matches_python_hashlib() {
    let t_r: [u8; 32] = fixed(0x11, 32).try_into().unwrap();
    let cba: [u8; 32] = fixed(0x22, 32).try_into().unwrap();
    let pubkey: [u8; PUBLIC_KEY_SIZE] = {
        let mut p = [0u8; PUBLIC_KEY_SIZE];
        p.iter_mut().for_each(|b| *b = 0x33);
        p
    };

    // Expected: 16d95f1d0f220f64a8448f1732ebb1adce639c93f48f53de6c5c7e0ad4b34e30
    let expected_hex = "16d95f1d0f220f64a8448f1732ebb1adce639c93f48f53de6c5c7e0ad4b34e30";
    let expected = hex_to_bytes(expected_hex);

    let actual = nr_sort_key(&t_r, &cba, &pubkey);
    assert_eq!(
        actual, expected,
        "nr_sort_key output расходится с Python hashlib oracle"
    );
}

fn hex_to_bytes(s: &str) -> [u8; 32] {
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).expect("invalid hex");
    }
    out
}
