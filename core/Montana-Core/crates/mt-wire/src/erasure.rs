// The erasure code of a delivery. Reed-Solomon over the field of 256 elements with the modulus of
// the polynomial basis every implementation of that field already carries, and a Cauchy coding
// matrix — every square submatrix of which is invertible, which is why any `erasure_data` cells of
// a group suffice and why the matrix is Cauchy rather than Vandermonde.

use crate::WireError;
use std::sync::OnceLock;

// The modulus of the polynomial basis, stated by the set.
mt_codec::constants! {
    FIELD:
    const MODULUS: u16 = 0x11D, writes "GF(2^8) with modulus 0x11D";
}

// Multiplication in the field, without a branch on either operand. One of the two is a byte of
// somebody's letter — the code runs over the body before it is sealed — and a condition on its bits
// is a condition a machine takes a measurably different time over. What replaces the condition is a
// mask of all ones or of all zeros, so the same eight steps run whatever the bytes are.
fn mul(a: u8, b: u8) -> u8 {
    let mut product = 0u8;
    let mut left = a;
    let mut right = b;
    for _ in 0..8 {
        let take = 0u8.wrapping_sub(right & 1);
        product ^= left & take;
        let overflows = 0u8.wrapping_sub(left >> 7);
        left <<= 1;
        left ^= ((MODULUS & 0xFF) as u8) & overflows;
        right >>= 1;
    }
    product
}

// The inverse of every element but zero, found once by walking the field: a table of 256 bytes,
// computed rather than written, so no transcription of it can be wrong.
fn inverses() -> &'static [u8; 256] {
    static TABLE: OnceLock<[u8; 256]> = OnceLock::new();
    TABLE.get_or_init(|| {
        let mut table = [0u8; 256];
        for a in 1..=255u8 {
            for b in 1..=255u8 {
                if mul(a, b) == 1 {
                    table[a as usize] = b;
                    break;
                }
            }
        }
        table
    })
}

fn inverse(a: u8) -> Result<u8, WireError> {
    if a == 0 {
        return Err(WireError::Singular);
    }
    Ok(inverses()[a as usize])
}

// The cells of one group, and how many of them carry body rather than parity.
pub fn group() -> Result<usize, WireError> {
    crate::scalar("erasure_group")
}

pub fn data() -> Result<usize, WireError> {
    let group = group()?;
    let (num, den) = mt_genesis::ratio("redundancy").ok_or(WireError::DecreeIncomplete)?;
    let num = usize::try_from(num).map_err(|_| WireError::DecreeIncomplete)?;
    let den = usize::try_from(den).map_err(|_| WireError::DecreeIncomplete)?;
    if den == 0 || group * num % den != 0 {
        return Err(WireError::DecreeIncomplete);
    }
    Ok(group - group * num / den)
}

pub fn parity_count() -> Result<usize, WireError> {
    Ok(group()? - data()?)
}

// The coding matrix: cauchy[i][j] = inverse( (erasure_data + i) XOR j ).
pub fn cauchy() -> Result<Vec<Vec<u8>>, WireError> {
    let data = data()?;
    let rows = parity_count()?;
    let mut out = Vec::with_capacity(rows);
    for i in 0..rows {
        let mut row = Vec::with_capacity(data);
        for j in 0..data {
            row.push(inverse(((data + i) ^ j) as u8)?);
        }
        out.push(row);
    }
    Ok(out)
}

// The parity blocks of one group: each is the sum in the field of every body block scaled by its
// coefficient, byte by byte.
pub fn parity(blocks: &[Vec<u8>]) -> Result<Vec<Vec<u8>>, WireError> {
    let data = data()?;
    // A code that carried no body block is not this code; the Decree that produced it is not this
    // protocol, and the answer is a refusal rather than a read past the end of an empty group.
    if data == 0 {
        return Err(WireError::DecreeIncomplete);
    }
    if blocks.len() != data {
        return Err(WireError::WrongLength {
            expected: data,
            found: blocks.len(),
        });
    }
    let width = blocks[0].len();
    if blocks.iter().any(|b| b.len() != width) {
        return Err(WireError::WrongLength {
            expected: width,
            found: blocks
                .iter()
                .map(Vec::len)
                .find(|l| *l != width)
                .unwrap_or(width),
        });
    }
    let matrix = cauchy()?;
    let mut out = Vec::with_capacity(parity_count()?);
    for row in &matrix {
        let mut block = vec![0u8; width];
        for (j, coefficient) in row.iter().enumerate() {
            for (slot, byte) in block.iter_mut().zip(blocks[j].iter()) {
                *slot ^= mul(*coefficient, *byte);
            }
        }
        out.push(block);
    }
    Ok(out)
}

// The cells of a group in the order the set gives them: the body blocks themselves, then the
// parity blocks.
pub fn encode(blocks: &[Vec<u8>]) -> Result<Vec<Vec<u8>>, WireError> {
    let mut out = blocks.to_vec();
    out.extend(parity(blocks)?);
    Ok(out)
}

// The row of the coding matrix a cell of a group stands for: the unit row for a body block, the
// Cauchy row for a parity block.
fn row_of(position: usize, data: usize, matrix: &[Vec<u8>]) -> Result<Vec<u8>, WireError> {
    if position < data {
        let mut row = vec![0u8; data];
        row[position] = 1;
        return Ok(row);
    }
    matrix
        .get(position - data)
        .cloned()
        .ok_or(WireError::Singular)
}

// Reconstruction from any `erasure_data` cells of a group, and from no fewer: the matrix of their
// rows is inverted in the field and applied to what they carry.
pub fn reconstruct(present: &[(usize, Vec<u8>)]) -> Result<Vec<Vec<u8>>, WireError> {
    let data = data()?;
    if data == 0 {
        return Err(WireError::DecreeIncomplete);
    }
    if present.len() < data {
        return Err(WireError::TooFewCells {
            needed: data,
            held: present.len(),
        });
    }
    let matrix = cauchy()?;
    let taken = &present[..data];
    let width = taken[0].1.len();
    if taken.iter().any(|(_, b)| b.len() != width) {
        return Err(WireError::WrongLength {
            expected: width,
            found: taken
                .iter()
                .map(|(_, b)| b.len())
                .find(|l| *l != width)
                .unwrap_or(width),
        });
    }
    // The system, its right-hand side beside it: rows of the coding matrix on the left, the bytes
    // the cells carry on the right, and Gauss-Jordan over the field turns one into the other.
    let mut left: Vec<Vec<u8>> = Vec::with_capacity(data);
    let mut right: Vec<Vec<u8>> = Vec::with_capacity(data);
    for (position, bytes) in taken {
        left.push(row_of(*position, data, &matrix)?);
        right.push(bytes.clone());
    }
    for column in 0..data {
        let pivot = (column..data)
            .find(|row| left[*row][column] != 0)
            .ok_or(WireError::Singular)?;
        left.swap(column, pivot);
        right.swap(column, pivot);
        let inverse = inverse(left[column][column])?;
        for slot in left[column].iter_mut() {
            *slot = mul(*slot, inverse);
        }
        for slot in right[column].iter_mut() {
            *slot = mul(*slot, inverse);
        }
        let pivot_left = left[column].clone();
        let pivot_right = right[column].clone();
        for row in 0..data {
            if row == column {
                continue;
            }
            let factor = left[row][column];
            if factor == 0 {
                continue;
            }
            for (slot, base) in pivot_left.iter().enumerate() {
                left[row][slot] ^= mul(factor, *base);
            }
            for (slot, base) in pivot_right.iter().enumerate() {
                right[row][slot] ^= mul(factor, *base);
            }
        }
    }
    Ok(right)
}

// A body is cut into blocks of the width one cell carries, the last block padded with zeros to that
// width. The count of blocks the delivery layer names is what tells the reader where the body ends;
// the padding says nothing, because every block is of one width whatever it holds.
//
// MSRV-OK: integer `div_ceil` is stable since 1.73 and this workspace declares 1.90.
pub fn cut(body: &[u8]) -> Result<Vec<Vec<u8>>, WireError> {
    let width = crate::chunk_bytes()?;
    let count = body.len().div_ceil(width).max(1);
    let mut out = Vec::with_capacity(count);
    for index in 0..count {
        let at = index * width;
        let end = body.len().min(at + width);
        let mut block = vec![0u8; width];
        if at < body.len() {
            block[..end - at].copy_from_slice(&body[at..end]);
        }
        out.push(block);
    }
    Ok(out)
}

// The blocks grouped as the code takes them: `erasure_data` at a time, the last group filled to
// that count with blocks of zeros so that every group of a delivery is one shape. Each group
// answers `erasure_group` cells, of which the last quarter is parity.
pub fn groups(blocks: &[Vec<u8>]) -> Result<Vec<Vec<Vec<u8>>>, WireError> {
    let data = data()?;
    if data == 0 {
        return Err(WireError::DecreeIncomplete);
    }
    let width = crate::chunk_bytes()?;
    // MSRV-OK: as above — integer `div_ceil` is stable since 1.73 and this tree declares 1.90.
    let mut out = Vec::with_capacity(blocks.len().div_ceil(data));
    for chunk in blocks.chunks(data) {
        let mut group: Vec<Vec<u8>> = chunk.to_vec();
        while group.len() < data {
            group.push(vec![0u8; width]);
        }
        out.push(encode(&group)?);
    }
    Ok(out)
}

// What a delivery of a body costs in cells, by the counts the set derives beside its own examples.
pub fn cells_of(body_length: usize) -> Result<usize, WireError> {
    // MSRV-OK: as above — integer `div_ceil` is stable since 1.73 and this tree declares 1.90.
    let blocks = body_length.div_ceil(crate::chunk_bytes()?).max(1);
    Ok(blocks.div_ceil(data()?) * group()?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn body() -> Vec<Vec<u8>> {
        let width = crate::chunk_bytes().expect("the Decree names the width");
        (0..data().expect("named"))
            .map(|j| vec![(0xA0 + j) as u8; width])
            .collect()
    }

    #[test]
    fn the_shape_of_a_group_is_the_one_the_decree_gives() {
        assert_eq!(group(), Ok(16));
        assert_eq!(data(), Ok(12));
        assert_eq!(parity_count(), Ok(4));
    }

    #[test]
    fn the_parity_of_the_frozen_group_is_the_frozen_value() {
        // Canon, "The vectors of the wire".
        use sha2::{Digest, Sha256};
        let parity = parity(&body()).expect("the group is of the right shape");
        let heads: Vec<String> = parity
            .iter()
            .map(|block| {
                format!(
                    "{:02x}{:02x}{:02x}{:02x}",
                    block[0], block[1], block[2], block[3]
                )
            })
            .collect();
        assert_eq!(heads, ["a5a5a5a5", "acacacac", "b7b7b7b7", "bebebebe"]);
        let mut h = Sha256::new();
        for block in &parity {
            h.update(block);
        }
        let digest: [u8; 32] = h.finalize().into();
        assert_eq!(
            digest
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>(),
            "8963024273fc41fdf9afe063f3be77e7fbc312a7d8ede4f96a7fd99dd4fd0e69"
        );
    }

    #[test]
    fn a_group_missing_four_cells_reconstructs() {
        // Canon: the twelve remaining when 0, 5, 7 and 11 are lost return the twelve body blocks.
        let body = body();
        let whole = encode(&body).expect("the group encodes");
        let lost = [0usize, 5, 7, 11];
        let present: Vec<(usize, Vec<u8>)> = whole
            .iter()
            .enumerate()
            .filter(|(position, _)| !lost.contains(position))
            .map(|(position, block)| (position, block.clone()))
            .collect();
        assert_eq!(present.len(), data().expect("named"));
        assert_eq!(reconstruct(&present).expect("the group reconstructs"), body);
    }

    #[test]
    fn reconstruction_is_attempted_from_no_fewer_than_the_code_needs() {
        let whole = encode(&body()).expect("encodes");
        let present: Vec<(usize, Vec<u8>)> = whole
            .iter()
            .enumerate()
            .take(data().expect("named") - 1)
            .map(|(position, block)| (position, block.clone()))
            .collect();
        assert_eq!(
            reconstruct(&present),
            Err(WireError::TooFewCells {
                needed: 12,
                held: 11
            })
        );
    }

    #[test]
    fn any_twelve_of_the_sixteen_reconstruct_the_body() {
        // The property the Cauchy matrix buys: every square submatrix is invertible, so which four
        // were lost carries nothing. Walked over every choice of four losses.
        // Narrow blocks: what this walks is a property of the matrix, and a block of the width a
        // cell carries would buy the same proof at a hundredfold of the time.
        let body: Vec<Vec<u8>> = (0..data().expect("named"))
            .map(|j| vec![(0xA0 + j) as u8; 8])
            .collect();
        let whole = encode(&body).expect("encodes");
        let group = group().expect("named");
        let mut walked = 0;
        for a in 0..group {
            for b in (a + 1)..group {
                for c in (b + 1)..group {
                    for d in (c + 1)..group {
                        let lost = [a, b, c, d];
                        let present: Vec<(usize, Vec<u8>)> = whole
                            .iter()
                            .enumerate()
                            .filter(|(position, _)| !lost.contains(position))
                            .map(|(position, block)| (position, block.clone()))
                            .collect();
                        assert_eq!(
                            reconstruct(&present).expect("every twelve reconstruct"),
                            body,
                            "lost {lost:?}"
                        );
                        walked += 1;
                    }
                }
            }
        }
        assert_eq!(walked, 1_820);
    }

    #[test]
    fn the_field_is_the_one_the_set_names() {
        // A field of another modulus produces parity nobody can use, and the multiplication below
        // is what its vector stands on: every element but zero has an inverse, and it is unique.
        for a in 1..=255u8 {
            let inverse = inverse(a).expect("every element but zero has one");
            assert_eq!(mul(a, inverse), 1, "{a}");
        }
        assert_eq!(inverse(0), Err(WireError::Singular));
    }

    #[test]
    fn a_body_is_cut_padded_and_grouped_by_the_rule_the_set_states() {
        let width = crate::chunk_bytes().expect("named");
        let data = data().expect("named");
        let group = group().expect("named");
        for length in [
            0usize,
            1,
            width - 1,
            width,
            width + 1,
            12 * width,
            12 * width + 5,
        ] {
            let body: Vec<u8> = (0..length).map(|i| (i % 251) as u8).collect();
            let blocks = cut(&body).expect("cuts");
            assert_eq!(blocks.len(), length.div_ceil(width).max(1));
            assert!(blocks.iter().all(|b| b.len() == width));
            let joined: Vec<u8> = blocks.concat();
            assert_eq!(&joined[..length], &body[..]);
            assert!(joined[length..].iter().all(|b| *b == 0));
            let grouped = groups(&blocks).expect("groups");
            assert_eq!(grouped.len(), blocks.len().div_ceil(data));
            assert!(grouped.iter().all(|g| g.len() == group));
            assert_eq!(
                grouped.len() * group,
                cells_of(length).expect("the count of cells")
            );
        }
    }

    #[test]
    fn the_count_of_cells_is_the_one_the_set_derives_for_its_own_objects() {
        // Canon, "What a delivery costs in cells": a heavy attestation is 304 blocks in 26 groups,
        // so 416 cells, and that is what the bound of a collection stands on.
        assert_eq!(cells_of(263_377), Ok(416));
    }

    #[test]
    fn the_multiplication_takes_the_same_steps_whatever_the_bytes_are() {
        // What this asserts is the arithmetic; what the shape of the code asserts is the time. The
        // condition on a byte of a letter is gone, replaced by a mask, and every product of the
        // field still answers what the field says it answers.
        for a in 0..=255u8 {
            for b in 0..=255u8 {
                let mut slow = 0u8;
                let (mut left, mut right) = (a, b);
                for _ in 0..8 {
                    if right & 1 == 1 {
                        slow ^= left;
                    }
                    let high = left & 0x80;
                    left <<= 1;
                    if high != 0 {
                        left ^= (MODULUS & 0xFF) as u8;
                    }
                    right >>= 1;
                }
                assert_eq!(mul(a, b), slow, "{a} x {b}");
            }
        }
    }
}
