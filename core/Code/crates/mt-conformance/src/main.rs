// conformance-gate — CI turnstile. Exit 0 iff every ledger row is Full and all
// version stamps agree; otherwise exit 1 and print the red rows. role [C-14].

use mt_conformance::harness::{
    build_ledger, count_by_status, parse_contract, verdict_green, Status,
};

const CONTRACT: &str = include_str!("../../../conformance/spec-v35.27.0.contract");
const VERSION_MD: &str = include_str!("../../../VERSION.md");
const AUDIT_MD: &str = include_str!("../../../AUDIT.md");
const NODE_TOML: &str = include_str!("../../montana-node/Cargo.toml");
const TRANSPORT_TOML: &str = include_str!("../../mt-net-transport/Cargo.toml");
const AUDIT_CFG: &str = include_str!("../../../.cargo/audit.toml");

fn main() {
    let contract = match parse_contract(CONTRACT) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("conformance-gate: contract parse error: {:?}", e);
            std::process::exit(2);
        },
    };

    let rows = build_ledger(
        &contract,
        VERSION_MD,
        AUDIT_MD,
        NODE_TOML,
        TRANSPORT_TOML,
        AUDIT_CFG,
    );

    println!(
        "Spec Conformance Ledger — contract spec v{} / network v{}",
        contract.spec_version, contract.network_version
    );
    println!("{:-<92}", "");
    println!("{:<8}  {:<44}  detail", "status", "spec-id");
    println!("{:-<92}", "");
    for r in &rows {
        let mark = match r.status {
            Status::Full => " ",
            _ => "!",
        };
        println!(
            "{}{:<7}  {:<44}  {}",
            mark,
            r.status.tag(),
            r.spec_id,
            r.detail
        );
    }
    println!("{:-<92}", "");

    let (full, partial, absent, unmapped) = count_by_status(&rows);
    println!(
        "rows={} full={} partial={} absent={} unmapped={}",
        rows.len(),
        full,
        partial,
        absent,
        unmapped
    );

    if verdict_green(&rows) {
        println!("VERDICT: GREEN — spec and code conform; release gate open.");
        std::process::exit(0);
    } else {
        println!("VERDICT: RED — spec-code drift / incompleteness; release BLOCKED ([C-14]).");
        std::process::exit(1);
    }
}
