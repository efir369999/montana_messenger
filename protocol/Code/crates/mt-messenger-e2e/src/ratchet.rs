//! Stage 6 — double ratchet (KEM ratchet over ML-KEM-768).
//! Symmetric chain steps (HMAC), root KEM step (HKDF), AEAD messages
//! (ChaCha20-Poly1305, RFC 8439). Byte-exact per spec "Derivation functions".

use crate::kdf::{hkdf_sha256, hmac_sha256};

pub const MLKEM_PUBKEY_SIZE: usize = 1184;

/// Symmetric chain step: (MK, CK').
pub fn kdf_ck(ck: &[u8; 32]) -> ([u8; 32], [u8; 32]) {
    (hmac_sha256(ck, &[0x01]), hmac_sha256(ck, &[0x02]))
}

/// Root/KEM step: (RK', CK) = HKDF(salt=RK, IKM=ss, info="mt-ratchet-rk", 64).
pub fn kdf_rk(rk: &[u8; 32], ss: &[u8; 32]) -> ([u8; 32], [u8; 32]) {
    let okm = hkdf_sha256(rk, ss, b"mt-ratchet-rk", 64);
    let mut a = [0u8; 32];
    let mut b = [0u8; 32];
    a.copy_from_slice(&okm[..32]);
    b.copy_from_slice(&okm[32..]);
    (a, b)
}

/// AEAD key+nonce: HKDF(salt=0×32, IKM=MK, info="mt-ratchet-msg", 44).
pub fn msg_key(mk: &[u8; 32]) -> ([u8; 32], [u8; 12]) {
    let okm = hkdf_sha256(&[0u8; 32], mk, b"mt-ratchet-msg", 44);
    let mut k = [0u8; 32];
    let mut n = [0u8; 12];
    k.copy_from_slice(&okm[..32]);
    n.copy_from_slice(&okm[32..44]);
    (k, n)
}

/// AD = session_id(32)‖PN(4 LE)‖Ns(4 LE)‖ratchet_pub(1184).
pub fn ad_bytes(
    session_id: &[u8; 32],
    pn: u32,
    ns: u32,
    ratchet_pub: &[u8; MLKEM_PUBKEY_SIZE],
) -> Vec<u8> {
    let mut ad = Vec::with_capacity(32 + 8 + MLKEM_PUBKEY_SIZE);
    ad.extend_from_slice(session_id);
    ad.extend_from_slice(&pn.to_le_bytes());
    ad.extend_from_slice(&ns.to_le_bytes());
    ad.extend_from_slice(ratchet_pub);
    ad
}

pub fn seal(k: &[u8; 32], n: &[u8; 12], pt: &[u8], ad: &[u8]) -> Vec<u8> {
    use chacha20poly1305::aead::{Aead, Payload};
    use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
    ChaCha20Poly1305::new_from_slice(k)
        .expect("32-byte key")
        .encrypt(Nonce::from_slice(n), Payload { msg: pt, aad: ad })
        .expect("chacha20poly1305 seal")
}

pub fn open(k: &[u8; 32], n: &[u8; 12], ct: &[u8], ad: &[u8]) -> Option<Vec<u8>> {
    use chacha20poly1305::aead::{Aead, Payload};
    use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
    ChaCha20Poly1305::new_from_slice(k)
        .ok()?
        .decrypt(Nonce::from_slice(n), Payload { msg: ct, aad: ad })
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aead_kat() {
        let mk = kdf_ck(&[0x42u8; 32]).0;
        let (enc_key, nonce) = msg_key(&mk);
        assert_eq!(
            hex::encode(enc_key),
            "7bb31482d13db3ad12d8529dc53aa5ba4f47b490b29f13fa275d6f56de4e8ed4"
        );
        assert_eq!(hex::encode(nonce), "00f4b713e2453c6ace58189c");
        let ad = ad_bytes(&[0xAA; 32], 0, 0, &[0x07; MLKEM_PUBKEY_SIZE]);
        let body = seal(&enc_key, &nonce, b"montana", &ad);
        assert_eq!(
            hex::encode(&body),
            "5f43ddbc831a09fab69467ec81e97c2b10e2ba06b1f287"
        );
        assert_eq!(open(&enc_key, &nonce, &body, &ad).unwrap(), b"montana");
    }

    #[test]
    fn open_rejects_tamper() {
        let (k, n) = msg_key(&[0x01; 32]);
        let ad = ad_bytes(&[0; 32], 0, 0, &[0; MLKEM_PUBKEY_SIZE]);
        let mut body = seal(&k, &n, b"hello", &ad);
        body[0] ^= 1;
        assert!(open(&k, &n, &body, &ad).is_none());
    }
}
