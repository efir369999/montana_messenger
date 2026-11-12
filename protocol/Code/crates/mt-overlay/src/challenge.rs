//! Challenge-response proof of ownership of overlay_addr / epoch_tag on account_key (ML-DSA-65).
//! Spec: Montana P2P Network, "Common primitive: challenge-response on account_key"
//! and Stage 1, step 0-a "Wire format of the registration prologue".

use mt_crypto::{sign, verify, CryptoError, PublicKey, SecretKey, Signature, PUBLIC_KEY_SIZE};
use mt_state::{derive_account_id, SUITE_MLDSA65};

use crate::{overlay_addr, OverlayAddr};

pub const NONCE_SIZE: usize = 16;
pub const CHANNEL_HASH_SIZE: usize = 32;
// [I-16] admission A-3: channel_hash is taken from the QUIC/TLS-1.3 channel (X25519 ECDHE is the
// admission wrapper of RFC 8446); the content is post-quantum (Noise_PQ XX + E2E on top).
// spec: channel_hash for QUIC/TLS 1.3 = TLS-Exporter(label, "", 32); the label is SSOT in mt-codec::domain
pub use mt_codec::domain::OVERLAY_CHANNEL_LABEL as CHANNEL_EXPORT_LABEL;

pub type Nonce = [u8; NONCE_SIZE];
pub type ChannelHash = [u8; CHANNEL_HASH_SIZE];

// spec: msg = op_domain || 0x00 || resource_id || nonce || channel_hash
//
// S1 (canonical): resource_id WITHOUT a length prefix; unambiguity rests on two invariants:
//   (1) op_domain (ASCII without 0x00) is separated by the `0x00` separator → cross-domain collision is excluded;
//   (2) within one op_domain the length of resource_id is FIXED: mt-reg → overlay_addr (32 B),
//       mt-fetch → epoch_tag (16 B). The tail (nonce 16 ‖ channel_hash 32) is fixed.
// Violating (2), i.e. passing a resource of another length under the same domain, is forbidden to the caller.
pub fn challenge_message(
    op_domain: &[u8],
    resource_id: &[u8],
    nonce: &Nonce,
    channel_hash: &ChannelHash,
) -> Vec<u8> {
    let mut msg = Vec::with_capacity(
        op_domain.len() + 1 + resource_id.len() + NONCE_SIZE + CHANNEL_HASH_SIZE,
    );
    msg.extend_from_slice(op_domain);
    msg.push(0u8);
    msg.extend_from_slice(resource_id);
    msg.extend_from_slice(nonce);
    msg.extend_from_slice(channel_hash);
    msg
}

pub fn sign_registration(
    account_sk: &SecretKey,
    claimed_overlay: &OverlayAddr,
    nonce: &Nonce,
    channel_hash: &ChannelHash,
) -> Result<Signature, CryptoError> {
    let msg = challenge_message(
        mt_codec::domain::OVERLAY_REG,
        claimed_overlay,
        nonce,
        channel_hash,
    );
    sign(account_sk, &msg)
}

/// RegProof check by the postman: signature against the pubkey from RegHello +
/// binding account_pubkey<->overlay_addr (the address is derived, not declared separately).
/// Returns the confirmed overlay_addr of the connection.
pub fn verify_registration(
    account_pubkey: &[u8; PUBLIC_KEY_SIZE],
    nonce: &Nonce,
    channel_hash: &ChannelHash,
    sig: &Signature,
) -> Option<OverlayAddr> {
    let account_id = derive_account_id(SUITE_MLDSA65, account_pubkey);
    let addr = overlay_addr(&account_id);
    let msg = challenge_message(mt_codec::domain::OVERLAY_REG, &addr, nonce, channel_hash);
    let pk = PublicKey::from_array(*account_pubkey);
    if verify(&pk, &msg, sig) {
        Some(addr)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::keypair_from_seed;

    fn keypair() -> (PublicKey, SecretKey) {
        keypair_from_seed(&[0x42; 32]).expect("keygen")
    }

    #[test]
    fn registration_roundtrip_and_binding() {
        let (pk, sk) = keypair();
        let pk_bytes: [u8; PUBLIC_KEY_SIZE] = *pk.as_bytes();
        let account_id = derive_account_id(SUITE_MLDSA65, &pk_bytes);
        let addr = overlay_addr(&account_id);
        let nonce = [0x07; NONCE_SIZE];
        let ch = [0x0C; CHANNEL_HASH_SIZE];

        let sig = sign_registration(&sk, &addr, &nonce, &ch).unwrap();
        assert_eq!(
            verify_registration(&pk_bytes, &nonce, &ch, &sig),
            Some(addr)
        );
    }

    #[test]
    fn wrong_nonce_channel_or_signer_rejected() {
        let (pk, sk) = keypair();
        let pk_bytes: [u8; PUBLIC_KEY_SIZE] = *pk.as_bytes();
        let account_id = derive_account_id(SUITE_MLDSA65, &pk_bytes);
        let addr = overlay_addr(&account_id);
        let nonce = [0x07; NONCE_SIZE];
        let ch = [0x0C; CHANNEL_HASH_SIZE];
        let sig = sign_registration(&sk, &addr, &nonce, &ch).unwrap();

        // Foreign nonce: replay is closed.
        assert_eq!(
            verify_registration(&pk_bytes, &[0x08; NONCE_SIZE], &ch, &sig),
            None
        );
        // Foreign channel: transfer between connections is closed (R4).
        assert_eq!(
            verify_registration(&pk_bytes, &nonce, &[0x0D; CHANNEL_HASH_SIZE], &sig),
            None
        );
        // Foreign key: address hijacking is closed (P4).
        let (pk2, _) = keypair_from_seed(&[0x43; 32]).unwrap();
        let pk2_bytes: [u8; PUBLIC_KEY_SIZE] = *pk2.as_bytes();
        assert_eq!(verify_registration(&pk2_bytes, &nonce, &ch, &sig), None);
    }

    #[test]
    fn challenge_message_composition_is_domain_separated() {
        let nonce = [0x01; NONCE_SIZE];
        let ch = [0x02; CHANNEL_HASH_SIZE];
        let a = challenge_message(mt_codec::domain::OVERLAY_REG, &[0xAA; 32], &nonce, &ch);
        let b = challenge_message(mt_codec::domain::OVERLAY_FETCH, &[0xAA; 32], &nonce, &ch);
        assert_ne!(a, b);
        assert_eq!(a.len(), 6 + 1 + 32 + 16 + 32);
    }
}
