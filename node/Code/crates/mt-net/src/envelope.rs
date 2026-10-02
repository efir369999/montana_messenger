use alloc::vec::Vec;

use mt_codec::{write_bytes, write_u32, write_u64, write_u8};

use crate::error::NetError;
use crate::msg_type::MsgType;

pub const ENVELOPE_HEADER_SIZE: usize = 14;
pub const MSG_VERSION_V1: u8 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProtocolMessage {
    pub msg_type: MsgType,
    pub msg_version: u8,
    pub request_id: u64,
    pub payload: Vec<u8>,
}

impl ProtocolMessage {
    pub fn new(msg_type: MsgType, request_id: u64, payload: Vec<u8>) -> Self {
        ProtocolMessage {
            msg_type,
            msg_version: MSG_VERSION_V1,
            request_id,
            payload,
        }
    }

    pub fn try_new(msg_type: MsgType, request_id: u64, payload: Vec<u8>) -> Result<Self, NetError> {
        if payload.len() > u32::MAX as usize {
            return Err(NetError::PayloadTooLarge);
        }
        Ok(ProtocolMessage {
            msg_type,
            msg_version: MSG_VERSION_V1,
            request_id,
            payload,
        })
    }
}

pub fn encode_envelope(msg: &ProtocolMessage, buf: &mut Vec<u8>) -> Result<(), NetError> {
    if msg.msg_version != MSG_VERSION_V1 {
        return Err(NetError::UnsupportedVersion(msg.msg_version));
    }
    if msg.payload.len() > u32::MAX as usize {
        return Err(NetError::PayloadTooLarge);
    }
    write_u8(buf, msg.msg_type.as_u8());
    write_u8(buf, msg.msg_version);
    write_u64(buf, msg.request_id);
    write_u32(buf, msg.payload.len() as u32);
    write_bytes(buf, &msg.payload);
    Ok(())
}

pub fn decode_envelope(input: &[u8]) -> Result<ProtocolMessage, NetError> {
    if input.len() < ENVELOPE_HEADER_SIZE {
        return Err(NetError::TruncatedHeader);
    }
    let msg_type = MsgType::from_u8(input[0])?;
    let msg_version = input[1];
    if msg_version != MSG_VERSION_V1 {
        return Err(NetError::UnsupportedVersion(msg_version));
    }
    let mut req_bytes = [0u8; 8];
    req_bytes.copy_from_slice(&input[2..10]);
    let request_id = u64::from_le_bytes(req_bytes);

    let mut len_bytes = [0u8; 4];
    len_bytes.copy_from_slice(&input[10..14]);
    let payload_length = u32::from_le_bytes(len_bytes) as usize;

    let payload_start = ENVELOPE_HEADER_SIZE;
    let payload_end = payload_start
        .checked_add(payload_length)
        .ok_or(NetError::PayloadTooLarge)?;
    if input.len() < payload_end {
        return Err(NetError::TruncatedPayload);
    }
    if input.len() != payload_end {
        return Err(NetError::PayloadLengthMismatch);
    }
    let payload = input[payload_start..payload_end].to_vec();
    Ok(ProtocolMessage {
        msg_type,
        msg_version,
        request_id,
        payload,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    #[test]
    fn roundtrip_ping_empty_payload() {
        let m = ProtocolMessage::new(MsgType::Ping, 0, vec![]);
        let mut buf = Vec::new();
        encode_envelope(&m, &mut buf).unwrap();
        assert_eq!(buf.len(), ENVELOPE_HEADER_SIZE);
        let decoded = decode_envelope(&buf).unwrap();
        assert_eq!(decoded, m);
    }

    #[test]
    fn roundtrip_typical_transfer_payload_1024b() {
        let payload: Vec<u8> = (0..1024).map(|_| 0xAB_u8).collect();
        let m = ProtocolMessage::new(MsgType::Transfer, 42, payload);
        let mut buf = Vec::new();
        encode_envelope(&m, &mut buf).unwrap();
        assert_eq!(buf.len(), ENVELOPE_HEADER_SIZE + 1024);
        let decoded = decode_envelope(&buf).unwrap();
        assert_eq!(decoded, m);
    }

    #[test]
    fn header_byte_layout_vector_a1() {
        let m = ProtocolMessage::new(MsgType::Ping, 0, vec![]);
        let mut buf = Vec::new();
        encode_envelope(&m, &mut buf).unwrap();
        assert_eq!(buf[0], 0xF0);
        assert_eq!(buf[1], 0x01);
        assert_eq!(&buf[2..10], &[0u8; 8]);
        assert_eq!(&buf[10..14], &[0u8; 4]);
    }

    #[test]
    fn header_byte_layout_vector_a2_request_id_le() {
        let payload: Vec<u8> = (0..1024).map(|_| 0xAB_u8).collect();
        let m = ProtocolMessage::new(MsgType::Transfer, 42, payload);
        let mut buf = Vec::new();
        encode_envelope(&m, &mut buf).unwrap();
        assert_eq!(buf[0], 0x01);
        assert_eq!(buf[1], 0x01);
        assert_eq!(&buf[2..10], &[42, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(&buf[10..14], &[0x00, 0x04, 0x00, 0x00]);
    }

    #[test]
    fn decode_truncated_header() {
        let buf = vec![0xF0, 0x01];
        assert_eq!(decode_envelope(&buf), Err(NetError::TruncatedHeader));
    }

    #[test]
    fn decode_truncated_payload() {
        let mut buf = Vec::new();
        let m = ProtocolMessage::new(MsgType::Transfer, 0, vec![1, 2, 3, 4, 5]);
        encode_envelope(&m, &mut buf).unwrap();
        buf.truncate(ENVELOPE_HEADER_SIZE + 2);
        assert_eq!(decode_envelope(&buf), Err(NetError::TruncatedPayload));
    }

    #[test]
    fn decode_payload_length_mismatch() {
        let mut buf = Vec::new();
        let m = ProtocolMessage::new(MsgType::Transfer, 0, vec![1, 2, 3]);
        encode_envelope(&m, &mut buf).unwrap();
        buf.push(0xCC);
        assert_eq!(decode_envelope(&buf), Err(NetError::PayloadLengthMismatch));
    }

    #[test]
    fn decode_invalid_msg_type() {
        let mut buf = vec![0x77, 0x01];
        buf.extend_from_slice(&[0u8; 12]);
        assert_eq!(decode_envelope(&buf), Err(NetError::InvalidMsgType(0x77)));
    }

    #[test]
    fn decode_unsupported_version() {
        let mut buf = vec![0xF0, 0x02];
        buf.extend_from_slice(&[0u8; 12]);
        assert_eq!(decode_envelope(&buf), Err(NetError::UnsupportedVersion(2)));
    }

    #[test]
    fn determinism_repeated_encode_byte_identical() {
        let payload: Vec<u8> = (0..256).map(|i| (i & 0xFF) as u8).collect();
        let m = ProtocolMessage::new(MsgType::FastSyncResponse, 0xDEAD_BEEF_CAFE_BABE, payload);
        let mut a = Vec::new();
        let mut b = Vec::new();
        encode_envelope(&m, &mut a).unwrap();
        encode_envelope(&m, &mut b).unwrap();
        assert_eq!(a, b);
    }
}
