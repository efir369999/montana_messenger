//! FastSyncRequest (0x40) — 16-byte fixed-size wire envelope payload.
//!
//! Wire layout per `Montana Network v1.1.0.md` section "Sync protocols":
//!   anchor_window     8 B    u64 little-endian
//!   resume_offset     8 B    u64 little-endian (chunk_index to resume from)
//!
//! Total: 16 bytes.

use mt_codec::write_u64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FastSyncRequest {
    pub anchor_window: u64,
    pub resume_offset: u64,
}

impl FastSyncRequest {
    pub const SIZE: usize = 16;

    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_u64(buf, self.anchor_window);
        write_u64(buf, self.resume_offset);
    }

    pub fn decode(input: &[u8]) -> Result<FastSyncRequest, FastSyncRequestError> {
        if input.len() != Self::SIZE {
            return Err(FastSyncRequestError::WrongSize {
                expected: Self::SIZE,
                actual: input.len(),
            });
        }
        let anchor_window = u64::from_le_bytes(input[0..8].try_into().unwrap());
        let resume_offset = u64::from_le_bytes(input[8..16].try_into().unwrap());
        Ok(FastSyncRequest {
            anchor_window,
            resume_offset,
        })
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum FastSyncRequestError {
    WrongSize { expected: usize, actual: usize },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let req = FastSyncRequest {
            anchor_window: 75_850,
            resume_offset: 0,
        };
        let mut buf = Vec::new();
        req.encode(&mut buf);
        assert_eq!(buf.len(), FastSyncRequest::SIZE);
        let decoded = FastSyncRequest::decode(&buf).expect("decode");
        assert_eq!(decoded, req);
    }

    #[test]
    fn wrong_size_rejected() {
        let too_short = vec![0u8; 15];
        assert!(matches!(
            FastSyncRequest::decode(&too_short),
            Err(FastSyncRequestError::WrongSize {
                expected: 16,
                actual: 15
            })
        ));
        let too_long = vec![0u8; 17];
        assert!(matches!(
            FastSyncRequest::decode(&too_long),
            Err(FastSyncRequestError::WrongSize {
                expected: 16,
                actual: 17
            })
        ));
    }
}
