//! Connection registration prologue (byte-exact, spec Stage 1 step 0-a):
//! RegHello{version, account_pubkey} / RegChallenge{nonce} / RegProof{sig}.

use mt_crypto::{PUBLIC_KEY_SIZE, SIGNATURE_SIZE};

use crate::challenge::{Nonce, NONCE_SIZE};
use crate::frame::FrameError;

pub const REG_HELLO_SIZE: usize = 1 + PUBLIC_KEY_SIZE; // 1953
pub const REG_VERSION: u8 = 0x01;

pub fn encode_reg_hello(account_pubkey: &[u8; PUBLIC_KEY_SIZE]) -> Vec<u8> {
    let mut buf = Vec::with_capacity(REG_HELLO_SIZE);
    buf.push(REG_VERSION);
    buf.extend_from_slice(account_pubkey);
    buf
}

pub fn decode_reg_hello(input: &[u8]) -> Result<[u8; PUBLIC_KEY_SIZE], FrameError> {
    if input.len() != REG_HELLO_SIZE {
        return Err(FrameError::Truncated);
    }
    if input[0] != REG_VERSION {
        return Err(FrameError::BadVersion(input[0]));
    }
    let mut pk = [0u8; PUBLIC_KEY_SIZE];
    pk.copy_from_slice(&input[1..]);
    Ok(pk)
}

pub fn encode_reg_challenge(nonce: &Nonce) -> Vec<u8> {
    nonce.to_vec()
}

pub fn decode_reg_challenge(input: &[u8]) -> Result<Nonce, FrameError> {
    if input.len() != NONCE_SIZE {
        return Err(FrameError::Truncated);
    }
    let mut n = [0u8; NONCE_SIZE];
    n.copy_from_slice(input);
    Ok(n)
}

pub fn encode_reg_proof(sig: &[u8; SIGNATURE_SIZE]) -> Vec<u8> {
    sig.to_vec()
}

pub fn decode_reg_proof(input: &[u8]) -> Result<[u8; SIGNATURE_SIZE], FrameError> {
    if input.len() != SIGNATURE_SIZE {
        return Err(FrameError::Truncated);
    }
    let mut s = [0u8; SIGNATURE_SIZE];
    s.copy_from_slice(input);
    Ok(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prologue_roundtrip_and_sizes() {
        let pk = [0x5A; PUBLIC_KEY_SIZE];
        let hello = encode_reg_hello(&pk);
        assert_eq!(hello.len(), 1953);
        assert_eq!(decode_reg_hello(&hello).unwrap(), pk);

        let nonce = [0x33; NONCE_SIZE];
        assert_eq!(
            decode_reg_challenge(&encode_reg_challenge(&nonce)).unwrap(),
            nonce
        );

        let sig = [0x77; SIGNATURE_SIZE];
        assert_eq!(
            decode_reg_proof(&encode_reg_proof(&sig)).unwrap()[..],
            sig[..]
        );
    }

    #[test]
    fn prologue_rejects_bad_inputs() {
        assert!(decode_reg_hello(&[0u8; 10]).is_err());
        let mut hello = encode_reg_hello(&[0x5A; PUBLIC_KEY_SIZE]);
        hello[0] = 0x02;
        assert!(decode_reg_hello(&hello).is_err());
        assert!(decode_reg_challenge(&[0u8; 15]).is_err());
        assert!(decode_reg_proof(&[0u8; 100]).is_err());
    }
}
