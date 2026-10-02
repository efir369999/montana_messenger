// spec, раздел "Ключи → Мнемоника и seed → Algorithm M-1 Шаг 3"

pub const INDICES_COUNT: usize = 24;
pub const INDEX_BITS: usize = 11;
pub const PACKED_BYTES: usize = 33; // 24 * 11 = 264 бит = 33 байта

pub fn pack_indices_to_bytes(indices: &[u16; INDICES_COUNT]) -> [u8; PACKED_BYTES] {
    let mut buf = [0u8; PACKED_BYTES];
    let mut bit_pos = 0;
    for idx in indices.iter().take(INDICES_COUNT) {
        for b in 0..INDEX_BITS {
            let bit = ((idx >> (INDEX_BITS - 1 - b)) & 1) as u8;
            let byte_idx = bit_pos / 8;
            let bit_in_byte = 7 - (bit_pos % 8);
            buf[byte_idx] |= bit << bit_in_byte;
            bit_pos += 1;
        }
    }
    buf
}

pub fn unpack_bytes_to_indices(buf: &[u8; PACKED_BYTES]) -> [u16; INDICES_COUNT] {
    let mut indices = [0u16; INDICES_COUNT];
    let mut bit_pos = 0;
    for idx in indices.iter_mut().take(INDICES_COUNT) {
        let mut acc: u16 = 0;
        for b in 0..INDEX_BITS {
            let byte_idx = bit_pos / 8;
            let bit_in_byte = 7 - (bit_pos % 8);
            let bit = (buf[byte_idx] >> bit_in_byte) & 1;
            acc |= (bit as u16) << (INDEX_BITS - 1 - b);
            bit_pos += 1;
        }
        *idx = acc;
    }
    indices
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pack_all_zeros() {
        let indices = [0u16; 24];
        let buf = pack_indices_to_bytes(&indices);
        assert_eq!(buf, [0u8; 33]);
    }

    #[test]
    fn pack_all_max() {
        // Каждый индекс = 0x7FF (11 bits все 1) — buf должен быть все 0xFF
        let indices = [0x7FFu16; 24];
        let buf = pack_indices_to_bytes(&indices);
        assert_eq!(buf, [0xFFu8; 33]);
    }

    #[test]
    fn unpack_all_zeros() {
        let buf = [0u8; 33];
        let indices = unpack_bytes_to_indices(&buf);
        assert_eq!(indices, [0u16; 24]);
    }

    #[test]
    fn unpack_all_ones() {
        let buf = [0xFFu8; 33];
        let indices = unpack_bytes_to_indices(&buf);
        assert_eq!(indices, [0x7FFu16; 24]);
    }

    #[test]
    fn roundtrip_random_patterns() {
        let patterns: [[u16; 24]; 4] = [
            [
                0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
                23,
            ],
            [2047; 24],
            [
                0, 2047, 0, 2047, 0, 2047, 0, 2047, 0, 2047, 0, 2047, 0, 2047, 0, 2047, 0, 2047, 0,
                2047, 0, 2047, 0, 2047,
            ],
            [
                1024, 0, 1, 2047, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1, 0, 2046, 1023, 511, 255,
                127, 63, 31, 15, 7,
            ],
        ];
        for p in &patterns {
            let buf = pack_indices_to_bytes(p);
            let back = unpack_bytes_to_indices(&buf);
            assert_eq!(&back, p);
        }
    }

    #[test]
    fn pack_bip39_standard_vector_all_abandon() {
        // BIP-39 standard: entropy = all zeros → 23 × abandon (idx 0) + last word depends on checksum
        // Bit-packing только — первые 23 index по 0, последний = checksum byte bits.
        // Берём случай где entropy=0 и checksum=0x66 (известный SHA-256(0^32)[0]):
        // last word index = bits 253..263 = 3 нулевых бита (entropy tail) + 8 bits checksum
        //                 = 0b000_01100110 = 102 → word "art" в BIP-39
        // Здесь проверяем только bit-packing — что index 102 recovered.
        let mut buf = [0u8; 33];
        buf[32] = 0x66; // checksum byte
                        // entropy bytes все нулевые
        let indices = unpack_bytes_to_indices(&buf);
        assert_eq!(indices[..23], [0u16; 23]);
        assert_eq!(indices[23], 102);
    }

    #[test]
    fn pack_msb_first_within_index() {
        // Index[0] = 0b10000000000 = 0x400 = 1024 → первый bit должен быть 1, остальные 10 — 0
        // MSB-first: первый bit входит в MSB buf[0] = 0x80
        let mut indices = [0u16; 24];
        indices[0] = 0x400; // 0b10000000000
        let buf = pack_indices_to_bytes(&indices);
        assert_eq!(buf[0], 0x80, "MSB of index 0 should land in MSB of byte 0");
        assert_eq!(buf[1], 0x00);
    }

    #[test]
    fn pack_lsb_of_index_0() {
        // Index[0] = 0b00000000001 = 1 — единичный bit в LSB 11-bit слова
        // После 11 битов MSB-first, LSB попадает в bit 3 MSB-first count:
        //   bit 10 (индекс битов pos=10) → в byte 1, bit-in-byte = 7 - (10 % 8) = 5
        //   значит buf[1] |= 1 << 5 = 0x20
        let mut indices = [0u16; 24];
        indices[0] = 1;
        let buf = pack_indices_to_bytes(&indices);
        assert_eq!(buf[0], 0x00);
        assert_eq!(buf[1], 0x20);
    }
}
