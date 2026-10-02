// Automated determinism invariants для mt-account.
// M3 audit prep — operation processing layer; любое non-determinism
// = consensus fork. Invariants ловят regression если refactor случайно
// ломает byte-exact apply semantics, op_hash stability, либо state
// transition determinism.

use mt_account::{
    apply, apply_anchor, apply_change_key, apply_proposal, apply_transfer, build_genesis_state,
    op_hash, reward_moneta, settle_window, supply_moneta, validate_transfer, Anchor, ChangeKey,
    Operation, ProposalSettle, Transfer, TransferActivation, ANCHOR_SIZE, CHANGE_KEY_SIZE,
    GENESIS_SUITE_ID, TRANSFER_ACTIVATION_SIZE, TRANSFER_SIZE, TYPE_ANCHOR, TYPE_CHANGE_KEY,
    TYPE_TRANSFER, TYPE_TRANSFER_ACTIVATION,
};
use mt_codec::CanonicalEncode;
use mt_crypto::{PublicKey, Signature, PUBLIC_KEY_SIZE, SIGNATURE_SIZE};
use mt_state::{AccountRecord, AccountTable, NodeRecord, NodeTable};

// ---------- Helpers ----------

fn sample_account(id_byte: u8, balance: u128) -> AccountRecord {
    AccountRecord {
        account_id: [id_byte; 32],
        balance,
        suite_id: 1,
        is_node_operator: false,
        frontier_hash: [0xBB; 32],
        op_height: 0,
        account_chain_length: 0,
        account_chain_length_snapshot: 0,
        current_pubkey: [0xCC; PUBLIC_KEY_SIZE],
        creation_window: 0,
        last_op_window: 0,
        last_activation_window: 0,
    }
}

fn sample_transfer(sender: [u8; 32], link: [u8; 32], amount: u128) -> Transfer {
    Transfer {
        prev_hash: [0xBB; 32],
        sender,
        link,
        amount,
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    }
}

fn sample_anchor(sender: [u8; 32]) -> Anchor {
    Anchor {
        prev_hash: [0xBB; 32],
        sender,
        app_id: [0x11; 32],
        data_hash: [0x22; 32],
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    }
}

fn sample_change_key(sender: [u8; 32]) -> ChangeKey {
    ChangeKey {
        prev_hash: [0xBB; 32],
        sender,
        new_suite_id: 1,
        new_pubkey: PublicKey::from_array([0xDD; PUBLIC_KEY_SIZE]),
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    }
}

// Synthetic genesis-less seed: empty genesis has no node, so emission tests
// seed an operator account + its node directly.
fn seed_operator(
    accounts: &mut AccountTable,
    nodes: &mut NodeTable,
    op_byte: u8,
    node_byte: u8,
) -> ([u8; 32], [u8; 32]) {
    let account_id = [op_byte; 32];
    accounts.insert(AccountRecord {
        account_id,
        balance: 0,
        suite_id: 1,
        is_node_operator: true,
        frontier_hash: [0u8; 32],
        op_height: 0,
        account_chain_length: 0,
        account_chain_length_snapshot: 0,
        current_pubkey: [op_byte; PUBLIC_KEY_SIZE],
        creation_window: 0,
        last_op_window: 0,
        last_activation_window: 0,
    });
    let node_id = [node_byte; 32];
    nodes.insert(NodeRecord {
        node_id,
        node_pubkey: [node_byte; PUBLIC_KEY_SIZE],
        suite_id: 1,
        operator_account_id: account_id,
        start_window: 0,
        chain_length: 1,
        chain_length_snapshot: 1,
        chain_length_checkpoints: [0u64; 6],
        last_confirmation_window: 0,
    });
    (account_id, node_id)
}

// ---------- Encoded sizes match constants ([I-9] determinism) ----------

#[test]
fn transfer_encoded_size_constant() {
    let mut buf = Vec::new();
    sample_transfer([0x01; 32], [0x02; 32], 100).encode(&mut buf);
    assert_eq!(
        buf.len(),
        TRANSFER_SIZE,
        "Transfer encoded size drift: expected {}, got {}",
        TRANSFER_SIZE,
        buf.len()
    );
}

#[test]
fn change_key_encoded_size_constant() {
    let mut buf = Vec::new();
    sample_change_key([0x01; 32]).encode(&mut buf);
    assert_eq!(buf.len(), CHANGE_KEY_SIZE);
}

#[test]
fn anchor_encoded_size_constant() {
    let mut buf = Vec::new();
    sample_anchor([0x01; 32]).encode(&mut buf);
    assert_eq!(buf.len(), ANCHOR_SIZE);
}

#[test]
fn transfer_activation_encoded_size_constant() {
    let op = TransferActivation {
        prev_hash: [0xBB; 32],
        sender: [0x01; 32],
        receiver: [0x02; 32],
        suite_id: 1,
        receiver_pubkey: PublicKey::from_array([0xCC; PUBLIC_KEY_SIZE]),
        amount: 100,
        signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
    };
    let mut buf = Vec::new();
    op.encode(&mut buf);
    assert_eq!(buf.len(), TRANSFER_ACTIVATION_SIZE);
}

// ---------- Type byte stability (consensus type codes) ----------

#[test]
fn type_codes_stable() {
    // SSOT [I-10]: type codes immutable. Изменение = consensus fork.
    assert_eq!(TYPE_TRANSFER, 0x02);
    assert_eq!(TYPE_CHANGE_KEY, 0x03);
    assert_eq!(TYPE_ANCHOR, 0x04);
    assert_eq!(TYPE_TRANSFER_ACTIVATION, 0x0A);
}

// ---------- op_hash determinism (R2 invariant) ----------

#[test]
fn op_hash_deterministic_transfer() {
    let op = Operation::Transfer(sample_transfer([0x01; 32], [0x02; 32], 100));
    assert_eq!(op_hash(&op), op_hash(&op));
}

#[test]
fn op_hash_stable_under_signature_mutation() {
    // R2: identifier(op) = SHA-256("mt-op" || signed_scope(op)) — signature
    // НЕ входит в hash. Защита от schemes where signature randomized.
    let t1 = sample_transfer([0x01; 32], [0x02; 32], 100);
    let mut t2 = t1.clone();
    t2.signature = Signature::from_array([0xFF; SIGNATURE_SIZE]);
    let op1 = Operation::Transfer(t1);
    let op2 = Operation::Transfer(t2);
    assert_eq!(op_hash(&op1), op_hash(&op2));
}

#[test]
fn op_hash_changes_on_field_mutation() {
    let base = Operation::Transfer(sample_transfer([0x01; 32], [0x02; 32], 100));
    let mutated_amount = Operation::Transfer(sample_transfer([0x01; 32], [0x02; 32], 101));
    let mutated_sender = Operation::Transfer(sample_transfer([0xAA; 32], [0x02; 32], 100));
    let mutated_link = Operation::Transfer(sample_transfer([0x01; 32], [0xBB; 32], 100));
    assert_ne!(op_hash(&base), op_hash(&mutated_amount));
    assert_ne!(op_hash(&base), op_hash(&mutated_sender));
    assert_ne!(op_hash(&base), op_hash(&mutated_link));
}

#[test]
fn op_hash_distinct_across_op_types() {
    // Type byte должен различать operations даже если поля совпадают.
    let t = Operation::Transfer(sample_transfer([0x01; 32], [0x02; 32], 100));
    let a = Operation::Anchor(sample_anchor([0x01; 32]));
    let c = Operation::ChangeKey(sample_change_key([0x01; 32]));
    assert_ne!(op_hash(&t), op_hash(&a));
    assert_ne!(op_hash(&t), op_hash(&c));
    assert_ne!(op_hash(&a), op_hash(&c));
}

// ---------- apply_* determinism (state transition) ----------

#[test]
fn apply_transfer_deterministic() {
    let mut state1 = AccountTable::new();
    state1.insert(sample_account(0xAA, 1_000_000));
    state1.insert(sample_account(0xBB, 0));
    let mut state2 = state1.clone();

    // Set frontier_hash to match what validate_transfer expects (sample's prev_hash)
    let mut s_acct = state1.get(&[0xAA; 32]).unwrap().clone();
    s_acct.frontier_hash = [0xBB; 32]; // matches sample_transfer.prev_hash
    state1.insert(s_acct.clone());
    state2.insert(s_acct);

    let op = sample_transfer([0xAA; 32], [0xBB; 32], 1000);
    apply_transfer(&op, &mut state1, 5);
    apply_transfer(&op, &mut state2, 5);
    assert_eq!(state1.root(), state2.root());
}

#[test]
fn apply_anchor_does_not_change_balance() {
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 1_000_000);
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);

    let op = sample_anchor([0xAA; 32]);
    let balance_before = state.get(&[0xAA; 32]).unwrap().balance;
    apply_anchor(&op, &mut state, 5);
    let balance_after = state.get(&[0xAA; 32]).unwrap().balance;
    assert_eq!(balance_before, balance_after, "Anchor не меняет balance");
}

#[test]
fn apply_change_key_updates_pubkey() {
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 1_000_000);
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);

    let op = sample_change_key([0xAA; 32]);
    apply_change_key(&op, &mut state, 5);
    let updated = state.get(&[0xAA; 32]).unwrap();
    assert_eq!(updated.current_pubkey, [0xDD; PUBLIC_KEY_SIZE]);
}

// ---------- Validation determinism ----------

#[test]
fn validate_rejects_self_transfer() {
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 1_000_000);
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);
    // Insert receiver
    state.insert(sample_account(0xCC, 0));

    let op = sample_transfer([0xAA; 32], [0xAA; 32], 100);
    assert!(validate_transfer(&op, &state).is_err());
}

#[test]
fn validate_rejects_zero_amount() {
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 1_000_000);
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);
    state.insert(sample_account(0xBB, 0));

    let op = sample_transfer([0xAA; 32], [0xBB; 32], 0);
    assert!(validate_transfer(&op, &state).is_err());
}

#[test]
fn validate_rejects_insufficient_balance() {
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 100);
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);
    state.insert(sample_account(0xBB, 0));

    let op = sample_transfer([0xAA; 32], [0xBB; 32], 1000); // более чем balance
    assert!(validate_transfer(&op, &state).is_err());
}

// ---------- settle_window determinism (op_hash sort order) ----------

#[test]
fn settle_window_op_order_independent() {
    // settle_window sorts by op_hash — порядок входа не влияет на итог.
    let mut state1 = AccountTable::new();
    let mut acct_aa = sample_account(0xAA, 1_000_000);
    acct_aa.frontier_hash = [0xBB; 32];
    state1.insert(acct_aa.clone());
    state1.insert(sample_account(0xCC, 0));
    state1.insert(sample_account(0xDD, 0));
    let mut state2 = state1.clone();

    let op_a = Operation::Transfer(sample_transfer([0xAA; 32], [0xCC; 32], 100));
    let op_b = Operation::Transfer(sample_transfer([0xAA; 32], [0xDD; 32], 200));

    // Note: после первого apply, frontier меняется → второй op fails validate
    // (prev_hash mismatch). Но settle_window не вызывает validate; смотрим
    // только что order-independence сохраняется на уровне sort+apply
    // (skipping validation gates за scope теста).
    settle_window(&mut state1, &[op_a.clone(), op_b.clone()], 5);
    settle_window(&mut state2, &[op_b, op_a], 5);

    // После sort'ов by op_hash — оба state равны.
    assert_eq!(state1.root(), state2.root());
}

// ---------- Genesis state determinism ----------

#[test]
fn build_genesis_state_deterministic() {
    let p = mt_genesis::genesis_params();
    let g1 = build_genesis_state(p);
    let g2 = build_genesis_state(p);
    assert_eq!(g1.account_table.root(), g2.account_table.root());
    assert_eq!(g1.node_table.root(), g2.node_table.root());
    assert_eq!(g1.candidate_pool.root(), g2.candidate_pool.root());
}

#[test]
fn genesis_supply_zero() {
    // spec: Genesis State до первого окна — supply = 0.
    let p = mt_genesis::genesis_params();
    let g = build_genesis_state(p);
    let total: u128 = g.account_table.iter().map(|r| r.balance).sum();
    assert_eq!(total, 0);
}

#[test]
fn genesis_tables_are_empty() {
    // spec: Genesis = empty window 0. No baked bootstrap operator: all three
    // consensus tables start empty. The first node self-admits via the
    // standard admission path (selection_slots(0)=1, quorum(1)=1).
    let p = mt_genesis::genesis_params();
    let g = build_genesis_state(p);
    assert_eq!(g.account_table.len(), 0);
    assert_eq!(g.node_table.len(), 0);
    assert_eq!(g.candidate_pool.len(), 0);
}

// ---------- reward_moneta + supply_moneta consistency ----------

#[test]
fn reward_moneta_returns_emission_const() {
    let p = mt_genesis::genesis_params();
    assert_eq!(reward_moneta(p), p.emission_moneta);
}

#[test]
fn supply_moneta_window_zero_is_zero() {
    let p = mt_genesis::genesis_params();
    assert_eq!(supply_moneta(0, p), 0);
}

#[test]
fn supply_moneta_grows_linearly() {
    let p = mt_genesis::genesis_params();
    let s0 = supply_moneta(0, p);
    let s10 = supply_moneta(10, p);
    let s100 = supply_moneta(100, p);
    assert!(s0 < s10);
    assert!(s10 < s100);
    assert_eq!(s10, p.emission_moneta * 10);
    assert_eq!(s100, p.emission_moneta * 100);
}

// ---------- apply_proposal determinism ----------

#[test]
fn apply_proposal_deterministic() {
    let p = mt_genesis::genesis_params();
    let g1 = build_genesis_state(p);
    let g2 = build_genesis_state(p);

    let mut a1 = g1.account_table;
    let mut n1 = g1.node_table;
    let c1 = g1.candidate_pool;

    let mut a2 = g2.account_table;
    let mut n2 = g2.node_table;
    let c2 = g2.candidate_pool;

    let (_acc, node_id) = seed_operator(&mut a1, &mut n1, 0xA1, 0xB1);
    let _ = seed_operator(&mut a2, &mut n2, 0xA1, 0xB1);

    let input = ProposalSettle {
        window_w: 5,
        winner_id: node_id,
        cemented_confirmers: vec![],
    };

    let r1 = apply_proposal(&mut a1, &mut n1, &c1, &input, p);
    let r2 = apply_proposal(&mut a2, &mut n2, &c2, &input, p);
    assert_eq!(r1, r2);
}

#[test]
fn apply_proposal_emission_changes_balance() {
    let p = mt_genesis::genesis_params();
    let g = build_genesis_state(p);
    let mut account_table = g.account_table;
    let mut node_table = g.node_table;
    let candidate_pool = g.candidate_pool;

    let (account_id, node_id) = seed_operator(&mut account_table, &mut node_table, 0xA2, 0xB2);
    let balance_before = account_table.get(&account_id).unwrap().balance;

    let input = ProposalSettle {
        window_w: 3,
        winner_id: node_id,
        cemented_confirmers: vec![],
    };
    apply_proposal(
        &mut account_table,
        &mut node_table,
        &candidate_pool,
        &input,
        p,
    );

    let balance_after = account_table.get(&account_id).unwrap().balance;
    assert_eq!(
        balance_after,
        balance_before + p.emission_moneta,
        "Operator получает EMISSION_moneta"
    );
}

// ---------- Static API invariants ----------

#[test]
fn record_sizes_positive() {
    const _: () = assert!(TRANSFER_SIZE > 0);
    const _: () = assert!(CHANGE_KEY_SIZE > 0);
    const _: () = assert!(ANCHOR_SIZE > 0);
    const _: () = assert!(TRANSFER_ACTIVATION_SIZE > 0);
}

#[test]
fn genesis_suite_id_is_one() {
    assert_eq!(GENESIS_SUITE_ID, 1);
}

// ---------- M3-3 closure: checked arithmetic panic on protocol breach ----------

#[test]
#[should_panic(expected = "balance underflow")]
fn apply_transfer_panics_on_unsanitized_underflow() {
    // Если кто-то вызывает apply_transfer без предварительного validate_transfer
    // и balance < amount — должен быть controlled halt, не silent wrap.
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 100); // balance = 100
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);
    state.insert(sample_account(0xBB, 0));

    let op = sample_transfer([0xAA; 32], [0xBB; 32], 1000); // amount = 1000 > balance
    apply_transfer(&op, &mut state, 5);
}

// ---------- M3-1 closure: window_w u64 unification ----------

#[test]
fn apply_accepts_u64_window() {
    // Compile-time проверка signature — все apply_* принимают u64.
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 1_000_000);
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);
    state.insert(sample_account(0xBB, 0));

    let op_t = Operation::Transfer(sample_transfer([0xAA; 32], [0xBB; 32], 100));
    let large_window: u64 = 1_000_000_000; // > u32::MAX/4 but < u32::MAX
    apply(&op_t, &mut state, large_window);
}

#[test]
#[should_panic(expected = "encoded arithmetic horizon")]
fn apply_panics_on_window_w_above_u32_max() {
    // window_w > u32::MAX → controlled halt (encoded arithmetic horizon).
    let mut state = AccountTable::new();
    let mut acct = sample_account(0xAA, 1_000_000);
    acct.frontier_hash = [0xBB; 32];
    state.insert(acct);
    state.insert(sample_account(0xBB, 0));

    let op = sample_transfer([0xAA; 32], [0xBB; 32], 100);
    apply_transfer(&op, &mut state, u64::from(u32::MAX) + 1);
}
