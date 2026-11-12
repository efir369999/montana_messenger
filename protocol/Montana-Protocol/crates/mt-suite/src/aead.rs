// ChaCha20-Poly1305. The set states it in `docs/Montana Canon.md`, "Primitives", and its sizes
// beside the others: a nonce of twelve bytes and a tag of sixteen, appended to the ciphertext.
//
// A nonce is never repeated under one key. That is not advice: two messages sealed under one
// (key, nonce) reveal the difference of their plaintexts to anyone holding both, so a caller
// states the nonce and the protocol above it is what keeps them apart.

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use mt_codec::size;
use zeroize::Zeroize;

mt_codec::constants! {
    SEALING_WIDTHS:
    /// The key of a seal is a hash output of this protocol, so its width is the width of one.
    pub const KEY_BYTES: usize = 32, row "hash_bytes";
}

#[derive(Debug, PartialEq, Eq)]
pub struct SealError;

#[derive(Debug, PartialEq, Eq)]
pub struct OpenError;

// The key wipes itself and never prints.
pub struct SealingKey([u8; KEY_BYTES]);

impl SealingKey {
    pub fn new(bytes: [u8; KEY_BYTES]) -> Self {
        Self(bytes)
    }
}

impl core::fmt::Debug for SealingKey {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("SealingKey(<wiped on drop, never shown>)")
    }
}

impl Drop for SealingKey {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

// The sealed bytes are the ciphertext with the tag after it, which is the layout the sizes of
// the set describe: a body of the plaintext's length and sixteen bytes beyond it.
pub fn seal(
    key: &SealingKey,
    nonce: &[u8; size::AEAD_NONCE],
    associated: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, SealError> {
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key.0));
    cipher
        .encrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: plaintext,
                aad: associated,
            },
        )
        .map_err(|_| SealError)
}

pub fn open(
    key: &SealingKey,
    nonce: &[u8; size::AEAD_NONCE],
    associated: &[u8],
    sealed: &[u8],
) -> Result<Vec<u8>, OpenError> {
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key.0));
    cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: sealed,
                aad: associated,
            },
        )
        .map_err(|_| OpenError)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vectors;

    #[test]
    fn the_published_vector_of_the_standard_reproduces() {
        // RFC 8439 §2.8.2: the one worked example of the standard, key, nonce, associated data,
        // plaintext, ciphertext and tag.
        let case = vectors::rfc8439_aead();
        let key = SealingKey(case.key);
        let sealed = seal(&key, &case.nonce, &case.associated, &case.plaintext).expect("seals");
        let (ciphertext, tag) = sealed.split_at(sealed.len() - size::AEAD_TAG);
        assert_eq!(ciphertext, &case.ciphertext[..]);
        assert_eq!(tag, &case.tag[..]);
        let opened = open(&key, &case.nonce, &case.associated, &sealed).expect("opens");
        assert_eq!(opened, case.plaintext);
    }

    #[test]
    fn a_doctored_body_a_doctored_tag_and_a_moved_association_each_fail_to_open() {
        let key = SealingKey([0x11u8; KEY_BYTES]);
        let nonce = [0x22u8; size::AEAD_NONCE];
        let sealed = seal(&key, &nonce, b"the header", b"the body").expect("seals");
        assert_eq!(sealed.len(), b"the body".len() + size::AEAD_TAG);
        open(&key, &nonce, b"the header", &sealed).expect("opens");
        for doctored_at in [0usize, sealed.len() - 1] {
            let mut doctored = sealed.clone();
            doctored[doctored_at] ^= 1;
            assert_eq!(open(&key, &nonce, b"the header", &doctored), Err(OpenError));
        }
        assert_eq!(
            open(&key, &nonce, b"another header", &sealed),
            Err(OpenError)
        );
        assert_eq!(
            open(&key, &[0x23u8; size::AEAD_NONCE], b"the header", &sealed),
            Err(OpenError)
        );
        assert_eq!(
            open(
                &SealingKey([0x12u8; KEY_BYTES]),
                &nonce,
                b"the header",
                &sealed
            ),
            Err(OpenError)
        );
    }

    #[test]
    fn a_sealing_key_shows_nothing_of_itself() {
        let key = SealingKey([0x77u8; KEY_BYTES]);
        let shown = format!("{key:?}");
        assert!(!shown.contains("77"), "{shown}");
        assert!(shown.contains("never shown"), "{shown}");
    }
}
