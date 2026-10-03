// spec, раздел "Криптографическая реализация → Primitive layer → PBKDF2-HMAC-SHA-256 integer спецификация"

use crate::hmac::hmac_sha256;
use zeroize::Zeroize;

const H_LEN: usize = 32;

pub fn pbkdf2_hmac_sha256(password: &[u8], salt: &[u8], iter: u32, dk_len: usize) -> Vec<u8> {
    let block_count = (dk_len + H_LEN - 1) / H_LEN;
    let mut dk: Vec<u8> = Vec::with_capacity(block_count * H_LEN);

    for i in 1..=(block_count as u32) {
        let mut salt_with_counter: Vec<u8> = Vec::with_capacity(salt.len() + 4);
        salt_with_counter.extend_from_slice(salt);
        salt_with_counter.extend_from_slice(&i.to_be_bytes());

        let u_1 = hmac_sha256(password, &salt_with_counter);
        let mut t_i = u_1;
        let mut u_prev = u_1;

        for _ in 2..=iter {
            let u_k = hmac_sha256(password, &u_prev);
            for j in 0..H_LEN {
                t_i[j] ^= u_k[j];
            }
            u_prev.zeroize();
            u_prev = u_k;
        }

        dk.extend_from_slice(&t_i);

        // Zeroize промежуточные buffers — содержат password-derived material
        // (defense-in-depth против memory inspection / kernel core dump).
        salt_with_counter.zeroize();
        u_prev.zeroize();
        t_i.zeroize();
    }

    dk.truncate(dk_len);
    dk
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

    // RFC 7914 §11 test vector 1 для PBKDF2-HMAC-SHA-256
    // P = "passwd", S = "salt", c = 1, dkLen = 64
    #[test]
    fn rfc7914_vector_1_passwd_salt_c1() {
        let got = pbkdf2_hmac_sha256(b"passwd", b"salt", 1, 64);
        assert_eq!(
            hex(&got),
            concat!(
                "55ac046e56e3089fec1691c22544b605",
                "f94185216dde0465e68b9d57c20dacbc",
                "49ca9cccf179b645991664b39d77ef31",
                "7c71b845b1e30bd509112041d3a19783",
            )
        );
    }

    // RFC 7914 §11 test vector 2 для PBKDF2-HMAC-SHA-256
    // P = "Password", S = "NaCl", c = 80000, dkLen = 64
    // Release-режим: ~50ms. Debug: ~500ms. Тест slow-ish но в допуске.
    #[test]
    fn rfc7914_vector_2_password_nacl_c80000() {
        let got = pbkdf2_hmac_sha256(b"Password", b"NaCl", 80_000, 64);
        assert_eq!(
            hex(&got),
            concat!(
                "4ddcd8f60b98be21830cee5ef22701f9",
                "641a4418d04c0414aeff08876b34ab56",
                "a1d425a1225833549adb841b51c9b317",
                "6a272bdebba1d078478f62b397f33c8d",
            )
        );
    }

    // Широко опубликованный vector: P="password", S="salt", c=4096, dkLen=32
    // Источник: CryptoJS test vectors, проверенный через OpenSSL 1.1.1
    #[test]
    fn common_vector_password_salt_c4096_dk32() {
        let got = pbkdf2_hmac_sha256(b"password", b"salt", 4096, 32);
        assert_eq!(
            hex(&got),
            "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"
        );
    }

    #[test]
    fn iter_1_no_inner_loop() {
        // iter=1 означает loop 2..=1 пустой → T_1 = U_1 без XOR
        let got = pbkdf2_hmac_sha256(b"k", b"s", 1, 32);
        // Ожидаем что результат = HMAC-SHA-256(password, salt || u32_be(1))
        let expected = {
            let mut buf = Vec::from(b"s" as &[u8]);
            buf.extend_from_slice(&1u32.to_be_bytes());
            crate::hmac::hmac_sha256(b"k", &buf).to_vec()
        };
        assert_eq!(got, expected);
    }

    #[test]
    fn dk_len_32_single_block() {
        let got = pbkdf2_hmac_sha256(b"password", b"salt", 2, 32);
        assert_eq!(got.len(), 32);
    }

    #[test]
    fn dk_len_64_two_blocks() {
        let got = pbkdf2_hmac_sha256(b"password", b"salt", 2, 64);
        assert_eq!(got.len(), 64);
    }

    #[test]
    fn dk_len_48_three_quarters_of_two_blocks() {
        // l = ceiling(48/32) = 2; две HMAC evaluations, затем truncate до 48
        let got = pbkdf2_hmac_sha256(b"password", b"salt", 2, 48);
        assert_eq!(got.len(), 48);
    }

    #[test]
    fn dk_len_96_three_blocks_counter_increments() {
        // l = ceiling(96/32) = 3 → counter проходит u32_be(1), u32_be(2), u32_be(3)
        let got = pbkdf2_hmac_sha256(b"password", b"salt", 2, 96);
        assert_eq!(got.len(), 96);
    }

    #[test]
    fn determinism_identical_input_identical_output() {
        let a = pbkdf2_hmac_sha256(b"pw", b"s", 100, 32);
        let b = pbkdf2_hmac_sha256(b"pw", b"s", 100, 32);
        assert_eq!(a, b);
    }
}
