use std::fs;
use std::path::PathBuf;

use montana_node::commands::init::{run as init_run, InitArgs};
use montana_node::commands::inspect::{run as inspect_run, InspectArgs};
use montana_node::{identity_path, load_identity, IDENTITY_FILE_SIZE};

// The tests' entropy passes the core health checks: a degenerate block
// (00×32, 11×32) is rejected by construction and cannot become an identity.
const HEALTHY_ENTROPY_A: &str = "9a1f03b72cd455e8117fa03648c25de10b93712abc4e68d7153982f46a0cd357";
const HEALTHY_ENTROPY_B: &str = "2b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfe";

#[test]
fn init_with_fixed_entropy_is_byte_exact_deterministic() {
    let dir_a = tempdir();
    let dir_b = tempdir();

    init_run(InitArgs {
        data_dir: Some(dir_a.clone()),
        mnemonic: None,
        entropy_hex: Some(HEALTHY_ENTROPY_A.to_string()),
        force: false,
    })
    .expect("init A");

    init_run(InitArgs {
        data_dir: Some(dir_b.clone()),
        mnemonic: None,
        entropy_hex: Some(HEALTHY_ENTROPY_A.to_string()),
        force: false,
    })
    .expect("init B");

    let bytes_a = fs::read(identity_path(&dir_a)).unwrap();
    let bytes_b = fs::read(identity_path(&dir_b)).unwrap();
    assert_eq!(bytes_a.len(), IDENTITY_FILE_SIZE);
    assert_eq!(
        bytes_a, bytes_b,
        "the same entropy must give a byte-for-byte identical identity.bin"
    );
}

#[test]
fn init_then_inspect_terminal_ids_match() {
    let dir = tempdir();
    init_run(InitArgs {
        data_dir: Some(dir.clone()),
        mnemonic: None,
        entropy_hex: Some(
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".into(),
        ),
        force: false,
    })
    .expect("init");

    let id = load_identity(&dir).expect("load");
    let acc = id.account_id();
    let node = id.node_id();
    assert_ne!(acc, [0u8; 32]);
    assert_ne!(node, [0u8; 32]);
    assert_ne!(acc, node);

    inspect_run(InspectArgs {
        data_dir: Some(dir),
        reveal_master_seed: false,
        export_pubkeys: false,
    })
    .expect("inspect");
}

#[test]
fn init_refuses_overwrite_without_force() {
    let dir = tempdir();
    init_run(InitArgs {
        data_dir: Some(dir.clone()),
        mnemonic: None,
        entropy_hex: Some(HEALTHY_ENTROPY_A.to_string()),
        force: false,
    })
    .expect("first init");

    let err = init_run(InitArgs {
        data_dir: Some(dir.clone()),
        mnemonic: None,
        entropy_hex: Some(HEALTHY_ENTROPY_B.to_string()),
        force: false,
    })
    .unwrap_err();
    let msg = format!("{err}");
    assert!(
        msg.contains("identity.bin already exists"),
        "expected a refusal because of the existing file, got: {msg}"
    );

    init_run(InitArgs {
        data_dir: Some(dir),
        mnemonic: None,
        entropy_hex: Some(HEALTHY_ENTROPY_B.to_string()),
        force: true,
    })
    .expect("force overwrite");
}

#[test]
fn init_rejects_both_mnemonic_and_entropy() {
    let dir = tempdir();
    let err = init_run(InitArgs {
        data_dir: Some(dir),
        mnemonic: Some("abandon ".repeat(23) + "art"),
        entropy_hex: Some(HEALTHY_ENTROPY_A.to_string()),
        force: false,
    })
    .unwrap_err();
    let msg = format!("{err}");
    assert!(msg.contains("--mnemonic") && msg.contains("--entropy"));
}

#[test]
fn mnemonic_input_recovers_same_identity_as_its_entropy() {
    let entropy_hex = HEALTHY_ENTROPY_A.to_string();
    let mut entropy = [0u8; 32];
    for (i, b) in entropy.iter_mut().enumerate() {
        *b = u8::from_str_radix(&HEALTHY_ENTROPY_A[i * 2..i * 2 + 2], 16).unwrap();
    }
    let mnemonic = mt_mnemonic::entropy_to_mnemonic(&entropy);

    let dir_e = tempdir();
    init_run(InitArgs {
        data_dir: Some(dir_e.clone()),
        mnemonic: None,
        entropy_hex: Some(entropy_hex),
        force: false,
    })
    .expect("init from entropy");

    let dir_m = tempdir();
    init_run(InitArgs {
        data_dir: Some(dir_m.clone()),
        mnemonic: Some(mnemonic),
        entropy_hex: None,
        force: false,
    })
    .expect("init from mnemonic");

    let id_e = load_identity(&dir_e).unwrap();
    let id_m = load_identity(&dir_m).unwrap();
    assert_eq!(id_e.master_seed, id_m.master_seed);
    assert_eq!(id_e.account_id(), id_m.account_id());
    assert_eq!(id_e.node_id(), id_m.node_id());
}

fn tempdir() -> PathBuf {
    let mut p = std::env::temp_dir();
    let mut nonce = [0u8; 8];
    getrandom::getrandom(&mut nonce).unwrap();
    let n = u64::from_le_bytes(nonce);
    p.push(format!("montana-node-e2e-{n:016x}"));
    fs::create_dir_all(&p).unwrap();
    p
}

#[test]
fn degenerate_entropy_is_refused_by_the_node() {
    // An operator may submit a degenerate block by mistake or receive it from
    // a broken source; such a block never becomes an identity on any path.
    for hex in ["00".repeat(32), "ff".repeat(32), "aa55".repeat(16)] {
        let dir = tempdir();
        let err = init_run(InitArgs {
            data_dir: Some(dir.clone()),
            mnemonic: None,
            entropy_hex: Some(hex.clone()),
            force: false,
        });
        assert!(err.is_err(), "degenerate entropy accepted: {hex}");
        assert!(!identity_path(&dir).exists(), "identity written for {hex}");
    }
}
