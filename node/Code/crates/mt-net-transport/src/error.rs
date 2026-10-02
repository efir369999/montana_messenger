use thiserror::Error;

#[derive(Debug, Error)]
pub enum TransportError {
    #[error("transport setup failed: {0}")]
    Setup(String),
    #[error("dial failed to {addr}: {reason}")]
    Dial { addr: String, reason: String },
    #[error("IBT handshake failed: {0}")]
    IbtFailure(String),
    #[error("connection limit reached (cap = {cap})")]
    ConnectionLimit { cap: usize },
    #[error("net error: {0}")]
    Net(mt_net::NetError),
}

impl From<mt_net::NetError> for TransportError {
    fn from(e: mt_net::NetError) -> Self {
        TransportError::Net(e)
    }
}
