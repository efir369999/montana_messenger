// spec, section "Account Chain (Block Lattice)"

use mt_codec::{domain, write_bytes, write_u128, write_u16, write_u8, CanonicalEncode};
use mt_crypto::{
    hash, suite_id_from_u16, verify, Hash32, PublicKey, Signature, PUBLIC_KEY_SIZE, SIGNATURE_SIZE,
};
use mt_state::{
    compute_state_root, derive_account_id, AccountId, AccountTable, CandidatePool, NodeId,
    NodeRecord, NodeTable,
};

// spec v30.x: OpenAccount removed; TransferActivation 0x0A creates an AccountRecord
// via a sponsor (the existing sender pays, the receiver is credited). type byte 0x01 is not allocated.
pub const TYPE_TRANSFER: u8 = 0x02;
pub const TYPE_CHANGE_KEY: u8 = 0x03;
pub const TYPE_ANCHOR: u8 = 0x04;
pub const TYPE_TRANSFER_ACTIVATION: u8 = 0x0A;

pub const TRANSFER_SIZE: usize = 1 + 32 + 32 + 32 + 16 + SIGNATURE_SIZE;
pub const CHANGE_KEY_SIZE: usize = 1 + 32 + 32 + 2 + PUBLIC_KEY_SIZE + SIGNATURE_SIZE;
pub const ANCHOR_SIZE: usize = 1 + 32 + 32 + 32 + 32 + SIGNATURE_SIZE;
// TransferActivation payload: sender 32 + receiver 32 + suite_id 2 + receiver_pubkey 1952 (ML-DSA-65) + amount 16
pub const TRANSFER_ACTIVATION_SIZE: usize =
    1 + 32 + 32 + 32 + 2 + PUBLIC_KEY_SIZE + 16 + SIGNATURE_SIZE;

pub type AppId = [u8; 32];
pub type DataHash = [u8; 32];

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Transfer {
    pub prev_hash: Hash32,
    pub sender: AccountId,
    pub link: AccountId,
    pub amount: u128,
    pub signature: Signature,
}

impl Transfer {
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        write_u8(buf, TYPE_TRANSFER);
        write_bytes(buf, &self.prev_hash);
        write_bytes(buf, &self.sender);
        write_bytes(buf, &self.link);
        write_u128(buf, self.amount);
    }
}

impl CanonicalEncode for Transfer {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ChangeKey {
    pub prev_hash: Hash32,
    pub sender: AccountId,
    pub new_suite_id: u16,
    pub new_pubkey: PublicKey,
    pub signature: Signature,
}

impl ChangeKey {
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        write_u8(buf, TYPE_CHANGE_KEY);
        write_bytes(buf, &self.prev_hash);
        write_bytes(buf, &self.sender);
        write_u16(buf, self.new_suite_id);
        write_bytes(buf, self.new_pubkey.as_bytes());
    }
}

impl CanonicalEncode for ChangeKey {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Anchor {
    pub prev_hash: Hash32,
    pub sender: AccountId,
    pub app_id: AppId,
    pub data_hash: DataHash,
    pub signature: Signature,
}

impl Anchor {
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        write_u8(buf, TYPE_ANCHOR);
        write_bytes(buf, &self.prev_hash);
        write_bytes(buf, &self.sender);
        write_bytes(buf, &self.app_id);
        write_bytes(buf, &self.data_hash);
    }
}

impl CanonicalEncode for Anchor {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

// spec: TransferActivation is a sponsor-activation operation that creates an AccountRecord for the receiver.
// Payload: sender + receiver + suite_id + receiver_pubkey + amount.
// Binding: receiver == SHA-256("mt-account" || suite_id || receiver_pubkey).
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransferActivation {
    pub prev_hash: Hash32,
    pub sender: AccountId,
    pub receiver: AccountId,
    pub suite_id: u16,
    pub receiver_pubkey: PublicKey,
    pub amount: u128,
    pub signature: Signature,
}

impl TransferActivation {
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        write_u8(buf, TYPE_TRANSFER_ACTIVATION);
        write_bytes(buf, &self.prev_hash);
        write_bytes(buf, &self.sender);
        write_bytes(buf, &self.receiver);
        write_u16(buf, self.suite_id);
        write_bytes(buf, self.receiver_pubkey.as_bytes());
        write_u128(buf, self.amount);
    }
}

impl CanonicalEncode for TransferActivation {
    fn encode(&self, buf: &mut Vec<u8>) {
        self.encode_signed_scope(buf);
        write_bytes(buf, self.signature.as_bytes());
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Operation {
    Transfer(Transfer),
    ChangeKey(ChangeKey),
    Anchor(Anchor),
    TransferActivation(TransferActivation),
}

impl Operation {
    pub fn encode_signed_scope(&self, buf: &mut Vec<u8>) {
        match self {
            Self::Transfer(op) => op.encode_signed_scope(buf),
            Self::ChangeKey(op) => op.encode_signed_scope(buf),
            Self::Anchor(op) => op.encode_signed_scope(buf),
            Self::TransferActivation(op) => op.encode_signed_scope(buf),
        }
    }
}

impl CanonicalEncode for Operation {
    fn encode(&self, buf: &mut Vec<u8>) {
        match self {
            Self::Transfer(op) => op.encode(buf),
            Self::ChangeKey(op) => op.encode(buf),
            Self::Anchor(op) => op.encode(buf),
            Self::TransferActivation(op) => op.encode(buf),
        }
    }
}

// spec: Rule R2 — identifier(op) = SHA-256("mt-op" || signed_scope(op))
// Stable under any signature scheme (the signature is excluded from the hash); for
// ML-DSA-65 the deterministic-variant signature is reproducible too, but R2
// does not depend on that property.
pub fn op_hash(op: &Operation) -> Hash32 {
    let mut buf = Vec::new();
    op.encode_signed_scope(&mut buf);
    hash(domain::OP, &[&buf])
}

// spec: "Account Chain (Block Lattice)" + "Balance verification" + validation table
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum OpError {
    InvalidPrevHash,
    DuplicateAccount,
    AccountNotFound,
    ReceiverNotActive,
    ReceiverAlreadyExists,
    InvalidBinding,
    InvalidSignature,
    InsufficientBalance,
    SelfTransfer,
    ZeroAmount,
    UnsupportedSuite,
    ActivationCooldownNotElapsed,
}

fn verify_signed_scope(
    scope: &[u8],
    signature: &Signature,
    pubkey_bytes: &[u8; PUBLIC_KEY_SIZE],
) -> bool {
    let pk = PublicKey::from_array(*pubkey_bytes);
    verify(&pk, scope, signature)
}

pub fn validate_transfer(op: &Transfer, state: &AccountTable) -> Result<(), OpError> {
    let sender = state.get(&op.sender).ok_or(OpError::AccountNotFound)?;
    if sender.frontier_hash != op.prev_hash {
        return Err(OpError::InvalidPrevHash);
    }
    if op.sender == op.link {
        return Err(OpError::SelfTransfer);
    }
    if op.amount == 0 {
        return Err(OpError::ZeroAmount);
    }
    if sender.balance < op.amount {
        return Err(OpError::InsufficientBalance);
    }
    // spec: receiver MUST exist in AccountTable; new accounts are created only via TransferActivation
    if !state.contains(&op.link) {
        return Err(OpError::ReceiverNotActive);
    }
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    if !verify_signed_scope(&scope, &op.signature, &sender.current_pubkey) {
        return Err(OpError::InvalidSignature);
    }
    Ok(())
}

// spec: TransferActivation invariants per v30.4.0+:
// (a) sender exists, prev_hash matches frontier
// (b) receiver NOT in AccountTable (creating a new record)
// (c) receiver == SHA-256("mt-account" || suite_id || receiver_pubkey) binding
// (d) amount > 0, sender.balance >= amount
// (e) cooldown [I-15]: current_window >= sender.last_activation_window + τ₂
//     (sender.last_activation_window == 0 — never activated, no check)
// (f) signature valid for sender.current_pubkey
// current_window and tau2_windows are consensus-level types (u64), as in the
// apply_proposal input. State field sender.last_activation_window: u32
// (encoded size optimization up to 4.29 billion windows, ~8000 years). The u32→u64 cast
// is done inside the function when comparing — the caller need not pre-cast.
pub fn validate_transfer_activation(
    op: &TransferActivation,
    state: &AccountTable,
    current_window: u64,
    tau2_windows: u64,
) -> Result<(), OpError> {
    let sender = state.get(&op.sender).ok_or(OpError::AccountNotFound)?;
    if sender.frontier_hash != op.prev_hash {
        return Err(OpError::InvalidPrevHash);
    }
    if state.contains(&op.receiver) {
        return Err(OpError::ReceiverAlreadyExists);
    }
    if suite_id_from_u16(op.suite_id).is_none() {
        return Err(OpError::UnsupportedSuite);
    }
    let derived = derive_account_id(op.suite_id, op.receiver_pubkey.as_bytes());
    if derived != op.receiver {
        return Err(OpError::InvalidBinding);
    }
    if op.sender == op.receiver {
        return Err(OpError::SelfTransfer);
    }
    if op.amount == 0 {
        return Err(OpError::ZeroAmount);
    }
    if sender.balance < op.amount {
        return Err(OpError::InsufficientBalance);
    }
    // spec [I-15]: cooldown 1 TransferActivation per sender per τ₂.
    // Cast u32→u64 for the consensus-level comparison (state field is u32, ctx is u64).
    if sender.last_activation_window != 0
        && current_window < (sender.last_activation_window as u64).saturating_add(tau2_windows)
    {
        return Err(OpError::ActivationCooldownNotElapsed);
    }
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    if !verify_signed_scope(&scope, &op.signature, &sender.current_pubkey) {
        return Err(OpError::InvalidSignature);
    }
    Ok(())
}

pub fn validate_change_key(op: &ChangeKey, state: &AccountTable) -> Result<(), OpError> {
    let sender = state.get(&op.sender).ok_or(OpError::AccountNotFound)?;
    if sender.frontier_hash != op.prev_hash {
        return Err(OpError::InvalidPrevHash);
    }
    if suite_id_from_u16(op.new_suite_id).is_none() {
        return Err(OpError::UnsupportedSuite);
    }
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    // spec: ChangeKey is signed by the OLD key (current_pubkey in state before apply)
    if !verify_signed_scope(&scope, &op.signature, &sender.current_pubkey) {
        return Err(OpError::InvalidSignature);
    }
    Ok(())
}

pub fn validate_anchor(op: &Anchor, state: &AccountTable) -> Result<(), OpError> {
    let sender = state.get(&op.sender).ok_or(OpError::AccountNotFound)?;
    if sender.frontier_hash != op.prev_hash {
        return Err(OpError::InvalidPrevHash);
    }
    let mut scope = Vec::new();
    op.encode_signed_scope(&mut scope);
    if !verify_signed_scope(&scope, &op.signature, &sender.current_pubkey) {
        return Err(OpError::InvalidSignature);
    }
    Ok(())
}

// Validation context: a mandatory wrapper for the consensus-dependent parameters of the
// window. Passed to generic validate(op, state, ctx). TransferActivation
// needs current_window + tau2_windows for the cooldown check ([I-15] time-based
// scarcity, 1 activation per sender per τ₂). The other opcodes ignore the
// context (fields are available but unused) — making it mandatory
// guarantees the caller will not forget the context when new
// context-dependent operations are added in the future.
#[derive(Clone, Copy, Debug)]
pub struct ValidationContext {
    pub current_window: u64,
    pub tau2_windows: u64,
}

pub fn validate(
    op: &Operation,
    state: &AccountTable,
    ctx: &ValidationContext,
) -> Result<(), OpError> {
    match op {
        Operation::Transfer(inner) => validate_transfer(inner, state),
        Operation::ChangeKey(inner) => validate_change_key(inner, state),
        Operation::Anchor(inner) => validate_anchor(inner, state),
        Operation::TransferActivation(inner) => {
            validate_transfer_activation(inner, state, ctx.current_window, ctx.tau2_windows)
        },
    }
}

// spec: "State transition" + "Anti-inflation"
// apply_* assumes validated input (Phase B). expect() on a protocol invariant
// violation means apply was called without a prior validate (a bug).

// spec v30.4.0+: TransferActivation creates an AccountRecord for the receiver from the sender.
// Sender: balance -= amount, frontier_hash = op_hash, chain increments, last_activation_window = window_w.
// Receiver: a new record with pubkey from the payload, balance = amount, frontier_hash = 0x00 (genesis chain),
// last_activation_window = 0 (never activated).
// Hot-fix utility: AccountRecord uses u32 for window fields (encoded size
// optimization), but apply_proposal passes window_w: u64 (consensus types).
// The cast is safe up to 4.29 billion windows (~8000 years at 60 sec/window). Beyond that a protocol
// upgrade is needed.
fn window_w_to_u32(w: u64, context: &'static str) -> u32 {
    u32::try_from(w).unwrap_or_else(|_| {
        panic!(
            "{context}: window_w = {w} > u32::MAX — encoded arithmetic horizon \
             reached (~8000 years at 60 sec/window), protocol upgrade required"
        )
    })
}

pub fn apply_transfer_activation(op: &TransferActivation, state: &mut AccountTable, window_w: u64) {
    let frontier = op_hash(&Operation::TransferActivation(op.clone()));

    let mut sender = state
        .get(&op.sender)
        .expect("protocol invariant: validate_transfer_activation ensures sender exists")
        .clone();
    // Checked arithmetic for defense-in-depth: validate_* guarantees
    // balance >= amount, but overflow protection remains as an explicit halt
    // in case of a protocol invariant breach.
    sender.balance = sender.balance.checked_sub(op.amount).unwrap_or_else(|| {
        panic!(
            "apply_transfer_activation: balance underflow — protocol invariant breach \
             (validate_transfer_activation should have rejected an op with balance={} < amount={})",
            sender.balance, op.amount
        )
    });
    sender.frontier_hash = frontier;
    sender.op_height = sender.op_height.checked_add(1).unwrap_or_else(|| {
        panic!("apply_transfer_activation: op_height overflow at u32::MAX — encoded arithmetic horizon")
    });
    sender.account_chain_length = sender
        .account_chain_length
        .checked_add(1)
        .unwrap_or_else(|| {
            panic!("apply_transfer_activation: account_chain_length overflow at u32::MAX")
        });
    sender.last_op_window = window_w_to_u32(window_w, "apply_transfer_activation last_op_window");
    sender.last_activation_window =
        window_w_to_u32(window_w, "apply_transfer_activation last_activation_window");
    state.insert(sender);

    let receiver_record = mt_state::AccountRecord {
        account_id: op.receiver,
        balance: op.amount,
        suite_id: op.suite_id,
        is_node_operator: false,
        frontier_hash: [0u8; 32],
        op_height: 0,
        account_chain_length: 0,
        account_chain_length_snapshot: 0,
        current_pubkey: *op.receiver_pubkey.as_bytes(),
        creation_window: window_w_to_u32(window_w, "apply_transfer_activation creation_window"),
        last_op_window: window_w_to_u32(
            window_w,
            "apply_transfer_activation receiver last_op_window",
        ),
        last_activation_window: 0,
    };
    state.insert(receiver_record);
}

pub fn apply_transfer(op: &Transfer, state: &mut AccountTable, window_w: u64) {
    let frontier = op_hash(&Operation::Transfer(op.clone()));

    // Sender update: balance -= amount, frontier, chain_length, op_height, last_op_window
    let mut sender = state
        .get(&op.sender)
        .expect("protocol invariant: validate_transfer ensures sender exists")
        .clone();
    sender.balance = sender.balance.checked_sub(op.amount).unwrap_or_else(|| {
        panic!(
            "apply_transfer: balance underflow — protocol invariant breach \
             (validate_transfer should have rejected an op with balance={} < amount={})",
            sender.balance, op.amount
        )
    });
    sender.frontier_hash = frontier;
    sender.op_height = sender
        .op_height
        .checked_add(1)
        .unwrap_or_else(|| panic!("apply_transfer: op_height overflow at u32::MAX"));
    sender.account_chain_length = sender
        .account_chain_length
        .checked_add(1)
        .unwrap_or_else(|| panic!("apply_transfer: account_chain_length overflow at u32::MAX"));
    sender.last_op_window = window_w_to_u32(window_w, "apply_transfer last_op_window");
    state.insert(sender);

    // Receiver update: ONLY balance += amount (spec dep rule:
    //   "The receiver of a Transfer does not get a chain_length update")
    let mut receiver = state
        .get(&op.link)
        .expect("protocol invariant: validate_transfer ensures receiver exists")
        .clone();
    receiver.balance = receiver.balance.checked_add(op.amount).unwrap_or_else(|| {
        panic!(
            "apply_transfer: receiver balance overflow at u128::MAX (balance={}, amount={}) — \
             encoded arithmetic horizon",
            receiver.balance, op.amount
        )
    });
    state.insert(receiver);
}

pub fn apply_change_key(op: &ChangeKey, state: &mut AccountTable, window_w: u64) {
    let frontier = op_hash(&Operation::ChangeKey(op.clone()));

    let mut sender = state
        .get(&op.sender)
        .expect("protocol invariant: validate_change_key ensures sender exists")
        .clone();
    sender.current_pubkey = *op.new_pubkey.as_bytes();
    sender.suite_id = op.new_suite_id;
    sender.frontier_hash = frontier;
    sender.op_height = sender
        .op_height
        .checked_add(1)
        .unwrap_or_else(|| panic!("apply_change_key: op_height overflow at u32::MAX"));
    sender.account_chain_length = sender
        .account_chain_length
        .checked_add(1)
        .unwrap_or_else(|| panic!("apply_change_key: account_chain_length overflow at u32::MAX"));
    sender.last_op_window = window_w_to_u32(window_w, "apply_change_key last_op_window");
    state.insert(sender);
}

pub fn apply_anchor(op: &Anchor, state: &mut AccountTable, window_w: u64) {
    let frontier = op_hash(&Operation::Anchor(op.clone()));

    // data_hash lives in the proposal chain, not in AccountTable — only frontier + chain_length update
    let mut sender = state
        .get(&op.sender)
        .expect("protocol invariant: validate_anchor ensures sender exists")
        .clone();
    sender.frontier_hash = frontier;
    sender.op_height = sender
        .op_height
        .checked_add(1)
        .unwrap_or_else(|| panic!("apply_anchor: op_height overflow at u32::MAX"));
    sender.account_chain_length = sender
        .account_chain_length
        .checked_add(1)
        .unwrap_or_else(|| panic!("apply_anchor: account_chain_length overflow at u32::MAX"));
    sender.last_op_window = window_w_to_u32(window_w, "apply_anchor last_op_window");
    state.insert(sender);
}

pub fn apply(op: &Operation, state: &mut AccountTable, window_w: u64) {
    match op {
        Operation::Transfer(inner) => apply_transfer(inner, state, window_w),
        Operation::ChangeKey(inner) => apply_change_key(inner, state, window_w),
        Operation::Anchor(inner) => apply_anchor(inner, state, window_w),
        Operation::TransferActivation(inner) => apply_transfer_activation(inner, state, window_w),
    }
}

// spec: "Emission" — const emission `reward_moneta(W) = EMISSION_moneta`.

use mt_genesis::ProtocolParams;

/// reward(W) = EMISSION_moneta — a constant from ProtocolParams.
pub fn reward_moneta(params: &ProtocolParams) -> u128 {
    params.emission_moneta
}

/// Total emitted supply over windows [1, window] — closed-form (window 0 has no emission).
/// `supply_moneta(W) = EMISSION_moneta × W` (supply_moneta(0) = 0; first payout settle(1)).
pub fn supply_moneta(window: u64, params: &ProtocolParams) -> u128 {
    params.emission_moneta * u128::from(window)
}

// spec: "State transition → apply_proposal" steps 2, 3.5, 3.6, 4.
// Steps 1, 3a, 3b stubbed until M4 (NodeRegistration/candidate expiry/selection event).

pub use mt_state::WINNER_CLASS_NODE;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProposalSettle {
    pub window_w: u64,
    pub winner_id: [u8; 32],
    pub cemented_confirmers: Vec<NodeId>,
}

// spec: "settle (apply at window close)" — cemented UserObjects of window W
// are applied as a batch in op_hash lex asc order.
pub fn settle_window(state: &mut AccountTable, cemented_ops: &[Operation], window_w: u64) {
    let mut indexed: Vec<(Hash32, &Operation)> =
        cemented_ops.iter().map(|op| (op_hash(op), op)).collect();
    indexed.sort_by_key(|(h, _)| *h);
    for (_, op) in indexed {
        apply(op, state, window_w);
    }
}

// Step 2: reward emission — winner_{W-1} receives EMISSION_moneta.
// spec Sovereignty Ladder: the lottery is single-class, the winner is always a node;
// the reward is credited to the winner node's operator_account_id.
//
// Protocol invariant: for any NodeRecord in NodeTable, the field
// operator_account_id must point to an existing AccountRecord in
// AccountTable. An invariant violation → panic in apply_emission; protection
// via an explicit panic, not a silent skip — a corrupted NodeTable guarantees
// a fork and must be detected immediately.
fn apply_emission(
    account_table: &mut AccountTable,
    node_table: &NodeTable,
    window_w: u64,
    winner_id: &[u8; 32],
    params: &ProtocolParams,
) {
    if window_w == 0 {
        return; // genesis: no W-1
    }
    let reward = reward_moneta(params);
    let node = node_table
        .get(winner_id)
        .expect("protocol invariant: winner node exists in NodeTable");
    let operator_id = node.operator_account_id;
    let mut operator = account_table
        .get(&operator_id)
        .expect("protocol invariant: operator account exists")
        .clone();
    operator.balance = operator.balance.checked_add(reward).unwrap_or_else(|| {
        panic!(
            "apply_emission: operator balance overflow at u128::MAX (balance={}, reward={}) — \
             encoded arithmetic horizon",
            operator.balance, reward
        )
    });
    account_table.insert(operator);
}

// Step 3.5: chain_length++ for nodes with a cemented BundledConfirmation in window W.
// Checked arithmetic for consistency with apply_transfer / apply_change_key /
// apply_anchor / apply_emission / apply_transfer_activation. u64 overflow
// horizon ~3.5×10^11 years at 60 sec/window — practically unreachable, panic
// = explicit halt on a protocol invariant breach.
fn apply_chain_length_increment(node_table: &mut NodeTable, confirmers: &[NodeId], window_w: u64) {
    for node_id in confirmers {
        if let Some(existing) = node_table.get(node_id) {
            let mut node = existing.clone();
            node.chain_length = node.chain_length.checked_add(1).unwrap_or_else(|| {
                panic!(
                    "apply_chain_length_increment: chain_length overflow at u64::MAX \
                     — encoded arithmetic horizon (~3.5×10^11 years at 60 sec/window)"
                )
            });
            node.last_confirmation_window = window_w;
            node_table.insert(node);
        }
    }
}

// Step 3.6: rotate chain_length_checkpoints at the τ₂ boundary.
// Shift: the oldest (index 0) drops out, the rest shift, newest (5) = current chain_length.
// chain_length_snapshot = chain_length - checkpoints[0] (the oldest after rotation).
// Checked subtraction guards against a protocol invariant breach: the rotation logic
// always maintains checkpoints[0] ≤ chain_length (newest = current,
// shift left → the older ones ≤ the current). Underflow means a corrupted state or a
// bug in the rotation invariant — panic, not a silent wrap to u64::MAX.
fn apply_checkpoint_rotation(node_table: &mut NodeTable, window_w: u64, params: &ProtocolParams) {
    if window_w == 0 || window_w % params.tau2_windows != 0 {
        return;
    }
    let snapshot: Vec<NodeRecord> = node_table.iter().cloned().collect();
    for node in snapshot {
        let mut rotated = node.clone();
        for i in 0..5 {
            rotated.chain_length_checkpoints[i] = rotated.chain_length_checkpoints[i + 1];
        }
        rotated.chain_length_checkpoints[5] = rotated.chain_length;
        rotated.chain_length_snapshot = rotated
            .chain_length
            .checked_sub(rotated.chain_length_checkpoints[0])
            .unwrap_or_else(|| {
                panic!(
                    "apply_checkpoint_rotation: invariant breach — checkpoints[0] ({}) > \
                     chain_length ({}) — rotation logic corrupted",
                    rotated.chain_length_checkpoints[0], rotated.chain_length
                )
            });
        node_table.insert(rotated);
    }
}

// spec: "Entry and registration → Genesis State"
//
// Genesis State is the network's axiom: an empty window 0. No baked-in bootstrap operator,
// no N_SEED cohort. Account Table, Node Table, Candidate Pool are empty; their roots
// equal the root of the empty sparse-Merkle tree (empty_internal(256)). The first node
// brings the network up through the existing admission path: with a zero Active set
// selection_slots(0)=1 self-admits the first candidate, and quorum(1)=1 lets it
// cement its own chain.

pub const GENESIS_SUITE_ID: u16 = 1;

pub struct GenesisState {
    pub account_table: AccountTable,
    pub node_table: NodeTable,
    pub candidate_pool: CandidatePool,
}

pub fn build_genesis_state(_params: &ProtocolParams) -> GenesisState {
    GenesisState {
        account_table: AccountTable::new(),
        node_table: NodeTable::new(),
        candidate_pool: CandidatePool::new(),
    }
}

pub fn genesis_state_root(state: &GenesisState) -> Hash32 {
    compute_state_root(
        &state.node_table.root(),
        &state.candidate_pool.root(),
        &state.account_table.root(),
    )
}

// spec, "State transition → apply_proposal" — orchestration steps 2/3.5/3.6/4.
//
// Settle (cemented user ops applied via `settle_window`) runs OUTSIDE
// apply_proposal, a design choice: the caller (M4 mt-consensus orchestrator) calls
// settle_window(account_table, cemented_ops, window_w) BEFORE apply_proposal —
// cemented user operations must be applied to state BEFORE emission, so that
// balance changes are visible in the reward account update.
//
// Steps 1, 3a, 3b stubbed (M4 mt-entry: NodeRegistration batch / candidate
// expiry / selection event) — orchestration tracker in M4.
pub fn apply_proposal(
    account_table: &mut AccountTable,
    node_table: &mut NodeTable,
    candidate_pool: &CandidatePool,
    input: &ProposalSettle,
    params: &ProtocolParams,
) -> Hash32 {
    // Step 1 stub: control_set (ControlObjects = NodeRegistrations) — M4 (mt-entry).
    // Step 2: emission for window W-1 — the constant EMISSION_moneta.
    apply_emission(
        account_table,
        node_table,
        input.window_w,
        &input.winner_id,
        params,
    );
    // Step 3a, 3b stubs: candidate expiry + selection event — M4 (mt-entry).
    // Step 3.5:
    apply_chain_length_increment(node_table, &input.cemented_confirmers, input.window_w);
    // Step 3.6:
    apply_checkpoint_rotation(node_table, input.window_w, params);
    // Step 4: state_root.
    compute_state_root(
        &node_table.root(),
        &candidate_pool.root(),
        &account_table.root(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    fn sample_pubkey(seed: u8) -> PublicKey {
        PublicKey::from_array([seed; PUBLIC_KEY_SIZE])
    }

    fn sample_signature(seed: u8) -> Signature {
        Signature::from_array([seed; SIGNATURE_SIZE])
    }

    fn sample_transfer_activation() -> TransferActivation {
        let pk = sample_pubkey(0xAA);
        let receiver = derive_account_id(0x0001, pk.as_bytes());
        TransferActivation {
            prev_hash: [0x10u8; 32],
            sender: [0x20u8; 32],
            receiver,
            suite_id: 0x0001,
            receiver_pubkey: pk,
            amount: 500_000_000_000u128,
            signature: sample_signature(0xBB),
        }
    }

    fn sample_transfer() -> Transfer {
        Transfer {
            prev_hash: [0x11u8; 32],
            sender: [0x22u8; 32],
            link: [0x33u8; 32],
            amount: 1_000_000_000u128,
            signature: sample_signature(0xCC),
        }
    }

    fn sample_change_key() -> ChangeKey {
        ChangeKey {
            prev_hash: [0x44u8; 32],
            sender: [0x55u8; 32],
            new_suite_id: 0x0001,
            new_pubkey: sample_pubkey(0xDD),
            signature: sample_signature(0xEE),
        }
    }

    fn sample_anchor() -> Anchor {
        Anchor {
            prev_hash: [0x66u8; 32],
            sender: [0x77u8; 32],
            app_id: [0x88u8; 32],
            data_hash: [0x99u8; 32],
            signature: sample_signature(0xAB),
        }
    }

    #[test]
    fn transfer_activation_encodes_to_expected_size() {
        let mut buf = Vec::new();
        sample_transfer_activation().encode(&mut buf);
        assert_eq!(buf.len(), TRANSFER_ACTIVATION_SIZE);
        // type 1 + prev_hash 32 + sender 32 + receiver 32 + suite_id 2
        // + receiver_pubkey 1952 (ML-DSA-65) + amount 16 + signature 3309 = 5376
        assert_eq!(TRANSFER_ACTIVATION_SIZE, 5376);
    }

    #[test]
    fn transfer_encodes_to_expected_size() {
        let mut buf = Vec::new();
        sample_transfer().encode(&mut buf);
        assert_eq!(buf.len(), TRANSFER_SIZE);
        // type 1 + prev_hash 32 + sender 32 + link 32 + amount 16
        // + signature 3309 (ML-DSA-65) = 3422
        assert_eq!(TRANSFER_SIZE, 3422);
    }

    #[test]
    fn change_key_encodes_to_expected_size() {
        let mut buf = Vec::new();
        sample_change_key().encode(&mut buf);
        assert_eq!(buf.len(), CHANGE_KEY_SIZE);
        // type 1 + prev_hash 32 + sender 32 + new_suite_id 2
        // + new_pubkey 1952 + signature 3309 = 5328
        assert_eq!(CHANGE_KEY_SIZE, 5328);
    }

    #[test]
    fn anchor_encodes_to_expected_size() {
        let mut buf = Vec::new();
        sample_anchor().encode(&mut buf);
        assert_eq!(buf.len(), ANCHOR_SIZE);
        // type 1 + prev_hash 32 + sender 32 + app_id 32 + data_hash 32
        // + signature 3309 = 3438
        assert_eq!(ANCHOR_SIZE, 3438);
    }

    #[test]
    fn first_byte_is_type_code() {
        let mut b2 = Vec::new();
        sample_transfer().encode(&mut b2);
        assert_eq!(b2[0], TYPE_TRANSFER);

        let mut b3 = Vec::new();
        sample_change_key().encode(&mut b3);
        assert_eq!(b3[0], TYPE_CHANGE_KEY);

        let mut b4 = Vec::new();
        sample_anchor().encode(&mut b4);
        assert_eq!(b4[0], TYPE_ANCHOR);

        let mut b5 = Vec::new();
        sample_transfer_activation().encode(&mut b5);
        assert_eq!(b5[0], TYPE_TRANSFER_ACTIVATION);
    }

    #[test]
    fn prev_hash_is_bytes_1_through_32() {
        let mut buf = Vec::new();
        sample_transfer().encode(&mut buf);
        assert_eq!(&buf[1..33], &[0x11u8; 32]);
    }

    #[test]
    fn transfer_amount_little_endian() {
        let mut buf = Vec::new();
        sample_transfer().encode(&mut buf);
        // type(1) + prev_hash(32) + sender(32) + link(32) = offset 97
        let amount_bytes = &buf[97..97 + 16];
        assert_eq!(amount_bytes, &1_000_000_000u128.to_le_bytes());
    }

    #[test]
    fn transfer_field_order_sender_link_amount() {
        let mut buf = Vec::new();
        sample_transfer().encode(&mut buf);
        assert_eq!(&buf[33..65], &[0x22u8; 32]); // sender
        assert_eq!(&buf[65..97], &[0x33u8; 32]); // link
    }

    #[test]
    fn change_key_field_order() {
        let mut buf = Vec::new();
        sample_change_key().encode(&mut buf);
        assert_eq!(&buf[33..65], &[0x55u8; 32]); // sender
        assert_eq!(u16::from_le_bytes([buf[65], buf[66]]), 0x0001); // new_suite_id
        assert_eq!(&buf[67..67 + PUBLIC_KEY_SIZE], &[0xDDu8; PUBLIC_KEY_SIZE]); // new_pubkey
    }

    #[test]
    fn anchor_field_order() {
        let mut buf = Vec::new();
        sample_anchor().encode(&mut buf);
        assert_eq!(&buf[33..65], &[0x77u8; 32]); // sender
        assert_eq!(&buf[65..97], &[0x88u8; 32]); // app_id
        assert_eq!(&buf[97..129], &[0x99u8; 32]); // data_hash
    }

    #[test]
    fn operation_enum_delegates_to_each_variant() {
        let cases: [(Operation, Vec<u8>); 4] = [
            (Operation::Transfer(sample_transfer()), {
                let mut b = Vec::new();
                sample_transfer().encode(&mut b);
                b
            }),
            (Operation::ChangeKey(sample_change_key()), {
                let mut b = Vec::new();
                sample_change_key().encode(&mut b);
                b
            }),
            (Operation::Anchor(sample_anchor()), {
                let mut b = Vec::new();
                sample_anchor().encode(&mut b);
                b
            }),
            (
                Operation::TransferActivation(sample_transfer_activation()),
                {
                    let mut b = Vec::new();
                    sample_transfer_activation().encode(&mut b);
                    b
                },
            ),
        ];
        for (op, expected) in cases {
            let mut via_enum = Vec::new();
            op.encode(&mut via_enum);
            assert_eq!(via_enum, expected);
        }
    }

    #[test]
    fn op_hash_is_deterministic() {
        let op = Operation::Transfer(sample_transfer());
        assert_eq!(op_hash(&op), op_hash(&op));
    }

    #[test]
    fn op_hash_uses_mt_op_domain_over_signed_scope() {
        // Rule R2: identifier(op) = hash("mt-op", [signed_scope(op)])
        //                            = SHA-256("mt-op" || 0x00 || signed_scope)
        // NUL byte separator — self-delimiting domain separation (spec v29.13.0).
        // signed_scope = canonical_bytes without the signature (last SIGNATURE_SIZE bytes).
        let op = Operation::Transfer(sample_transfer());
        let mut signed_scope = Vec::new();
        op.encode_signed_scope(&mut signed_scope);

        let mut hasher = Sha256::new();
        hasher.update(b"mt-op");
        hasher.update([0u8]); // NUL separator per canonical hash primitive
        hasher.update(&signed_scope);
        let expected: Hash32 = hasher.finalize().into();

        assert_eq!(op_hash(&op), expected);
    }

    #[test]
    fn op_hash_stable_under_signature_mutation() {
        // Positive test for SSI Rule R2: op_hash does not depend on σ.
        // ML-DSA-65 in Montana works in the deterministic variant, so re-signing
        // yields the same σ — but R2 must not rely on that property:
        // identifier(op) must be identical even under an arbitrary mutation of σ.
        let mut t1 = sample_transfer();
        let t1_hash = op_hash(&Operation::Transfer(t1.clone()));

        // Simulate re-signing the same logical op with other randomness → a different σ
        t1.signature = Signature::from_array([0xFFu8; SIGNATURE_SIZE]);
        let t2_hash = op_hash(&Operation::Transfer(t1));

        assert_eq!(
            t1_hash, t2_hash,
            "op_hash must be stable under signature change (SSI R2)"
        );
    }

    #[test]
    fn signed_scope_excludes_signature() {
        // SSI Rule R1: signed_scope = canonical_bytes without the last SIGNATURE_SIZE bytes.
        let op = sample_transfer();
        let mut canonical = Vec::new();
        op.encode(&mut canonical);
        let mut scope = Vec::new();
        op.encode_signed_scope(&mut scope);

        assert_eq!(canonical.len(), TRANSFER_SIZE);
        assert_eq!(scope.len(), TRANSFER_SIZE - SIGNATURE_SIZE);
        assert_eq!(&canonical[..scope.len()], scope.as_slice());
    }

    #[test]
    fn different_operations_produce_different_hashes() {
        let h1 = op_hash(&Operation::TransferActivation(sample_transfer_activation()));
        let h2 = op_hash(&Operation::Transfer(sample_transfer()));
        let h3 = op_hash(&Operation::ChangeKey(sample_change_key()));
        let h4 = op_hash(&Operation::Anchor(sample_anchor()));
        assert_ne!(h1, h2);
        assert_ne!(h1, h3);
        assert_ne!(h1, h4);
        assert_ne!(h2, h3);
        assert_ne!(h2, h4);
        assert_ne!(h3, h4);
    }

    #[test]
    fn mutated_field_changes_op_hash() {
        let mut t = sample_transfer();
        let h_before = op_hash(&Operation::Transfer(t.clone()));
        t.amount += 1;
        let h_after = op_hash(&Operation::Transfer(t));
        assert_ne!(h_before, h_after);
    }

    #[test]
    fn signature_position_is_last_signature_size_bytes() {
        let mut buf = Vec::new();
        sample_transfer().encode(&mut buf);
        let sig_start = buf.len() - SIGNATURE_SIZE;
        assert_eq!(&buf[sig_start..], &[0xCCu8; SIGNATURE_SIZE]);
    }

    #[test]
    fn type_codes_are_stable() {
        // type byte 0x01 is not allocated (OpenAccount removed)
        assert_eq!(TYPE_TRANSFER, 0x02);
        assert_eq!(TYPE_CHANGE_KEY, 0x03);
        assert_eq!(TYPE_ANCHOR, 0x04);
        assert_eq!(TYPE_TRANSFER_ACTIVATION, 0x0A);
    }

    // ================== Phase B: validation ==================

    use mt_crypto::{keypair, sign, SecretKey};
    use mt_state::AccountRecord;

    const MLDSA_SUITE: u16 = 0x0001;

    fn make_account_record(
        pubkey_bytes: &[u8; PUBLIC_KEY_SIZE],
        suite_id: u16,
        balance: u128,
        frontier: Hash32,
    ) -> AccountRecord {
        let account_id = derive_account_id(suite_id, pubkey_bytes);
        AccountRecord {
            account_id,
            balance,
            suite_id,
            is_node_operator: false,
            frontier_hash: frontier,
            op_height: 1,
            account_chain_length: 1,
            account_chain_length_snapshot: 1,
            current_pubkey: *pubkey_bytes,
            creation_window: 0,
            last_op_window: 0,
            last_activation_window: 0,
        }
    }

    fn sign_op<F>(sk: &SecretKey, encode_scope: F) -> Signature
    where
        F: FnOnce(&mut Vec<u8>),
    {
        let mut scope = Vec::new();
        encode_scope(&mut scope);
        sign(sk, &scope).expect("sign op scope")
    }

    // ---- TransferActivation ----

    #[test]
    fn validate_transfer_activation_happy() {
        let (sender_pk, sender_sk) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let mut state = AccountTable::new();
        state.insert(make_account_record(
            sender_pk.as_bytes(),
            MLDSA_SUITE,
            1_000_000_000,
            [0u8; 32],
        ));
        let (receiver_pk, _) = keypair();
        let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());
        let mut op = TransferActivation {
            prev_hash: [0u8; 32],
            sender: sender_id,
            receiver: receiver_id,
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk,
            amount: 100,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        op.signature = sign_op(&sender_sk, |b| op.encode_signed_scope(b));
        assert_eq!(
            validate_transfer_activation(&op, &state, 1_000, 20_160),
            Ok(())
        );
    }

    #[test]
    fn validate_transfer_activation_rejects_existing_receiver() {
        let (sender_pk, _) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let (receiver_pk, _) = keypair();
        let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());
        let mut state = AccountTable::new();
        state.insert(make_account_record(
            sender_pk.as_bytes(),
            MLDSA_SUITE,
            1_000,
            [0u8; 32],
        ));
        state.insert(make_account_record(
            receiver_pk.as_bytes(),
            MLDSA_SUITE,
            0,
            [0u8; 32],
        ));
        let op = TransferActivation {
            prev_hash: [0u8; 32],
            sender: sender_id,
            receiver: receiver_id,
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk,
            amount: 100,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        assert_eq!(
            validate_transfer_activation(&op, &state, 1_000, 20_160),
            Err(OpError::ReceiverAlreadyExists)
        );
    }

    #[test]
    fn validate_transfer_activation_rejects_bad_binding() {
        let (sender_pk, _) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let (receiver_pk, _) = keypair();
        let mut state = AccountTable::new();
        state.insert(make_account_record(
            sender_pk.as_bytes(),
            MLDSA_SUITE,
            1_000,
            [0u8; 32],
        ));
        let op = TransferActivation {
            prev_hash: [0u8; 32],
            sender: sender_id,
            receiver: [0xAAu8; 32], // not SHA-256 of receiver_pubkey
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk,
            amount: 100,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        assert_eq!(
            validate_transfer_activation(&op, &state, 1_000, 20_160),
            Err(OpError::InvalidBinding)
        );
    }

    #[test]
    fn validate_transfer_activation_rejects_cooldown_not_elapsed() {
        let (sender_pk, _) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let mut sender_rec =
            make_account_record(sender_pk.as_bytes(), MLDSA_SUITE, 1_000, [0u8; 32]);
        // sender already activated someone in window 500; cooldown τ₂ = 20_160.
        sender_rec.last_activation_window = 500;
        let mut state = AccountTable::new();
        state.insert(sender_rec);
        let (receiver_pk, _) = keypair();
        let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());
        let op = TransferActivation {
            prev_hash: [0u8; 32],
            sender: sender_id,
            receiver: receiver_id,
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk,
            amount: 100,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        // current_window = 1000; 1000 < 500 + 20_160 → reject
        assert_eq!(
            validate_transfer_activation(&op, &state, 1_000, 20_160),
            Err(OpError::ActivationCooldownNotElapsed)
        );
    }

    // ---- Transfer ----

    struct TransferFixture {
        sender_sk: SecretKey,
        state: AccountTable,
        sender_id: AccountId,
        receiver_id: AccountId,
        frontier: Hash32,
    }

    fn setup_transfer() -> TransferFixture {
        let (sender_pk, sender_sk) = keypair();
        let (receiver_pk, _) = keypair();
        let frontier = [0x77u8; 32];
        let sender_record =
            make_account_record(sender_pk.as_bytes(), MLDSA_SUITE, 1_000_000, frontier);
        let receiver_record =
            make_account_record(receiver_pk.as_bytes(), MLDSA_SUITE, 0, [0u8; 32]);
        let sender_id = sender_record.account_id;
        let receiver_id = receiver_record.account_id;
        let mut state = AccountTable::new();
        state.insert(sender_record);
        state.insert(receiver_record);
        TransferFixture {
            sender_sk,
            state,
            sender_id,
            receiver_id,
            frontier,
        }
    }

    fn signed_transfer(fx: &TransferFixture, amount: u128) -> Transfer {
        let mut op = Transfer {
            prev_hash: fx.frontier,
            sender: fx.sender_id,
            link: fx.receiver_id,
            amount,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        op.signature = sign_op(&fx.sender_sk, |b| op.encode_signed_scope(b));
        op
    }

    #[test]
    fn validate_transfer_happy() {
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 100);
        assert_eq!(validate_transfer(&op, &fx.state), Ok(()));
    }

    #[test]
    fn validate_transfer_rejects_missing_sender() {
        let fx = setup_transfer();
        let mut op = signed_transfer(&fx, 100);
        op.sender = [0xEEu8; 32];
        assert_eq!(
            validate_transfer(&op, &fx.state),
            Err(OpError::AccountNotFound)
        );
    }

    #[test]
    fn validate_transfer_rejects_wrong_prev_hash() {
        let fx = setup_transfer();
        let mut op = signed_transfer(&fx, 100);
        op.prev_hash = [0x11u8; 32];
        assert_eq!(
            validate_transfer(&op, &fx.state),
            Err(OpError::InvalidPrevHash)
        );
    }

    #[test]
    fn validate_transfer_rejects_self_transfer() {
        let fx = setup_transfer();
        let mut op = signed_transfer(&fx, 100);
        op.link = op.sender;
        assert_eq!(
            validate_transfer(&op, &fx.state),
            Err(OpError::SelfTransfer)
        );
    }

    #[test]
    fn validate_transfer_rejects_zero_amount() {
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 0);
        assert_eq!(validate_transfer(&op, &fx.state), Err(OpError::ZeroAmount));
    }

    #[test]
    fn validate_transfer_rejects_insufficient_balance() {
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 10_000_000);
        assert_eq!(
            validate_transfer(&op, &fx.state),
            Err(OpError::InsufficientBalance)
        );
    }

    #[test]
    fn validate_transfer_rejects_missing_receiver() {
        // spec v30.x: Transfer rejects ReceiverNotActive if receiver ∉ AccountTable
        // (new accounts are created only via TransferActivation)
        let fx = setup_transfer();
        let mut op = signed_transfer(&fx, 100);
        op.link = [0xFFu8; 32];
        assert_eq!(
            validate_transfer(&op, &fx.state),
            Err(OpError::ReceiverNotActive)
        );
    }

    #[test]
    fn validate_transfer_rejects_bad_signature() {
        let fx = setup_transfer();
        let mut op = signed_transfer(&fx, 100);
        op.signature = Signature::from_array([0u8; SIGNATURE_SIZE]);
        assert_eq!(
            validate_transfer(&op, &fx.state),
            Err(OpError::InvalidSignature)
        );
    }

    // ---- ChangeKey ----

    #[test]
    fn validate_change_key_happy() {
        let (old_pk, old_sk) = keypair();
        let (new_pk, _) = keypair();
        let frontier = [0x33u8; 32];
        let record = make_account_record(old_pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);

        let mut op = ChangeKey {
            prev_hash: frontier,
            sender: sender_id,
            new_suite_id: MLDSA_SUITE,
            new_pubkey: new_pk,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        op.signature = sign_op(&old_sk, |b| op.encode_signed_scope(b));
        assert_eq!(validate_change_key(&op, &state), Ok(()));
    }

    #[test]
    fn validate_change_key_rejects_missing_sender() {
        let (new_pk, _) = keypair();
        let op = ChangeKey {
            prev_hash: [0u8; 32],
            sender: [0xABu8; 32],
            new_suite_id: MLDSA_SUITE,
            new_pubkey: new_pk,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let state = AccountTable::new();
        assert_eq!(
            validate_change_key(&op, &state),
            Err(OpError::AccountNotFound)
        );
    }

    #[test]
    fn validate_change_key_rejects_wrong_prev_hash() {
        let (old_pk, _) = keypair();
        let (new_pk, _) = keypair();
        let frontier = [0x33u8; 32];
        let record = make_account_record(old_pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);

        let op = ChangeKey {
            prev_hash: [0x22u8; 32], // != frontier
            sender: sender_id,
            new_suite_id: MLDSA_SUITE,
            new_pubkey: new_pk,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        assert_eq!(
            validate_change_key(&op, &state),
            Err(OpError::InvalidPrevHash)
        );
    }

    #[test]
    fn validate_change_key_rejects_unsupported_new_suite() {
        let (old_pk, old_sk) = keypair();
        let (new_pk, _) = keypair();
        let frontier = [0x33u8; 32];
        let record = make_account_record(old_pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);

        let mut op = ChangeKey {
            prev_hash: frontier,
            sender: sender_id,
            new_suite_id: 0xDEAD,
            new_pubkey: new_pk,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        op.signature = sign_op(&old_sk, |b| op.encode_signed_scope(b));
        assert_eq!(
            validate_change_key(&op, &state),
            Err(OpError::UnsupportedSuite)
        );
    }

    #[test]
    fn validate_change_key_rejects_signature_by_new_key_not_old() {
        // SSI R1: ChangeKey must be signed by the OLD key; a signature by the new one is invalid
        let (old_pk, _old_sk) = keypair();
        let (new_pk, new_sk) = keypair();
        let frontier = [0x33u8; 32];
        let record = make_account_record(old_pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);

        let mut op = ChangeKey {
            prev_hash: frontier,
            sender: sender_id,
            new_suite_id: MLDSA_SUITE,
            new_pubkey: new_pk,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        // sign with the NEW key — must fail
        op.signature = sign_op(&new_sk, |b| op.encode_signed_scope(b));
        assert_eq!(
            validate_change_key(&op, &state),
            Err(OpError::InvalidSignature)
        );
    }

    // ---- Anchor ----

    #[test]
    fn validate_anchor_happy() {
        let (pk, sk) = keypair();
        let frontier = [0x44u8; 32];
        let record = make_account_record(pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);

        let mut op = Anchor {
            prev_hash: frontier,
            sender: sender_id,
            app_id: [0x88u8; 32],
            data_hash: [0x99u8; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        op.signature = sign_op(&sk, |b| op.encode_signed_scope(b));
        assert_eq!(validate_anchor(&op, &state), Ok(()));
    }

    #[test]
    fn validate_anchor_rejects_missing_sender() {
        let op = Anchor {
            prev_hash: [0u8; 32],
            sender: [0xCDu8; 32],
            app_id: [0x88u8; 32],
            data_hash: [0x99u8; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let state = AccountTable::new();
        assert_eq!(validate_anchor(&op, &state), Err(OpError::AccountNotFound));
    }

    #[test]
    fn validate_anchor_rejects_wrong_prev_hash() {
        let (pk, _sk) = keypair();
        let record = make_account_record(pk.as_bytes(), MLDSA_SUITE, 0, [0x44u8; 32]);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);
        let op = Anchor {
            prev_hash: [0x00u8; 32],
            sender: sender_id,
            app_id: [0x88u8; 32],
            data_hash: [0x99u8; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        assert_eq!(validate_anchor(&op, &state), Err(OpError::InvalidPrevHash));
    }

    #[test]
    fn validate_anchor_rejects_bad_signature() {
        let (pk, _sk) = keypair();
        let frontier = [0x44u8; 32];
        let record = make_account_record(pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);

        let op = Anchor {
            prev_hash: frontier,
            sender: sender_id,
            app_id: [0x88u8; 32],
            data_hash: [0x99u8; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        assert_eq!(validate_anchor(&op, &state), Err(OpError::InvalidSignature));
    }

    // ---- dispatcher ----

    #[test]
    fn validate_dispatcher_delegates() {
        let fx = setup_transfer();
        let op = Operation::Transfer(signed_transfer(&fx, 100));
        let ctx = ValidationContext {
            current_window: 0,
            tau2_windows: 1,
        };
        assert_eq!(validate(&op, &fx.state, &ctx), Ok(()));
    }

    #[test]
    fn validate_dispatcher_enforces_cooldown_for_transfer_activation() {
        // Anti-regression M3-A-4: generic validate(op, state, ctx) for
        // TransferActivation must NOT silently bypass the cooldown. If the sender
        // has activated recently — the generic dispatcher must return
        // ActivationCooldownNotElapsed with a production-like context.
        let (sender_pk, sender_sk) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let (receiver_pk, _) = keypair();
        let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());

        // sender activated in window 100; tau2 = 1000; current = 500
        // → 500 < 100 + 1000 = 1100 → cooldown is active.
        let mut state = AccountTable::new();
        state.insert(AccountRecord {
            account_id: sender_id,
            balance: 1000,
            suite_id: MLDSA_SUITE,
            is_node_operator: false,
            frontier_hash: [9u8; 32],
            op_height: 5,
            account_chain_length: 5,
            account_chain_length_snapshot: 5,
            current_pubkey: *sender_pk.as_bytes(),
            creation_window: 0,
            last_op_window: 100,
            last_activation_window: 100,
        });

        let mut activation = TransferActivation {
            prev_hash: [9u8; 32],
            sender: sender_id,
            receiver: receiver_id,
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk.clone(),
            amount: 50,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        activation.encode_signed_scope(&mut scope);
        activation.signature = mt_crypto::sign(&sender_sk, &scope).unwrap();

        let op = Operation::TransferActivation(activation);
        let ctx = ValidationContext {
            current_window: 500,
            tau2_windows: 1000,
        };
        assert_eq!(
            validate(&op, &state, &ctx),
            Err(OpError::ActivationCooldownNotElapsed)
        );
    }

    // ================== Phase C: apply ==================

    const TEST_WINDOW: u64 = 42;
    const TEST_WINDOW_U32: u32 = 42; // for assertions against AccountRecord fields (u32)

    #[test]
    fn apply_transfer_activation_creates_receiver_record() {
        let (sender_pk, _) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let (receiver_pk, _) = keypair();
        let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());
        let mut state = AccountTable::new();
        state.insert(make_account_record(
            sender_pk.as_bytes(),
            MLDSA_SUITE,
            1_000_000,
            [0u8; 32],
        ));

        let op = TransferActivation {
            prev_hash: [0u8; 32],
            sender: sender_id,
            receiver: receiver_id,
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk.clone(),
            amount: 100_000,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        apply_transfer_activation(&op, &mut state, TEST_WINDOW);

        let receiver = state.get(&receiver_id).expect("receiver must exist");
        assert_eq!(receiver.balance, 100_000);
        assert_eq!(receiver.suite_id, MLDSA_SUITE);
        assert_eq!(receiver.current_pubkey, *receiver_pk.as_bytes());
        assert_eq!(receiver.frontier_hash, [0u8; 32]);
        assert_eq!(receiver.last_activation_window, 0);
    }

    #[test]
    fn apply_transfer_activation_updates_sender_cooldown() {
        let (sender_pk, _) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let (receiver_pk, _) = keypair();
        let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());
        let mut state = AccountTable::new();
        state.insert(make_account_record(
            sender_pk.as_bytes(),
            MLDSA_SUITE,
            1_000_000,
            [0u8; 32],
        ));

        let op = TransferActivation {
            prev_hash: [0u8; 32],
            sender: sender_id,
            receiver: receiver_id,
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk,
            amount: 42,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        apply_transfer_activation(&op, &mut state, TEST_WINDOW);

        let sender = state.get(&sender_id).unwrap();
        assert_eq!(sender.last_activation_window, TEST_WINDOW_U32);
        assert_eq!(sender.balance, 1_000_000 - 42);
    }

    #[test]
    fn apply_transfer_debits_sender_credits_receiver() {
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 250);
        let sender_before = fx.state.get(&fx.sender_id).unwrap().balance;
        let receiver_before = fx.state.get(&fx.receiver_id).unwrap().balance;

        let mut state = fx.state;
        apply_transfer(&op, &mut state, TEST_WINDOW);

        let sender_after = state.get(&fx.sender_id).unwrap().balance;
        let receiver_after = state.get(&fx.receiver_id).unwrap().balance;
        assert_eq!(sender_after, sender_before - 250);
        assert_eq!(receiver_after, receiver_before + 250);
    }

    #[test]
    fn apply_transfer_sum_delta_balance_is_zero() {
        // spec: Anti-inflation — Σ delta_balance == 0 for Transfer
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 777);
        let sender_before = fx.state.get(&fx.sender_id).unwrap().balance;
        let receiver_before = fx.state.get(&fx.receiver_id).unwrap().balance;

        let mut state = fx.state;
        apply_transfer(&op, &mut state, TEST_WINDOW);

        let sender_after = state.get(&fx.sender_id).unwrap().balance;
        let receiver_after = state.get(&fx.receiver_id).unwrap().balance;
        let delta_sender = sender_after as i128 - sender_before as i128;
        let delta_receiver = receiver_after as i128 - receiver_before as i128;
        assert_eq!(delta_sender + delta_receiver, 0);
    }

    #[test]
    fn apply_transfer_updates_sender_frontier_and_chain_length() {
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 100);
        let expected_frontier = op_hash(&Operation::Transfer(op.clone()));
        let sender_chain_before = fx.state.get(&fx.sender_id).unwrap().account_chain_length;

        let mut state = fx.state;
        apply_transfer(&op, &mut state, TEST_WINDOW);

        let sender = state.get(&fx.sender_id).unwrap();
        assert_eq!(sender.frontier_hash, expected_frontier);
        assert_eq!(sender.account_chain_length, sender_chain_before + 1);
        assert_eq!(sender.last_op_window, TEST_WINDOW_U32);
    }

    #[test]
    fn apply_transfer_receiver_frontier_and_chain_length_unchanged() {
        // spec dep rule: a Transfer receiver gets no chain_length++ and no frontier update
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 100);
        let receiver_before = fx.state.get(&fx.receiver_id).unwrap().clone();

        let mut state = fx.state;
        apply_transfer(&op, &mut state, TEST_WINDOW);

        let receiver_after = state.get(&fx.receiver_id).unwrap();
        assert_eq!(receiver_after.frontier_hash, receiver_before.frontier_hash);
        assert_eq!(
            receiver_after.account_chain_length,
            receiver_before.account_chain_length
        );
        assert_eq!(
            receiver_after.last_op_window,
            receiver_before.last_op_window
        );
        assert_eq!(receiver_after.op_height, receiver_before.op_height);
    }

    #[test]
    fn apply_change_key_updates_pubkey_and_suite_id() {
        let (old_pk, _old_sk) = keypair();
        let (new_pk, _new_sk) = keypair();
        let frontier = [0x33u8; 32];
        let record = make_account_record(old_pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record);

        let op = ChangeKey {
            prev_hash: frontier,
            sender: sender_id,
            new_suite_id: MLDSA_SUITE, // only one suite for now, but the field is updated
            new_pubkey: new_pk.clone(),
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        apply_change_key(&op, &mut state, TEST_WINDOW);

        let sender = state.get(&sender_id).unwrap();
        assert_eq!(sender.current_pubkey, *new_pk.as_bytes());
        assert_eq!(sender.suite_id, MLDSA_SUITE);
    }

    #[test]
    fn apply_change_key_updates_frontier_and_chain_length() {
        let (old_pk, _) = keypair();
        let (new_pk, _) = keypair();
        let frontier = [0x33u8; 32];
        let record = make_account_record(old_pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let chain_before = record.account_chain_length;
        let mut state = AccountTable::new();
        state.insert(record);

        let op = ChangeKey {
            prev_hash: frontier,
            sender: sender_id,
            new_suite_id: MLDSA_SUITE,
            new_pubkey: new_pk,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let expected_frontier = op_hash(&Operation::ChangeKey(op.clone()));
        apply_change_key(&op, &mut state, TEST_WINDOW);

        let sender = state.get(&sender_id).unwrap();
        assert_eq!(sender.frontier_hash, expected_frontier);
        assert_eq!(sender.account_chain_length, chain_before + 1);
        assert_eq!(sender.last_op_window, TEST_WINDOW_U32);
    }

    #[test]
    fn apply_anchor_updates_frontier_only_balance_unchanged() {
        let (pk, _) = keypair();
        let initial_balance = 500_000u128;
        let frontier = [0x44u8; 32];
        let record = make_account_record(pk.as_bytes(), MLDSA_SUITE, initial_balance, frontier);
        let sender_id = record.account_id;
        let chain_before = record.account_chain_length;
        let mut state = AccountTable::new();
        state.insert(record);

        let op = Anchor {
            prev_hash: frontier,
            sender: sender_id,
            app_id: [0x88u8; 32],
            data_hash: [0x99u8; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let expected_frontier = op_hash(&Operation::Anchor(op.clone()));
        apply_anchor(&op, &mut state, TEST_WINDOW);

        let sender = state.get(&sender_id).unwrap();
        assert_eq!(sender.balance, initial_balance); // balance UNCHANGED
        assert_eq!(sender.frontier_hash, expected_frontier);
        assert_eq!(sender.account_chain_length, chain_before + 1);
        assert_eq!(sender.last_op_window, TEST_WINDOW_U32);
    }

    #[test]
    fn apply_anchor_does_not_store_data_hash() {
        // spec: data_hash lives in the proposal chain, not in AccountTable
        // ⇒ applying an Anchor creates no new fields in the record,
        // data_hash is not reflected in state at all (only frontier changes via op_hash)
        let (pk, _) = keypair();
        let frontier = [0x44u8; 32];
        let record = make_account_record(pk.as_bytes(), MLDSA_SUITE, 0, frontier);
        let sender_id = record.account_id;
        let mut state = AccountTable::new();
        state.insert(record.clone());

        let op = Anchor {
            prev_hash: frontier,
            sender: sender_id,
            app_id: [0x88u8; 32],
            data_hash: [0x99u8; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        apply_anchor(&op, &mut state, TEST_WINDOW);

        // All fields except frontier/chain_length/op_height/last_op_window are identical
        let after = state.get(&sender_id).unwrap();
        assert_eq!(after.balance, record.balance);
        assert_eq!(after.current_pubkey, record.current_pubkey);
        assert_eq!(after.suite_id, record.suite_id);
        assert_eq!(after.creation_window, record.creation_window);
        assert_eq!(after.account_id, record.account_id);
    }

    #[test]
    fn apply_dispatcher_delegates_transfer() {
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 100);
        let mut via_direct = fx.state.clone();
        apply_transfer(&op, &mut via_direct, TEST_WINDOW);

        let mut via_dispatch = fx.state;
        apply(&Operation::Transfer(op), &mut via_dispatch, TEST_WINDOW);
        assert_eq!(via_direct.root(), via_dispatch.root());
    }

    #[test]
    fn apply_transfer_activation_sender_op_height_increments() {
        let (sender_pk, _) = keypair();
        let sender_id = derive_account_id(MLDSA_SUITE, sender_pk.as_bytes());
        let (receiver_pk, _) = keypair();
        let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());
        let mut state = AccountTable::new();
        let mut sender_rec =
            make_account_record(sender_pk.as_bytes(), MLDSA_SUITE, 1_000_000, [0u8; 32]);
        sender_rec.op_height = 5;
        state.insert(sender_rec);

        let op = TransferActivation {
            prev_hash: [0u8; 32],
            sender: sender_id,
            receiver: receiver_id,
            suite_id: MLDSA_SUITE,
            receiver_pubkey: receiver_pk,
            amount: 100,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        apply_transfer_activation(&op, &mut state, TEST_WINDOW);

        let sender = state.get(&sender_id).unwrap();
        assert_eq!(sender.op_height, 6);
    }

    #[test]
    fn apply_state_root_changes_on_transfer() {
        // State root deterministic — after apply_transfer the root changed
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 100);
        let root_before = fx.state.root();

        let mut state = fx.state;
        apply_transfer(&op, &mut state, TEST_WINDOW);
        let root_after = state.root();

        assert_ne!(root_before, root_after);
    }

    #[test]
    fn apply_transfer_op_height_increments_on_sender_only() {
        let fx = setup_transfer();
        let op = signed_transfer(&fx, 100);
        let sender_op_height_before = fx.state.get(&fx.sender_id).unwrap().op_height;
        let receiver_op_height_before = fx.state.get(&fx.receiver_id).unwrap().op_height;

        let mut state = fx.state;
        apply_transfer(&op, &mut state, TEST_WINDOW);

        assert_eq!(
            state.get(&fx.sender_id).unwrap().op_height,
            sender_op_height_before + 1
        );
        assert_eq!(
            state.get(&fx.receiver_id).unwrap().op_height,
            receiver_op_height_before // UNCHANGED per dep rule
        );
    }

    // ================== Phase D: emission (const EMISSION_moneta = 13 Ɉ) ==================

    const EMISSION: u128 = 13_000_000_000;

    #[test]
    fn reward_moneta_is_const() {
        let p = mt_genesis::genesis_params();
        assert_eq!(reward_moneta(p), EMISSION);
    }

    #[test]
    fn reward_moneta_independent_of_window() {
        let p = mt_genesis::genesis_params();
        let r0 = reward_moneta(p);
        let r1 = reward_moneta(p);
        assert_eq!(r0, r1);
        assert_eq!(r0, EMISSION);
    }

    #[test]
    fn supply_moneta_window_zero() {
        let p = mt_genesis::genesis_params();
        assert_eq!(supply_moneta(0, p), 0);
    }

    #[test]
    fn supply_moneta_grows_linearly() {
        let p = mt_genesis::genesis_params();
        assert_eq!(supply_moneta(0, p), 0);
        assert_eq!(supply_moneta(1, p), EMISSION);
        assert_eq!(supply_moneta(100, p), EMISSION * 100);
        assert_eq!(supply_moneta(1_000_000, p), EMISSION * 1_000_000);
    }

    #[test]
    fn supply_moneta_closed_form_matches_per_window_sum() {
        let p = mt_genesis::genesis_params();
        for &w in &[0u64, 1, 10, 100, 1000, 524_160] {
            let mut expected: u128 = 0;
            for _ in 1..=w {
                expected += reward_moneta(p);
            }
            assert_eq!(supply_moneta(w, p), expected, "mismatch at W={w}");
        }
    }

    // ================== Phase E: apply_proposal ==================

    fn make_node_record(node_id_byte: u8, operator: AccountId) -> NodeRecord {
        NodeRecord {
            node_id: [node_id_byte; 32],
            node_pubkey: [0u8; PUBLIC_KEY_SIZE],
            suite_id: MLDSA_SUITE,
            operator_account_id: operator,
            start_window: 0,
            chain_length: 100,
            chain_length_snapshot: 0,
            chain_length_checkpoints: [50, 60, 70, 80, 90, 100],
            last_confirmation_window: 0,
        }
    }

    #[test]
    fn settle_window_sorts_by_op_hash_lex_asc() {
        // Three TransferActivations with different receiver_pubkey → different op_hash.
        // settle_window must sort ops by op_hash and apply deterministically.
        let fx = setup_transfer();
        let mut state1 = fx.state.clone();
        let mut state2 = fx.state.clone();

        let ops: Vec<Operation> = (0..3)
            .map(|i| {
                let (receiver_pk, _) = keypair();
                let receiver_id = derive_account_id(MLDSA_SUITE, receiver_pk.as_bytes());
                Operation::TransferActivation(TransferActivation {
                    prev_hash: fx.state.get(&fx.sender_id).unwrap().frontier_hash,
                    sender: fx.sender_id,
                    receiver: receiver_id,
                    suite_id: MLDSA_SUITE,
                    receiver_pubkey: receiver_pk,
                    amount: 1,
                    signature: Signature::from_array([i; SIGNATURE_SIZE]),
                })
            })
            .collect();

        let reversed: Vec<Operation> = ops.iter().rev().cloned().collect();
        settle_window(&mut state1, &ops, 10);
        settle_window(&mut state2, &reversed, 10);
        assert_eq!(state1.root(), state2.root());
    }

    #[test]
    fn settle_window_empty_ops_no_change() {
        let fx = setup_transfer();
        let root_before = fx.state.root();
        let mut state = fx.state;
        settle_window(&mut state, &[], 10);
        assert_eq!(state.root(), root_before);
    }

    // spec Sovereignty Ladder: apply_proposal_emission_credits_account_winner removed
    // as obsolete. The lottery is single-class, the winner is always a node;
    // an account cannot be winner_id directly.

    #[test]
    fn apply_proposal_emission_credits_node_operator() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();
        let operator = fx.receiver_id;
        let node = make_node_record(0xAA, operator);
        let node_id = node.node_id;
        node_table.insert(node);
        let balance_before = account_table.get(&operator).unwrap().balance;

        let input = ProposalSettle {
            window_w: 10,
            winner_id: node_id,
            cemented_confirmers: vec![],
        };
        let p = mt_genesis::genesis_params();
        let _root = apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );

        // reward = const EMISSION_moneta = 13 Ɉ.
        let expected_reward = reward_moneta(p);
        assert_eq!(
            account_table.get(&operator).unwrap().balance,
            balance_before + expected_reward
        );
    }

    #[test]
    fn apply_proposal_emission_no_op_at_window_zero() {
        let fx = setup_transfer();
        let mut account_table = fx.state.clone();
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();
        let balance_before = account_table.get(&fx.receiver_id).unwrap().balance;

        // W=0: apply_emission early-returns before lookup; the winner_id value does not matter
        let input = ProposalSettle {
            window_w: 0,
            winner_id: [0u8; 32],
            cemented_confirmers: vec![],
        };
        let p = mt_genesis::genesis_params();
        apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );
        // W=0: no W-1, emission skipped
        assert_eq!(
            account_table.get(&fx.receiver_id).unwrap().balance,
            balance_before
        );
    }

    #[test]
    fn apply_proposal_chain_length_increment() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();

        let node_a = make_node_record(0x01, fx.sender_id);
        let node_b = make_node_record(0x02, fx.sender_id);
        let id_a = node_a.node_id;
        let id_b = node_b.node_id;
        let chain_before_a = node_a.chain_length;
        let chain_before_b = node_b.chain_length;
        node_table.insert(node_a);
        node_table.insert(node_b);

        let input = ProposalSettle {
            window_w: 15,
            winner_id: id_a,
            cemented_confirmers: vec![id_a, id_b],
        };
        let p = mt_genesis::genesis_params();
        apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );

        let after_a = node_table.get(&id_a).unwrap();
        let after_b = node_table.get(&id_b).unwrap();
        assert_eq!(after_a.chain_length, chain_before_a + 1);
        assert_eq!(after_a.last_confirmation_window, 15);
        assert_eq!(after_b.chain_length, chain_before_b + 1);
        assert_eq!(after_b.last_confirmation_window, 15);
    }

    #[test]
    fn apply_proposal_chain_length_ignores_unknown_confirmer() {
        // Node id not in NodeTable — ignored (protocol bug protection)
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();
        let node = make_node_record(0x99, fx.sender_id);
        let node_id = node.node_id;
        node_table.insert(node);

        let input = ProposalSettle {
            window_w: 5,
            winner_id: node_id,
            cemented_confirmers: vec![[0xFFu8; 32]], // unknown
        };
        let p = mt_genesis::genesis_params();
        apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );
        // No panic, node_table holds only the one inserted node (unknown confirmer ignored)
        assert_eq!(node_table.len(), 1);
    }

    #[test]
    fn apply_proposal_checkpoint_rotation_on_tau2_boundary() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();

        let mut node = make_node_record(0x11, fx.sender_id);
        node.chain_length = 150;
        node.chain_length_checkpoints = [50, 60, 70, 80, 90, 100];
        let node_id = node.node_id;
        node_table.insert(node);

        let p = mt_genesis::genesis_params();
        let input = ProposalSettle {
            window_w: p.tau2_windows, // τ₂ boundary
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

        let rotated = node_table.get(&node_id).unwrap();
        // Shift: [50,60,70,80,90,100] → [60,70,80,90,100,150]
        assert_eq!(rotated.chain_length_checkpoints, [60, 70, 80, 90, 100, 150]);
        // snapshot = chain_length - oldest (after rotation) = 150 - 60 = 90
        assert_eq!(rotated.chain_length_snapshot, 90);
    }

    #[test]
    fn apply_proposal_checkpoint_rotation_no_op_off_boundary() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();

        let node = make_node_record(0x11, fx.sender_id);
        let node_id = node.node_id;
        let checkpoints_before = node.chain_length_checkpoints;
        node_table.insert(node);

        let p = mt_genesis::genesis_params();
        let input = ProposalSettle {
            window_w: p.tau2_windows + 1, // NOT a boundary
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

        let after = node_table.get(&node_id).unwrap();
        assert_eq!(after.chain_length_checkpoints, checkpoints_before);
    }

    #[test]
    fn apply_proposal_checkpoint_rotation_skipped_at_window_zero() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();
        let node = make_node_record(0x22, fx.sender_id);
        let node_id = node.node_id;
        let before = node.chain_length_checkpoints;
        node_table.insert(node);

        let p = mt_genesis::genesis_params();
        // W=0: apply_emission early-returns; the winner_id value does not matter
        let input = ProposalSettle {
            window_w: 0,
            winner_id: [0u8; 32],
            cemented_confirmers: vec![],
        };
        apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );

        let after = node_table.get(&node_id).unwrap();
        assert_eq!(after.chain_length_checkpoints, before);
    }

    #[test]
    fn apply_proposal_state_root_deterministic() {
        let fx = setup_transfer();
        let p = mt_genesis::genesis_params();

        let run = |initial_state: AccountTable| -> Hash32 {
            let mut acc = initial_state;
            let mut nodes = NodeTable::new();
            let candidates = CandidatePool::new();
            let node = make_node_record(0x33, fx.sender_id);
            let node_id = node.node_id;
            nodes.insert(node);
            let input = ProposalSettle {
                window_w: 20,
                winner_id: node_id,
                cemented_confirmers: vec![node_id],
            };
            apply_proposal(&mut acc, &mut nodes, &candidates, &input, p)
        };

        let r1 = run(fx.state.clone());
        let r2 = run(fx.state);
        assert_eq!(r1, r2);
    }

    #[test]
    fn apply_proposal_state_root_matches_manual_composition() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();
        let p = mt_genesis::genesis_params();
        let node = make_node_record(0x77, fx.sender_id);
        let node_id = node.node_id;
        node_table.insert(node);

        let input = ProposalSettle {
            window_w: 7,
            winner_id: node_id,
            cemented_confirmers: vec![],
        };
        let returned_root = apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );

        let manual = compute_state_root(
            &node_table.root(),
            &candidate_pool.root(),
            &account_table.root(),
        );
        assert_eq!(returned_root, manual);
    }

    #[test]
    fn apply_proposal_emission_changes_state_root() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();
        let p = mt_genesis::genesis_params();
        let node = make_node_record(0x88, fx.sender_id);
        let node_id = node.node_id;
        node_table.insert(node);

        let root_before = compute_state_root(
            &node_table.root(),
            &candidate_pool.root(),
            &account_table.root(),
        );

        let input = ProposalSettle {
            window_w: 3,
            winner_id: node_id,
            cemented_confirmers: vec![],
        };
        let root_after = apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );

        assert_ne!(root_before, root_after);
    }

    #[test]
    fn apply_proposal_only_cemented_confirmers_updated() {
        // A node NOT in the confirmers list gets no chain_length++
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();

        let a = make_node_record(0x01, fx.sender_id);
        let b = make_node_record(0x02, fx.sender_id);
        let id_a = a.node_id;
        let id_b = b.node_id;
        let chain_b_before = b.chain_length;
        node_table.insert(a);
        node_table.insert(b);

        let input = ProposalSettle {
            window_w: 5,
            winner_id: id_a,
            cemented_confirmers: vec![id_a], // only A, not B
        };
        let p = mt_genesis::genesis_params();
        apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );

        assert_eq!(
            node_table.get(&id_b).unwrap().chain_length,
            chain_b_before // did NOT change
        );
    }

    #[test]
    fn proposal_settle_struct_fields_accessible() {
        // Sanity check — struct is public + all fields are public
        let s = ProposalSettle {
            window_w: 42,
            winner_id: [0xAB; 32],
            cemented_confirmers: vec![[0x01; 32]],
        };
        assert_eq!(s.window_w, 42);
    }

    // Anti-regression M3-A-1: apply_chain_length_increment use checked_add
    // (consistency with other apply_*). u64::MAX overflow → descriptive panic.
    #[test]
    #[should_panic(expected = "apply_chain_length_increment: chain_length overflow at u64::MAX")]
    fn apply_chain_length_panics_on_overflow() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();

        let mut node = make_node_record(0x11, fx.sender_id);
        node.chain_length = u64::MAX; // protocol invariant breach trigger
        let node_id = node.node_id;
        node_table.insert(node);

        let input = ProposalSettle {
            window_w: 5,
            winner_id: node_id,
            cemented_confirmers: vec![node_id],
        };
        let p = mt_genesis::genesis_params();
        apply_proposal(
            &mut account_table,
            &mut node_table,
            &candidate_pool,
            &input,
            p,
        );
    }

    // Anti-regression M3-A-2: apply_checkpoint_rotation use checked_sub
    // (defense-in-depth). Corrupted state checkpoints[0] > chain_length →
    // descriptive panic, not a silent u64 wrap to a huge chain_length_snapshot.
    #[test]
    #[should_panic(expected = "apply_checkpoint_rotation: invariant breach")]
    fn apply_checkpoint_rotation_panics_on_underflow() {
        let fx = setup_transfer();
        let mut account_table = fx.state;
        let mut node_table = NodeTable::new();
        let candidate_pool = CandidatePool::new();

        let mut node = make_node_record(0x11, fx.sender_id);
        node.chain_length = 100;
        // After rotation [80,90,100,110,120,130] → checkpoints[0] = 90 (the old
        // index 1). Is that > chain_length=100? No, 90<100. It must be so that the
        // old index 1 > chain_length: set [_, 200, _, _, _, _].
        node.chain_length_checkpoints = [50, 200, 70, 80, 90, 100];
        let node_id = node.node_id;
        node_table.insert(node);

        let p = mt_genesis::genesis_params();
        let input = ProposalSettle {
            window_w: p.tau2_windows, // τ₂ boundary triggers rotation
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
    }

    // ================== Phase F: Genesis state ==================

    #[test]
    fn genesis_state_is_empty() {
        // spec: Genesis = empty window 0. No baked bootstrap operator, no N_SEED
        // cohort: all three consensus tables are empty.
        let p = mt_genesis::genesis_params();
        let g = build_genesis_state(p);
        assert_eq!(g.account_table.len(), 0);
        assert_eq!(g.node_table.len(), 0);
        assert_eq!(g.candidate_pool.len(), 0);
    }

    #[test]
    fn genesis_account_node_candidate_roots_are_empty_internal_256() {
        // spec, "Entry and registration → Genesis State":
        //   genesis_account_root = genesis_node_root = genesis_candidate_root
        //   = empty_internal(256). Empty window 0: all three tables empty, so
        //   each root is the canonical empty sparse-Merkle root at TREE_DEPTH=256.
        let p = mt_genesis::genesis_params();
        let g = build_genesis_state(p);
        let empty = mt_merkle::empty_internal(256);
        assert_eq!(g.account_table.root(), empty);
        assert_eq!(g.node_table.root(), empty);
        assert_eq!(g.candidate_pool.root(), empty);
        // Determinism vs fresh empty tables.
        assert_eq!(g.account_table.root(), AccountTable::new().root());
        assert_eq!(g.node_table.root(), NodeTable::new().root());
        assert_eq!(g.candidate_pool.root(), CandidatePool::new().root());
    }

    #[test]
    fn genesis_supply_zero_no_accounts() {
        // Empty genesis has no accounts, hence zero supply.
        let p = mt_genesis::genesis_params();
        let g = build_genesis_state(p);
        let total: u128 = g.account_table.iter().map(|r| r.balance).sum();
        assert_eq!(total, 0);
        assert_eq!(g.account_table.iter().count(), 0);
    }

    #[test]
    fn build_genesis_state_is_deterministic() {
        let p = mt_genesis::genesis_params();
        let g1 = build_genesis_state(p);
        let g2 = build_genesis_state(p);
        assert_eq!(genesis_state_root(&g1), genesis_state_root(&g2));
        assert_eq!(g1.account_table.root(), g2.account_table.root());
        assert_eq!(g1.node_table.root(), g2.node_table.root());
    }

    #[test]
    fn genesis_state_root_matches_manual_composition() {
        let p = mt_genesis::genesis_params();
        let g = build_genesis_state(p);
        let expected = compute_state_root(
            &g.node_table.root(),
            &g.candidate_pool.root(),
            &g.account_table.root(),
        );
        assert_eq!(genesis_state_root(&g), expected);
    }

    #[test]
    fn genesis_suite_id_is_mldsa_65() {
        // spec: suite_id = 0x0001 (ML-DSA-65)
        assert_eq!(GENESIS_SUITE_ID, 0x0001);
        assert_eq!(GENESIS_SUITE_ID, MLDSA_SUITE);
    }

    #[test]
    fn genesis_supply_is_zero() {
        // spec: "Genesis State (before the first window, supply = 0)"
        let p = mt_genesis::genesis_params();
        let g = build_genesis_state(p);
        let total: u128 = g.account_table.iter().map(|r| r.balance).sum();
        assert_eq!(total, 0);
    }
}
