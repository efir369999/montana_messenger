//! Montana M7 fast-sync — snapshot-based state delivery for new operators
//! joining a long-running mesh.
//!
//! Wire-format messages (registered in `mt_net::MsgType`):
//!   - `FastSyncRequest`  (0x40, 16 B) — request anchored at a window
//!   - `FastSyncResponse` (0x41, chunked) — snapshot delivery
//!   - `FastSyncError`    (0x42)        — error response
//!
//! Anchor: the server side delivers the snapshot at the state of a specific
//! window `W`; the client side verifies the snapshot's reconstructed
//! `state_root` byte-equals the proposer's `state_root` for window `W`
//! recorded in the proposer's archived ProposalHeader, which the client
//! independently retrieves from any honest peer via the standard Proposal
//! propagation path.
//!
//! Without M7, a fresh operator joining a mesh at window `W` must process
//! `W` apply_proposal iterations (~6 minutes per 1000 windows on 1 vCPU).
//! With M7, the operator receives the entire state in chunked delivery
//! over the existing Noise_PQ XX session — bounded by network bandwidth,
//! not by CPU iteration count.

pub mod client;
pub mod request;
pub mod response;
pub mod snapshot;

pub use client::{AcceptOutcome, FastSyncClient, FastSyncClientError};
pub use request::FastSyncRequest;
pub use response::{FastSyncChunk, FastSyncResponse, FastSyncTableId};
pub use snapshot::{Snapshot, SnapshotError, SnapshotVerifier};

/// Per spec line 964–970 of `Montana Network v1.1.0.md`.
pub const FAST_SYNC_REQUEST_SIZE: usize = 16;
pub const FAST_SYNC_CHUNK_HEADER_SIZE: usize = 4 + 4 + 1 + 4; // chunk_index + total_chunks + table_id + record_count
