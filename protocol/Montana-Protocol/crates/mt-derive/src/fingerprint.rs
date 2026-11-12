// The fingerprint two people compare out of band. The set states it in `docs/Montana Canon.md`,
// "The fingerprint compared out of band": the key is folded under the safety domain a fixed number
// of times, and the first thirty bytes of the result are read as six groups of five, each reduced
// modulo one hundred thousand and written as five decimal digits.
//
// There is exactly one derivation, and a second would let a comparison succeed on one path and fail
// on the other. The groups are read big-endian, and the frozen vector is what catches the other
// reading.

use mt_codec::{domain, hash, hash_of_one, Part};

mt_codec::constants! {
    FINGERPRINT:
    pub const ITERATIONS: u32 = 5_200, writes "| `fingerprint_iterations` | 5 200 |";
    pub const GROUPS: usize = 6, spells "read them as six groups";
    pub const GROUP_BYTES: usize = 5, spells "groups of five bytes";
    pub const GROUP_MODULUS: u64 = 100_000, writes "reduced modulo 100000";
}

pub fn digits(answering_key: &[u8]) -> [u32; GROUPS] {
    let mut h = hash_of_one(domain::MT_SAFETY, answering_key);
    for _ in 1..ITERATIONS {
        h = hash(domain::MT_SAFETY, &[Part::of(&h)]);
    }
    let mut out = [0u32; GROUPS];
    for (group, slot) in out.iter_mut().enumerate() {
        let at = group * GROUP_BYTES;
        let mut value = 0u64;
        for byte in &h[at..at + GROUP_BYTES] {
            value = (value << 8) | u64::from(*byte);
        }
        *slot = (value % GROUP_MODULUS) as u32;
    }
    out
}

// Six groups of five digits, separated by single spaces: one number for speech, screen and a
// scanned code alike.
pub fn shown(answering_key: &[u8]) -> String {
    let groups = digits(answering_key);
    let mut out = String::with_capacity(GROUPS * (GROUP_BYTES + 1) - 1);
    for (i, group) in groups.iter().enumerate() {
        if i > 0 {
            out.push(' ');
        }
        out.push_str(&format!("{group:05}"));
    }
    out
}

// Both people read identical digits without agreeing who reads first: the two keys are ordered
// ascending as big-endian integers and their fingerprints concatenated in that order.
pub fn of_pair(a: &[u8], b: &[u8]) -> String {
    let (first, second) = if a <= b { (a, b) } else { (b, a) };
    format!("{} {}", shown(first), shown(second))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_fingerprint_is_the_frozen_one() {
        // Canon, "The fingerprint compared out of band".
        assert_eq!(shown(&[0x66u8; 32]), "00534 22536 46923 62969 86064 85215");
    }

    #[test]
    fn the_groups_are_read_from_the_most_significant_byte() {
        // The other reading gives another number, which is what the frozen vector catches: an
        // implementation reading a group little-endian shows digits nobody else shows.
        let mut h = hash_of_one(domain::MT_SAFETY, &[0x66u8; 32][..]);
        for _ in 1..ITERATIONS {
            h = hash(domain::MT_SAFETY, &[Part::of(&h)]);
        }
        let little: Vec<u32> = (0..GROUPS)
            .map(|g| {
                let mut value = 0u64;
                for byte in h[g * GROUP_BYTES..g * GROUP_BYTES + GROUP_BYTES]
                    .iter()
                    .rev()
                {
                    value = (value << 8) | u64::from(*byte);
                }
                (value % GROUP_MODULUS) as u32
            })
            .collect();
        assert_ne!(little[..], digits(&[0x66u8; 32])[..]);
    }

    #[test]
    fn the_count_of_iterations_is_the_one_the_set_fixes_and_a_neighbour_of_it_differs() {
        let mut once_less = hash_of_one(domain::MT_SAFETY, &[0x66u8; 32][..]);
        for _ in 1..(ITERATIONS - 1) {
            once_less = hash_of_one(domain::MT_SAFETY, &once_less);
        }
        let mut groups = [0u32; GROUPS];
        for (g, slot) in groups.iter_mut().enumerate() {
            let mut value = 0u64;
            for byte in &once_less[g * GROUP_BYTES..g * GROUP_BYTES + GROUP_BYTES] {
                value = (value << 8) | u64::from(*byte);
            }
            *slot = (value % GROUP_MODULUS) as u32;
        }
        assert_ne!(groups, digits(&[0x66u8; 32]));
    }

    #[test]
    fn a_change_of_the_key_yields_a_new_fingerprint() {
        assert_ne!(shown(&[0x66u8; 32]), shown(&[0x67u8; 32]));
    }

    #[test]
    fn the_pair_form_is_ordered_so_both_sides_read_one_number() {
        let a = [0x11u8; 32];
        let b = [0x22u8; 32];
        assert_eq!(of_pair(&a, &b), of_pair(&b, &a));
        assert_eq!(of_pair(&a, &b), format!("{} {}", shown(&a), shown(&b)));
    }

    #[test]
    fn every_group_is_five_digits_and_thirty_stand_in_all() {
        let shown = shown(&[0x01u8; 32]);
        let groups: Vec<&str> = shown.split(' ').collect();
        assert_eq!(groups.len(), GROUPS);
        for group in groups {
            assert_eq!(group.len(), GROUP_BYTES);
            assert!(group.bytes().all(|b| b.is_ascii_digit()));
        }
    }
}
