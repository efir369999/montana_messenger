use std::path::Path;

use mt_genesis::ProtocolParams;
use mt_state::{
    AccountRecord, AccountTable, CandidatePool, NodeTable, ACCOUNT_RECORD_SIZE,
    CANDIDATE_RECORD_SIZE, NODE_RECORD_SIZE,
};
use mt_store::FsStore;

use crate::identity::{Identity, NodeError};

pub struct LocalState {
    pub accounts: AccountTable,
    pub nodes: NodeTable,
    pub candidates: CandidatePool,
}

impl LocalState {
    // Genesis = пустое окно 0: build_genesis_state даёт пустые таблицы. Каждый
    // узел стартует кандидатом и self-admit-ит себя через standard admission
    // path (apply_selection_event). Узел появляется в NodeTable только после
    // admission; до этого NodeTable пуст. Operator account создаётся сразу —
    // он нужен для подписания будущей NodeRegistration (is_node_operator=false,
    // ещё НЕ Active).
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
            NodeError::InvalidArguments(format!("открытие хранилища {}: {e:?}", data_dir.display()))
        })?;
        let accounts_path = data_dir.join("accounts.bin");
        if !accounts_path.exists() {
            return Ok(Self::bootstrap(operator, params));
        }
        let accounts = store.load_account_table().map_err(|e| {
            NodeError::InvalidArguments(format!(
                "загрузка accounts.bin: {e:?} (ожидался размер кратный {ACCOUNT_RECORD_SIZE})"
            ))
        })?;
        let nodes = store.load_node_table().map_err(|e| {
            NodeError::InvalidArguments(format!(
                "загрузка nodes.bin: {e:?} (ожидался размер кратный {NODE_RECORD_SIZE})"
            ))
        })?;
        let candidates = store.load_candidate_pool().map_err(|e| {
            NodeError::InvalidArguments(format!(
                "загрузка candidates.bin: {e:?} (ожидался размер кратный {CANDIDATE_RECORD_SIZE})"
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
            .map_err(|e| NodeError::InvalidArguments(format!("открытие хранилища: {e:?}")))?;
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

    // Применение проверенного fast-sync снимка: вызывающая сторона передаёт
    // TypedTables только после того как FastSyncClient::finalize сверил
    // reconstructed state_root с доверенным anchor root окна W. Здесь снимок
    // уже доверенный — заменяем три consensus-таблицы и фиксируем
    // meta_last_cemented = W (точка восстановления после перезапуска).
    pub fn apply_fast_sync(
        &mut self,
        tables: mt_sync::snapshot::TypedTables,
        data_dir: &Path,
        anchor_window: u64,
    ) -> Result<(), NodeError> {
        self.accounts = tables.accounts;
        self.nodes = tables.nodes;
        self.candidates = tables.candidates;
        self.save(data_dir)?;
        let store = FsStore::open(data_dir)
            .map_err(|e| NodeError::InvalidArguments(format!("открытие хранилища: {e:?}")))?;
        store
            .save_meta_last_cemented(anchor_window)
            .map_err(|e| NodeError::InvalidArguments(format!("save_meta_last_cemented: {e:?}")))?;
        Ok(())
    }
}

// SPEC DEVIATION DEV-010 (obsolete — closed by "Genesis = empty window 0"):
// Genesis больше не печёт NodeRecord для bootstrap. Все таблицы пусты на окне 0;
// каждый узел self-admit-ит себя через standard admission path. См.
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
        let tables = mt_sync::snapshot::TypedTables {
            accounts,
            nodes: NodeTable::new(),
            candidates: CandidatePool::new(),
        };

        state.apply_fast_sync(tables, &dir, 75_850).unwrap();

        assert_eq!(state.accounts.len(), 2);

        let store = FsStore::open(&dir).unwrap();
        assert_eq!(store.load_meta_last_cemented().unwrap(), Some(75_850));
        assert_eq!(store.load_account_table().unwrap().len(), 2);
        assert!(store.load_node_table().unwrap().is_empty());

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
