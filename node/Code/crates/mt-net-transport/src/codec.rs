// Custom libp2p codec для Montana ProtocolMessage envelope.
//
// Spec section "Protocol Message Layer" — 14 B header + payload (≤ 1 MiB).
// Подходит для request-response pattern libp2p (FastSync, PeerList,
// BatchLookup, RangeSubscribe). One-way gossip (Transfer, Anchor) —
// отдельный gossipsub behaviour в Phase C.2.

use std::io;

use futures::prelude::*;
use libp2p::{request_response::Codec, StreamProtocol};
use mt_net::{decode_envelope, encode_envelope, ProtocolMessage};

pub const MONTANA_PROTOCOL_NAME: StreamProtocol = StreamProtocol::new("/montana/1.0.0");
pub const MAX_PROTOCOL_PAYLOAD_BYTES: usize = 1_048_576; // = Genesis Decree max_protocol_payload_bytes
pub const ENVELOPE_HEADER_SIZE: usize = mt_net::ENVELOPE_HEADER_SIZE;

#[derive(Debug, Clone, Default)]
pub struct MontanaCodec;

#[async_trait::async_trait]
impl Codec for MontanaCodec {
    type Protocol = StreamProtocol;
    type Request = ProtocolMessage;
    type Response = ProtocolMessage;

    async fn read_request<T>(&mut self, _: &Self::Protocol, io: &mut T) -> io::Result<Self::Request>
    where
        T: AsyncRead + Unpin + Send,
    {
        read_envelope(io).await
    }

    async fn read_response<T>(
        &mut self,
        _: &Self::Protocol,
        io: &mut T,
    ) -> io::Result<Self::Response>
    where
        T: AsyncRead + Unpin + Send,
    {
        read_envelope(io).await
    }

    async fn write_request<T>(
        &mut self,
        _: &Self::Protocol,
        io: &mut T,
        req: Self::Request,
    ) -> io::Result<()>
    where
        T: AsyncWrite + Unpin + Send,
    {
        write_envelope(io, &req).await
    }

    async fn write_response<T>(
        &mut self,
        _: &Self::Protocol,
        io: &mut T,
        resp: Self::Response,
    ) -> io::Result<()>
    where
        T: AsyncWrite + Unpin + Send,
    {
        write_envelope(io, &resp).await
    }
}

async fn read_envelope<T>(io: &mut T) -> io::Result<ProtocolMessage>
where
    T: AsyncRead + Unpin + Send,
{
    let mut header = [0u8; ENVELOPE_HEADER_SIZE];
    io.read_exact(&mut header).await?;
    let mut len_bytes = [0u8; 4];
    len_bytes.copy_from_slice(&header[10..14]);
    let payload_length = u32::from_le_bytes(len_bytes) as usize;
    if payload_length > MAX_PROTOCOL_PAYLOAD_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "payload_length {payload_length} exceeds max_protocol_payload_bytes {MAX_PROTOCOL_PAYLOAD_BYTES}"
            ),
        ));
    }
    let mut buf = Vec::with_capacity(ENVELOPE_HEADER_SIZE + payload_length);
    buf.extend_from_slice(&header);
    buf.resize(ENVELOPE_HEADER_SIZE + payload_length, 0);
    io.read_exact(&mut buf[ENVELOPE_HEADER_SIZE..]).await?;
    decode_envelope(&buf).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("{e}")))
}

async fn write_envelope<T>(io: &mut T, msg: &ProtocolMessage) -> io::Result<()>
where
    T: AsyncWrite + Unpin + Send,
{
    let mut buf = Vec::with_capacity(ENVELOPE_HEADER_SIZE + msg.payload.len());
    encode_envelope(msg, &mut buf)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, format!("{e}")))?;
    io.write_all(&buf).await?;
    io.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::io::Cursor;
    use mt_net::MsgType;

    #[tokio::test]
    async fn roundtrip_ping_envelope() {
        let msg = ProtocolMessage::new(MsgType::Ping, 0, Vec::new());
        let mut buf = Vec::new();
        write_envelope(&mut buf, &msg).await.unwrap();
        let mut cur = Cursor::new(buf);
        let decoded = read_envelope(&mut cur).await.unwrap();
        assert_eq!(decoded, msg);
    }

    #[tokio::test]
    async fn roundtrip_transfer_envelope_1024b() {
        let payload: Vec<u8> = (0..1024).map(|_| 0xAB).collect();
        let msg = ProtocolMessage::new(MsgType::Transfer, 42, payload);
        let mut buf = Vec::new();
        write_envelope(&mut buf, &msg).await.unwrap();
        let mut cur = Cursor::new(buf);
        let decoded = read_envelope(&mut cur).await.unwrap();
        assert_eq!(decoded, msg);
    }

    #[tokio::test]
    async fn rejects_oversize_payload_length() {
        // Header with payload_length = MAX + 1
        let mut header = vec![0xF0u8, 0x01];
        header.extend_from_slice(&[0u8; 8]);
        let too_big: u32 = (MAX_PROTOCOL_PAYLOAD_BYTES as u32) + 1;
        header.extend_from_slice(&too_big.to_le_bytes());
        let mut cur = Cursor::new(header);
        let r = read_envelope(&mut cur).await;
        assert!(r.is_err());
        assert_eq!(r.unwrap_err().kind(), io::ErrorKind::InvalidData);
    }

    #[tokio::test]
    async fn truncated_header_returns_unexpected_eof() {
        let mut cur = Cursor::new(vec![0xF0, 0x01]);
        let r = read_envelope(&mut cur).await;
        assert!(r.is_err());
    }
}
