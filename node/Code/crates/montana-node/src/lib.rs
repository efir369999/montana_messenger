pub mod clock;
pub mod commands;
pub mod identity;
/// Слой имён на узле. Подсистема ВЫКЛЮЧЕНА по умолчанию: пока не проверена вживую,
/// узел ведёт себя ровно как прежде.
pub mod names;
pub mod network;
pub mod node_lifecycle;
/// Плоскость пользовательских операций. Приёмник ВЫКЛЮЧЕН по умолчанию и состояние не меняет.
pub mod ops;
pub mod state;
pub mod timechain_state;

pub use clock::{
    current_window_path, ensure_current_window_initialized, load_current_window,
    save_current_window,
};
pub use identity::{
    default_data_dir, identity_path, load_identity, save_identity, Identity, NodeError,
    IDENTITY_FILE_SIZE, IDENTITY_MAGIC, IDENTITY_VERSION,
};
pub use state::LocalState;
