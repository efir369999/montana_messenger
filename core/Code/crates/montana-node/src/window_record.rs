//! Issue #19 K5: the window record of the node — the one truth of the window it applied.
//!
//! A settle and a fast sync each end in one record (`mt_store::WindowRecord`, `window.bin`)
//! written whole: the window, the clock, the three tables and, for a settle, the cemented
//! envelope of the window. Memory takes the new window only after the record stands.
//!
//! The earlier files stay as views for the readers (`status`, `time`, the archive readers of
//! mt-store): accounts.bin, nodes.bin, candidates.bin, meta_last_cemented.bin,
//! meta/current_window.bin, meta/timechain.bin and proposals/<window>.bin. They are written
//! after the record and `start` never reads them back as truth, except once, to migrate a
//! store that has no record yet.

use std::path::Path;

use mt_crypto::Hash32;
use mt_genesis::ProtocolParams;
use mt_state::compute_state_root;
use mt_store::{FsStore, WindowHead, WindowRecord, WINDOW_RECORD_FILE};

use crate::clock::{load_current_window, save_current_window};
use crate::identity::{Identity, NodeError};
use crate::state::LocalState;
use crate::timechain_state::{load_or_init_timechain, save_timechain, TimeChainState};

// The state_root of a cemented envelope: bytes 172..204 of its 3722-byte header
// (mt-store, decode_proposal_header).
const HEADER_SIZE: usize = mt_consensus::PROPOSAL_HEADER_SIZE;
const STATE_ROOT_AT: usize = 172;

fn store_error(what: &str) -> impl Fn(mt_store::StoreError) -> NodeError + '_ {
    move |e| NodeError::InvalidArguments(format!("{what}: {e:?}"))
}

/// The commit point: the record written whole and flushed. Nothing else is written.
pub fn commit(store: &FsStore, record: &WindowRecord) -> Result<(), NodeError> {
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

/// The record of what a node holds in memory.
pub fn record_of(
    window: u64,
    state: &LocalState,
    clock: &TimeChainState,
    envelope: Vec<u8>,
) -> WindowRecord {
    WindowRecord {
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

/// What start takes as truth: the record. A store without one is migrated once from the
/// earlier layout when that layout holds one window; otherwise the node does not start.
/// `opening` (issue #17 K5, --open on a store holding nothing of a chain): the cohort of
/// window zero enters the tables before the first record is committed, so the record of
/// window zero never stands without it; a store that already holds a record is refused.
pub fn open(
    data_dir: &Path,
    operator: &Identity,
    params: &ProtocolParams,
    opening: bool,
) -> Result<(LocalState, u64, TimeChainState), NodeError> {
    let store = FsStore::open(data_dir).map_err(store_error("opening storage"))?;
    let record = match store.load_window_record() {
        Ok(Some(_)) if opening => {
            return Err(NodeError::InvalidArguments(
                crate::commands::start::OPENED_OVER_A_CHAIN.into(),
            ))
        },
        Ok(Some(record)) => record,
        Ok(None) => {
            let mut record = from_earlier_layout(&store, data_dir, operator, params)?;
            if opening {
                let (mut state, window, clock, envelope) = into_parts(record);
                crate::commands::start::open_window_zero(&mut state, operator);
                record = record_of(window, &state, &clock, envelope);
            }
            commit(&store, &record)?;
            record
        },
        Err(e) => {
            return Err(NodeError::InvalidArguments(format!(
                "{}: {e:?}; the node does not start on a record it cannot read",
                data_dir.join(WINDOW_RECORD_FILE).display()
            )))
        },
    };
    let (state, window, clock, envelope) = into_parts(record);
    write_views(&store, data_dir, window, &state, &clock, &envelope)?;
    Ok((state, window, clock))
}

/// The earlier layout as one record, if it holds one window: meta/current_window.bin and
/// meta_last_cemented.bin name the same window and, above window zero, the envelope of that
/// window is archived and the tables give the state_root its header names. A store holding
/// none of the earlier files is a new node: the genesis tables at window zero.
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
    let envelope = store
        .load_proposal_envelope(current)
        .map_err(store_error("loading the archived envelope"))?
        .unwrap_or_default();
    // Main f1a5fada swallowed a failed archive write and wrote current_window and
    // meta_last_cemented before the tables, so a window above zero without its envelope may
    // stand on the tables of the window before: nothing here can check them.
    if current > 0 && envelope.is_empty() {
        return Err(NodeError::InvalidArguments(format!(
            "the earlier layout of {} at window {current}: the envelope of that window is not \
             archived, so its tables cannot be checked against a state_root; the node does not \
             start on it (re-sync this node)",
            data_dir.display()
        )));
    }
    if !envelope.is_empty() {
        if envelope.len() < HEADER_SIZE {
            return Err(NodeError::InvalidArguments(format!(
                "the earlier layout of {}: the archived envelope of window {current} is {} bytes, \
                 shorter than a header; the node does not start on it",
                data_dir.display(),
                envelope.len()
            )));
        }
        let mut named: Hash32 = [0u8; 32];
        named.copy_from_slice(&envelope[STATE_ROOT_AT..STATE_ROOT_AT + 32]);
        let held = compute_state_root(
            &state.nodes.root(),
            &state.candidates.root(),
            &state.accounts.root(),
        );
        if held != named {
            return Err(NodeError::InvalidArguments(format!(
                "the earlier layout of {} at window {current}: the tables give state_root {}, \
                 the archived envelope of that window names {}; the node does not start on it",
                data_dir.display(),
                hex8(&held),
                hex8(&named)
            )));
        }
    }
    let clock = load_or_init_timechain(data_dir)?;
    Ok(record_of(current, &state, &clock, envelope))
}

/// A running node whose memory moved from its last record without a window (its own
/// registration in the pool, a clock turn) commits the record of its memory and writes the
/// views; when nothing moved, nothing is written.
pub fn commit_if_moved(
    data_dir: &Path,
    window: u64,
    state: &LocalState,
    clock: &TimeChainState,
) -> Result<(), NodeError> {
    let store = FsStore::open(data_dir).map_err(store_error("opening storage"))?;
    let now = WindowHead {
        window,
        t_r: clock.t_r,
        current_d: clock.current_d,
        last_window: clock.last_window,
        state_root: compute_state_root(
            &state.nodes.root(),
            &state.candidates.root(),
            &state.accounts.root(),
        ),
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
    let record = record_of(window, state, clock, envelope);
    commit(&store, &record)?;
    write_views(&store, data_dir, window, state, clock, &record.envelope)
}

fn hex8(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(16);
    for b in &bytes[..8] {
        s.push_str(&format!("{b:02x}"));
    }
    s
}
