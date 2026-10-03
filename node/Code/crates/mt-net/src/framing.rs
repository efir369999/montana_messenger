// spec, раздел "Сетевой уровень → Обфускация транспорта → Uniform Framing"
//
// Frame layout (1024 B fixed):
//   flags         1B   (0x01 data | 0x02 padding | 0x04 continuation;
//                       data | continuation допустимо для multi-frame
//                       ProtocolMessage; padding | continuation запрещено)
//   length        2B   u16 LE (≤ 1021)
//   payload      1021B (length bytes data, далее random padding)

use alloc::vec::Vec;

use mt_codec::{write_bytes, write_u16, write_u8};

use crate::error::NetError;

pub const FRAME_SIZE: usize = 1024;
pub const FRAME_HEADER_SIZE: usize = 3;
pub const FRAME_PAYLOAD_CAP: usize = FRAME_SIZE - FRAME_HEADER_SIZE; // 1021

pub const FLAG_DATA: u8 = 0x01;
pub const FLAG_PADDING: u8 = 0x02;
pub const FLAG_CONTINUATION: u8 = 0x04;

pub const MAX_BURST_FRAMES: u8 = 8;
pub const MIN_PADDING_RATIO_NUM: u32 = 20;
pub const MIN_PADDING_RATIO_DEN: u32 = 100;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub flags: u8,
    pub length: u16,
    pub payload: [u8; FRAME_PAYLOAD_CAP],
}

impl Frame {
    pub fn data(payload: &[u8], continuation: bool) -> Result<Frame, NetError> {
        if payload.len() > FRAME_PAYLOAD_CAP {
            return Err(NetError::PayloadTooLarge);
        }
        let mut buf = [0u8; FRAME_PAYLOAD_CAP];
        buf[..payload.len()].copy_from_slice(payload);
        let mut flags = FLAG_DATA;
        if continuation {
            flags |= FLAG_CONTINUATION;
        }
        Ok(Frame {
            flags,
            length: payload.len() as u16,
            payload: buf,
        })
    }

    pub fn padding(random_bytes: &[u8; FRAME_PAYLOAD_CAP]) -> Frame {
        Frame {
            flags: FLAG_PADDING,
            length: 0,
            payload: *random_bytes,
        }
    }

    pub fn validate(&self) -> Result<(), NetError> {
        if self.length as usize > FRAME_PAYLOAD_CAP {
            return Err(NetError::PayloadLengthMismatch);
        }
        let known_bits = FLAG_DATA | FLAG_PADDING | FLAG_CONTINUATION;
        if self.flags & !known_bits != 0 {
            return Err(NetError::InvalidPayloadField);
        }
        // padding | continuation запрещено
        if (self.flags & FLAG_PADDING) != 0 && (self.flags & FLAG_CONTINUATION) != 0 {
            return Err(NetError::InvalidPayloadField);
        }
        // data и padding взаимоисключают
        let is_data = self.flags & FLAG_DATA != 0;
        let is_padding = self.flags & FLAG_PADDING != 0;
        if is_data && is_padding {
            return Err(NetError::InvalidPayloadField);
        }
        if !is_data && !is_padding {
            return Err(NetError::InvalidPayloadField);
        }
        // padding frames must have length = 0
        if is_padding && self.length != 0 {
            return Err(NetError::InvalidPayloadField);
        }
        Ok(())
    }
}

pub fn encode_frame(frame: &Frame, buf: &mut Vec<u8>) -> Result<(), NetError> {
    frame.validate()?;
    write_u8(buf, frame.flags);
    write_u16(buf, frame.length);
    write_bytes(buf, &frame.payload);
    Ok(())
}

pub fn decode_frame(input: &[u8]) -> Result<Frame, NetError> {
    if input.len() != FRAME_SIZE {
        return Err(NetError::PayloadLengthMismatch);
    }
    let flags = input[0];
    let mut len_bytes = [0u8; 2];
    len_bytes.copy_from_slice(&input[1..3]);
    let length = u16::from_le_bytes(len_bytes);
    let mut payload = [0u8; FRAME_PAYLOAD_CAP];
    payload.copy_from_slice(&input[3..]);
    let f = Frame {
        flags,
        length,
        payload,
    };
    f.validate()?;
    Ok(f)
}

pub fn encode_message_to_frames(
    message_bytes: &[u8],
    padding_provider: &mut dyn FnMut() -> [u8; FRAME_PAYLOAD_CAP],
) -> Vec<Frame> {
    if message_bytes.is_empty() {
        return Vec::new();
    }
    let chunks: Vec<&[u8]> = message_bytes.chunks(FRAME_PAYLOAD_CAP).collect();
    let total = chunks.len();
    let mut frames = Vec::with_capacity(total);
    for (i, chunk) in chunks.iter().enumerate() {
        let continuation = i + 1 < total;
        // last chunk may be short — pad-fill remaining bytes with random
        let mut full = [0u8; FRAME_PAYLOAD_CAP];
        full[..chunk.len()].copy_from_slice(chunk);
        if chunk.len() < FRAME_PAYLOAD_CAP {
            let pad = padding_provider();
            full[chunk.len()..].copy_from_slice(&pad[chunk.len()..]);
        }
        let mut flags = FLAG_DATA;
        if continuation {
            flags |= FLAG_CONTINUATION;
        }
        frames.push(Frame {
            flags,
            length: chunk.len() as u16,
            payload: full,
        });
    }
    frames
}

pub fn decode_message_from_frames(frames: &[Frame]) -> Result<Vec<u8>, NetError> {
    if frames.is_empty() {
        return Err(NetError::TruncatedPayload);
    }
    let mut out = Vec::with_capacity(frames.len() * FRAME_PAYLOAD_CAP);
    for (i, f) in frames.iter().enumerate() {
        f.validate()?;
        if (f.flags & FLAG_DATA) == 0 {
            return Err(NetError::InvalidPayloadField);
        }
        let last = i + 1 == frames.len();
        let has_continuation = (f.flags & FLAG_CONTINUATION) != 0;
        if last && has_continuation {
            return Err(NetError::TruncatedPayload);
        }
        if !last && !has_continuation {
            return Err(NetError::InvalidPayloadField);
        }
        out.extend_from_slice(&f.payload[..f.length as usize]);
    }
    Ok(out)
}

pub struct FrameWindowState {
    data_count: u32,
    padding_count: u32,
}

impl FrameWindowState {
    pub const fn new() -> Self {
        FrameWindowState {
            data_count: 0,
            padding_count: 0,
        }
    }

    pub fn record(&mut self, frame: &Frame) {
        if (frame.flags & FLAG_PADDING) != 0 {
            self.padding_count += 1;
        } else {
            self.data_count += 1;
        }
    }

    pub fn meets_padding_ratio(&self) -> bool {
        let total = self.data_count + self.padding_count;
        if total == 0 {
            return true;
        }
        // padding_count / total >= 20 / 100
        // <=> padding_count * 100 >= total * 20
        (self.padding_count as u64) * (MIN_PADDING_RATIO_DEN as u64)
            >= (total as u64) * (MIN_PADDING_RATIO_NUM as u64)
    }

    pub fn reset(&mut self) {
        self.data_count = 0;
        self.padding_count = 0;
    }

    pub fn data_count(&self) -> u32 {
        self.data_count
    }

    pub fn padding_count(&self) -> u32 {
        self.padding_count
    }
}

impl Default for FrameWindowState {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(feature = "csprng")]
pub fn os_csprng_padding() -> Result<[u8; FRAME_PAYLOAD_CAP], NetError> {
    let mut buf = [0u8; FRAME_PAYLOAD_CAP];
    getrandom::getrandom(&mut buf).map_err(|_| NetError::EntropyUnavailable)?;
    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    fn fake_padding() -> [u8; FRAME_PAYLOAD_CAP] {
        [0u8; FRAME_PAYLOAD_CAP]
    }

    #[test]
    fn frame_data_roundtrip() {
        let f = Frame::data(b"hello", false).unwrap();
        let mut buf = Vec::new();
        encode_frame(&f, &mut buf).unwrap();
        assert_eq!(buf.len(), FRAME_SIZE);
        let dec = decode_frame(&buf).unwrap();
        assert_eq!(dec, f);
    }

    #[test]
    fn frame_padding_roundtrip() {
        let pad = [0xCAu8; FRAME_PAYLOAD_CAP];
        let f = Frame::padding(&pad);
        let mut buf = Vec::new();
        encode_frame(&f, &mut buf).unwrap();
        let dec = decode_frame(&buf).unwrap();
        assert_eq!(dec, f);
    }

    #[test]
    fn frame_data_too_large_rejected() {
        let big = vec![0u8; FRAME_PAYLOAD_CAP + 1];
        assert_eq!(Frame::data(&big, false), Err(NetError::PayloadTooLarge));
    }

    #[test]
    fn frame_validate_rejects_padding_with_length() {
        let f = Frame {
            flags: FLAG_PADDING,
            length: 1,
            payload: [0; FRAME_PAYLOAD_CAP],
        };
        assert_eq!(f.validate(), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn frame_validate_rejects_padding_with_continuation() {
        let f = Frame {
            flags: FLAG_PADDING | FLAG_CONTINUATION,
            length: 0,
            payload: [0; FRAME_PAYLOAD_CAP],
        };
        assert_eq!(f.validate(), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn frame_validate_rejects_unknown_flags() {
        let f = Frame {
            flags: 0x10,
            length: 0,
            payload: [0; FRAME_PAYLOAD_CAP],
        };
        assert_eq!(f.validate(), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn frame_validate_rejects_zero_flags() {
        let f = Frame {
            flags: 0x00,
            length: 0,
            payload: [0; FRAME_PAYLOAD_CAP],
        };
        assert_eq!(f.validate(), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn multi_frame_message_roundtrip() {
        let msg: Vec<u8> = (0..3500).map(|i| (i & 0xFF) as u8).collect();
        let frames = encode_message_to_frames(&msg, &mut fake_padding);
        assert_eq!(frames.len(), 4); // ceil(3500 / 1021) = 4
                                     // continuation flag check
        for (i, f) in frames.iter().enumerate() {
            let cont = (f.flags & FLAG_CONTINUATION) != 0;
            if i + 1 < frames.len() {
                assert!(cont, "frame {} must have continuation", i);
            } else {
                assert!(!cont, "last frame must clear continuation");
            }
        }
        let decoded = decode_message_from_frames(&frames).unwrap();
        assert_eq!(decoded, msg);
    }

    #[test]
    fn empty_message_yields_no_frames() {
        let frames = encode_message_to_frames(&[], &mut fake_padding);
        assert!(frames.is_empty());
    }

    #[test]
    fn decode_frames_rejects_dangling_continuation() {
        let f = Frame {
            flags: FLAG_DATA | FLAG_CONTINUATION,
            length: 5,
            payload: [0; FRAME_PAYLOAD_CAP],
        };
        assert_eq!(
            decode_message_from_frames(&[f]),
            Err(NetError::TruncatedPayload)
        );
    }

    #[test]
    fn decode_frames_rejects_missing_continuation_in_middle() {
        let f1 = Frame {
            flags: FLAG_DATA,
            length: 5,
            payload: [0; FRAME_PAYLOAD_CAP],
        };
        let f2 = Frame {
            flags: FLAG_DATA,
            length: 5,
            payload: [0; FRAME_PAYLOAD_CAP],
        };
        assert_eq!(
            decode_message_from_frames(&[f1, f2]),
            Err(NetError::InvalidPayloadField)
        );
    }

    #[test]
    fn padding_ratio_state_default_pass() {
        let s = FrameWindowState::new();
        assert!(s.meets_padding_ratio());
    }

    #[test]
    fn padding_ratio_state_below_threshold_fails() {
        let mut s = FrameWindowState::new();
        let data = Frame::data(b"x", false).unwrap();
        let pad = Frame::padding(&[0; FRAME_PAYLOAD_CAP]);
        for _ in 0..9 {
            s.record(&data);
        }
        s.record(&pad);
        // 1 padding из 10 = 10% < 20%
        assert!(!s.meets_padding_ratio());
    }

    #[test]
    fn padding_ratio_state_meets_threshold_exact_20() {
        let mut s = FrameWindowState::new();
        let data = Frame::data(b"x", false).unwrap();
        let pad = Frame::padding(&[0; FRAME_PAYLOAD_CAP]);
        for _ in 0..8 {
            s.record(&data);
        }
        for _ in 0..2 {
            s.record(&pad);
        }
        // 2 padding из 10 = 20% — порог достигнут
        assert!(s.meets_padding_ratio());
    }
}
