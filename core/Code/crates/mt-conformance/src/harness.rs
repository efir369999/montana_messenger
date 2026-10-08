// Spec Conformance Harness — executable spec<->code equivalence.
// spec, Genesis Decree protocol_params; role CLAUDE.md [C-14].
// Contract (conformance/spec-vXX.contract) is the single source of truth;
// code is asserted byte-exact against it. A spec field absent in code surfaces
// as an Absent row; a value mismatch as Partial. Verdict green iff all Full.

use mt_codec::CanonicalEncode;
use mt_genesis::{genesis_params, PARAMS_ENCODED_SIZE};
use mt_net::{FastSyncResponseChunk, TableId};
use mt_state::NodeRecord;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    Full,
    Partial,
    Absent,
    Unmapped,
}

impl Status {
    pub fn tag(&self) -> &'static str {
        match self {
            Status::Full => "full",
            Status::Partial => "partial",
            Status::Absent => "absent",
            Status::Unmapped => "unmapped",
        }
    }
}

#[derive(Debug, Clone)]
pub struct LedgerRow {
    pub spec_id: String,
    pub status: Status,
    pub detail: String,
}

#[derive(Debug, Clone)]
pub struct ContractField {
    pub name: String,
    pub size: usize,
    pub value: Option<u128>,
}

#[derive(Debug, Clone)]
pub struct SpecContract {
    pub spec_version: String,
    pub network_version: String,
    pub fields: Vec<ContractField>,
    pub kats: Vec<(String, u128)>,
    pub hashes: Vec<(String, [u8; 32])>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseError {
    BadField(String),
    BadKat(String),
    BadHash(String),
    MissingVersion,
}

pub fn parse_contract(src: &str) -> Result<SpecContract, ParseError> {
    let mut spec_version = String::new();
    let mut network_version = String::new();
    let mut fields = Vec::new();
    let mut kats = Vec::new();
    let mut hashes = Vec::new();
    for raw in src.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let toks: Vec<&str> = line.split_whitespace().collect();
        match toks.as_slice() {
            ["spec_version", "=", v] => spec_version = v.to_string(),
            ["network_version", "=", v] => network_version = v.to_string(),
            ["field", name, size, value] => {
                let size: usize = size
                    .parse()
                    .map_err(|_| ParseError::BadField(line.to_string()))?;
                let value = if *value == "-" {
                    None
                } else {
                    Some(
                        value
                            .parse::<u128>()
                            .map_err(|_| ParseError::BadField(line.to_string()))?,
                    )
                };
                fields.push(ContractField {
                    name: name.to_string(),
                    size,
                    value,
                });
            },
            ["kat", name, value] => {
                let value = value
                    .parse::<u128>()
                    .map_err(|_| ParseError::BadKat(line.to_string()))?;
                kats.push((name.to_string(), value));
            },
            ["hash", name, value] => {
                let bytes =
                    parse_hash32(value).ok_or_else(|| ParseError::BadHash(line.to_string()))?;
                hashes.push((name.to_string(), bytes));
            },
            _ => return Err(ParseError::BadField(line.to_string())),
        }
    }
    if spec_version.is_empty() || network_version.is_empty() {
        return Err(ParseError::MissingVersion);
    }
    Ok(SpecContract {
        spec_version,
        network_version,
        fields,
        kats,
        hashes,
    })
}

fn parse_hash32(hex: &str) -> Option<[u8; 32]> {
    if hex.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}

// Extract "<token>" following a marker like "Montana Protocol v" from a doc.
pub fn extract_version_after(doc: &str, marker: &str) -> Option<String> {
    let idx = doc.find(marker)? + marker.len();
    let tail = &doc[idx..];
    let end = tail
        .find(|c: char| !(c.is_ascii_digit() || c == '.'))
        .unwrap_or(tail.len());
    let v = &tail[..end];
    if v.is_empty() {
        None
    } else {
        Some(v.to_string())
    }
}

// Map a contract field name to its current code state:
//   None            -> field absent in code (cross-boundary structural drift)
//   Some(None)      -> present, non-scalar (array/pubkey/hash); structural only
//   Some(Some(v))   -> present scalar with value v
fn code_field_value(name: &str) -> Option<Option<u128>> {
    let p = genesis_params();
    let scalar = |v: u128| Some(Some(v));
    match name {
        "d0" => scalar(p.d0 as u128),
        "reserved_m0" => Some(None),
        "tau2_windows" => scalar(p.tau2_windows as u128),
        "emission_moneta" => scalar(p.emission_moneta),
        "target_zero" => Some(None),
        "confirmation_quorum_num" => scalar(p.confirmation_quorum_num as u128),
        "confirmation_quorum_den" => scalar(p.confirmation_quorum_den as u128),
        "participation_dead_zone_low" => scalar(p.participation_dead_zone_low as u128),
        "participation_dead_zone_high" => scalar(p.participation_dead_zone_high as u128),
        "d_adjustment_rate_num" => scalar(p.d_adjustment_rate_num as u128),
        "d_adjustment_rate_den" => scalar(p.d_adjustment_rate_den as u128),
        "ssha_entry_windows" => scalar(p.ssha_entry_windows as u128),
        "selection_interval" => scalar(p.selection_interval as u128),
        "admission_divisor" => scalar(p.admission_divisor as u128),
        "candidate_expiry_windows" => scalar(p.candidate_expiry_windows as u128),
        "adaptive_ssha_threshold" => scalar(p.adaptive_ssha_threshold as u128),
        "adaptive_ssha_multiplier" => scalar(p.adaptive_ssha_multiplier as u128),
        "pruning_idle_windows" => scalar(p.pruning_idle_windows as u128),
        "genesis_content_app_id" => Some(None),
        "genesis_content_data_hash" => Some(None),
        "max_protocol_payload_bytes" => scalar(p.max_protocol_payload_bytes as u128),
        "max_sf_ciphertext_bytes" => scalar(p.max_sf_ciphertext_bytes as u128),
        // Unknown field -> Absent (cross-boundary structural drift).
        _ => None,
    }
}

fn code_encoded_len() -> usize {
    let mut buf = Vec::new();
    genesis_params().encode(&mut buf);
    buf.len()
}

pub fn build_ledger(
    contract: &SpecContract,
    version_md: &str,
    audit_md: &str,
    node_toml: &str,
    transport_toml: &str,
    audit_cfg: &str,
) -> Vec<LedgerRow> {
    let mut rows = Vec::new();

    // 1. Structural: encoded size (spec contract vs code const vs actual encode).
    let spec_size: usize = contract.fields.iter().map(|f| f.size).sum();
    let code_const = PARAMS_ENCODED_SIZE;
    let actual = code_encoded_len();
    let size_full = spec_size == code_const && code_const == actual;
    rows.push(LedgerRow {
        spec_id: "protocol_params.encoded_size".to_string(),
        status: if size_full {
            Status::Full
        } else {
            Status::Partial
        },
        detail: format!(
            "spec={} code_const={} actual_encode={}",
            spec_size, code_const, actual
        ),
    });

    // 2. Per-field presence + scalar value.
    for f in &contract.fields {
        let (status, detail) = match code_field_value(&f.name) {
            None => (
                Status::Absent,
                format!("size={} — field not present in code", f.size),
            ),
            Some(None) => (
                Status::Full,
                format!("present (size={}, structural)", f.size),
            ),
            Some(Some(code_v)) => match f.value {
                Some(spec_v) if spec_v == code_v => (Status::Full, format!("value={}", code_v)),
                Some(spec_v) => (Status::Partial, format!("spec={} code={}", spec_v, code_v)),
                None => (Status::Full, format!("present scalar={}", code_v)),
            },
        };
        rows.push(LedgerRow {
            spec_id: format!("protocol_params.{}", f.name),
            status,
            detail,
        });
    }

    // 3. KAT cross-check (encoded size KAT vs actual code encode length).
    for (name, kat_v) in &contract.kats {
        if name == "params_encoded_size" {
            let ok = *kat_v as usize == actual;
            rows.push(LedgerRow {
                spec_id: format!("kat.{}", name),
                status: if ok { Status::Full } else { Status::Partial },
                detail: format!("kat={} actual_encode={}", kat_v, actual),
            });
        } else {
            rows.push(LedgerRow {
                spec_id: format!("kat.{}", name),
                status: Status::Unmapped,
                detail: format!("kat={} — no code oracle wired", kat_v),
            });
        }
    }

    // 3b. Identity-root oracles: the birth of an identity is asserted against the
    //     contract the same way protocol_params are — a chain that starts at the
    //     word list and ends at the account_id a second implementation must
    //     reproduce byte for byte.
    for (name, expected) in &contract.hashes {
        let actual = identity_hash_oracle(name);
        let (status, detail) = match actual {
            Some(got) if got == *expected => (Status::Full, format!("hash={}", hex32(&got))),
            Some(got) => (
                Status::Partial,
                format!("contract={} code={}", hex32(expected), hex32(&got)),
            ),
            None => (
                Status::Unmapped,
                format!("hash={} — no code oracle wired", hex32(expected)),
            ),
        };
        rows.push(LedgerRow {
            spec_id: format!("identity.{}", name),
            status,
            detail,
        });
    }

    // 4. Version-stamp coherence across spec contract / VERSION.md / AUDIT.md.
    rows.extend(version_rows(
        "VERSION.md",
        version_md,
        &contract.spec_version,
        &contract.network_version,
    ));
    rows.extend(version_rows(
        "AUDIT.md",
        audit_md,
        &contract.spec_version,
        &contract.network_version,
    ));

    // 5. Behavioral oracles — assert code BEHAVIOR, not just protocol_params
    //    fields. These rows are what makes "GREEN" mean spec<->code equivalence
    //    for the monetary closed-form, active predicate, FastSync anchor policy,
    //    transport feature hygiene and dependency-audit gate (REAUDIT-06).
    rows.extend(behavioral_rows(node_toml, transport_toml, audit_cfg));

    rows
}

fn hex32(bytes: &[u8; 32]) -> String {
    let mut s = String::with_capacity(64);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

// Canonical reference identity of the conformance suite: all-zero entropy. Every
// row below is derived from it, so a second implementation reproduces the whole
// chain from one published input.
const REFERENCE_ENTROPY: [u8; 32] = [0u8; 32];

fn identity_hash_oracle(name: &str) -> Option<[u8; 32]> {
    match name {
        "wordlist_fingerprint" => Some(mt_mnemonic::WORDLIST_FINGERPRINT),
        "mix_zero_zero" => Some(*mt_mnemonic::combine_entropy(&[0u8; 32], &[0u8; 32])),
        "mix_ascending_descending" => {
            let asc: Vec<u8> = (0u8..32).collect();
            let desc: Vec<u8> = (0u8..32).rev().collect();
            Some(*mt_mnemonic::combine_entropy(&asc, &desc))
        },
        "mnemonic_zero_entropy" => {
            let m = mt_mnemonic::entropy_to_mnemonic(&REFERENCE_ENTROPY);
            Some(mt_crypto::sha256_raw(m.as_bytes()))
        },
        "master_seed_zero_entropy" => {
            let m = mt_mnemonic::entropy_to_mnemonic(&REFERENCE_ENTROPY);
            let seed = mt_mnemonic::mnemonic_to_master_seed(&m).ok()?;
            Some(mt_crypto::sha256_raw(&seed))
        },
        "account_seed_zero_entropy" => {
            let m = mt_mnemonic::entropy_to_mnemonic(&REFERENCE_ENTROPY);
            let seed = mt_mnemonic::mnemonic_to_master_seed(&m).ok()?;
            let role = mt_mnemonic::mldsa_seed_for_role(&seed, mt_codec::domain::ACCOUNT_KEY);
            Some(mt_crypto::sha256_raw(&role))
        },
        "account_id_zero_entropy" => {
            let m = mt_mnemonic::entropy_to_mnemonic(&REFERENCE_ENTROPY);
            let seed = mt_mnemonic::mnemonic_to_master_seed(&m).ok()?;
            let role = mt_mnemonic::mldsa_seed_for_role(&seed, mt_codec::domain::ACCOUNT_KEY);
            let (pk, _sk) = mt_crypto::keypair_from_seed(&role).ok()?;
            // suite_id 0x0001 — ML-DSA-65, the canonical account suite.
            Some(mt_state::derive_account_id(1, pk.as_bytes()))
        },
        _ => None,
    }
}

fn beh_row(id: &str, ok: bool, detail: String) -> LedgerRow {
    LedgerRow {
        spec_id: id.to_string(),
        status: if ok { Status::Full } else { Status::Partial },
        detail,
    }
}

fn libp2p_features_have(toml: &str, feat: &str) -> bool {
    toml.lines()
        .filter(|l| l.contains("libp2p") && l.contains("features"))
        .any(|l| l.contains(&format!("\"{}\"", feat)))
}

fn behavioral_rows(node_toml: &str, transport_toml: &str, audit_cfg: &str) -> Vec<LedgerRow> {
    let p = genesis_params();
    let mut out = Vec::new();

    // monetary closed-form: supply_moneta(W) = EMISSION_moneta * W, supply(0) = 0
    let e = p.emission_moneta;
    let mon_ok = mt_account::supply_moneta(0, p) == 0
        && mt_account::supply_moneta(1, p) == e
        && mt_account::supply_moneta(100, p) == e * 100;
    out.push(beh_row(
        "monetary.supply_moneta_closed_form",
        mon_ok,
        format!("supply(0)=0, supply(1)=E, supply(100)=100E (E={})", e),
    ));

    // active predicate: active iff (W - last_confirmation_window) <= 2 * tau2
    let t2 = p.tau2_windows;
    let mk = |last: u64| NodeRecord {
        node_id: [0u8; 32],
        node_pubkey: [0u8; mt_crypto::PUBLIC_KEY_SIZE],
        suite_id: 0,
        operator_account_id: [0u8; 32],
        start_window: 0,
        chain_length: 0,
        chain_length_snapshot: 0,
        chain_length_checkpoints: [0u64; 6],
        last_confirmation_window: last,
    };
    let act_ok =
        mt_state::is_active(&mk(0), 2 * t2, t2) && !mt_state::is_active(&mk(0), 2 * t2 + 1, t2);
    out.push(beh_row(
        "consensus.active_predicate_2tau2",
        act_ok,
        format!("active iff (W-last)<=2*tau2 (tau2={})", t2),
    ));

    // FastSync anchor policy: response chunk binds anchor_window on the wire
    let chunk = FastSyncResponseChunk {
        chunk_index: 0,
        total_chunks: 1,
        table_id: TableId::Account,
        record_count: 1,
        anchor_window: 12345,
        records: vec![0x55u8; 1],
    };
    let mut buf = Vec::new();
    chunk.encode(&mut buf);
    let fs_ok = buf.len() >= 21
        && FastSyncResponseChunk::decode(&buf)
            .map(|c| c.anchor_window == 12345)
            .unwrap_or(false);
    out.push(beh_row(
        "fastsync.anchor_window_wire",
        fs_ok,
        "chunk binds anchor_window (>=21B header, roundtrip)".to_string(),
    ));

    // transport feature hygiene: production libp2p excludes classical tls/noise
    let feat_ok = !libp2p_features_have(node_toml, "tls")
        && !libp2p_features_have(node_toml, "noise")
        && !libp2p_features_have(transport_toml, "tls")
        && !libp2p_features_have(transport_toml, "noise");
    out.push(beh_row(
        "transport.no_classical_tls_noise",
        feat_ok,
        "montana-node + mt-net-transport libp2p features exclude tls/noise".to_string(),
    ));

    // dependency-audit gate present and documented
    let audit_ok = audit_cfg.contains("[advisories]") && audit_cfg.contains("ignore");
    out.push(beh_row(
        "deps.audit_gate_present",
        audit_ok,
        ".cargo/audit.toml documents the ignore set with justification".to_string(),
    ));

    // genesis empty-window-0 invariant: build_genesis_state yields empty tables
    // whose roots equal the root of a freshly-constructed empty table (the empty
    // sparse-Merkle root, shared across all three table types at the same depth).
    let empty_root = mt_state::NodeTable::new().root();
    let g = mt_account::build_genesis_state(p);
    let gen_ok = g.account_table.root() == empty_root
        && g.node_table.root() == empty_root
        && g.candidate_pool.root() == empty_root;
    out.push(beh_row(
        "genesis.empty_window_zero",
        gen_ok,
        "account/node/candidate roots == empty sparse-Merkle root".to_string(),
    ));

    out
}

fn version_rows(
    doc_name: &str,
    doc: &str,
    spec_version: &str,
    network_version: &str,
) -> Vec<LedgerRow> {
    let mut out = Vec::new();
    let checks = [
        ("protocol", "Montana Protocol v", spec_version),
        ("network", "Montana Network v", network_version),
    ];
    for (kind, marker, expected) in checks {
        let (status, detail) = match extract_version_after(doc, marker) {
            Some(found) if found == expected => (Status::Full, format!("v{}", found)),
            Some(found) => (
                Status::Partial,
                format!("doc=v{} contract=v{}", found, expected),
            ),
            None => (Status::Absent, "marker not found".to_string()),
        };
        out.push(LedgerRow {
            spec_id: format!("version.{}.{}", doc_name, kind),
            status,
            detail,
        });
    }
    out
}

pub fn verdict_green(rows: &[LedgerRow]) -> bool {
    rows.iter().all(|r| r.status == Status::Full)
}

pub fn count_by_status(rows: &[LedgerRow]) -> (usize, usize, usize, usize) {
    let mut full = 0;
    let mut partial = 0;
    let mut absent = 0;
    let mut unmapped = 0;
    for r in rows {
        match r.status {
            Status::Full => full += 1,
            Status::Partial => partial += 1,
            Status::Absent => absent += 1,
            Status::Unmapped => unmapped += 1,
        }
    }
    (full, partial, absent, unmapped)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "\
spec_version = 1.2.3
network_version = 9.9.9
field a 8 100
field b 4 -
kat params_encoded_size_nseed0 12
hash wordlist_fingerprint 2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda
";

    #[test]
    fn parse_ok() {
        let c = parse_contract(SAMPLE).expect("parse");
        assert_eq!(c.spec_version, "1.2.3");
        assert_eq!(c.network_version, "9.9.9");
        assert_eq!(c.fields.len(), 2);
        assert_eq!(c.fields[0].name, "a");
        assert_eq!(c.fields[0].size, 8);
        assert_eq!(c.fields[0].value, Some(100));
        assert_eq!(c.fields[1].value, None);
        assert_eq!(c.kats, vec![("params_encoded_size_nseed0".to_string(), 12)]);
        assert_eq!(c.hashes.len(), 1);
        assert_eq!(c.hashes[0].0, "wordlist_fingerprint");
        assert_eq!(c.hashes[0].1, mt_mnemonic::WORDLIST_FINGERPRINT);
    }

    #[test]
    fn bad_hash_errs() {
        let src = format!("{SAMPLE}hash broken deadbeef\n");
        assert!(matches!(parse_contract(&src), Err(ParseError::BadHash(_))));
    }

    #[test]
    fn identity_oracles_are_wired_for_every_contract_hash() {
        // The completeness denominator comes from the contract: a contract row without an oracle
        // in code is not "skipped" but Unmapped, and the ledger turns red.
        for name in [
            "wordlist_fingerprint",
            "mnemonic_zero_entropy",
            "master_seed_zero_entropy",
            "account_seed_zero_entropy",
            "account_id_zero_entropy",
            "mix_zero_zero",
            "mix_ascending_descending",
        ] {
            assert!(
                identity_hash_oracle(name).is_some(),
                "no oracle wired for {name}"
            );
        }
        assert!(identity_hash_oracle("not_a_row").is_none());
    }

    #[test]
    fn parse_missing_version_errs() {
        let r = parse_contract("field a 8 1\n");
        assert_eq!(r.unwrap_err(), ParseError::MissingVersion);
    }

    #[test]
    fn parse_bad_field_errs() {
        let r = parse_contract("spec_version = 1\nnetwork_version = 2\nfield a eight 1\n");
        assert!(matches!(r, Err(ParseError::BadField(_))));
    }

    #[test]
    fn extract_version_basic() {
        let doc = "Spec target: Montana Protocol v35.26.1 + Montana Network v1.3.0 (x)";
        assert_eq!(
            extract_version_after(doc, "Montana Protocol v"),
            Some("35.26.1".to_string())
        );
        assert_eq!(
            extract_version_after(doc, "Montana Network v"),
            Some("1.3.0".to_string())
        );
        assert_eq!(extract_version_after(doc, "Absent marker v"), None);
    }

    #[test]
    fn verdict_logic() {
        let green = vec![LedgerRow {
            spec_id: "x".into(),
            status: Status::Full,
            detail: String::new(),
        }];
        let red = vec![LedgerRow {
            spec_id: "y".into(),
            status: Status::Absent,
            detail: String::new(),
        }];
        assert!(verdict_green(&green));
        assert!(!verdict_green(&red));
    }

    #[test]
    fn version_rows_detect_drift() {
        let stale = "Spec target: Montana Protocol v35.25.1 + Montana Network v1.1.0";
        let rows = version_rows("AUDIT.md", stale, "35.26.1", "1.3.0");
        assert_eq!(rows.len(), 2);
        assert!(rows.iter().all(|r| r.status == Status::Partial));
    }

    #[test]
    fn behavioral_rows_present_and_green() {
        let clean_node = "libp2p = { features = [\"tcp\", \"yamux\"] }";
        let clean_tr = "libp2p = { features = [\"tcp\", \"yamux\"] }";
        let audit = "[advisories]\nignore = [\"RUSTSEC-0000-0000\"]\n";
        let rows = behavioral_rows(clean_node, clean_tr, audit);
        let ids: Vec<&str> = rows.iter().map(|r| r.spec_id.as_str()).collect();
        for want in [
            "monetary.supply_moneta_closed_form",
            "consensus.active_predicate_2tau2",
            "fastsync.anchor_window_wire",
            "transport.no_classical_tls_noise",
            "deps.audit_gate_present",
            "genesis.empty_window_zero",
        ] {
            assert!(ids.contains(&want), "missing behavioral row {want}");
        }
        assert!(rows.iter().all(|r| r.status == Status::Full));
    }

    #[test]
    fn transport_row_red_when_tls_feature_present() {
        let dirty = "libp2p = { features = [\"tcp\", \"tls\", \"noise\", \"yamux\"] }";
        let audit = "[advisories]\nignore = []\n";
        let rows = behavioral_rows(dirty, "libp2p = { features = [] }", audit);
        let r = rows
            .iter()
            .find(|r| r.spec_id == "transport.no_classical_tls_noise")
            .unwrap();
        assert_eq!(r.status, Status::Partial);
    }
}
