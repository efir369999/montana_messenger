// issue #17 K5: the single mode without a manifest is dropped. A node that is not
// given --listen and --genesis-manifest does not start, in any build, and reads
// neither its identity nor its store.

use std::fs;
use std::path::PathBuf;
use std::process::Command;

use montana_node::commands::start::{run, StartArgs, NO_MANIFEST_REFUSED};
use montana_node::NodeError;

const REFUSAL: &str = "there is no single mode without a manifest";

fn start_cli(extra: &[&str]) -> (Option<i32>, String) {
    let dir = tempdir();
    let out = Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["start", "--data-dir"])
        .arg(&dir)
        .args(extra)
        // The refusal is read with private diagnostics on; by default start prints only "node start failed".
        .env("MONTANA_PRIVATE_DIAGNOSTICS", "1")
        .output()
        .expect("spawn montana-node");
    (
        out.status.code(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn a_start_without_listen_and_manifest_is_refused() {
    // Rejects the old single mode, which went on to load the store and self-admit.
    let (code, stderr) = start_cli(&["--max-windows", "1"]);
    assert_eq!(code, Some(1), "stderr: {stderr}");
    assert!(stderr.contains(REFUSAL), "single mode started: {stderr}");
}

#[test]
fn a_start_with_listen_but_no_manifest_is_refused() {
    let (code, stderr) = start_cli(&["--listen", "/ip4/127.0.0.1/tcp/0"]);
    assert_eq!(code, Some(1), "stderr: {stderr}");
    assert!(stderr.contains(REFUSAL), "stderr: {stderr}");
}

#[test]
fn the_library_entry_refuses_a_start_without_a_manifest() {
    // Rejects a caller of the library that bypasses the CLI parser.
    let dir = tempdir();
    let err = run(StartArgs {
        data_dir: Some(dir.clone()),
        max_windows: Some(1),
        d_test_override: None,
        listen_multiaddr: None,
        genesis_manifest: None,
        enable_candidate: false,
        enable_names: false,
        open: true,
    })
    .expect_err("a start without a manifest must be refused");
    assert!(
        matches!(&err, NodeError::InvalidArguments(m) if m == NO_MANIFEST_REFUSED),
        "{err:?}"
    );
    assert!(NO_MANIFEST_REFUSED.contains(REFUSAL));
    assert!(!dir.join("accounts.bin").exists(), "the store was touched");
}

fn tempdir() -> PathBuf {
    let mut p = std::env::temp_dir();
    let mut nonce = [0u8; 8];
    getrandom::getrandom(&mut nonce).unwrap();
    p.push(format!(
        "montana-node-k5m-{:016x}",
        u64::from_le_bytes(nonce)
    ));
    fs::create_dir_all(&p).unwrap();
    p
}
