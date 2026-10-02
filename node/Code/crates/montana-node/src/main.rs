use std::path::PathBuf;
use std::process::ExitCode;

use montana_node::commands::{init, inspect, start, status, time};
use montana_node::NodeError;

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().collect();
    if argv.len() < 2 {
        eprintln!("{}", help_text());
        return ExitCode::from(2);
    }

    let result = match argv[1].as_str() {
        "init" => parse_init(&argv[2..]).and_then(init::run),
        "inspect" => parse_inspect(&argv[2..]).and_then(inspect::run),
        "status" => parse_status(&argv[2..]).and_then(status::run),
        "time" => parse_time(&argv[2..]).and_then(time::run),
        "start" => parse_start(&argv[2..]).and_then(start::run),
        "help" | "-h" | "--help" => {
            println!("{}", help_text());
            return ExitCode::SUCCESS;
        },
        "version" | "--version" | "-V" => {
            println!(
                "Montana Core 0.1 — montana-node {} (git {} {})",
                env!("CARGO_PKG_VERSION"),
                env!("MONTANA_GIT_SHA"),
                env!("MONTANA_GIT_COMMIT_DATE"),
            );
            return ExitCode::SUCCESS;
        },
        other => {
            eprintln!("unknown command: {other}");
            eprintln!();
            eprintln!("{}", help_text());
            return ExitCode::from(2);
        },
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::from(1)
        },
    }
}

fn help_text() -> String {
    String::from(
        "montana-node — Montana node (singleton or cross-machine M8 mode)\n\
         \n\
         Usage:\n\
         \n\
           montana-node init    [--data-dir <PATH>] [--mnemonic \"<24 words>\"]\n\
                                 [--mnemonic-stdin] [--entropy <hex32>] [--force]\n\
         \n\
           montana-node inspect [--data-dir <PATH>] [--reveal-master-seed]\n\
         \n\
           montana-node status  [--data-dir <PATH>]\n\
         \n\
           montana-node time    [--data-dir <PATH>]\n\
         \n\
           montana-node start   [--data-dir <PATH>] [--max-windows <N>]\n\
                                 [--d-test-override <N>]\n\
                                 [--listen <multiaddr>] [--genesis-manifest <PATH>]\n\
         \n\
         Commands:\n\
         \n\
           init      Create identity (mnemonic + keys) and save to identity.bin.\n\
                     If neither --mnemonic nor --entropy is given, random\n\
                     entropy is generated via the system CSPRNG.\n\
         \n\
           inspect   Read identity.bin and print account_id / node_id /\n\
                     fingerprint. Secret keys are not printed.\n\
         \n\
           status    Show local state: AccountTable,\n\
                     NodeTable, CandidatePool, node status, current_window,\n\
                     phase lifecycle (Bootstrap/CandidateSsha/Registered/Active),\n\
                     supply, balances.\n\
         \n\
           time      Show local current_window, next\n\
                     selection window, τ₂ epoch.\n\
         \n\
           start     PRODUCTION MODE — run the Montana node via the canonical\n\
                     apply_proposal pipeline. The node goes through the lifecycle:\n\
                       Bootstrap → CandidateSsha (ticks SSHA until ssha_chain_length\n\
                                                   ≥ τ₂ = 20160 windows, ~10 hours\n\
                                                   wall-clock on an M-class Mac)\n\
                       CandidateSsha → Registered (builds NodeRegistration\n\
                                                   через apply_noderegistrations_batch)\n\
                       Registered → Active (via apply_selection_event at\n\
                                            the next W % 336 == 0)\n\
                       Active: per window SshaReveal + BundledConfirmation +\n\
                               ProposalHeader + apply_proposal + archive_proposal,\n\
                               state_root self-verify, 13 Ɉ emission to the operator\n\
                     Ctrl-C — graceful shutdown with state save.\n\
         \n\
         Options:\n\
         \n\
           --data-dir <PATH>          Node data directory. Default on macOS:\n\
                                      $HOME/Library/Application Support/Montana/node\n\
           --mnemonic \"...\"           Recover identity from a 24-word phrase. WARNING:\n\
                                       visible in `ps aux` to other system users.\n\
                                       For production use --mnemonic-stdin.\n\
           --mnemonic-stdin           Read the 24-word phrase from stdin (no leak\n\
                                       via ps aux).\n\
           --entropy <hex32>          Use 32-byte entropy (64 hex).\n\
           --force                    Overwrite existing identity.bin.\n\
           --reveal-master-seed       In inspect: show the full master_seed.\n\
           --max-windows <N>          In start: stop after N windows.\n\
           --d-test-override <N>      In start: TEST-ONLY override D = N iterations.\n\
                                      Production uses params.d0 (Genesis Decree, value from mt-genesis).\n\
                                      Override is used in tests for speed.\n",
    )
}

fn parse_init(args: &[String]) -> Result<init::InitArgs, NodeError> {
    let mut data_dir: Option<PathBuf> = None;
    let mut mnemonic: Option<String> = None;
    let mut entropy_hex: Option<String> = None;
    let mut force = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--data-dir" => {
                data_dir = Some(PathBuf::from(expect_value(args, i, "--data-dir")?));
                i += 2;
            },
            "--mnemonic" => {
                mnemonic = Some(expect_value(args, i, "--mnemonic")?.to_string());
                i += 2;
            },
            "--mnemonic-stdin" => {
                use std::io::BufRead;
                let stdin = std::io::stdin();
                let mut buf = String::new();
                stdin.lock().read_line(&mut buf).map_err(|e| {
                    NodeError::InvalidArguments(format!("--mnemonic-stdin read: {e}"))
                })?;
                mnemonic = Some(
                    buf.trim_end_matches('\n')
                        .trim_end_matches('\r')
                        .to_string(),
                );
                i += 1;
            },
            "--entropy" => {
                entropy_hex = Some(expect_value(args, i, "--entropy")?.to_string());
                i += 2;
            },
            "--force" => {
                force = true;
                i += 1;
            },
            other => {
                return Err(NodeError::InvalidArguments(format!(
                    "unknown flag for init: {other}"
                )))
            },
        }
    }
    Ok(init::InitArgs {
        data_dir,
        mnemonic,
        entropy_hex,
        force,
    })
}

fn parse_inspect(args: &[String]) -> Result<inspect::InspectArgs, NodeError> {
    let mut data_dir: Option<PathBuf> = None;
    let mut reveal_master_seed = false;
    let mut export_pubkeys = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--data-dir" => {
                data_dir = Some(PathBuf::from(expect_value(args, i, "--data-dir")?));
                i += 2;
            },
            "--reveal-master-seed" => {
                reveal_master_seed = true;
                i += 1;
            },
            "--export-pubkeys" => {
                export_pubkeys = true;
                i += 1;
            },
            other => {
                return Err(NodeError::InvalidArguments(format!(
                    "unknown flag for inspect: {other}"
                )))
            },
        }
    }
    Ok(inspect::InspectArgs {
        data_dir,
        reveal_master_seed,
        export_pubkeys,
    })
}

fn parse_status(args: &[String]) -> Result<status::StatusArgs, NodeError> {
    let mut data_dir: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--data-dir" => {
                data_dir = Some(PathBuf::from(expect_value(args, i, "--data-dir")?));
                i += 2;
            },
            other => {
                return Err(NodeError::InvalidArguments(format!(
                    "unknown flag for status: {other}"
                )))
            },
        }
    }
    Ok(status::StatusArgs { data_dir })
}

fn parse_time(args: &[String]) -> Result<time::TimeArgs, NodeError> {
    let mut data_dir: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--data-dir" => {
                data_dir = Some(PathBuf::from(expect_value(args, i, "--data-dir")?));
                i += 2;
            },
            other => {
                return Err(NodeError::InvalidArguments(format!(
                    "unknown flag for time: {other}"
                )))
            },
        }
    }
    Ok(time::TimeArgs { data_dir })
}

fn parse_start(args: &[String]) -> Result<start::StartArgs, NodeError> {
    let mut data_dir: Option<PathBuf> = None;
    let mut enable_candidate = false;
    // Слой имён по умолчанию выключен: старое поведение узла не меняется, пока не проверено новое.
    let mut enable_names = false;
    let mut max_windows: Option<u64> = None;
    let mut d_test_override: Option<u64> = None;
    let mut listen_multiaddr: Option<String> = None;
    let mut genesis_manifest: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--data-dir" => {
                data_dir = Some(PathBuf::from(expect_value(args, i, "--data-dir")?));
                i += 2;
            },
            "--max-windows" => {
                max_windows = Some(expect_value(args, i, "--max-windows")?.parse().map_err(
                    |_| NodeError::InvalidArguments("--max-windows must be u64".into()),
                )?);
                i += 2;
            },
            "--d-test-override" => {
                d_test_override = Some(
                    expect_value(args, i, "--d-test-override")?
                        .parse()
                        .map_err(|_| {
                            NodeError::InvalidArguments("--d-test-override must be u64".into())
                        })?,
                );
                i += 2;
            },
            "--enable-candidate" => {
                enable_candidate = true;
                i += 1;
            },
            "--enable-names" => {
                enable_names = true;
                i += 1;
            },
            "--listen" => {
                listen_multiaddr = Some(expect_value(args, i, "--listen")?.to_string());
                i += 2;
            },
            "--genesis-manifest" => {
                genesis_manifest =
                    Some(PathBuf::from(expect_value(args, i, "--genesis-manifest")?));
                i += 2;
            },
            other => {
                return Err(NodeError::InvalidArguments(format!(
                    "unknown flag for start: {other}"
                )))
            },
        }
    }
    if listen_multiaddr.is_some() != genesis_manifest.is_some() {
        return Err(NodeError::InvalidArguments(
            "--listen and --genesis-manifest must be given together (cross-machine mode) or both omitted (singleton mode)"
                .into(),
        ));
    }
    Ok(start::StartArgs {
        enable_candidate,
        enable_names,
        data_dir,
        max_windows,
        d_test_override,
        listen_multiaddr,
        genesis_manifest,
    })
}

fn expect_value<'a>(args: &'a [String], i: usize, flag: &str) -> Result<&'a str, NodeError> {
    args.get(i + 1)
        .map(|s| s.as_str())
        .ok_or_else(|| NodeError::InvalidArguments(format!("flag {flag} requires a value")))
}
