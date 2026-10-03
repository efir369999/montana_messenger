// spec, раздел "Криптографическая реализация → Primitive layer → HKDF-Expand integer спецификация"

use crate::hmac::hmac_sha256;
use zeroize::Zeroize;

const H_LEN: usize = 32;
const MAX_LENGTH: usize = 255 * H_LEN;

pub fn hkdf_expand(prk: &[u8], info: &[u8], length: usize) -> Vec<u8> {
    // Precondition violation: protocol bug в вызывающем коде, не runtime error.
    assert!(
        length <= MAX_LENGTH,
        "HKDF-Expand: length {length} > 255 * hLen = {MAX_LENGTH}"
    );

    let block_count = (length + H_LEN - 1) / H_LEN;
    let mut okm: Vec<u8> = Vec::with_capacity(block_count * H_LEN);
    let mut t_prev: Vec<u8> = Vec::new();

    for i in 1..=(block_count as u32) {
        let mut hmac_input: Vec<u8> = Vec::with_capacity(t_prev.len() + info.len() + 1);
        hmac_input.extend_from_slice(&t_prev);
        hmac_input.extend_from_slice(info);
        // u8(i): counter помещается в u8 потому что block_count ≤ 255 (enforced выше).
        hmac_input.push(i as u8);

        let mut t_i = hmac_sha256(prk, &hmac_input);
        okm.extend_from_slice(&t_i);

        // Rotate: zeroize old t_prev перед replace новой копией.
        t_prev.zeroize();
        t_prev = t_i.to_vec();
        t_i.zeroize();

        // hmac_input содержит prk-derived material — zeroize.
        hmac_input.zeroize();
    }

    // Final t_prev держит копию последнего blocк okm — zeroize перед return.
    t_prev.zeroize();

    okm.truncate(length);
    okm
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

    fn hex_to_bytes(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("valid hex in test vector"))
            .collect()
    }

    // RFC 5869 §A.1 — Basic test case with SHA-256
    // PRK  = 077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5 (32B)
    // info = f0f1f2f3f4f5f6f7f8f9 (10B)
    // L    = 42
    // OKM  = 3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf
    //        34007208d5b887185865 (42B)
    #[test]
    fn rfc5869_a1_sha256_basic() {
        let prk = hex_to_bytes("077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5");
        let info = hex_to_bytes("f0f1f2f3f4f5f6f7f8f9");
        let got = hkdf_expand(&prk, &info, 42);
        assert_eq!(
            hex(&got),
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
        );
    }

    // RFC 5869 §A.2 — Test with SHA-256 и longer inputs/outputs
    // PRK  = 06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244 (32B)
    // info = 80 bytes 0xb0..0xff
    // L    = 82
    #[test]
    fn rfc5869_a2_sha256_long_inputs() {
        let prk = hex_to_bytes("06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244");
        let info = hex_to_bytes(concat!(
            "b0b1b2b3b4b5b6b7b8b9babbbcbdbebf",
            "c0c1c2c3c4c5c6c7c8c9cacbcccdcecf",
            "d0d1d2d3d4d5d6d7d8d9dadbdcdddedf",
            "e0e1e2e3e4e5e6e7e8e9eaebecedeeef",
            "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
        ));
        let got = hkdf_expand(&prk, &info, 82);
        assert_eq!(
            hex(&got),
            concat!(
                "b11e398dc80327a1c8e7f78c596a4934",
                "4f012eda2d4efad8a050cc4c19afa97c",
                "59045a99cac7827271cb41c65e590e09",
                "da3275600c2f09b8367793a9aca3db71",
                "cc30c58179ec3e87c14c01d5c1f3434f",
                "1d87",
            )
        );
    }

    // RFC 5869 §A.3 — Test with SHA-256 и zero-length salt/info
    // PRK  = 19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04 (32B)
    // info = (empty)
    // L    = 42
    #[test]
    fn rfc5869_a3_sha256_empty_info() {
        let prk = hex_to_bytes("19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04");
        let got = hkdf_expand(&prk, &[], 42);
        assert_eq!(
            hex(&got),
            "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"
        );
    }

    #[test]
    fn length_1_minimal_output() {
        let prk = [0x0bu8; 32];
        let out = hkdf_expand(&prk, b"info", 1);
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn length_32_single_block() {
        let prk = [0x0bu8; 32];
        let out = hkdf_expand(&prk, b"info", 32);
        assert_eq!(out.len(), 32);
    }

    #[test]
    fn length_64_two_blocks_counter_increments() {
        let prk = [0x0bu8; 32];
        let out = hkdf_expand(&prk, b"info", 64);
        assert_eq!(out.len(), 64);
        // Первые 32 байта = T_1 = HMAC(prk, "" || info || 0x01)
        // Вторые 32 байта = T_2 = HMAC(prk, T_1 || info || 0x02)
        let t1 = {
            let mut m = Vec::from(b"info" as &[u8]);
            m.push(0x01);
            crate::hmac::hmac_sha256(&prk, &m).to_vec()
        };
        assert_eq!(&out[..32], &t1[..]);
    }

    #[test]
    fn length_32_mldsa_seed_case() {
        // Montana per-role derivation для ML-DSA-65 использует L=32
        // (FIPS 204 §3.1 ξ ∈ B32)
        let prk = [0x00u8; 64]; // master_seed
        let out = hkdf_expand(&prk, b"mt-account-key", 32);
        assert_eq!(out.len(), 32);
    }

    #[test]
    fn length_64_mlkem_seed_case() {
        // Montana per-role derivation для ML-KEM использует L=64
        let prk = [0x00u8; 64];
        let out = hkdf_expand(&prk, b"mt-app-encryption-key", 64);
        assert_eq!(out.len(), 64);
    }

    #[test]
    fn determinism_identical_input_identical_output() {
        let prk = [0xabu8; 48];
        let a = hkdf_expand(&prk, b"info", 50);
        let b = hkdf_expand(&prk, b"info", 50);
        assert_eq!(a, b);
    }

    #[test]
    #[should_panic(expected = "length")]
    fn length_above_max_panics() {
        let prk = [0x0bu8; 32];
        let _ = hkdf_expand(&prk, b"info", MAX_LENGTH + 1);
    }

    #[test]
    fn length_exactly_max_works() {
        let prk = [0x0bu8; 32];
        let out = hkdf_expand(&prk, b"info", MAX_LENGTH);
        assert_eq!(out.len(), MAX_LENGTH);
    }
}
