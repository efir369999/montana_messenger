//! libp2p custom upgrade for the Noise_PQ XX-pattern handshake.
//!
//! Single config type implements both `InboundConnectionUpgrade` and
//! `OutboundConnectionUpgrade` — XX discovers remote identity during the
//! handshake, so the same upgrade serves dial-side and accept-side.
//!
//! Output: `(libp2p::PeerId, NoisePqStream<C>)`. PeerId derived as
//! SHA-256 multihash over the peer's authenticated ML-DSA-65 identity pk
//! (libp2p / IPFS sha2-256 multihash code 0x12).

use futures::future::BoxFuture;
use futures::{AsyncRead, AsyncWrite};
use libp2p::core::upgrade::{InboundConnectionUpgrade, OutboundConnectionUpgrade, UpgradeInfo};
use libp2p::identity::PeerId;
use mt_crypto::{PublicKey as MtPublicKey, SecretKey as MtSecretKey};
use mt_noise_pq::stream::NoisePqStream;
use mt_noise_pq::xx_libp2p_upgrade::{
    xx_initiator_drive, xx_responder_drive, XxUpgradeError, XX_PROTOCOL_NAME,
};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use std::time::Duration;

const MULTIHASH_CODE_SHA2_256: u64 = 0x12;
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);

/// Derive a libp2p PeerId from an ML-DSA-65 public key.
pub fn derive_peer_id(ml_dsa_pk: &MtPublicKey) -> Result<PeerId, XxUpgradeError> {
    let digest: [u8; 32] = Sha256::digest(ml_dsa_pk.as_bytes()).into();
    let mh: multihash::Multihash<64> = multihash::Multihash::wrap(MULTIHASH_CODE_SHA2_256, &digest)
        .map_err(|e| {
            XxUpgradeError::Io(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("multihash wrap: {e}"),
            ))
        })?;
    PeerId::from_multihash(mh).map_err(|_| {
        XxUpgradeError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "PeerId::from_multihash rejected",
        ))
    })
}

/// Unified Noise_PQ XX upgrade config. Cloneable so libp2p can reuse it
/// across multiple connections.
#[derive(Clone)]
pub struct NoisePqXxConfig {
    id_pk: Arc<MtPublicKey>,
    id_sk: Arc<MtSecretKey>,
}

impl NoisePqXxConfig {
    pub fn new(id_pk: MtPublicKey, id_sk: MtSecretKey) -> Self {
        NoisePqXxConfig {
            id_pk: Arc::new(id_pk),
            id_sk: Arc::new(id_sk),
        }
    }
}

impl UpgradeInfo for NoisePqXxConfig {
    type Info = &'static str;
    type InfoIter = std::iter::Once<Self::Info>;
    fn protocol_info(&self) -> Self::InfoIter {
        std::iter::once(XX_PROTOCOL_NAME)
    }
}

impl<C> InboundConnectionUpgrade<C> for NoisePqXxConfig
where
    C: AsyncRead + AsyncWrite + Send + Unpin + 'static,
{
    type Output = (PeerId, NoisePqStream<C>);
    type Error = XxUpgradeError;
    type Future = BoxFuture<'static, Result<Self::Output, Self::Error>>;

    fn upgrade_inbound(self, socket: C, _: Self::Info) -> Self::Future {
        let id_pk = (*self.id_pk).clone();
        let id_sk = Arc::clone(&self.id_sk);
        Box::pin(async move {
            let fut = xx_responder_drive(socket, id_pk, id_sk);
            let (session, stream) = tokio::time::timeout(HANDSHAKE_TIMEOUT, fut)
                .await
                .map_err(|_| {
                    XxUpgradeError::Io(std::io::Error::new(
                        std::io::ErrorKind::TimedOut,
                        "Noise_PQ XX inbound handshake exceeded HANDSHAKE_TIMEOUT",
                    ))
                })??;
            let pid = derive_peer_id(&session.remote_id_pk)?;
            Ok((pid, stream))
        })
    }
}

impl<C> OutboundConnectionUpgrade<C> for NoisePqXxConfig
where
    C: AsyncRead + AsyncWrite + Send + Unpin + 'static,
{
    type Output = (PeerId, NoisePqStream<C>);
    type Error = XxUpgradeError;
    type Future = BoxFuture<'static, Result<Self::Output, Self::Error>>;

    fn upgrade_outbound(self, socket: C, _: Self::Info) -> Self::Future {
        let id_pk = (*self.id_pk).clone();
        let id_sk = Arc::clone(&self.id_sk);
        Box::pin(async move {
            let fut = xx_initiator_drive(socket, id_pk, id_sk);
            let (session, stream) = tokio::time::timeout(HANDSHAKE_TIMEOUT, fut)
                .await
                .map_err(|_| {
                    XxUpgradeError::Io(std::io::Error::new(
                        std::io::ErrorKind::TimedOut,
                        "Noise_PQ XX outbound handshake exceeded HANDSHAKE_TIMEOUT",
                    ))
                })??;
            let pid = derive_peer_id(&session.remote_id_pk)?;
            Ok((pid, stream))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair_from_seed, KEYPAIR_SEED_SIZE};

    #[test]
    fn protocol_name_matches_montana_namespace() {
        let (pk, sk) = keypair_from_seed(&[0x33u8; KEYPAIR_SEED_SIZE]).unwrap();
        let cfg = NoisePqXxConfig::new(pk, sk);
        let mut iter = cfg.protocol_info();
        assert_eq!(iter.next(), Some(XX_PROTOCOL_NAME));
        assert_eq!(iter.next(), None);
    }

    #[test]
    fn derive_peer_id_deterministic_and_distinct() {
        let (pk1, _) = keypair_from_seed(&[0x44u8; KEYPAIR_SEED_SIZE]).unwrap();
        let (pk2, _) = keypair_from_seed(&[0x55u8; KEYPAIR_SEED_SIZE]).unwrap();
        let pid1a = derive_peer_id(&pk1).unwrap();
        let pid1b = derive_peer_id(&pk1).unwrap();
        let pid2 = derive_peer_id(&pk2).unwrap();
        assert_eq!(pid1a, pid1b);
        assert_ne!(pid1a, pid2);
    }
}
