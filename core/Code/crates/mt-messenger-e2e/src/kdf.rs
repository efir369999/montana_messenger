//! Cryptographic KDF primitives (spec Stage 5-7). Pure HMAC/HKDF-SHA-256 →
//! cross-platform byte-identical. RFC 5869 (HKDF), RFC 2104 (HMAC).

use sha2::{Digest, Sha256};

pub fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut k = [0u8; 64];
    if key.len() > 64 {
        k[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let mut ipad = [0x36u8; 64];
    let mut opad = [0x5cu8; 64];
    for i in 0..64 {
        ipad[i] ^= k[i];
        opad[i] ^= k[i];
    }
    let mut hi = Sha256::new();
    hi.update(ipad);
    hi.update(msg);
    let inner = hi.finalize();
    let mut ho = Sha256::new();
    ho.update(opad);
    ho.update(inner);
    ho.finalize().into()
}

pub fn hkdf_sha256(salt: &[u8], ikm: &[u8], info: &[u8], l: usize) -> Vec<u8> {
    let prk = hmac_sha256(salt, ikm);
    let mut okm = Vec::new();
    let mut t: Vec<u8> = Vec::new();
    let mut i = 1u8;
    while okm.len() < l {
        let mut m = t.clone();
        m.extend_from_slice(info);
        m.push(i);
        t = hmac_sha256(&prk, &m).to_vec();
        okm.extend_from_slice(&t);
        i += 1;
    }
    okm.truncate(l);
    okm
}
