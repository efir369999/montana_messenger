//! Issue #19 K5: the window record of the node — the one truth of the window it applied.
//!
//! A settle and a fast sync each end in one record (`mt_store::WindowRecord`, `window.bin`)
//! written whole: the window, the clock, the three tables and, for a settle, the cemented
//! envelope of the window. Memory takes the new window only after the record stands.
//!
//! The earlier files stay as views for the readers (`status`, `time`, the archive readers of
//! mt-store): accounts.bin, nodes.bin, candidates.bin, meta_last_cemented.bin,
//! meta/current_window.bin, meta/timechain.bin and proposals/<window>.bin. They are written
//! after the record and `start` never reads them back as truth, except once, to take a store
//! at window zero that has no record yet.
//!
//! Issue #19 K6 (the Author's decision 331a, constitution record 336): the record names its
//! network by the Genesis State Hash of the Decree (`mt_account::genesis_state_hash`). A node
//! does not start on a record of another network. A store that names no network (a record of
//! version 1, or the earlier layout) is taken at window zero only on the tables a machine of
//! this network holds there; above window zero it returns only by a fresh sync.

use std::path::Path;

use mt_crypto::Hash32;
use mt_genesis::ProtocolParams;
use mt_state::compute_state_root;
use mt_store::{FsStore, WindowHead, WindowRecord, WINDOW_RECORD_FILE};

use crate::clock::{load_current_window, save_current_window};
use crate::identity::{Identity, NodeError};
use crate::state::LocalState;
use crate::timechain_state::{load_or_init_timechain, save_timechain, TimeChainState};

fn store_error(what: &str) -> impl Fn(mt_store::StoreError) -> NodeError + '_ {
    move |e| NodeError::InvalidArguments(format!("{what}: {e:?}"))
}

/// The refusal of a record of another network: both hashes, 8 bytes each.
fn another_network(what: &str, named: &Hash32, ours: &Hash32) -> NodeError {
    NodeError::InvalidArguments(format!(
        "{what} names genesis_state_hash {}, this node runs genesis_state_hash {}: a record of \
         another network; the node does not start on it",
        hex8(named),
        hex8(ours)
    ))
}

/// The commit point: the record written whole and flushed. Nothing else is written. A record
/// that does not name this node's network is never written.
pub fn commit(
    store: &FsStore,
    record: &WindowRecord,
    params: &ProtocolParams,
) -> Result<(), NodeError> {
    let ours = mt_account::genesis_state_hash(params);
    if record.genesis_state_hash != ours {
        return Err(another_network(
            &format!("the record of window {} to commit", record.window),
            &record.genesis_state_hash,
            &ours,
        ));
    }
    store.commit_window(record).map_err(|e| {
        NodeError::InvalidArguments(format!("commit of window {}: {e:?}", record.window))
    })
}

/// The views of a record that stands, for the readers. Written after the commit only.
pub fn write_views(
    store: &FsStore,
    data_dir: &Path,
    window: u64,
    state: &LocalState,
    clock: &TimeChainState,
    envelope: &[u8],
) -> Result<(), NodeError> {
    state.save(data_dir)?;
    store
        .save_meta_last_cemented(window)
        .map_err(store_error("view meta_last_cemented"))?;
    save_current_window(data_dir, window)?;
    save_timechain(data_dir, clock)?;
    if !envelope.is_empty()
        && store
            .load_proposal_envelope(window)
            .ok()
            .flatten()
            .as_deref()
            != Some(envelope)
    {
        store
            .archive_proposal_envelope(window, envelope)
            .map_err(store_error("view proposals"))?;
    }
    Ok(())
}

/// The record of what a node holds in memory, in the network of `params`.
pub fn record_of(
    window: u64,
    state: &LocalState,
    clock: &TimeChainState,
    envelope: Vec<u8>,
    params: &ProtocolParams,
) -> WindowRecord {
    WindowRecord {
        genesis_state_hash: mt_account::genesis_state_hash(params),
        window,
        t_r: clock.t_r,
        current_d: clock.current_d,
        last_window: clock.last_window,
        accounts: state.accounts.clone(),
        nodes: state.nodes.clone(),
        candidates: state.candidates.clone(),
        envelope,
    }
}

/// A record taken apart into what start holds: the tables, the window, the clock, the envelope.
pub fn into_parts(record: WindowRecord) -> (LocalState, u64, TimeChainState, Vec<u8>) {
    (
        LocalState {
            accounts: record.accounts,
            nodes: record.nodes,
            candidates: record.candidates,
        },
        record.window,
        TimeChainState {
            t_r: record.t_r,
            current_d: record.current_d,
            last_window: record.last_window,
        },
        record.envelope,
    )
}

/// What start takes as truth: the record, when it names this node's network. A store whose
/// record names no network (version 1, or no record and the earlier layout) is taken once at
/// window zero, by `named_at_window_zero`; otherwise the node does not start. `opening`
/// (issue #17 K5, --open on a store holding nothing of a chain): the cohort of window zero
/// enters the tables before the first record is committed, so the record of window zero never
/// stands without it; a store that already holds a record is refused. A refusal writes nothing.
pub fn open(
    data_dir: &Path,
    operator: &Identity,
    params: &ProtocolParams,
    opening: bool,
) -> Result<(LocalState, u64, TimeChainState), NodeError> {
    let store = FsStore::open(data_dir).map_err(store_error("opening storage"))?;
    let ours = mt_account::genesis_state_hash(params);
    let path = data_dir.join(WINDOW_RECORD_FILE);
    let opened_over_a_chain =
        || NodeError::InvalidArguments(crate::commands::start::OPENED_OVER_A_CHAIN.into());
    let cannot_read = |e: mt_store::StoreError| {
        NodeError::InvalidArguments(format!(
            "{}: {e:?}; the node does not start on a record it cannot read",
            path.display()
        ))
    };
    let record = match store.load_window_record() {
        Ok(Some(_)) if opening => return Err(opened_over_a_chain()),
        Ok(Some(record)) if record.genesis_state_hash != ours => {
            return Err(another_network(
                &path.display().to_string(),
                &record.genesis_state_hash,
                &ours,
            ))
        },
        Ok(Some(record)) => record,
        Ok(None) => {
            let mut record = from_earlier_layout(&store, data_dir, operator, params)?;
            if opening {
                let (mut state, window, clock, envelope) = into_parts(record);
                crate::commands::start::open_window_zero(&mut state, operator);
                record = record_of(window, &state, &clock, envelope, params);
            }
            commit(&store, &record, params)?;
            record
        },
        Err(e) => match store.load_window_record_version_1() {
            Ok(None) => return Err(cannot_read(e)),
            Err(e) => return Err(cannot_read(e)),
            Ok(Some(_)) if opening => return Err(opened_over_a_chain()),
            Ok(Some(earlier)) => {
                let what = format!("{} (version 1)", path.display());
                let record = named_at_window_zero(&what, earlier, operator, params)?;
                commit(&store, &record, params)?;
                record
            },
        },
    };
    let (state, window, clock, envelope) = into_parts(record);
    write_views(&store, data_dir, window, &state, &clock, &envelope)?;
    Ok((state, window, clock))
}

/// A record that names no network, named this node's network: only at window zero, and only
/// on the tables a machine of this network holds there — the genesis tables, with this
/// operator's account as `LocalState::bootstrap` adds it, and with the cohort of window zero as
/// an opening adds it. Above window zero the tables are another network's for all this node
/// can tell, so the store returns only by a fresh sync (the Author's decision 331a).
fn named_at_window_zero(
    what: &str,
    mut record: WindowRecord,
    operator: &Identity,
    params: &ProtocolParams,
) -> Result<WindowRecord, NodeError> {
    if record.window != 0 {
        return Err(NodeError::InvalidArguments(format!(
            "{what} at window {}: it names no network, and a store of an earlier layout above \
             window zero returns only by a fresh sync; the node does not start on it (re-sync \
             this node)",
            record.window
        )));
    }
    let genesis = mt_account::build_genesis_state(params);
    let bootstrap = LocalState::bootstrap(operator, params);
    let mut opened = LocalState::bootstrap(operator, params);
    crate::commands::start::open_window_zero(&mut opened, operator);
    let held = record.state_root();
    let of_this_network = [
        mt_account::genesis_state_root(&genesis),
        root_of(&bootstrap),
        root_of(&opened),
    ];
    if !of_this_network.contains(&held) {
        return Err(NodeError::InvalidArguments(format!(
            "{what} at window 0: it names no network, and its tables give state_root {}, not the \
             tables a machine of genesis_state_hash {} holds at window zero; the node does not \
             start on it",
            hex8(&held),
            hex8(&mt_account::genesis_state_hash(params))
        )));
    }
    record.genesis_state_hash = mt_account::genesis_state_hash(params);
    Ok(record)
}

fn root_of(state: &LocalState) -> Hash32 {
    compute_state_root(
        &state.nodes.root(),
        &state.candidates.root(),
        &state.accounts.root(),
    )
}

/// The earlier layout (no record) as one record, if it holds one window and that window is
/// zero: meta/current_window.bin and meta_last_cemented.bin name the same window. A store
/// holding none of the earlier files is a new node: the genesis tables at window zero. Above
/// window zero the earlier layout is refused: it returns only by a fresh sync (issue #19 K6,
/// the Author's decision 331a; main 8a6e7bc migrated it on its archived envelope).
fn from_earlier_layout(
    store: &FsStore,
    data_dir: &Path,
    operator: &Identity,
    params: &ProtocolParams,
) -> Result<WindowRecord, NodeError> {
    let state = LocalState::load_or_bootstrap(data_dir, operator, params)?;
    let current = load_current_window(data_dir)?;
    let last_cemented = store
        .load_meta_last_cemented()
        .map_err(store_error("loading meta_last_cemented.bin"))?
        .unwrap_or(0);
    if current != last_cemented {
        return Err(NodeError::InvalidArguments(format!(
            "the earlier layout of {} holds two windows: meta/current_window.bin names {current}, \
             meta_last_cemented.bin names {last_cemented}; the node does not start on it",
            data_dir.display()
        )));
    }
    let envelope = if current == 0 {
        store
            .load_proposal_envelope(0)
            .map_err(store_error("loading the archived envelope"))?
            .unwrap_or_default()
    } else {
        Vec::new()
    };
    let clock = load_or_init_timechain(data_dir)?;
    let what = format!("the earlier layout of {}", data_dir.display());
    let record = record_of(current, &state, &clock, envelope, params);
    named_at_window_zero(&what, record, operator, params)
}

/// A running node whose memory moved from its last record without a window (its own
/// registration in the pool, a clock turn) commits the record of its memory and writes the
/// views; when nothing moved, nothing is written.
pub fn commit_if_moved(
    data_dir: &Path,
    window: u64,
    state: &LocalState,
    clock: &TimeChainState,
    params: &ProtocolParams,
) -> Result<(), NodeError> {
    let store = FsStore::open(data_dir).map_err(store_error("opening storage"))?;
    let ours = mt_account::genesis_state_hash(params);
    let now = WindowHead {
        window,
        t_r: clock.t_r,
        current_d: clock.current_d,
        last_window: clock.last_window,
        state_root: root_of(state),
        genesis_state_hash: ours,
    };
    if store.load_window_head().ok().flatten() == Some(now) {
        return Ok(());
    }
    // The envelope of the window stays with it. Memory moves to another window only through a
    // commit, so a record of another window, a missing one or one that no longer reads means the
    // store is not the one this node committed: the node stops rather than write over it.
    let held = store
        .load_window_record()
        .map_err(store_error("the window record"))?;
    let envelope = match held {
        Some(held) if held.genesis_state_hash != ours => {
            return Err(another_network(
                "the window record under a running node",
                &held.genesis_state_hash,
                &ours,
            ))
        },
        Some(held) if held.window == window => held.envelope,
        Some(held) => {
            return Err(NodeError::InvalidArguments(format!(
                "memory holds window {window}, the window record holds window {}: a window \
                 moved without its commit",
                held.window
            )))
        },
        None => {
            return Err(NodeError::InvalidArguments(format!(
                "{} is missing under a running node",
                data_dir.join(WINDOW_RECORD_FILE).display()
            )))
        },
    };
    let record = record_of(window, state, clock, envelope, params);
    commit(&store, &record, params)?;
    write_views(&store, data_dir, window, state, clock, &record.envelope)
}

fn hex8(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(16);
    for b in &bytes[..8] {
        s.push_str(&format!("{b:02x}"));
    }
    s
}
