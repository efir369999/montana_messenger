//! Stage 5 — post-quantum session establishment (PQXDH over ML-KEM-768).
//! Key schedule: HKDF-SHA-256(salt=0×32, IKM=ss_id‖ss_spk[‖ss_opk],
//! info="mt-pqxdh-root"‖0x00‖transcript_hash, L=96) → root‖chain‖confirm_key.

use zeroize::Zeroize;

use crate::kdf::{hkdf_sha256, hmac_sha256};

pub const DOMAIN_ROOT: &[u8] = b"mt-pqxdh-root";
pub const DOMAIN_CONFIRM: &[u8] = b"mt-pqxdh-confirm";
pub const DOMAIN_SIG: &[u8] = b"mt-pqxdh-sig";

pub struct SessionKeys {
    pub root_key: [u8; 32],
    pub sending_chain_key: [u8; 32],
    pub confirm_key: [u8; 32],
}

impl Drop for SessionKeys {
    fn drop(&mut self) {
        self.root_key.zeroize();
        self.sending_chain_key.zeroize();
        self.confirm_key.zeroize();
    }
}

/// Derive the session root from ML-KEM shared secrets and the transcript (spec Step 3).
/// `ss_opk = None` — path without a one-time pre-key (IKM = ss_id‖ss_spk).
pub fn derive_session_keys(
    ss_id: &[u8; 32],
    ss_spk: &[u8; 32],
    ss_opk: Option<&[u8; 32]>,
    transcript_hash: &[u8; 32],
) -> SessionKeys {
    let mut info = DOMAIN_ROOT.to_vec();
    info.push(0u8);
    info.extend_from_slice(transcript_hash);

    let mut ikm = Vec::with_capacity(96);
    ikm.extend_from_slice(ss_id);
    ikm.extend_from_slice(ss_spk);
    if let Some(o) = ss_opk {
        ikm.extend_from_slice(o);
    }

    let okm = hkdf_sha256(&[0u8; 32], &ikm, &info, 96);
    ikm.zeroize();

    let mut root_key = [0u8; 32];
    let mut sending_chain_key = [0u8; 32];
    let mut confirm_key = [0u8; 32];
    root_key.copy_from_slice(&okm[..32]);
    sending_chain_key.copy_from_slice(&okm[32..64]);
    confirm_key.copy_from_slice(&okm[64..96]);

    SessionKeys {
        root_key,
        sending_chain_key,
        confirm_key,
    }
}

/// confirm_tag = HMAC-SHA-256(confirm_key, "mt-pqxdh-confirm"‖0x00‖transcript_hash).
pub fn confirm_tag(confirm_key: &[u8; 32], transcript_hash: &[u8; 32]) -> [u8; 32] {
    let mut ci = DOMAIN_CONFIRM.to_vec();
    ci.push(0u8);
    ci.extend_from_slice(transcript_hash);
    hmac_sha256(confirm_key, &ci)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_schedule_kat_with_opk() {
        let sk = derive_session_keys(&[0x11; 32], &[0x22; 32], Some(&[0x33; 32]), &[0xAA; 32]);
        assert_eq!(
            hex::encode(sk.root_key),
            "d1d0a8699658a49099eddf5eafa58cf9da1d8ff02ce00f7218245b3bee0efcd1"
        );
        assert_eq!(
            hex::encode(sk.sending_chain_key),
            "082046319cc79abbfa129a7699607dd55fe989ca9f1822ab5af53692788a27b2"
        );
        assert_eq!(
            hex::encode(sk.confirm_key),
            "872152f9fcef01639bda5890534901b1ed2c206334b64eeb46c62532ffeed5b9"
        );
        assert_eq!(
            hex::encode(confirm_tag(&sk.confirm_key, &[0xAA; 32])),
            "6f5d00d0a49c7a231819863706eb93bc859071ee2b7919e9e0db5c58af538dbf"
        );
    }

    #[test]
    fn key_schedule_kat_without_opk() {
        let sk = derive_session_keys(&[0x11; 32], &[0x22; 32], None, &[0xAA; 32]);
        assert_eq!(
            hex::encode(sk.root_key),
            "38fa29cc640c4a87e554ece7cb1168bf3d18bd0e4b6ee5683336091c433ca4ca"
        );
        assert_eq!(
            hex::encode(sk.sending_chain_key),
            "6697d2bb86b5306ff82a86e9213655328bde8b3056226f5d3b1c89b769a76098"
        );
        assert_eq!(
            hex::encode(sk.confirm_key),
            "19defc490566c6523a96b36610ade231fb73ca9418eeaba9d6fa724bf7ff375b"
        );
        assert_eq!(
            hex::encode(confirm_tag(&sk.confirm_key, &[0xAA; 32])),
            "441e93d5283d8af4d053a16a4a3601342fbae0550c501e700d9062ce5d98bf56"
        );
    }
}
