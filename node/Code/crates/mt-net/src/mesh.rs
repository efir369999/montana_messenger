// spec, раздел "Сетевой уровень → Mesh Transport" + apply_mesh_frame
//   нормативная формулировка
//
// MeshFrame wire format:
//   flags             1B   (bit0 = continuation)
//   fragment_index    1B
//   total_fragments   1B   (≤ 255)
//   recipient_hint   32B   (0xFF×32 = broadcast)
//   payload          var   (≤ MTU практический)

use alloc::collections::{BTreeMap, BTreeSet};
use alloc::vec::Vec;

use mt_codec::{write_bytes, write_u8};

use crate::error::NetError;

pub const MESH_RECIPIENT_HINT_SIZE: usize = 32;
pub const MESH_BROADCAST_HINT: [u8; 32] = [0xFF; MESH_RECIPIENT_HINT_SIZE];
pub const MESH_FLAG_CONTINUATION: u8 = 0x01;
pub const MESH_HEADER_SIZE: usize = 1 + 1 + 1 + MESH_RECIPIENT_HINT_SIZE; // = 35

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeshFrame {
    pub flags: u8,
    pub fragment_index: u8,
    pub total_fragments: u8,
    pub recipient_hint: [u8; MESH_RECIPIENT_HINT_SIZE],
    pub payload: Vec<u8>,
}

impl MeshFrame {
    pub fn try_new(
        flags: u8,
        fragment_index: u8,
        total_fragments: u8,
        recipient_hint: [u8; MESH_RECIPIENT_HINT_SIZE],
        payload: Vec<u8>,
    ) -> Result<Self, NetError> {
        let f = MeshFrame {
            flags,
            fragment_index,
            total_fragments,
            recipient_hint,
            payload,
        };
        f.validate()?;
        Ok(f)
    }

    pub fn validate(&self) -> Result<(), NetError> {
        if self.total_fragments == 0 {
            return Err(NetError::InvalidPayloadField);
        }
        if self.fragment_index >= self.total_fragments {
            return Err(NetError::InvalidPayloadField);
        }
        let known_bits = MESH_FLAG_CONTINUATION;
        if self.flags & !known_bits != 0 {
            return Err(NetError::InvalidPayloadField);
        }
        Ok(())
    }

    pub fn is_broadcast(&self) -> bool {
        self.recipient_hint == MESH_BROADCAST_HINT
    }
}

pub fn encode_mesh_frame(frame: &MeshFrame, buf: &mut Vec<u8>) -> Result<(), NetError> {
    frame.validate()?;
    write_u8(buf, frame.flags);
    write_u8(buf, frame.fragment_index);
    write_u8(buf, frame.total_fragments);
    write_bytes(buf, &frame.recipient_hint);
    write_bytes(buf, &frame.payload);
    Ok(())
}

pub fn decode_mesh_frame(input: &[u8]) -> Result<MeshFrame, NetError> {
    if input.len() < MESH_HEADER_SIZE {
        return Err(NetError::TruncatedHeader);
    }
    let flags = input[0];
    let fragment_index = input[1];
    let total_fragments = input[2];
    let mut recipient_hint = [0u8; MESH_RECIPIENT_HINT_SIZE];
    recipient_hint.copy_from_slice(&input[3..3 + MESH_RECIPIENT_HINT_SIZE]);
    let payload = input[MESH_HEADER_SIZE..].to_vec();
    let f = MeshFrame {
        flags,
        fragment_index,
        total_fragments,
        recipient_hint,
        payload,
    };
    f.validate()?;
    Ok(f)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MeshIntake {
    Accepted,
    AcceptedComplete(Vec<u8>),
    Rejected(MeshRejectReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MeshRejectReason {
    InvalidStructure,
    NonceReplay,
    RateLimit,
    LowMemory,
}

pub type MeshFragmentKey = ([u8; 32], [u8; 32]);

#[derive(Debug, Default)]
pub struct LocalMeshState {
    used_nonces: BTreeMap<[u8; 32], BTreeSet<[u8; 32]>>,
    fragments: BTreeMap<MeshFragmentKey, Vec<Option<Vec<u8>>>>,
    rate_window_intake: BTreeMap<[u8; 32], u32>,
    pub max_intake_per_window: u32,
    pub max_used_nonces_per_sender: usize,
}

impl LocalMeshState {
    pub fn new() -> Self {
        LocalMeshState {
            used_nonces: BTreeMap::new(),
            fragments: BTreeMap::new(),
            rate_window_intake: BTreeMap::new(),
            max_intake_per_window: 8, // baseline 1 fps × max_burst 8
            max_used_nonces_per_sender: 64,
        }
    }

    pub fn reset_rate_window(&mut self) {
        self.rate_window_intake.clear();
    }

    pub fn nonce_count(&self, sender_pubkey_hash: &[u8; 32]) -> usize {
        self.used_nonces
            .get(sender_pubkey_hash)
            .map(|s| s.len())
            .unwrap_or(0)
    }
}

pub fn apply_mesh_frame(
    frame: &MeshFrame,
    sender_pubkey_hash: &[u8; 32],
    mesh_session_nonce: &[u8; 32],
    state: &mut LocalMeshState,
) -> MeshIntake {
    // Step 1: structure validation
    if frame.validate().is_err() {
        return MeshIntake::Rejected(MeshRejectReason::InvalidStructure);
    }

    // Step 2: nonce replay tracking (IBT mesh layer уже verified signature
    // и attached nonce; здесь only dedup для apply level)
    let nonces = state.used_nonces.entry(*sender_pubkey_hash).or_default();
    if nonces.contains(mesh_session_nonce) {
        return MeshIntake::Rejected(MeshRejectReason::NonceReplay);
    }
    if nonces.len() >= state.max_used_nonces_per_sender {
        return MeshIntake::Rejected(MeshRejectReason::LowMemory);
    }

    // Step 3: frame intake rate per Backpressure Rule B2
    let intake = state
        .rate_window_intake
        .entry(*sender_pubkey_hash)
        .or_insert(0);
    *intake += 1;
    if *intake > state.max_intake_per_window {
        return MeshIntake::Rejected(MeshRejectReason::RateLimit);
    }

    // Step 4-5: fragment assembly
    let key = (*sender_pubkey_hash, frame.recipient_hint);
    let fragment_buf = state.fragments.entry(key).or_insert_with(|| {
        let mut v = Vec::with_capacity(frame.total_fragments as usize);
        v.resize(frame.total_fragments as usize, None);
        v
    });
    if fragment_buf.len() != frame.total_fragments as usize {
        // total_fragments diverged within same msg — invalid
        return MeshIntake::Rejected(MeshRejectReason::InvalidStructure);
    }
    fragment_buf[frame.fragment_index as usize] = Some(frame.payload.clone());

    // check completeness
    if fragment_buf.iter().all(|f| f.is_some()) {
        let mut full = Vec::new();
        for f in fragment_buf.iter().flatten() {
            full.extend_from_slice(f);
        }
        state.fragments.remove(&key);
        // Step 6: register nonce after full accept
        nonces.insert(*mesh_session_nonce);
        return MeshIntake::AcceptedComplete(full);
    }

    // single accepted fragment
    nonces.insert(*mesh_session_nonce);
    MeshIntake::Accepted
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    fn make_frame(idx: u8, total: u8, recipient: [u8; 32], payload: Vec<u8>) -> MeshFrame {
        let flags = if idx + 1 < total {
            MESH_FLAG_CONTINUATION
        } else {
            0
        };
        MeshFrame {
            flags,
            fragment_index: idx,
            total_fragments: total,
            recipient_hint: recipient,
            payload,
        }
    }

    #[test]
    fn frame_encode_decode_roundtrip() {
        let f = make_frame(0, 1, MESH_BROADCAST_HINT, vec![0x55; 100]);
        let mut buf = Vec::new();
        encode_mesh_frame(&f, &mut buf).unwrap();
        assert_eq!(buf.len(), MESH_HEADER_SIZE + 100);
        let dec = decode_mesh_frame(&buf).unwrap();
        assert_eq!(dec, f);
    }

    #[test]
    fn frame_validate_total_zero_rejected() {
        let f = MeshFrame {
            flags: 0,
            fragment_index: 0,
            total_fragments: 0,
            recipient_hint: [0; 32],
            payload: vec![],
        };
        assert_eq!(f.validate(), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn frame_validate_index_oob_rejected() {
        let f = MeshFrame {
            flags: 0,
            fragment_index: 5,
            total_fragments: 3,
            recipient_hint: [0; 32],
            payload: vec![],
        };
        assert_eq!(f.validate(), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn apply_single_fragment_accepted_complete() {
        let mut state = LocalMeshState::new();
        let sender = [0xAA; 32];
        let nonce = [0xBB; 32];
        let f = make_frame(0, 1, MESH_BROADCAST_HINT, vec![0xDE, 0xAD]);
        let intake = apply_mesh_frame(&f, &sender, &nonce, &mut state);
        assert_eq!(intake, MeshIntake::AcceptedComplete(vec![0xDE, 0xAD]));
    }

    #[test]
    fn apply_multifragment_assembles() {
        let mut state = LocalMeshState::new();
        let sender = [0xAA; 32];
        let recipient = [0x11; 32];
        let f0 = make_frame(0, 3, recipient, vec![1, 2]);
        let f1 = make_frame(1, 3, recipient, vec![3, 4]);
        let f2 = make_frame(2, 3, recipient, vec![5, 6]);
        let r0 = apply_mesh_frame(&f0, &sender, &[0x01; 32], &mut state);
        assert_eq!(r0, MeshIntake::Accepted);
        let r1 = apply_mesh_frame(&f1, &sender, &[0x02; 32], &mut state);
        assert_eq!(r1, MeshIntake::Accepted);
        let r2 = apply_mesh_frame(&f2, &sender, &[0x03; 32], &mut state);
        assert_eq!(r2, MeshIntake::AcceptedComplete(vec![1, 2, 3, 4, 5, 6]));
    }

    #[test]
    fn apply_nonce_replay_rejected() {
        let mut state = LocalMeshState::new();
        let sender = [0xAA; 32];
        let nonce = [0xBB; 32];
        let f = make_frame(0, 1, MESH_BROADCAST_HINT, vec![1, 2, 3]);
        let _ = apply_mesh_frame(&f, &sender, &nonce, &mut state);
        let r = apply_mesh_frame(&f, &sender, &nonce, &mut state);
        assert_eq!(r, MeshIntake::Rejected(MeshRejectReason::NonceReplay));
    }

    #[test]
    fn apply_rate_limit_rejected() {
        let mut state = LocalMeshState::new();
        state.max_intake_per_window = 2;
        let sender = [0xAA; 32];
        for i in 0..3u8 {
            let f = make_frame(0, 1, MESH_BROADCAST_HINT, vec![i]);
            let mut nonce = [0; 32];
            nonce[0] = i;
            let r = apply_mesh_frame(&f, &sender, &nonce, &mut state);
            if i < 2 {
                assert!(matches!(
                    r,
                    MeshIntake::Accepted | MeshIntake::AcceptedComplete(_)
                ));
            } else {
                assert_eq!(r, MeshIntake::Rejected(MeshRejectReason::RateLimit));
            }
        }
    }
}
