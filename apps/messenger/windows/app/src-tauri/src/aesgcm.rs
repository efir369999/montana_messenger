//! AES-256-GCM (iOS CryptoKit AES.GCM in its combined form: nonce 12 ‖ ciphertext ‖ tag 16), by Windows' own cryptography
//! (CNG, BCrypt) -- the cipher a group room's pair words are sealed with (iOS MTRoomSeal), with no crate of its own.

/// Sealed under the key with a fresh nonce: nonce ‖ ciphertext ‖ tag.
pub fn seal(key: &[u8], plain: &[u8]) -> Option<Vec<u8>> {
    let nonce = crate::crypto::random(12)?;
    seal_with(key, &nonce, plain)
}

/// Opened from the combined form; none when the key, the nonce or a single bit of it is not what sealed it.
pub fn open(key: &[u8], combined: &[u8]) -> Option<Vec<u8>> {
    if combined.len() < 28 {
        return None;
    }
    let (nonce, rest) = combined.split_at(12);
    let (ct, tag) = rest.split_at(rest.len() - 16);
    run(key, nonce, ct, Some(tag)).map(|(p, _)| p)
}

pub(crate) fn seal_with(key: &[u8], nonce: &[u8], plain: &[u8]) -> Option<Vec<u8>> {
    let (ct, tag) = run(key, nonce, plain, None)?;
    Some([nonce, &ct, &tag].concat())
}

/// One pass of the cipher: encryption when no tag is given (the tag comes back), decryption against the tag given.
#[cfg(windows)]
fn run(key: &[u8], nonce: &[u8], input: &[u8], tag: Option<&[u8]>) -> Option<(Vec<u8>, Vec<u8>)> {
    use windows_sys::Win32::Security::Cryptography::*;
    if key.len() != 32 || nonce.len() != 12 {
        return None;
    }
    let wide = |s: &str| s.encode_utf16().chain(std::iter::once(0)).collect::<Vec<u16>>();
    let (aes, chaining, gcm) = (wide("AES"), wide("ChainingMode"), wide("ChainingModeGCM"));
    // SAFETY: CNG's own handles, opened and closed here; every buffer outlives the call that reads or writes it
    unsafe {
        let mut alg: BCRYPT_ALG_HANDLE = std::ptr::null_mut();
        if BCryptOpenAlgorithmProvider(&mut alg, aes.as_ptr(), std::ptr::null(), 0) != 0 {
            return None;
        }
        let out = (|| {
            if BCryptSetProperty(alg, chaining.as_ptr(), gcm.as_ptr() as *const u8, (gcm.len() * 2) as u32, 0) != 0 {
                return None;
            }
            let mut k: BCRYPT_KEY_HANDLE = std::ptr::null_mut();
            if BCryptGenerateSymmetricKey(alg, &mut k, std::ptr::null_mut(), 0, key.as_ptr(), key.len() as u32, 0) != 0 {
                return None;
            }
            let mut t = tag.map(|t| t.to_vec()).unwrap_or_else(|| vec![0u8; 16]);
            let mut nonce = nonce.to_vec();
            let mut info: BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO = std::mem::zeroed();
            info.cbSize = std::mem::size_of::<BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO>() as u32;
            info.dwInfoVersion = BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO_VERSION;
            info.pbNonce = nonce.as_mut_ptr();
            info.cbNonce = nonce.len() as u32;
            info.pbTag = t.as_mut_ptr();
            info.cbTag = t.len() as u32;
            let mut out = vec![0u8; input.len()];
            let mut done = 0u32;
            let input_ptr = if input.is_empty() { std::ptr::null() } else { input.as_ptr() };
            let out_ptr = if out.is_empty() { std::ptr::null_mut() } else { out.as_mut_ptr() };
            let info_ptr = &info as *const _ as *const core::ffi::c_void;
            let rc = if tag.is_some() {
                BCryptDecrypt(k, input_ptr, input.len() as u32, info_ptr, std::ptr::null_mut(), 0, out_ptr, out.len() as u32, &mut done, 0)
            } else {
                BCryptEncrypt(k, input_ptr, input.len() as u32, info_ptr, std::ptr::null_mut(), 0, out_ptr, out.len() as u32, &mut done, 0)
            };
            BCryptDestroyKey(k);
            (rc == 0 && done as usize == input.len()).then_some((out, t))
        })();
        BCryptCloseAlgorithmProvider(alg, 0);
        out
    }
}

#[cfg(not(windows))]
fn run(_key: &[u8], _nonce: &[u8], _input: &[u8], _tag: Option<&[u8]>) -> Option<(Vec<u8>, Vec<u8>)> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::hex;

    #[test]
    fn the_gcm_vectors_hold_and_a_bit_changed_opens_nothing() {
        // the GCM specification's test cases 13 and 14: a 256-bit key of zeros, a 96-bit nonce of zeros
        let (key, nonce) = ([0u8; 32], [0u8; 12]);
        let empty = seal_with(&key, &nonce, &[]).unwrap();
        assert_eq!(hex(&empty[12..]), "530f8afbc74536b9a963b4f1c4cb738b");
        let block = seal_with(&key, &nonce, &[0u8; 16]).unwrap();
        assert_eq!(hex(&block[12..28]), "cea7403d4d606b6e074ec5d3baf39d18");
        assert_eq!(hex(&block[28..]), "d0d1c8a799996bf0265b98b5d48ab919");
        // a fresh nonce each time, and back
        let k: Vec<u8> = (0..32).collect();
        let a = seal(&k, b"offer").unwrap();
        assert_ne!(a, seal(&k, b"offer").unwrap());
        assert_eq!(open(&k, &a).as_deref(), Some(&b"offer"[..]));
        let mut b = a.clone();
        *b.last_mut().unwrap() ^= 1;
        assert!(open(&k, &b).is_none(), "a tag changed by one bit opens nothing");
        assert!(open(&[7u8; 32], &a).is_none(), "another key opens nothing");
    }
}
