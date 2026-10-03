#![allow(deprecated)] // exercises the deprecated legacy XK libp2p path on purpose
//! libp2p custom upgrade for the Noise_PQ post-quantum handshake.
//!
//! Wraps mt_noise_pq's drive functions in the libp2p UpgradeInfo +
//! {Inbound,Outbound}ConnectionUpgrade traits so the handshake can replace
//! `noise::Config::new` in `transport::build_swarm_with_keypair`'s upgrade
//! chain.
//!
//! Output: `(libp2p::PeerId, NoisePqStream<C>)`. The PeerId is derived as a
//! SHA-256 multihash over the peer's authenticated ML-DSA-65 identity
//! public key — `PeerId::from_multihash(Multihash::wrap(0x12, sha256(ml_dsa_pk)))`.
//! Multihash code 0x12 = sha2-256 (standard libp2p IPFS convention).

use futures::{AsyncRead, AsyncWrite};
use libp2p::core::upgrade::{InboundConnectionUpgrade, OutboundConnectionUpgrade, UpgradeInfo};
use libp2p::identity::PeerId;
use mt_crypto::PublicKey as MtPublicKey;
use mt_noise_pq::libp2p_upgrade::{
    initiator_drive, responder_drive, NoisePqInitiatorConfig, NoisePqResponderConfig, UpgradeError,
    PROTOCOL_NAME,
};
use mt_noise_pq::stream::NoisePqStream;
use sha2::{Digest, Sha256};
use std::future::Future;
use std::pin::Pin;

/// Multihash code 0x12 — sha2-256 (libp2p / IPFS standard for peer identifiers).
const MULTIHASH_CODE_SHA2_256: u64 = 0x12;

/// [I-16]: post-quantum identity — NOT an admission place (contrast A-1 ed25519 Swarm key).
/// Convert an ML-DSA-65 public key into a libp2p PeerId. The PeerId is the
/// SHA-256 multihash of the public key bytes — a stable, deterministic
/// mapping from Montana's post-quantum identity to libp2p's routing identifier.
pub fn derive_peer_id(ml_dsa_pk: &MtPublicKey) -> Result<PeerId, UpgradeError> {
    let digest: [u8; 32] = Sha256::digest(ml_dsa_pk.as_bytes()).into();
    let mh: multihash::Multihash<64> = multihash::Multihash::wrap(MULTIHASH_CODE_SHA2_256, &digest)
        .map_err(|e| {
            UpgradeError::Io(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("multihash wrap: {e}"),
            ))
        })?;
    PeerId::from_multihash(mh).map_err(|_| {
        UpgradeError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "PeerId::from_multihash rejected",
        ))
    })
}

/// Local newtype wrapper around `NoisePqInitiatorConfig` enabling libp2p
/// upgrade-trait impls. Required because both the trait and the wrapped
/// config type are foreign to this crate.
#[deprecated(
    note = "non-production legacy path; use xx_noise_pq_upgrade::NoisePqXxConfig (Noise_PQ XX)"
)]
pub struct NoisePqInitiatorUpgrade(pub NoisePqInitiatorConfig);

/// Local newtype wrapper around `NoisePqResponderConfig` for the inbound side.
#[deprecated(
    note = "non-production legacy path; use xx_noise_pq_upgrade::NoisePqXxConfig (Noise_PQ XX)"
)]
pub struct NoisePqResponderUpgrade(pub NoisePqResponderConfig);

impl UpgradeInfo for NoisePqInitiatorUpgrade {
    type Info = &'static str;
    type InfoIter = std::iter::Once<&'static str>;
    fn protocol_info(&self) -> Self::InfoIter {
        std::iter::once(PROTOCOL_NAME)
    }
}

impl UpgradeInfo for NoisePqResponderUpgrade {
    type Info = &'static str;
    type InfoIter = std::iter::Once<&'static str>;
    fn protocol_info(&self) -> Self::InfoIter {
        std::iter::once(PROTOCOL_NAME)
    }
}

impl<C> OutboundConnectionUpgrade<C> for NoisePqInitiatorUpgrade
where
    C: AsyncRead + AsyncWrite + Send + Unpin + 'static,
{
    type Output = (PeerId, NoisePqStream<C>);
    type Error = UpgradeError;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Output, Self::Error>> + Send>>;

    fn upgrade_outbound(self, socket: C, _info: Self::Info) -> Self::Future {
        Box::pin(async move {
            let (remote_id, stream) = initiator_drive(socket, self.0).await?;
            let pid = derive_peer_id(&remote_id.mldsa65_pubkey)?;
            Ok((pid, stream))
        })
    }
}

impl<C> InboundConnectionUpgrade<C> for NoisePqResponderUpgrade
where
    C: AsyncRead + AsyncWrite + Send + Unpin + 'static,
{
    type Output = (PeerId, NoisePqStream<C>);
    type Error = UpgradeError;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Output, Self::Error>> + Send>>;

    fn upgrade_inbound(self, socket: C, _info: Self::Info) -> Self::Future {
        Box::pin(async move {
            let (remote_id, stream) = responder_drive(socket, self.0).await?;
            let pid = derive_peer_id(&remote_id.mldsa65_pubkey)?;
            Ok((pid, stream))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair_from_seed, KEYPAIR_SEED_SIZE};

    #[test]
    fn derive_peer_id_is_deterministic() {
        let (pk, _sk) = keypair_from_seed(&[0x11u8; KEYPAIR_SEED_SIZE]).unwrap();
        let pid1 = derive_peer_id(&pk).unwrap();
        let pid2 = derive_peer_id(&pk).unwrap();
        assert_eq!(pid1, pid2);
    }

    #[test]
    fn derive_peer_id_distinguishes_keys() {
        let (pk1, _) = keypair_from_seed(&[0x11u8; KEYPAIR_SEED_SIZE]).unwrap();
        let (pk2, _) = keypair_from_seed(&[0x22u8; KEYPAIR_SEED_SIZE]).unwrap();
        assert_ne!(derive_peer_id(&pk1).unwrap(), derive_peer_id(&pk2).unwrap());
    }

    #[test]
    fn upgrade_info_matches_protocol_name() {
        // Initiator upgrade exposes the canonical /montana/noise-pq/1.0.0 protocol.
        let dummy_kem_pk_bytes = [0x42u8; mt_crypto::MLKEM_PUBLIC_KEY_SIZE];
        let dummy_kem_pk = mt_crypto::MlkemPublicKey::from_array(dummy_kem_pk_bytes);
        let (id_pk, id_sk) = keypair_from_seed(&[0x33u8; KEYPAIR_SEED_SIZE]).unwrap();
        let cfg = NoisePqInitiatorConfig {
            remote_static_kem_pk: dummy_kem_pk,
            local_id_pk: id_pk,
            local_id_sk: id_sk,
        };
        let upgrade = NoisePqInitiatorUpgrade(cfg);
        let mut iter = upgrade.protocol_info();
        assert_eq!(iter.next(), Some("/montana/noise-pq/1.0.0"));
        assert_eq!(iter.next(), None);
    }
}
