// issue #17 K5, the author's decision 287: window zero of the earlier core opens only by the
// operator's explicit --open on a store holding nothing of a chain, on the operator's cohort --
// the machine the genesis manifest names as its bootstrap peer. Without --open an empty store
// does not start; there is no cold-start self-admission. Every refusal leaves the store as it
// was, byte for byte.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use montana_node::commands::init::{run as init_run, InitArgs};
use montana_node::commands::status::NO_RUNNING_HOLDER;
use montana_node::node_lifecycle::{load_or_init_lifecycle, NodePhase};
use montana_node::{load_identity, LocalState};

// What the binary says when it refuses, as an operator reads it with private diagnostics on
// (MONTANA_PRIVATE_DIAGNOSTICS=1); by default start prints only "node start failed".
const NO_ANCHOR_REFUSED: &str = "a machine with no anchor opens no window";
const OPENED_OVER_A_CHAIN: &str = "--open is refused on a store that holds a chain";
const OPENER_NOT_BOOTSTRAP: &str = "does not name this machine as its bootstrap peer";

const OPENER_ENTROPY: &str = "9a1f03b72cd455e8117fa03648c25de10b93712abc4e68d7153982f46a0cd357";
const OTHER_ENTROPY: &str = "2b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfe";

#[test]
fn an_empty_store_without_open_does_not_start() {
    // Rejects the old cold start, where a fresh machine started and self-admitted.
    let (dir, manifest) = machine(OPENER_ENTROPY, OPENER_ENTROPY);
    let before = files(&dir);
    let (code, stderr) = start(&dir, &manifest, &[]);
    assert_eq!(code, Some(1), "stderr: {stderr}");
    assert!(stderr.contains(NO_ANCHOR_REFUSED), "stderr: {stderr}");
    assert_eq!(files(&dir), before, "a refused start wrote to the store");
}

#[test]
fn open_on_an_empty_store_opens_window_zero_on_the_bootstrap_peer() {
    let (dir, manifest) = machine(OPENER_ENTROPY, OPENER_ENTROPY);
    let (code, stderr) = start(&dir, &manifest, &["--open"]);
    assert_eq!(code, Some(0), "stderr: {stderr}");

    // The opener stands in the Node Table from window zero and is Active.
    let identity = load_identity(&dir).expect("identity");
    let params = mt_genesis::genesis_params();
    let state = LocalState::load_or_bootstrap(&dir, &identity, params).expect("state");
    let record = state
        .nodes
        .get(&identity.node_id())
        .expect("the opener is admitted at window zero");
    assert_eq!(record.start_window, 0);
    assert_eq!(state.nodes.len(), 1, "window zero carries the cohort alone");
    assert!(
        state.candidates.is_empty(),
        "no candidate, no selection event"
    );
    let lifecycle = load_or_init_lifecycle(&dir, &identity, params).expect("lifecycle");
    assert_eq!(lifecycle.phase, NodePhase::Active);

    // A second --open is a second window zero of a network this store stands in.
    let opened = files(&dir);
    let (code, stderr) = start(&dir, &manifest, &["--open"]);
    assert_eq!(code, Some(1), "stderr: {stderr}");
    assert!(stderr.contains(OPENED_OVER_A_CHAIN), "stderr: {stderr}");
    assert_eq!(files(&dir), opened, "a refused --open wrote to the store");

    // Without --open the store holding a chain starts from it.
    let (code, stderr) = start(&dir, &manifest, &[]);
    assert_eq!(code, Some(0), "stderr: {stderr}");
}

#[test]
fn open_by_a_machine_the_manifest_does_not_name_is_refused() {
    // Rejects an opener that admits itself whatever the manifest names.
    let (dir, manifest) = machine(OTHER_ENTROPY, OPENER_ENTROPY);
    let before = files(&dir);
    let (code, stderr) = start(&dir, &manifest, &["--open"]);
    assert_eq!(code, Some(1), "stderr: {stderr}");
    assert!(stderr.contains(OPENER_NOT_BOOTSTRAP), "stderr: {stderr}");
    assert_eq!(files(&dir), before, "a refused --open wrote to the store");
}

// Issue #21 K4: status reports a running node from the records of its chain, or fails with
// `no diagnostics`, code 4 (the codes of the earlier core, the Author's decision (a)). Refuses the
// status before K4, which stood a default in for every missing record and exited 0 on a store
// holding nothing of a chain, and exited 0 on a store no node runs -- the Docker health check
// is its exit code (docker-compose.yml). A probe writes nothing, and a held store is not
// started a second time.
#[test]
fn status_fails_without_the_records_of_a_chain_or_a_running_holder() {
    let (dir, manifest) = machine(OPENER_ENTROPY, OPENER_ENTROPY);
    let (code, stderr) = status(&dir);
    assert_eq!(code, Some(4), "stderr: {stderr}");
    assert!(stderr.contains("is missing"), "stderr: {stderr}");

    let (code, stderr) = start(&dir, &manifest, &["--open"]);
    assert_eq!(code, Some(0), "stderr: {stderr}");
    let opened = files(&dir);
    let (code, stderr) = status(&dir);
    assert_eq!(code, Some(4), "stderr: {stderr}");
    assert!(stderr.contains(NO_RUNNING_HOLDER), "stderr: {stderr}");

    // Held as a running start holds it.
    let holder = montana_node::holder::hold(&dir).expect("the store is held");
    let (code, stderr) = status(&dir);
    assert_eq!(code, Some(0), "stderr: {stderr}");
    let (code, stderr) = start(&dir, &manifest, &[]);
    assert_eq!(code, Some(1), "a second start on a held store: {stderr}");
    assert_eq!(
        files(&dir),
        opened,
        "a probe or a refused start wrote to the store"
    );

    drop(holder);
    let (code, stderr) = status(&dir);
    assert_eq!(code, Some(4), "stderr: {stderr}");
    assert!(stderr.contains(NO_RUNNING_HOLDER), "stderr: {stderr}");
}

// Issue #21, the codes of the earlier core (the Author's decision (a), record 358): the exit code of
// status is the code of the node's reading -- 0 a closed window, 1 `no quorum`, 2 `no data` -- and
// 4 `no diagnostics` where this run has none. Refuses a status that exits 0 on a stall, gives two
// verdicts one code, reads an absent reading as success, or lets a run stand on the reading of an
// earlier one.
#[test]
fn status_exits_with_the_code_of_the_reading() {
    use montana_node::reading::{self, Lack, Reading};
    let (dir, manifest) = machine(OPENER_ENTROPY, OPENER_ENTROPY);
    let (code, stderr) = start(&dir, &manifest, &["--open"]);
    assert_eq!(code, Some(0), "stderr: {stderr}");
    // The opening of window zero is the first close of its run.
    assert_eq!(
        reading::read(&dir),
        Some(Reading::Closed {
            window: 0,
            refused: 0
        })
    );
    let holder = montana_node::holder::hold(&dir).expect("the store is held");
    let (code, stderr) = status(&dir);
    assert_eq!(code, Some(0), "stderr: {stderr}");
    for (on, code) in [(Lack::Quorum, 1), (Lack::Data, 2)] {
        let stalled = Reading::Stalled {
            on,
            window: 1,
            refused: 3,
        };
        reading::write(&dir, stalled).unwrap();
        let (got, stderr) = status(&dir);
        assert_eq!(got, Some(code), "stderr: {stderr}");
        assert!(stderr.contains(&stalled.to_string()), "stderr: {stderr}");
    }
    reading::clear(&dir).unwrap();
    let (code, stderr) = status(&dir);
    assert_eq!(code, Some(4), "stderr: {stderr}");
    assert!(stderr.contains("no diagnostics"), "stderr: {stderr}");

    // A start does not stand on the reading of an earlier run.
    drop(holder);
    let earlier = Reading::Closed {
        window: 99,
        refused: 9,
    };
    reading::write(&dir, earlier).unwrap();
    let (code, stderr) = start(&dir, &manifest, &[]);
    assert_eq!(code, Some(0), "stderr: {stderr}");
    assert_ne!(reading::read(&dir), Some(earlier));
}

fn status(dir: &Path) -> (Option<i32>, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["status", "--data-dir"])
        .arg(dir)
        .output()
        .expect("spawn montana-node");
    (
        out.status.code(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

// A data dir holding the identity of `entropy` and nothing of a chain, and a manifest whose
// bootstrap peer is the identity of `bootstrap`.
fn machine(entropy: &str, bootstrap: &str) -> (PathBuf, PathBuf) {
    let dir = tempdir();
    init_run(InitArgs {
        data_dir: Some(dir.clone()),
        mnemonic: None,
        entropy_hex: Some(entropy.to_string()),
        force: false,
        recovery_file: None,
    })
    .expect("init");
    let named = tempdir();
    init_run(InitArgs {
        data_dir: Some(named.clone()),
        mnemonic: None,
        entropy_hex: Some(bootstrap.to_string()),
        force: false,
        recovery_file: None,
    })
    .expect("init the named machine");
    let peer = load_identity(&named).expect("identity of the named machine");
    let peer_id = mt_net_transport::derive_peer_id(&peer.node_pk).expect("peer id");
    let manifest = dir.with_extension("manifest.json");
    fs::write(
        &manifest,
        format!(
            r#"{{"network_name":"k5-test","peers":[{{"label":"opener","multiaddr":"/ip4/127.0.0.1/tcp/9","peer_id":"{peer_id}","account_id_hex":"{a}","node_id_hex":"{n}","bootstrap":true}}]}}"#,
            a = hex(&peer.account_id()),
            n = hex(&peer.node_id()),
        ),
    )
    .unwrap();
    (dir, manifest)
}

fn start(dir: &Path, manifest: &Path, extra: &[&str]) -> (Option<i32>, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_montana-node"))
        .args(["start", "--data-dir"])
        .arg(dir)
        .args(["--listen", "/ip4/127.0.0.1/tcp/0", "--genesis-manifest"])
        .arg(manifest)
        .args(["--max-windows", "0"])
        .args(extra)
        .env("MONTANA_PRIVATE_DIAGNOSTICS", "1")
        .output()
        .expect("spawn montana-node");
    (
        out.status.code(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

// Every file under a data dir with its bytes.
fn files(dir: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
    let mut out = BTreeMap::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for entry in fs::read_dir(&d).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                out.insert(path.clone(), Vec::new());
                stack.push(path);
            } else {
                out.insert(path.clone(), fs::read(&path).unwrap());
            }
        }
    }
    out
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn tempdir() -> PathBuf {
    let mut p = std::env::temp_dir();
    let mut nonce = [0u8; 8];
    getrandom::getrandom(&mut nonce).unwrap();
    p.push(format!(
        "montana-node-k5o-{:016x}",
        u64::from_le_bytes(nonce)
    ));
    fs::create_dir_all(&p).unwrap();
    p
}
