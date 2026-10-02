// spec, раздел "Сетевой уровень → Store-and-Forward Semantics" +
//   apply_store_and_forward нормативная формулировка + Storage Card sf_buffer
//
// SF Envelope layout:
//   recipient_hint    32B
//   ttl_window         4B  u32 LE
//   fragment_index     1B
//   total_fragments    1B
//   ciphertext        var
//   sender_signature 3309B  ML-DSA-65

use alloc::collections::BTreeMap;
use alloc::vec::Vec;

use mt_codec::{write_bytes, write_u32, write_u8};

use crate::error::NetError;

pub const SF_RECIPIENT_HINT_SIZE: usize = 32;
pub const SF_SENDER_SIG_SIZE: usize = 3309;
pub const SF_HEADER_SIZE: usize = SF_RECIPIENT_HINT_SIZE + 4 + 1 + 1; // 38
pub const SF_TTL_HARD_CAP_TAU1: u32 = 24;
pub const SF_PER_SENDER_QUOTA_PER_TAU1: u32 = 256;
pub const SF_TOTAL_HARD_CAP_BYTES: u64 = 1 << 30; // 1 GB

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SfEnvelope {
    pub recipient_hint: [u8; SF_RECIPIENT_HINT_SIZE],
    pub ttl_window: u32,
    pub fragment_index: u8,
    pub total_fragments: u8,
    pub ciphertext: Vec<u8>,
    pub sender_signature: Vec<u8>,
}

impl SfEnvelope {
    #[allow(clippy::too_many_arguments)]
    pub fn try_new(
        recipient_hint: [u8; SF_RECIPIENT_HINT_SIZE],
        ttl_window: u32,
        fragment_index: u8,
        total_fragments: u8,
        ciphertext: Vec<u8>,
        sender_signature: Vec<u8>,
        current_window: u32,
        tau1: u32,
    ) -> Result<Self, NetError> {
        let env = SfEnvelope {
            recipient_hint,
            ttl_window,
            fragment_index,
            total_fragments,
            ciphertext,
            sender_signature,
        };
        env.validate(current_window, tau1)?;
        Ok(env)
    }

    pub fn validate(&self, current_window: u32, tau1: u32) -> Result<(), NetError> {
        if self.sender_signature.len() != SF_SENDER_SIG_SIZE {
            return Err(NetError::InvalidPayloadField);
        }
        if self.total_fragments == 0 {
            return Err(NetError::InvalidPayloadField);
        }
        if self.fragment_index >= self.total_fragments {
            return Err(NetError::InvalidPayloadField);
        }
        let max_ttl = current_window.saturating_add(SF_TTL_HARD_CAP_TAU1.saturating_mul(tau1));
        if self.ttl_window <= current_window {
            return Err(NetError::InvalidPayloadField);
        }
        if self.ttl_window > max_ttl {
            return Err(NetError::InvalidPayloadField);
        }
        Ok(())
    }

    pub fn signed_message(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(SF_HEADER_SIZE + self.ciphertext.len());
        write_bytes(&mut buf, &self.recipient_hint);
        write_u32(&mut buf, self.ttl_window);
        write_u8(&mut buf, self.fragment_index);
        write_u8(&mut buf, self.total_fragments);
        write_bytes(&mut buf, &self.ciphertext);
        buf
    }
}

pub fn encode_sf_envelope(env: &SfEnvelope, buf: &mut Vec<u8>) -> Result<(), NetError> {
    if env.sender_signature.len() != SF_SENDER_SIG_SIZE {
        return Err(NetError::InvalidPayloadField);
    }
    write_bytes(buf, &env.recipient_hint);
    write_u32(buf, env.ttl_window);
    write_u8(buf, env.fragment_index);
    write_u8(buf, env.total_fragments);
    write_bytes(buf, &env.ciphertext);
    write_bytes(buf, &env.sender_signature);
    Ok(())
}

pub fn decode_sf_envelope(input: &[u8]) -> Result<SfEnvelope, NetError> {
    if input.len() < SF_HEADER_SIZE + SF_SENDER_SIG_SIZE {
        return Err(NetError::TruncatedPayload);
    }
    let mut recipient_hint = [0u8; SF_RECIPIENT_HINT_SIZE];
    recipient_hint.copy_from_slice(&input[..SF_RECIPIENT_HINT_SIZE]);
    let mut ttl_bytes = [0u8; 4];
    ttl_bytes.copy_from_slice(&input[32..36]);
    let ttl_window = u32::from_le_bytes(ttl_bytes);
    let fragment_index = input[36];
    let total_fragments = input[37];
    let sig_start = input.len() - SF_SENDER_SIG_SIZE;
    let ciphertext = input[SF_HEADER_SIZE..sig_start].to_vec();
    let sender_signature = input[sig_start..].to_vec();
    Ok(SfEnvelope {
        recipient_hint,
        ttl_window,
        fragment_index,
        total_fragments,
        ciphertext,
        sender_signature,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SfIntake {
    Buffered,
    DeliveredLocally(Vec<u8>),
    Rejected(SfRejectReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SfRejectReason {
    InvalidStructure,
    InvalidSignature,
    SenderQuotaExceeded,
    ForwardingRevoked,
    TotalQuotaExceeded,
    DecryptFailure,
}

#[derive(Debug, Default)]
pub struct LocalSfState {
    pub buffer: BTreeMap<[u8; 32], Vec<SfEnvelope>>,
    pub sender_quotas: BTreeMap<[u8; 32], u32>,
    pub revoked: BTreeMap<[u8; 32], u32>,
    pub vip_whitelist: BTreeMap<[u8; 32], ()>,
    pub total_bytes: u64,
}

impl LocalSfState {
    pub fn new() -> Self {
        Default::default()
    }

    pub fn reset_quota_window(&mut self) {
        self.sender_quotas.clear();
    }

    pub fn revoke_forwarding(&mut self, recipient_hint: [u8; 32], until_window: u32) {
        self.revoked.insert(recipient_hint, until_window);
    }

    pub fn add_vip(&mut self, sender_pubkey_hash: [u8; 32]) {
        self.vip_whitelist.insert(sender_pubkey_hash, ());
    }
}

#[allow(clippy::too_many_arguments)]
pub fn apply_store_and_forward(
    envelope: &SfEnvelope,
    sender_pubkey_hash: &[u8; 32],
    signature_valid: bool,
    is_local_recipient: bool,
    local_decrypt: Option<Vec<u8>>,
    current_window: u32,
    tau1: u32,
    state: &mut LocalSfState,
) -> SfIntake {
    // Step 1: structure
    if envelope.validate(current_window, tau1).is_err() {
        return SfIntake::Rejected(SfRejectReason::InvalidStructure);
    }
    // Step 2: signature already verified externally (caller отвечает за crypto)
    if !signature_valid {
        return SfIntake::Rejected(SfRejectReason::InvalidSignature);
    }
    // Step 3: per-sender quota
    let quota = state.sender_quotas.entry(*sender_pubkey_hash).or_insert(0);
    *quota += 1;
    if *quota > SF_PER_SENDER_QUOTA_PER_TAU1 {
        return SfIntake::Rejected(SfRejectReason::SenderQuotaExceeded);
    }
    // Step 4: recipient ack revocation
    if let Some(&until_w) = state.revoked.get(&envelope.recipient_hint) {
        if current_window <= until_w {
            return SfIntake::Rejected(SfRejectReason::ForwardingRevoked);
        }
    }
    // Step 6: recipient determination
    if is_local_recipient {
        match local_decrypt {
            Some(plaintext) => return SfIntake::DeliveredLocally(plaintext),
            None => return SfIntake::Rejected(SfRejectReason::DecryptFailure),
        }
    }
    // Step 5: total buffer quota check
    let env_size = (SF_HEADER_SIZE + envelope.ciphertext.len() + SF_SENDER_SIG_SIZE) as u64;
    let prospective = state.total_bytes.saturating_add(env_size);
    if prospective > SF_TOTAL_HARD_CAP_BYTES {
        if !state.vip_whitelist.contains_key(sender_pubkey_hash) {
            return SfIntake::Rejected(SfRejectReason::TotalQuotaExceeded);
        }
        // VIP path: evict oldest non-VIP — simplified: drop earliest buffer
        if let Some((&first_key, _)) = state.buffer.iter().next() {
            if let Some(envs) = state.buffer.remove(&first_key) {
                let freed: u64 = envs
                    .iter()
                    .map(|e| (SF_HEADER_SIZE + e.ciphertext.len() + SF_SENDER_SIG_SIZE) as u64)
                    .sum();
                state.total_bytes = state.total_bytes.saturating_sub(freed);
            }
        }
    }
    // Buffered for forwarding
    state
        .buffer
        .entry(envelope.recipient_hint)
        .or_default()
        .push(envelope.clone());
    state.total_bytes = state.total_bytes.saturating_add(env_size);
    SfIntake::Buffered
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    fn make_env(recipient: [u8; 32], ttl: u32, ciphertext: Vec<u8>) -> SfEnvelope {
        SfEnvelope {
            recipient_hint: recipient,
            ttl_window: ttl,
            fragment_index: 0,
            total_fragments: 1,
            ciphertext,
            sender_signature: vec![0xAA; SF_SENDER_SIG_SIZE],
        }
    }

    #[test]
    fn envelope_validate_ok() {
        let e = make_env([0x11; 32], 100, vec![0; 64]);
        assert!(e.validate(50, 60).is_ok());
    }

    #[test]
    fn envelope_validate_ttl_in_past_rejected() {
        let e = make_env([0x11; 32], 50, vec![]);
        assert_eq!(e.validate(50, 60), Err(NetError::InvalidPayloadField));
        assert_eq!(e.validate(100, 60), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn envelope_validate_ttl_too_far_rejected() {
        // current=0, max_ttl = 24 * 60 = 1440
        let e = make_env([0x11; 32], 1500, vec![]);
        assert_eq!(e.validate(0, 60), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn envelope_validate_bad_sig_size_rejected() {
        let mut e = make_env([0x11; 32], 100, vec![]);
        e.sender_signature = vec![0; 100];
        assert_eq!(e.validate(50, 60), Err(NetError::InvalidPayloadField));
    }

    #[test]
    fn envelope_encode_decode_roundtrip() {
        let e = make_env([0x11; 32], 100, vec![0xBB; 64]);
        let mut buf = Vec::new();
        encode_sf_envelope(&e, &mut buf).unwrap();
        let dec = decode_sf_envelope(&buf).unwrap();
        assert_eq!(dec, e);
    }

    #[test]
    fn apply_buffered_when_remote_recipient() {
        let mut s = LocalSfState::new();
        let env = make_env([0x11; 32], 100, vec![0; 64]);
        let r = apply_store_and_forward(&env, &[0xAA; 32], true, false, None, 50, 60, &mut s);
        assert_eq!(r, SfIntake::Buffered);
        assert!(s.total_bytes > 0);
    }

    #[test]
    fn apply_delivered_locally_when_local_recipient_with_decrypt() {
        let mut s = LocalSfState::new();
        let env = make_env([0x11; 32], 100, vec![0; 64]);
        let r = apply_store_and_forward(
            &env,
            &[0xAA; 32],
            true,
            true,
            Some(vec![1, 2, 3]),
            50,
            60,
            &mut s,
        );
        assert_eq!(r, SfIntake::DeliveredLocally(vec![1, 2, 3]));
    }

    #[test]
    fn apply_decrypt_failure_when_local_no_plaintext() {
        let mut s = LocalSfState::new();
        let env = make_env([0x11; 32], 100, vec![0; 64]);
        let r = apply_store_and_forward(&env, &[0xAA; 32], true, true, None, 50, 60, &mut s);
        assert_eq!(r, SfIntake::Rejected(SfRejectReason::DecryptFailure));
    }

    #[test]
    fn apply_rejects_invalid_signature() {
        let mut s = LocalSfState::new();
        let env = make_env([0x11; 32], 100, vec![0; 64]);
        let r = apply_store_and_forward(&env, &[0xAA; 32], false, false, None, 50, 60, &mut s);
        assert_eq!(r, SfIntake::Rejected(SfRejectReason::InvalidSignature));
    }

    #[test]
    fn apply_rejects_sender_quota_exceeded() {
        let mut s = LocalSfState::new();
        let env = make_env([0x11; 32], 100, vec![0; 64]);
        for _ in 0..SF_PER_SENDER_QUOTA_PER_TAU1 {
            let _ = apply_store_and_forward(&env, &[0xAA; 32], true, false, None, 50, 60, &mut s);
        }
        let r = apply_store_and_forward(&env, &[0xAA; 32], true, false, None, 50, 60, &mut s);
        assert_eq!(r, SfIntake::Rejected(SfRejectReason::SenderQuotaExceeded));
    }

    #[test]
    fn apply_rejects_when_forwarding_revoked() {
        let mut s = LocalSfState::new();
        s.revoke_forwarding([0x11; 32], 100);
        let env = make_env([0x11; 32], 200, vec![0; 64]);
        let r = apply_store_and_forward(&env, &[0xAA; 32], true, false, None, 50, 60, &mut s);
        assert_eq!(r, SfIntake::Rejected(SfRejectReason::ForwardingRevoked));
    }
}
