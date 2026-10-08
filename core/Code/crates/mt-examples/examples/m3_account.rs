// M3 — Account operations shakedown.
// Subcommands:
//   genesis-state        build_genesis_state(params): empty window 0 (no bootstrap operator)
//   open-account         TransferActivation: sponsor → new account
//   transfer-scenario    sponsor → A → B → Transfer A→B 50% balance
//   change-key           ChangeKey: rotate pk; old pk → InvalidSignature on the next op
//   anchor               Anchor: chain payload hashes
//   emission-schedule [W1 W2 ...]  reward + supply ledger
//   validation-rejects   6 OpError cases REJECTED byte-for-byte
//   all                  Run all 7
//
// Exit code 0=PASS, 1=FAIL.

use std::env;
use std::process::ExitCode;

use mt_account::{
    apply, build_genesis_state, genesis_state_root, op_hash, reward_moneta, supply_moneta,
    validate_anchor, validate_change_key, validate_transfer, validate_transfer_activation, Anchor,
    ChangeKey, GenesisState, OpError, Operation, Transfer, TransferActivation,
};
use mt_crypto::{keypair_from_seed, sign, PublicKey, SecretKey, KEYPAIR_SEED_SIZE};
use mt_examples::{hex_full, print_kv, print_note, print_section, print_subsection};
use mt_genesis::genesis_params;
use mt_state::{derive_account_id, AccountId, AccountRecord, AccountTable};

const SUITE_ID: u16 = 0x0001;

// ---- helpers ----

// Deterministic keypair from a seed byte (repeatable across runs).
fn kp(seed_byte: u8) -> (PublicKey, SecretKey) {
    let mut seed = [0u8; KEYPAIR_SEED_SIZE];
    seed[0] = seed_byte;
    seed[31] = seed_byte ^ 0xAA; // entropy
    keypair_from_seed(&seed).expect("keypair_from_seed")
}

// Short pubkey fingerprint (8 bytes) for display.
fn pk8(pk: &PublicKey) -> String {
    hex_full(&pk.as_bytes()[..8])
}

// Create a sponsor account with an explicit balance — synthetic setup without build_genesis_state.
fn synthetic_sponsor(state: &mut AccountTable, pk: &PublicKey, balance: u128) -> AccountId {
    let account_id = derive_account_id(SUITE_ID, pk.as_bytes());
    let frontier = mt_crypto::hash(mt_codec::domain::GENESIS, &[&account_id]);
    state.insert(AccountRecord {
        account_id,
        balance,
        suite_id: SUITE_ID,
        is_node_operator: false,
        frontier_hash: frontier,
        op_height: 0,
        account_chain_length: 0,
        account_chain_length_snapshot: 0,
        current_pubkey: *pk.as_bytes(),
        creation_window: 0,
        last_op_window: 0,
        last_activation_window: 0,
    });
    account_id
}

// ---- operation builders ----

fn mk_transfer_activation(
    sponsor_id: AccountId,
    sponsor_sk: &SecretKey,
    receiver_pk: &PublicKey,
    amount: u128,
    prev_hash: mt_crypto::Hash32,
) -> TransferActivation {
    let receiver_id = derive_account_id(SUITE_ID, receiver_pk.as_bytes());
    let mut op = TransferActivation {
        prev_hash,
        sender: sponsor_id,
        receiver: receiver_id,
        suite_id: SUITE_ID,
        receiver_pubkey: receiver_pk.clone(),
        amount,
        signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
    };
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    op.signature = sign(sponsor_sk, &scope).expect("sign TransferActivation");
    op
}

fn mk_transfer(
    sender_id: AccountId,
    sender_sk: &SecretKey,
    link_id: AccountId,
    amount: u128,
    prev_hash: mt_crypto::Hash32,
) -> Transfer {
    let mut op = Transfer {
        prev_hash,
        sender: sender_id,
        link: link_id,
        amount,
        signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
    };
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    op.signature = sign(sender_sk, &scope).expect("sign Transfer");
    op
}

fn mk_change_key(
    sender_id: AccountId,
    old_sk: &SecretKey,
    new_pk: &PublicKey,
    prev_hash: mt_crypto::Hash32,
) -> ChangeKey {
    let mut op = ChangeKey {
        prev_hash,
        sender: sender_id,
        new_suite_id: SUITE_ID,
        new_pubkey: new_pk.clone(),
        signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
    };
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    op.signature = sign(old_sk, &scope).expect("sign ChangeKey");
    op
}

fn mk_anchor(
    sender_id: AccountId,
    sk: &SecretKey,
    app_id: [u8; 32],
    data_hash: [u8; 32],
    prev_hash: mt_crypto::Hash32,
) -> Anchor {
    let mut op = Anchor {
        prev_hash,
        sender: sender_id,
        app_id,
        data_hash,
        signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
    };
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    op.signature = sign(sk, &scope).expect("sign Anchor");
    op
}

// ---- subcommands ----

fn cmd_genesis_state() -> bool {
    print_section("GENESIS STATE — build_genesis_state(params) sanity");
    print_note(
        "spec, section \"Genesis Decree\": Genesis = empty window 0. No baked bootstrap operator — all three tables are empty; roots = root of the empty sparse-Merkle tree. The first node self-admits (selection_slots(0)=1) and self-cements (quorum(1)=1).",
    );

    let params = genesis_params();
    let GenesisState {
        account_table,
        node_table,
        candidate_pool,
    } = build_genesis_state(params);

    print_subsection("Tables population (empty genesis)");
    let acc_count = account_table.len();
    let node_count = node_table.len();
    let cand_count = candidate_pool.len();
    print_kv("AccountTable rows", format!("{acc_count}"));
    print_kv("NodeTable rows", format!("{node_count}"));
    print_kv("CandidatePool rows", format!("{cand_count}"));

    print_subsection("Empty sparse-Merkle roots");
    let empty_root = mt_merkle::empty_internal(mt_merkle::TREE_DEPTH);
    print_kv("account_table.root()", hex_full(&account_table.root()));
    print_kv("node_table.root()", hex_full(&node_table.root()));
    print_kv("candidate_pool.root()", hex_full(&candidate_pool.root()));
    print_kv("empty_internal(256)", hex_full(&empty_root));
    let roots_empty = account_table.root() == empty_root
        && node_table.root() == empty_root
        && candidate_pool.root() == empty_root;
    print_kv("all three == empty_internal(256)", format!("{roots_empty}"));

    print_subsection("genesis_state_root determinism");
    let genesis_state = build_genesis_state(params);
    let r1 = genesis_state_root(&genesis_state);
    let r2 = genesis_state_root(&build_genesis_state(params));
    print_kv("root run #1", hex_full(&r1));
    print_kv("root run #2", hex_full(&r2));
    let det = r1 == r2;
    print_kv("byte-exact determinism", format!("{det}"));

    print_subsection("Genesis State Hash");
    let gsh = mt_genesis::compute_genesis_state_hash(&r1, params);
    print_kv("compute_genesis_state_hash", hex_full(&gsh));

    let pass = acc_count == 0 && node_count == 0 && cand_count == 0 && roots_empty && det;
    println!(
        "\n[result] GENESIS-STATE: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_open_account() -> bool {
    print_section("OPEN ACCOUNT — TransferActivation from sponsor creates receiver");
    print_note(
        "spec, sections \"TransferActivation\" + \"Account Chain (Block Lattice)\": sender balance -= amount, receiver = new AccountRecord with balance = amount, receiver frontier_hash = 0x00 ... (receiver chain genesis), sender frontier_hash = op_hash.",
    );

    let mut state = AccountTable::new();
    let (sponsor_pk, sponsor_sk) = kp(0x01);
    let (alice_pk, _alice_sk) = kp(0x02);
    let sponsor_id = synthetic_sponsor(&mut state, &sponsor_pk, 1_000_000);
    let sponsor_frontier = state.get(&sponsor_id).unwrap().frontier_hash;

    print_subsection("Pre-state");
    print_kv("sponsor balance", "1_000_000");
    print_kv("alice balance", "—");
    print_kv("sponsor frontier", hex_full(&sponsor_frontier));

    let op = mk_transfer_activation(
        sponsor_id,
        &sponsor_sk,
        &alice_pk,
        100_000,
        sponsor_frontier,
    );
    let opc = Operation::TransferActivation(op.clone());
    print_subsection("Operation");
    print_kv("amount", format!("{}", op.amount));
    print_kv("receiver_pk(8B)", pk8(&alice_pk));
    let h = op_hash(&opc);
    print_kv("op_hash", hex_full(&h));
    let h2 = op_hash(&opc);
    print_kv("op_hash recompute", hex_full(&h2));
    print_kv(
        "op_hash deterministic (R2: identifier(op) = SHA-256(\"mt-op\" || signed_scope))",
        format!("{}", h == h2),
    );

    print_subsection("Validate");
    let r = validate_transfer_activation(&op, &state, /*W*/ 1000, /*τ₂*/ 20160);
    print_kv("validate", format!("{r:?}"));
    if r.is_err() {
        println!("\n[result] OPEN-ACCOUNT: FAIL");
        return false;
    }

    apply(&opc, &mut state, /*W*/ 1000);

    print_subsection("Post-state");
    let sponsor_after = state.get(&sponsor_id).unwrap();
    let alice_id = derive_account_id(SUITE_ID, alice_pk.as_bytes());
    let alice_after = state.get(&alice_id).expect("alice created");

    print_kv("sponsor balance", format!("{}", sponsor_after.balance));
    print_kv("alice balance", format!("{}", alice_after.balance));
    print_kv(
        "sponsor account_chain_length",
        format!("{}", sponsor_after.account_chain_length),
    );
    print_kv(
        "alice account_chain_length",
        format!("{}", alice_after.account_chain_length),
    );
    print_kv(
        "sponsor frontier (new)",
        hex_full(&sponsor_after.frontier_hash),
    );
    print_kv(
        "alice frontier (genesis)",
        hex_full(&alice_after.frontier_hash),
    );

    let pass = sponsor_after.balance == 900_000
        && alice_after.balance == 100_000
        && sponsor_after.account_chain_length == 1
        && alice_after.account_chain_length == 0
        && alice_after.last_activation_window == 0
        && sponsor_after.last_activation_window == 1000;
    println!(
        "\n[result] OPEN-ACCOUNT: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_transfer_scenario() -> bool {
    print_section("TRANSFER SCENARIO — sponsor → A → B → Transfer A→B 50%");
    print_note(
        "Full chain: 2× TransferActivation (create A, B), then Transfer A→B. Σ delta_balance = 0 after each step. spec, sections \"TransferActivation\" + \"Transfer\".",
    );

    let mut state = AccountTable::new();
    let (sponsor_pk, sponsor_sk) = kp(0x10);
    let (alice_pk, alice_sk) = kp(0x11);
    let (bob_pk, _bob_sk) = kp(0x12);
    let sponsor_id = synthetic_sponsor(&mut state, &sponsor_pk, 1_000_000);

    // Step 1: sponsor → alice (creation).
    print_subsection("Step 1: sponsor → alice (TransferActivation 200_000), W=100");
    let f1 = state.get(&sponsor_id).unwrap().frontier_hash;
    let op1 = mk_transfer_activation(sponsor_id, &sponsor_sk, &alice_pk, 200_000, f1);
    validate_transfer_activation(&op1, &state, 100, 20160).expect("step 1 validate");
    apply(&Operation::TransferActivation(op1.clone()), &mut state, 100);
    let alice_id = derive_account_id(SUITE_ID, alice_pk.as_bytes());
    print_kv(
        "sponsor balance",
        format!("{}", state.get(&sponsor_id).unwrap().balance),
    );
    print_kv(
        "alice balance",
        format!("{}", state.get(&alice_id).unwrap().balance),
    );

    // Step 2: sponsor → bob (creation). Cooldown τ₂ — hence W=100+20160=20260.
    print_subsection(
        "Step 2: sponsor → bob (TransferActivation 100_000), W=20260 (after cooldown τ₂)",
    );
    let f2 = state.get(&sponsor_id).unwrap().frontier_hash;
    let op2 = mk_transfer_activation(sponsor_id, &sponsor_sk, &bob_pk, 100_000, f2);
    validate_transfer_activation(&op2, &state, 20260, 20160).expect("step 2 validate");
    apply(
        &Operation::TransferActivation(op2.clone()),
        &mut state,
        20260,
    );
    let bob_id = derive_account_id(SUITE_ID, bob_pk.as_bytes());
    print_kv(
        "sponsor balance",
        format!("{}", state.get(&sponsor_id).unwrap().balance),
    );
    print_kv(
        "bob balance",
        format!("{}", state.get(&bob_id).unwrap().balance),
    );

    // Step 3: Alice → Bob, 50% of Alice balance = 100_000.
    print_subsection("Step 3: Alice → Bob (Transfer 100_000)");
    let alice_frontier = state.get(&alice_id).unwrap().frontier_hash;
    let alice_balance_before = state.get(&alice_id).unwrap().balance;
    let bob_balance_before = state.get(&bob_id).unwrap().balance;
    let op3 = mk_transfer(alice_id, &alice_sk, bob_id, 100_000, alice_frontier);
    let validate_r = validate_transfer(&op3, &state);
    print_kv("validate Transfer", format!("{validate_r:?}"));
    apply(&Operation::Transfer(op3.clone()), &mut state, 20300);

    let alice_after = state.get(&alice_id).unwrap();
    let bob_after = state.get(&bob_id).unwrap();
    print_kv("alice balance", format!("{}", alice_after.balance));
    print_kv("bob balance", format!("{}", bob_after.balance));
    print_kv(
        "alice account_chain_length",
        format!("{}", alice_after.account_chain_length),
    );
    print_kv("alice frontier_hash", hex_full(&alice_after.frontier_hash));

    print_subsection("Conservation: Σ delta_balance == 0 for Transfer step");
    let alice_delta: i128 = alice_after.balance as i128 - alice_balance_before as i128;
    let bob_delta: i128 = bob_after.balance as i128 - bob_balance_before as i128;
    let total_delta = alice_delta + bob_delta;
    print_kv("alice delta", format!("{alice_delta}"));
    print_kv("bob delta", format!("{bob_delta}"));
    print_kv("total delta (Σ)", format!("{total_delta}"));

    let pass = validate_r.is_ok()
        && alice_after.balance == 100_000
        && bob_after.balance == 200_000
        && alice_after.account_chain_length == 1
        && bob_after.account_chain_length == 0
        && alice_delta == -100_000
        && bob_delta == 100_000
        && total_delta == 0;
    println!(
        "\n[result] TRANSFER-SCENARIO: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_change_key() -> bool {
    print_section("CHANGE KEY — rotate pubkey, signature transition");
    print_note(
        "spec, section \"ChangeKey\": op is signed with the OLD key (current_pubkey in state before apply). After apply: state.current_pubkey = new_pubkey. The next op is signed with the new key.",
    );

    let mut state = AccountTable::new();
    let (sponsor_pk, sponsor_sk_old) = kp(0x20);
    let (new_pk, sponsor_sk_new) = kp(0x21);
    let acc_id = synthetic_sponsor(&mut state, &sponsor_pk, 500_000);
    let f0 = state.get(&acc_id).unwrap().frontier_hash;

    print_subsection("Pre-state");
    print_kv("current_pubkey (old, 8B)", pk8(&sponsor_pk));

    print_subsection("ChangeKey signed by OLD sk");
    let op_change = mk_change_key(acc_id, &sponsor_sk_old, &new_pk, f0);
    let r1 = validate_change_key(&op_change, &state);
    print_kv("validate (old sk → ok)", format!("{r1:?}"));
    apply(&Operation::ChangeKey(op_change.clone()), &mut state, 500);

    let after_change = state.get(&acc_id).unwrap();
    print_kv(
        "current_pubkey now (8B)",
        pk8(&PublicKey::from_array(after_change.current_pubkey)),
    );
    let pk_rotated = after_change.current_pubkey == *new_pk.as_bytes();

    print_subsection("Anchor signed with NEW sk → must validate");
    let f1 = after_change.frontier_hash;
    let op_anchor_new = mk_anchor(acc_id, &sponsor_sk_new, [0xAB; 32], [0xCD; 32], f1);
    let r2 = validate_anchor(&op_anchor_new, &state);
    print_kv("validate (new sk)", format!("{r2:?}"));

    print_subsection("Anchor signed with OLD sk → must be rejected");
    let op_anchor_old = mk_anchor(acc_id, &sponsor_sk_old, [0xAB; 32], [0xCD; 32], f1);
    let r3 = validate_anchor(&op_anchor_old, &state);
    print_kv("validate (old sk)", format!("{r3:?}"));
    let old_rejected = matches!(r3, Err(OpError::InvalidSignature));

    let pass = r1.is_ok() && pk_rotated && r2.is_ok() && old_rejected;
    println!(
        "\n[result] CHANGE-KEY: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_anchor() -> bool {
    print_section("ANCHOR — chain payload hashes");
    print_note(
        "spec, section \"Anchor\": user opcode records the hash of off-chain content in the chain. Multiple anchors form a chain via frontier_hash linkage.",
    );

    let mut state = AccountTable::new();
    let (pk, sk) = kp(0x30);
    let acc_id = synthetic_sponsor(&mut state, &pk, 100_000);

    let mut prev = state.get(&acc_id).unwrap().frontier_hash;
    let mut applied_count = 0u32;
    for i in 1u8..=3 {
        print_subsection(&format!("Anchor #{i}"));
        let op = mk_anchor(acc_id, &sk, [i; 32], [i ^ 0xAA; 32], prev);
        let r = validate_anchor(&op, &state);
        print_kv("validate", format!("{r:?}"));
        if r.is_err() {
            break;
        }
        apply(
            &Operation::Anchor(op.clone()),
            &mut state,
            u64::from(i) * 10,
        );
        let after = state.get(&acc_id).unwrap();
        print_kv("frontier_hash", hex_full(&after.frontier_hash));
        print_kv(
            "account_chain_length",
            format!("{}", after.account_chain_length),
        );
        prev = after.frontier_hash;
        applied_count += 1;
    }

    let final_state = state.get(&acc_id).unwrap();
    let pass = applied_count == 3
        && final_state.account_chain_length == 3
        && final_state.balance == 100_000;

    println!("\n[result] ANCHOR: {}", if pass { "PASS" } else { "FAIL" });
    pass
}

fn cmd_emission_schedule(windows: &[u64]) -> bool {
    print_section("EMISSION SCHEDULE — reward + supply ledger");
    print_note(
        "spec, section \"Emission\": reward_moneta = EMISSION_moneta = 13 Ɉ const per window. supply_moneta(W) = W × EMISSION_moneta.",
    );

    let params = genesis_params();
    let reward = reward_moneta(params);
    print_kv("EMISSION_moneta (per window)", format!("{reward} nɈ"));

    let mut all_match = true;
    print_subsection("Schedule");
    for &w in windows {
        let supply = supply_moneta(w, params);
        let expected = u128::from(w) * reward;
        let ok = supply == expected;
        print_kv(
            &format!("W = {w:8}"),
            format!(
                "supply = {supply:20} nɈ (expected {expected}) {}",
                if ok { "✓" } else { "✗" }
            ),
        );
        if !ok {
            all_match = false;
        }
    }

    print_subsection("Linearity sanity");
    let s_a = supply_moneta(1000, params);
    let s_b = supply_moneta(2000, params);
    let diff = s_b - s_a;
    let expected_diff = u128::from(1000u64) * reward;
    print_kv("supply(2000) - supply(1000)", format!("{diff} nɈ"));
    print_kv("expected (1000 × reward)", format!("{expected_diff}"));
    let lin_ok = diff == expected_diff;

    let pass = all_match && lin_ok && reward > 0;
    println!(
        "\n[result] EMISSION-SCHEDULE: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_validation_rejects() -> bool {
    print_section("VALIDATION REJECTS — 10 adversarial cases");
    print_note(
        "Ten OpError cases must be REJECTED by the validate_* detection rules. spec, sections \"Account Chain (Block Lattice) → Verification\" + \"Anti-spam\".",
    );

    let mut state = AccountTable::new();
    let (alice_pk, alice_sk) = kp(0x40);
    let (bob_pk, bob_sk) = kp(0x41);
    let (charlie_pk, _charlie_sk) = kp(0x42);
    let (dave_pk, _dave_sk) = kp(0x43);
    let alice_id = synthetic_sponsor(&mut state, &alice_pk, 500_000);
    let bob_id = synthetic_sponsor(&mut state, &bob_pk, 100_000);

    let alice_frontier = state.get(&alice_id).unwrap().frontier_hash;
    let mut all_correctly_rejected = true;

    fn report(label: &str, expected: &str, actual: &Result<(), OpError>, matches: bool) {
        print_kv("validate", format!("{actual:?}"));
        print_kv("expected", format!("{expected} — rule: {label}"));
        print_kv(
            "verdict",
            if matches {
                "REJECTED ✓"
            } else {
                "ACCEPTED ✗"
            },
        );
    }

    // 1. InsufficientBalance.
    print_subsection("1. InsufficientBalance — Transfer amount > sender balance");
    let op = mk_transfer(alice_id, &alice_sk, bob_id, 1_000_000, alice_frontier);
    let r = validate_transfer(&op, &state);
    let m = matches!(r, Err(OpError::InsufficientBalance));
    report(
        "amount=1_000_000 > balance=500_000",
        "InsufficientBalance",
        &r,
        m,
    );
    if !m {
        all_correctly_rejected = false;
    }

    // 2. SelfTransfer.
    print_subsection("2. SelfTransfer — sender == link");
    let op = mk_transfer(alice_id, &alice_sk, alice_id, 100, alice_frontier);
    let r = validate_transfer(&op, &state);
    let m = matches!(r, Err(OpError::SelfTransfer));
    report("Alice → Alice", "SelfTransfer", &r, m);
    if !m {
        all_correctly_rejected = false;
    }

    // 3. ZeroAmount.
    print_subsection("3. ZeroAmount — Transfer amount = 0");
    let op = mk_transfer(alice_id, &alice_sk, bob_id, 0, alice_frontier);
    let r = validate_transfer(&op, &state);
    let m = matches!(r, Err(OpError::ZeroAmount));
    report("amount=0", "ZeroAmount", &r, m);
    if !m {
        all_correctly_rejected = false;
    }

    // 4. InvalidPrevHash.
    print_subsection("4. InvalidPrevHash — prev_hash != sender.frontier_hash");
    let op = mk_transfer(alice_id, &alice_sk, bob_id, 100, [0xFF; 32]);
    let r = validate_transfer(&op, &state);
    let m = matches!(r, Err(OpError::InvalidPrevHash));
    report("stale prev_hash 0xFF×32", "InvalidPrevHash", &r, m);
    if !m {
        all_correctly_rejected = false;
    }

    // 5. InvalidSignature.
    print_subsection("5. InvalidSignature — signature by another sk");
    let op = mk_transfer(alice_id, &bob_sk, bob_id, 100, alice_frontier);
    let r = validate_transfer(&op, &state);
    let m = matches!(r, Err(OpError::InvalidSignature));
    report("Alice's op signed with Bob's sk", "InvalidSignature", &r, m);
    if !m {
        all_correctly_rejected = false;
    }

    // 6. ReceiverAlreadyExists.
    print_subsection("6. ReceiverAlreadyExists — TransferActivation for an already-existing receiver");
    let op = mk_transfer_activation(alice_id, &alice_sk, &bob_pk, 100, alice_frontier);
    let r = validate_transfer_activation(&op, &state, 5000, 20160);
    let m = matches!(r, Err(OpError::ReceiverAlreadyExists));
    report("Bob already in AccountTable", "ReceiverAlreadyExists", &r, m);
    if !m {
        all_correctly_rejected = false;
    }

    // 7. ActivationCooldownNotElapsed.
    print_subsection("7. ActivationCooldownNotElapsed — second TransferActivation before τ₂");
    let mut state_cd = state.clone();
    let f0 = state_cd.get(&alice_id).unwrap().frontier_hash;
    let op_first = mk_transfer_activation(alice_id, &alice_sk, &charlie_pk, 100, f0);
    apply(&Operation::TransferActivation(op_first), &mut state_cd, 100);
    let f1 = state_cd.get(&alice_id).unwrap().frontier_hash;
    let op_second = mk_transfer_activation(alice_id, &alice_sk, &dave_pk, 100, f1);
    let r = validate_transfer_activation(&op_second, &state_cd, 200, 20160);
    let m = matches!(r, Err(OpError::ActivationCooldownNotElapsed));
    report(
        "apply at W=100, validate at W=200 < 100+τ₂",
        "ActivationCooldownNotElapsed",
        &r,
        m,
    );
    if !m {
        all_correctly_rejected = false;
    }

    // 8. UnsupportedSuite.
    print_subsection("8. UnsupportedSuite — TransferActivation with suite_id = 0xFFFF");
    let receiver_id_bad = derive_account_id(0xFFFF, dave_pk.as_bytes());
    let mut op = TransferActivation {
        prev_hash: alice_frontier,
        sender: alice_id,
        receiver: receiver_id_bad,
        suite_id: 0xFFFF,
        receiver_pubkey: dave_pk.clone(),
        amount: 100,
        signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
    };
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    op.signature = sign(&alice_sk, &scope).expect("sign 0xFFFF suite");
    let r = validate_transfer_activation(&op, &state, 5000, 20160);
    let m = matches!(r, Err(OpError::UnsupportedSuite));
    report(
        "suite_id = 0xFFFF is not registered",
        "UnsupportedSuite",
        &r,
        m,
    );
    if !m {
        all_correctly_rejected = false;
    }

    // 9. AccountNotFound.
    print_subsection("9. AccountNotFound — Transfer from an account_id not in AccountTable");
    let phantom_id: AccountId = [0xDE; 32];
    let op = mk_transfer(phantom_id, &alice_sk, bob_id, 100, alice_frontier);
    let r = validate_transfer(&op, &state);
    let m = matches!(r, Err(OpError::AccountNotFound));
    report("phantom sender 0xDE×32", "AccountNotFound", &r, m);
    if !m {
        all_correctly_rejected = false;
    }

    // 10. InvalidBinding.
    print_subsection("10. InvalidBinding — receiver_id not derived from (suite_id, receiver_pubkey)");
    let mut op = TransferActivation {
        prev_hash: alice_frontier,
        sender: alice_id,
        receiver: [0x00; 32],
        suite_id: SUITE_ID,
        receiver_pubkey: dave_pk.clone(),
        amount: 100,
        signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
    };
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    op.signature = sign(&alice_sk, &scope).expect("sign bad binding");
    let r = validate_transfer_activation(&op, &state, 5000, 20160);
    let m = matches!(r, Err(OpError::InvalidBinding));
    report(
        "receiver = 0x00×32 ≠ derive_account_id(suite, pk)",
        "InvalidBinding",
        &r,
        m,
    );
    if !m {
        all_correctly_rejected = false;
    }

    // Sanity positive.
    print_subsection("Sanity positive — legitimate TransferActivation Alice → Charlie");
    let op = mk_transfer_activation(alice_id, &alice_sk, &charlie_pk, 100, alice_frontier);
    let r = validate_transfer_activation(&op, &state, 5000, 20160);
    print_kv("validate", format!("{r:?}"));
    let positive_ok = r.is_ok();
    print_kv(
        "verdict",
        if positive_ok {
            "ACCEPTED ✓"
        } else {
            "REJECTED ✗"
        },
    );

    let pass = all_correctly_rejected && positive_ok;
    println!(
        "\n[result] VALIDATION-REJECTS: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_all() -> bool {
    print_section("M3 ACCOUNT — FULL SHAKEDOWN");

    let a = cmd_genesis_state();
    let b = cmd_open_account();
    let c = cmd_transfer_scenario();
    let d = cmd_change_key();
    let e = cmd_anchor();
    let f = cmd_emission_schedule(&[0, 100, 1000, 20160, 1_000_000]);
    let g = cmd_validation_rejects();

    print_section("SUMMARY");
    print_kv("genesis-state", if a { "PASS" } else { "FAIL" });
    print_kv("open-account", if b { "PASS" } else { "FAIL" });
    print_kv("transfer-scenario", if c { "PASS" } else { "FAIL" });
    print_kv("change-key", if d { "PASS" } else { "FAIL" });
    print_kv("anchor", if e { "PASS" } else { "FAIL" });
    print_kv("emission-schedule", if f { "PASS" } else { "FAIL" });
    print_kv("validation-rejects", if g { "PASS" } else { "FAIL" });

    let pass = a && b && c && d && e && f && g;
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
    eprintln!("M3 — Account operations shakedown");
    eprintln!();
    eprintln!("usage: m3_account <subcommand> [args]");
    eprintln!();
    eprintln!("  genesis-state               build_genesis_state(params): empty window 0");
    eprintln!("  open-account                TransferActivation: sponsor → new account");
    eprintln!("  transfer-scenario           sponsor → A → B → Transfer A→B");
    eprintln!("  change-key                  ChangeKey: pk rotation + signature transition");
    eprintln!("  anchor                      Anchor: chain payload hashes");
    eprintln!("  emission-schedule [W ...]   reward + supply ledger");
    eprintln!("  validation-rejects          6 OpError adversarial cases");
    eprintln!("  all                         Run all 7");
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
        "genesis-state" => cmd_genesis_state(),
        "open-account" => cmd_open_account(),
        "transfer-scenario" => cmd_transfer_scenario(),
        "change-key" => cmd_change_key(),
        "anchor" => cmd_anchor(),
        "emission-schedule" => {
            let ws: Vec<u64> = args[2..].iter().filter_map(|s| s.parse().ok()).collect();
            let default = vec![0u64, 100, 1000, 20160, 1_000_000];
            let use_args: &[u64] = if ws.is_empty() { &default } else { &ws };
            cmd_emission_schedule(use_args)
        },
        "validation-rejects" => cmd_validation_rejects(),
        "all" => cmd_all(),
        _ => {
            usage();
            return ExitCode::FAILURE;
        },
    };
    bool_to_exit(pass)
}
