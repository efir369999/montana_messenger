// M2 — TimeChain + State shakedown.
// Subcommands:
//   ssha-forward [N]          SSHA forward N steps, byte-exact match with manual SHA-256^N
//   next-d-boundaries        Adaptive D: 7 binding test vectors from the spec
//   cba-branches             cemented_bundle_aggregate: three branches (W<2 / empty / non-empty)
//   state-root-compose       state_root = SHA-256("mt-state-root" || node || cand || acct)
//   merkle-inclusion         SparseMerkleTree: prove → verify (existence + absence)
//   all                      Run all 5
//
// Exit code 0=PASS, 1=FAIL.

use std::env;
use std::process::ExitCode;

use mt_codec::domain;
use mt_crypto::{hash, sha256_raw, Hash32, PUBLIC_KEY_SIZE};
use mt_examples::{hex_full, print_kv, print_note, print_section, print_subsection};
use mt_genesis::genesis_params;
use mt_merkle::{verify_proof, SparseMerkleTree};
use mt_state::{
    compute_state_root, AccountId, AccountRecord, AccountTable, CandidatePool, CandidateRecord,
    NodeId, NodeRecord, NodeTable,
};
use mt_timechain::{cemented_bundle_aggregate, next_d, ssha_step};

// SSHA forward via the single ssha_step(prev, N) vs a manual N-fold SHA-256.
fn cmd_ssha_forward(steps: u64) -> bool {
    print_section(&format!(
        "SSHA FORWARD — ssha_step(prev, {steps}) vs manual SHA-256^{steps}"
    ));
    print_note(
        "spec, section \"TimeChain\": T_r = SHA-256^D(T_{r-1}). ssha_step(prev, D) applies exactly D single SHA-256 rounds.",
    );

    let prev: Hash32 = [0u8; 32];
    print_kv("T_r_0 (genesis seed)", hex_full(&prev));
    print_kv("D", format!("{steps}"));

    print_subsection("1. ssha_step(prev, D) → T_r_D");
    let t_r_batch = ssha_step(&prev, steps);
    print_kv("T_r_D (batch)", hex_full(&t_r_batch));

    print_subsection("2. Manual: prev → SHA-256 → SHA-256 → ... exactly D times");
    let mut manual: Hash32 = prev;
    for _ in 0..steps {
        manual = sha256_raw(&manual);
    }
    print_kv("T_r_D (manual)", hex_full(&manual));

    let equal = t_r_batch == manual;
    print_subsection("3. Byte-exact equality");
    print_kv("ssha_step == SHA-256^D", format!("{equal}"));

    print_subsection("4. Determinism: repeated call ssha_step(prev, D) → same T_r_D");
    let t_r_again = ssha_step(&prev, steps);
    let det = t_r_batch == t_r_again;
    print_kv("ssha_step idempotent", format!("{det}"));

    print_subsection("5. Preimage resistance: D=0 → identity; D=1 → one SHA-256");
    let d0 = ssha_step(&prev, 0);
    let d1 = ssha_step(&prev, 1);
    let single_sha = sha256_raw(&prev);
    let d0_id = d0 == prev;
    let d1_match = d1 == single_sha;
    print_kv("ssha_step(prev, 0) == prev", format!("{d0_id}"));
    print_kv("ssha_step(prev, 1) == SHA-256(prev)", format!("{d1_match}"));

    let pass = equal && det && d0_id && d1_match;
    println!(
        "\n[result] SSHA-FORWARD: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

// Adaptive D — 7 binding test vectors from the spec + sanity cases.
fn cmd_next_d_boundaries() -> bool {
    print_section("ADAPTIVE D — next_d boundary cases");
    print_note(
        "spec, section \"Adaptive D\" (Integer form, [I-9]): high_permille=950, low_permille=850, rate=3/100. high/low — inclusive boundaries.",
    );

    let params = genesis_params();
    print_kv("high_permille", "950");
    print_kv("low_permille", "850");
    print_kv("rate", "3/100");

    // (median_permille, expected_D_at_D_old=1000, comment)
    let cases: [(u32, u64, &str); 7] = [
        (1000, 1030, "100% — above high, +3%"),
        (950, 1030, "950 = high_permille edge, inclusive → +3%"),
        (980, 1030, "980 — above high, +3%"),
        (900, 1000, "dead zone middle — no change"),
        (
            851,
            1000,
            "851 — dead zone upper edge (>low), no change",
        ),
        (850, 970, "850 = low_permille edge, inclusive → -3%"),
        (700, 970, "700 — deep below low, -3%"),
    ];

    let mut all_match = true;
    for (median, expected, comment) in &cases {
        let actual = next_d(1000, *median, params);
        let match_ok = actual == *expected;
        print_kv(
            &format!("median={median:4} permille"),
            format!("D_new = {actual:5} (expected {expected}) — {comment}"),
        );
        if !match_ok {
            all_match = false;
        }
    }

    print_subsection("Sanity: D_old=2_000_000_000, median=1000 → D_old × 103/100 without overflow");
    let big = next_d(2_000_000_000, 1000, params);
    let big_expected: u64 = 2_000_000_000u64 * 103 / 100;
    print_kv("D_new", format!("{big}"));
    print_kv("expected", format!("{big_expected}"));
    let big_ok = big == big_expected;

    let pass = all_match && big_ok;
    println!(
        "\n[result] NEXT-D-BOUNDARIES: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

// cemented_bundle_aggregate: three branches.
fn cmd_cba_branches() -> bool {
    print_section("CEMENTED BUNDLE AGGREGATE — three branches ([I-8] anti-grinding binding)");
    print_note(
        "spec lines 2080-2089: W<2 → 0x00×32; |cemented|==0 → SHA-256(\"mt-bc-aggregate-empty\" || W_le8); otherwise → SHA-256(\"mt-bc-aggregate\" || concat(sorted node_ids) || W_le8).",
    );

    // Branch 1: W < 2 → zeros.
    print_subsection("Branch 1: W=0, W=1 → 0x00 × 32");
    let cba_w0 = cemented_bundle_aggregate(0, &[]);
    let cba_w1 = cemented_bundle_aggregate(1, &[[0xAB; 32]]); // zeros even with node_ids (W<2)
    print_kv("cba(W=0, [])", hex_full(&cba_w0));
    print_kv("cba(W=1, [one_node])", hex_full(&cba_w1));
    let zeros: Hash32 = [0u8; 32];
    let b1_pass = cba_w0 == zeros && cba_w1 == zeros;
    print_kv("== 0x00 × 32", format!("{b1_pass}"));

    // Branch 2: empty cemented set, W>=2.
    print_subsection("Branch 2: W=5, |cemented|==0 → SHA-256(\"mt-bc-aggregate-empty\" || W_le8)");
    let w: u64 = 5;
    let cba_empty = cemented_bundle_aggregate(w, &[]);
    let manual_empty: Hash32 = hash(domain::BC_AGGREGATE_EMPTY, &[&w.to_le_bytes()]);
    print_kv("cba(W=5, [])", hex_full(&cba_empty));
    print_kv("manual hash", hex_full(&manual_empty));
    let b2_pass = cba_empty == manual_empty;
    print_kv("byte-exact match", format!("{b2_pass}"));

    // Branch 3: non-empty, W=10, two node_ids.
    print_subsection(
        "Branch 3: W=10, two node_ids (ascending sort) → SHA-256(\"mt-bc-aggregate\" || concat(sorted) || W_le8)",
    );
    let w3: u64 = 10;
    let id_a: NodeId = [0x11; 32];
    let id_b: NodeId = [0x22; 32];
    // Pass in reverse order — the function must sort on its own.
    let cba_pair_unsorted = cemented_bundle_aggregate(w3, &[id_b, id_a]);
    let cba_pair_sorted = cemented_bundle_aggregate(w3, &[id_a, id_b]);
    print_kv("cba(W=10, [B, A])", hex_full(&cba_pair_unsorted));
    print_kv("cba(W=10, [A, B])", hex_full(&cba_pair_sorted));
    let order_invariant = cba_pair_unsorted == cba_pair_sorted;
    print_kv(
        "order-invariant (sorts itself)",
        format!("{order_invariant}"),
    );

    // Manual computation.
    let mut concat: Vec<u8> = Vec::with_capacity(64);
    concat.extend_from_slice(&id_a);
    concat.extend_from_slice(&id_b);
    let manual_pair: Hash32 = hash(domain::BC_AGGREGATE, &[&concat, &w3.to_le_bytes()]);
    print_kv("manual hash", hex_full(&manual_pair));
    let manual_match = cba_pair_sorted == manual_pair;
    print_kv("byte-exact match", format!("{manual_match}"));

    // Domain difference: empty branch ≠ non-empty branch.
    print_subsection("Domain separation: empty branch ≠ non-empty branch for the same W");
    let cba_empty_w10 = cemented_bundle_aggregate(w3, &[]);
    let domain_distinct = cba_empty_w10 != cba_pair_sorted;
    print_kv("cba(10, []) ≠ cba(10, [A,B])", format!("{domain_distinct}"));

    let pass = b1_pass && b2_pass && order_invariant && manual_match && domain_distinct;
    println!(
        "\n[result] CBA-BRANCHES: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

// Helpers: build deterministic test records.
fn make_account(seed_byte: u8, account_id_byte: u8) -> AccountRecord {
    AccountRecord {
        account_id: [account_id_byte; 32],
        balance: 1_000_000_000_000_u128 + u128::from(seed_byte) * 1_000_000_u128,
        suite_id: 0x0001,
        is_node_operator: seed_byte == 1,
        frontier_hash: [seed_byte; 32],
        op_height: u32::from(seed_byte) * 7,
        account_chain_length: u32::from(seed_byte) * 11,
        account_chain_length_snapshot: u32::from(seed_byte) * 11,
        current_pubkey: [seed_byte; PUBLIC_KEY_SIZE],
        creation_window: u32::from(seed_byte) * 100,
        last_op_window: u32::from(seed_byte) * 100 + 5,
        last_activation_window: u32::from(seed_byte) * 100,
    }
}

fn make_node(seed_byte: u8, operator_id: AccountId) -> NodeRecord {
    NodeRecord {
        node_id: [seed_byte ^ 0x80; 32],
        node_pubkey: [seed_byte ^ 0x80; PUBLIC_KEY_SIZE],
        suite_id: 0x0001,
        operator_account_id: operator_id,
        start_window: u64::from(seed_byte) * 50,
        chain_length: u64::from(seed_byte) * 200,
        chain_length_snapshot: u64::from(seed_byte) * 200,
        chain_length_checkpoints: [u64::from(seed_byte) * 200; 6],
        last_confirmation_window: u64::from(seed_byte) * 200 + 10,
    }
}

fn make_candidate(seed_byte: u8, operator_id: AccountId) -> CandidateRecord {
    CandidateRecord {
        node_id: [seed_byte ^ 0xC0; 32],
        node_pubkey: [seed_byte ^ 0xC0; PUBLIC_KEY_SIZE],
        suite_id: 0x0001,
        operator_account_id: operator_id,
        proof_endpoint: [seed_byte; 32],
        w_start: u64::from(seed_byte) * 30,
        ssha_chain_length: u64::from(seed_byte) * 1000,
        registration_window: u64::from(seed_byte) * 30,
        expires: u64::from(seed_byte) * 30 + 60480,
    }
}

fn cmd_state_root_compose() -> bool {
    print_section("STATE ROOT COMPOSITION — 3 accounts + 2 nodes + 1 candidate");
    print_note(
        "spec line 1269: state_root = SHA-256(\"mt-state-root\" || node_root || candidate_root || account_root). Order: node, candidate, account.",
    );

    let mut accounts = AccountTable::new();
    let acc1 = make_account(1, 0x01);
    let acc2 = make_account(2, 0x02);
    let acc3 = make_account(3, 0x03);
    accounts.insert(acc1.clone());
    accounts.insert(acc2.clone());
    accounts.insert(acc3.clone());

    let mut nodes = NodeTable::new();
    let node1 = make_node(1, acc1.account_id);
    let node2 = make_node(2, acc2.account_id);
    nodes.insert(node1.clone());
    nodes.insert(node2.clone());

    let mut candidates = CandidatePool::new();
    let cand1 = make_candidate(7, acc3.account_id);
    candidates.insert(cand1);

    print_subsection("Sub-roots");
    let acct_root = accounts.root();
    let node_root = nodes.root();
    let cand_root = candidates.root();
    print_kv("account_root", hex_full(&acct_root));
    print_kv("node_root", hex_full(&node_root));
    print_kv("candidate_root", hex_full(&cand_root));

    print_subsection("compute_state_root vs manual hash composition");
    let lib_root = compute_state_root(&node_root, &cand_root, &acct_root);
    let manual_root: Hash32 = hash(domain::STATE_ROOT, &[&node_root, &cand_root, &acct_root]);
    print_kv("compute_state_root", hex_full(&lib_root));
    print_kv("manual SHA-256", hex_full(&manual_root));
    let composition_ok = lib_root == manual_root;
    print_kv("byte-exact match", format!("{composition_ok}"));

    print_subsection("Determinism: rebuild the tables from scratch → root is byte-for-byte the same");
    let mut accounts2 = AccountTable::new();
    accounts2.insert(make_account(3, 0x03));
    accounts2.insert(make_account(1, 0x01));
    accounts2.insert(make_account(2, 0x02));
    let acct_root2 = accounts2.root();
    let det_ok = acct_root == acct_root2;
    print_kv("insert-order invariance (BTreeMap)", format!("{det_ok}"));

    print_subsection("Sub-root sensitivity: change one balance → state_root changes");
    let mut accounts3 = AccountTable::new();
    let mut acc1_mut = acc1.clone();
    acc1_mut.balance += 1;
    accounts3.insert(acc1_mut);
    accounts3.insert(acc2.clone());
    accounts3.insert(acc3.clone());
    let mutated_root = compute_state_root(&node_root, &cand_root, &accounts3.root());
    let sensitive = mutated_root != lib_root;
    print_kv(
        "state_root changed after balance += 1",
        format!("{sensitive}"),
    );

    let pass = composition_ok && det_ok && sensitive;
    println!(
        "\n[result] STATE-ROOT-COMPOSE: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_merkle_inclusion() -> bool {
    print_section("MERKLE INCLUSION PROOF — sparse tree depth 256, prove + verify");
    print_note(
        "spec, section \"Sparse Merkle Tree\". InclusionProof = leaf_value + 256 siblings from bottom to top. verify_proof recomputes the root.",
    );

    let mut tree = SparseMerkleTree::new();

    // One account + manual encode.
    let acc = make_account(7, 0x42);
    let mut serialized = Vec::with_capacity(2059);
    use mt_codec::CanonicalEncode;
    acc.encode(&mut serialized);
    print_kv("AccountRecord size", format!("{} bytes", serialized.len()));

    tree.insert(acc.account_id, &serialized);
    let root = tree.root();
    print_kv("root (1 leaf)", hex_full(&root));

    print_subsection("1. Prove existing key → verify_proof true");
    let proof = tree.prove(&acc.account_id, Some(&serialized));
    let exist_ok = verify_proof(&root, &proof);
    print_kv("verify_proof(root, proof)", format!("{exist_ok}"));

    print_subsection("2. Tampered leaf → verify_proof false");
    let mut bad_serialized = serialized.clone();
    bad_serialized[0] ^= 0x01;
    let bad_proof = tree.prove(&acc.account_id, Some(&bad_serialized));
    let tampered_rejected = !verify_proof(&root, &bad_proof);
    print_kv(
        "verify(tampered_leaf) == false",
        format!("{tampered_rejected}"),
    );

    print_subsection("3. Absence proof — non-existent account_id");
    let absent_id: AccountId = [0xFE; 32];
    let absent_proof = tree.prove(&absent_id, None);
    let absent_ok = verify_proof(&root, &absent_proof);
    print_kv("verify_proof(absent)", format!("{absent_ok}"));

    print_subsection("4. Cross-key fail: a proof for one key does not verify against another root");
    let mut tree2 = SparseMerkleTree::new();
    let acc_other = make_account(8, 0x55);
    let mut other_ser = Vec::with_capacity(2059);
    acc_other.encode(&mut other_ser);
    tree2.insert(acc_other.account_id, &other_ser);
    let other_root = tree2.root();
    let cross_rejected = !verify_proof(&other_root, &proof);
    print_kv(
        "verify(other_root, proof) == false",
        format!("{cross_rejected}"),
    );

    let pass = exist_ok && tampered_rejected && absent_ok && cross_rejected;
    println!(
        "\n[result] MERKLE-INCLUSION: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_all() -> bool {
    print_section("M2 TIMECHAIN + STATE — FULL SHAKEDOWN");

    let a = cmd_ssha_forward(1000);
    let b = cmd_next_d_boundaries();
    let c = cmd_cba_branches();
    let d = cmd_state_root_compose();
    let e = cmd_merkle_inclusion();

    print_section("SUMMARY");
    print_kv("ssha-forward 1000", if a { "PASS" } else { "FAIL" });
    print_kv("next-d-boundaries", if b { "PASS" } else { "FAIL" });
    print_kv("cba-branches", if c { "PASS" } else { "FAIL" });
    print_kv("state-root-compose", if d { "PASS" } else { "FAIL" });
    print_kv("merkle-inclusion", if e { "PASS" } else { "FAIL" });

    let pass = a && b && c && d && e;
    println!(
        "\n[result] ALL SCENARIOS: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn bool_to_exit(pass: bool) -> ExitCode {
    if pass {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn usage() {
    eprintln!("M2 — TimeChain (SSHA, next_d, CBA) + State (roots, merkle) shakedown");
    eprintln!();
    eprintln!("usage: m2_timechain_state <subcommand> [args]");
    eprintln!();
    eprintln!("  ssha-forward [N]        SSHA forward N steps (default 1000) vs manual SHA-256^N");
    eprintln!("  next-d-boundaries      Adaptive D — 7 binding test vectors from the spec");
    eprintln!("  cba-branches           cemented_bundle_aggregate: three branches");
    eprintln!("  state-root-compose     state_root = SHA-256(\"mt-state-root\" || ...)");
    eprintln!("  merkle-inclusion       SparseMerkleTree: prove → verify (existence + absence)");
    eprintln!("  all                    Run all 5 subcommands");
    eprintln!();
    eprintln!("Exit code 0=PASS, 1=FAIL.");
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let sub = match args.get(1) {
        Some(s) => s.as_str(),
        None => {
            usage();
            return ExitCode::FAILURE;
        },
    };
    let pass = match sub {
        "ssha-forward" => {
            let n: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1000);
            cmd_ssha_forward(n)
        },
        "next-d-boundaries" => cmd_next_d_boundaries(),
        "cba-branches" => cmd_cba_branches(),
        "state-root-compose" => cmd_state_root_compose(),
        "merkle-inclusion" => cmd_merkle_inclusion(),
        "all" => cmd_all(),
        _ => {
            usage();
            return ExitCode::FAILURE;
        },
    };
    bool_to_exit(pass)
}
