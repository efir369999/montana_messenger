// Transport build helper для libp2p Swarm с Noise_PQ + Yamux.
//
// Spec section "Connection lifecycle":
//   TCP SYN → Noise_PQ XX handshake (ML-KEM-768 + ML-DSA-65) → Yamux
//
// Production transport — post-quantum через Noise_PQ XX pattern. Без TLS 1.3,
// без classical Noise. ML-DSA-65 ID signature + ML-KEM-768 ephemeral KEM на
// обе стороны handshake — identity discovered during the handshake.
//
// Step 4-5 (IBT proof + access level) — см. ibt_upgrade::classify_proof.

use libp2p::{tcp, yamux, Multiaddr, Swarm, SwarmBuilder};

use crate::error::TransportError;
use crate::xx_noise_pq_upgrade::NoisePqXxConfig;
use mt_crypto::{PublicKey as MtPublicKey, SecretKey as MtSecretKey};

pub struct NetworkConfig {
    pub listen_addrs: Vec<Multiaddr>,
    pub max_inbound: u32,
    pub max_outbound: u32,
}

impl NetworkConfig {
    pub fn defaults() -> Self {
        NetworkConfig {
            listen_addrs: Vec::new(),
            max_inbound: 13,
            max_outbound: 24,
        }
    }
}

/// Build a libp2p Swarm with a randomly-generated libp2p transport keypair
/// (suitable for unit tests). Production code paths must use
/// `build_swarm_with_keypair` so the local PeerId is stable across restarts.
///
/// `mldsa_id_pk` + `mldsa_id_sk` provide the Montana ML-DSA-65 identity
/// used by the Noise_PQ XX handshake to authenticate this side of every
/// connection.
pub fn build_swarm<B>(
    behaviour: B,
    config: &NetworkConfig,
    mldsa_id_pk: MtPublicKey,
    mldsa_id_sk: MtSecretKey,
) -> Result<Swarm<B>, TransportError>
where
    B: libp2p::swarm::NetworkBehaviour + Send,
{
    let xx_config = NoisePqXxConfig::new(mldsa_id_pk, mldsa_id_sk);
    let mut swarm = SwarmBuilder::with_new_identity()
        .with_tokio()
        .with_tcp(
            tcp::Config::default(),
            move |_libp2p_kp: &libp2p::identity::Keypair| -> Result<NoisePqXxConfig, std::convert::Infallible> {
                Ok(xx_config.clone())
            },
            yamux::Config::default,
        )
        .map_err(|e| TransportError::Setup(format!("transport upgrade: {e}")))?
        .with_behaviour(|_| behaviour)
        .map_err(|e| TransportError::Setup(format!("behaviour: {e}")))?
        .build();

    for addr in &config.listen_addrs {
        swarm
            .listen_on(addr.clone())
            .map_err(|e| TransportError::Setup(format!("listen_on {addr}: {e}")))?;
    }
    Ok(swarm)
}

/// [I-16] admission A-1: Ed25519 keypair — формальный SwarmBuilder book-keeping, НЕ
/// Montana-identity (та — ML-DSA-65 `derive_peer_id`; manifest peer_id = ML-DSA).
/// Build a libp2p Swarm pinned to a specific local Ed25519 transport keypair
/// (production: derived deterministically from the operator's identity so the
/// PeerId is reproducible).
///
/// Noise_PQ XX is the security upgrade — ML-DSA-65 identity is authenticated
/// in the handshake, derived PeerId is the SHA-256 multihash of the remote's
/// ML-DSA-65 public key.
pub fn build_swarm_with_keypair<B>(
    keypair: libp2p::identity::Keypair,
    behaviour: B,
    config: &NetworkConfig,
    mldsa_id_pk: MtPublicKey,
    mldsa_id_sk: MtSecretKey,
) -> Result<Swarm<B>, TransportError>
where
    B: libp2p::swarm::NetworkBehaviour + Send,
{
    let xx_config = NoisePqXxConfig::new(mldsa_id_pk, mldsa_id_sk);
    let mut swarm = SwarmBuilder::with_existing_identity(keypair)
        .with_tokio()
        .with_tcp(
            tcp::Config::default(),
            move |_libp2p_kp: &libp2p::identity::Keypair| -> Result<NoisePqXxConfig, std::convert::Infallible> {
                Ok(xx_config.clone())
            },
            yamux::Config::default,
        )
        .map_err(|e| TransportError::Setup(format!("transport upgrade: {e}")))?
        .with_behaviour(|_| behaviour)
        .map_err(|e| TransportError::Setup(format!("behaviour: {e}")))?
        .with_swarm_config(|c| c.with_idle_connection_timeout(std::time::Duration::from_secs(60)))
        .build();

    for addr in &config.listen_addrs {
        swarm
            .listen_on(addr.clone())
            .map_err(|e| TransportError::Setup(format!("listen_on {addr}: {e}")))?;
    }
    Ok(swarm)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_spec() {
        let c = NetworkConfig::defaults();
        assert_eq!(c.max_outbound, 24);
        assert_eq!(c.max_inbound, 13);
    }
}
