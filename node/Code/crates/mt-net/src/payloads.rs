use alloc::vec::Vec;

use mt_codec::{write_bytes, write_u16, write_u32, write_u64, write_u8};

use crate::error::NetError;

pub const PEER_ENTRY_SIZE: usize = 59;
pub const FASTSYNC_REQUEST_SIZE: usize = 16;
pub const PEER_LIST_REQUEST_SIZE: usize = 2;
pub const RANGE_SUBSCRIBE_ERROR_SIZE: usize = 1;
pub const BATCH_LOOKUP_ERROR_SIZE: usize = 2;
pub const BYE_SIZE: usize = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FastSyncRequest {
    pub anchor_window: u64,
    pub resume_offset: u64,
}

impl FastSyncRequest {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u64(buf, self.anchor_window);
        write_u64(buf, self.resume_offset);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() != FASTSYNC_REQUEST_SIZE {
            return Err(NetError::PayloadLengthMismatch);
        }
        let mut a = [0u8; 8];
        a.copy_from_slice(&input[0..8]);
        let mut b = [0u8; 8];
        b.copy_from_slice(&input[8..16]);
        Ok(FastSyncRequest {
            anchor_window: u64::from_le_bytes(a),
            resume_offset: u64::from_le_bytes(b),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[repr(u8)]
pub enum TableId {
    Account = 0x01,
    Node = 0x02,
    Candidate = 0x03,
    Proposals = 0x04,
}

impl TableId {
    pub fn from_u8(b: u8) -> Result<Self, NetError> {
        match b {
            0x01 => Ok(TableId::Account),
            0x02 => Ok(TableId::Node),
            0x03 => Ok(TableId::Candidate),
            0x04 => Ok(TableId::Proposals),
            _ => Err(NetError::InvalidPayloadField),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FastSyncResponseChunk {
    pub chunk_index: u32,
    pub total_chunks: u32,
    pub table_id: TableId,
    pub record_count: u32,
    // DEV-018: snapshot anchor window. Receiver checks anchor_window > local current
    // before accepting (drop chunks from peers at the same or older window — they
    // cannot help us catch up). Finalize uses this to look up the correct
    // recent_roots[anchor_window] for state_root verification, instead of scanning
    // all known roots and accepting any match.
    pub anchor_window: u64,
    pub records: Vec<u8>,
}

impl FastSyncResponseChunk {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u32(buf, self.chunk_index);
        write_u32(buf, self.total_chunks);
        write_u8(buf, self.table_id.clone() as u8);
        write_u32(buf, self.record_count);
        let aw = self.anchor_window.to_le_bytes();
        buf.extend_from_slice(&aw);
        write_bytes(buf, &self.records);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() < 21 {
            return Err(NetError::TruncatedPayload);
        }
        let mut a = [0u8; 4];
        a.copy_from_slice(&input[0..4]);
        let chunk_index = u32::from_le_bytes(a);
        let mut b = [0u8; 4];
        b.copy_from_slice(&input[4..8]);
        let total_chunks = u32::from_le_bytes(b);
        if total_chunks == 0 || chunk_index >= total_chunks {
            return Err(NetError::InvalidPayloadField);
        }
        let table_id = TableId::from_u8(input[8])?;
        let mut c = [0u8; 4];
        c.copy_from_slice(&input[9..13]);
        let record_count = u32::from_le_bytes(c);
        let mut aw = [0u8; 8];
        aw.copy_from_slice(&input[13..21]);
        let anchor_window = u64::from_le_bytes(aw);
        let records = input[21..].to_vec();
        Ok(FastSyncResponseChunk {
            chunk_index,
            total_chunks,
            table_id,
            record_count,
            anchor_window,
            records,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FastSyncError {
    pub code: u8,
    pub message: Vec<u8>,
}

impl FastSyncError {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u8(buf, self.code);
        write_u8(buf, self.message.len() as u8);
        write_bytes(buf, &self.message);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() < 2 {
            return Err(NetError::TruncatedPayload);
        }
        let code = input[0];
        let len = input[1] as usize;
        if input.len() != 2 + len {
            return Err(NetError::PayloadLengthMismatch);
        }
        Ok(FastSyncError {
            code,
            message: input[2..2 + len].to_vec(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerListRequest {
    pub max_count: u16,
}

impl PeerListRequest {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u16(buf, self.max_count);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() != PEER_LIST_REQUEST_SIZE {
            return Err(NetError::PayloadLengthMismatch);
        }
        let mut a = [0u8; 2];
        a.copy_from_slice(input);
        Ok(PeerListRequest {
            max_count: u16::from_le_bytes(a),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IpAddrV {
    V4 = 0x04,
    V6 = 0x06,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerEntry {
    pub ip_version: IpAddrV,
    pub ip: [u8; 16],
    pub port: u16,
    pub node_id: [u8; 32],
    pub start_window: u64,
}

impl PeerEntry {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u8(buf, self.ip_version.clone() as u8);
        write_bytes(buf, &self.ip);
        write_u16(buf, self.port);
        write_bytes(buf, &self.node_id);
        write_u64(buf, self.start_window);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() != PEER_ENTRY_SIZE {
            return Err(NetError::PayloadLengthMismatch);
        }
        let ip_version = match input[0] {
            0x04 => IpAddrV::V4,
            0x06 => IpAddrV::V6,
            _ => return Err(NetError::InvalidPayloadField),
        };
        let mut ip = [0u8; 16];
        ip.copy_from_slice(&input[1..17]);
        let mut p = [0u8; 2];
        p.copy_from_slice(&input[17..19]);
        let port = u16::from_le_bytes(p);
        let mut nid = [0u8; 32];
        nid.copy_from_slice(&input[19..51]);
        let mut sw = [0u8; 8];
        sw.copy_from_slice(&input[51..59]);
        Ok(PeerEntry {
            ip_version,
            ip,
            port,
            node_id: nid,
            start_window: u64::from_le_bytes(sw),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerListResponse {
    pub peers: Vec<PeerEntry>,
}

impl PeerListResponse {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u16(buf, self.peers.len() as u16);
        for p in &self.peers {
            p.encode(buf);
        }
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() < 2 {
            return Err(NetError::TruncatedPayload);
        }
        let mut c = [0u8; 2];
        c.copy_from_slice(&input[0..2]);
        let count = u16::from_le_bytes(c) as usize;
        let expected = 2 + count * PEER_ENTRY_SIZE;
        if input.len() != expected {
            return Err(NetError::PayloadLengthMismatch);
        }
        let mut peers = Vec::with_capacity(count);
        for i in 0..count {
            let off = 2 + i * PEER_ENTRY_SIZE;
            peers.push(PeerEntry::decode(&input[off..off + PEER_ENTRY_SIZE])?);
        }
        Ok(PeerListResponse { peers })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BatchLookupError {
    pub query_type: u8,
    pub error_code: u8,
}

impl BatchLookupError {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u8(buf, self.query_type);
        write_u8(buf, self.error_code);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() != BATCH_LOOKUP_ERROR_SIZE {
            return Err(NetError::PayloadLengthMismatch);
        }
        Ok(BatchLookupError {
            query_type: input[0],
            error_code: input[1],
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RangeSubscribeRequest {
    pub labels: Vec<[u8; 32]>,
}

impl RangeSubscribeRequest {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u16(buf, self.labels.len() as u16);
        for l in &self.labels {
            write_bytes(buf, l);
        }
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() < 2 {
            return Err(NetError::TruncatedPayload);
        }
        let mut c = [0u8; 2];
        c.copy_from_slice(&input[0..2]);
        let count = u16::from_le_bytes(c) as usize;
        let expected = 2 + count * 32;
        if input.len() != expected {
            return Err(NetError::PayloadLengthMismatch);
        }
        let mut labels = Vec::with_capacity(count);
        for i in 0..count {
            let off = 2 + i * 32;
            let mut l = [0u8; 32];
            l.copy_from_slice(&input[off..off + 32]);
            labels.push(l);
        }
        Ok(RangeSubscribeRequest { labels })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RangeSubscribeError {
    pub error_code: u8,
}

impl RangeSubscribeError {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u8(buf, self.error_code);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() != RANGE_SUBSCRIBE_ERROR_SIZE {
            return Err(NetError::PayloadLengthMismatch);
        }
        Ok(RangeSubscribeError {
            error_code: input[0],
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bye {
    pub reason: u8,
}

impl Bye {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u8(buf, self.reason);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() != BYE_SIZE {
            return Err(NetError::PayloadLengthMismatch);
        }
        // Forward compatibility per spec section "Protocol Message Layer":
        // unknown reason values accepted as protocol evolution allowance.
        // Caller distinguishes known reasons (0x00..0x05) для специфической
        // обработки, неизвестные — log + accept disconnect.
        Ok(Bye { reason: input[0] })
    }

    pub fn is_known_reason(&self) -> bool {
        self.reason <= 0x05
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    #[test]
    fn fastsync_request_roundtrip() {
        let r = FastSyncRequest {
            anchor_window: 12345,
            resume_offset: 0,
        };
        let mut buf = Vec::new();
        r.encode(&mut buf);
        assert_eq!(buf.len(), FASTSYNC_REQUEST_SIZE);
        assert_eq!(FastSyncRequest::decode(&buf).unwrap(), r);
    }

    #[test]
    fn fastsync_error_roundtrip() {
        let e = FastSyncError {
            code: 0x01,
            message: b"anchor_window not retained".to_vec(),
        };
        let mut buf = Vec::new();
        e.encode(&mut buf);
        assert_eq!(FastSyncError::decode(&buf).unwrap(), e);
    }

    #[test]
    fn peer_entry_byte_layout() {
        let mut ip = [0u8; 16];
        ip[12..].copy_from_slice(&[10, 0, 0, 1]);
        let pe = PeerEntry {
            ip_version: IpAddrV::V4,
            ip,
            port: 4242,
            node_id: [0xAA; 32],
            start_window: 100,
        };
        let mut buf = Vec::new();
        pe.encode(&mut buf);
        assert_eq!(buf.len(), PEER_ENTRY_SIZE);
        assert_eq!(buf[0], 0x04);
        assert_eq!(&buf[1..17], &ip);
        assert_eq!(&buf[17..19], &4242u16.to_le_bytes());
        assert_eq!(&buf[19..51], &[0xAA; 32]);
        assert_eq!(&buf[51..59], &100u64.to_le_bytes());
        assert_eq!(PeerEntry::decode(&buf).unwrap(), pe);
    }

    #[test]
    fn peer_list_response_3_entries() {
        let mut ip4 = [0u8; 16];
        ip4[12..].copy_from_slice(&[10, 0, 0, 1]);
        let pe1 = PeerEntry {
            ip_version: IpAddrV::V4,
            ip: ip4,
            port: 4242,
            node_id: [0xAA; 32],
            start_window: 100,
        };
        let mut ip6 = [0u8; 16];
        ip6[0] = 0xfe;
        ip6[1] = 0x80;
        ip6[15] = 1;
        let pe2 = PeerEntry {
            ip_version: IpAddrV::V6,
            ip: ip6,
            port: 4242,
            node_id: [0xBB; 32],
            start_window: 200,
        };
        let mut ip4b = [0u8; 16];
        ip4b[12..].copy_from_slice(&[10, 0, 0, 2]);
        let pe3 = PeerEntry {
            ip_version: IpAddrV::V4,
            ip: ip4b,
            port: 4243,
            node_id: [0xCC; 32],
            start_window: 300,
        };
        let resp = PeerListResponse {
            peers: vec![pe1, pe2, pe3],
        };
        let mut buf = Vec::new();
        resp.encode(&mut buf);
        assert_eq!(buf.len(), 2 + 3 * PEER_ENTRY_SIZE);
        assert_eq!(PeerListResponse::decode(&buf).unwrap(), resp);
    }

    #[test]
    fn fastsync_response_chunk_roundtrip() {
        let chunk = FastSyncResponseChunk {
            chunk_index: 0,
            total_chunks: 1,
            table_id: TableId::Account,
            record_count: 1,
            anchor_window: 0,
            records: vec![0x55; 64],
        };
        let mut buf = Vec::new();
        chunk.encode(&mut buf);
        assert_eq!(FastSyncResponseChunk::decode(&buf).unwrap(), chunk);
    }

    #[test]
    fn fastsync_response_chunk_invalid_total_zero() {
        let mut buf = Vec::new();
        write_u32(&mut buf, 0);
        write_u32(&mut buf, 0);
        write_u8(&mut buf, 0x01);
        write_u32(&mut buf, 0);
        buf.extend_from_slice(&0u64.to_le_bytes());
        assert_eq!(
            FastSyncResponseChunk::decode(&buf),
            Err(NetError::InvalidPayloadField)
        );
    }

    #[test]
    fn peer_list_request_roundtrip() {
        let r = PeerListRequest { max_count: 64 };
        let mut buf = Vec::new();
        r.encode(&mut buf);
        assert_eq!(buf.len(), 2);
        assert_eq!(PeerListRequest::decode(&buf).unwrap(), r);
    }

    #[test]
    fn batch_lookup_error_roundtrip() {
        let e = BatchLookupError {
            query_type: 0x01,
            error_code: 0x01,
        };
        let mut buf = Vec::new();
        e.encode(&mut buf);
        assert_eq!(buf.len(), 2);
        assert_eq!(BatchLookupError::decode(&buf).unwrap(), e);
    }

    #[test]
    fn range_subscribe_request_4_labels() {
        let r = RangeSubscribeRequest {
            labels: vec![[0xE0; 32], [0xE1; 32], [0xE2; 32], [0xE3; 32]],
        };
        let mut buf = Vec::new();
        r.encode(&mut buf);
        assert_eq!(buf.len(), 2 + 4 * 32);
        assert_eq!(RangeSubscribeRequest::decode(&buf).unwrap(), r);
    }

    #[test]
    fn range_subscribe_error_roundtrip() {
        let e = RangeSubscribeError { error_code: 0x02 };
        let mut buf = Vec::new();
        e.encode(&mut buf);
        assert_eq!(RangeSubscribeError::decode(&buf).unwrap(), e);
    }

    #[test]
    fn bye_all_valid_reasons() {
        for r in 0u8..=0x05 {
            let bye = Bye { reason: r };
            let mut buf = Vec::new();
            bye.encode(&mut buf);
            assert_eq!(Bye::decode(&buf).unwrap(), bye);
        }
    }

    #[test]
    fn bye_unknown_reason_forward_compat_accepted() {
        // Spec forward compat: unknown reasons accepted, distinguished via is_known_reason()
        let b = Bye::decode(&[0x06]).unwrap();
        assert_eq!(b.reason, 0x06);
        assert!(!b.is_known_reason());
        let b = Bye::decode(&[0xFF]).unwrap();
        assert_eq!(b.reason, 0xFF);
        assert!(!b.is_known_reason());
    }
}
