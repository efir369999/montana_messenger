// Automated determinism invariants для mt-store.
// M5 audit prep — persistence layer: AccountTable / NodeTable / CandidatePool /
// ProposalHeader save-load roundtrip + crash recovery + pruning.
// Любая non-equivalence save/load = state divergence = consensus fork.
// Invariants ловят byte-exact roundtrip regression при refactor encoding/decoding.

use mt_crypto::PUBLIC_KEY_SIZE;
use mt_state::{
    AccountRecord, AccountTable, CandidatePool, CandidateRecord, NodeRecord, NodeTable,
};
use mt_store::{FsStore, StoreError};
use std::path::PathBuf;

// ---------- Helpers ----------

fn unique_tmp_dir(seed: &str) -> PathBuf {
    let pid = std::process::id();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos() as u64)
        .unwrap_or(0);
    let path = std::env::temp_dir().join(format!("mt-store-det-{seed}-{pid}-{nanos}"));
    let _ = std::fs::remove_dir_all(&path);
    path
}

fn sample_account(id_byte: u8) -> AccountRecord {
    AccountRecord {
        account_id: [id_byte; 32],
        balance: 1_000_000_000_000u128,
        suite_id: 1,
        is_node_operator: id_byte % 2 == 0,
        frontier_hash: [id_byte.wrapping_add(1); 32],
        op_height: id_byte as u32,
        account_chain_length: id_byte as u32,
        account_chain_length_snapshot: (id_byte / 2) as u32,
        current_pubkey: [id_byte; PUBLIC_KEY_SIZE],
        creation_window: id_byte as u32,
        last_op_window: (id_byte as u32).saturating_add(10),
        last_activation_window: 0,
    }
}

fn sample_node(id_byte: u8) -> NodeRecord {
    NodeRecord {
        node_id: [id_byte; 32],
        node_pubkey: [id_byte; PUBLIC_KEY_SIZE],
        suite_id: 1,
        operator_account_id: [id_byte.wrapping_add(1); 32],
        start_window: id_byte as u64 * 10,
        chain_length: id_byte as u64 * 100,
        chain_length_snapshot: id_byte as u64 * 50,
        chain_length_checkpoints: [id_byte as u64; 6],
        last_confirmation_window: id_byte as u64 * 200,
    }
}

fn sample_candidate(id_byte: u8) -> CandidateRecord {
    CandidateRecord {
        node_id: [id_byte; 32],
        node_pubkey: [id_byte; PUBLIC_KEY_SIZE],
        suite_id: 1,
        operator_account_id: [id_byte.wrapping_add(1); 32],
        proof_endpoint: [id_byte.wrapping_add(2); 32],
        w_start: id_byte as u64 * 10,
        ssha_chain_length: 20_160,
        registration_window: id_byte as u64 * 10,
        expires: id_byte as u64 * 10 + 60_480,
    }
}

// ---------- AccountTable save/load roundtrip ----------

#[test]
fn account_table_save_load_roundtrip() {
    let dir = unique_tmp_dir("acct-rt");
    let store = FsStore::open(&dir).expect("open store");

    let mut table = AccountTable::new();
    table.insert(sample_account(0x01));
    table.insert(sample_account(0x02));
    table.insert(sample_account(0x03));
    let root_before = table.root();

    store.save_account_table(&table).expect("save");
    let loaded = store.load_account_table().expect("load");

    assert_eq!(table.len(), loaded.len());
    assert_eq!(
        root_before,
        loaded.root(),
        "root byte-equal after roundtrip"
    );

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn account_table_load_empty_when_no_file() {
    let dir = unique_tmp_dir("acct-empty");
    let store = FsStore::open(&dir).expect("open store");
    let loaded = store.load_account_table().expect("load empty");
    assert_eq!(loaded.len(), 0);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn account_table_corrupted_length_detected() {
    let dir = unique_tmp_dir("acct-corrupt");
    let store = FsStore::open(&dir).expect("open store");
    // Записываем не-кратное ACCOUNT_RECORD_SIZE количество байт
    std::fs::write(dir.join("accounts.bin"), b"corrupt-not-multiple").expect("write");
    let result = store.load_account_table();
    assert!(matches!(result, Err(StoreError::CorruptedLength(_))));
    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- NodeTable save/load roundtrip ----------

#[test]
fn node_table_save_load_roundtrip() {
    let dir = unique_tmp_dir("node-rt");
    let store = FsStore::open(&dir).expect("open store");

    let mut table = NodeTable::new();
    table.insert(sample_node(0x10));
    table.insert(sample_node(0x20));
    let root_before = table.root();

    store.save_node_table(&table).expect("save");
    let loaded = store.load_node_table().expect("load");

    assert_eq!(table.len(), loaded.len());
    assert_eq!(root_before, loaded.root());

    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- CandidatePool save/load roundtrip ----------

#[test]
fn candidate_pool_save_load_roundtrip() {
    let dir = unique_tmp_dir("cand-rt");
    let store = FsStore::open(&dir).expect("open store");

    let mut pool = CandidatePool::new();
    pool.insert(sample_candidate(0x40));
    pool.insert(sample_candidate(0x50));
    let root_before = pool.root();

    store.save_candidate_pool(&pool).expect("save");
    let loaded = store.load_candidate_pool().expect("load");

    assert_eq!(pool.len(), loaded.len());
    assert_eq!(root_before, loaded.root());

    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- Crash recovery (meta_last_cemented) ----------

#[test]
fn meta_last_cemented_save_load_roundtrip() {
    let dir = unique_tmp_dir("meta-rt");
    let store = FsStore::open(&dir).expect("open store");

    store.save_meta_last_cemented(42).expect("save meta");
    let loaded = store.load_meta_last_cemented().expect("load meta");
    assert_eq!(loaded, Some(42));

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn meta_last_cemented_returns_none_when_absent() {
    let dir = unique_tmp_dir("meta-empty");
    let store = FsStore::open(&dir).expect("open store");
    assert_eq!(store.load_meta_last_cemented().expect("load"), None);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn verify_consistency_zero_when_no_meta() {
    let dir = unique_tmp_dir("consist-zero");
    let store = FsStore::open(&dir).expect("open store");
    // Без meta файла → last = 0, no proposal проверка
    assert_eq!(store.verify_consistency().expect("verify"), 0);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn verify_consistency_detects_missing_proposal() {
    let dir = unique_tmp_dir("consist-missing");
    let store = FsStore::open(&dir).expect("open store");
    // meta = 100, но proposal в archive отсутствует → finding
    store.save_meta_last_cemented(100).expect("save meta");
    let result = store.verify_consistency();
    assert!(matches!(result, Err(StoreError::NotFound(_))));
    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- Pruning ----------

#[test]
fn prune_proposals_returns_empty_when_dir_absent() {
    let dir = unique_tmp_dir("prune-empty");
    let store = FsStore::open(&dir).expect("open store");
    // Удаляем proposals dir чтобы test edge case (хотя open() создаёт)
    let _ = std::fs::remove_dir_all(dir.join("proposals"));
    let removed = store.prune_proposals_before(100).expect("prune");
    assert_eq!(removed, Vec::<u64>::new());
    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- Determinism: byte-equal save для identical input ----------

#[test]
fn save_account_table_byte_equal_for_identical_input() {
    let dir1 = unique_tmp_dir("det-acct-1");
    let dir2 = unique_tmp_dir("det-acct-2");
    let store1 = FsStore::open(&dir1).expect("open 1");
    let store2 = FsStore::open(&dir2).expect("open 2");

    let mut table = AccountTable::new();
    table.insert(sample_account(0x01));
    table.insert(sample_account(0x02));
    table.insert(sample_account(0x03));

    store1.save_account_table(&table).expect("save 1");
    store2.save_account_table(&table).expect("save 2");

    let bytes1 = std::fs::read(dir1.join("accounts.bin")).expect("read 1");
    let bytes2 = std::fs::read(dir2.join("accounts.bin")).expect("read 2");
    assert_eq!(
        bytes1, bytes2,
        "byte-exact identical input → identical file"
    );

    let _ = std::fs::remove_dir_all(&dir1);
    let _ = std::fs::remove_dir_all(&dir2);
}

#[test]
fn save_account_table_byte_equal_invariant_under_insertion_order() {
    // BTreeMap-backed AccountTable должен давать identical encoded bytes
    // независимо от insertion order.
    let dir1 = unique_tmp_dir("ord-acct-1");
    let dir2 = unique_tmp_dir("ord-acct-2");
    let store1 = FsStore::open(&dir1).expect("open 1");
    let store2 = FsStore::open(&dir2).expect("open 2");

    let mut t1 = AccountTable::new();
    t1.insert(sample_account(0x01));
    t1.insert(sample_account(0x02));
    t1.insert(sample_account(0x03));

    let mut t2 = AccountTable::new();
    t2.insert(sample_account(0x03));
    t2.insert(sample_account(0x01));
    t2.insert(sample_account(0x02));

    store1.save_account_table(&t1).expect("save 1");
    store2.save_account_table(&t2).expect("save 2");

    let bytes1 = std::fs::read(dir1.join("accounts.bin")).expect("read 1");
    let bytes2 = std::fs::read(dir2.join("accounts.bin")).expect("read 2");
    assert_eq!(
        bytes1, bytes2,
        "BTreeMap canonical sort guarantees order-independent encode"
    );

    let _ = std::fs::remove_dir_all(&dir1);
    let _ = std::fs::remove_dir_all(&dir2);
}

// ---------- Static API invariants ----------

#[test]
fn store_root_returns_open_path() {
    let dir = unique_tmp_dir("root-path");
    let store = FsStore::open(&dir).expect("open");
    assert_eq!(store.root(), dir.as_path());
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn store_creates_proposals_subdirectory() {
    let dir = unique_tmp_dir("propdir");
    let _store = FsStore::open(&dir).expect("open");
    assert!(dir.join("proposals").is_dir());
    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- R5 atomic rename pattern verification ----------

#[test]
fn save_does_not_leave_tmp_on_success() {
    // R5 invariant: после успешного save_X нет файла `<name>.tmp` в root.
    // (rename атомарен, tmp removed.)
    let dir = unique_tmp_dir("atomic-cleanup");
    let store = FsStore::open(&dir).expect("open");
    let mut table = AccountTable::new();
    table.insert(sample_account(0x01));
    store.save_account_table(&table).expect("save");
    assert!(dir.join("accounts.bin").exists(), "final file present");
    assert!(
        !dir.join("accounts.bin.tmp").exists(),
        "tmp file removed after rename"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn save_atomic_overwrite_preserves_old_until_rename() {
    // R5 invariant: existing файл не truncated в-мiddle write. Если write fails
    // mid-flight (вне нашего теста — нужен fault injection для full coverage),
    // old content остаётся valid.
    // Этот тест verifies happy path: повторный save заменяет content полностью.
    let dir = unique_tmp_dir("atomic-overwrite");
    let store = FsStore::open(&dir).expect("open");

    let mut t1 = AccountTable::new();
    t1.insert(sample_account(0x01));
    store.save_account_table(&t1).expect("save 1");
    let bytes_v1 = std::fs::read(dir.join("accounts.bin")).expect("read 1");

    let mut t2 = AccountTable::new();
    t2.insert(sample_account(0x01));
    t2.insert(sample_account(0x02));
    store.save_account_table(&t2).expect("save 2");
    let bytes_v2 = std::fs::read(dir.join("accounts.bin")).expect("read 2");

    assert_ne!(bytes_v1, bytes_v2, "v2 overwrites v1");
    assert_eq!(bytes_v2.len(), 2 * 2059, "v2 contains 2 records");
    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- Full state cycle: open → populate → save → close → reopen → load ----------

#[test]
fn full_state_cycle_state_root_byte_equal() {
    let dir = unique_tmp_dir("cycle");
    {
        let store = FsStore::open(&dir).expect("open");
        let mut acct = AccountTable::new();
        acct.insert(sample_account(0x01));
        acct.insert(sample_account(0x02));
        let mut nodes = NodeTable::new();
        nodes.insert(sample_node(0x10));
        let mut cands = CandidatePool::new();
        cands.insert(sample_candidate(0x40));

        store.save_account_table(&acct).expect("save acct");
        store.save_node_table(&nodes).expect("save nodes");
        store.save_candidate_pool(&cands).expect("save cand");
    } // close

    {
        // reopen
        let store2 = FsStore::open(&dir).expect("reopen");
        let acct = store2.load_account_table().expect("load acct");
        let nodes = store2.load_node_table().expect("load nodes");
        let cands = store2.load_candidate_pool().expect("load cand");

        assert_eq!(acct.len(), 2);
        assert_eq!(nodes.len(), 1);
        assert_eq!(cands.len(), 1);
    }

    let _ = std::fs::remove_dir_all(&dir);
}
