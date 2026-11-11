// Poseidon2 over the proof field, the authors' instantiation for width twelve: the constants
// below are the reference's own, reproduced verbatim, and the test at the bottom holds this
// implementation to the known answer the authors publish — an implementation that transcribed
// one constant wrongly reproduces nothing of it.
//
// The permutation is what the set names `proof_hash` and is admitted for exactly what circuits
// walk: the trees and the transcript of a proof, and the trees whose paths exist only as
// witnesses of proofs. Everything an implementation or a person compares without a proof in
// hand stays SHA-256, and the doors below take their domains from the one registry.

use crate::field::F;
use mt_codec::Domain;

mt_codec::constants! {
    SHAPE:
    /// The width of the permutation state, in field elements.
    pub const WIDTH: usize = 12, writes "width 12";
    /// The elements absorbed per block; what remains is the capacity.
    pub const RATE: usize = 8, writes "its rate
of 8 absorbs";
    /// The elements the capacity holds, and the digest squeezed: four elements, 32 B.
    pub const CAPACITY: usize = 4, writes "capacity of 4 elements";
    /// The bytes one limb of a byte string carries into an element: four, the one width at
    /// which every seam of the protocol falls on a limb.
    pub const LIMB_BYTES: usize = 4, spells "limbs of four bytes each";
    /// The external rounds, half before the internal ones and half after.
    pub const ROUNDS_EXTERNAL: usize = 8, writes "the rounds are 8 external";
    /// The internal rounds, where one cell alone takes the power.
    pub const ROUNDS_PARTIAL: usize = 22, writes "22 internal";
}

// A digest of this permutation: four elements of the field, and nothing else can be one. There are
// two doors and no third — the squeeze below, which yields elements by construction, and the door
// that takes thirty-two bytes from outside and refuses them unless every limb is an element. That
// is what stands between a node of a path arriving over a wire and the arithmetic that consumes it,
// and it is held by the type rather than by an assertion inside the arithmetic: a value that is not
// a digest has no way to reach the permutation at all.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Digest([F; CAPACITY]);

impl Digest {
    pub const ZERO: Digest = Digest([F::ZERO; CAPACITY]);

    // The four words of a digest, read where an absorption consumes another digest: `cells(x)`
    // of the set. A derivation that consumes a digest takes these and never the limbs of its
    // bytes, so no splitting of a word exists anywhere in the family.
    pub fn elements(&self) -> &[F; CAPACITY] {
        &self.0
    }

    pub fn bytes(&self) -> [u8; 32] {
        let mut out = [0u8; 32];
        for (at, cell) in self.0.iter().enumerate() {
            out[at * 8..at * 8 + 8].copy_from_slice(&cell.as_u64().to_le_bytes());
        }
        out
    }

    // The one door for bytes that arrived from outside this tree. A word at or above the modulus is
    // not an element of this field, so what these bytes are is not a digest, and the answer is
    // nothing rather than a folded value: folding would give one digest two preimages.
    pub fn of_bytes(bytes: &[u8; 32]) -> Option<Digest> {
        let mut out = [F::ZERO; CAPACITY];
        for (at, slot) in out.iter_mut().enumerate() {
            let mut raw = [0u8; 8];
            raw.copy_from_slice(&bytes[at * 8..at * 8 + 8]);
            *slot = F::try_from_u64(u64::from_le_bytes(raw))?;
        }
        Some(Digest(out))
    }
}

const ROUNDS_FULL_HALF: usize = ROUNDS_EXTERNAL / 2;
const ROUNDS: usize = ROUNDS_EXTERNAL + ROUNDS_PARTIAL;

#[rustfmt::skip]
const DIAGONAL_LESS_ONE: [u64; 12] = [
    0xC3B6C08E23BA9300,
    0xD84B5DE94A324FB6,
    0x0D0C371C5B35B84F,
    0x7964F570E7188037,
    0x5DAF18BBD996604B,
    0x6743BC47B9595257,
    0x5528B9362C59BB70,
    0xAC45E25B7127B68B,
    0xA2077D7DFBB606B5,
    0xF3FAAC6FAEE378AE,
    0x0C6388B51545E883,
    0xD27DBB6944917B60,
];

#[rustfmt::skip]
const ROUND_CONSTANTS: [[u64; 12]; 30] = [
    [0x13DCF33ABA214F46, 0x30B3B654A1DA6D83, 0x1FC634ADA6159B56, 0x937459964DC03466, 0xEDD2EF2CA7949924, 0xEDE9AFFDE0E22F68, 0x8515B9D6BAC9282D, 0x6B5C07B4E9E900D8, 0x1EC66368838C8A08, 0x9042367D80D1FBAB, 0x400283564A3C3799, 0x4A00BE0466BCA75E],
    [0x7913BEEE58E3817F, 0xF545E88532237D90, 0x22F8CB8736042005, 0x6F04990E247A2623, 0xFE22E87BA37C38CD, 0xD20E32C85FFE2815, 0x117227674048FE73, 0x4E9FB7EA98A6B145, 0xE0866C232B8AF08B, 0x00BBC77916884964, 0x7031C0FB990D7116, 0x240A9E87CF35108F],
    [0x2E6363A5A12244B3, 0x5E1C3787D1B5011C, 0x4132660E2A196E8B, 0x3A013B648D3D4327, 0xF79839F49888EA43, 0xFE85658EBAFE1439, 0xB6889825A14240BD, 0x578453605541382B, 0x4508CDA8F6B63CE9, 0x9C3EF35848684C91, 0x0812BDE23C87178C, 0xFE49638F7F722C14],
    [0x8E3F688CE885CBF5, 0xB8E110ACF746A87D, 0xB4B2E8973A6DABEF, 0x9E714C5DA3D462EC, 0x6438F9033D3D0C15, 0x24312F7CF1A27199, 0x23F843BB47ACBF71, 0x9183F11A34BE9F01, 0x839062FBB9D45DBF, 0x24B56E7E6C2E43FA, 0xE1683DA61C962A72, 0xA95C63971A19BFA7],
    [0x4ADF842AA75D4316, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xF8FBB871AA4AB4EB, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x68E85B6EB2DD6AEB, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x07A0B06B2D270380, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xD94E0228BD282DE4, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x8BDD91D3250C5278, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x209C68B88BBA778F, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xB5E18CDAB77F3877, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xB296A3E808DA93FA, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x8370ECBDA11A327E, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x3F9075283775DAD8, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xB78095BB23C6AA84, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x3F36B9FE72AD4E5F, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x69BC96780B10B553, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x3F1D341F2EB7B881, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x4E939E9815838818, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xDA366B3AE2A31604, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xBC89DB1E7287D509, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x6102F411F9EF5659, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x58725C5E7AC1F0AB, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0x0DF5856C798883E7, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xF7BB62A8DA4C961B, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
    [0xC68BE7C94882A24D, 0xAF996D5D5CDAEDD9, 0x9717F025E7DAF6A5, 0x6436679E6E7216F4, 0x8A223D99047AF267, 0xBB512E35A133BA9A, 0xFBBF44097671AA03, 0xF04058EBF6811E61, 0x5CCA84703FAC7FFB, 0x9B55C7945DE6469F, 0x8E05BF09808E934F, 0x2EA900DE876307D7],
    [0x7748FFF2B38DFB89, 0x6B99A676DD3B5D81, 0xAC4BB7C627CF7C13, 0xADB6EBE5E9E2F5BA, 0x2D33378CAFA24AE3, 0x1E5B73807543F8C2, 0x09208814BFEBB10F, 0x782E64B6BB5B93DD, 0xADD5A48EAC90B50F, 0xADD4C54C736EA4B1, 0xD58DBB86ED817FD8, 0x6D5ED1A533F34DDD],
    [0x28686AA3E36B7CB9, 0x591ABD3476689F36, 0x047D766678F13875, 0xA2A11112625F5B49, 0x21FD10A3F8304958, 0xF9B40711443B0280, 0xD2697EB8B2BDE88E, 0x3493790B51731B3F, 0x11CAF9DD73764023, 0x7ACFB8F72878164E, 0x744EC4DB23CEFC26, 0x1E00E58F422C6340],
    [0x21DD28D906A62DDA, 0xF32A46AB5F465B5F, 0xBFCE13201F3F7E6B, 0xF30D2E7ADB5304E2, 0xECDF4EE4ABAD48E9, 0xF94E82182D395019, 0x4EE52E3744D887C5, 0xA1341C7CAC0083B2, 0x2302FB26C30C834A, 0xAEA3C587273BF7D3, 0xF798E24961823EC7, 0x962DEBA3E9A2CD94],
];
fn quadruple(state: &mut [F; WIDTH], at: usize) {
    let t0 = state[at].plus(state[at + 1]);
    let t1 = state[at + 2].plus(state[at + 3]);
    let t2 = state[at + 1].plus(state[at + 1]).plus(t1);
    let t3 = state[at + 3].plus(state[at + 3]).plus(t0);
    let t4 = t1.plus(t1).plus(t1.plus(t1)).plus(t3);
    let t5 = t0.plus(t0).plus(t0.plus(t0)).plus(t2);
    state[at] = t3.plus(t5);
    state[at + 1] = t5;
    state[at + 2] = t2.plus(t4);
    state[at + 3] = t4;
}

// The two linear layers stand open because the circuit of a frame asserts this permutation and
// must speak its arithmetic from this one place: a circuit carrying its own copy of a matrix or of
// a constant is the second place that parts from the first the day either moves.
pub fn external(state: &mut [F; WIDTH]) {
    quadruple(state, 0);
    quadruple(state, 4);
    quadruple(state, 8);
    let mut stored = [F::ZERO; 4];
    for (l, slot) in stored.iter_mut().enumerate() {
        *slot = state[l].plus(state[4 + l]).plus(state[8 + l]);
    }
    for (i, cell) in state.iter_mut().enumerate() {
        *cell = cell.plus(stored[i % 4]);
    }
}

pub fn internal(state: &mut [F; WIDTH]) {
    let mut sum = F::ZERO;
    for cell in state.iter() {
        sum = sum.plus(*cell);
    }
    for (i, cell) in state.iter_mut().enumerate() {
        *cell = cell
            .times(F::from_u64_reduced(DIAGONAL_LESS_ONE[i]))
            .plus(sum);
    }
}

fn seventh(x: F) -> F {
    let x2 = x.times(x);
    let x4 = x2.times(x2);
    x4.times(x2).times(x)
}

// The constants of a round, read where they are written. The rounds run external, then internal,
// then external, in the order `permute` applies them, and a round beyond the count answers nothing.
pub const ROUNDS_TOTAL: usize = ROUNDS;

pub fn round_constant(round: usize, lane: usize) -> Option<F> {
    let constants = ROUND_CONSTANTS.get(round)?;
    Some(F::from_u64_reduced(*constants.get(lane)?))
}

// Whether the round at this index applies its S-box to every lane or to the first alone. The
// order is the one `permute` runs and is not a second schedule beside it.
pub fn round_is_external(round: usize) -> bool {
    !(ROUNDS_FULL_HALF..ROUNDS_FULL_HALF + ROUNDS_PARTIAL).contains(&round)
}

pub fn permute(state: &mut [F; WIDTH]) {
    external(state);
    for constants in &ROUND_CONSTANTS[..ROUNDS_FULL_HALF] {
        for (cell, rc) in state.iter_mut().zip(constants) {
            *cell = seventh(cell.plus(F::from_u64_reduced(*rc)));
        }
        external(state);
    }
    for constants in &ROUND_CONSTANTS[ROUNDS_FULL_HALF..ROUNDS_FULL_HALF + ROUNDS_PARTIAL] {
        state[0] = seventh(state[0].plus(F::from_u64_reduced(constants[0])));
        internal(state);
    }
    for constants in &ROUND_CONSTANTS[ROUNDS_FULL_HALF + ROUNDS_PARTIAL..ROUNDS] {
        for (cell, rc) in state.iter_mut().zip(constants) {
            *cell = seventh(cell.plus(F::from_u64_reduced(*rc)));
        }
        external(state);
    }
}

// The capacity a use starts from: the first four limbs of the domain's empty hash —
// the same value the empty leaf of a construction already stands on — so two domains never share
// an initial state, the registry stays the one place a domain exists, and the recorder of the
// gate sees every use the moment the capacity is derived.
pub fn capacity_of(domain: Domain) -> [F; CAPACITY] {
    let digest = mt_codec::hash_of_one(domain, &[]);
    let limbs = limbs_of(&digest);
    [limbs[0], limbs[1], limbs[2], limbs[3]]
}

// Bytes enter the field in little-endian limbs of `LIMB_BYTES`, the last limb short where the
// length demands: every limb is below two to the thirty-second and therefore canonical, and no
// byte string of a fixed length shares an encoding with another. The width is the set's own and is
// the one at which every seam of the protocol falls on a limb — a limb of another width moves every
// value of this family, which is why the row of the register carries it and this sentence does not.
pub fn limbs_of(bytes: &[u8]) -> Vec<F> {
    bytes
        .chunks(LIMB_BYTES)
        .map(|chunk| {
            let mut raw = [0u8; 8];
            raw[..chunk.len()].copy_from_slice(chunk);
            F::from_u64_reduced(u64::from_le_bytes(raw))
        })
        .collect()
}

fn squeeze(state: &[F; WIDTH]) -> Digest {
    let mut out = [F::ZERO; CAPACITY];
    for (slot, cell) in out.iter_mut().zip(state.iter().take(CAPACITY)) {
        *slot = *cell;
    }
    Digest(out)
}

// The sponge: the capacity is the domain's, the rate absorbs the elements in blocks by overwrite,
// and the input ends with a single one-element and zeros to the block boundary, so two inputs of
// different lengths never share an absorption. The digest is the first four elements, 32 B.
pub fn hash_elements(domain: Domain, elements: &[F]) -> Digest {
    let capacity = capacity_of(domain);
    let mut state = [F::ZERO; WIDTH];
    state[RATE..].copy_from_slice(&capacity);
    let mut padded = Vec::with_capacity(elements.len() + RATE);
    padded.extend_from_slice(elements);
    padded.push(F::ONE);
    while !padded.len().is_multiple_of(RATE) {
        padded.push(F::ZERO);
    }
    for block in padded.chunks(RATE) {
        state[..RATE].copy_from_slice(block);
        permute(&mut state);
    }
    squeeze(&state)
}

pub fn hash_bytes(domain: Domain, bytes: &[u8]) -> Digest {
    hash_elements(domain, &limbs_of(bytes))
}

// Two values from one absorption: the sponge takes the input once and is squeezed twice, the
// second squeeze standing one permutation past the first.
//
// **Why one absorption and not two domains.** A circuit proving both values would absorb the input
// once per derivation, and two absorptions of one secret are two places a prover may write two
// different secrets. Nothing in an arithmetic of rows ties a value at one row to a value forty
// rows on unless a column carries it, so the tie is made here instead: there is one place the
// input enters, and the second value is what the state becomes, not what a second reading of the
// input becomes.
pub fn hash_elements_twice(domain: Domain, elements: &[F]) -> (Digest, Digest) {
    let capacity = capacity_of(domain);
    let mut state = [F::ZERO; WIDTH];
    state[RATE..].copy_from_slice(&capacity);
    let mut padded = Vec::with_capacity(elements.len() + RATE);
    padded.extend_from_slice(elements);
    padded.push(F::ONE);
    while !padded.len().is_multiple_of(RATE) {
        padded.push(F::ZERO);
    }
    for block in padded.chunks(RATE) {
        state[..RATE].copy_from_slice(block);
        permute(&mut state);
    }
    let first = squeeze(&state);
    permute(&mut state);
    (first, squeeze(&state))
}

pub fn hash_bytes_twice(domain: Domain, bytes: &[u8]) -> (Digest, Digest) {
    hash_elements_twice(domain, &limbs_of(bytes))
}

// The node of a tree: two digests are eight canonical elements — exactly the rate — and the form
// is fixed, so no padding stands between them and the permutation; one node is one permutation,
// which is what the count of a circuit stands on.
pub fn node(domain: Domain, left: &Digest, right: &Digest) -> Digest {
    let capacity = capacity_of(domain);
    let mut state = [F::ZERO; WIDTH];
    state[..CAPACITY].copy_from_slice(&left.0);
    state[CAPACITY..RATE].copy_from_slice(&right.0);
    state[RATE..].copy_from_slice(&capacity);
    permute(&mut state);
    squeeze(&state)
}

#[cfg(test)]
mod tests {
    use super::*;

    // The known answer the authors of the scheme publish for width twelve: the permutation of the
    // first twelve integers. An implementation that transcribed a constant wrongly, folded a
    // matrix in another order, or raised to another power reproduces none of these twelve words.
    #[test]
    fn the_authors_known_answer_reproduces() {
        let mut state = [F::ZERO; WIDTH];
        for (at, cell) in state.iter_mut().enumerate() {
            *cell = F::from_u64_reduced(at as u64);
        }
        permute(&mut state);
        let expected: [u64; 12] = [
            0x01ea_ef96_bdf1_c0c1,
            0x1f0d_2cc5_25b2_540c,
            0x6282_c1df_e1e0_358d,
            0xe780_d721_f698_e1e6,
            0x280c_0b6f_753d_833b,
            0x1b94_2dd5_0231_56ab,
            0x43f0_df3f_cccb_8398,
            0xe8e8_1905_8548_9025,
            0x56bd_bf72_f77a_da22,
            0x7911_c32b_f9dc_d705,
            0xec46_7926_508f_be67,
            0x6a50_450d_df85_a6ed,
        ];
        for (cell, want) in state.iter().zip(expected) {
            assert_eq!(cell.as_u64(), want);
        }
    }

    #[test]
    fn a_limb_never_reaches_the_modulus() {
        let limbs = limbs_of(&[0xFFu8; 32]);
        assert_eq!(limbs.len(), 8);
        for limb in &limbs {
            assert!(limb.as_u64() < 1u64 << 32);
        }
    }

    #[test]
    fn two_domains_never_share_a_hash_of_one_input() {
        let one = hash_elements(mt_codec::domain::MT_PROOF_LEAF, &[F::ONE]);
        let two = hash_elements(mt_codec::domain::MT_PROOF_NODE, &[F::ONE]);
        assert_ne!(one, two);
    }

    #[test]
    fn inputs_of_different_lengths_never_share_a_hash() {
        let short = hash_elements(mt_codec::domain::MT_PROOF_LEAF, &[F::ZERO; 8]);
        let long = hash_elements(mt_codec::domain::MT_PROOF_LEAF, &[F::ZERO; 9]);
        assert_ne!(short, long);
    }
}
