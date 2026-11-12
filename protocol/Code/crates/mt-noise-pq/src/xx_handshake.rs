//! Noise_PQ XX-pattern handshake — ephemeral ML-KEM-768 on both sides, identity
//! discovered during the handshake. Replaces the XK variant in `lib.rs` for
//! production libp2p plug-in use: the responder's static ML-KEM-768 public key
//! does not need to be known a priori, so the same upgrade type can serve both
//! inbound and outbound connections in libp2p's auth-upgrade slot.
//!
//! Wire format:
//!
//! - msg1 (initiator → responder), 1184 B:
//!     ke_pk_i    1184 B  — initiator ephemeral ML-KEM-768 public key
//!
//! - msg2 (responder → initiator), 7533 B:
//!     ke_pk_r    1184 B  — responder ephemeral ML-KEM-768 public key
//!     ct_i       1088 B  — encap to ke_pk_i → ss_i
//!     rs_id_pk   1952 B  — responder ML-DSA-65 identity public key
//!     sig_r      3309 B  — responder sig over transcript through msg2 ‖ ss_i
//!
//! - msg3 (initiator → responder), 6349 B:
//!     ct_r       1088 B  — encap to ke_pk_r → ss_r
//!     is_id_pk   1952 B  — initiator ML-DSA-65 identity public key
//!     sig_i      3309 B  — initiator sig over transcript through msg3 ‖ ss_i ‖ ss_r
//!
//! Transcript = msg1 || msg2_payload_through_sig || msg3_payload_through_sig
//!
//! Session derivation:
//!   master = SHA-256("mt-noise-pq-xx-v1-master" || ss_i || ss_r || transcript)
//!   sk_i_to_r = SHA-256("mt-noise-pq-xx-v1-i2r" || master)
//!   sk_r_to_i = SHA-256("mt-noise-pq-xx-v1-r2i" || master)
//!
//! Identity authentication: ML-DSA-65 signatures bind both ephemerals + remote
//! identity AND the post-decap shared secrets (ss_i into sig_r; ss_i+ss_r into
//! sig_i) into the signed input, so authentication covers the derived session key
//! identity into the transcript, so a MITM cannot forge either side without
//! its private signing key.

use crate::NoisePqError;
use mt_crypto::{
    keypair_from_seed_mlkem, mlkem_decapsulate, mlkem_encapsulate, sign, verify, MlkemCiphertext,
    MlkemPublicKey, MlkemSecretKey, PublicKey, SecretKey, Signature, MLKEM_CIPHERTEXT_SIZE,
    MLKEM_PUBLIC_KEY_SIZE, MLKEM_SEED_SIZE, PUBLIC_KEY_SIZE, SIGNATURE_SIZE,
};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use zeroize::Zeroize;

pub const XX_MSG1_SIZE: usize = MLKEM_PUBLIC_KEY_SIZE;
pub const XX_MSG2_SIZE: usize =
    MLKEM_PUBLIC_KEY_SIZE + MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE + SIGNATURE_SIZE;
pub const XX_MSG3_SIZE: usize = MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE + SIGNATURE_SIZE;

pub const XX_SESSION_KEY_SIZE: usize = 32;

const DOMAIN_MASTER: &[u8] = b"mt-noise-pq-xx-v1-master";
const DOMAIN_I2R: &[u8] = b"mt-noise-pq-xx-v1-i2r";
const DOMAIN_R2I: &[u8] = b"mt-noise-pq-xx-v1-r2i";
const SIG_DOMAIN_RESPONDER: &[u8] = b"mt-noise-pq-xx-v1-sig-r";
const SIG_DOMAIN_INITIATOR: &[u8] = b"mt-noise-pq-xx-v1-sig-i";
const TRANSCRIPT_DOMAIN: &[u8] = b"mt-noise-pq-xx-v1-transcript";

pub struct XxSession {
    pub sk_i_to_r: [u8; XX_SESSION_KEY_SIZE],
    pub sk_r_to_i: [u8; XX_SESSION_KEY_SIZE],
    pub transcript_hash: [u8; 32],
    pub remote_id_pk: PublicKey,
}

impl Drop for XxSession {
    fn drop(&mut self) {
        self.sk_i_to_r.zeroize();
        self.sk_r_to_i.zeroize();
        self.transcript_hash.zeroize();
    }
}

// Holds the 32-byte ML-KEM-768 shared secret inside handshake state.
// Wraps the raw bytes so that every Drop site of the containing struct or
// stack-frame zeroises the secret. Closing the gap that left
// InitiatorAfterMsg2.ss_i / ResponderAfterMsg2.ss_i as a plain [u8; 32].
pub struct XxSharedSecret([u8; 32]);
impl XxSharedSecret {
    pub fn from_bytes(b: [u8; 32]) -> Self {
        Self(b)
    }
    pub fn from_slice(s: &[u8]) -> Result<Self, NoisePqError> {
        if s.len() != 32 {
            return Err(NoisePqError::BadMsgSize {
                expected: 32,
                actual: s.len(),
            });
        }
        let mut b = [0u8; 32];
        b.copy_from_slice(s);
        Ok(Self(b))
    }
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}
impl Drop for XxSharedSecret {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

pub struct InitiatorAfterMsg1 {
    ke_sk_i: MlkemSecretKey,
    ke_pk_i_bytes: [u8; MLKEM_PUBLIC_KEY_SIZE],
    is_id_sk: Arc<SecretKey>,
    is_id_pk: PublicKey,
}

pub struct InitiatorAfterMsg2 {
    transcript_through_msg2: Vec<u8>,
    ke_pk_r: MlkemPublicKey,
    ss_i: XxSharedSecret,
    rs_id_pk: PublicKey,
    is_id_sk: Arc<SecretKey>,
    is_id_pk: PublicKey,
}

pub struct ResponderAfterMsg1 {
    ke_pk_i: MlkemPublicKey,
    ke_pk_i_bytes: [u8; MLKEM_PUBLIC_KEY_SIZE],
    rs_id_sk: Arc<SecretKey>,
    rs_id_pk: PublicKey,
}

pub struct ResponderAfterMsg2 {
    transcript_through_msg2: Vec<u8>,
    ke_sk_r: MlkemSecretKey,
    ss_i: XxSharedSecret,
}

pub fn initiator_send_msg1(
    is_id_sk: Arc<SecretKey>,
    is_id_pk: PublicKey,
) -> Result<(Vec<u8>, InitiatorAfterMsg1), NoisePqError> {
    let mut seed = [0u8; MLKEM_SEED_SIZE];
    getrandom::getrandom(&mut seed).map_err(|_| NoisePqError::RngFailed)?;
    let (ke_pk_i, ke_sk_i) = keypair_from_seed_mlkem(&seed)?;
    seed.zeroize();

    let mut wire = Vec::with_capacity(XX_MSG1_SIZE);
    wire.extend_from_slice(ke_pk_i.as_bytes());

    Ok((
        wire,
        InitiatorAfterMsg1 {
            ke_sk_i,
            ke_pk_i_bytes: *ke_pk_i.as_bytes(),
            is_id_sk,
            is_id_pk,
        },
    ))
}

pub fn responder_receive_msg1(
    msg1: &[u8],
    rs_id_sk: Arc<SecretKey>,
    rs_id_pk: PublicKey,
) -> Result<ResponderAfterMsg1, NoisePqError> {
    if msg1.len() != XX_MSG1_SIZE {
        return Err(NoisePqError::BadMsgSize {
            expected: XX_MSG1_SIZE,
            actual: msg1.len(),
        });
    }
    let ke_pk_i_arr: [u8; MLKEM_PUBLIC_KEY_SIZE] = msg1
        .try_into()
        .map_err(|_| NoisePqError::InvalidPublicKey)?;
    let ke_pk_i = MlkemPublicKey::from_array(ke_pk_i_arr);
    Ok(ResponderAfterMsg1 {
        ke_pk_i,
        ke_pk_i_bytes: ke_pk_i_arr,
        rs_id_sk,
        rs_id_pk,
    })
}

pub fn responder_send_msg2(
    state: ResponderAfterMsg1,
) -> Result<(Vec<u8>, ResponderAfterMsg2), NoisePqError> {
    let mut seed = [0u8; MLKEM_SEED_SIZE];
    getrandom::getrandom(&mut seed).map_err(|_| NoisePqError::RngFailed)?;
    let (ke_pk_r, ke_sk_r) = keypair_from_seed_mlkem(&seed)?;
    seed.zeroize();

    let (ct_i, ss_i) = mlkem_encapsulate(&state.ke_pk_i)?;
    let ss_i_wrapped = XxSharedSecret::from_slice(ss_i.as_bytes())?;

    let mut transcript = Vec::with_capacity(XX_MSG1_SIZE + XX_MSG2_SIZE - SIGNATURE_SIZE);
    transcript.extend_from_slice(&state.ke_pk_i_bytes);
    transcript.extend_from_slice(ke_pk_r.as_bytes());
    transcript.extend_from_slice(ct_i.as_bytes());
    transcript.extend_from_slice(state.rs_id_pk.as_bytes());

    let sig_input: [u8; 32] = Sha256::new()
        .chain_update(SIG_DOMAIN_RESPONDER)
        .chain_update(&transcript)
        .chain_update(ss_i.as_bytes())
        .finalize()
        .into();
    let sig_r = sign(&state.rs_id_sk, &sig_input)?;

    let mut wire = Vec::with_capacity(XX_MSG2_SIZE);
    wire.extend_from_slice(ke_pk_r.as_bytes());
    wire.extend_from_slice(ct_i.as_bytes());
    wire.extend_from_slice(state.rs_id_pk.as_bytes());
    wire.extend_from_slice(sig_r.as_bytes());

    transcript.extend_from_slice(sig_r.as_bytes());

    Ok((
        wire,
        ResponderAfterMsg2 {
            transcript_through_msg2: transcript,
            ke_sk_r,
            ss_i: ss_i_wrapped,
        },
    ))
}

pub fn initiator_receive_msg2(
    msg2: &[u8],
    state: InitiatorAfterMsg1,
) -> Result<InitiatorAfterMsg2, NoisePqError> {
    if msg2.len() != XX_MSG2_SIZE {
        return Err(NoisePqError::BadMsgSize {
            expected: XX_MSG2_SIZE,
            actual: msg2.len(),
        });
    }
    let (ke_pk_r_slice, rest) = msg2.split_at(MLKEM_PUBLIC_KEY_SIZE);
    let (ct_i_slice, rest) = rest.split_at(MLKEM_CIPHERTEXT_SIZE);
    let (rs_id_pk_slice, sig_r_slice) = rest.split_at(PUBLIC_KEY_SIZE);

    let ke_pk_r_arr: [u8; MLKEM_PUBLIC_KEY_SIZE] = ke_pk_r_slice
        .try_into()
        .map_err(|_| NoisePqError::InvalidPublicKey)?;
    let ke_pk_r = MlkemPublicKey::from_array(ke_pk_r_arr);
    let ct_i = MlkemCiphertext::from_slice(ct_i_slice).ok_or(NoisePqError::InvalidCiphertext)?;
    let rs_id_pk_arr: [u8; PUBLIC_KEY_SIZE] = rs_id_pk_slice
        .try_into()
        .map_err(|_| NoisePqError::InvalidPublicKey)?;
    let rs_id_pk = PublicKey::from_array(rs_id_pk_arr);
    let sig_r_arr: [u8; SIGNATURE_SIZE] =
        sig_r_slice
            .try_into()
            .map_err(|_| NoisePqError::BadMsgSize {
                expected: SIGNATURE_SIZE,
                actual: sig_r_slice.len(),
            })?;
    let sig_r = Signature::from_array(sig_r_arr);

    let ss_i = mlkem_decapsulate(&state.ke_sk_i, &ct_i)?;
    let ss_i_wrapped = XxSharedSecret::from_slice(ss_i.as_bytes())?;

    let mut transcript = Vec::with_capacity(XX_MSG1_SIZE + XX_MSG2_SIZE - SIGNATURE_SIZE);
    transcript.extend_from_slice(&state.ke_pk_i_bytes);
    transcript.extend_from_slice(ke_pk_r.as_bytes());
    transcript.extend_from_slice(ct_i.as_bytes());
    transcript.extend_from_slice(rs_id_pk.as_bytes());

    let sig_input: [u8; 32] = Sha256::new()
        .chain_update(SIG_DOMAIN_RESPONDER)
        .chain_update(&transcript)
        .chain_update(ss_i.as_bytes())
        .finalize()
        .into();
    if !verify(&rs_id_pk, &sig_input, &sig_r) {
        return Err(NoisePqError::BadResponderSignature);
    }

    transcript.extend_from_slice(sig_r.as_bytes());

    Ok(InitiatorAfterMsg2 {
        transcript_through_msg2: transcript,
        ke_pk_r,
        ss_i: ss_i_wrapped,
        rs_id_pk,
        is_id_sk: state.is_id_sk,
        is_id_pk: state.is_id_pk,
    })
}

pub fn initiator_send_msg3(
    state: InitiatorAfterMsg2,
) -> Result<(Vec<u8>, XxSession), NoisePqError> {
    let InitiatorAfterMsg2 {
        mut transcript_through_msg2,
        ke_pk_r,
        ss_i,
        rs_id_pk,
        is_id_sk,
        is_id_pk,
    } = state;

    let (ct_r, ss_r) = mlkem_encapsulate(&ke_pk_r)?;
    let ss_r_wrapped = XxSharedSecret::from_slice(ss_r.as_bytes())?;

    transcript_through_msg2.extend_from_slice(ct_r.as_bytes());
    transcript_through_msg2.extend_from_slice(is_id_pk.as_bytes());

    let sig_input: [u8; 32] = Sha256::new()
        .chain_update(SIG_DOMAIN_INITIATOR)
        .chain_update(&transcript_through_msg2)
        .chain_update(ss_i.as_bytes())
        .chain_update(ss_r_wrapped.as_bytes())
        .finalize()
        .into();
    let sig_i = sign(&is_id_sk, &sig_input)?;

    transcript_through_msg2.extend_from_slice(sig_i.as_bytes());

    let mut wire = Vec::with_capacity(XX_MSG3_SIZE);
    wire.extend_from_slice(ct_r.as_bytes());
    wire.extend_from_slice(is_id_pk.as_bytes());
    wire.extend_from_slice(sig_i.as_bytes());

    let session = derive_session(
        ss_i.as_bytes(),
        ss_r_wrapped.as_bytes(),
        &transcript_through_msg2,
        rs_id_pk,
    )?;
    Ok((wire, session))
}

pub fn responder_receive_msg3(
    msg3: &[u8],
    state: ResponderAfterMsg2,
) -> Result<XxSession, NoisePqError> {
    if msg3.len() != XX_MSG3_SIZE {
        return Err(NoisePqError::BadMsgSize {
            expected: XX_MSG3_SIZE,
            actual: msg3.len(),
        });
    }
    let (ct_r_slice, rest) = msg3.split_at(MLKEM_CIPHERTEXT_SIZE);
    let (is_id_pk_slice, sig_i_slice) = rest.split_at(PUBLIC_KEY_SIZE);

    let ct_r = MlkemCiphertext::from_slice(ct_r_slice).ok_or(NoisePqError::InvalidCiphertext)?;
    let is_id_pk_arr: [u8; PUBLIC_KEY_SIZE] = is_id_pk_slice
        .try_into()
        .map_err(|_| NoisePqError::InvalidPublicKey)?;
    let is_id_pk = PublicKey::from_array(is_id_pk_arr);
    let sig_i_arr: [u8; SIGNATURE_SIZE] =
        sig_i_slice
            .try_into()
            .map_err(|_| NoisePqError::BadMsgSize {
                expected: SIGNATURE_SIZE,
                actual: sig_i_slice.len(),
            })?;
    let sig_i = Signature::from_array(sig_i_arr);

    let ss_r = mlkem_decapsulate(&state.ke_sk_r, &ct_r)?;
    let ss_r_wrapped = XxSharedSecret::from_slice(ss_r.as_bytes())?;

    let mut transcript = state.transcript_through_msg2;
    transcript.extend_from_slice(ct_r.as_bytes());
    transcript.extend_from_slice(is_id_pk.as_bytes());

    let sig_input: [u8; 32] = Sha256::new()
        .chain_update(SIG_DOMAIN_INITIATOR)
        .chain_update(&transcript)
        .chain_update(state.ss_i.as_bytes())
        .chain_update(ss_r_wrapped.as_bytes())
        .finalize()
        .into();
    if !verify(&is_id_pk, &sig_input, &sig_i) {
        return Err(NoisePqError::BadInitiatorSignature);
    }

    transcript.extend_from_slice(sig_i.as_bytes());

    let session = derive_session(
        state.ss_i.as_bytes(),
        ss_r_wrapped.as_bytes(),
        &transcript,
        is_id_pk,
    )?;
    Ok(session)
}

fn derive_session(
    ss_i: &[u8; 32],
    ss_r: &[u8; 32],
    transcript: &[u8],
    remote_id_pk: PublicKey,
) -> Result<XxSession, NoisePqError> {
    let mut master_input = Vec::with_capacity(64 + transcript.len());
    master_input.extend_from_slice(ss_i);
    master_input.extend_from_slice(ss_r);
    master_input.extend_from_slice(transcript);
    let master: [u8; 32] = Sha256::new()
        .chain_update(DOMAIN_MASTER)
        .chain_update(&master_input)
        .finalize()
        .into();
    master_input.zeroize();

    let mut sk_i_to_r = [0u8; XX_SESSION_KEY_SIZE];
    sk_i_to_r.copy_from_slice(
        &Sha256::new()
            .chain_update(DOMAIN_I2R)
            .chain_update(master)
            .finalize(),
    );
    let mut sk_r_to_i = [0u8; XX_SESSION_KEY_SIZE];
    sk_r_to_i.copy_from_slice(
        &Sha256::new()
            .chain_update(DOMAIN_R2I)
            .chain_update(master)
            .finalize(),
    );
    let mut transcript_hash = [0u8; 32];
    transcript_hash.copy_from_slice(
        &Sha256::new()
            .chain_update(TRANSCRIPT_DOMAIN)
            .chain_update(transcript)
            .finalize(),
    );

    Ok(XxSession {
        sk_i_to_r,
        sk_r_to_i,
        transcript_hash,
        remote_id_pk,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair_from_seed, KEYPAIR_SEED_SIZE};
    use std::sync::Arc;

    fn make_id(seed_byte: u8) -> (PublicKey, SecretKey) {
        keypair_from_seed(&[seed_byte; KEYPAIR_SEED_SIZE]).unwrap()
    }

    #[test]
    fn xx_roundtrip() {
        let (rs_id_pk, rs_id_sk) = make_id(0x11);
        let (is_id_pk, is_id_sk) = make_id(0x22);

        let (msg1, init_after_msg1) =
            initiator_send_msg1(Arc::new(is_id_sk), is_id_pk.clone()).unwrap();
        assert_eq!(msg1.len(), XX_MSG1_SIZE);

        let resp_after_msg1 =
            responder_receive_msg1(&msg1, Arc::new(rs_id_sk), rs_id_pk.clone()).unwrap();
        let (msg2, resp_after_msg2) = responder_send_msg2(resp_after_msg1).unwrap();
        assert_eq!(msg2.len(), XX_MSG2_SIZE);

        let init_after_msg2 = initiator_receive_msg2(&msg2, init_after_msg1).unwrap();
        let (msg3, init_session) = initiator_send_msg3(init_after_msg2).unwrap();
        assert_eq!(msg3.len(), XX_MSG3_SIZE);

        let resp_session = responder_receive_msg3(&msg3, resp_after_msg2).unwrap();

        assert_eq!(init_session.sk_i_to_r, resp_session.sk_i_to_r);
        assert_eq!(init_session.sk_r_to_i, resp_session.sk_r_to_i);
        assert_eq!(init_session.transcript_hash, resp_session.transcript_hash);

        assert_eq!(init_session.remote_id_pk.as_bytes(), rs_id_pk.as_bytes());
        assert_eq!(resp_session.remote_id_pk.as_bytes(), is_id_pk.as_bytes());
    }

    #[test]
    fn xx_tamper_msg2_signature() {
        let (rs_id_pk, rs_id_sk) = make_id(0x11);
        let (is_id_pk, is_id_sk) = make_id(0x22);

        let (msg1, init_after_msg1) =
            initiator_send_msg1(Arc::new(is_id_sk), is_id_pk.clone()).unwrap();
        let resp_after_msg1 =
            responder_receive_msg1(&msg1, Arc::new(rs_id_sk), rs_id_pk.clone()).unwrap();
        let (mut msg2, _resp_after_msg2) = responder_send_msg2(resp_after_msg1).unwrap();

        let sig_offset = MLKEM_PUBLIC_KEY_SIZE + MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE;
        msg2[sig_offset] ^= 0x01;
        let r = initiator_receive_msg2(&msg2, init_after_msg1);
        assert_eq!(r.err(), Some(NoisePqError::BadResponderSignature));
    }

    #[test]
    fn xx_tamper_msg3_signature() {
        let (rs_id_pk, rs_id_sk) = make_id(0x11);
        let (is_id_pk, is_id_sk) = make_id(0x22);

        let (msg1, init_after_msg1) =
            initiator_send_msg1(Arc::new(is_id_sk), is_id_pk.clone()).unwrap();
        let resp_after_msg1 =
            responder_receive_msg1(&msg1, Arc::new(rs_id_sk), rs_id_pk.clone()).unwrap();
        let (msg2, resp_after_msg2) = responder_send_msg2(resp_after_msg1).unwrap();
        let init_after_msg2 = initiator_receive_msg2(&msg2, init_after_msg1).unwrap();
        let (mut msg3, _) = initiator_send_msg3(init_after_msg2).unwrap();

        let sig_offset = MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE;
        msg3[sig_offset] ^= 0x01;
        let r = responder_receive_msg3(&msg3, resp_after_msg2);
        assert_eq!(r.err(), Some(NoisePqError::BadInitiatorSignature));
    }

    #[test]
    fn xx_remote_identity_authenticated() {
        let (rs_id_pk, rs_id_sk) = make_id(0xAA);
        let (is_id_pk, is_id_sk) = make_id(0xBB);

        let (msg1, init_after_msg1) =
            initiator_send_msg1(Arc::new(is_id_sk), is_id_pk.clone()).unwrap();
        let resp_after_msg1 =
            responder_receive_msg1(&msg1, Arc::new(rs_id_sk), rs_id_pk.clone()).unwrap();
        let (msg2, resp_after_msg2) = responder_send_msg2(resp_after_msg1).unwrap();
        let init_after_msg2 = initiator_receive_msg2(&msg2, init_after_msg1).unwrap();
        let (msg3, init_session) = initiator_send_msg3(init_after_msg2).unwrap();
        let resp_session = responder_receive_msg3(&msg3, resp_after_msg2).unwrap();

        assert_eq!(init_session.remote_id_pk.as_bytes(), rs_id_pk.as_bytes());
        assert_eq!(resp_session.remote_id_pk.as_bytes(), is_id_pk.as_bytes());
    }
}
