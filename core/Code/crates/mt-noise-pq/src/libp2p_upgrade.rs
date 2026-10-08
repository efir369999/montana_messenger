#![allow(deprecated)] // this module IS the legacy XK path; external users still get the warning
//! libp2p custom upgrade integration for the Noise_PQ handshake.
//!
//! This module implements the `libp2p::core::upgrade::UpgradeInfo` +
//! `InboundConnectionUpgrade` + `OutboundConnectionUpgrade` traits so the
//! Noise_PQ post-quantum handshake can replace the existing
//! `noise::Config::new` upgrade in `mt-net-transport`'s SwarmBuilder chain.
//!
//! The upgrade output is `(NoisePqRemoteIdentity, NoisePqStream<C>)`:
//!   - `NoisePqRemoteIdentity` exposes the authenticated ML-DSA-65 public
//!     key of the peer (the Montana-level identity), independent of the
//!     libp2p PeerId machinery which uses Ed25519 for transport-level
//!     peer routing.
//!   - `NoisePqStream<C>` is the AEAD-encrypted byte stream defined in
//!     `crate::stream`; everything written / read is ChaCha20-Poly1305
//!     encrypted with the directional session keys derived in the
//!     handshake.

use crate::stream::NoisePqStream;
use crate::{
    initiator_receive_msg2, initiator_send_msg1, initiator_send_msg3, responder_receive_msg1,
    responder_receive_msg3, responder_send_msg2, NoisePqError, NOISE_PQ_MSG1_SIZE,
    NOISE_PQ_MSG2_SIZE, NOISE_PQ_MSG3_SIZE,
};
use futures::io::{AsyncReadExt, AsyncWriteExt};
use futures::AsyncRead;
use futures::AsyncWrite;
use mt_crypto::{
    MlkemPublicKey, MlkemSecretKey, PublicKey as MtPublicKey, SecretKey as MtSecretKey,
};
use std::future::Future;
use std::pin::Pin;

/// Protocol identifier for the libp2p multistream-select dialog. Selects
/// the Noise_PQ v1 handshake.
pub const PROTOCOL_NAME: &str = "/montana/noise-pq/1.0.0";

/// Authenticated remote identity returned by a Noise_PQ upgrade.
#[derive(Debug, Clone)]
pub struct NoisePqRemoteIdentity {
    /// Peer's static ML-DSA-65 identity public key, verified during the
    /// handshake transcript signature step.
    pub mldsa65_pubkey: MtPublicKey,
}

/// Initiator-side configuration: knows the responder's static ML-KEM-768
/// public key (from the IBT directory / GenesisManifest), supplies its own
/// static ML-DSA-65 identity keypair for transcript signing.
#[deprecated(
    note = "non-production legacy XK path; use xx_handshake / NoisePqXxConfig (Noise_PQ XX)"
)]
pub struct NoisePqInitiatorConfig {
    pub remote_static_kem_pk: MlkemPublicKey,
    pub local_id_pk: MtPublicKey,
    pub local_id_sk: MtSecretKey,
}

/// Responder-side configuration: holds the local static ML-KEM-768 keypair
/// (used to decapsulate the initiator's first message) and the local
/// ML-DSA-65 identity keypair for signing the transcript.
#[deprecated(
    note = "non-production legacy XK path; use xx_handshake / NoisePqXxConfig (Noise_PQ XX)"
)]
pub struct NoisePqResponderConfig {
    pub local_static_kem_sk: MlkemSecretKey,
    pub local_id_pk: MtPublicKey,
    pub local_id_sk: MtSecretKey,
}

#[derive(Debug)]
pub enum UpgradeError {
    Io(std::io::Error),
    Handshake(NoisePqError),
}

impl std::fmt::Display for UpgradeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            UpgradeError::Io(e) => write!(f, "io: {}", e),
            UpgradeError::Handshake(e) => write!(f, "handshake: {:?}", e),
        }
    }
}

impl std::error::Error for UpgradeError {}

impl From<std::io::Error> for UpgradeError {
    fn from(e: std::io::Error) -> Self {
        UpgradeError::Io(e)
    }
}

impl From<NoisePqError> for UpgradeError {
    fn from(e: NoisePqError) -> Self {
        UpgradeError::Handshake(e)
    }
}

/// Drive the initiator side of the Noise_PQ handshake over an arbitrary
/// async byte stream, then return the AEAD-wrapped stream + the
/// authenticated responder identity.
pub async fn initiator_drive<C>(
    mut socket: C,
    config: NoisePqInitiatorConfig,
) -> Result<(NoisePqRemoteIdentity, NoisePqStream<C>), UpgradeError>
where
    C: AsyncRead + AsyncWrite + Unpin,
{
    let (msg1, init_state) = initiator_send_msg1(
        &config.remote_static_kem_pk,
        config.local_id_sk,
        config.local_id_pk,
    )?;
    socket.write_all(&msg1).await?;
    socket.flush().await?;

    let mut msg2 = vec![0u8; NOISE_PQ_MSG2_SIZE];
    socket.read_exact(&mut msg2).await?;
    let init_after_msg2 = initiator_receive_msg2(&msg2, init_state)?;

    // Extract responder identity from the verified msg2 transcript.
    let rs_id_pk = extract_responder_pk_from_msg2(&msg2)?;

    let (msg3, session) = initiator_send_msg3(init_after_msg2)?;
    socket.write_all(&msg3).await?;
    socket.flush().await?;

    let stream = NoisePqStream::new(socket, session.sk_i_to_r, session.sk_r_to_i);
    Ok((
        NoisePqRemoteIdentity {
            mldsa65_pubkey: rs_id_pk,
        },
        stream,
    ))
}

/// Drive the responder side of the Noise_PQ handshake over an arbitrary
/// async byte stream, then return the AEAD-wrapped stream + the
/// authenticated initiator identity.
pub async fn responder_drive<C>(
    mut socket: C,
    config: NoisePqResponderConfig,
) -> Result<(NoisePqRemoteIdentity, NoisePqStream<C>), UpgradeError>
where
    C: AsyncRead + AsyncWrite + Unpin,
{
    let mut msg1 = vec![0u8; NOISE_PQ_MSG1_SIZE];
    socket.read_exact(&mut msg1).await?;
    let resp_state = responder_receive_msg1(
        &msg1,
        &config.local_static_kem_sk,
        config.local_id_sk,
        config.local_id_pk,
    )?;

    let (msg2, resp_after_msg2) = responder_send_msg2(resp_state)?;
    socket.write_all(&msg2).await?;
    socket.flush().await?;

    let mut msg3 = vec![0u8; NOISE_PQ_MSG3_SIZE];
    socket.read_exact(&mut msg3).await?;
    let is_id_pk = extract_initiator_pk_from_msg3(&msg3)?;
    let session = responder_receive_msg3(&msg3, resp_after_msg2)?;

    // Responder direction: tx = r_to_i, rx = i_to_r (mirror of initiator).
    let stream = NoisePqStream::new(socket, session.sk_r_to_i, session.sk_i_to_r);
    Ok((
        NoisePqRemoteIdentity {
            mldsa65_pubkey: is_id_pk,
        },
        stream,
    ))
}

fn extract_responder_pk_from_msg2(msg2: &[u8]) -> Result<MtPublicKey, UpgradeError> {
    use mt_crypto::{MLKEM_CIPHERTEXT_SIZE, PUBLIC_KEY_SIZE};
    if msg2.len() != NOISE_PQ_MSG2_SIZE {
        return Err(UpgradeError::Handshake(NoisePqError::BadMsgSize {
            expected: NOISE_PQ_MSG2_SIZE,
            actual: msg2.len(),
        }));
    }
    let pk_slice = &msg2[MLKEM_CIPHERTEXT_SIZE..MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE];
    let arr: [u8; PUBLIC_KEY_SIZE] = pk_slice
        .try_into()
        .map_err(|_| UpgradeError::Handshake(NoisePqError::InvalidPublicKey))?;
    Ok(MtPublicKey::from_array(arr))
}

fn extract_initiator_pk_from_msg3(msg3: &[u8]) -> Result<MtPublicKey, UpgradeError> {
    use mt_crypto::PUBLIC_KEY_SIZE;
    if msg3.len() != NOISE_PQ_MSG3_SIZE {
        return Err(UpgradeError::Handshake(NoisePqError::BadMsgSize {
            expected: NOISE_PQ_MSG3_SIZE,
            actual: msg3.len(),
        }));
    }
    let arr: [u8; PUBLIC_KEY_SIZE] = msg3[..PUBLIC_KEY_SIZE]
        .try_into()
        .map_err(|_| UpgradeError::Handshake(NoisePqError::InvalidPublicKey))?;
    Ok(MtPublicKey::from_array(arr))
}

/// Boxed future type alias for libp2p's upgrade traits.
pub type UpgradeFuture<T> = Pin<Box<dyn Future<Output = Result<T, UpgradeError>> + Send>>;
