use std::path::PathBuf;

use mt_genesis::genesis_params;

use crate::clock::{current_window_path, load_current_window};
use crate::identity::{default_data_dir, NodeError};

pub struct TimeArgs {
    pub data_dir: Option<PathBuf>,
}

pub fn run(args: TimeArgs) -> Result<(), NodeError> {
    let data_dir = args.data_dir.unwrap_or_else(default_data_dir);
    let window = load_current_window(&data_dir)?;
    let params = genesis_params();
    let next_selection = next_selection_window(window, params.selection_interval);
    let epoch = window / params.tau2_windows;
    let in_epoch = window % params.tau2_windows;

    println!("=== montana-node time ===");
    println!();
    println!("data-dir              : {}", data_dir.display());
    println!(
        "current_window file   : {}",
        current_window_path(&data_dir).display()
    );
    println!();
    println!("current_window        : {window}");
    println!(
        "epoch τ₂              : {epoch} (window {in_epoch} of {})",
        params.tau2_windows
    );
    println!(
        "next selection        : window {next_selection} (in {} windows)",
        next_selection.saturating_sub(window)
    );
    println!(
        "selection_interval    : every {} windows",
        params.selection_interval
    );

    Ok(())
}

fn next_selection_window(current: u64, interval: u64) -> u64 {
    if interval == 0 {
        return current.saturating_add(1);
    }
    let next_multiple = current
        .saturating_add(interval)
        .saturating_sub(1)
        .saturating_div(interval)
        .saturating_mul(interval);
    if next_multiple == current || next_multiple == 0 {
        current.saturating_add(interval)
    } else {
        next_multiple
    }
}
