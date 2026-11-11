// The unsigned arithmetic of the ring and of both retargets. A threshold is thirty-two bytes read as
// an unsigned big-endian integer, so the recomputation multiplies a 256-bit number by a 64-bit one
// and divides the product by another — and the product does not fit in 256 bits. What stands here
// is that one operation, done in five limbs, with the division truncating toward zero as the set
// states.
//
// Nothing here is general-purpose arithmetic: it is the one shape the rules need, so there is no
// surface for a second implementation to differ on.

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug, Default)]
pub struct U256([u64; 4]);

impl U256 {
    pub const ZERO: U256 = U256([0; 4]);
    pub const ONE: U256 = U256([0, 0, 0, 1]);

    // Big-endian, most significant limb first: the order a threshold is compared in.
    pub fn from_be_bytes(bytes: &[u8; 32]) -> Self {
        let mut limbs = [0u64; 4];
        for (i, limb) in limbs.iter_mut().enumerate() {
            let mut eight = [0u8; 8];
            eight.copy_from_slice(&bytes[i * 8..i * 8 + 8]);
            *limb = u64::from_be_bytes(eight);
        }
        U256(limbs)
    }

    pub fn to_be_bytes(self) -> [u8; 32] {
        let mut out = [0u8; 32];
        for (i, limb) in self.0.iter().enumerate() {
            out[i * 8..i * 8 + 8].copy_from_slice(&limb.to_be_bytes());
        }
        out
    }

    pub fn from_u64(value: u64) -> Self {
        U256([0, 0, 0, value])
    }

    // A single bit set at position `n`, counted from the low end: the shift of the ring the rule
    // of entries takes, written as a value rather than as a shift so that a position beyond the
    // width is refused instead of wrapping.
    pub fn bit(n: u32) -> Option<Self> {
        if n >= 256 {
            return None;
        }
        let mut limbs = [0u64; 4];
        limbs[3 - (n / 64) as usize] = 1u64 << (n % 64);
        Some(U256(limbs))
    }

    // The low `n` bits, which is the remainder of a division by two raised to `n`. The rule of
    // entries reduces an offset inside the scale of a ring, and every such scale is a power of two.
    pub fn low_bits(self, n: u32) -> Option<Self> {
        if n > 256 {
            return None;
        }
        let mut limbs = self.0;
        for (i, limb) in limbs.iter_mut().enumerate() {
            let position = (3 - i) as u32 * 64;
            if n <= position {
                *limb = 0;
            } else if n < position + 64 {
                *limb &= (1u64 << (n - position)) - 1;
            }
        }
        Some(U256(limbs))
    }

    // Addition on the ring: the sum passes the top and continues from the bottom, which is the
    // wrap the ring of commitments is defined by.
    pub fn wrapping_add(self, other: Self) -> Self {
        let mut out = [0u64; 4];
        let mut carry = 0u128;
        for i in (0..4).rev() {
            let wide = u128::from(self.0[i]) + u128::from(other.0[i]) + carry;
            out[i] = wide as u64;
            carry = wide >> 64;
        }
        U256(out)
    }

    // The one operation the retargets need: `self × numer / denom`, the multiplication first and
    // the division truncating toward zero. The product is held in five limbs, which is what makes
    // the order of the two operations the set states possible to obey at all.
    pub fn mul_div(self, numer: u64, denom: u64) -> Option<Self> {
        if denom == 0 {
            return None;
        }
        let mut product = [0u64; 5];
        let mut carry = 0u128;
        for i in (0..4).rev() {
            let wide = u128::from(self.0[i]) * u128::from(numer) + carry;
            product[i + 1] = wide as u64;
            carry = wide >> 64;
        }
        product[0] = carry as u64;

        let mut quotient = [0u64; 5];
        let mut remainder = 0u128;
        for i in 0..5 {
            let current = (remainder << 64) | u128::from(product[i]);
            quotient[i] = (current / u128::from(denom)) as u64;
            remainder = current % u128::from(denom);
        }
        // A quotient beyond the width is not a threshold of this protocol. The ratio of either
        // rule is bounded by the damping, so this is unreachable through the rules; a caller
        // reaching it is told rather than handed a wrapped number.
        if quotient[0] != 0 {
            return None;
        }
        Some(U256([quotient[1], quotient[2], quotient[3], quotient[4]]))
    }

    // Division by a small unsigned, toward zero: the lower end of the clamp.
    pub fn div_u64(self, divisor: u64) -> Option<Self> {
        if divisor == 0 {
            return None;
        }
        let mut quotient = [0u64; 4];
        let mut remainder = 0u128;
        for (slot, limb) in quotient.iter_mut().zip(self.0.iter()) {
            let current = (remainder << 64) | u128::from(*limb);
            *slot = (current / u128::from(divisor)) as u64;
            remainder = current % u128::from(divisor);
        }
        Some(U256(quotient))
    }

    // Multiplication by a small unsigned: the upper end of the clamp. A product beyond the width
    // is answered as the width's maximum, because the clamp that consumes it only ever compares
    // against a number that fits.
    pub fn saturating_mul_u64(self, factor: u64) -> Self {
        let mut out = [0u64; 4];
        let mut carry = 0u128;
        for i in (0..4).rev() {
            let wide = u128::from(self.0[i]) * u128::from(factor) + carry;
            out[i] = wide as u64;
            carry = wide >> 64;
        }
        if carry != 0 {
            return U256([u64::MAX; 4]);
        }
        U256(out)
    }

    pub fn is_zero(self) -> bool {
        self.0 == [0u64; 4]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(v: U256) -> String {
        v.to_be_bytes().iter().map(|b| format!("{b:02x}")).collect()
    }

    fn two_pow_248() -> U256 {
        let mut bytes = [0u8; 32];
        bytes[0] = 1;
        U256::from_be_bytes(&bytes)
    }

    #[test]
    fn the_order_of_the_bytes_is_the_one_a_threshold_is_compared_in() {
        // Most significant byte first, and a value whose two ends differ tells the two readings
        // apart — a vector standing on a palindrome could not.
        let mut bytes = [0u8; 32];
        bytes[0] = 0x01;
        bytes[31] = 0xFF;
        let held = U256::from_be_bytes(&bytes);
        assert_eq!(held.to_be_bytes(), bytes);
        let mut reversed = bytes;
        reversed.reverse();
        assert!(U256::from_be_bytes(&reversed) > held);
    }

    #[test]
    fn the_product_is_taken_before_the_division_and_the_division_truncates() {
        // Five thirds of two to the two hundred and forty-eighth: a rule that divided first would
        // answer one times it, because one and two thirds truncates to one.
        let held = two_pow_248().mul_div(5, 3).expect("within the width");
        assert_eq!(
            hex(held),
            "01aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        );
        assert_ne!(
            held,
            two_pow_248().div_u64(3).unwrap().saturating_mul_u64(5)
        );
        // And the truncation is toward zero at every width.
        assert_eq!(U256::from_u64(7).mul_div(1, 2), Some(U256::from_u64(3)));
        assert_eq!(U256::from_u64(1).mul_div(1, 2), Some(U256::ZERO));
    }

    #[test]
    fn a_divisor_of_zero_and_a_quotient_beyond_the_width_are_refused() {
        assert_eq!(U256::from_u64(5).mul_div(1, 0), None);
        assert_eq!(U256::from_u64(5).div_u64(0), None);
        let top = U256([u64::MAX; 4]);
        assert_eq!(top.mul_div(2, 1), None);
        assert_eq!(top.saturating_mul_u64(2), top);
    }

    #[test]
    fn the_small_operations_answer_what_they_are_asked() {
        assert_eq!(U256::from_u64(12).div_u64(4), Some(U256::from_u64(3)));
        assert_eq!(U256::from_u64(3).saturating_mul_u64(4), U256::from_u64(12));
        assert!(U256::ZERO.is_zero());
        assert!(!U256::ONE.is_zero());
        assert!(U256::ONE > U256::ZERO);
    }
}
