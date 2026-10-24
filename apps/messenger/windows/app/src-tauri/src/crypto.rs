//! The core's cryptography in safe words: every byte here is the core's (mt_bindings.dll) -- the randomness, the seal of a
//! blob (ChaCha20-Poly1305, mt_e2e_seal_blob), the ML-KEM-768 contact keys, the first secret of a meeting. Nothing here is a
//! cipher of its own; this file only hands buffers to the core and takes them back.

use crate::abi::*;

/// Bytes of the core's randomness (mt_random_fast, at most 1024 a call).
pub fn random(n: usize) -> Option<Vec<u8>> {
    let mut out = vec![0u8; n];
    // SAFETY: a live buffer of n bytes
    (unsafe { mt_random_fast(out.as_mut_ptr(), n) } == MT_OK).then_some(out)
}

unsafe fn taken(ptr: *mut u8, len: usize) -> Vec<u8> {
    let v = std::slice::from_raw_parts(ptr, len).to_vec();
    mt_e2e_free(ptr, len);
    v
}

/// A blob sealed under a 32-byte key with a fresh 12-byte nonce (iOS seal, Wire.seal).
pub fn seal(key: &[u8], plain: &[u8]) -> Option<Vec<u8>> {
    if key.len() != 32 {
        return None;
    }
    let nonce = random(12)?;
    let (mut p, mut n) = (std::ptr::null_mut(), 0usize);
    // SAFETY: a 32-byte key, a 12-byte nonce, the input of its length; the core allocates the output, freed by taken
    let rc = unsafe { mt_e2e_seal_blob(key.as_ptr(), nonce.as_ptr(), plain.as_ptr(), plain.len(), &mut p, &mut n) };
    (rc == MT_OK && !p.is_null()).then(|| unsafe { taken(p, n) })
}

/// A blob sealed under a 32-byte key with the nonce given (a media chunk's nonce is derived, iOS MontanaMediaKit.sealOne).
pub fn seal_with(key: &[u8], nonce: &[u8], plain: &[u8]) -> Option<Vec<u8>> {
    if key.len() != 32 || nonce.len() != 12 {
        return None;
    }
    let (mut p, mut n) = (std::ptr::null_mut(), 0usize);
    // SAFETY: a 32-byte key, a 12-byte nonce, the input of its length; the core allocates the output, freed by taken
    let rc = unsafe { mt_e2e_seal_blob(key.as_ptr(), nonce.as_ptr(), plain.as_ptr(), plain.len(), &mut p, &mut n) };
    (rc == MT_OK && !p.is_null()).then(|| unsafe { taken(p, n) })
}

/// The core's name of a blob (mt_e2e_blob_id): the 32 bytes the chunk is filed under.
pub fn blob_id(data: &[u8]) -> Option<[u8; 32]> {
    let mut out = [0u8; 32];
    // SAFETY: the input of its length and a 32-byte buffer
    (unsafe { mt_e2e_blob_id(data.as_ptr(), data.len(), out.as_mut_ptr()) } == MT_OK).then_some(out)
}

/// The length a media piece is padded to before it is sealed (mt_e2e_pad_len), so a size says little.
pub fn pad_len(n: usize) -> usize {
    // SAFETY: a pure function of a number
    unsafe { mt_e2e_pad_len(n) }
}

/// A sealed blob opened, or None when the key is not its key.
pub fn open(key: &[u8], sealed: &[u8]) -> Option<Vec<u8>> {
    if key.len() != 32 {
        return None;
    }
    let (mut p, mut n) = (std::ptr::null_mut(), 0usize);
    // SAFETY: as in seal
    let rc = unsafe { mt_e2e_open_blob(key.as_ptr(), sealed.as_ptr(), sealed.len(), &mut p, &mut n) };
    if rc != MT_OK || p.is_null() {
        return None;
    }
    Some(unsafe { taken(p, n) })
}

/// An ML-KEM-768 key pair from a 64-byte seed: (public 1184, secret 2400).
pub fn mlkem_keypair(seed: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    if seed.len() != MT_MLKEM_SEED_LEN {
        return None;
    }
    let (mut pk, mut sk) = (vec![0u8; MT_MLKEM_PUBKEY_SIZE], vec![0u8; MT_MLKEM_SECKEY_SIZE]);
    // SAFETY: buffers of the sizes the door writes
    (unsafe { mt_mlkem_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) } == MT_OK).then_some((pk, sk))
}

/// One encapsulation to a contact key: (ciphertext 1088, shared secret 32).
pub fn mlkem_encaps(pk: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    if pk.len() != MT_MLKEM_PUBKEY_SIZE {
        return None;
    }
    let (mut ct, mut ss) = (vec![0u8; MT_MLKEM_CT_SIZE], vec![0u8; MT_MLKEM_SS_SIZE]);
    // SAFETY: as above
    (unsafe { mt_mlkem_encaps(pk.as_ptr(), ct.as_mut_ptr(), ss.as_mut_ptr()) } == MT_OK).then_some((ct, ss))
}

/// The shared secret of a ciphertext under a secret key (it never refuses: FIPS 203's implicit rejection).
pub fn mlkem_decaps(sk: &[u8], ct: &[u8]) -> Option<Vec<u8>> {
    if sk.len() != MT_MLKEM_SECKEY_SIZE || ct.len() != MT_MLKEM_CT_SIZE {
        return None;
    }
    let mut ss = vec![0u8; MT_MLKEM_SS_SIZE];
    // SAFETY: as above
    (unsafe { mt_mlkem_decaps(sk.as_ptr(), ct.as_ptr(), ss.as_mut_ptr()) } == MT_OK).then_some(ss)
}

/// The first letter's secret of a meeting: ss, the contact root, the ciphertext (mt_name_first_secret; iOS nativeFirstSecret).
pub fn first_secret(ss: &[u8], root: &[u8], ct: &[u8]) -> Option<Vec<u8>> {
    let mut out = vec![0u8; 32];
    // SAFETY: the three inputs with their lengths, a 32-byte output
    let rc = unsafe { mt_name_first_secret(ss.as_ptr(), ss.len(), root.as_ptr(), root.len(), ct.as_ptr(), ct.len(), out.as_mut_ptr()) };
    (rc == MT_OK).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blob_opens_under_its_key_only() {
        let key = random(32).unwrap();
        let sealed = seal(&key, b"Privet, Montana").unwrap();
        assert_eq!(open(&key, &sealed).as_deref(), Some(&b"Privet, Montana"[..]));
        assert!(open(&random(32).unwrap(), &sealed).is_none());
    }

    #[test]
    fn a_meeting_gives_both_sides_one_secret() {
        let (pk, sk) = mlkem_keypair(&random(64).unwrap()).unwrap();
        let (ct, ss_a) = mlkem_encaps(&pk).unwrap();
        let ss_b = mlkem_decaps(&sk, &ct).unwrap();
        assert_eq!(ss_a, ss_b);
        assert_eq!(first_secret(&ss_a, &pk, &ct), first_secret(&ss_b, &pk, &ct));
    }
}
