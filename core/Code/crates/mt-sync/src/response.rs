//! FastSyncResponse (0x41) — chunked snapshot delivery.
//!
//! Per spec line 964–970 of `Montana Network v1.1.0.md`:
//!   chunk_index    4 B    u32 little-endian (0-based)
//!   total_chunks   4 B    u32 little-endian
//!   table_id       1 B    u8 (0x01 Account, 0x02 Node, 0x03 Candidate, 0x04 Proposals)
//!   record_count   4 B    u32 little-endian
//!   records        ?      record_count × serialize(record) canonical encoding
//!
//! The response is a sequence of chunks; the client reassembles by
//! chunk_index. After all `total_chunks` have arrived, the client
//! reconstructs the Merkle root and compares against the anchor
//! ProposalHeader.state_root for the requested window.

use mt_codec::{write_bytes, write_u32};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum FastSyncTableId {
    Account = 0x01,
    Node = 0x02,
    Candidate = 0x03,
    Proposals = 0x04,
}

impl FastSyncTableId {
    pub fn from_u8(b: u8) -> Option<FastSyncTableId> {
        match b {
            0x01 => Some(FastSyncTableId::Account),
            0x02 => Some(FastSyncTableId::Node),
            0x03 => Some(FastSyncTableId::Candidate),
            0x04 => Some(FastSyncTableId::Proposals),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FastSyncChunk {
    pub chunk_index: u32,
    pub total_chunks: u32,
    pub table_id: FastSyncTableId,
    pub anchor_window: u64,
    pub records: Vec<Vec<u8>>,
}

impl FastSyncChunk {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u32(buf, self.chunk_index);
        write_u32(buf, self.total_chunks);
        buf.push(self.table_id as u8);
        write_u32(buf, self.records.len() as u32);
        buf.extend_from_slice(&self.anchor_window.to_le_bytes());
        for r in &self.records {
            write_bytes(buf, r);
        }
    }

    pub fn decode(
        input: &[u8],
        record_size: usize,
    ) -> Result<FastSyncChunk, FastSyncResponseError> {
        if input.len() < 21 {
            return Err(FastSyncResponseError::HeaderTooShort);
        }
        let chunk_index = u32::from_le_bytes(input[0..4].try_into().unwrap());
        let total_chunks = u32::from_le_bytes(input[4..8].try_into().unwrap());
        let table_id = FastSyncTableId::from_u8(input[8])
            .ok_or(FastSyncResponseError::UnknownTableId(input[8]))?;
        let record_count = u32::from_le_bytes(input[9..13].try_into().unwrap()) as usize;
        let anchor_window = u64::from_le_bytes(input[13..21].try_into().unwrap());
        let body = &input[21..];
        let expected_body = record_count.checked_mul(record_size).ok_or(
            FastSyncResponseError::RecordCountOverflow {
                count: record_count,
                size: record_size,
            },
        )?;
        if body.len() != expected_body {
            return Err(FastSyncResponseError::BodyLengthMismatch {
                expected: expected_body,
                actual: body.len(),
            });
        }
        let mut records = Vec::with_capacity(record_count);
        for i in 0..record_count {
            records.push(body[i * record_size..(i + 1) * record_size].to_vec());
        }
        Ok(FastSyncChunk {
            chunk_index,
            total_chunks,
            table_id,
            anchor_window,
            records,
        })
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FastSyncResponse {
    pub chunks: Vec<FastSyncChunk>,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum FastSyncResponseError {
    HeaderTooShort,
    UnknownTableId(u8),
    RecordCountOverflow { count: usize, size: usize },
    BodyLengthMismatch { expected: usize, actual: usize },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunk_roundtrip_single_record() {
        let chunk = FastSyncChunk {
            chunk_index: 0,
            total_chunks: 1,
            table_id: FastSyncTableId::Account,
            anchor_window: 75_850,
            records: vec![vec![0xAB; 2059]],
        };
        let mut buf = Vec::new();
        chunk.encode(&mut buf);
        let decoded = FastSyncChunk::decode(&buf, 2059).expect("decode");
        assert_eq!(decoded, chunk);
    }

    #[test]
    fn chunk_roundtrip_multi_record() {
        let mut records = Vec::new();
        for i in 0..16u8 {
            records.push(vec![i; 2059]);
        }
        let chunk = FastSyncChunk {
            chunk_index: 3,
            total_chunks: 12,
            table_id: FastSyncTableId::Account,
            anchor_window: 9,
            records,
        };
        let mut buf = Vec::new();
        chunk.encode(&mut buf);
        let decoded = FastSyncChunk::decode(&buf, 2059).expect("decode");
        assert_eq!(decoded, chunk);
    }

    #[test]
    fn chunk_unknown_table_id_rejected() {
        let mut buf = Vec::new();
        FastSyncChunk {
            chunk_index: 0,
            total_chunks: 1,
            table_id: FastSyncTableId::Account,
            anchor_window: 0,
            records: vec![],
        }
        .encode(&mut buf);
        buf[8] = 0xFF;
        assert!(matches!(
            FastSyncChunk::decode(&buf, 2059),
            Err(FastSyncResponseError::UnknownTableId(0xFF))
        ));
    }

    #[test]
    fn chunk_body_length_mismatch_rejected() {
        let mut buf = Vec::new();
        FastSyncChunk {
            chunk_index: 0,
            total_chunks: 1,
            table_id: FastSyncTableId::Account,
            anchor_window: 0,
            records: vec![vec![0u8; 100]],
        }
        .encode(&mut buf);
        // Now decode claiming records are 200 bytes each, but only 100 bytes of body present
        assert!(matches!(
            FastSyncChunk::decode(&buf, 200),
            Err(FastSyncResponseError::BodyLengthMismatch { .. })
        ));
    }
}
