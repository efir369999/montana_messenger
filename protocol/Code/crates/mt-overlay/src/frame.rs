//! OverlayFrame — the canonical binary frame of the overlay (LE).
//! Spec: Montana P2P Network, Stage 1 "OverlayFrame format".

use mt_codec::{write_bytes, write_u32, write_u8, CanonicalEncode};

use crate::{OverlayAddr, OVERLAY_ADDR_SIZE};

pub const FRAME_VERSION: u8 = 0x01;
pub const MSG_ID_SIZE: usize = 16;
// version 1 + type 1 + dst 32 + src 32 + msg_id 16 + payload_len 4
pub const FRAME_HEADER_SIZE: usize = 86;
// Defensive DoS limit of the decoder on payload (D3: an implementation cap, NOT a byte-exact invariant
// of the spec): the top Stage 2 bucket = 1 MiB (MAX_PLAINTEXT), plus headroom for AEAD/erasure overhead.
// Rejection from above is FrameError::PayloadTooLong, not a panic.
pub const MAX_PAYLOAD_LEN: usize = 2 * 1024 * 1024;

pub type MsgId = [u8; MSG_ID_SIZE];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FrameType {
    Relay = 0x01,
    Deliver = 0x02,
    Ack = 0x03,
}

impl FrameType {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0x01 => Some(Self::Relay),
            0x02 => Some(Self::Deliver),
            0x03 => Some(Self::Ack),
            _ => None,
        }
    }
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct OverlayFrame {
    pub frame_type: FrameType,
    pub dst_overlay: OverlayAddr,
    pub src_overlay: OverlayAddr,
    pub msg_id: MsgId,
    pub payload: Vec<u8>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FrameError {
    Truncated,
    BadVersion(u8),
    BadType(u8),
    PayloadTooLong(u32),
    LengthMismatch,
}

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Truncated => write!(f, "frame truncated"),
            Self::BadVersion(v) => write!(f, "bad frame version {v:#04x}"),
            Self::BadType(t) => write!(f, "bad frame type {t:#04x}"),
            Self::PayloadTooLong(n) => write!(f, "payload length {n} exceeds cap"),
            Self::LengthMismatch => write!(f, "payload length field mismatch"),
        }
    }
}

impl std::error::Error for FrameError {}

impl CanonicalEncode for OverlayFrame {
    fn encode(&self, buf: &mut Vec<u8>) {
        // S8: payload_len is u32; with payload > MAX_PAYLOAD_LEN truncation would distort the length.
        // The caller must not exceed the cap (decode rejects this on receive).
        debug_assert!(
            self.payload.len() <= MAX_PAYLOAD_LEN,
            "payload {} exceeds MAX_PAYLOAD_LEN",
            self.payload.len()
        );
        write_u8(buf, FRAME_VERSION);
        write_u8(buf, self.frame_type as u8);
        write_bytes(buf, &self.dst_overlay);
        write_bytes(buf, &self.src_overlay);
        write_bytes(buf, &self.msg_id);
        write_u32(buf, self.payload.len() as u32);
        write_bytes(buf, &self.payload);
    }
}

impl OverlayFrame {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(FRAME_HEADER_SIZE + self.payload.len());
        self.encode(&mut buf);
        buf
    }

    pub fn decode(input: &[u8]) -> Result<Self, FrameError> {
        if input.len() < FRAME_HEADER_SIZE {
            return Err(FrameError::Truncated);
        }
        if input[0] != FRAME_VERSION {
            return Err(FrameError::BadVersion(input[0]));
        }
        let frame_type = FrameType::from_u8(input[1]).ok_or(FrameError::BadType(input[1]))?;
        let mut o = 2usize;
        let mut dst_overlay = [0u8; OVERLAY_ADDR_SIZE];
        dst_overlay.copy_from_slice(&input[o..o + OVERLAY_ADDR_SIZE]);
        o += OVERLAY_ADDR_SIZE;
        let mut src_overlay = [0u8; OVERLAY_ADDR_SIZE];
        src_overlay.copy_from_slice(&input[o..o + OVERLAY_ADDR_SIZE]);
        o += OVERLAY_ADDR_SIZE;
        let mut msg_id = [0u8; MSG_ID_SIZE];
        msg_id.copy_from_slice(&input[o..o + MSG_ID_SIZE]);
        o += MSG_ID_SIZE;
        let mut len_bytes = [0u8; 4];
        len_bytes.copy_from_slice(&input[o..o + 4]);
        let payload_len = u32::from_le_bytes(len_bytes);
        o += 4;
        if payload_len as usize > MAX_PAYLOAD_LEN {
            return Err(FrameError::PayloadTooLong(payload_len));
        }
        if input.len() - o != payload_len as usize {
            return Err(FrameError::LengthMismatch);
        }
        Ok(Self {
            frame_type,
            dst_overlay,
            src_overlay,
            msg_id,
            payload: input[o..].to_vec(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> OverlayFrame {
        OverlayFrame {
            frame_type: FrameType::Relay,
            dst_overlay: [0xBB; 32],
            src_overlay: [0xAA; 32],
            msg_id: [0x11; 16],
            payload: b"sealed-e2e-envelope".to_vec(),
        }
    }

    #[test]
    fn roundtrip_all_types() {
        for t in [FrameType::Relay, FrameType::Deliver, FrameType::Ack] {
            let mut f = sample();
            f.frame_type = t;
            if t == FrameType::Ack {
                f.payload.clear();
            }
            assert_eq!(OverlayFrame::decode(&f.to_bytes()).unwrap(), f);
        }
    }

    #[test]
    fn header_size_is_86() {
        let mut f = sample();
        f.payload.clear();
        assert_eq!(f.to_bytes().len(), FRAME_HEADER_SIZE);
    }

    #[test]
    fn rejects_bad_version_type_and_lengths() {
        let f = sample();
        let b = f.to_bytes();

        let mut bad = b.clone();
        bad[0] = 0x02;
        assert_eq!(
            OverlayFrame::decode(&bad),
            Err(FrameError::BadVersion(0x02))
        );

        let mut bad = b.clone();
        bad[1] = 0x00;
        assert_eq!(OverlayFrame::decode(&bad), Err(FrameError::BadType(0x00)));

        assert_eq!(
            OverlayFrame::decode(&b[..FRAME_HEADER_SIZE - 1]),
            Err(FrameError::Truncated)
        );

        let mut bad = b.clone();
        bad.pop();
        assert_eq!(OverlayFrame::decode(&bad), Err(FrameError::LengthMismatch));

        let mut long = b;
        let cap = (MAX_PAYLOAD_LEN as u32 + 1).to_le_bytes();
        long[82..86].copy_from_slice(&cap);
        assert_eq!(
            OverlayFrame::decode(&long),
            Err(FrameError::PayloadTooLong(MAX_PAYLOAD_LEN as u32 + 1))
        );
    }

    #[test]
    fn roundtrip_1000_random_payload_lengths() {
        let mut st = 0x853C49E6748FEA9Bu64;
        for i in 0..1000usize {
            st = st
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            let len = (st >> 33) as usize % 512;
            let mut f = sample();
            f.payload = vec![(i % 251) as u8; len];
            assert_eq!(OverlayFrame::decode(&f.to_bytes()).unwrap(), f);
        }
    }
}
