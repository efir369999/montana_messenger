//! Issue #18, R3 and R4: the order of delivery and incomplete data.
//!
//! A follower at window 4 receives the messages that close window 5: the
//! tickets of window 4 from two nodes and one cemented envelope. The envelope is
//! built by hand from real ML-DSA-65 keys so that every check before the ticket
//! check passes; only the ticket check decides.

use super::*;
use mt_lottery::{Candidate, WINNER_CLASS_NODE};
use mt_state::{AccountRecord, AccountTable, CandidatePool, NodeRecord, NodeTable};
use std::sync::atomic::AtomicU64;

const W: u64 = 5;
const T_R_PREV: Hash32 = [0x41; 32];
const T_R_W: Hash32 = [0x42; 32];

static DIR_SEQ: AtomicU64 = AtomicU64::new(0);

/// The closed window, the state root, the account root and the node root.
type Outcome = (u64, Hash32, Hash32, Hash32);

fn identity(seed: u8) -> crate::identity::Identity {
    crate::identity::Identity::from_master_seed([seed; 64]).expect("identity")
}

fn temp_data_dir(tag: &str) -> PathBuf {
    let n = DIR_SEQ.fetch_add(1, Ordering::SeqCst);
    let name = format!("montana-order-{tag}-{}-{n}", std::process::id());
    let dir = std::env::temp_dir().join(name);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

/// The proposer P and the two ticket holders A and B, with their tables.
struct Fixture {
    p: crate::identity::Identity,
    a: crate::identity::Identity,
    b: crate::identity::Identity,
    follower: crate::identity::Identity,
    nodes: NodeTable,
    accounts: AccountTable,
}

impl Fixture {
    fn new() -> Self {
        let p = identity(0x50);
        let a = identity(0x51);
        let b = identity(0x52);
        let follower = identity(0x53);
        let mut nodes = NodeTable::new();
        let mut accounts = AccountTable::new();
        for id in [&p, &a, &b] {
            nodes.insert(NodeRecord {
                node_id: id.node_id(),
                node_pubkey: *id.node_pk.as_bytes(),
                suite_id: id.suite_id as u16,
                operator_account_id: id.account_id(),
                start_window: 1,
                chain_length: 10,
                chain_length_snapshot: 10,
                chain_length_checkpoints: [0; 6],
                last_confirmation_window: W - 1,
            });
            accounts.insert(AccountRecord {
                account_id: id.account_id(),
                balance: 0,
                suite_id: id.suite_id as u16,
                is_node_operator: true,
                frontier_hash: [0u8; 32],
                op_height: 0,
                account_chain_length: 0,
                account_chain_length_snapshot: 0,
                current_pubkey: *id.account_pk.as_bytes(),
                creation_window: 0,
                last_op_window: 0,
                last_activation_window: 0,
            });
        }
        Fixture {
            p,
            a,
            b,
            follower,
            nodes,
            accounts,
        }
    }

    fn ticket(&self, id: &crate::identity::Identity) -> SshaReveal {
        let cba = cemented_bundle_aggregate(W - 3, &[]);
        let mut r = SshaReveal {
            node_id: id.node_id(),
            window_index: W - 1,
            endpoint: compute_endpoint(&T_R_PREV, &cba, &id.node_id(), W - 1),
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        r.encode_signed_scope(&mut scope);
        r.signature = sign(&id.node_sk, &scope).expect("sign ticket");
        r
    }

    fn confirmation(
        &self,
        id: &crate::identity::Identity,
        window: u64,
        endpoint: Hash32,
        reveal_hashes: Vec<Hash32>,
    ) -> BundledConfirmation {
        let mut bc = BundledConfirmation {
            node_id: id.node_id(),
            endpoint,
            window_index: window,
            op_hashes: Vec::new(),
            reveal_hashes,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        bc.encode_signed_scope(&mut scope);
        bc.signature = sign(&id.node_sk, &scope).expect("sign confirmation");
        bc
    }

    /// The argmin winner of the two tickets and the other one.
    fn winner_and_loser(&self) -> (mt_state::NodeId, mt_state::NodeId) {
        let cands: Vec<Candidate> = [self.ticket(&self.a), self.ticket(&self.b)]
            .iter()
            .map(|r| Candidate {
                ticket: weighted_ticket_node(&r.endpoint, 10, 10),
                class: WINNER_CLASS_NODE,
                id: r.node_id,
            })
            .collect();
        let win = mt_lottery::determine_winner(&cands)
            .expect("two candidates")
            .id;
        let lose = if win == self.a.node_id() {
            self.b.node_id()
        } else {
            self.a.node_id()
        };
        (win, lose)
    }

    /// A cemented envelope of window W naming `winner`, with the state_root
    /// that the settle computes for that winner.
    fn envelope(&self, winner: mt_state::NodeId) -> ProtocolMessage {
        let (ra, rb) = (self.ticket(&self.a), self.ticket(&self.b));
        let mut cemented = vec![reveal_hash(&ra), reveal_hash(&rb)];
        cemented.sort();
        let signers = [&self.p, &self.a, &self.b];
        let bundles_prev: Vec<BundledConfirmation> = signers
            .iter()
            .map(|id| self.confirmation(id, W - 1, T_R_PREV, Vec::new()))
            .collect();
        let evidence: Vec<BundledConfirmation> = signers
            .iter()
            .map(|id| self.confirmation(id, W, T_R_W, cemented.clone()))
            .collect();
        let mut confirmers: Vec<mt_state::NodeId> = signers.iter().map(|i| i.node_id()).collect();
        confirmers.sort();
        let mut accounts = self.accounts.clone();
        let mut nodes = self.nodes.clone();
        let state_root = apply_proposal(
            &mut accounts,
            &mut nodes,
            &CandidatePool::new(),
            &ProposalSettle {
                window_w: W,
                winner_id: winner,
                cemented_confirmers: confirmers,
            },
            genesis_params(),
        );
        let reveal_entries = vec![
            (ra.node_id, reveal_hash(&ra)),
            (rb.node_id, reveal_hash(&rb)),
        ];
        let winner_endpoint = if winner == ra.node_id {
            ra.endpoint
        } else {
            rb.endpoint
        };
        let mut header = ProposalHeader {
            prev_proposal_hash: [0u8; 32],
            window_index: W,
            protocol_version: 1,
            control_root: empty_internal(TREE_DEPTH),
            node_root: nodes.root(),
            candidate_root: CandidatePool::new().root(),
            account_root: accounts.root(),
            state_root,
            timechain_value: T_R_W,
            included_bundles_root: [0u8; 32],
            included_reveals_root: meta_root(&reveal_entries),
            winner_endpoint,
            winner_id: winner,
            proposer_node_id: self.p.node_id(),
            target: u128::MAX,
            fallback_depth: 1,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        header.encode_signed_scope(&mut scope);
        header.signature = sign(&self.p.node_sk, &scope).expect("sign header");
        let mut payload = Vec::new();
        header.encode(&mut payload);
        for list in [&bundles_prev, &evidence] {
            payload.extend_from_slice(&(list.len() as u16).to_le_bytes());
            for bc in list {
                bc.encode(&mut payload);
            }
        }
        ProtocolMessage::new(MsgType::Proposal, W, payload)
    }

    fn ticket_msg(&self, r: &SshaReveal) -> ProtocolMessage {
        let mut payload = Vec::new();
        r.encode(&mut payload);
        ProtocolMessage::new(MsgType::SshaReveal, W - 1, payload)
    }

    /// A ticket of B with one signature byte flipped.
    fn corrupt_ticket_msg(&self) -> ProtocolMessage {
        let mut msg = self.ticket_msg(&self.ticket(&self.b));
        let last = msg.payload.len() - 1;
        msg.payload[last] ^= 0x01;
        msg
    }
}

/// A follower at window W-1 that knows the clock of W-1 and W and the
/// canonical proposer of W (P, the first candidate of W-2).
struct Follower {
    state: LocalState,
    current: u64,
    timechain: TimeChainState,
    recent_roots: BTreeMap<u64, Hash32>,
    t_r_history: BTreeMap<u64, Hash32>,
    reveal_pool: BTreeMap<u64, BTreeMap<mt_state::NodeId, SshaReveal>>,
    bc_accumulator: BTreeMap<u64, BTreeMap<mt_state::NodeId, BundledConfirmation>>,
    winner_history: BTreeMap<u64, mt_state::NodeId>,
    lottery_history: BTreeMap<u64, Vec<mt_lottery::Candidate>>,
    bc_set_history: BTreeMap<u64, Vec<mt_state::NodeId>>,
    last_proposer_cement: BTreeMap<mt_state::NodeId, u64>,
    own_bc_cache: BTreeMap<u64, BundledConfirmation>,
    pending_msgs: Vec<ProtocolMessage>,
    fast_sync: Option<mt_sync::FastSyncClient>,
    fast_sync_deadline: Option<Instant>,
    last_cement_at: Instant,
    prev_proposal_hash: Hash32,
    data_dir: PathBuf,
    store: FsStore,
}

impl Follower {
    fn new(f: &Fixture, tag: &str) -> Self {
        let data_dir = temp_data_dir(tag);
        let store = FsStore::open(&data_dir).expect("store");
        let timechain = load_or_init_timechain(&data_dir).expect("genesis clock");
        let mut t_r_history = BTreeMap::new();
        t_r_history.insert(W - 1, T_R_PREV);
        t_r_history.insert(W, T_R_W);
        let mut lottery_history = BTreeMap::new();
        lottery_history.insert(
            W - 2,
            vec![Candidate {
                ticket: 0,
                class: WINNER_CLASS_NODE,
                id: f.p.node_id(),
            }],
        );
        Follower {
            state: LocalState {
                accounts: f.accounts.clone(),
                nodes: f.nodes.clone(),
                candidates: CandidatePool::new(),
            },
            current: W - 1,
            timechain,
            recent_roots: BTreeMap::new(),
            t_r_history,
            reveal_pool: BTreeMap::new(),
            bc_accumulator: BTreeMap::new(),
            winner_history: BTreeMap::new(),
            lottery_history,
            bc_set_history: BTreeMap::new(),
            last_proposer_cement: BTreeMap::new(),
            own_bc_cache: BTreeMap::new(),
            pending_msgs: Vec::new(),
            fast_sync: None,
            fast_sync_deadline: None,
            last_cement_at: Instant::now(),
            prev_proposal_hash: [0u8; 32],
            data_dir,
            store,
        }
    }

    /// Delivers the messages one by one as drain_network does: the deferred
    /// queue is replayed before every fresh message and once more at the end.
    fn deliver(&mut self, me: &crate::identity::Identity, msgs: Vec<ProtocolMessage>) {
        let (tx, _rx) = tokio::sync::mpsc::unbounded_channel::<ProtocolMessage>();
        let mut ctx = NetCtx {
            state: &mut self.state,
            current: &mut self.current,
            timechain: &mut self.timechain,
            recent_roots: &mut self.recent_roots,
            t_r_history: &mut self.t_r_history,
            reveal_pool: &mut self.reveal_pool,
            bc_accumulator: &mut self.bc_accumulator,
            winner_history: &mut self.winner_history,
            lottery_history: &mut self.lottery_history,
            bc_set_history: &mut self.bc_set_history,
            last_proposer_cement: &mut self.last_proposer_cement,
            own_bc_cache: &mut self.own_bc_cache,
            pending_msgs: &mut self.pending_msgs,
            fast_sync: &mut self.fast_sync,
            fast_sync_deadline: &mut self.fast_sync_deadline,
            last_cement_at: &mut self.last_cement_at,
            prev_proposal_hash: &mut self.prev_proposal_hash,
            fast_sync_lag_threshold: FAST_SYNC_LAG_THRESHOLD,
            fallback_secs: 3,
            data_dir: &self.data_dir,
            params: genesis_params(),
            store: &self.store,
            identity: me,
            my_node: me.node_id(),
        };
        for m in msgs {
            replay_deferred(&mut ctx, &tx);
            handle_protocol_message(&mut ctx, &tx, m).expect("deliver");
        }
        replay_deferred(&mut ctx, &tx);
    }

    /// What every verifier must agree on: the closed window and the roots.
    fn outcome(&self) -> Outcome {
        (
            self.current,
            compute_state_root(
                &self.state.nodes.root(),
                &self.state.candidates.root(),
                &self.state.accounts.root(),
            ),
            self.state.accounts.root(),
            self.state.nodes.root(),
        )
    }
}

fn replay_deferred(ctx: &mut NetCtx, tx: &tokio::sync::mpsc::UnboundedSender<ProtocolMessage>) {
    let pend = std::mem::take(ctx.pending_msgs);
    for m in pend {
        handle_protocol_message(ctx, tx, m).expect("replay");
    }
}

impl Drop for Follower {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.data_dir);
    }
}

fn permutations(n: usize) -> Vec<Vec<usize>> {
    if n == 0 {
        return vec![Vec::new()];
    }
    let mut out = Vec::new();
    for rest in permutations(n - 1) {
        for pos in 0..=rest.len() {
            let mut p = rest.clone();
            p.insert(pos, n - 1);
            out.push(p);
        }
    }
    out
}

/// Every order of the same messages gives every follower the same window and roots.
fn outcomes_over_all_orders(
    f: &Fixture,
    msgs: &[ProtocolMessage],
    tag: &str,
) -> Vec<(Vec<usize>, Outcome)> {
    permutations(msgs.len())
        .into_iter()
        .map(|order| {
            let mut node = Follower::new(f, tag);
            node.deliver(
                &f.follower,
                order.iter().map(|&i| msgs[i].clone()).collect(),
            );
            (order, node.outcome())
        })
        .collect()
}

// R3. Rejects a verifier whose verdict depends on whether the tickets arrived
// before the envelope (the "accepted by quorum" path of start.rs before R2):
// an envelope naming the wrong winner must be refused in every one of the 24
// orders, and the honest envelope applied in every one, with the same roots.
#[test]
fn every_delivery_order_gives_the_same_window_and_roots() {
    let f = Fixture::new();
    let (winner, loser) = f.winner_and_loser();
    let (ra, rb) = (f.ticket(&f.a), f.ticket(&f.b));
    for (name, env, closes) in [
        ("honest", f.envelope(winner), true),
        ("wrong-winner", f.envelope(loser), false),
    ] {
        let msgs = vec![
            f.ticket_msg(&ra),
            f.ticket_msg(&rb),
            f.corrupt_ticket_msg(),
            env,
        ];
        let runs = outcomes_over_all_orders(&f, &msgs, name);
        assert_eq!(runs.len(), 24);
        let (first_order, first) = runs[0].clone();
        for (order, out) in &runs {
            assert_eq!(
                out, &first,
                "{name}: order {order:?} gives a different window or roots than {first_order:?}"
            );
        }
        let expected = if closes { W } else { W - 1 };
        assert_eq!(first.0, expected, "{name}: window after delivery");
    }
}

// R4. Rejects a verifier that applies an envelope while a cemented ticket is
// missing from its pool: the ticket of B never arrives, so the envelope that
// names the wrong winner must not be applied, whichever comes first.
#[test]
fn an_envelope_with_a_missing_ticket_is_not_applied() {
    let f = Fixture::new();
    let (_, loser) = f.winner_and_loser();
    let ra = f.ticket(&f.a);
    for msgs in [
        vec![f.ticket_msg(&ra), f.envelope(loser)],
        vec![f.envelope(loser), f.ticket_msg(&ra)],
    ] {
        let mut node = Follower::new(&f, "incomplete");
        let before = node.outcome();
        node.deliver(&f.follower, msgs);
        assert_eq!(node.current, W - 1, "incomplete data closed the window");
        assert_eq!(node.outcome(), before, "incomplete data moved the state");
    }
}

// R4. Rejects a clock-record decoder that slices before it checks the length:
// a record shorter than its magic must be refused with an error, not panic.
#[test]
fn a_clock_record_shorter_than_its_magic_is_refused() {
    let dir = temp_data_dir("short-clock");
    let path = crate::timechain_state::timechain_path(&dir);
    std::fs::create_dir_all(path.parent().expect("meta dir")).expect("meta dir");
    std::fs::write(&path, b"mt").expect("write");
    let got = std::panic::catch_unwind(|| load_or_init_timechain(&dir).is_err());
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(
        got.ok(),
        Some(true),
        "a 2-byte clock record must be an error"
    );
}
