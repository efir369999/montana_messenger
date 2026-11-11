//! mt-postman -- flat TCP+TLS transport of the postman (Montana P2P Network, Stage 1;
//! spec §152 -- TCP/TLS-443 is mandatory, operators cut non-443 UDP).
//!
//! The postman server accepts TCP+TLS connections, runs the prologue handshake
//! (RegHello/RegChallenge/RegProof, ML-DSA-65 -- mt-overlay::prologue/challenge) and
//! routes OverlayFrame by overlay_addr (RELAY->DELIVER/Buffer, ACK -- Postman).
//! The transport hop is TCP+TLS 1.3 (admission wrapper A-3 per [I-16]); the real security is the
//! opaque E2E payload + the ML-DSA registration signature. Not consensus state.

pub mod client;
pub mod config;
pub mod muq;
pub mod muq_client;
pub mod node;
pub mod path;
pub mod server;
pub mod wire;

pub use client::{ClientError, PostmanClient};
pub use config::{stand_client_config, stand_server_config, ConfigError, STAND_SNI};
pub use muq::{MuqState, TAG_HOST_DEPOSIT};
pub use muq_client::{node_hello, MuqClient};
pub use node::Node;
pub use server::{PostmanServer, ServerError};
pub use wire::WireError;
