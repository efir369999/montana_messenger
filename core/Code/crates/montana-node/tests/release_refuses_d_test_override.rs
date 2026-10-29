// issue #17 K5: --d-test-override is a test-only lever on D. A release binary refuses it
// before it reads anything from disk, so no production node runs on an overridden D.
// Run under `cargo test --release` to exercise the release refusal.

use std::fs;
use std::path::PathBuf;
use std::process::Command;

use montana_node::commands::start::{run, StartArgs};

const REFUSAL: &str = "--d-test-override is refused in a release build";

#[test]
fn a_release_build_refuses_the_d_test_override() {
    let dir = tempdir();
    let out = Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["start", "--data-dir"])
        .arg(&dir)
        .args(["--d-test-override", "1", "--max-windows", "1"])
        // Both branches read the refusal text, shown only with private diagnostics on.
        .env("MONTANA_PRIVATE_DIAGNOSTICS", "1")
        .output()
        .expect("spawn montana-node");
    let stderr = String::from_utf8_lossy(&out.stderr);
    if cfg!(debug_assertions) {
        // A debug/test build keeps the lever; the start stops later (no manifest).
        assert!(!stderr.contains(REFUSAL), "debug build refused: {stderr}");
    } else {
        // Rejects a release binary that accepts the flag and goes on to load the store.
        assert_eq!(out.status.code(), Some(1), "stderr: {stderr}");
        assert!(stderr.contains(REFUSAL), "release build accepted: {stderr}");
        assert!(
            !dir.join("accounts.bin").exists(),
            "release build touched the store"
        );
    }
}

#[test]
fn the_library_entry_refuses_the_d_test_override_in_release() {
    // Rejects a release start::run that takes the override from a caller around the CLI.
    let dir = tempdir();
    let err = run(StartArgs {
        data_dir: Some(dir.clone()),
        max_windows: Some(0),
        d_test_override: Some(1),
        listen_multiaddr: None,
        genesis_manifest: None,
        enable_candidate: false,
        enable_names: false,
        open: true,
    })
    .expect_err("this start has no manifest and is refused in every build");
    let said = format!("{err:?}");
    if cfg!(debug_assertions) {
        assert!(!said.contains(REFUSAL), "debug build refused: {said}");
    } else {
        assert!(
            said.contains(REFUSAL),
            "release start::run accepted: {said}"
        );
    }
    assert!(!dir.join("accounts.bin").exists(), "the store was touched");
}

fn tempdir() -> PathBuf {
    let mut p = std::env::temp_dir();
    let mut nonce = [0u8; 8];
    getrandom::getrandom(&mut nonce).unwrap();
    p.push(format!(
        "montana-node-k5-{:016x}",
        u64::from_le_bytes(nonce)
    ));
    fs::create_dir_all(&p).unwrap();
    p
}
