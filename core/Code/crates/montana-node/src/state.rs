use std::path::Path;

use mt_genesis::ProtocolParams;
use mt_state::{
    AccountRecord, AccountTable, CandidatePool, NodeTable, ACCOUNT_RECORD_SIZE,
    CANDIDATE_RECORD_SIZE, NODE_RECORD_SIZE,
};
use mt_store::FsStore;

use crate::identity::{Identity, NodeError};
use crate::timechain_state::TimeChainState;
use crate::window_record;

pub struct LocalState {
    pub accounts: AccountTable,
    pub nodes: NodeTable,
    pub candidates: CandidatePool,
}

impl LocalState {
    // Genesis = empty window 0: build_genesis_state gives empty tables. Every
    // node starts as a candidate and self-admits through the standard admission
    // path (apply_selection_event). A node appears in NodeTable only after
    // admission; until then NodeTable is empty. The operator account is created at once —
    // it is needed to sign the future NodeRegistration (is_node_operator=false,
    // not yet Active).
    pub fn bootstrap(operator: &Identity, params: &ProtocolParams) -> Self {
        // Canonical empty genesis tables — byte-identical to
        // mt_account::genesis_state_root, so the runtime state_root equals the
        // Genesis State Hash. build_genesis_state is the single source of truth
        // for genesis seeding ([C-1]).
        let genesis = mt_account::build_genesis_state(params);
        let mut accounts = genesis.account_table;
        let nodes = genesis.node_table;
        let candidates = genesis.candidate_pool;

        // The node carries its own operator account (needed to sign a future
        // NodeRegistration). Empty genesis has no baked accounts, so this insert
        // always runs; the `is_none` guard is kept defensively against any future
        // pre-seeded account so that AccountTable::insert never silently
        // OVERWRITES a canonical record and diverges account_root.
        if accounts.get(&operator.account_id()).is_none() {
            accounts.insert(AccountRecord {
                account_id: operator.account_id(),
                balance: 0,
                suite_id: operator.suite_id as u16,
                is_node_operator: false,
                frontier_hash: [0u8; 32],
                op_height: 0,
                account_chain_length: 0,
                account_chain_length_snapshot: 0,
                current_pubkey: *operator.account_pk.as_bytes(),
                creation_window: 0,
                last_op_window: 0,
                last_activation_window: 0,
            });
        }

        Self {
            accounts,
            nodes,
            candidates,
        }
    }

    pub fn load_or_bootstrap(
        data_dir: &Path,
        operator: &Identity,
        params: &ProtocolParams,
    ) -> Result<Self, NodeError> {
        let store = FsStore::open(data_dir).map_err(|e| {
            NodeError::InvalidArguments(format!("opening storage {}: {e:?}", data_dir.display()))
        })?;
        let accounts_path = data_dir.join("accounts.bin");
        if !accounts_path.exists() {
            return Ok(Self::bootstrap(operator, params));
        }
        let accounts = store.load_account_table().map_err(|e| {
            NodeError::InvalidArguments(format!(
                "loading accounts.bin: {e:?} (expected a size multiple of {ACCOUNT_RECORD_SIZE})"
            ))
        })?;
        let nodes = store.load_node_table().map_err(|e| {
            NodeError::InvalidArguments(format!(
                "loading nodes.bin: {e:?} (expected a size multiple of {NODE_RECORD_SIZE})"
            ))
        })?;
        let candidates = store.load_candidate_pool().map_err(|e| {
            NodeError::InvalidArguments(format!(
                "loading candidates.bin: {e:?} (expected a size multiple of {CANDIDATE_RECORD_SIZE})"
            ))
        })?;
        Ok(Self {
            accounts,
            nodes,
            candidates,
        })
    }

    pub fn save(&self, data_dir: &Path) -> Result<(), NodeError> {
        let store = FsStore::open(data_dir)
            .map_err(|e| NodeError::InvalidArguments(format!("opening storage: {e:?}")))?;
        store
            .save_account_table(&self.accounts)
            .map_err(|e| NodeError::InvalidArguments(format!("save accounts: {e:?}")))?;
        store
            .save_node_table(&self.nodes)
            .map_err(|e| NodeError::InvalidArguments(format!("save nodes: {e:?}")))?;
        store
            .save_candidate_pool(&self.candidates)
            .map_err(|e| NodeError::InvalidArguments(format!("save candidates: {e:?}")))?;
        Ok(())
    }

    // Applying a verified fast-sync snapshot: the caller passes the record of window W (its
    // tables from the snapshot) only after FastSyncClient::finalize has checked the
    // reconstructed state_root against the trusted anchor root of W. Here the snapshot is
    // already trusted. Issue #19 K5: the three tables, the window W, the clock and the anchor's
    // envelope are committed as ONE record; the tables, the window and the clock in memory are
    // replaced only after that record stands, the views after them. Issue #19 K6: a record that
    // does not name the network of `params` is refused and nothing moves.
    pub fn apply_fast_sync(
        &mut self,
        record: mt_store::WindowRecord,
        data_dir: &Path,
        current: &mut u64,
        clock: &mut TimeChainState,
        params: &ProtocolParams,
    ) -> Result<(), NodeError> {
        let store = FsStore::open(data_dir)
            .map_err(|e| NodeError::InvalidArguments(format!("opening storage: {e:?}")))?;
        window_record::commit(&store, &record, params)?;
        let (state, window, synced_clock, envelope) = window_record::into_parts(record);
        *self = state;
        *current = window;
        *clock = synced_clock;
        window_record::write_views(&store, data_dir, window, self, clock, &envelope)
    }
}

// SPEC DEVIATION DEV-010 (obsolete — closed by "Genesis = empty window 0"):
// Genesis no longer bakes a NodeRecord for bootstrap. All tables are empty at window 0;
// every node self-admits through the standard admission path. See
// docs/SPEC_DEVIATIONS.md DEV-010.

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::PUBLIC_KEY_SIZE;
    use mt_state::{AccountTable, CandidatePool, NodeTable};
    use std::fs;
    use std::path::PathBuf;

    fn tempdir() -> PathBuf {
        let mut p = std::env::temp_dir();
        let mut buf = [0u8; 8];
        getrandom::getrandom(&mut buf).unwrap();
        p.push(format!(
            "montana-state-test-{:016x}",
            u64::from_le_bytes(buf)
        ));
        fs::create_dir_all(&p).unwrap();
        p
    }

    fn sample_account(seed: u8) -> AccountRecord {
        AccountRecord {
            account_id: [seed; 32],
            balance: 500,
            suite_id: 1,
            is_node_operator: false,
            frontier_hash: [seed; 32],
            op_height: 0,
            account_chain_length: 0,
            account_chain_length_snapshot: 0,
            current_pubkey: [seed; PUBLIC_KEY_SIZE],
            creation_window: 0,
            last_op_window: 0,
            last_activation_window: 0,
        }
    }

    #[test]
    fn apply_fast_sync_replaces_tables_and_persists_anchor() {
        let dir = tempdir();
        let mut state = LocalState {
            accounts: AccountTable::new(),
            nodes: NodeTable::new(),
            candidates: CandidatePool::new(),
        };

        let mut accounts = AccountTable::new();
        accounts.insert(sample_account(0xAB));
        accounts.insert(sample_account(0xCD));
        let synced = mt_store::WindowRecord {
            genesis_state_hash: mt_account::genesis_state_hash(mt_genesis::genesis_params()),
            window: 75_850,
            t_r: [0x5A; 32],
            current_d: 1,
            last_window: 75_850,
            accounts,
            ..mt_store::WindowRecord::default()
        };

        let mut clock = TimeChainState {
            t_r: [0u8; 32],
            current_d: 1,
            last_window: 0,
        };
        let mut current = 7;
        let p = mt_genesis::genesis_params();
        state
            .apply_fast_sync(synced, &dir, &mut current, &mut clock, p)
            .unwrap();

        assert_eq!(state.accounts.len(), 2);
        assert_eq!(current, 75_850);
        assert_eq!((clock.t_r, clock.last_window), ([0x5A; 32], 75_850));

        let store = FsStore::open(&dir).unwrap();
        let record = store.load_window_record().unwrap().unwrap();
        assert_eq!((record.window, record.accounts.len()), (75_850, 2));
        assert_eq!(store.load_meta_last_cemented().unwrap(), Some(75_850));
        assert_eq!(store.load_account_table().unwrap().len(), 2);
        assert!(store.load_node_table().unwrap().is_empty());

        fs::remove_dir_all(&dir).ok();
    }

    // Issue #19 K6: rejects a fast sync that takes a record of another network. The record of a
    // snapshot that names another genesis_state_hash is refused before anything is written:
    // the data dir stays empty of a record, and the tables, the window and the clock in memory
    // stay as they were.
    #[test]
    fn apply_fast_sync_refuses_a_record_of_another_network() {
        let dir = tempdir();
        let p = mt_genesis::genesis_params();
        let mut devnet = p.clone();
        devnet.ssha_entry_windows = 1;
        let mut accounts = AccountTable::new();
        accounts.insert(sample_account(0xAB));
        let foreign = mt_store::WindowRecord {
            genesis_state_hash: mt_account::genesis_state_hash(&devnet),
            window: 75_850,
            accounts,
            ..mt_store::WindowRecord::default()
        };
        let mut state = LocalState {
            accounts: AccountTable::new(),
            nodes: NodeTable::new(),
            candidates: CandidatePool::new(),
        };
        let mut clock = TimeChainState {
            t_r: [0u8; 32],
            current_d: 1,
            last_window: 0,
        };
        let mut current = 7;
        let err = state
            .apply_fast_sync(foreign, &dir, &mut current, &mut clock, p)
            .expect_err("a record of another network was synced");
        assert!(format!("{err}").contains("another network"), "{err}");
        assert_eq!(
            (current, clock.last_window, state.accounts.len()),
            (7, 0, 0)
        );
        let store = FsStore::open(&dir).unwrap();
        assert!(store.load_window_record().unwrap().is_none());
        assert!(!dir.join("accounts.bin").exists());

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn bootstrap_empty_genesis_seeds_only_own_account() {
        use mt_genesis::genesis_params;
        let id = crate::identity::Identity::from_entropy_ephemeral(&[0x77; 32]).unwrap();

        // Genesis = empty window 0: no baked node, no N_SEED cohort. The node
        // boots with an empty NodeTable and exactly its own operator account
        // (is_node_operator=false — not pre-Active).
        let p = genesis_params();
        let local = LocalState::bootstrap(&id, p);
        assert_eq!(local.nodes.len(), 0);
        assert_eq!(local.accounts.len(), 1);
        let rec = local.accounts.get(&id.account_id()).unwrap();
        assert!(!rec.is_node_operator);
    }

    #[test]
    fn local_state_node_set_equals_canonical_genesis() {
        // Every node boots with exactly the canonical (empty) genesis NodeTable,
        // so all nodes agree on the Genesis State Hash consensus set. A fresh node
        // adds only its own account on top of the empty genesis.
        use mt_genesis::genesis_params;
        let id = crate::identity::Identity::from_entropy_ephemeral(&[0x11; 32]).unwrap();
        let p = genesis_params();
        let local = LocalState::bootstrap(&id, p);
        let g = mt_account::build_genesis_state(p);
        assert_eq!(
            local.nodes.root(),
            g.node_table.root(),
            "runtime node set != canonical genesis -> consensus fork"
        );
        assert_eq!(local.accounts.len(), g.account_table.len() + 1);
    }

    #[test]
    fn genesis_member_local_state_root_equals_canonical() {
        // For a genesis member the FULL runtime root equals the canonical genesis
        // root (no own-account delta). Verified by reconstructing the canonical
        // tables directly (a genesis member's bootstrap output == build_genesis_state).
        use mt_genesis::genesis_params;
        let p = genesis_params();
        let g = mt_account::build_genesis_state(p);
        let canonical = mt_account::genesis_state_root(&g);
        let runtime = mt_state::compute_state_root(
            &g.node_table.root(),
            &g.candidate_pool.root(),
            &g.account_table.root(),
        );
        assert_eq!(runtime, canonical);
    }
}
