//! Async drive functions for the Noise_PQ XX-pattern handshake over any
//! `AsyncRead + AsyncWrite` socket. Library-only — no libp2p types.
//! libp2p UpgradeInfo / Inbound / OutboundConnectionUpgrade trait impls live
//! in `mt-net-transport/src/xx_noise_pq_upgrade.rs` to keep libp2p deps out
//! of mt-noise-pq.

use crate::stream::NoisePqStream;
use crate::xx_handshake::{
    initiator_receive_msg2, initiator_send_msg1, initiator_send_msg3, responder_receive_msg1,
    responder_receive_msg3, responder_send_msg2, XxSession, XX_MSG1_SIZE, XX_MSG2_SIZE,
    XX_MSG3_SIZE,
};
use crate::NoisePqError;
use futures::io::{AsyncReadExt, AsyncWriteExt};
use futures::{AsyncRead, AsyncWrite};
use mt_crypto::{PublicKey, SecretKey};
use std::sync::Arc;

pub const XX_PROTOCOL_NAME: &str = "/montana/noise-pq-xx/1.0.0";

/// Maximum random padding appended to each Noise_PQ XX handshake message.
/// The `XX_MSG*_SIZE` values are the floor; padding only adds, so a passive
/// observer sees no fixed distinctive length triple. Montana Network spec,
/// "Post-quantum transport" -> "Handshake length obfuscation".
pub const XX_MAX_HANDSHAKE_PAD: usize = 1024;

/// Write one handshake message with length obfuscation:
///   `[total_len: u16 LE][core bytes][random pad]`
/// where `total_len = core.len() + pad_len` and `pad_len` is drawn uniformly
/// from `[0, XX_MAX_HANDSHAKE_PAD]` via the OS CSPRNG. The first bytes carry no
/// fixed magic (the length varies per connection). Padding is random and is
/// not covered by the transcript or the identity signatures (they sign the
/// core message only), so length obfuscation never changes the derived
/// session keys.
async fn write_obfuscated<C>(socket: &mut C, core: &[u8]) -> Result<(), XxUpgradeError>
where
    C: AsyncWrite + Unpin,
{
    let mut r = [0u8; 2];
    getrandom::getrandom(&mut r).map_err(|_| NoisePqError::RngFailed)?;
    let pad_len = (u16::from_le_bytes(r) as usize) % (XX_MAX_HANDSHAKE_PAD + 1);
    let total_len = core.len() + pad_len;
    let mut frame = Vec::with_capacity(2 + total_len);
    debug_assert!(
        total_len <= u16::MAX as usize,
        "handshake frame length {total_len} exceeds the u16 length prefix"
    );
    frame.extend_from_slice(&(total_len as u16).to_le_bytes());
    frame.extend_from_slice(core);
    if pad_len > 0 {
        let start = frame.len();
        frame.resize(start + pad_len, 0);
        getrandom::getrandom(&mut frame[start..]).map_err(|_| NoisePqError::RngFailed)?;
    }
    socket.write_all(&frame).await?;
    socket.flush().await?;
    Ok(())
}

/// Read one length-obfuscated handshake message and return the core bytes.
/// Validates `core_size <= total_len <= core_size + XX_MAX_HANDSHAKE_PAD`
/// before allocating, then reads `total_len` bytes and strips the padding.
async fn read_obfuscated<C>(socket: &mut C, core_size: usize) -> Result<Vec<u8>, XxUpgradeError>
where
    C: AsyncRead + Unpin,
{
    let mut len_b = [0u8; 2];
    socket.read_exact(&mut len_b).await?;
    let total_len = u16::from_le_bytes(len_b) as usize;
    if total_len < core_size || total_len > core_size + XX_MAX_HANDSHAKE_PAD {
        return Err(XxUpgradeError::Handshake(NoisePqError::BadMsgSize {
            expected: core_size,
            actual: total_len,
        }));
    }
    let mut buf = vec![0u8; total_len];
    socket.read_exact(&mut buf).await?;
    buf.truncate(core_size);
    Ok(buf)
}

#[derive(Debug)]
pub enum XxUpgradeError {
    Io(std::io::Error),
    Handshake(NoisePqError),
}

impl std::fmt::Display for XxUpgradeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            XxUpgradeError::Io(e) => write!(f, "io: {e}"),
            XxUpgradeError::Handshake(e) => write!(f, "handshake: {e:?}"),
        }
    }
}

impl std::error::Error for XxUpgradeError {}

impl From<std::io::Error> for XxUpgradeError {
    fn from(e: std::io::Error) -> Self {
        XxUpgradeError::Io(e)
    }
}

impl From<NoisePqError> for XxUpgradeError {
    fn from(e: NoisePqError) -> Self {
        XxUpgradeError::Handshake(e)
    }
}

/// Drive initiator side of XX handshake: send msg1, recv msg2, send msg3.
/// Returns the final session and the AEAD-wrapped stream.
pub async fn xx_initiator_drive<C>(
    mut socket: C,
    id_pk: PublicKey,
    id_sk: Arc<SecretKey>,
) -> Result<(XxSession, NoisePqStream<C>), XxUpgradeError>
where
    C: AsyncRead + AsyncWrite + Unpin,
{
    let (msg1, init_after_msg1) = initiator_send_msg1(id_sk, id_pk)?;
    write_obfuscated(&mut socket, &msg1).await?;

    let msg2 = read_obfuscated(&mut socket, XX_MSG2_SIZE).await?;
    let init_after_msg2 = initiator_receive_msg2(&msg2, init_after_msg1)?;

    let (msg3, session) = initiator_send_msg3(init_after_msg2)?;
    write_obfuscated(&mut socket, &msg3).await?;

    let sk_tx = session.sk_i_to_r;
    let sk_rx = session.sk_r_to_i;
    let stream = NoisePqStream::new(socket, sk_tx, sk_rx);
    Ok((session, stream))
}

/// Drive responder side of XX handshake: recv msg1, send msg2, recv msg3.
/// Returns the final session and the AEAD-wrapped stream.
pub async fn xx_responder_drive<C>(
    mut socket: C,
    id_pk: PublicKey,
    id_sk: Arc<SecretKey>,
) -> Result<(XxSession, NoisePqStream<C>), XxUpgradeError>
where
    C: AsyncRead + AsyncWrite + Unpin,
{
    let msg1 = read_obfuscated(&mut socket, XX_MSG1_SIZE).await?;
    let resp_after_msg1 = responder_receive_msg1(&msg1, id_sk, id_pk)?;

    let (msg2, resp_after_msg2) = responder_send_msg2(resp_after_msg1)?;
    write_obfuscated(&mut socket, &msg2).await?;

    let msg3 = read_obfuscated(&mut socket, XX_MSG3_SIZE).await?;
    let session = responder_receive_msg3(&msg3, resp_after_msg2)?;

    let sk_tx = session.sk_r_to_i;
    let sk_rx = session.sk_i_to_r;
    let stream = NoisePqStream::new(socket, sk_tx, sk_rx);
    Ok((session, stream))
}

#[cfg(test)]
mod obfuscation_tests {
    use super::*;
    use futures::{AsyncReadExt, AsyncWriteExt};
    use tokio_util::compat::TokioAsyncReadCompatExt;

    #[tokio::test]
    async fn obfuscated_roundtrip_strips_padding() {
        let core = vec![0xABu8; XX_MSG1_SIZE];
        let (a, b) = tokio::io::duplex(1 << 16);
        let mut a = a.compat();
        let mut b = b.compat();
        write_obfuscated(&mut a, &core).await.unwrap();
        let got = read_obfuscated(&mut b, XX_MSG1_SIZE).await.unwrap();
        assert_eq!(got, core, "core is recovered after the padding is stripped");
    }

    #[tokio::test]
    async fn obfuscated_length_varies_and_stays_in_range() {
        let core = vec![0x11u8; XX_MSG1_SIZE];
        let mut seen = std::collections::BTreeSet::new();
        for _ in 0..64 {
            let (a, b) = tokio::io::duplex(1 << 16);
            let mut a = a.compat();
            let mut b = b.compat();
            write_obfuscated(&mut a, &core).await.unwrap();
            let mut len_b = [0u8; 2];
            b.read_exact(&mut len_b).await.unwrap();
            seen.insert(u16::from_le_bytes(len_b) as usize);
        }
        assert!(
            seen.len() > 1,
            "the framed length must vary with random padding"
        );
        assert!(*seen.iter().min().unwrap() >= XX_MSG1_SIZE);
        assert!(*seen.iter().max().unwrap() <= XX_MSG1_SIZE + XX_MAX_HANDSHAKE_PAD);
    }

    #[tokio::test]
    async fn read_obfuscated_rejects_below_floor() {
        let (a, b) = tokio::io::duplex(1 << 16);
        let mut a = a.compat();
        let mut b = b.compat();
        let bad = ((XX_MSG2_SIZE - 1) as u16).to_le_bytes();
        a.write_all(&bad).await.unwrap();
        a.flush().await.unwrap();
        let r = read_obfuscated(&mut b, XX_MSG2_SIZE).await;
        assert!(matches!(
            r,
            Err(XxUpgradeError::Handshake(NoisePqError::BadMsgSize { .. }))
        ));
    }

    #[tokio::test]
    async fn read_obfuscated_rejects_above_ceiling() {
        let (a, b) = tokio::io::duplex(1 << 16);
        let mut a = a.compat();
        let mut b = b.compat();
        let bad = ((XX_MSG2_SIZE + XX_MAX_HANDSHAKE_PAD + 1) as u16).to_le_bytes();
        a.write_all(&bad).await.unwrap();
        a.flush().await.unwrap();
        let r = read_obfuscated(&mut b, XX_MSG2_SIZE).await;
        assert!(matches!(
            r,
            Err(XxUpgradeError::Handshake(NoisePqError::BadMsgSize { .. }))
        ));
    }
}
