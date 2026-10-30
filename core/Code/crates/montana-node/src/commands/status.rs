use std::path::PathBuf;

use mt_account::{window_credit_coins, window_credit_moneta};
use mt_genesis::genesis_params;

use crate::clock::load_current_window;
use crate::identity::{default_data_dir, load_identity, NodeError};
use crate::node_lifecycle::load_or_init_lifecycle;
use crate::reading::Lack;
use crate::state::LocalState;
use crate::timechain_state::load_or_init_timechain;

pub struct StatusArgs {
    pub data_dir: Option<PathBuf>,
}

/// Issue #21 (the Author's decision on the codes of the earlier core, (a)): the exit code of
/// `status` is the code of the node's reading -- 0 for a closed window, 1 `no quorum`, 2 `no data`
/// -- and 4 `no diagnostics` where the node gives no reading: a record of its chain is missing, no
/// running node holds the store, or this run has read nothing yet. A missing reading never reads
/// as success. A status writes nothing.
pub fn run(args: StatusArgs) -> u8 {
    let data_dir = args.data_dir.unwrap_or_else(default_data_dir);
    let no_diagnostics = Lack::Diagnostics;
    if let Err(e) = report(&data_dir) {
        eprintln!("{}: {e}", no_diagnostics.name());
        return no_diagnostics.exit_code();
    }
    println!();
    println!("--- reading ---");
    match crate::reading::read(&data_dir) {
        Some(reading) if reading.exit_code() == 0 => {
            println!("{reading}");
            0
        },
        Some(reading) => {
            eprintln!("{reading}");
            reading.exit_code()
        },
        None => {
            eprintln!(
                "{}: this run of the node has read nothing yet",
                no_diagnostics.name()
            );
            no_diagnostics.exit_code()
        },
    }
}

fn report(data_dir: &std::path::Path) -> Result<(), NodeError> {
    let identity = whole_and_held(data_dir)?;
    let params = genesis_params();
    let state = LocalState::load_or_bootstrap(data_dir, &identity, params)?;
    let current_window = load_current_window(data_dir)?;
    let lifecycle = load_or_init_lifecycle(data_dir, &identity, params)?;
    let timechain = load_or_init_timechain(data_dir)?;

    let my_account = identity.account_id();
    let my_node = identity.node_id();

    println!("=== montana-node status ===");
    println!();
    println!("data-dir              : {}", data_dir.display());
    println!("current_window        : {current_window}");
    println!("phase                 : {:?}", lifecycle.phase);
    println!("D (current)           : {}", timechain.current_d);
    if matches!(
        lifecycle.phase,
        crate::node_lifecycle::NodePhase::CandidateSsha
    ) {
        println!(
            "candidate SSHA         : {}/{} ({} windows left)",
            lifecycle.candidate_progress,
            lifecycle.target_chain_length,
            lifecycle
                .target_chain_length
                .saturating_sub(lifecycle.candidate_progress)
        );
    }
    if matches!(
        lifecycle.phase,
        crate::node_lifecycle::NodePhase::Registered | crate::node_lifecycle::NodePhase::Active
    ) {
        println!("registration_window   : {}", lifecycle.registration_window);
    }
    println!();
    println!("--- your identity ---");
    println!("account_id            : {}", hex_lower(&my_account));
    println!("node_id               : {}", hex_lower(&my_node));
    println!(
        "node_pubkey_hex       : {}",
        hex_lower(identity.node_pk.as_bytes())
    );
    println!(
        "account_pubkey_hex    : {}",
        hex_lower(identity.account_pk.as_bytes())
    );
    println!();
    println!("--- local state table sizes ---");
    println!("AccountTable          : {} records", state.accounts.len());
    println!(
        "NodeTable             : {} records (active nodes)",
        state.nodes.len()
    );
    println!(
        "CandidatePool         : {} records (awaiting selection event)",
        state.candidates.len()
    );
    println!();

    let in_node_table = state.nodes.contains(&my_node);
    let in_candidate_pool = state.candidates.contains(&my_node);
    let operator_record = state.accounts.get(&my_account);

    println!("--- your status ---");
    if let Some(rec) = operator_record {
        println!("operator account     : found in AccountTable");
        println!("balance               : {} nɈ", rec.balance);
        println!("is_node_operator      : {}", rec.is_node_operator);
        println!("account_chain_length  : {}", rec.account_chain_length);
    } else {
        println!("operator account      : NOT FOUND (state not bootstrapped)");
    }

    if in_node_table {
        println!("node in Node Table    : YES — active");
        let n = state.nodes.get(&my_node).unwrap();
        println!("  start_window         : {}", n.start_window);
        println!("  chain_length         : {}", n.chain_length);
    } else if in_candidate_pool {
        println!("node in Candidate Pool: YES — awaiting selection event");
        let c = state.candidates.get(&my_node).unwrap();
        println!("  w_start              : {}", c.w_start);
        println!("  ssha_chain_length     : {}", c.ssha_chain_length);
        println!("  registration_window  : {}", c.registration_window);
        println!("  expires (window)     : {}", c.expires);
        println!("  proof_endpoint       : {}", hex_lower(&c.proof_endpoint));
    } else {
        println!("node                  : NOT REGISTERED");
        println!("                        run 'start' — the node will go through");
        println!("                        candidate SSHA (τ₂ windows) → registered → active");
    }
    println!();

    println!("--- protocol parameters ---");
    println!("τ₂ (windows per epoch): {}", params.tau2_windows);
    println!(
        "selection interval   : every {} windows",
        params.selection_interval
    );
    println!(
        "admission divisor    : {} (1/{} active nodes / selection)",
        params.admission_divisor, params.admission_divisor
    );
    println!(
        "candidate expiry     : {} windows from registration",
        params.candidate_expiry_windows
    );
    println!(
        "credit per window    : {} nɈ ({} Ɉ, one per second) to every living node",
        window_credit_moneta(params),
        window_credit_coins(params)
    );

    let total_balances: u128 = state.accounts.iter().map(|a| a.balance).sum();
    println!();
    println!("--- AccountTable balances ---");
    println!(
        "Σ balances           : {} nɈ ({} Ɉ)",
        total_balances,
        total_balances / 1_000_000_000
    );

    Ok(())
}

/// What `status` says of a store no running node holds (issue #21 K4).
pub const NO_RUNNING_HOLDER: &str = "no running node holds";

// Issue #21 K4: a status reports a running node from the records of its chain, or fails. A record
// that is missing is named and no default stands in for it, and a store no running node holds is
// said to be one, so a health check that reads the exit code never reads success for a dead node.
fn whole_and_held(data_dir: &std::path::Path) -> Result<crate::identity::Identity, NodeError> {
    let identity = load_identity(data_dir)?;
    let records = crate::commands::start::chain_records(data_dir);
    if let Some(missing) = records.iter().find(|p| !p.exists()) {
        return Err(NodeError::InvalidArguments(format!(
            "{} is missing; status reports nothing in its place",
            missing.display()
        )));
    }
    if !crate::holder::is_held(data_dir)? {
        return Err(NodeError::InvalidArguments(format!(
            "{NO_RUNNING_HOLDER} {}",
            data_dir.display()
        )));
    }
    Ok(identity)
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}
