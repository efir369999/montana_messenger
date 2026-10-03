// mt-net-transport — libp2p-based async transport для Montana protocol M6.
//
// Архитектурный layer per spec section "Сетевой уровень → Connection lifecycle":
//   TCP → TLS 1.3 → Noise → IBT proof exchange → ProtocolMessage envelope
//
// Этот crate изолирует heavy dep tree (libp2p ~120 transitive) от no_std
// ядра mt-net. iOS bridge через FFI к no_std функциям envelope/payloads/ibt/pow
// без включения transport layer (iOS использует Network.framework + NetworkExtension
// через свой собственный bridge).

pub mod behaviour;
pub mod codec;
pub mod error;
pub mod ibt_upgrade;
pub mod transport;

pub use behaviour::{MontanaBehaviour, MontanaBehaviourEvent};
pub use codec::{MontanaCodec, MAX_PROTOCOL_PAYLOAD_BYTES, MONTANA_PROTOCOL_NAME};
pub use error::TransportError;
pub use ibt_upgrade::{IbtAccessLevel, IbtConfig};
pub use transport::{build_swarm, build_swarm_with_keypair, NetworkConfig};

/// NON-PRODUCTION. Legacy Noise_PQ libp2p upgrade wrapper. Production transport
/// uses [`xx_noise_pq_upgrade::NoisePqXxConfig`] (Noise_PQ XX).
pub mod noise_pq_upgrade;
pub mod xx_noise_pq_upgrade;
pub use xx_noise_pq_upgrade::{derive_peer_id, NoisePqXxConfig};
