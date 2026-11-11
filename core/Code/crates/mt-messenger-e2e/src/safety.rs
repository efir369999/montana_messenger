//! Stage 8 — identity fingerprint verification (safety number).
//! party_code: account_id (32 B) → 30 decimal digits (iterated SHA-256, ITER=5200).
//! safety_number: symmetric 60-digit fingerprint of the pair. Byte-exact per spec "Fingerprint".

use sha2::{Digest, Sha256};

pub const SAFETY_ITER: u32 = 5200;

/// party_code(account_id) = 30 digits: h = SHA-256^ITER("mt-safety"‖0x00‖account_id),
/// 6 groups of big-endian uint40(h[5k..5k+5]) mod 100000, each 5 digits.
pub fn party_code(account_id: &[u8; 32]) -> String {
    let mut init = b"mt-safety".to_vec();
    init.push(0u8);
    init.extend_from_slice(account_id);
    let mut d: [u8; 32] = Sha256::digest(&init).into();
    for _ in 1..SAFETY_ITER {
        d = Sha256::digest(d).into();
    }
    let mut out = String::with_capacity(30);
    for k in 0..6 {
        let mut v: u64 = 0;
        for &b in &d[5 * k..5 * k + 5] {
            v = (v << 8) | b as u64;
        }
        v %= 100000;
        out.push_str(&format!("{v:05}"));
    }
    out
}

/// safety_number(id_A, id_B) = 60 digits: party_code(lo)‖party_code(hi),
/// (lo, hi) — ascending sort as 32-byte big-endian numbers. Symmetric.
pub fn safety_number(a: &[u8; 32], b: &[u8; 32]) -> String {
    let (lo, hi) = if a <= b { (a, b) } else { (b, a) };
    party_code(lo) + &party_code(hi)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safety_number_spec_kat() {
        let a: [u8; 32] =
            hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21")
                .unwrap()
                .try_into()
                .unwrap();
        let b = [0x11u8; 32];
        assert_eq!(party_code(&a), "157809020367483198118535796002");
        assert_eq!(party_code(&b), "534333257869110355393448740858");
        assert_eq!(
            safety_number(&a, &b),
            "534333257869110355393448740858157809020367483198118535796002"
        );
        // symmetry: argument order does not matter
        assert_eq!(safety_number(&a, &b), safety_number(&b, &a));
    }
}
