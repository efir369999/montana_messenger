#![cfg(unix)]

use std::fs;
use std::io::Write;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};

const ENTROPY: [u8; 32] = [
    0x9a, 0x1f, 0x03, 0xb7, 0x2c, 0xd4, 0x55, 0xe8, 0x11, 0x7f, 0xa0, 0x36, 0x48, 0xc2, 0x5d, 0xe1,
    0x0b, 0x93, 0x71, 0x2a, 0xbc, 0x4e, 0x68, 0xd7, 0x15, 0x39, 0x82, 0xf4, 0x6a, 0x0c, 0xd3, 0x57,
];

fn directory() -> PathBuf {
    let mut nonce = [0u8; 8];
    getrandom::getrandom(&mut nonce).unwrap();
    let path = std::env::temp_dir().join(format!(
        "montana-private-init-{:016x}",
        u64::from_le_bytes(nonce)
    ));
    fs::create_dir(&path).unwrap();
    path
}

fn init(path: &std::path::Path, input: &str, extra: &[&str]) -> Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["init", "--mnemonic-stdin", "--data-dir"])
        .arg(path)
        .args(extra)
        .env_remove("MONTANA_PRIVATE_DIAGNOSTICS")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(format!("{input}\n").as_bytes())
        .unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn recovery_is_private_and_neither_output_stream_carries_it() {
    // Rejects the old stdout fallback and a file created with broad permissions.
    let path = directory();
    let phrase = mt_mnemonic::entropy_to_mnemonic(&ENTROPY);
    let out = init(&path, &phrase, &[]);
    assert!(out.status.success());
    assert!(!String::from_utf8_lossy(&out.stdout).contains(&phrase));
    assert!(!String::from_utf8_lossy(&out.stderr).contains(&phrase));
    assert!(!String::from_utf8_lossy(&out.stdout).contains("network_peer_id"));
    let recovery = path.join("mnemonic.txt");
    assert_eq!(
        fs::metadata(&recovery).unwrap().permissions().mode() & 0o777,
        0o400
    );
    assert_eq!(
        fs::read_to_string(&recovery).unwrap(),
        format!("{phrase}\n")
    );
    let saved = montana_node::load_identity(&path).unwrap();
    let restored = montana_node::Identity::from_mnemonic(&phrase).unwrap();
    assert_eq!(saved.node_id(), restored.node_id());
}

#[test]
fn existing_recovery_is_not_overwritten_even_with_force() {
    // Rejects force-overwriting recovery or replacing identity before recovery succeeds.
    let path = directory();
    fs::write(path.join("mnemonic.txt"), "TEST_RETAINED_RECOVERY").unwrap();
    fs::write(path.join("identity.bin"), b"TEST_RETAINED_IDENTITY").unwrap();
    let phrase = mt_mnemonic::entropy_to_mnemonic(&ENTROPY);
    let out = init(&path, &phrase, &["--force"]);
    assert!(!out.status.success());
    assert_eq!(
        fs::read_to_string(path.join("mnemonic.txt")).unwrap(),
        "TEST_RETAINED_RECOVERY"
    );
    assert_eq!(
        fs::read(path.join("identity.bin")).unwrap(),
        b"TEST_RETAINED_IDENTITY"
    );
    assert!(!String::from_utf8_lossy(&out.stderr).contains(&phrase));
}

#[test]
fn recovery_symlink_is_refused_before_identity_is_written() {
    // Rejects following a pre-existing symlink instead of exclusive creation.
    let path = directory();
    let target = path.join("retained");
    fs::write(&target, "TEST_RETAINED_TARGET").unwrap();
    symlink(&target, path.join("mnemonic.txt")).unwrap();
    let out = init(&path, &mt_mnemonic::entropy_to_mnemonic(&ENTROPY), &[]);
    assert!(!out.status.success());
    assert_eq!(fs::read_to_string(target).unwrap(), "TEST_RETAINED_TARGET");
    assert!(!path.join("identity.bin").exists());
}

#[test]
fn input_errors_do_not_echo_secret_or_arbitrary_argument_text() {
    // Rejects dependency errors or CLI parse errors that echo untrusted input.
    let path = directory();
    let marker = "TEST_PRIVATE_INPUT_MARKER";
    let out = init(&path, marker, &[]);
    assert!(!out.status.success());
    assert!(!String::from_utf8_lossy(&out.stdout).contains(marker));
    assert!(!String::from_utf8_lossy(&out.stderr).contains(marker));
    let out = Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["init", marker])
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(!String::from_utf8_lossy(&out.stderr).contains(marker));
}

#[test]
fn explicit_recovery_path_is_exclusive_and_used_for_the_new_identity() {
    // Rejects accepting the option but writing the phrase to the default sink.
    let path = directory();
    let recovery = path.join("selected-recovery.txt");
    let phrase = mt_mnemonic::entropy_to_mnemonic(&ENTROPY);
    let out = init(
        &path,
        &phrase,
        &["--recovery-file", recovery.to_str().unwrap()],
    );
    assert!(out.status.success());
    assert_eq!(
        fs::read_to_string(&recovery).unwrap(),
        format!("{phrase}\n")
    );
    assert!(!path.join("mnemonic.txt").exists());
    let out = init(
        &path,
        &phrase,
        &["--force", "--recovery-file", recovery.to_str().unwrap()],
    );
    assert!(!out.status.success());
}
