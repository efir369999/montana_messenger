//! Issue #19 K5: a window is applied as ONE record — the tables, the window, the clock and the
//! cemented envelope. A death at any file operation of a settle or of a fast sync leaves on disk
//! the old record or the new one byte for byte, never a mix; the node reopens on that record;
//! and a window applied again after such a death issues nothing a second time.
//!
//! Three active nodes P, A and B (chain length 10 each) at window W-1; the node under test is
//! one of them. The death is the fault hook of mt-store (`fault::fail_at`): the k-th file
//! operation fails, and every one after it, as in a process that died there.

use super::*;
use mt_state::{AccountRecord, AccountTable, CandidatePool, NodeRecord, NodeTable};
use mt_store::{fault, WindowRecord, WINDOW_RECORD_FILE};
use std::sync::atomic::AtomicU64;

const W: u64 = 5;
const D: u64 = 1_000;

static DIR_SEQ: AtomicU64 = AtomicU64::new(0);

/// The canonical clock value of window w in these tests.
fn t_r_of(w: u64) -> Hash32 {
    [0x40u8.wrapping_add(w as u8); 32]
}

fn identity(seed: u8) -> crate::identity::Identity {
    crate::identity::Identity::from_master_seed([seed; 64]).expect("identity")
}

fn temp_data_dir(tag: &str) -> PathBuf {
    let n = DIR_SEQ.fetch_add(1, Ordering::SeqCst);
    let name = format!("montana-k5-{tag}-{}-{n}", std::process::id());
    let dir = std::env::temp_dir().join(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn root(s: &LocalState) -> Hash32 {
    compute_state_root(&s.nodes.root(), &s.candidates.root(), &s.accounts.root())
}

fn record_bytes(dir: &std::path::Path) -> Vec<u8> {
    std::fs::read(dir.join(WINDOW_RECORD_FILE)).expect("the window record")
}

/// Every file of a data directory, byte for byte.
fn files(dir: &std::path::Path) -> BTreeMap<PathBuf, Vec<u8>> {
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
    let mut out = BTreeMap::new();
    walk(dir, &mut out);
    out
}

struct Fixture {
    ids: Vec<crate::identity::Identity>,
    nodes: NodeTable,
    accounts: AccountTable,
}

impl Fixture {
    fn new() -> Self {
        let ids: Vec<_> = [0x70u8, 0x71, 0x72].into_iter().map(identity).collect();
        let mut nodes = NodeTable::new();
        let mut accounts = AccountTable::new();
        for id in &ids {
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
            ids,
            nodes,
            accounts,
        }
    }

    fn confirmers(&self) -> Vec<mt_state::NodeId> {
        let mut v: Vec<_> = self.ids.iter().map(|i| i.node_id()).collect();
        v.sort();
        v
    }

    /// The node whose envelope of W the followers take: the lowest ticket by the aggregate
    /// of W-2 (issue #18).
    fn proposer_of_w(&self) -> &crate::identity::Identity {
        let aggregate = cemented_bundle_aggregate(W - 2, &self.confirmers());
        let electorate: Vec<mt_state::NodeId> = self.ids.iter().map(|i| i.node_id()).collect();
        let first = mt_consensus::proposer_order(&aggregate, &electorate)[0];
        self.ids
            .iter()
            .find(|i| i.node_id() == first)
            .expect("a member")
    }

    fn tables(&self) -> LocalState {
        LocalState {
            accounts: self.accounts.clone(),
            nodes: self.nodes.clone(),
            candidates: CandidatePool::new(),
        }
    }

    /// The tables of window w closed on `before`, as every node computes them.
    fn closed(&self, before: &LocalState, w: u64) -> LocalState {
        let mut accounts = before.accounts.clone();
        let mut nodes = before.nodes.clone();
        apply_proposal(
            &mut accounts,
            &mut nodes,
            &before.candidates,
            &ProposalSettle {
                window_w: w,
                cemented_confirmers: self.confirmers(),
            },
            genesis_params(),
        );
        LocalState {
            accounts,
            nodes,
            candidates: before.candidates.clone(),
        }
    }

    /// A data directory whose record holds window W-1 on the fixture's tables.
    fn store_at_w_minus_1(&self, tag: &str) -> PathBuf {
        let dir = temp_data_dir(tag);
        let store = FsStore::open(&dir).expect("store");
        let clock = TimeChainState {
            t_r: t_r_of(W - 1),
            current_d: D,
            last_window: W - 1,
        };
        let p = genesis_params();
        let record = crate::window_record::record_of(W - 1, &self.tables(), &clock, Vec::new(), p);
        crate::window_record::commit(&store, &record, p).expect("record of W-1");
        dir
    }

    fn confirmation(&self, id: &crate::identity::Identity, w: u64) -> BundledConfirmation {
        let mut bc = BundledConfirmation {
            node_id: id.node_id(),
            endpoint: t_r_of(w),
            window_index: w,
            op_hashes: Vec::new(),
            reveal_hashes: Vec::new(),
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        };
        let mut scope = Vec::new();
        bc.encode_signed_scope(&mut scope);
        bc.signature = sign(&id.node_sk, &scope).expect("sign confirmation");
        bc
    }

    /// `leader` closes window w: the confirmations of w-1 and of w by all three are held, as a
    /// proposer holds them when its quorum wait ends, and the cement block runs.
    fn lead(
        &self,
        node: &mut Node,
        leader: &crate::identity::Identity,
        w: u64,
    ) -> Result<Cemented, NodeError> {
        for cw in [w - 1, w] {
            for id in &self.ids {
                node.bc_accumulator
                    .entry(cw)
                    .or_default()
                    .insert(id.node_id(), self.confirmation(id, cw));
            }
        }
        let canonical = if w == W {
            leader.node_id()
        } else {
            mt_consensus::NO_PROPOSER
        };
        node.with_ctx(leader.node_id(), |ctx| {
            cement_as_leader(ctx, leader, w, t_r_of(w), canonical, 1)
        })
    }

    /// The envelope of W its proposer cements on the tables of W-1.
    fn envelope_of_w(&self) -> Vec<u8> {
        let leader = self.proposer_of_w();
        let dir = self.store_at_w_minus_1("envelope");
        let mut node = Node::start(self, &dir, leader);
        let cemented = self
            .lead(&mut node, leader, W)
            .expect("the proposer's envelope");
        drop(node);
        let _ = std::fs::remove_dir_all(&dir);
        cemented.envelope
    }
}

/// A node as `start` holds it: what window_record::open read, and the histories of a node
/// that saw windows W-2 and W-1 close.
struct Node {
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

impl Node {
    fn start(f: &Fixture, dir: &std::path::Path, me: &crate::identity::Identity) -> Self {
        Self::try_start(f, dir, me).expect("start")
    }

    fn try_start(
        f: &Fixture,
        dir: &std::path::Path,
        me: &crate::identity::Identity,
    ) -> Result<Self, NodeError> {
        let (state, current, timechain) =
            crate::window_record::open(dir, me, genesis_params(), false)?;
        let mut t_r_history = BTreeMap::new();
        for w in W - 1..=W + 2 {
            t_r_history.insert(w, t_r_of(w));
        }
        let mut bc_set_history = BTreeMap::new();
        bc_set_history.insert(W - 2, f.confirmers());
        Ok(Node {
            state,
            current,
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
            data_dir: dir.to_path_buf(),
            store: FsStore::open(dir).expect("store"),
        })
    }

    fn with_ctx<R>(&mut self, me: mt_state::NodeId, f: impl FnOnce(&mut NetCtx) -> R) -> R {
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
            my_node: me,
        };
        f(&mut ctx)
    }

    fn held(&self) -> (u64, Hash32) {
        (self.current, root(&self.state))
    }

    fn balance(&self, id: &crate::identity::Identity) -> u128 {
        self.state
            .accounts
            .get(&id.account_id())
            .map(|a| a.balance)
            .unwrap_or(0)
    }
}

/// One way of applying window W to a node at W-1 (the leader's cement, a follower taking the
/// envelope, a fast sync), run on a fresh store at every death k of its file operations.
/// After each death the record on disk is the old one or the new one byte for byte; a node
/// whose record is still the old one has not moved in memory; the node reopens on that record.
fn dies_whole_at_every_file_operation(
    tag: &str,
    f: &Fixture,
    me: &crate::identity::Identity,
    apply: &dyn Fn(&mut Node) -> Result<(), NodeError>,
) {
    let old = (W - 1, root(&f.tables()));
    let new = (W, root(&f.closed(&f.tables(), W)));
    let (new_bytes, ops) = {
        let dir = f.store_at_w_minus_1(tag);
        let mut node = Node::start(f, &dir, me);
        fault::fail_at(None);
        apply(&mut node).expect("an unharmed application");
        let ops = fault::done();
        assert_eq!(node.held(), new, "{tag}: the unharmed application");
        let bytes = record_bytes(&dir);
        drop(node);
        let _ = std::fs::remove_dir_all(&dir);
        (bytes, ops)
    };
    assert!(
        ops >= 5,
        "{tag}: {ops} file operations, fewer than one commit"
    );
    let (mut seen_old, mut seen_new) = (false, false);
    for k in 1..=ops {
        let dir = f.store_at_w_minus_1(tag);
        let mut node = Node::start(f, &dir, me);
        let old_bytes = record_bytes(&dir);
        fault::fail_at(Some(k));
        let got = apply(&mut node);
        fault::fail_at(None);
        assert!(
            got.is_err(),
            "{tag}: the death at file operation {k} was not reported"
        );
        let held = record_bytes(&dir);
        let on_disk = if held == old_bytes {
            seen_old = true;
            assert_eq!(
                node.held(),
                old,
                "{tag}: death at {k}: memory moved without its record"
            );
            old
        } else {
            assert!(
                held == new_bytes,
                "{tag}: death at {k}: the record is neither the old one nor the new one"
            );
            seen_new = true;
            new
        };
        drop(node);
        let reopened = Node::start(f, &dir, me);
        assert_eq!(
            reopened.held(),
            on_disk,
            "{tag}: death at {k}: the node reopens on another window or other tables"
        );
        drop(reopened);
        let _ = std::fs::remove_dir_all(&dir);
    }
    assert!(
        seen_old && seen_new,
        "{tag}: deaths before and after the commit"
    );
}

// (a) Rejects a settle that writes its window apart from its tables, or memory before disk
// (main f1a5fada: current_window and meta_last_cemented by the settle, the tables by
// save_progress after the envelope was archived and broadcast). The proposer's cement block.
#[test]
fn a_leader_settle_dying_at_every_file_operation_leaves_the_old_or_the_new_window() {
    let f = Fixture::new();
    let leader = f.proposer_of_w();
    dies_whole_at_every_file_operation("leader", &f, leader, &|node| {
        f.lead(node, leader, W).map(|_| ())
    });
}

// (a) The same for a follower: the envelope the proposer of W cemented, checked against its
// state_root and then committed once.
#[test]
fn a_follower_settle_dying_at_every_file_operation_leaves_the_old_or_the_new_window() {
    let f = Fixture::new();
    let leader = f.proposer_of_w();
    let envelope = f.envelope_of_w();
    let follower = f
        .ids
        .iter()
        .find(|i| i.node_id() != leader.node_id())
        .unwrap();
    dies_whole_at_every_file_operation("follower", &f, follower, &|node| {
        let (tx, _rx) = tokio::sync::mpsc::unbounded_channel::<ProtocolMessage>();
        let msg = ProtocolMessage::new(MsgType::Proposal, W, envelope.clone());
        node.with_ctx(follower.node_id(), |ctx| {
            handle_protocol_message(ctx, &tx, msg)
        })?;
        // A refusal is no application: the death must be what stopped it.
        if node.current != W {
            return Err(NodeError::InvalidArguments("not applied".into()));
        }
        Ok(())
    });
}

// (b) Rejects a fast sync that writes its tables apart from its window (main f1a5fada:
// apply_fast_sync writes the tables and meta_last_cemented, the caller current_window and
// the clock after). The record of the synced window carries the envelope its anchor root
// was taken from.
#[test]
fn a_fast_sync_dying_at_every_file_operation_leaves_the_old_or_the_new_window() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let snapshot = f.closed(&f.tables(), W);
    let anchor = f.envelope_of_w();
    let apply = |node: &mut Node| {
        let tables = mt_sync::snapshot::TypedTables {
            accounts: snapshot.accounts.clone(),
            nodes: snapshot.nodes.clone(),
            candidates: snapshot.candidates.clone(),
        };
        node.fast_sync_anchor = Some(anchor.clone());
        node.with_ctx(me.node_id(), |ctx| complete_fast_sync(ctx, W, tables))
    };
    dies_whole_at_every_file_operation("fast-sync", &f, me, &apply);
    let dir = f.store_at_w_minus_1("fast-sync-anchor");
    let mut node = Node::start(&f, &dir, me);
    apply(&mut node).expect("a fast sync");
    let record = WindowRecord::decode(&record_bytes(&dir)).expect("the synced record");
    assert!(
        record.envelope == anchor,
        "the synced record lost its anchor's envelope"
    );
    drop(node);
    let _ = std::fs::remove_dir_all(&dir);
}

// (c) The issue's own: a fast sync to W dies at any file operation (the death between the
// tables and the window among them), the node reopens and, as the leader, closes its next
// window. Every confirmer holds one window credit per window closed since W-1: a window the
// snapshot already credited is never credited again.
#[test]
fn a_fast_sync_death_then_the_leader_issues_each_window_once() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let snapshot = f.closed(&f.tables(), W);
    let anchor = f.envelope_of_w();
    let credit = mt_account::window_credit_moneta(genesis_params());
    let apply = |node: &mut Node| {
        node.fast_sync_anchor = Some(anchor.clone());
        node.with_ctx(me.node_id(), |ctx| {
            complete_fast_sync(ctx, W, typed(&snapshot))
        })
    };
    let ops = {
        let dir = f.store_at_w_minus_1("one-emission-count");
        let mut node = Node::start(&f, &dir, me);
        fault::fail_at(None);
        apply(&mut node).expect("an unharmed fast sync");
        let ops = fault::done();
        drop(node);
        let _ = std::fs::remove_dir_all(&dir);
        ops
    };
    // k = ops + 1 is the fast sync that did not die.
    for k in 1..=ops + 1 {
        let dir = f.store_at_w_minus_1("one-emission");
        let mut node = Node::start(&f, &dir, me);
        fault::fail_at(Some(k));
        let _ = apply(&mut node);
        fault::fail_at(None);
        drop(node);
        let mut node = Node::start(&f, &dir, me);
        let next = node.current + 1;
        f.lead(&mut node, me, next)
            .expect("the leader closes its next window");
        for id in &f.ids {
            assert_eq!(
                node.balance(id),
                credit * u128::from(node.current - (W - 1)),
                "death at {k}: at head {} a confirmer holds {} window credits",
                node.current,
                node.balance(id) / credit
            );
        }
        drop(node);
        let reopened = Node::start(&f, &dir, me);
        assert_eq!(
            reopened.balance(me),
            credit * u128::from(reopened.current - (W - 1)),
            "death at {k}: after a restart"
        );
        drop(reopened);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

/// The tables of a snapshot, as `FastSyncClient::finalize` hands them over.
fn typed(s: &LocalState) -> mt_sync::snapshot::TypedTables {
    mt_sync::snapshot::TypedTables {
        accounts: s.accounts.clone(),
        nodes: s.nodes.clone(),
        candidates: s.candidates.clone(),
    }
}

// Rejects a fast sync that commits a head without its proof (the Author's decisions 301/303:
// the proof in the record of a head is the cemented Proposal; 74738de committed the record
// with an empty envelope). A snapshot whose anchor is missing, cut short, the envelope of
// another window, or names another state_root is refused: the store is left byte for byte,
// memory stays at W-1 and the anchor is spent. The next attempt, whose anchor is the envelope
// of W naming the snapshot's root, applies W with that envelope in its record.
#[test]
fn a_fast_sync_whose_anchor_does_not_name_its_window_and_root_is_refused() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let snapshot = f.closed(&f.tables(), W);
    let anchor = f.envelope_of_w();
    let id = me.node_id();
    let old = (W - 1, root(&f.tables()));
    let (a, s) = (|| Some(anchor.clone()), || typed(&snapshot));
    for (name, given, window, tables) in [
        ("no anchor", None, W, s()),
        ("cut short", Some(anchor[..100].to_vec()), W, s()),
        ("another window", a(), W + 1, s()),
        ("another root", a(), W, typed(&f.tables())),
    ] {
        let dir = f.store_at_w_minus_1("no-proof");
        let mut node = Node::start(&f, &dir, me);
        let before = files(&dir);
        node.fast_sync_anchor = given;
        let got = node.with_ctx(id, |ctx| complete_fast_sync(ctx, window, tables));
        assert!(got.is_ok(), "{name}: a refused sync stopped the node");
        assert!(
            files(&dir) == before,
            "{name}: a head was committed without its proof"
        );
        assert_eq!(node.held(), old, "{name}: memory moved");
        assert!(node.fast_sync_anchor.is_none(), "{name}: anchor kept");
        // The retry on the next cemented window, with the anchor that names it.
        node.fast_sync_anchor = Some(anchor.clone());
        let retry = node.with_ctx(id, |ctx| complete_fast_sync(ctx, W, typed(&snapshot)));
        retry.expect("the retry");
        assert_eq!(node.held(), (W, root(&snapshot)), "{name}: the retry");
        let record = WindowRecord::decode(&record_bytes(&dir)).expect("the synced record");
        assert!(
            record.window == W && record.envelope == anchor,
            "{name}: the retry's record does not carry its anchor"
        );
        drop(node);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

/// The earlier layout of a node at `current` / `last_cemented` on the fixture's tables.
fn earlier_layout(f: &Fixture, tag: &str, current: u64, last_cemented: u64) -> PathBuf {
    earlier_layout_on(&f.tables(), tag, current, last_cemented)
}

/// The earlier layout of a node at `current` / `last_cemented` on `tables`.
fn earlier_layout_on(tables: &LocalState, tag: &str, current: u64, last_cemented: u64) -> PathBuf {
    let dir = temp_data_dir(tag);
    tables.save(&dir).expect("tables");
    crate::clock::save_current_window(&dir, current).expect("current_window");
    FsStore::open(&dir)
        .expect("store")
        .save_meta_last_cemented(last_cemented)
        .expect("meta_last_cemented");
    dir
}

/// An archived envelope of window w whose header names `state_root`.
fn archive_naming(dir: &std::path::Path, w: u64, state_root: Hash32) {
    let mut envelope = vec![0u8; mt_consensus::PROPOSAL_HEADER_SIZE + 4];
    envelope[172..204].copy_from_slice(&state_root);
    FsStore::open(dir)
        .expect("store")
        .archive_proposal_envelope(w, &envelope)
        .expect("archive");
}

/// A start on `dir` that must be refused: the refusal says `says`, and the store is left as it
/// was, byte for byte.
fn refused_and_left(
    f: &Fixture,
    dir: &std::path::Path,
    me: &crate::identity::Identity,
    says: &[&str],
) {
    let before = files(dir);
    let err = Node::try_start(f, dir, me)
        .err()
        .unwrap_or_else(|| panic!("{}: the node started", dir.display()));
    let said = format!("{err}");
    for want in says {
        assert!(
            said.contains(want),
            "the refusal does not say {want:?}: {said}"
        );
    }
    assert!(
        files(dir) == before,
        "{said}: a refused start wrote to the store"
    );
}

/// The bytes of a record of version 2 in the layout of version 1 (main 8a6e7bc): the head
/// without the network (bytes 96..128), summed again.
fn as_version_1(v2: &[u8]) -> Vec<u8> {
    let mut body = v2[..96].to_vec();
    body.extend_from_slice(&v2[128..v2.len() - 32]);
    body[4] = 1;
    let sum = mt_crypto::sha256_raw(&body);
    body.extend_from_slice(&sum);
    body
}

/// A data directory whose record holds `tables` at `window` in the layout of version 1.
fn store_version_1(tag: &str, window: u64, tables: &LocalState) -> PathBuf {
    let dir = temp_data_dir(tag);
    let clock = TimeChainState {
        t_r: t_r_of(window),
        current_d: D,
        last_window: window,
    };
    let record =
        crate::window_record::record_of(window, tables, &clock, Vec::new(), genesis_params());
    std::fs::write(dir.join(WINDOW_RECORD_FILE), as_version_1(&record.encode()))
        .expect("a record of version 1");
    dir
}

fn genesis_tables() -> LocalState {
    LocalState {
        accounts: AccountTable::new(),
        nodes: NodeTable::new(),
        candidates: CandidatePool::new(),
    }
}

// (d) Rejects a start that takes the earlier layout as it finds it: a store whose
// current_window and meta_last_cemented name two windows does not start, says why, and is left
// as it was. Issue #19 K6 (d), the Author's decision 331a: a store of the earlier layout above
// window zero names no network and returns only by a fresh sync, even when the archived
// envelope of its window names its tables (main 8a6e7bc migrated that one, "one-window"); so
// does a record of version 1 above window zero. Each is refused, says "re-sync this node", and
// is left as it was.
#[test]
fn an_earlier_layout_or_a_record_of_version_1_above_window_zero_returns_only_by_re_sync() {
    let f = Fixture::new();
    let me = &f.ids[0];

    let dir = earlier_layout(&f, "two-windows", 7, 5);
    refused_and_left(
        &f,
        &dir,
        me,
        &[
            "current_window.bin names 7",
            "meta_last_cemented.bin names 5",
        ],
    );
    let _ = std::fs::remove_dir_all(&dir);

    let resync = ["it names no network", "re-sync this node"];
    let dir = earlier_layout(&f, "unarchived", W - 1, W - 1);
    refused_and_left(&f, &dir, me, &resync);
    let _ = std::fs::remove_dir_all(&dir);

    let dir = earlier_layout(&f, "foreign-root", W - 1, W - 1);
    archive_naming(&dir, W - 1, [0xEE; 32]);
    refused_and_left(&f, &dir, me, &resync);
    let _ = std::fs::remove_dir_all(&dir);

    let dir = earlier_layout(&f, "one-window", W - 1, W - 1);
    archive_naming(&dir, W - 1, root(&f.tables()));
    refused_and_left(&f, &dir, me, &resync);
    let _ = std::fs::remove_dir_all(&dir);

    for window in [1, W - 1] {
        let dir = store_version_1("v1-above-zero", window, &f.tables());
        refused_and_left(
            &f,
            &dir,
            me,
            &["(version 1) at window", "re-sync this node"],
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
    // Not even on the tables of window zero: above it no table names the network.
    let bootstrap = LocalState::bootstrap(me, genesis_params());
    let dir = store_version_1("v1-above-zero-genesis", W - 1, &bootstrap);
    refused_and_left(&f, &dir, me, &resync);
    let _ = std::fs::remove_dir_all(&dir);
}

// Issue #19 K6: the earlier layout at window zero is a new node. On the tables a machine of
// this network holds there it starts, and its record names this network; on other tables it
// does not start and the store is left as it was. The record is the truth from then on: the
// earlier files no longer move the start.
#[test]
fn an_earlier_layout_at_window_zero_starts_only_on_the_tables_of_this_network() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let p = genesis_params();
    let bootstrap = LocalState::bootstrap(me, p);

    let dir = earlier_layout_on(&bootstrap, "window-zero", 0, 0);
    assert_eq!(Node::start(&f, &dir, me).held(), (0, root(&bootstrap)));
    let record = WindowRecord::decode(&record_bytes(&dir)).expect("the record of window zero");
    assert_eq!(record.genesis_state_hash, mt_account::genesis_state_hash(p));
    crate::clock::save_current_window(&dir, 99).expect("a stray view");
    assert_eq!(Node::start(&f, &dir, me).held(), (0, root(&bootstrap)));
    let _ = std::fs::remove_dir_all(&dir);

    let dir = earlier_layout(&f, "window-zero-other-tables", 0, 0);
    refused_and_left(
        &f,
        &dir,
        me,
        &["at window 0: it names no network", "state_root"],
    );
    let _ = std::fs::remove_dir_all(&dir);
}

// Issue #19 K6 (a): rejects a start on a record of another network (main 8a6e7bc: the record
// named none, and a store of another Decree's balances started as this network's). A record of
// version 2 whose genesis_state_hash is the devnet Decree's, at window zero or above it, is
// refused: the refusal names both hashes, 8 bytes each, and says "another network", and nothing
// in the data dir changes. A running node does not write over such a record, and no commit
// writes one.
#[test]
fn a_record_of_another_network_is_refused_and_the_store_is_left_as_it_was() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let p = genesis_params();
    let mut devnet = p.clone();
    devnet.ssha_entry_windows = 1;
    devnet.selection_interval = 1;
    let (ours, theirs) = (
        mt_account::genesis_state_hash(p),
        mt_account::genesis_state_hash(&devnet),
    );
    assert_ne!(ours, theirs);
    let (theirs8, ours8) = (hex_lower(&theirs[..8]), hex_lower(&ours[..8]));
    let named = ["another network", theirs8.as_str(), ours8.as_str()];
    let foreign = |window: u64, tables: &LocalState| {
        let clock = TimeChainState {
            t_r: t_r_of(window),
            current_d: D,
            last_window: window,
        };
        crate::window_record::record_of(window, tables, &clock, Vec::new(), &devnet)
    };
    for (tag, window, tables) in [
        ("another-network-zero", 0, LocalState::bootstrap(me, p)),
        ("another-network", W - 1, f.tables()),
    ] {
        let dir = temp_data_dir(tag);
        let record = foreign(window, &tables);
        assert_eq!(record.genesis_state_hash, theirs);
        std::fs::write(dir.join(WINDOW_RECORD_FILE), record.encode()).expect("write");
        refused_and_left(&f, &dir, me, &named);
        let _ = std::fs::remove_dir_all(&dir);
    }

    let dir = f.store_at_w_minus_1("another-network-turn");
    let node = Node::start(&f, &dir, me);
    let record = foreign(W - 1, &f.tables());
    std::fs::write(dir.join(WINDOW_RECORD_FILE), record.encode()).expect("write");
    let lifecycle = crate::node_lifecycle::load_or_init_lifecycle(&dir, me, p).expect("lifecycle");
    let before = files(&dir);
    let turn = save_progress(
        &dir,
        &node.state,
        &node.timechain,
        &lifecycle,
        node.current,
        p,
    );
    assert!(
        turn.is_err_and(|e| format!("{e}").contains("another network")),
        "a running node wrote over a record of another network"
    );
    assert!(
        crate::window_record::commit(&node.store, &record, p).is_err(),
        "a record of another network was committed"
    );
    assert!(files(&dir) == before, "the store moved");
    drop(node);
    let _ = std::fs::remove_dir_all(&dir);
}

// Issue #19 K6 (b): a record of version 1 at window zero on the tables a machine of this
// network holds there — the genesis tables, with the operator's account (a new node), with the
// cohort of window zero (an opener) — starts, and is rewritten as version 2 naming this
// network. Rejects a start that keeps a record naming no network (main 8a6e7bc never names one).
#[test]
fn a_record_of_version_1_at_window_zero_on_the_tables_of_this_network_is_named_it() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let p = genesis_params();
    let mut opened = LocalState::bootstrap(me, p);
    open_window_zero(&mut opened, me);
    for (tag, tables) in [
        ("v1-genesis", genesis_tables()),
        ("v1-bootstrap", LocalState::bootstrap(me, p)),
        ("v1-opened", opened),
    ] {
        let dir = store_version_1(tag, 0, &tables);
        assert_eq!(record_bytes(&dir)[4], 1, "{tag}: not a record of version 1");
        let node = Node::start(&f, &dir, me);
        assert_eq!(node.held(), (0, root(&tables)), "{tag}");
        drop(node);
        let bytes = record_bytes(&dir);
        assert_eq!(bytes[4], 2, "{tag}: the record was not rewritten");
        let record = WindowRecord::decode(&bytes).expect("a record of version 2");
        assert_eq!(
            record.genesis_state_hash,
            mt_account::genesis_state_hash(p),
            "{tag}"
        );
        assert_eq!(
            (record.window, record.state_root()),
            (0, root(&tables)),
            "{tag}"
        );
        // Named once: the next start reads it as it stands.
        assert_eq!(
            Node::start(&f, &dir, me).held(),
            (0, root(&tables)),
            "{tag}"
        );
        assert!(
            record_bytes(&dir) == bytes,
            "{tag}: the second start rewrote the record"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}

// Issue #19 K6 (c): a record of version 1 at window zero on other tables (another operator's
// account, the three active nodes of the fixture, a balance) is refused: it names no network
// and its tables are not those of this network at window zero. The store is left as it was.
// Rejects a start that names any record of version 1 this network's.
#[test]
fn a_record_of_version_1_at_window_zero_on_other_tables_is_refused() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let p = genesis_params();
    let mut rich = LocalState::bootstrap(me, p);
    let mut account = rich
        .accounts
        .get(&me.account_id())
        .expect("own account")
        .clone();
    account.balance = 1_000_000;
    rich.accounts.insert(account);
    for (tag, tables) in [
        ("v1-another-operator", LocalState::bootstrap(&f.ids[1], p)),
        ("v1-fixture", f.tables()),
        ("v1-rich", rich),
    ] {
        let dir = store_version_1(tag, 0, &tables);
        refused_and_left(
            &f,
            &dir,
            me,
            &["(version 1) at window 0: it names no network", "state_root"],
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}

// (e) Rejects a start on a record it cannot vouch for: a record cut short by one byte, or with
// one byte flipped, is refused, and the store is left as it was.
#[test]
fn a_torn_or_flipped_record_is_refused() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let whole = {
        let dir = f.store_at_w_minus_1("whole");
        let bytes = record_bytes(&dir);
        let _ = std::fs::remove_dir_all(&dir);
        bytes
    };
    let mut flipped = whole.clone();
    flipped[200] ^= 0x01;
    let mut last_flipped = whole.clone();
    *last_flipped.last_mut().unwrap() ^= 0x80;
    for (name, bytes) in [
        ("cut by one byte", whole[..whole.len() - 1].to_vec()),
        ("cut to its head", whole[..96].to_vec()),
        ("one table byte flipped", flipped),
        ("one checksum byte flipped", last_flipped),
    ] {
        let dir = f.store_at_w_minus_1("torn");
        std::fs::write(dir.join(WINDOW_RECORD_FILE), &bytes).expect("write");
        let before = files(&dir);
        let got = Node::try_start(&f, &dir, me);
        assert!(got.is_err(), "{name}: the node started");
        assert!(
            files(&dir) == before,
            "{name}: a refused start wrote to the store"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}

// What moves in memory without a window (the node's own registration in the pool) is
// committed by the end of the turn and survives a restart; a turn that moved nothing writes
// nothing.
#[test]
fn a_turn_commits_what_moved_and_writes_nothing_when_nothing_moved() {
    let f = Fixture::new();
    let me = &f.ids[0];
    let dir = f.store_at_w_minus_1("turn");
    let mut node = Node::start(&f, &dir, me);
    let lifecycle = crate::node_lifecycle::load_or_init_lifecycle(&dir, me, genesis_params())
        .expect("lifecycle");
    fault::fail_at(None);
    let p = genesis_params();
    save_progress(
        &dir,
        &node.state,
        &node.timechain,
        &lifecycle,
        node.current,
        p,
    )
    .expect("turn");
    assert_eq!(
        fault::done(),
        0,
        "a turn that moved nothing wrote the record or a view"
    );
    let before = record_bytes(&dir);
    node.state.candidates.insert(mt_state::CandidateRecord {
        node_id: [0x99; 32],
        node_pubkey: [0x99; mt_crypto::PUBLIC_KEY_SIZE],
        suite_id: 1,
        operator_account_id: [0x99; 32],
        proof_endpoint: [0x99; 32],
        w_start: 1,
        ssha_chain_length: 7,
        registration_window: W,
        expires: W + 100,
    });
    save_progress(
        &dir,
        &node.state,
        &node.timechain,
        &lifecycle,
        node.current,
        p,
    )
    .expect("turn");
    assert!(
        record_bytes(&dir) != before,
        "a moved pool was not committed"
    );
    let held = node.held();
    let moved = record_bytes(&dir);
    drop(node);
    let node = Node::start(&f, &dir, me);
    assert_eq!(node.held(), held, "the pool is lost on a restart");
    // A record of another window under a running node is not written over.
    let foreign =
        crate::window_record::record_of(W + 3, &f.tables(), &node.timechain, Vec::new(), p);
    crate::window_record::commit(&node.store, &foreign, p).expect("a foreign record");
    let foreign_bytes = record_bytes(&dir);
    assert!(
        save_progress(
            &dir,
            &node.state,
            &node.timechain,
            &lifecycle,
            node.current,
            p
        )
        .is_err(),
        "a record of another window was written over"
    );
    assert!(record_bytes(&dir) == foreign_bytes && foreign_bytes != moved);
    drop(node);
    let _ = std::fs::remove_dir_all(&dir);
}
