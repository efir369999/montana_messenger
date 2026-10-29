//! Issue #18: the order of delivery, the proposer of a window and its issuance.
//!
//! A follower at window 4 receives the messages that close window 5: confirmations
//! of the window and cemented envelopes. The envelopes are built by hand from real
//! ML-DSA-65 keys so that every check passes except the one a test aims at.
//!
//! The lottery is removed (the author's decision 279): the proposer of window 5 is
//! the lowest ticket by the aggregate of window 3 among the active nodes
//! (mt_consensus::proposer_at), and a window credits every living node the seconds
//! of the window.

use super::*;
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

/// Three active nodes P, A and B, with their tables, and a follower outside them.
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

    fn members(&self) -> [&crate::identity::Identity; 3] {
        [&self.p, &self.a, &self.b]
    }

    /// The confirmers of window W-2 the follower holds, as the proposal of W-1 included them.
    fn confirmers_two_before(&self) -> Vec<mt_state::NodeId> {
        let mut ids: Vec<mt_state::NodeId> = self.members().iter().map(|i| i.node_id()).collect();
        ids.sort();
        ids
    }

    /// The three nodes in the order of their tickets for window W.
    fn ticket_order(&self) -> Vec<&crate::identity::Identity> {
        let aggregate = cemented_bundle_aggregate(W - 2, &self.confirmers_two_before());
        let electorate: Vec<mt_state::NodeId> =
            self.members().iter().map(|i| i.node_id()).collect();
        mt_consensus::proposer_order(&aggregate, &electorate)
            .iter()
            .map(|id| {
                *self
                    .members()
                    .iter()
                    .find(|i| i.node_id() == *id)
                    .expect("a member")
            })
            .collect()
    }

    fn confirmation(
        &self,
        id: &crate::identity::Identity,
        window: u64,
        endpoint: Hash32,
    ) -> BundledConfirmation {
        let mut bc = BundledConfirmation {
            node_id: id.node_id(),
            endpoint,
            window_index: window,
            op_hashes: Vec::new(),
            reveal_hashes: Vec::new(),
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        bc.encode_signed_scope(&mut scope);
        bc.signature = sign(&id.node_sk, &scope).expect("sign confirmation");
        bc
    }

    fn confirmation_msg(&self, id: &crate::identity::Identity, window: u64) -> ProtocolMessage {
        let endpoint = if window == W { T_R_W } else { T_R_PREV };
        let mut payload = Vec::new();
        self.confirmation(id, window, endpoint).encode(&mut payload);
        ProtocolMessage::new(MsgType::BundledConfirmation, window, payload)
    }

    /// A confirmation of B for window W with one signature byte flipped.
    fn corrupt_confirmation_msg(&self) -> ProtocolMessage {
        let mut msg = self.confirmation_msg(&self.b, W);
        let last = msg.payload.len() - 1;
        msg.payload[last] ^= 0x01;
        msg
    }

    /// The header of window W proposed and signed by `proposer` at fallback_depth `depth`,
    /// with the state_root the settle computes, after `edit` and before the signature.
    fn header(
        &self,
        proposer: &crate::identity::Identity,
        depth: u8,
        edit: impl Fn(&mut ProposalHeader),
    ) -> ProposalHeader {
        self.header_with(proposer, depth, self.confirmers_two_before(), edit)
    }

    /// The same, with the state_root the settle computes for the given confirmers of W-1.
    fn header_with(
        &self,
        proposer: &crate::identity::Identity,
        depth: u8,
        confirmers: Vec<mt_state::NodeId>,
        edit: impl Fn(&mut ProposalHeader),
    ) -> ProposalHeader {
        let mut accounts = self.accounts.clone();
        let mut nodes = self.nodes.clone();
        let state_root = apply_proposal(
            &mut accounts,
            &mut nodes,
            &CandidatePool::new(),
            &ProposalSettle {
                window_w: W,
                cemented_confirmers: confirmers,
            },
            genesis_params(),
        );
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
            included_reveals_root: [0u8; 32],
            winner_endpoint: [0u8; 32],
            winner_id: [0u8; 32],
            proposer_node_id: proposer.node_id(),
            target: 0,
            fallback_depth: depth,
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        edit(&mut header);
        let mut scope = Vec::new();
        header.encode_signed_scope(&mut scope);
        header.signature = sign(&proposer.node_sk, &scope).expect("sign header");
        header
    }

    /// The cemented envelope of a header: the confirmations of W-1 and of W by all three.
    fn envelope_of(&self, header: &ProposalHeader) -> ProtocolMessage {
        self.envelope_with(header, &self.members(), &self.members())
    }

    /// The cemented envelope of a header with the confirmations of W-1 by `included` and of W
    /// by `evidence`, in that order.
    fn envelope_with(
        &self,
        header: &ProposalHeader,
        included: &[&crate::identity::Identity],
        evidence: &[&crate::identity::Identity],
    ) -> ProtocolMessage {
        let bundles_prev: Vec<BundledConfirmation> = included
            .iter()
            .map(|id| self.confirmation(id, W - 1, T_R_PREV))
            .collect();
        let evidence: Vec<BundledConfirmation> = evidence
            .iter()
            .map(|id| self.confirmation(id, W, T_R_W))
            .collect();
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

    fn envelope(&self, proposer: &crate::identity::Identity, depth: u8) -> ProtocolMessage {
        self.envelope_of(&self.header(proposer, depth, |_| {}))
    }
}

/// A follower at window W-1 that knows the clock of W-1 and W and the confirmers of W-2.
struct Follower {
    state: LocalState,
    current: u64,
    timechain: TimeChainState,
    recent_roots: BTreeMap<u64, Hash32>,
    t_r_history: BTreeMap<u64, Hash32>,
    bc_accumulator: BTreeMap<u64, BTreeMap<mt_state::NodeId, BundledConfirmation>>,
    bc_set_history: BTreeMap<u64, Vec<mt_state::NodeId>>,
    last_proposer_cement: BTreeMap<mt_state::NodeId, u64>,
    own_bc_cache: BTreeMap<u64, BundledConfirmation>,
    pending_msgs: Vec<ProtocolMessage>,
    equivocations: Equivocations,
    fast_sync: Option<mt_sync::FastSyncClient>,
    fast_sync_deadline: Option<Instant>,
    fast_sync_anchor: Option<Vec<u8>>,
    last_cement_at: Instant,
    prev_proposal_hash: Hash32,
    data_dir: PathBuf,
    store: FsStore,
}

impl Follower {
    fn new(f: &Fixture, tag: &str) -> Self {
        let data_dir = temp_data_dir(tag);
        let store = FsStore::open(&data_dir).expect("store");
        let timechain =
            crate::timechain_state::load_or_init_timechain(&data_dir).expect("genesis clock");
        let mut t_r_history = BTreeMap::new();
        t_r_history.insert(W - 1, T_R_PREV);
        t_r_history.insert(W, T_R_W);
        let mut bc_set_history = BTreeMap::new();
        bc_set_history.insert(W - 2, f.confirmers_two_before());
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
            bc_accumulator: BTreeMap::new(),
            bc_set_history,
            last_proposer_cement: BTreeMap::new(),
            own_bc_cache: BTreeMap::new(),
            pending_msgs: Vec::new(),
            equivocations: BTreeMap::new(),
            fast_sync: None,
            fast_sync_deadline: None,
            fast_sync_anchor: None,
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
            bc_accumulator: &mut self.bc_accumulator,
            bc_set_history: &mut self.bc_set_history,
            last_proposer_cement: &mut self.last_proposer_cement,
            own_bc_cache: &mut self.own_bc_cache,
            pending_msgs: &mut self.pending_msgs,
            equivocations: &mut self.equivocations,
            fast_sync: &mut self.fast_sync,
            fast_sync_deadline: &mut self.fast_sync_deadline,
            fast_sync_anchor: &mut self.fast_sync_anchor,
            last_cement_at: &mut self.last_cement_at,
            prev_proposal_hash: &mut self.prev_proposal_hash,
            fast_sync_lag_threshold: FAST_SYNC_LAG_THRESHOLD,
            fallback_secs: 3,
            data_dir: &self.data_dir,
            params: genesis_params(),
            store: &self.store,
            my_node: me.node_id(),
        };
        for m in msgs {
            replay_deferred(&mut ctx, &tx);
            handle_protocol_message(&mut ctx, &tx, m).expect("deliver");
        }
        replay_deferred(&mut ctx, &tx);
    }

    /// Everything the follower holds of its state: the closed window, the roots of the three
    /// tables, the hash of the proposal it closed on, and every file of its data directory
    /// (current_window, meta_last_cemented, the archived envelopes) byte for byte.
    fn held(&self) -> (Outcome, Hash32, BTreeMap<PathBuf, Vec<u8>>) {
        fn walk(dir: &std::path::Path, out: &mut BTreeMap<PathBuf, Vec<u8>>) {
            for entry in std::fs::read_dir(dir).expect("read dir") {
                let path = entry.expect("entry").path();
                if path.is_dir() {
                    walk(&path, out);
                } else {
                    out.insert(path.clone(), std::fs::read(&path).expect("read"));
                }
            }
        }
        let mut files = BTreeMap::new();
        walk(&self.data_dir, &mut files);
        (self.outcome(), self.prev_proposal_hash, files)
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

/// Every order of the same messages, each to a fresh follower: the order, the outcome and the
/// hash of the proposal the follower closed the window on.
fn outcomes_over_all_orders(
    f: &Fixture,
    msgs: &[ProtocolMessage],
    tag: &str,
) -> Vec<(Vec<usize>, Outcome, Hash32)> {
    permutations(msgs.len())
        .into_iter()
        .map(|order| {
            let mut node = Follower::new(f, tag);
            node.deliver(
                &f.follower,
                order.iter().map(|&i| msgs[i].clone()).collect(),
            );
            (order, node.outcome(), node.prev_proposal_hash)
        })
        .collect()
}

// R3, carried over the removal of the lottery. Rejects a verifier whose verdict depends on the
// order of delivery: the envelope of the proposer the ticket names must be applied in every one
// of the 24 orders, and the envelope of a node the ticket does not name refused in every one,
// with the same roots.
#[test]
fn every_delivery_order_gives_the_same_window_and_roots() {
    let f = Fixture::new();
    let order = f.ticket_order();
    for (name, env, closes) in [
        ("lowest-ticket", f.envelope(order[0], 1), true),
        ("not-the-ticket", f.envelope(order[1], 1), false),
    ] {
        let msgs = vec![
            f.confirmation_msg(&f.a, W),
            f.confirmation_msg(&f.p, W - 1),
            f.corrupt_confirmation_msg(),
            env,
        ];
        let runs = outcomes_over_all_orders(&f, &msgs, name);
        assert_eq!(runs.len(), 24);
        let (first_order, first, _) = runs[0].clone();
        for (order, out, _) in &runs {
            assert_eq!(
                out, &first,
                "{name}: order {order:?} gives a different window or roots than {first_order:?}"
            );
        }
        let expected = if closes { W } else { W - 1 };
        assert_eq!(first.0, expected, "{name}: window after delivery");
    }
}

// Issue #18, S1. Rejects a proposer rule taken from arrival: every node of the electorate sends
// its own envelope of window W at depth 1, and in every one of the 6 orders the follower closes
// the window on the envelope of the lowest ticket by the aggregate of W-2, and on no other.
#[test]
fn a_window_has_one_proposer_whatever_the_order_of_delivery() {
    let f = Fixture::new();
    let order = f.ticket_order();
    let lowest = proposal_hash(&f.header(order[0], 1, |_| {}));
    let msgs: Vec<ProtocolMessage> = f.members().iter().map(|id| f.envelope(id, 1)).collect();
    let runs = outcomes_over_all_orders(&f, &msgs, "one-proposer");
    assert_eq!(runs.len(), 6);
    for (delivery, out, closed_on) in &runs {
        assert_eq!(out.0, W, "order {delivery:?}: the window stays open");
        assert_eq!(
            *closed_on, lowest,
            "order {delivery:?}: closed on another proposer's envelope"
        );
    }
    // The cascade walks the same order: depth 2 names the second ticket and nobody else.
    let mut node = Follower::new(&f, "depth-two");
    node.deliver(
        &f.follower,
        vec![f.envelope(order[0], 2), f.envelope(order[2], 2)],
    );
    assert_eq!(
        node.current,
        W - 1,
        "depth 2 accepted from a node it does not name"
    );
    node.deliver(&f.follower, vec![f.envelope(order[1], 2)]);
    assert_eq!(node.current, W, "depth 2 refused from the second ticket");
}

// Issue #18, S3. Rejects a follower that applies a header carrying a value in a field of the
// lottery: the proposer the ticket names signs each such header itself, so only the field is
// wrong, and every one is refused; the same header with the four fields zero is applied.
#[test]
fn a_header_with_a_non_zero_lottery_field_is_refused() {
    let f = Fixture::new();
    let proposer = f.ticket_order()[0];
    let edits: [fn(&mut ProposalHeader); 4] = [
        |h| h.target = u128::MAX,
        |h| h.included_reveals_root = [0x09; 32],
        |h| h.winner_endpoint = [0x0A; 32],
        |h| h.winner_id = [0x0B; 32],
    ];
    for (i, edit) in edits.into_iter().enumerate() {
        let mut node = Follower::new(&f, "lottery-field");
        let before = node.outcome();
        node.deliver(
            &f.follower,
            vec![f.envelope_of(&f.header(proposer, 1, edit))],
        );
        assert_eq!(
            node.outcome(),
            before,
            "field {i}: a non-zero lottery field applied"
        );
    }
    let mut node = Follower::new(&f, "lottery-zero");
    node.deliver(&f.follower, vec![f.envelope(proposer, 1)]);
    assert_eq!(
        node.current, W,
        "a header with the four fields zero refused"
    );
}

// Issue #18, S4: a second envelope of an applied window: refused, state byte-identical, the pair
// kept. core/docs Consensus:1382, a machine "never abandons a decision it verified"; :1239-1243,
// two decisions that both verify are an equivocation and are kept as its evidence. Rejects a
// follower that takes the second envelope as the window's decision (re-archives it, moves to it,
// re-applies it), and one that keeps no evidence of the equivocation.
#[test]
fn a_second_envelope_of_an_applied_window_is_refused_and_the_pair_kept() {
    let f = Fixture::new();
    let order = f.ticket_order();
    let first = f.envelope(order[0], 1);
    let edited = f.header(order[0], 1, |h| h.included_bundles_root = [0x77; 32]);
    let second = f.envelope_of(&edited);
    let mut node = Follower::new(&f, "equivocation");
    node.deliver(&f.follower, vec![first.clone()]);
    assert_eq!(node.current, W, "the first envelope is applied");
    let held = node.held();
    node.deliver(&f.follower, vec![second.clone()]);
    assert!(node.held() == held, "a second envelope moved the state");
    assert_eq!(
        node.equivocations.get(&(W, order[0].node_id())),
        Some(&(first.payload.clone(), second.payload.clone())),
        "the pair of the equivocation is not kept"
    );
    // The same envelope again, or one of another proposer, is no equivocation of the first.
    node.deliver(&f.follower, vec![first, f.envelope(order[1], 2)]);
    assert!(
        node.held() == held,
        "a repeated or foreign envelope moved the state"
    );
    assert_eq!(node.equivocations.len(), 1);
}

// Issue #18, S5. An envelope that names one node's confirmation twice, in the confirmations of
// W-1 or in the evidence of W, is refused whole and moves nothing. Three nodes of chain length
// 10 give a quorum of 21: P and A alone (20) fall short, P counted twice (30) passes. Rejects the
// counting code before S5, which summed the repeat into the quorum and applied the envelope with
// P's chain length raised twice.
#[test]
fn an_envelope_naming_one_confirmation_twice_is_refused_whole() {
    let f = Fixture::new();
    let proposer = f.ticket_order()[0];
    let all = f.members();
    let twice = [&f.p, &f.a, &f.p];
    let mut repeated: Vec<mt_state::NodeId> = twice.iter().map(|i| i.node_id()).collect();
    repeated.sort();
    for (name, header, included, evidence) in [
        (
            "included",
            f.header_with(proposer, 1, repeated, |_| {}),
            twice,
            all,
        ),
        ("evidence", f.header(proposer, 1, |_| {}), all, twice),
    ] {
        let mut node = Follower::new(&f, "named-twice");
        let before = node.held();
        node.deliver(
            &f.follower,
            vec![f.envelope_with(&header, &included, &evidence)],
        );
        assert!(
            node.held() == before,
            "{name}: an envelope naming a confirmation twice moved the state"
        );
    }
}

// Issue #18, S1. Rejects a follower that names a proposer from confirmers of W-2 it does not
// hold: without them it refuses, rather than hashing an absent set as an empty one.
#[test]
fn a_follower_that_does_not_hold_the_aggregate_refuses() {
    let f = Fixture::new();
    let order = f.ticket_order();
    let mut node = Follower::new(&f, "no-aggregate");
    node.bc_set_history.clear();
    let before = node.outcome();
    node.deliver(&f.follower, vec![f.envelope(order[0], 1)]);
    assert_eq!(
        node.outcome(),
        before,
        "applied without the aggregate of W-2"
    );
}

// Issue #18, S2 at the node. Rejects a window that issues anything but its seconds to each of
// its living nodes: the three confirmers of W-1 gain 60 coins each, and nobody else gains.
#[test]
fn a_closed_window_issues_its_seconds_to_every_living_node() {
    let f = Fixture::new();
    let order = f.ticket_order();
    let mut node = Follower::new(&f, "issuance");
    let supply = |n: &Follower| -> u128 { n.state.accounts.iter().map(|r| r.balance).sum() };
    let before = supply(&node);
    node.deliver(&f.follower, vec![f.envelope(order[0], 1)]);
    assert_eq!(node.current, W);
    assert_eq!(supply(&node) - before, 3 * 60 * mt_account::MONETA_PER_COIN);
    for id in f.members() {
        assert_eq!(
            node.state.accounts.get(&id.account_id()).map(|r| r.balance),
            Some(60 * mt_account::MONETA_PER_COIN)
        );
    }
}

/// Runs one test of this module again in a child process with its stderr not captured, the
/// local opt-in MONTANA_PRIVATE_DIAGNOSTICS absent or set to 1, and returns that stderr.
fn stderr_of(test: &str, opt_in: bool) -> String {
    let mut child = std::process::Command::new(std::env::current_exe().expect("test binary"));
    child
        .arg(format!("commands::start::order_tests::{test}"))
        .args(["--exact", "--nocapture", "--test-threads=1"]);
    if opt_in {
        child.env("MONTANA_PRIVATE_DIAGNOSTICS", "1");
    } else {
        child.env_remove("MONTANA_PRIVATE_DIAGNOSTICS");
    }
    let out = child.output().expect("run the test binary");
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    assert!(out.status.success(), "{test} failed: {stderr}");
    stderr
}

// K7, issue #22. Rejects a default record that names a node or renders an error: the
// equivocation (keep_equivocation) and the refusal of a non-zero lottery field print only their
// fixed categories, with no proposer identifier and no error, unless the operator sets
// MONTANA_PRIVATE_DIAGNOSTICS=1; with it the same runs carry both, so the check sees what it
// rejects.
#[test]
fn the_equivocation_and_retired_field_records_name_no_node_by_default() {
    let proposer = hex16(&Fixture::new().ticket_order()[0].node_id());
    let equivocation = format!("equivocation by {proposer}");
    for (test, public, detail, secret) in [
        (
            "a_second_envelope_of_an_applied_window_is_refused_and_the_pair_kept",
            "[node] equivocation kept",
            equivocation.as_str(),
            proposer.as_str(),
        ),
        (
            "a_header_with_a_non_zero_lottery_field_is_refused",
            "[node] retired header fields refused",
            "RetiredFieldNotZero — skip",
            "RetiredFieldNotZero",
        ),
    ] {
        let default = stderr_of(test, false);
        assert!(default.contains(public), "{test}: no category");
        assert!(
            !default.contains(secret),
            "{test}: default stderr carries `{secret}`"
        );
        let opted_in = stderr_of(test, true);
        assert!(
            opted_in.contains(detail),
            "{test}: the opt-in does not print `{detail}`"
        );
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
    let got =
        std::panic::catch_unwind(|| crate::timechain_state::load_or_init_timechain(&dir).is_err());
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(
        got.ok(),
        Some(true),
        "a 2-byte clock record must be an error"
    );
}
