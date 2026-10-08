//! Read/write over a TCP+TLS stream (Stage 1; spec §152 -- "TCP/TLS-443 is mandatory",
//! operators cut non-443 UDP). Prologue/fixed replies use read_exact/write_all;
//! variable messages use a u32 BE length prefix (TCP carries no per-stream FIN like QUIC,
//! so the message boundary is an explicit length). Request-response is sequential on one duplex
//! stream: a side writes the request, then reads the reply on the same `&mut S`.

use thiserror::Error;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use mt_codec::domain::OVERLAY_CHANNEL_LABEL;
use mt_overlay::frame::MAX_PAYLOAD_LEN;

/// Upper bound on one message on the wire: header + payload cap + slack.
pub const MAX_FRAME_WIRE: usize = MAX_PAYLOAD_LEN + 4096;

#[derive(Debug, Error)]
pub enum WireError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("frame too large: {0}")]
    TooLarge(usize),
    #[error("stream already closed")]
    Closed,
    #[error("TLS-Exporter (channel_hash) failed")]
    Export,
}

/// Write a fixed block (prologue/tag/fixed reply) + flush.
pub async fn write_fixed<W: AsyncWrite + Unpin + ?Sized>(
    s: &mut W,
    bytes: &[u8],
) -> Result<(), WireError> {
    s.write_all(bytes).await?;
    s.flush().await?;
    Ok(())
}

/// Read exactly `buf.len()` bytes (prologue/fixed reply).
pub async fn read_fixed<R: AsyncRead + Unpin + ?Sized>(
    s: &mut R,
    buf: &mut [u8],
) -> Result<(), WireError> {
    s.read_exact(buf).await?;
    Ok(())
}

/// One message = [u32 BE len][bytes]. Write + flush (the reply follows on the same stream).
pub async fn send_frame<W: AsyncWrite + Unpin + ?Sized>(
    s: &mut W,
    bytes: &[u8],
) -> Result<(), WireError> {
    if bytes.len() > MAX_FRAME_WIRE {
        return Err(WireError::TooLarge(bytes.len()));
    }
    s.write_all(&(bytes.len() as u32).to_be_bytes()).await?;
    s.write_all(bytes).await?;
    s.flush().await?;
    Ok(())
}

/// Read a message [u32 BE len][bytes].
pub async fn recv_frame<R: AsyncRead + Unpin + ?Sized>(s: &mut R) -> Result<Vec<u8>, WireError> {
    let mut lb = [0u8; 4];
    s.read_exact(&mut lb).await?;
    let len = u32::from_be_bytes(lb) as usize;
    if len > MAX_FRAME_WIRE {
        return Err(WireError::TooLarge(len));
    }
    let mut buf = vec![0u8; len];
    s.read_exact(&mut buf).await?;
    Ok(buf)
}

/// channel_hash of the connection = TLS-Exporter(OVERLAY_CHANNEL_LABEL, no-context, 32).
/// Both TLS 1.3 sides derive the same 32 B -> binds RegProof to the channel (R4);
/// spec 0.8.1 (RFC 8446 §7.5). The argument is a rustls connection (client/server), shared by
/// tokio-rustls through `TlsStream::get_ref().1`.
pub fn channel_hash<D>(conn: &rustls::ConnectionCommon<D>) -> Result<[u8; 32], WireError> {
    conn.export_keying_material([0u8; 32], OVERLAY_CHANNEL_LABEL, None)
        .map_err(|_| WireError::Export)
}
