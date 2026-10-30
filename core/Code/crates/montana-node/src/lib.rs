pub mod clock;
pub mod commands;
pub mod diagnostics;
/// The holder of a data directory: a running node, by a lock on it (issue #21 K4).
pub mod holder;
pub mod identity;
/// Name layer on the node. The subsystem is OFF by default: until verified live,
/// the node behaves exactly as before.
pub mod names;
pub mod network;
pub mod node_lifecycle;
/// User-operations plane. The receiver is OFF by default and does not change state.
pub mod ops;
pub mod reading;
pub mod state;
pub mod timechain_state;
/// The window record: the one truth of the window a node applied (issue #19 K5).
pub mod window_record;

pub use clock::{
    current_window_path, ensure_current_window_initialized, load_current_window,
    save_current_window,
};
pub use identity::{
    default_data_dir, identity_path, load_identity, save_identity, Identity, NodeError,
    IDENTITY_FILE_SIZE, IDENTITY_MAGIC, IDENTITY_VERSION,
};
pub use state::LocalState;
