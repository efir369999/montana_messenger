// spec, раздел "Криптографическая реализация → Primitive layer → HMAC-SHA-256 integer спецификация"

use crate::{sha256_raw, Hash32};
use zeroize::Zeroize;

const BLOCK_SIZE: usize = 64;
const IPAD_BYTE: u8 = 0x36;
const OPAD_BYTE: u8 = 0x5C;

pub fn hmac_sha256(key: &[u8], message: &[u8]) -> Hash32 {
    let mut key_block = [0u8; BLOCK_SIZE];
    if key.len() > BLOCK_SIZE {
        let mut reduced = sha256_raw(key);
        key_block[..32].copy_from_slice(&reduced);
        reduced.zeroize();
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }

    let mut key_ipad = [0u8; BLOCK_SIZE];
    let mut key_opad = [0u8; BLOCK_SIZE];
    for i in 0..BLOCK_SIZE {
        key_ipad[i] = key_block[i] ^ IPAD_BYTE;
        key_opad[i] = key_block[i] ^ OPAD_BYTE;
    }

    let inner = sha256_concat(&key_ipad, message);
    let result = sha256_concat(&key_opad, &inner);

    // Zeroize key-derived padded blocks (содержат key XOR pad byte —
    // partial key recovery возможна при leak).
    key_block.zeroize();
    key_ipad.zeroize();
    key_opad.zeroize();

    result
}

// HMAC требует raw SHA-256 без domain separation (RFC 2104, RFC 4231).
// Используется sha256_raw из mt-crypto, НЕ domain-separated hash().
fn sha256_concat(a: &[u8], b: &[u8]) -> Hash32 {
    let mut combined = Vec::with_capacity(a.len() + b.len());
    combined.extend_from_slice(a);
    combined.extend_from_slice(b);
    let result = sha256_raw(&combined);
    combined.zeroize();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        let mut s = String::with_capacity(bytes.len() * 2);
        for b in bytes {
            s.push_str(&format!("{b:02x}"));
        }
        s
    }

    // RFC 4231 §4.2 Test Case 1
    // Key  = 0x0b repeated 20 times
    // Data = "Hi There"
    // HMAC-SHA-256 = b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7
    #[test]
    fn rfc4231_case_1() {
        let key = [0x0bu8; 20];
        let msg = b"Hi There";
        let got = hmac_sha256(&key, msg);
        assert_eq!(
            hex(&got),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        );
    }

    // RFC 4231 §4.3 Test Case 2
    // Key  = "Jefe" (ASCII, 4 bytes)
    // Data = "what do ya want for nothing?"
    // HMAC-SHA-256 = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
    #[test]
    fn rfc4231_case_2() {
        let key = b"Jefe";
        let msg = b"what do ya want for nothing?";
        let got = hmac_sha256(key, msg);
        assert_eq!(
            hex(&got),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
    }

    // RFC 4231 §4.5 Test Case 4
    // Key  = 0x0102030405060708090a0b0c0d0e0f10111213141516171819 (25 bytes)
    // Data = 0xcd repeated 50 times
    // HMAC-SHA-256 = 82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b
    #[test]
    fn rfc4231_case_4() {
        let key: [u8; 25] = [
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
            0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19,
        ];
        let msg = [0xcdu8; 50];
        let got = hmac_sha256(&key, &msg);
        assert_eq!(
            hex(&got),
            "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"
        );
    }

    // RFC 4231 §4.7 Test Case 6
    // Key  = 0xaa repeated 131 times (longer than block size B=64 → key = SHA-256(key))
    // Data = "Test Using Larger Than Block-Size Key - Hash Key First"
    // HMAC-SHA-256 = 60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54
    #[test]
    fn rfc4231_case_6_long_key_triggers_sha256_reduction() {
        let key = [0xaau8; 131];
        let msg = b"Test Using Larger Than Block-Size Key - Hash Key First";
        let got = hmac_sha256(&key, msg);
        assert_eq!(
            hex(&got),
            "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
        );
    }

    #[test]
    fn empty_message_does_not_panic() {
        let key = [0x0bu8; 20];
        let out = hmac_sha256(&key, &[]);
        assert_eq!(out.len(), 32);
    }

    #[test]
    fn empty_key_does_not_panic() {
        let msg = b"anything";
        let out = hmac_sha256(&[], msg);
        assert_eq!(out.len(), 32);
    }

    #[test]
    fn key_exactly_block_size_no_reduction_no_padding() {
        let key = [0x5au8; BLOCK_SIZE];
        let msg = b"exactly block size";
        let out = hmac_sha256(&key, msg);
        assert_eq!(out.len(), 32);
    }

    #[test]
    fn determinism_identical_input_identical_output() {
        let key = b"deterministic-key";
        let msg = b"deterministic-message";
        let a = hmac_sha256(key, msg);
        let b = hmac_sha256(key, msg);
        assert_eq!(a, b);
    }
}
