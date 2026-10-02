// spec, разделы "Состояние сети" + "Consensus encoding layer"

use std::collections::BTreeMap;

use mt_codec::{
    domain, write_bytes, write_u128, write_u16, write_u32, write_u64, write_u8, CanonicalEncode,
};
use mt_crypto::{hash, Hash32, PUBLIC_KEY_SIZE};
use mt_merkle::SparseMerkleTree;

pub type AccountId = [u8; 32];
pub type NodeId = [u8; 32];

// spec: AccountRecord layout — см. раздел "Account — содержимое блока".
pub const ACCOUNT_RECORD_SIZE: usize = 2059;
pub const NODE_RECORD_SIZE: usize = 2098;
pub const CANDIDATE_RECORD_SIZE: usize = 2082;

// spec, "Proposal header" layout: winner_class единственное valid значение = 1 (Node).
// Константа WINNER_CLASS_NODE сохранена для apply_emission и mt-lottery::Candidate.class.
pub const WINNER_CLASS_NODE: u8 = 1;

// spec: Account Table (запись на аккаунт) — 2059 bytes fixed
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AccountRecord {
    pub account_id: AccountId,
    pub balance: u128,
    pub suite_id: u16,
    pub is_node_operator: bool,
    pub frontier_hash: Hash32,
    pub op_height: u32,
    pub account_chain_length: u32,
    pub account_chain_length_snapshot: u32,
    pub current_pubkey: [u8; PUBLIC_KEY_SIZE],
    pub creation_window: u32,
    pub last_op_window: u32,
    pub last_activation_window: u32,
}

impl CanonicalEncode for AccountRecord {
    fn encode(&self, buf: &mut Vec<u8>) {
        write_bytes(buf, &self.account_id);
        write_u128(buf, self.balance);
        write_u16(buf, self.suite_id);
        write_u8(buf, self.is_node_operator as u8);
        write_bytes(buf, &self.frontier_hash);
        write_u32(buf, self.op_height);
        write_u32(buf, self.account_chain_length);
        write_u32(buf, self.account_chain_length_snapshot);
        write_bytes(buf, &self.current_pubkey);
        write_u32(buf, self.creation_window);
        write_u32(buf, self.last_op_window);
        write_u32(buf, self.last_activation_window);
    }
}

/// Errors returned by AccountRecord / NodeRecord / CandidateRecord decode functions.
#[derive(Debug, Clone, Eq, PartialEq)]
pub enum RecordDecodeError {
    /// The input slice was not exactly the canonical fixed record size.
    WrongSize { expected: usize, actual: usize },
    /// A boolean field carried a non-0/1 byte.
    BadBoolByte(u8),
}

impl AccountRecord {
    /// Decode a canonical-encoded AccountRecord from a fixed 2059-byte slice.
    /// The layout mirrors `<AccountRecord as CanonicalEncode>::encode`.
    pub fn decode(input: &[u8]) -> Result<AccountRecord, RecordDecodeError> {
        if input.len() != ACCOUNT_RECORD_SIZE {
            return Err(RecordDecodeError::WrongSize {
                expected: ACCOUNT_RECORD_SIZE,
                actual: input.len(),
            });
        }
        let mut o = 0usize;
        let mut account_id = [0u8; 32];
        account_id.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let balance = u128::from_le_bytes(input[o..o + 16].try_into().unwrap());
        o += 16;
        let suite_id = u16::from_le_bytes(input[o..o + 2].try_into().unwrap());
        o += 2;
        let is_node_operator = match input[o] {
            0 => false,
            1 => true,
            other => return Err(RecordDecodeError::BadBoolByte(other)),
        };
        o += 1;
        let mut frontier_hash = [0u8; 32];
        frontier_hash.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let op_height = u32::from_le_bytes(input[o..o + 4].try_into().unwrap());
        o += 4;
        let account_chain_length = u32::from_le_bytes(input[o..o + 4].try_into().unwrap());
        o += 4;
        let account_chain_length_snapshot = u32::from_le_bytes(input[o..o + 4].try_into().unwrap());
        o += 4;
        let mut current_pubkey = [0u8; PUBLIC_KEY_SIZE];
        current_pubkey.copy_from_slice(&input[o..o + PUBLIC_KEY_SIZE]);
        o += PUBLIC_KEY_SIZE;
        let creation_window = u32::from_le_bytes(input[o..o + 4].try_into().unwrap());
        o += 4;
        let last_op_window = u32::from_le_bytes(input[o..o + 4].try_into().unwrap());
        o += 4;
        let last_activation_window = u32::from_le_bytes(input[o..o + 4].try_into().unwrap());
        o += 4;
        debug_assert_eq!(o, ACCOUNT_RECORD_SIZE);
        Ok(AccountRecord {
            account_id,
            balance,
            suite_id,
            is_node_operator,
            frontier_hash,
            op_height,
            account_chain_length,
            account_chain_length_snapshot,
            current_pubkey,
            creation_window,
            last_op_window,
            last_activation_window,
        })
    }
}

// spec: Node Table (запись на узел) — 2098 bytes fixed (см. NODE_RECORD_SIZE)
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NodeRecord {
    pub node_id: NodeId,
    pub node_pubkey: [u8; PUBLIC_KEY_SIZE],
    pub suite_id: u16,
    pub operator_account_id: AccountId,
    pub start_window: u64,
    pub chain_length: u64,
    pub chain_length_snapshot: u64,
    // spec, раздел "Состояние сети → Node tier checkpoints" — 6 snapshot
    // значений `chain_length` зафиксированных на границах τ₂-окон tier
    // confirmation. Используется selection event для weighted lottery: tier
    // weight рассчитывается через серию snapshots, а не моментальное значение
    // (защита от грайнинга через мгновенный chain_length boost).
    pub chain_length_checkpoints: [u64; 6],
    pub last_confirmation_window: u64,
}

impl CanonicalEncode for NodeRecord {
    fn encode(&self, buf: &mut Vec<u8>) {
        write_bytes(buf, &self.node_id);
        write_bytes(buf, &self.node_pubkey);
        write_u16(buf, self.suite_id);
        write_bytes(buf, &self.operator_account_id);
        write_u64(buf, self.start_window);
        write_u64(buf, self.chain_length);
        write_u64(buf, self.chain_length_snapshot);
        for checkpoint in &self.chain_length_checkpoints {
            write_u64(buf, *checkpoint);
        }
        write_u64(buf, self.last_confirmation_window);
    }
}

impl NodeRecord {
    /// Decode a canonical-encoded NodeRecord from a fixed 2098-byte slice.
    pub fn decode(input: &[u8]) -> Result<NodeRecord, RecordDecodeError> {
        if input.len() != NODE_RECORD_SIZE {
            return Err(RecordDecodeError::WrongSize {
                expected: NODE_RECORD_SIZE,
                actual: input.len(),
            });
        }
        let mut o = 0usize;
        let mut node_id = [0u8; 32];
        node_id.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let mut node_pubkey = [0u8; PUBLIC_KEY_SIZE];
        node_pubkey.copy_from_slice(&input[o..o + PUBLIC_KEY_SIZE]);
        o += PUBLIC_KEY_SIZE;
        let suite_id = u16::from_le_bytes(input[o..o + 2].try_into().unwrap());
        o += 2;
        let mut operator_account_id = [0u8; 32];
        operator_account_id.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let start_window = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        let chain_length = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        let chain_length_snapshot = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        let mut chain_length_checkpoints = [0u64; 6];
        for cp in &mut chain_length_checkpoints {
            *cp = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
            o += 8;
        }
        let last_confirmation_window = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        debug_assert_eq!(o, NODE_RECORD_SIZE);
        Ok(NodeRecord {
            node_id,
            node_pubkey,
            suite_id,
            operator_account_id,
            start_window,
            chain_length,
            chain_length_snapshot,
            chain_length_checkpoints,
            last_confirmation_window,
        })
    }
}

// spec: Candidate Pool (запись на кандидата) — 2082 bytes fixed (см. CANDIDATE_RECORD_SIZE)
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CandidateRecord {
    pub node_id: NodeId,
    pub node_pubkey: [u8; PUBLIC_KEY_SIZE],
    pub suite_id: u16,
    pub operator_account_id: AccountId,
    pub proof_endpoint: Hash32,
    pub w_start: u64,
    pub ssha_chain_length: u64,
    pub registration_window: u64,
    pub expires: u64,
}

impl CanonicalEncode for CandidateRecord {
    fn encode(&self, buf: &mut Vec<u8>) {
        write_bytes(buf, &self.node_id);
        write_bytes(buf, &self.node_pubkey);
        write_u16(buf, self.suite_id);
        write_bytes(buf, &self.operator_account_id);
        write_bytes(buf, &self.proof_endpoint);
        write_u64(buf, self.w_start);
        write_u64(buf, self.ssha_chain_length);
        write_u64(buf, self.registration_window);
        write_u64(buf, self.expires);
    }
}

impl CandidateRecord {
    /// Decode a canonical-encoded CandidateRecord from a fixed 2082-byte slice.
    pub fn decode(input: &[u8]) -> Result<CandidateRecord, RecordDecodeError> {
        if input.len() != CANDIDATE_RECORD_SIZE {
            return Err(RecordDecodeError::WrongSize {
                expected: CANDIDATE_RECORD_SIZE,
                actual: input.len(),
            });
        }
        let mut o = 0usize;
        let mut node_id = [0u8; 32];
        node_id.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let mut node_pubkey = [0u8; PUBLIC_KEY_SIZE];
        node_pubkey.copy_from_slice(&input[o..o + PUBLIC_KEY_SIZE]);
        o += PUBLIC_KEY_SIZE;
        let suite_id = u16::from_le_bytes(input[o..o + 2].try_into().unwrap());
        o += 2;
        let mut operator_account_id = [0u8; 32];
        operator_account_id.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let mut proof_endpoint = [0u8; 32];
        proof_endpoint.copy_from_slice(&input[o..o + 32]);
        o += 32;
        let w_start = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        let ssha_chain_length = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        let registration_window = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        let expires = u64::from_le_bytes(input[o..o + 8].try_into().unwrap());
        o += 8;
        debug_assert_eq!(o, CANDIDATE_RECORD_SIZE);
        Ok(CandidateRecord {
            node_id,
            node_pubkey,
            suite_id,
            operator_account_id,
            proof_endpoint,
            w_start,
            ssha_chain_length,
            registration_window,
            expires,
        })
    }
}

// BTreeMap + SparseMerkleTree, детерминированный порядок (HashMap запрещён спекой)
#[derive(Default, Clone)]
pub struct AccountTable {
    records: BTreeMap<AccountId, AccountRecord>,
    tree: SparseMerkleTree,
}

impl AccountTable {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, id: &AccountId) -> Option<&AccountRecord> {
        self.records.get(id)
    }

    pub fn insert(&mut self, record: AccountRecord) {
        let key = record.account_id;
        let mut buf = Vec::with_capacity(ACCOUNT_RECORD_SIZE);
        record.encode(&mut buf);
        self.tree.insert(key, &buf);
        self.records.insert(key, record);
    }

    pub fn remove(&mut self, id: &AccountId) -> Option<AccountRecord> {
        self.tree.remove(id);
        self.records.remove(id)
    }

    pub fn contains(&self, id: &AccountId) -> bool {
        self.records.contains_key(id)
    }

    pub fn len(&self) -> usize {
        self.records.len()
    }

    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    pub fn root(&self) -> Hash32 {
        self.tree.root()
    }

    pub fn iter(&self) -> impl Iterator<Item = &AccountRecord> {
        self.records.values()
    }
}

#[derive(Default, Clone)]
pub struct NodeTable {
    records: BTreeMap<NodeId, NodeRecord>,
    tree: SparseMerkleTree,
}

impl NodeTable {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, id: &NodeId) -> Option<&NodeRecord> {
        self.records.get(id)
    }

    pub fn insert(&mut self, record: NodeRecord) {
        let key = record.node_id;
        let mut buf = Vec::with_capacity(NODE_RECORD_SIZE);
        record.encode(&mut buf);
        self.tree.insert(key, &buf);
        self.records.insert(key, record);
    }

    pub fn remove(&mut self, id: &NodeId) -> Option<NodeRecord> {
        self.tree.remove(id);
        self.records.remove(id)
    }

    pub fn contains(&self, id: &NodeId) -> bool {
        self.records.contains_key(id)
    }

    pub fn len(&self) -> usize {
        self.records.len()
    }

    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    pub fn root(&self) -> Hash32 {
        self.tree.root()
    }

    pub fn iter(&self) -> impl Iterator<Item = &NodeRecord> {
        self.records.values()
    }
}

#[derive(Default, Clone)]
pub struct CandidatePool {
    records: BTreeMap<NodeId, CandidateRecord>,
    tree: SparseMerkleTree,
}

impl CandidatePool {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, id: &NodeId) -> Option<&CandidateRecord> {
        self.records.get(id)
    }

    pub fn insert(&mut self, record: CandidateRecord) {
        let key = record.node_id;
        let mut buf = Vec::with_capacity(CANDIDATE_RECORD_SIZE);
        record.encode(&mut buf);
        self.tree.insert(key, &buf);
        self.records.insert(key, record);
    }

    pub fn remove(&mut self, id: &NodeId) -> Option<CandidateRecord> {
        self.tree.remove(id);
        self.records.remove(id)
    }

    pub fn contains(&self, id: &NodeId) -> bool {
        self.records.contains_key(id)
    }

    pub fn len(&self) -> usize {
        self.records.len()
    }

    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    pub fn root(&self) -> Hash32 {
        self.tree.root()
    }

    pub fn iter(&self) -> impl Iterator<Item = &CandidateRecord> {
        self.records.values()
    }
}

// spec: state_root = SHA-256("mt-state-root"
//                              || node_root
//                              || candidate_root
//                              || account_root)
pub fn compute_state_root(
    node_root: &Hash32,
    candidate_root: &Hash32,
    account_root: &Hash32,
) -> Hash32 {
    hash(
        domain::STATE_ROOT,
        &[node_root, candidate_root, account_root],
    )
}

// spec: suite_id 0x0001 = ML-DSA-65 (единственный активный suite)
pub const SUITE_MLDSA65: u16 = 0x0001;

// spec: account_id = SHA-256("mt-account" || suite_id || pubkey)
pub fn derive_account_id(suite_id: u16, pubkey: &[u8; PUBLIC_KEY_SIZE]) -> AccountId {
    hash(domain::ACCOUNT, &[&suite_id.to_le_bytes(), pubkey])
}

// spec: node_id = SHA-256("mt-node" || node_pubkey)
pub fn derive_node_id(node_pubkey: &[u8; PUBLIC_KEY_SIZE]) -> NodeId {
    hash(domain::NODE, &[node_pubkey])
}

// spec: active(node, W) = (W - node.last_confirmation_window) <= 2 × τ₂_windows
pub fn is_active(node: &NodeRecord, current_window: u64, tau2_windows: u64) -> bool {
    current_window.saturating_sub(node.last_confirmation_window) <= 2 * tau2_windows
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_account() -> AccountRecord {
        AccountRecord {
            account_id: [0xAA; 32],
            balance: 1_000_000_000_000u128,
            suite_id: 1,
            is_node_operator: false,
            frontier_hash: [0xBB; 32],
            op_height: 5,
            account_chain_length: 10,
            account_chain_length_snapshot: 9,
            current_pubkey: [0xCC; PUBLIC_KEY_SIZE],
            creation_window: 100,
            last_op_window: 200,
            last_activation_window: 0,
        }
    }

    fn sample_node() -> NodeRecord {
        NodeRecord {
            node_id: [0x11; 32],
            node_pubkey: [0x22; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [0x33; 32],
            start_window: 50,
            chain_length: 100,
            chain_length_snapshot: 80,
            chain_length_checkpoints: [10, 20, 30, 40, 50, 60],
            last_confirmation_window: 150,
        }
    }

    fn sample_candidate() -> CandidateRecord {
        CandidateRecord {
            node_id: [0x44; 32],
            node_pubkey: [0x55; PUBLIC_KEY_SIZE],
            suite_id: 1,
            operator_account_id: [0x66; 32],
            proof_endpoint: [0x77; 32],
            w_start: 10,
            ssha_chain_length: 20_160,
            registration_window: 30_000,
            expires: 90_480,
        }
    }

    #[test]
    fn account_record_encoded_size() {
        let mut buf = Vec::new();
        sample_account().encode(&mut buf);
        assert_eq!(buf.len(), ACCOUNT_RECORD_SIZE);
        assert_eq!(ACCOUNT_RECORD_SIZE, 2059);
    }

    #[test]
    fn node_record_encoded_size() {
        let mut buf = Vec::new();
        sample_node().encode(&mut buf);
        assert_eq!(buf.len(), NODE_RECORD_SIZE);
        assert_eq!(NODE_RECORD_SIZE, 2098);
    }

    #[test]
    fn candidate_record_encoded_size() {
        let mut buf = Vec::new();
        sample_candidate().encode(&mut buf);
        assert_eq!(buf.len(), CANDIDATE_RECORD_SIZE);
        assert_eq!(CANDIDATE_RECORD_SIZE, 2082);
    }

    #[test]
    fn account_record_field_order() {
        let a = sample_account();
        let mut buf = Vec::new();
        a.encode(&mut buf);
        // First 32 bytes = account_id
        assert_eq!(&buf[..32], &a.account_id);
        // Next 16 bytes = balance LE
        assert_eq!(&buf[32..48], &a.balance.to_le_bytes());
        // Next 2 bytes = suite_id LE
        assert_eq!(&buf[48..50], &a.suite_id.to_le_bytes());
        // Next 1 byte = is_node_operator as u8
        assert_eq!(buf[50], 0u8); // false
    }

    #[test]
    fn account_record_is_node_operator_true_encodes_one() {
        let mut a = sample_account();
        a.is_node_operator = true;
        let mut buf = Vec::new();
        a.encode(&mut buf);
        assert_eq!(buf[50], 1u8);
    }

    #[test]
    fn node_record_field_order() {
        let n = sample_node();
        let mut buf = Vec::new();
        n.encode(&mut buf);
        // First 32 = node_id
        assert_eq!(&buf[..32], &n.node_id);
        // Next PUBLIC_KEY_SIZE (1952 для ML-DSA-65) = node_pubkey
        assert_eq!(&buf[32..32 + PUBLIC_KEY_SIZE], &n.node_pubkey);
    }

    #[test]
    fn candidate_record_field_order() {
        let c = sample_candidate();
        let mut buf = Vec::new();
        c.encode(&mut buf);
        assert_eq!(&buf[..32], &c.node_id);
        assert_eq!(&buf[32..32 + PUBLIC_KEY_SIZE], &c.node_pubkey);
    }

    #[test]
    fn encoding_deterministic() {
        let a = sample_account();
        let mut b1 = Vec::new();
        a.encode(&mut b1);
        let mut b2 = Vec::new();
        a.encode(&mut b2);
        assert_eq!(b1, b2);
    }

    #[test]
    fn derive_account_id_deterministic() {
        let pk = [0xAB; PUBLIC_KEY_SIZE];
        let id1 = derive_account_id(1, &pk);
        let id2 = derive_account_id(1, &pk);
        assert_eq!(id1, id2);
    }

    #[test]
    fn derive_account_id_formula() {
        let pk = [0xAB; PUBLIC_KEY_SIZE];
        let expected = hash(domain::ACCOUNT, &[&1u16.to_le_bytes(), &pk]);
        assert_eq!(derive_account_id(1, &pk), expected);
    }

    #[test]
    fn derive_account_id_differs_by_suite() {
        let pk = [0xAB; PUBLIC_KEY_SIZE];
        assert_ne!(derive_account_id(1, &pk), derive_account_id(2, &pk));
    }

    #[test]
    fn derive_node_id_formula() {
        let pk = [0xCD; PUBLIC_KEY_SIZE];
        let expected = hash(domain::NODE, &[&pk]);
        assert_eq!(derive_node_id(&pk), expected);
    }

    #[test]
    fn account_table_insert_get() {
        let mut t = AccountTable::new();
        assert!(t.is_empty());
        let a = sample_account();
        let id = a.account_id;
        t.insert(a.clone());
        assert!(t.contains(&id));
        assert_eq!(t.get(&id), Some(&a));
        assert_eq!(t.len(), 1);
    }

    #[test]
    fn account_table_remove() {
        let mut t = AccountTable::new();
        let a = sample_account();
        t.insert(a.clone());
        let removed = t.remove(&a.account_id);
        assert_eq!(removed, Some(a));
        assert!(t.is_empty());
    }

    #[test]
    fn account_table_root_changes_on_insert() {
        let mut t = AccountTable::new();
        let empty_root = t.root();
        t.insert(sample_account());
        assert_ne!(t.root(), empty_root);
    }

    #[test]
    fn account_table_root_stable_on_idempotent_insert() {
        let mut t = AccountTable::new();
        let a = sample_account();
        t.insert(a.clone());
        let r1 = t.root();
        t.insert(a);
        let r2 = t.root();
        assert_eq!(r1, r2);
    }

    #[test]
    fn account_table_root_order_independent() {
        let mut a1 = sample_account();
        a1.account_id = [0x01; 32];
        let mut a2 = sample_account();
        a2.account_id = [0x02; 32];
        let mut a3 = sample_account();
        a3.account_id = [0x03; 32];

        let mut t1 = AccountTable::new();
        t1.insert(a1.clone());
        t1.insert(a2.clone());
        t1.insert(a3.clone());

        let mut t2 = AccountTable::new();
        t2.insert(a3);
        t2.insert(a1);
        t2.insert(a2);

        assert_eq!(t1.root(), t2.root());
    }

    #[test]
    fn node_table_insert_get_root() {
        let mut t = NodeTable::new();
        let empty_root = t.root();
        let n = sample_node();
        t.insert(n.clone());
        assert_eq!(t.get(&n.node_id), Some(&n));
        assert_ne!(t.root(), empty_root);
    }

    #[test]
    fn candidate_pool_insert_get_root() {
        let mut p = CandidatePool::new();
        let empty_root = p.root();
        let c = sample_candidate();
        p.insert(c.clone());
        assert_eq!(p.get(&c.node_id), Some(&c));
        assert_ne!(p.root(), empty_root);
    }

    #[test]
    fn state_root_deterministic() {
        let node_root = [0x01; 32];
        let cand_root = [0x02; 32];
        let acct_root = [0x03; 32];
        let a = compute_state_root(&node_root, &cand_root, &acct_root);
        let b = compute_state_root(&node_root, &cand_root, &acct_root);
        assert_eq!(a, b);
    }

    #[test]
    fn state_root_detects_node_root_mutation() {
        let a = compute_state_root(&[0x01; 32], &[0x02; 32], &[0x03; 32]);
        let b = compute_state_root(&[0xFF; 32], &[0x02; 32], &[0x03; 32]);
        assert_ne!(a, b);
    }

    #[test]
    fn state_root_detects_candidate_root_mutation() {
        let a = compute_state_root(&[0x01; 32], &[0x02; 32], &[0x03; 32]);
        let b = compute_state_root(&[0x01; 32], &[0xFF; 32], &[0x03; 32]);
        assert_ne!(a, b);
    }

    #[test]
    fn state_root_detects_account_root_mutation() {
        let a = compute_state_root(&[0x01; 32], &[0x02; 32], &[0x03; 32]);
        let b = compute_state_root(&[0x01; 32], &[0x02; 32], &[0xFF; 32]);
        assert_ne!(a, b);
    }

    #[test]
    fn state_root_order_matters() {
        let r1 = [0x01; 32];
        let r2 = [0x02; 32];
        let r3 = [0x03; 32];
        assert_ne!(
            compute_state_root(&r1, &r2, &r3),
            compute_state_root(&r2, &r1, &r3)
        );
        assert_ne!(
            compute_state_root(&r1, &r2, &r3),
            compute_state_root(&r3, &r2, &r1)
        );
    }

    #[test]
    fn state_root_uses_domain_separator() {
        let r1 = [0x01; 32];
        let r2 = [0x02; 32];
        let r3 = [0x03; 32];
        let expected = hash(domain::STATE_ROOT, &[&r1, &r2, &r3]);
        assert_eq!(compute_state_root(&r1, &r2, &r3), expected);
    }

    #[test]
    fn is_active_same_window() {
        let mut n = sample_node();
        n.last_confirmation_window = 100;
        assert!(is_active(&n, 100, 20_160));
    }

    #[test]
    fn is_active_within_2_tau2() {
        let mut n = sample_node();
        let tau2 = 20_160u64;
        n.last_confirmation_window = 100;
        assert!(is_active(&n, 100 + 2 * tau2, tau2)); // ровно на границе
        assert!(is_active(&n, 100 + tau2, tau2));
    }

    #[test]
    fn is_active_beyond_2_tau2_false() {
        let mut n = sample_node();
        let tau2 = 20_160u64;
        n.last_confirmation_window = 100;
        assert!(!is_active(&n, 100 + 2 * tau2 + 1, tau2));
    }

    #[test]
    fn is_active_bootstrap_at_genesis() {
        // bootstrap узел имеет last_confirmation_window = 0
        // В окне 0 active должен быть true
        let mut n = sample_node();
        n.last_confirmation_window = 0;
        assert!(is_active(&n, 0, 20_160));
    }

    #[test]
    fn account_table_default_equals_new() {
        let t1 = AccountTable::new();
        let t2 = AccountTable::default();
        assert_eq!(t1.root(), t2.root());
    }

    #[test]
    fn empty_tables_have_same_empty_root() {
        let a = AccountTable::new();
        let n = NodeTable::new();
        let c = CandidatePool::new();
        // Все три используют SparseMerkleTree — empty root одинаков
        assert_eq!(a.root(), n.root());
        assert_eq!(n.root(), c.root());
    }

    #[test]
    fn pubkey_size_matches_crypto_constant() {
        // Связка: наши record types используют PUBLIC_KEY_SIZE из mt-crypto
        // ML-DSA-65 pubkey = 1952 B (FIPS 204 level 3)
        assert_eq!(PUBLIC_KEY_SIZE, 1952);
    }

    // ── Decode roundtrip tests (M7 typed insertion path) ──────────────────────

    #[test]
    fn account_record_decode_roundtrip() {
        let original = sample_account();
        let mut buf = Vec::new();
        original.encode(&mut buf);
        let decoded = AccountRecord::decode(&buf).expect("decode");
        assert_eq!(decoded, original);
    }

    #[test]
    fn account_record_decode_roundtrip_operator_true() {
        let mut original = sample_account();
        original.is_node_operator = true;
        let mut buf = Vec::new();
        original.encode(&mut buf);
        let decoded = AccountRecord::decode(&buf).expect("decode");
        assert!(decoded.is_node_operator);
        assert_eq!(decoded, original);
    }

    #[test]
    fn account_record_decode_rejects_wrong_size() {
        let too_short = vec![0u8; ACCOUNT_RECORD_SIZE - 1];
        assert_eq!(
            AccountRecord::decode(&too_short),
            Err(RecordDecodeError::WrongSize {
                expected: ACCOUNT_RECORD_SIZE,
                actual: ACCOUNT_RECORD_SIZE - 1
            })
        );
        let too_long = vec![0u8; ACCOUNT_RECORD_SIZE + 1];
        assert_eq!(
            AccountRecord::decode(&too_long),
            Err(RecordDecodeError::WrongSize {
                expected: ACCOUNT_RECORD_SIZE,
                actual: ACCOUNT_RECORD_SIZE + 1
            })
        );
    }

    #[test]
    fn account_record_decode_rejects_bad_bool_byte() {
        let original = sample_account();
        let mut buf = Vec::new();
        original.encode(&mut buf);
        // Corrupt is_node_operator byte (offset 50) with non-0/1 value.
        buf[50] = 2;
        assert_eq!(
            AccountRecord::decode(&buf),
            Err(RecordDecodeError::BadBoolByte(2))
        );
    }

    #[test]
    fn node_record_decode_roundtrip() {
        let original = sample_node();
        let mut buf = Vec::new();
        original.encode(&mut buf);
        let decoded = NodeRecord::decode(&buf).expect("decode");
        assert_eq!(decoded, original);
        assert_eq!(
            decoded.chain_length_checkpoints,
            original.chain_length_checkpoints
        );
    }

    #[test]
    fn node_record_decode_rejects_wrong_size() {
        let too_short = vec![0u8; NODE_RECORD_SIZE - 1];
        assert_eq!(
            NodeRecord::decode(&too_short),
            Err(RecordDecodeError::WrongSize {
                expected: NODE_RECORD_SIZE,
                actual: NODE_RECORD_SIZE - 1
            })
        );
    }

    #[test]
    fn candidate_record_decode_roundtrip() {
        let original = sample_candidate();
        let mut buf = Vec::new();
        original.encode(&mut buf);
        let decoded = CandidateRecord::decode(&buf).expect("decode");
        assert_eq!(decoded, original);
    }

    #[test]
    fn candidate_record_decode_rejects_wrong_size() {
        let too_short = vec![0u8; CANDIDATE_RECORD_SIZE - 1];
        assert_eq!(
            CandidateRecord::decode(&too_short),
            Err(RecordDecodeError::WrongSize {
                expected: CANDIDATE_RECORD_SIZE,
                actual: CANDIDATE_RECORD_SIZE - 1
            })
        );
    }
}
